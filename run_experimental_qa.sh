#!/bin/bash
# Runner for the experimental Godot QA Bot (Retry)

GODOT_BIN="/home/codex/Downloads/Godot_v4.6.1-stable_linux.x86_64"
PROJECT_DIR="/home/codex/git/dutch"

echo "Launching Modular QA Pipeline..."

# Ensure binary is executable
chmod +x "$GODOT_BIN"

# Run Godot with the pipeline script
# You can pass 'epic3' to run only Epic 3 tests
"$GODOT_BIN" --path "$PROJECT_DIR" -s res://qa_pipeline.gd epic3 --rendering-driver opengl3 --windowed --screen 0 --resolution 1280x720
