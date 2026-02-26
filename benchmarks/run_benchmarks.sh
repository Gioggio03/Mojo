#!/usr/bin/env bash
# run_benchmarks.sh — Builds and runs all benchmarks, then generates plots.
# Usage: cd benchmarks && ./run_benchmarks.sh
set -euo pipefail

QUEUES=("MPMC_padding_optional_v2" "MPMC" "MPMC_naif" "MPMC_padding" "MPMC_padding_optional")
RESULTS_DIR="results"
PLOTS_DIR="Plots"
COMMUNICATOR="../pipeline/communicator.mojo"

# The Python interpreter: use venv if available, else python3
if [ -f .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    PYTHON=python3
fi

mkdir -p "$RESULTS_DIR" "$PLOTS_DIR"

# ─── Helper: set the active queue in communicator.mojo ─────────────
set_queue() {
    local target="$1"
    # Comment all queue imports, then uncomment the target
    sed -i 's/^from pipeline\.\(MPMC\)/# from pipeline.\1/' "$COMMUNICATOR"
    sed -i "s|^# from pipeline\.${target} import|from pipeline.${target} import|" "$COMMUNICATOR"
}

# ─── 1. Scalability benchmark (V2 only) ───────────────────────────
echo "=========================================="
echo " 1/3  Scalability Benchmark (V2 only)"
echo "=========================================="
set_queue "MPMC_padding_optional_v2"
echo "Building scalability_bench.mojo..."
mojo build -I .. scalability_bench.mojo -o scalability_bench
echo "Running scalability benchmark..."
./scalability_bench > "$RESULTS_DIR/scalability_results.txt"
echo "Done. Results in $RESULTS_DIR/scalability_results.txt"

# ─── 2. Zero-computation benchmark (all queues) ───────────────────
echo ""
echo "=========================================="
echo " 2/3  Zero-Computation Benchmark (all queues)"
echo "=========================================="
> "$RESULTS_DIR/benchmark_results.txt"  # clear file

for queue in "${QUEUES[@]}"; do
    echo ""
    echo "--- Queue: $queue ---"
    set_queue "$queue"
    echo "  Building benchmark_pipe.mojo..."
    mojo build -I .. benchmark_pipe.mojo -o benchmark_pipe
    echo "  Running benchmark..."
    # Inject a parseable queue header into the results file
    echo "" >> "$RESULTS_DIR/benchmark_results.txt"
    echo "  Queue: $queue" >> "$RESULTS_DIR/benchmark_results.txt"
    ./benchmark_pipe >> "$RESULTS_DIR/benchmark_results.txt" 2>> "$RESULTS_DIR/errors.log"
    echo "  Done."
done

# Restore Communicator to V2
set_queue "MPMC_padding_optional_v2"
echo ""
echo "Restored Communicator to MPMC_padding_optional_v2"

# ─── 3. Generate plots ────────────────────────────────────────────
echo ""
echo "=========================================="
echo " 3/3  Generating plots"
echo "=========================================="
$PYTHON generate_plots.py

echo ""
echo "All done! Results in $RESULTS_DIR/, plots in $PLOTS_DIR/"
