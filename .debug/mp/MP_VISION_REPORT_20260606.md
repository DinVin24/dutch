# MP Vision Agent Report — 2026-06-06

**Task:** V1-V6 dual-window screenshot capture for MP sync verification  
**Runner:** Agent (Vision) — DISPLAY=:0, Godot 4.6.3 flatpak  
**Screenshots:** `.debug/mp/C1_*.png` (Host/Server) and `.debug/mp/C2_*.png` (Client)

---

## Environment

| Item | Value |
|------|-------|
| Display | DISPLAY=:0 (X.Org 24.1.6, accessible) |
| Screenshot tools | `xwd` available; `scrot`/`import` not installed (no sudo) |
| Godot | 4.6.3.stable.flathub, Mesa Intel UHD 620 |
| Signaling server | `wss://dutch-signaling.onrender.com` — REACHABLE via WebSocket from Godot flatpak (curl fails but Godot WebRTC works) |

---

## Dual Window Launch — Result: CONNECTED

Room code `81FC` issued by signaling server.  
Host PID=24221, Client PID=24617. Match auto-started with `seed=424242`, `num_players=2`.

Timeline:
- `15:11:41` Host ready, signaling connected
- `15:11:42` Room `81FC` created by signaling server
- `15:12:21` Client joined room `81FC` (peer_id=838315)
- `15:12:22` Host detected 2 players → `start_match.rpc(2, 424242)`
- `15:12:27` cp1_deal screenshots captured (both instances)
- `15:12:30` cp2_drawn screenshots captured (both instances)
- `15:12:32` cp3_discarded screenshots captured (both instances)

---

## Screenshots Captured

All 8 screenshots saved to `.debug/mp/` and `debug/test_runs/20260606T181227/`.

### Host (C1_ prefix — 1280x720)

| File | Checkpoint | Brightness | Visual change |
|------|-----------|-----------|---------------|
| C1_cp1_deal.png | cp1_deal (after deal) | 89.7/255 | Game board loaded |
| C1_cp2_drawn.png | cp2_drawn (host drew) | 88.1/255 | Slight darkening (pending card overlaid) |
| C1_cp3_discarded.png | cp3_discarded (host discarded) | 88.3/255 | Visual update after discard |
| C1_lobby_handshake.png | lobby_handshake | 89.5/255 | Board state |

### Client (C2_ prefix — 400x800)

| File | Checkpoint | Brightness | Visual change |
|------|-----------|-----------|---------------|
| C2_cp1_deal.png | cp1_deal | 44.8/255 | Board partially rendered |
| C2_cp2_drawn.png | cp2_drawn | 44.8/255 | IDENTICAL to cp1 — frozen |
| C2_cp3_discarded.png | cp3_discarded | 44.8/255 | IDENTICAL to cp1 — frozen |
| C2_lobby_handshake.png | lobby_handshake | 44.8/255 | IDENTICAL — frozen |

---

## V1-V6 Checklist Results

| ID | Instance | Result | Notes |
|----|----------|--------|-------|
| V1 | Host — Lobby with Room Code visible | PARTIAL | Room code `81FC` in logs; lobby screen dark (Godot dark theme), game started before handshake screenshot |
| V2 | Client — Lobby joined, 2+ players in roster | PARTIAL | Logs confirm client joined room, peer_id=838315 registered, roster populated |
| V3 | Both — Objects right after Deal | PARTIAL | C1_cp1_deal.png shows live game board; C2 frozen at initial state |
| V4 | Host — Pending card floating mid-turn | PARTIAL | C1_cp2_drawn.png shows brightness drop (pending card change); visual diff confirmed |
| V5 | Client — Same moment, pending rank/position match | FAIL | Client board frozen due to sync crash (see Bug section) |
| V6 | Client — After remote discard, pending cleared | FAIL | Client board frozen; headless suite confirms pending cleared correctly in mock sync |

---

## Bug Found: Client Sync Crash at `game_board_3d.gd:501`

### Error (from client log)
```
ERROR: Can't take value from empty array.
       [0] _on_multiplayer_sync_applied (res://game_board_3d.gd:501)
SCRIPT ERROR: Invalid access to property or key 'rank' on a base object of type 'Nil'.
              [1] _on_multiplayer_sync_applied (res://game_board_3d.gd:503)
```

### Root Cause
In `_on_multiplayer_sync_applied()`, the condition `new_discard > prev_discard` fires on the client during the initial deal sync. At that moment, `GameManager.deck_manager.discard_pile` is still empty (the sync data has not yet been pushed to the deck_manager), so `.back()` returns null.

Offending code (`game_board_3d.gd:501-503`):
```gdscript
var top_card: CardData = GameManager.deck_manager.discard_pile.back()  # line 501 — crashes if empty
var actor_idx: int = int(_last_sync_diag["cur"])
_on_card_discarded(actor_idx, top_card)  # line 503 — top_card is null → rank access fails
```

### Fix (for Executor — Agent 2)
Guard the `.back()` call and gate on a non-empty pile:
```gdscript
if new_discard > prev_discard \
        and GameManager.is_multiplayer \
        and not multiplayer.is_server() \
        and GameManager.deck_manager.discard_pile.size() > 0:
    var top_card: CardData = GameManager.deck_manager.discard_pile.back()
    if top_card != null:
        var actor_idx: int = int(_last_sync_diag["cur"])
        _on_card_discarded(actor_idx, top_card)
    else:
        _update_discard_visual()
else:
    _update_discard_visual()
```

**Impact:** Client game board freezes at deal state. All subsequent syncs (draw, discard, cp2, cp3) are rendered identically. V5 and V6 vision checks fail.

---

## Host vs Client Visual State Comparison

| Metric | Host | Client |
|--------|------|--------|
| Board rendered | YES (brightness 88-90/255) | PARTIAL (44.8/255 — darker, sync error) |
| Visual changes across checkpoints | YES (cp1→cp2→cp3 brightness shifts) | NO — all identical |
| `discard_pile` at sync | Populated correctly | Empty at time of `_on_multiplayer_sync_applied` call |
| Pending card sequence | Correct | Could not verify visually (board frozen) |
| `suite.log` headless | ALL MP HEADLESS PHASES PASSED | (same process) |

---

## Headless Fallback Results

`debug_mp_suite.gd` was run previously (suite.log confirms) and all phases passed:
- MP-1: roster mock, payload num=2 — PASS
- MP-2: pending visible after draw, pending cleared after discard, discard size=1 — PASS
- MP-3: disconnect probe documented — PASS
- MP-4: spam absorbed, FSM stable — PASS
- MP-EC-2: Perfect Match pending cleared (V12 regression) — PASS
- P-3: object count stable delta=+-101 — PASS

**VERDICT: ALL MP HEADLESS PHASES PASSED**

---

## Action Items for Executor (Agent 2)

1. **Fix sync crash** in `game_board_3d.gd:501-503` — guard `discard_pile.back()` as described above. This is the blocker for V5 and V6 visual verification.
2. After fix, re-run `run_mp_dual.sh` to capture clean C2_cp2_drawn and C2_cp3_discarded screenshots.
3. Optional: add a `_last_sync_diag` guard for initial sync (prev_discard=0, new_discard=0 at start of deal).

