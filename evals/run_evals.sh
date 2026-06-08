#!/bin/bash
set -e

# Change directory to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Running Agent Prompt Evaluations ==="

# Set defaults
export DUTCH_LM_STUDIO_URL=${DUTCH_LM_STUDIO_URL:-"http://127.0.0.1:1234/v1"}
export DUTCH_LM_STUDIO_MODEL=${DUTCH_LM_STUDIO_MODEL:-"qwen/qwen3.5-9b"}

# Check if mock mode is requested
if [ "$1" == "--mock" ] || [ "$1" == "-m" ]; then
  echo "Using Offline Mock Provider..."
  export PROVIDER_ARGS="--providers file://$SCRIPT_DIR/mock_provider.py"
  export DUTCH_LM_STUDIO_URL="http://unused"
else
  export PROVIDER_ARGS=""
  export OPENAI_API_BASE=$DUTCH_LM_STUDIO_URL
  export OPENAI_API_KEY="lm-studio"
  echo "Using Live LLM Provider at $DUTCH_LM_STUDIO_URL (Model: $DUTCH_LM_STUDIO_MODEL)..."
  echo "Make sure LM Studio is running and the model is loaded."
fi

echo "Evaluating Chippy (Rules Assistant)..."
npx -y promptfoo@latest eval -c evals/chippy.yaml $PROVIDER_ARGS

echo "Evaluating Dutch Player Agent (Bot)..."
npx -y promptfoo@latest eval -c evals/bot.yaml $PROVIDER_ARGS

echo "=== Evaluation Run Complete ==="
