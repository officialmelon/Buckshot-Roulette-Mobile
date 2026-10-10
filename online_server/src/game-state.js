import crypto from "node:crypto";

export const ITEMS = ["handcuffs", "beer", "magnifying glass", "cigarettes", "handsaw", "expired medicine", "inverter", "burner phone", "adrenaline"];
const STARTING_HEALTH = 3;

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function shuffle(values, seed) {
  const result = [...values];
  let state = Number.parseInt(seed.slice(0, 8), 16) >>> 0;
  for (let i = result.length - 1; i > 0; i--) {
    state = (1664525 * state + 1013904223) >>> 0;
    const j = state % (i + 1);
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}
function publicPlayer(player) {
  return { id: player.id, health: player.health, items: player.items, cuffed: player.cuffed };
}

export class BuckshotMatch {
  constructor(roomCode, players) {
    this.roomCode = roomCode;
    this.players = players;
    this.started = false;
    this.finished = false;
    this.turn = null;
    this.round = 0;
    this.damage = 1;
    this.sawedOff = false;
    this.sequence = [];
    this.lastEventId = 0;
    this.log = [];
    this.seed = crypto.randomBytes(16).toString("hex");
    this._resetPlayers();
  }

  _resetPlayers() {
    for (const player of this.players.values()) {
      player.health = STARTING_HEALTH;
      player.items = [];
      player.cuffed = false;
      player.knownShell = null;
      player.stolenItem = null;
    }
  }

  start() {
    if (this.players.size !== 2) throw new Error("Two players are required");
    this.started = true;
    this.finished = false;
    this.round = 1;
    this.turn = [...this.players.keys()][0];
    this._loadShells(4, 2);
    this._dealItems();
    return this.snapshotFor(null);
  }

  _loadShells(live, blank) {
    const shells = shuffle([...Array(live).fill("live"), ...Array(blank).fill("blank")], this.seed + this.round);
    this.sequence = shells;
    this.damage = 1;
    this.sawedOff = false;
    for (const player of this.players.values()) player.knownShell = null;
  }

  _dealItems() {
    for (const player of this.players.values()) {
      player.items = shuffle(ITEMS, this.seed + player.id).slice(0, 4);
      player.cuffed = false;
      player.stolenItem = null;
    }
  }

  _nextPlayer(playerId) {
    return [...this.players.keys()].find((id) => id !== playerId);
  }

  _requireTurn(playerId) {
    if (!this.started || this.finished) throw new Error("Match is not active");
    if (this.turn !== playerId) throw new Error("It is not this player's turn");
  }

  _requirePlayer(playerId) {
    const player = this.players.get(playerId);
    if (!player) throw new Error("Player is not in this match");
    return player;
  }

  _event(type, actor, payload = {}) {
    const event = { id: ++this.lastEventId, type, actor, payload };
    this.log.push(event);
    return event;
  }

  _finishIfDead() {
    const dead = [...this.players.values()].find((p) => p.health <= 0);
    if (!dead) return null;
    this.finished = true;
    const winner = this._nextPlayer(dead.id);
    return this._event("match.finished", "server", { winner, loser: dead.id });
  }

  shoot(actorId, target) {
    this._requireTurn(actorId);
    this._requirePlayer(actorId);
    if (target !== "self" && target !== "opponent") throw new Error("Invalid shooting target");
    if (!this.sequence.length) throw new Error("No shells remaining");
    const shell = this.sequence.shift();
    const victimId = target === "self" ? actorId : this._nextPlayer(actorId);
    const victim = this._requirePlayer(victimId);
    const damage = shell === "live" ? this.damage : 0;
    victim.health = Math.max(0, victim.health - damage);
    const events = [this._event("shot.resolved", actorId, { target, shell, damage, victim: victimId, remaining: this.sequence.length })];
    const finish = this._finishIfDead();
    if (finish) events.push(finish);
    if (!this.finished) {
      const keepTurn = shell === "blank" && target === "self";
      this.turn = keepTurn ? actorId : this._nextPlayer(actorId);
      events.push(this._event("turn.changed", "server", { player: this.turn }));
      if (!this.sequence.length) {
        this.round += 1;
        this._loadShells(4, 2);
        this._dealItems();
        events.push(this._event("round.started", "server", { round: this.round }));
      }
    }
    return events;
  }

  useItem(actorId, item, payload = {}) {
    this._requireTurn(actorId);
    const actor = this._requirePlayer(actorId);
    if (!ITEMS.includes(item)) throw new Error("Unknown item");
    const index = actor.items.indexOf(item);
    if (index < 0) throw new Error("Item is not in this player's inventory");
    actor.items.splice(index, 1);
    const events = [this._event("item.used", actorId, { item })];
    const opponent = this._requirePlayer(this._nextPlayer(actorId));
    switch (item) {
      case "handcuffs":
        opponent.cuffed = true;
        this.turn = actorId;
        break;
      case "beer":
        if (!this.sequence.length) throw new Error("No shell to eject");
        this.sequence.shift();
        if (!this.sequence.length) { this.round += 1; this._loadShells(4, 2); this._dealItems(); events.push(this._event("round.started", "server", { round: this.round })); }
        this.turn = actorId;
        break;
      case "magnifying glass":
        actor.knownShell = this.sequence[0] || null;
        this.turn = actorId;
        break;
      case "cigarettes":
        actor.health = Math.min(STARTING_HEALTH, actor.health + 1);
        this.turn = actorId;
        break;
      case "handsaw":
        this.sawedOff = true;
        this.damage = 2;
        this.turn = actorId;
        break;
      case "expired medicine":
        actor.health = Math.min(STARTING_HEALTH, actor.health + 2);
        this.turn = actorId;
        break;
      case "inverter":
        if (!this.sequence.length) throw new Error("No shell to invert");
        this.sequence[0] = this.sequence[0] === "live" ? "blank" : "live";
        actor.knownShell = this.sequence[0];
        this.turn = actorId;
        break;
      case "burner phone":
        actor.knownShell = this.sequence.length > 1 ? this.sequence[1] : null;
        this.turn = actorId;
        break;
      case "adrenaline": {
        const stolen = payload.item;
        if (!opponent.items.includes(stolen)) throw new Error("Opponent does not have that item");
        opponent.items.splice(opponent.items.indexOf(stolen), 1);
        actor.stolenItem = stolen;
        actor.items.push(stolen);
        events.push(this._event("item.stolen", actorId, { item: stolen }));
        this.turn = actorId;
        break;
      }
    }
    events.push(this._event("state.updated", "server", {}));
    return events;
  }

  snapshotFor(requesterId) {
    const players = {};
    for (const [id, player] of this.players) {
      const view = publicPlayer(player);
      if (id !== requesterId) view.knownShell = null;
      else view.knownShell = player.knownShell;
      players[id] = view;
    }
    return { room: this.roomCode, started: this.started, finished: this.finished, round: this.round, turn: this.turn, damage: this.damage, sawed_off: this.sawedOff, remaining_shells: this.sequence.length, players };
  }
}
