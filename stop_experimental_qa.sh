#!/bin/bash
# Kill switch for the experimental Godot QA Bot

STOP_FILE="/tmp/STOP_DUTCH_QA"

echo "Activating kill switch..."
touch "$STOP_FILE"
sleep 1
pkill -f Godot_v4.6.1-stable_linux.x86_64
rm -f "$STOP_FILE"
echo "Project Dutch: QA process terminated."
