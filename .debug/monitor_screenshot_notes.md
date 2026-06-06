# Debug plan screenshot #3 (Godot Monitor → Objects)

## Godot on this machine
- **Found:** Flatpak `org.godotengine.Godot` **4.6.3.stable**
- **Command:** `flatpak run org.godotengine.Godot --path /home/teosimi/Projects/dutch`

## Why automated Monitor screenshot was not captured
- The **Debugger → Monitor → Objects** graph exists only in the **editor** while the game runs (F5), not in `--headless` runs.
- No screenshot CLI (`scrot`, `gnome-screenshot`, `import`) is installed on this host.
- Automating the editor Monitor panel would require interactive UI focus.

## What was run instead
```bash
# One-time import (missing chick.glb / GLB caches on first attempt)
flatpak run org.godotengine.Godot --headless --path /home/teosimi/Projects/dutch --import

# Programmatic Monitor-equivalent counters
flatpak run org.godotengine.Godot --headless --path /home/teosimi/Projects/dutch -s res://debug_object_counter.gd
```

Logs: `object_counter.log`, `object_counter_stdout.txt`, `object_counter_verbose.txt`

## Manual steps for screenshot #3
1. `flatpak run org.godotengine.Godot --path /home/teosimi/Projects/dutch` (opens editor)
2. Open **Debugger** bottom panel → **Monitor** tab → enable **Objects** (and **Object Nodes** if desired).
3. Press **F5** to run; skip initial peek; perform **first Draw → Discard**.
4. Capture screenshot when discard VFX peaks and again ~2s after discard completes.
5. Save PNG under `.debug/` as `monitor_objects_draw_discard.png`.

## Flatpak wrapper for `run_experimental_qa.sh`
```bash
export GODOT_BIN=/home/teosimi/Projects/dutch/.debug/godot_flatpak.sh
# .debug/godot_flatpak.sh: exec flatpak run org.godotengine.Godot "$@"
```
