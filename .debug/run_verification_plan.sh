#!/bin/bash
# Runs post-pull verification suite and saves logs under .debug/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-flatpak run org.godotengine.Godot}"
LOG_DIR="$ROOT/.debug"
mkdir -p "$LOG_DIR"

run() {
  local name="$1"
  shift
  echo ""
  echo "========== $name =========="
  sleep 1
  if "$@" 2>&1 | tee "$LOG_DIR/${name}.log"; then
    echo "========== $name: OK =========="
  else
    echo "========== $name: FAILED (exit $?) =========="
  fi
}

cd "$ROOT"
G=(flatpak run org.godotengine.Godot --headless --path "$ROOT")
run "qa_pipeline" "${G[@]}" -s res://qa_pipeline.gd
run "object_counter" "${G[@]}" -s res://debug_object_counter.gd
run "ec3_perfect_match" "${G[@]}" -s res://debug_ec3_perfect_match.gd
run "mp_suite" "${G[@]}" -s res://debug_mp_suite.gd
echo ""
echo "All logs in $LOG_DIR"
