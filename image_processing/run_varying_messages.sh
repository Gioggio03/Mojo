#!/bin/bash

# Directory setup
cd "$(dirname "$0")" || exit
RESULTS_DIR="results"

# Assicurati che la cartella results esista
mkdir -p "$RESULTS_DIR"

echo "================================================="
echo "  Starting automated image pipeline benchmarks   "
echo "================================================="

# Variables
MESSAGE_COUNTS=(250 500 1000 1500)
export MOSTREAM_HOME="/home/gcappello/Mojo"

for N in "${MESSAGE_COUNTS[@]}"; do
    echo "-> Running with N=${N} messages..."
    
    # Sostituisce il valore hardcoded comptime NUM_IMAGES nel file mojo
    sed -i "s/comptime NUM_IMAGES: Int = [0-9]\+/comptime NUM_IMAGES: Int = ${N}/" image_pipeline.mojo
    
    # Esegue il benchmark e salva l'output
    mojo run -I /home/gcappello/Mojo image_pipeline.mojo > "${RESULTS_DIR}/pipeline_results_${N}.txt"
    
    echo "   Finished run for N=${N}. Output saved in: ${RESULTS_DIR}/pipeline_results_${N}.txt"
done

# Ripristina il valore originale a 200 per pulizia
echo "-> Restoring default configuration (N=200)..."
sed -i "s/comptime NUM_IMAGES: Int = [0-9]\+/comptime NUM_IMAGES: Int = 200/" image_pipeline.mojo

echo "================================================="
echo "  All benchmark runs completed successfully!     "
echo "================================================="

echo "-> Generating summary plots..."
if [ ! -d ".venv" ]; then
    echo "   Creating Python virtual environment (.venv)..."
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install -q pandas matplotlib
python3 plot_results.py
deactivate

echo "================================================="
echo "  Plots saved successfully in results/plots/     "
echo "================================================="
