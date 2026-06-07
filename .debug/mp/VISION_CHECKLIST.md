# Vision Checklist — Multiplayer (Client1 vs Client2)

Save screenshots under `.debug/mp/` with prefix `C1_` (Host) or `C2_` (Client).
Or use F12 in `debug_layout_test` mode — saves to `debug/test_runs/<timestamp>/`.

## Set A — Connect (MP-1)

| ID | Instance | Capture |
|----|----------|---------|
| V1 | Host | Lobby with Room Code visible |
| V2 | Client | Lobby joined, 2+ players in roster |
| V3 | Both | Monitor → Objects right after Deal |

## Set B — Sync draw→discard (MP-2)

| ID | Instance | Capture |
|----|----------|---------|
| V4 | Host | Pending card floating mid-turn |
| V5 | Client | Same moment (~1s): pending rank/position match |
| V6 | Client | After remote discard: no pending, discard pile updated |
| V7 | Client | HUD label ONLINE / SYNC / LAGGING / OFFLINE |

## Set C — Stress / disconnect

| ID | Instance | Capture |
|----|----------|---------|
| V8 | Host | Right after client force-quit mid-turn |
| V9 | Client | Network sim 300ms + spam clicks, Remote Scene Tree |
| V10 | Host | Profiler flame graph after 3 MP turns |

## Set D — Game Over / EC-2

| ID | Capture |
|----|---------|
| V11 | Both: Dutch → Game Over, Orphan Nodes = 0 |
| V12 | Client: Perfect Match with pending visible before activation |

## Run dual instance

```bash
chmod +x .debug/run_mp_dual.sh
.debug/run_mp_dual.sh
```

Or manually:
```bash
# Terminal 1
flatpak run org.godotengine.Godot --path . -- --host

# Terminal 2 (use code from host Output or .debug/mp/room_code.txt)
flatpak run org.godotengine.Godot --path . -- --client --room-code-file .debug/mp/room_code.txt
```

## Lag simulation (MP-4 manual)

Project → Debug → Network → Enable simulation → 300ms latency, 5% loss on Client instance.
