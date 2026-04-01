#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export MOSTREAM_HOME="$(dirname "$SCRIPT_DIR")"
PYTHON="$SCRIPT_DIR/.venv/bin/python3"

echo "=== Compiling ==="
mojo build -O3 -I .. bottleneck_tuned_benchmark.mojo -o bottleneck_tuned_benchmark

echo "=== Running ==="
OUTPUT=$(./bottleneck_tuned_benchmark)
echo "$OUTPUT"

echo "$OUTPUT" | "$PYTHON" _parse_tuning.py
