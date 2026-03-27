#!/bin/bash
# Run the FastFlow benchmark and optionally generate comparison plots.
#
# Usage:
#   ./run_benchmark.sh                    # Build + run FastFlow benchmark
#   ./run_benchmark.sh --compare          # Also generate Mojo vs FastFlow plots
#   ./run_benchmark.sh --ff-home /path    # Specify FastFlow location

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FF_HOME="${FF_HOME:-../fastflow}"
DO_COMPARE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compare) DO_COMPARE=1; shift ;;
        --ff-home) FF_HOME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR/plots"

echo "=== Building FastFlow benchmark ==="
make FF_HOME="$FF_HOME"

echo ""
echo "=== Running FastFlow source_rate_benchmark (512x512) ==="
./source_rate_benchmark | tee "$RESULTS_DIR/source_rate_512.txt"

echo ""
echo "Done. Results: $RESULTS_DIR/source_rate_512.txt"

if [ "$DO_COMPARE" -eq 1 ]; then
    echo ""
    echo "=== Generating comparison plots ==="
    MOJO_RESULTS="../image_processing_2/results/source_rate_512.txt"
    if [ ! -f "$MOJO_RESULTS" ]; then
        echo "WARNING: Mojo results not found at $MOJO_RESULTS"
        echo "Run the Mojo benchmark first: cd ../image_processing_2 && ./run_source_rate.sh"
    else
        python3 compare_results.py
        echo "Plots saved to $RESULTS_DIR/plots/"
    fi
fi
