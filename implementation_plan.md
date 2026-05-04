# Implementation Plan: Multiplayer Architecture & Lobby

## Goal
Implement a robust multiplayer system for the Dutch card game using Godot 4's `ENetMultiplayerPeer`. The system will allow players to host a server, join via code (IP-based or LAN discovery), configure match settings, and play the game with synchronized FSM states.

## User Review Required

> [!WARNING]
> Multiplayer introduces a paradigm shift. Currently, `GameManager` assumes Player 0 is local and Players 1-3 are bots. We need to decouple this so any player ID can be a remote human player, a local human player, or a bot.

> [!IMPORTANT]
> The "Code" to connect: Without a dedicated matchmaking server, connecting via a "Code" usually means entering the Host's IP address. We can format the IP as a Base64 string or simple alphanumeric code to make it look like a "Room Code". Is this acceptable, or will we strictly play on LAN (where we can use UDP broadcast to auto-discover hosts)?

## Proposed Changes

---

### UI & Flow

#### [NEW] `lobby.tscn` / `lobby.gd`
- **Username Selection**: Input field for the player's name.
- **Host / Join Panel**: Buttons to Host a server or Join via Code.
- **Player List**: Displays connected players and their ready status.
- **Match Options (Host Only)**:
  - Toggle: Abilities Enabled / Disabled (Infinite Money)
  - Slider/Buttons: Starting Beers (e.g., 1 to 5)
  - Toggle: Cards Visibility (Normal / All Up / All Down)
- **Start Match Button**: Only visible to the Host when all players are connected.

#### [MODIFY] `main_menu.gd`
- Add a "Multiplayer" button that transitions to `lobby.tscn`.

---

### Networking Layer

#### [NEW] `network_manager.gd` (Autoload)
- Manages `ENetMultiplayerPeer`.
- Handles `peer_connected`, `peer_disconnected`, `server_disconnected` signals.
- Stores networked players' info (ID, Username).
- Broadcasts chat messages or system messages.
- Exposes methods to `Host` and `Join`.
- Handles RPCs for transferring match settings from Host to Clients before starting.

---

### Game Logic & FSM Adaptation

#### [MODIFY] `game_manager.gd`
- Needs to support Remote players. Currently, it initializes `bot_memory` for everyone except index 0.
- `initialize_game()` must be updated to accept player data from `NetworkManager`.
- Add `@rpc` methods for state synchronization. Since the game relies on a strict FSM, the easiest architectural pattern is **Host Authority**:
  - The Host runs the FSM and determines valid transitions.
  - Clients send input via `@rpc("any_peer", "call_local") func request_action(action_type, args)`.
  - Host validates the action and, if valid, executes it and broadcasts the new state/visuals via `@rpc("authority", "call_local") func sync_state(new_state)`.

#### [MODIFY] `game_board_3d.gd`
- Refactor the input handlers (clicking decks, cards, buttons) to route through `NetworkManager` or `GameManager` RPCs instead of directly calling local functions.
- E.g., `on_deck_clicked()` -> `GameManager.rpc_id(1, "request_draw_card")`.

## Verification Plan

### Automated Tests
- Test connection failure edge cases (invalid code).
- Test state synchronization by running two instances locally (using `Debug > Run Multiple Instances` in Godot).

### Manual Verification
- Start Host, check if lobby settings are synchronized to the connected client.
- Start match, verify both screens load `game_board_3d.tscn`.
- Ensure Player 1 (Host) can draw, and Player 2 (Client) sees the card draw animation and state change.
