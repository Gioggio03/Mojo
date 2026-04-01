#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export MOSTREAM_HOME="$(dirname "$SCRIPT_DIR")"
PYTHON="$SCRIPT_DIR/.venv/bin/python3"

RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR/plots"

SIZE=${1:-512}
OUTPUT="$RESULTS_DIR/test_spot_${SIZE}.txt"

echo "=== Compiling test_spot ==="
mojo build -O3 -I .. test_spot.mojo -o test_spot

echo "=== Running test_spot (${SIZE}x${SIZE}, sequential only, ${DURATION:-60}s) ==="
./test_spot | tee "$OUTPUT"

echo ""
echo "=== Generating plots ==="
"$PYTHON" plot_test_spot.py

echo ""
echo "Done. Results: $OUTPUT"
echo "Plots:   $RESULTS_DIR/plots/"
