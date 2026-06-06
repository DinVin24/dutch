#!/bin/bash
# Automated MP vision test: launch host+client, side-by-side windows, capture SS, analyze, cleanup.
# Usage: bash .debug/run_mp_vision_test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MP_DIR="$ROOT/.debug/mp"
RUN_ID="$(date +%Y%m%dT%H%M%S)"
OUT_DIR="$MP_DIR/runs/$RUN_ID"
G="flatpak run org.godotengine.Godot --path $ROOT"
ARGS="--vision-layout"
ROOM_FILE="$MP_DIR/room_code.txt"
HOST_LOG="$OUT_DIR/host.log"
CLIENT_LOG="$OUT_DIR/client.log"
HOST_PID=""
CLIENT_PID=""
REPORT="$OUT_DIR/report.md"

mkdir -p "$OUT_DIR"

log() { echo "[vision] $*" | tee -a "$OUT_DIR/orchestrator.log"; }

kill_dutch_godot() {
  # Match flatpak Godot for this project only; never leave orphan windows.
  for pid in $(pgrep -f "org.godotengine.Godot.*--path.*dutch" 2>/dev/null || true); do
    kill "$pid" 2>/dev/null || true
  done
  sleep 0.5
}

find_godot_windows() {
  xwininfo -root -tree 2>/dev/null \
    | grep 'Godot_Engine' \
    | grep 'Dutch (DEBUG)' \
    | grep -o '0x[0-9a-f]\{3,\}' \
    | head -4
}

capture_xwd() {
  local wid="$1" label="$2"
  local xwd_path="$OUT_DIR/${label}.xwd"
  if xwd -silent -id "$wid" -out "$xwd_path" 2>/dev/null; then
    log "xwd captured $label -> $xwd_path"
    python3 "$ROOT/.debug/xwd_to_png.py" "$xwd_path" "$OUT_DIR/${label}.png" 2>/dev/null \
      && log "converted $label -> $OUT_DIR/${label}.png" \
      || log "WARN: xwd->png failed for $label (xwd kept)"
  else
    log "WARN: xwd failed for $label wid=$wid"
  fi
}

snapshot_windows() {
  local tag="$1"
  local idx=0
  while IFS= read -r wid; do
    [[ -z "$wid" ]] && continue
    if [[ $idx -eq 0 ]]; then
      capture_xwd "$wid" "C1_${tag}"
    else
      capture_xwd "$wid" "C2_${tag}"
    fi
    idx=$((idx + 1))
  done < <(find_godot_windows)
  log "snapshot $tag: $(find_godot_windows | tr '\n' ' ')"
}

analyze_png_brightness() {
  python3 << PY
import glob, os
from PIL import Image

out = "$OUT_DIR"
rows = []
for pat in ["C1_*.png", "C2_*.png", "Server_*.png", "Client_*.png"]:
    for f in sorted(glob.glob(os.path.join(out, pat))):
        im = Image.open(f).convert("L")
        w, h = im.size
        patch = im.crop((w//2-50, h//2-50, w//2+50, h//2+50))
        rows.append((os.path.basename(f), sum(im.getdata())/len(im.getdata()), sum(patch.getdata())/len(patch.getdata())))
for name, full, center in rows:
    print(f"{full:6.1f} {center:6.1f} {name}")
PY
}

write_report() {
  {
    echo "# MP Vision Run $RUN_ID"
    echo ""
    echo "## Processes"
    echo "- Host PID: ${HOST_PID:-n/a}"
    echo "- Client PID: ${CLIENT_PID:-n/a}"
    echo ""
    echo "## Host log highlights"
    grep -E "CHECKPOINT|VISION_RUN|DRAW SUCCESS|Card Discarded|FSM Blocked|ERROR|SCRIPT ERROR|Auto-skipping|Ready for draw|Window " "$HOST_LOG" 2>/dev/null || echo "(none)"
    echo ""
    echo "## Client log highlights"
    grep -E "CHECKPOINT|VISION_RUN|Card Discarded|ERROR|SCRIPT ERROR|Auto-skipping|Ready for draw|Window " "$CLIENT_LOG" 2>/dev/null || echo "(none)"
    echo ""
    echo "## Brightness (full / center)"
    echo '```'
    analyze_png_brightness 2>/dev/null || echo "(no pngs)"
    echo '```'
  } > "$REPORT"
  log "Report -> $REPORT"
}

# --- main ---
log "=== MP vision test $RUN_ID ==="
kill_dutch_godot
rm -f "$ROOM_FILE"

log "Starting host..."
$G -- $ARGS --host > "$HOST_LOG" 2>&1 &
HOST_PID=$!
echo "$HOST_PID" > "$OUT_DIR/host.pid"
log "Host PID=$HOST_PID"

CODE=""
for i in $(seq 1 90); do
  if [[ -s "$ROOM_FILE" ]]; then
    CODE="$(tr -d '[:space:]' < "$ROOM_FILE")"
    [[ ${#CODE} -ge 4 ]] && break
  fi
  sleep 0.5
done
if [[ -z "$CODE" ]]; then
  log "FAIL: no room code after 45s"
  tail -20 "$HOST_LOG"
  kill "$HOST_PID" 2>/dev/null || true
  exit 1
fi
log "Room code: $CODE"

sleep 2
snapshot_windows "pre_client"

log "Starting client..."
$G -- $ARGS --client --room-code "$CODE" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!
echo "$CLIENT_PID" > "$OUT_DIR/client.pid"
log "Client PID=$CLIENT_PID"

# Wait for both to finish (VISION_RUN_COMPLETE) or timeout 90s
DEADLINE=$((SECONDS + 90))
HOST_DONE=0
CLIENT_DONE=0
while (( SECONDS < DEADLINE )); do
  grep -q "VISION_RUN_COMPLETE" "$HOST_LOG" 2>/dev/null && HOST_DONE=1
  grep -q "VISION_RUN_COMPLETE" "$CLIENT_LOG" 2>/dev/null && CLIENT_DONE=1
  if [[ $HOST_DONE -eq 1 && $CLIENT_DONE -eq 1 ]]; then
    log "Both instances reported VISION_RUN_COMPLETE"
    break
  fi
  # Capture on checkpoint lines appearing
  for cp in cp1_deal cp2_drawn cp3_discarded; do
    if grep -q "CHECKPOINT $cp" "$HOST_LOG" 2>/dev/null; then
      touch "$OUT_DIR/.seen_host_$cp"
    fi
    if grep -q "CHECKPOINT $cp" "$CLIENT_LOG" 2>/dev/null; then
      touch "$OUT_DIR/.seen_client_$cp"
    fi
  done
  if [[ -f "$OUT_DIR/.seen_host_cp2_drawn" && ! -f "$OUT_DIR/.xwd_cp2" ]]; then
    snapshot_windows "cp2"
    touch "$OUT_DIR/.xwd_cp2"
  fi
  sleep 1
done

sleep 1
snapshot_windows "final"

# Copy Godot internal PNGs from latest test_runs folder
LATEST_RUN="$(ls -td "$ROOT/debug/test_runs/"*/ 2>/dev/null | head -1 || true)"
if [[ -n "$LATEST_RUN" ]]; then
  cp -a "$LATEST_RUN"*.png "$OUT_DIR/" 2>/dev/null || true
  log "Copied Godot screenshots from $LATEST_RUN"
fi

# Cleanup processes
kill "$HOST_PID" "$CLIENT_PID" 2>/dev/null || true
sleep 1
kill_dutch_godot

write_report
log "Done. Artifacts in $OUT_DIR"
cat "$REPORT"
