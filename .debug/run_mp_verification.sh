#!/bin/bash
# Headless MP mock suite + SP regression bundle.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/.debug/mp"
mkdir -p "$LOG_DIR"
G=(flatpak run org.godotengine.Godot --headless --path "$ROOT")

echo "========== MP headless suite =========="
if "${G[@]}" -s res://debug_mp_suite.gd 2>&1 | tee "$LOG_DIR/suite_run.log"; then
  echo "========== MP suite: OK =========="
  SUITE_OK=1
else
  echo "========== MP suite: FAILED =========="
  SUITE_OK=0
fi

echo ""
echo "========== SP regression (optional) =========="
if [[ "${SKIP_SP:-0}" != "1" ]]; then
  "$ROOT/.debug/run_verification_plan.sh" || true
fi

echo ""
if [[ "$SUITE_OK" == "1" ]]; then
  echo "MP VERDICT: headless phases passed. See $LOG_DIR/suite.log"
  exit 0
else
  echo "MP VERDICT: failures — see $LOG_DIR/suite_run.log"
  exit 1
fi
