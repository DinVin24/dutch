#!/bin/bash
# Runner for the experimental Godot QA Bot (Retry)

GODOT_BIN="/home/codex/Downloads/Godot_v4.6.1-stable_linux.x86_64"
PROJECT_DIR="/home/codex/git/dutch"

echo "Launching Experimental QA Bot (Retry)..."

# Ensure binary is executable
chmod +x "$GODOT_BIN"

# Run Godot with the QA bot script
# Using --display-driver x11 since DISPLAY=:0 is available
"$GODOT_BIN" --path "$PROJECT_DIR" -s res://qa_bot.gd --rendering-driver opengl3 --windowed --screen 0 --resolution 1280x720
