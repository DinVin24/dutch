#!/bin/bash
# Launch Host + Client for manual Vision tests (V1-V12).
# For automated capture + cleanup use: bash .debug/run_mp_vision_test.sh
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/run_mp_vision_test.sh"
