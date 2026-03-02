#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="results"
PLOTS_DIR="plots"
export MOSTREAM_HOME="$(cd .. && pwd)"

mkdir -p "$RESULTS_DIR" "$PLOTS_DIR"

echo "=========================================="
echo " Scalability Benchmark (Small T: 2ms, 1ms)"
echo "=========================================="

echo "Setting NUM_MESSAGES to 500 in scalabilityStages.mojo..."
sed -i 's/^comptime NUM_MESSAGES: Int = [0-9]*/comptime NUM_MESSAGES: Int = 500/' scalabilityStages.mojo

echo "--- A. Running WITHOUT Pinning ---"
sed -i 's/pipeline.setPinning(True)/pipeline.setPinning(False)/g' scalability_bench_small_t.mojo
echo "Building scalability_bench_small_t (No Pinning)..."
mojo build -O3 -I .. scalability_bench_small_t.mojo -o scalability_bench_small_t_no_pinning
echo "Running scalability benchmark (No Pinning)..."
./scalability_bench_small_t_no_pinning > "$RESULTS_DIR/scalability_small_t_no_pinning.txt"

echo "--- B. Running WITH Pinning ---"
sed -i 's/pipeline.setPinning(False)/pipeline.setPinning(True)/g' scalability_bench_small_t.mojo
CORE_COUNT=$(nproc)
export MOSTREAM_PINNING=$(seq -s, 0 $((CORE_COUNT - 1)))

echo "Building scalability_bench_small_t (With Pinning)..."
mojo build -O3 -I .. scalability_bench_small_t.mojo -o scalability_bench_small_t_with_pinning
echo "Running scalability benchmark (With Pinning)..."
./scalability_bench_small_t_with_pinning > "$RESULTS_DIR/scalability_small_t_with_pinning.txt"

echo "=========================================="
echo " Generating plots..."
echo "=========================================="
if [ -f .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    PYTHON=python3
fi
$PYTHON generate_plots_small_t.py

echo "Cleaning up message count..."
sed -i 's/^comptime NUM_MESSAGES: Int = [0-9]*/comptime NUM_MESSAGES: Int = 50/' scalabilityStages.mojo

echo "Done! Results in $RESULTS_DIR/"
