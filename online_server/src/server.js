import http from "node:http";
import crypto from "node:crypto";
import dotenv from "dotenv";
import { WebSocketServer } from "ws";
import { AccessToken } from "livekit-server-sdk";
import { BuckshotMatch } from "./game-state.js";

dotenv.config();

const PORT = Number(process.env.PORT || 8080);
const LIVEKIT_URL = process.env.LIVEKIT_URL || "wss://qrm-63tzw7ds.livekit.cloud";
const rooms = new Map();
const clients = new Map();
const matchmaking = [];

const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function makeCode() {
  let code = "";
  do {
    code = Array.from({ length: 6 }, () => alphabet[crypto.randomInt(alphabet.length)]).join("");
  } while (rooms.has(code));
  return code;
}
function makePlayerId() {
  return crypto.randomUUID();
}
function send(ws, type, payload = {}) {
  if (ws.readyState === 1) ws.send(JSON.stringify({ v: 1, type, payload }));
}
function error(ws, message) { send(ws, "error", { message }); }
function roomOf(client) { return client.roomCode ? rooms.get(client.roomCode) : null; }
function opponent(room, playerId) {
  return [...room.players.values()].find((p) => p.playerId !== playerId) || null;
}
function leaveRoom(client) {
  const room = roomOf(client);
  if (!room) return;
  room.players.delete(client.playerId);
  client.roomCode = "";
  for (const other of room.players.values()) send(other.ws, "room.opponent_left", {});
  if (room.players.size === 0) rooms.delete(room.code);
}
function joinRoom(client, code) {
  const room = rooms.get(code);
  if (!room) return error(client.ws, "Room not found");
  if (room.players.size >= 2 && !room.players.has(client.playerId)) return error(client.ws, "Room is full");
  leaveRoom(client);
  client.roomCode = code;
  room.players.set(client.playerId, client);
  send(client.ws, "room.joined", { code, player_id: client.playerId, players: room.players.size });
  const other = opponent(room, client.playerId);
  if (other) {
    send(client.ws, "room.opponent_joined", { player_id: other.id });
    send(other.ws, "room.opponent_joined", { player_id: client.playerId });
    if (!room.match) {
      room.match = new BuckshotMatch(room.code, room.players);
      room.match.start();
    }
    broadcastState(room);
  }
}
function broadcastState(room) {
  if (!room.match) return;
  for (const player of room.players.values()) send(player.ws, "game.state", room.match.snapshotFor(player.playerId));
}
function broadcastEvents(room, events) {
  if (!room.match) return;
  for (const player of room.players.values()) {
    for (const event of events) send(player.ws, "game.event", event);
    send(player.ws, "game.state", room.match.snapshotFor(player.playerId));
  }
}
function matchmake(client) {
  if (!matchmaking.includes(client)) matchmaking.push(client);
  send(client.ws, "matchmaking.started", {});
  while (matchmaking.length >= 2) {
    const a = matchmaking.shift();
    const b = matchmaking.shift();
    if (!a || !b || a.ws.readyState !== 1 || b.ws.readyState !== 1) continue;
    const code = makeCode();
    const room = { code, players: new Map(), seed: crypto.randomBytes(16).toString("hex"), match: null };
    rooms.set(code, room);
    joinRoom(a, code);
    joinRoom(b, code);
    send(a.ws, "matchmaking.matched", { code });
    send(b.ws, "matchmaking.matched", { code });
  }
}
async function issueVoiceToken(client) {
  const room = roomOf(client);
  if (!room) return error(client.ws, "Join a room first");
  if (!process.env.LIVEKIT_API_KEY || !process.env.LIVEKIT_API_SECRET) return error(client.ws, "Voice service is not configured on the server");
  const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, { identity: client.playerId, ttl: "10m" });
  token.addGrant({ roomJoin: true, room: room.code, canPublish: true, canSubscribe: true });
  send(client.ws, "voice.token", { url: LIVEKIT_URL, token: await token.toJwt(), room: room.code });
}
function handleMessage(client, raw) {
  let message;
  try { message = JSON.parse(raw); } catch { return error(client.ws, "Invalid JSON"); }
  const type = String(message.type || "");
  const payload = message.payload || {};
  if (type === "room.create") {
    leaveRoom(client);
    const code = makeCode();
    rooms.set(code, { code, players: new Map(), seed: crypto.randomBytes(16).toString("hex"), match: null });
    joinRoom(client, code);
    send(client.ws, "room.created", { code, player_id: client.playerId });
    return;
  }
  if (type === "room.join") return joinRoom(client, String(payload.code || "").toUpperCase());
  if (type === "room.leave") { leaveRoom(client); return send(client.ws, "room.left", {}); }
  if (type === "matchmaking.enqueue") return matchmake(client);
  if (type === "matchmaking.cancel") {
    const index = matchmaking.indexOf(client);
    if (index >= 0) matchmaking.splice(index, 1);
    return send(client.ws, "matchmaking.cancelled", {});
  }
  if (type === "voice.token") return issueVoiceToken(client);
  if (type === "game.start") {
    const room = roomOf(client);
    if (!room || room.players.size !== 2) return error(client.ws, "Two players are required");
    if (!room.match) room.match = new BuckshotMatch(room.code, room.players);
    try { room.match.start(); broadcastState(room); } catch (e) { error(client.ws, e.message); }
    return;
  }
  if (type === "game.action") {
    const room = roomOf(client);
    if (!room) return error(client.ws, "Join a room first");
    if (!room.match) return error(client.ws, "Match has not started");
    try {
      let events;
      if (payload.action === "shoot") events = room.match.shoot(client.playerId, payload.target);
      else if (payload.action === "use_item") events = room.match.useItem(client.playerId, payload.item, payload);
      else throw new Error("Unknown game action");
      broadcastEvents(room, events);
    } catch (e) { error(client.ws, e.message); }
    return;
  }
  error(client.ws, "Unknown command");
}

const httpServer = http.createServer((_req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ ok: true, service: "buckshot-online", rooms: rooms.size }));
});
const wss = new WebSocketServer({ server: httpServer });
wss.on("connection", (ws) => {
  const client = { ws, playerId: makePlayerId(), roomCode: "" };
  clients.set(client.playerId, client);
  send(ws, "hello", { player_id: client.playerId });
  ws.on("message", (data) => handleMessage(client, data.toString()));
  ws.on("close", () => { const index = matchmaking.indexOf(client); if (index >= 0) matchmaking.splice(index, 1); leaveRoom(client); clients.delete(client.playerId); });
});
httpServer.listen(PORT, "0.0.0.0", () => console.log(`Buckshot online server listening on ${PORT}`));
