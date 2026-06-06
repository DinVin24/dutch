#!/bin/bash
# Launch Host + Client for manual Vision tests (V1-V12).
# Host writes room code to .debug/mp/room_code.txt; client reads it after a short delay.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MP_DIR="$ROOT/.debug/mp"
mkdir -p "$MP_DIR"
G="flatpak run org.godotengine.Godot --path $ROOT"

ROOM_FILE="$MP_DIR/room_code.txt"
rm -f "$ROOM_FILE"

echo "Starting MP Host (writes room code to $ROOM_FILE)..."
$G -- --host &
HOST_PID=$!

echo "Waiting 8s for host room code..."
sleep 8

if [[ ! -f "$ROOM_FILE" ]]; then
  echo "WARN: room_code.txt not found yet — check host Output for room code"
  CODE="TEST"
else
  CODE="$(cat "$ROOM_FILE")"
  echo "Room code: $CODE"
fi

echo "Starting MP Client..."
$G -- --client --room-code "$CODE" &
CLIENT_PID=$!

echo ""
echo "Host PID=$HOST_PID Client PID=$CLIENT_PID"
echo "Manual checklist: .debug/mp/VISION_CHECKLIST.md"
echo "Press F12 in either window for synced screenshots -> debug/test_runs/"
echo "Kill with: kill $HOST_PID $CLIENT_PID"

wait $HOST_PID $CLIENT_PID 2>/dev/null || true
