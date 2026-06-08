#!/bin/bash
# Runner for the experimental Godot QA Bot (Retry)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
GODOT_BIN="${GODOT_BIN:-}"

# OS Check (Linux Only)
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "ERROR: Automated QA Pipeline is currently only supported on Linux."
    exit 1
fi

if [[ -z "$GODOT_BIN" || ! -f "$GODOT_BIN" ]]; then
    echo "ERROR: Set GODOT_BIN to your Godot 4.x Linux binary (e.g. export GODOT_BIN=/path/to/Godot_v4.6.x-stable_linux.x86_64)"
    exit 1
fi

echo "Launching Modular QA Pipeline..."

# Ensure binary is executable
chmod +x "$GODOT_BIN"

# Build class cache for Godot 4 (required in CI environments so it recognizes class_name)
echo "Building class cache..."
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --editor --quit || true

# Run Godot with the pipeline script in HEADLESS mode for pure logic verification
"$GODOT_BIN" --headless --path "$PROJECT_DIR" -s res://qa_pipeline.gd epic3
