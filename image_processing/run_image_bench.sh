#!/bin/bash
# Image Processing Pipeline Benchmark Runner
# Compiles and runs the image pipeline benchmark, saving results to file.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Set MOSTREAM_HOME so MoStream can find libFuncC.so
export MOSTREAM_HOME="$(cd .. && pwd)"

RESULTS_FILE="results/image_pipeline_results.txt"
BINARY="image_pipeline"

echo "=============================================="
echo "  Image Processing Pipeline Benchmark"
echo "=============================================="

# Step 1: Generate test images (optional, for PPM file I/O tests)
echo ""
echo "[Phase 1] Generating test images..."
python3 generate_test_images.py

# Step 2: Compile the benchmark
echo ""
echo "[Phase 2] Compiling image_pipeline.mojo..."
mojo build -O3 -I .. image_pipeline.mojo -o "$BINARY"
echo "  Compilation successful!"

# Step 3: Run the benchmark
echo ""
echo "[Phase 3] Running benchmark..."
mkdir -p results

echo "Run started at: $(date)" > "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

./"$BINARY" 2>&1 | tee -a "$RESULTS_FILE"

echo "" >> "$RESULTS_FILE"
echo "Run completed at: $(date)" >> "$RESULTS_FILE"

echo ""
echo "[Phase 4] Results saved to $RESULTS_FILE"

# Step 4: Generate plots (if matplotlib is available)
echo ""
echo "[Phase 5] Generating plots..."
if python3 -c "import matplotlib" 2>/dev/null; then
    python3 plot_image_results.py
    echo "  Plots saved to plots/"
else
    echo "  WARNING: matplotlib not available, skipping plots"
    echo "  Install with: pip install matplotlib"
fi

echo ""
echo "=============================================="
echo "  Benchmark complete!"
echo "=============================================="
