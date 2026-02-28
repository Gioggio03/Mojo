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
