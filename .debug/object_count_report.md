# First Draw → Discard object counts (headless diagnostic)

**Date:** 2026-06-06  
**Godot:** 4.6.3 (Flatpak)  
**Script:** `res://debug_object_counter.gd` (loads `game_board_3d.tscn`, skips peek, one draw + discard)

## Performance monitor samples (successful run after `--import`)

| Phase | OBJECT_COUNT | OBJECT_NODE_COUNT | board CPUParticles3D |
|-------|-------------:|------------------:|---------------------:|
| Baseline (after peek) | 2478 | 487 | 21 |
| Immediately after draw | 2528 (+50) | 499 (+12) | 23 (+2) |
| ~5 frames after draw | 2528 | 499 | 23 |
| During draw VFX (~0.15s) | 2518 | 500 | 23 |
| Immediately after discard | 2567 (+89 vs baseline) | 504 (+17) | 24 (+3) |
| Mid discard tween | 2551–2560 | 503–504 | 24–25 |
| After 2.5s settle | 2472 (−6 vs baseline) | 496 (+9) | 22 (+1) |
| After 6.0s settle (extra run) | 2472 | 496 | 22 (+1) |

## Interpretation
- **OBJECT_COUNT (Monitor “Objects”):** clear **spike during draw/discard**, then **returns below baseline** after ~2.5s — consistent with **temporary VFX/allocation**, not a runaway Object leak for this action.
- **OBJECT_NODE_COUNT:** remains **+9 vs baseline** after settle — likely **persistent nodes** from the discard side effects (money popup `Label3D`, beer penalty animation / UI, FSM UI refresh), not necessarily `spawn_particles`.
- **CPUParticles3D on board:** **+1 vs baseline** even after 6s — one spawned VFX node may not have freed; draw adds `default`, discard adds `card_trail`, beer penalty adds up to **3** beer particle systems (lifetimes up to 1.0s).

## `spawn_particles` cleanup (game_board_3d.gd ~3321)
- Creates `CPUParticles3D`, configures one-shot burst, sets `emitting = true`.
- Schedules `get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)`.
- **Expected:** transient spike, particles removed after lifetime.
- **Observed:** mostly recovers; **+1 particle child** on board after long settle suggests occasional leftover (worth Monitor screenshot + longer match to confirm).

## Exit leaks (verbose run)
- `AudioStreamMP3` / playback for `main_menu.mp3` (GameManager music) — **unrelated to draw/discard VFX**.
- Not treated as confirmation of a `spawn_particles` Object leak.

## Code fix
- **Not applied:** OBJECT_COUNT recovers; remaining +1 CPUParticles3D / +9 nodes may be beer discard UX. Recommend manual Monitor screenshot before changing production VFX code.
