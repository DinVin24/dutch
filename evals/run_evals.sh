#!/bin/bash

# Change directory to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Running Agent Prompt Evaluations ==="

# Set defaults
export DUTCH_LM_STUDIO_URL=${DUTCH_LM_STUDIO_URL:-"http://127.0.0.1:1234/v1"}
export DUTCH_LM_STUDIO_MODEL=${DUTCH_LM_STUDIO_MODEL:-"qwen/qwen3.5-9b"}
export REQUEST_TIMEOUT_MS=300000
export PROMPTFOO_EVAL_TIMEOUT_MS=300000


# Check if mock mode is requested
if [ "$1" == "--mock" ] || [ "$1" == "-m" ]; then
  echo "Using Offline Mock Provider..."
  export PROVIDER_ARGS="--providers file://$SCRIPT_DIR/mock_provider.py"
  export DUTCH_LM_STUDIO_URL="http://unused"
  shift
else
  export PROVIDER_ARGS=""
  export OPENAI_API_BASE=$DUTCH_LM_STUDIO_URL
  export OPENAI_API_KEY="lm-studio"
  echo "Using Live LLM Provider at $DUTCH_LM_STUDIO_URL (Model: $DUTCH_LM_STUDIO_MODEL)..."
  echo "Make sure LM Studio is running and the model is loaded."
  if [ "$1" == "--live" ] || [ "$1" == "-l" ]; then
    shift
  fi
fi

# Capture any remaining arguments (e.g. -n 2 or --filter-sample 2)
EXTRA_ARGS="$@"

echo "Evaluating Chippy (Rules Assistant)..."
npx -y promptfoo@latest eval -c evals/chippy.yaml $PROVIDER_ARGS -j 1 $EXTRA_ARGS
CHIPPY_EXIT=$?

echo "Evaluating Dutch Player Agent (Bot)..."
npx -y promptfoo@latest eval -c evals/bot.yaml $PROVIDER_ARGS -j 1 $EXTRA_ARGS
BOT_EXIT=$?

echo "=== Evaluation Run Complete ==="

# Exit with error if either failed
if [ $CHIPPY_EXIT -ne 0 ] || [ $BOT_EXIT -ne 0 ]; then
  exit 100
fi
