#!/bin/bash
# Runner for the experimental Godot QA Bot (Retry)

GODOT_BIN="/home/codex/Downloads/Godot_v4.6.1-stable_linux.x86_64"
PROJECT_DIR="/home/codex/git/dutch"

# OS Check (Linux Only)
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "ERROR: Automated QA Pipeline is currently only supported on Linux."
    exit 1
fi

echo "Launching Modular QA Pipeline..."

# Ensure binary is executable
chmod +x "$GODOT_BIN"

# Run Godot with the pipeline script in HEADLESS mode for pure logic verification
"$GODOT_BIN" --headless --path "$PROJECT_DIR" -s res://qa_pipeline.gd epic3
