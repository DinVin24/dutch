#!/bin/bash
# Runner for the experimental Godot QA Bot (Retry)

GODOT_BIN="/home/codex/Downloads/Godot_v4.6.1-stable_linux.x86_64"
PROJECT_DIR="/home/codex/git/dutch"

echo "Launching Exhaustive FSM Verifier..."

# Ensure binary is executable
chmod +x "$GODOT_BIN"

# Run Godot with the verification script
"$GODOT_BIN" --path "$PROJECT_DIR" -s res://verify_fsm.gd --rendering-driver opengl3 --windowed --screen 0 --resolution 1280x720
