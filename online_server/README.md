# Buckshot Online Foundation

This server is the first online milestone for the IPA-derived target. The GitHub source tree is reference-only and is not modified.

## Implemented

- Private six-character room codes.
- Join by code.
- Quick matchmaking queue.
- Two-player room presence.
- Reconnect-safe player identity per connection foundation.
- Game event relay boundary.
- LiveKit token endpoint over WebSocket, with secrets kept in server environment variables.

## Run

```bash
cp .env.example .env
# Fill LIVEKIT_API_KEY and LIVEKIT_API_SECRET on the server only.
npm install
npm start
```

The Godot client must be configured with the deployed `wss://...` server URL. Do not place LiveKit API secrets in the PCK or IPA.

## Next milestones

1. Authoritative Buckshot game state and turn validation.
2. UI wiring for Quick Match, Create Room, Join Code, Invite/Share.
3. Native LiveKit iOS plugin or Godot iOS extension for microphone/WebRTC.
4. iOS microphone usage description and signed export on macOS.
