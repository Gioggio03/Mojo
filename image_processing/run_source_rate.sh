#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export MOSTREAM_HOME="$(dirname "$SCRIPT_DIR")"
PYTHON="$SCRIPT_DIR/.venv/bin/python3"

RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR/plots"

SIZE=${1:-512}
OUTPUT="$RESULTS_DIR/source_rate_${SIZE}.txt"

echo "=== Running source_rate_benchmark (${SIZE}x${SIZE}) ==="
mojo -I .. source_rate_benchmark.mojo | tee "$OUTPUT"

echo ""
echo "=== Generating plots ==="
"$PYTHON" plot_source_rate.py

echo ""
echo "Done. Results: $OUTPUT"
echo "Plots:   $RESULTS_DIR/plots/"
