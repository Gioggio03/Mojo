#!/usr/bin/env bash
# run_benchmarks.sh — Builds and runs all benchmarks, then generates plots.
# Usage: cd benchmarks && ./run_benchmarks.sh
set -euo pipefail

QUEUES=("MPMC_padding_optional_v2" "MPMC" "MPMC_naif" "MPMC_padding" "MPMC_padding_optional")
RESULTS_DIR="results"
PLOTS_DIR="plots"
COMMUNICATOR="../MoStream/communicator.mojo"

# ─── Detect Core Count and Set Pinning ──────────────────────────────
CORE_COUNT=$(nproc)
echo "Detected $CORE_COUNT cores."
PINNING_LIST=$(seq -s, 0 $((CORE_COUNT - 1)))
export MOSTREAM_PINNING="$PINNING_LIST"
echo "Setting MOSTREAM_PINNING=$MOSTREAM_PINNING"

# ─── Environment Setup ─────────────────────────────────────────────
if [ -f .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    PYTHON=python3
fi
export MOSTREAM_HOME="$(cd .. && pwd)"

mkdir -p "$RESULTS_DIR" "$PLOTS_DIR"

# ─── Helper: set the active queue in communicator.mojo ─────────────
set_queue() {
    local target="$1"
    echo "  Switching to $target..."
    
    # 1. Comment all queue imports, then uncomment the target
    sed -i 's/^from MoStream\.\(MPMC\)/# from MoStream.\1/' "$COMMUNICATOR"
    sed -i "s|^# from MoStream\.${target} import|from MoStream.${target} import|" "$COMMUNICATOR"

    # 2. Handle push method patching
    # Use markers at column 0 for stability. 
    # Patch lines following the marker while preserving indentation.
    if [ "$target" == "MPMC_padding_optional_v2" ]; then
        # Activate PUSH_V2: uncomment lines starting with 4 spaces + '#'
        sed -i '/### \[PUSH_V2\]/,+2 s/^    # /    /' "$COMMUNICATOR"
        # Deactivate PUSH_UNIVERSAL: comment lines starting with 4 spaces (if not already commented)
        sed -i '/### \[PUSH_UNIVERSAL\]/,+3 s/^    \([^#]\)/    # \1/' "$COMMUNICATOR"
    else
        # Deactivate PUSH_V2
        sed -i '/### \[PUSH_V2\]/,+2 s/^    \([^#]\)/    # \1/' "$COMMUNICATOR"
        # Activate PUSH_UNIVERSAL
        sed -i '/### \[PUSH_UNIVERSAL\]/,+3 s/^    # /    /' "$COMMUNICATOR"
    fi
    
    # Global cleanup to ensure no double comments like '# # '
    sed -i 's/# # /# /g' "$COMMUNICATOR"
}

# ─── 1. Scalability benchmark (V2 only) ───────────────────────────
# ─── 1. Scalability benchmark (NO PINNING) ───────────────────────────
echo "=========================================="
echo " 1/5  Scalability Benchmark (No Pinning)"
echo "=========================================="
set_queue "MPMC_padding_optional_v2"

echo "Setting NUM_MESSAGES to 50 for regular benchmark..."
sed -i 's/^comptime NUM_MESSAGES: Int = [0-9]*/comptime NUM_MESSAGES: Int = 50/' scalabilityStages.mojo

echo "Setting T values to 100ms - 5ms..."
sed -i 's/bench_size_t\[\([0-9]*\), 2_000_000\]()/bench_size_t\[\1, 100_000_000\]()\n    bench_size_t\[\1, 50_000_000\]()\n    bench_size_t\[\1, 25_000_000\]()\n    bench_size_t\[\1, 10_000_000\]()\n    bench_size_t\[\1, 5_000_000\]()/g' scalability_bench.mojo
sed -i '/bench_size_t\[[0-9]*, 1_000_000\]()/d' scalability_bench.mojo

echo "--- A. Running WITHOUT Pinning ---"
sed -i 's/pipeline.setPinning(True)/pipeline.setPinning(False)/g' scalability_bench.mojo
echo "Building scalability_bench_no_pinning..."
mojo build -I .. scalability_bench.mojo -o scalability_bench_no_pinning
echo "Running scalability benchmark (No Pinning)..."
./scalability_bench_no_pinning > "$RESULTS_DIR/scalability_results_no_pinning.txt"
echo "Done."

# ─── 2. Scalability benchmark (WITH PINNING) ───────────────────────────
echo ""
echo "=========================================="
echo " 2/5  Scalability Benchmark (With Pinning)"
echo "=========================================="
echo "Restoring Pinning to True in scalabilityStages..."
sed -i 's/pipeline.setPinning(False)/pipeline.setPinning(True)/g' scalability_bench.mojo
echo "Building scalability_bench_with_pinning..."
mojo build -I .. scalability_bench.mojo -o scalability_bench_with_pinning
echo "Running scalability benchmark (With Pinning)..."
./scalability_bench_with_pinning > "$RESULTS_DIR/scalability_results.txt"
echo "Done."

# ─── 3. Zero-computation benchmark (NO PINNING) ───────────────────
echo ""
echo "=========================================="
echo " 3/5  Zero-Computation Benchmark (No Pinning)"
echo "=========================================="
> "$RESULTS_DIR/benchmark_results_no_pinning.txt"  # clear file

for queue in "${QUEUES[@]}"; do
    echo ""
    echo "--- Queue: $queue ---"
    set_queue "$queue"
    
    # Disable pinning in benchmark pipe as well
    sed -i 's/pipeline.setPinning(True)/pipeline.setPinning(False)/g' benchmark_pipe.mojo

    echo "  Building benchmark_pipe_no_pinning..."
    mojo build -I .. benchmark_pipe.mojo -o benchmark_pipe_no_pinning
    echo "  Running benchmark..."
    echo "" >> "$RESULTS_DIR/benchmark_results_no_pinning.txt"
    echo "  Queue: $queue" >> "$RESULTS_DIR/benchmark_results_no_pinning.txt"
    ./benchmark_pipe_no_pinning >> "$RESULTS_DIR/benchmark_results_no_pinning.txt" 2>> "$RESULTS_DIR/errors.log"
    echo "  Done."
done

# ─── 4. Zero-computation benchmark (WITH PINNING) ───────────────────
echo ""
echo "=========================================="
echo " 4/5  Zero-Computation Benchmark (With Pinning)"
echo "=========================================="
> "$RESULTS_DIR/benchmark_results.txt"  # clear file

for queue in "${QUEUES[@]}"; do
    echo ""
    echo "--- Queue: $queue ---"
    set_queue "$queue"
    
    # Enable pinning in benchmark pipe
    sed -i 's/pipeline.setPinning(False)/pipeline.setPinning(True)/g' benchmark_pipe.mojo

    echo "  Building benchmark_pipe_with_pinning..."
    mojo build -I .. benchmark_pipe.mojo -o benchmark_pipe_with_pinning
    echo "  Running benchmark..."
    echo "" >> "$RESULTS_DIR/benchmark_results.txt"
    echo "  Queue: $queue" >> "$RESULTS_DIR/benchmark_results.txt"
    ./benchmark_pipe_with_pinning >> "$RESULTS_DIR/benchmark_results.txt" 2>> "$RESULTS_DIR/errors.log"
    echo "  Done."
done

# Restore Communicator to V2
set_queue "MPMC_padding_optional_v2"
echo ""
echo "Restored Communicator to MPMC_padding_optional_v2"

# ─── 5. Generate plots ────────────────────────────────────────────
echo ""
echo "=========================================="
echo " 5/5  Generating plots"
echo "=========================================="

$PYTHON generate_plots.py
$PYTHON generate_plots_no_pinning.py

echo ""
echo "All done! Results in $RESULTS_DIR/, plots in $PLOTS_DIR/"
