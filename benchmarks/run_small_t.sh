#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="results"
PLOTS_DIR="plots"
export MOSTREAM_HOME="$(cd .. && pwd)"

mkdir -p "$RESULTS_DIR" "$PLOTS_DIR"

echo "=========================================="
echo " Scalability Benchmark (Small T: 1ms, 2ms)"
echo "=========================================="

echo "Setting NUM_MESSAGES to 500 in scalabilityStages.mojo..."
sed -i 's/^comptime NUM_MESSAGES: Int = [0-9]*/comptime NUM_MESSAGES: Int = 500/' scalabilityStages.mojo

echo "Setting T values to 2ms and 1ms in scalability_bench.mojo..."
# Assicura che ci siano solo 2ms e 1ms togliendo eventuali 100ms, 50ms ecc...
sed -i '/bench_size_t\[[0-9]*, 100_000_000\]/d' scalability_bench.mojo
sed -i '/bench_size_t\[[0-9]*, 50_000_000\]/d' scalability_bench.mojo
sed -i '/bench_size_t\[[0-9]*, 25_000_000\]/d' scalability_bench.mojo
sed -i '/bench_size_t\[[0-9]*, 10_000_000\]/d' scalability_bench.mojo
sed -i '/bench_size_t\[[0-9]*, 5_000_000\]/d' scalability_bench.mojo
# Riposizioniamoli se non ci sono
if ! grep -q "1_000_000" scalability_bench.mojo; then
    sed -i 's/bench_size_t\[\([0-9]*\), 2_000_000\]()/bench_size_t\[\1, 2_000_000\]()\n    bench_size_t\[\1, 1_000_000\]()/g' scalability_bench.mojo
fi

echo "--- A. Running WITHOUT Pinning ---"
sed -i 's/pipeline.setPinning(True)/pipeline.setPinning(False)/g' scalability_bench.mojo
echo "Building scalability_bench_no_pinning..."
mojo build -I .. scalability_bench.mojo -o scalability_bench_no_pinning
echo "Running scalability benchmark (No Pinning)..."
./scalability_bench_no_pinning > "$RESULTS_DIR/scalability_small_t_no_pinning.txt"

echo "--- B. Running WITH Pinning ---"
sed -i 's/pipeline.setPinning(False)/pipeline.setPinning(True)/g' scalability_bench.mojo
CORE_COUNT=$(nproc)
export MOSTREAM_PINNING=$(seq -s, 0 $((CORE_COUNT - 1)))

echo "Building scalability_bench_with_pinning..."
mojo build -I .. scalability_bench.mojo -o scalability_bench_with_pinning
echo "Running scalability benchmark (With Pinning)..."
./scalability_bench_with_pinning > "$RESULTS_DIR/scalability_small_t_with_pinning.txt"

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

echo "Done! Run './run_benchmarks.sh' later if you want to restore all properties."
