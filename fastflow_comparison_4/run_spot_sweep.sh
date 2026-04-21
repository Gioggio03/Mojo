#!/bin/bash
# Spot sweep — FastFlow V4 stages (planar layout)
#
# Imita il benchmark_full ma ogni configurazione viene eseguita come
# processo separato (./test_spot G B S), evitando il problema di
# accumulo di thread FastFlow tra run successivi nello stesso processo.
#
# Output: results/spot_sweep_512_O3.txt
# Durata: ~10-11 minuti (8 config × ~80s ciascuna)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FF_HOME="${FF_HOME:-../fastflow}"
RESULTS_DIR="results"
OUTPUT="$RESULTS_DIR/spot_sweep_512_O3.txt"

mkdir -p "$RESULTS_DIR"

echo "=== Compiling test_spot (O3) ===" >&2
make FF_HOME="$FF_HOME" test_spot >&2
echo "" >&2

# Configs: "label|G|B|S|threads"
CONFIGS=(
    "SEQ  G1  B1  S1 |1|1|1|5"
    "Uniform P=2      |2|2|2|8"
    "Uniform P=3      |3|3|3|11"
    "Uniform P=4      |4|4|4|14"
    "Uniform P=5      |5|5|5|17"
    "Uniform P=6      |6|6|6|20"
    "Uniform P=7      |7|7|7|23"
    "OPT  G2  B7  S10 |2|7|10|21"
)

# Arrays for summary
declare -a SUM_LABELS SUM_THREADS SUM_NIMGS SUM_TPUTS SUM_SRCS SUM_EFFS

{
    echo "======================================================================"
    echo "  Spot Sweep Benchmark (FastFlow — V4 stages, planar layout)"
    echo "  Image: 512x512 | Duration=60s"
    echo "  Ogni config = processo separato (no thread accumulation)"
    echo "  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink"
    echo "======================================================================"
    echo ""

    for cfg in "${CONFIGS[@]}"; do
        IFS='|' read -r label g b s threads <<< "$cfg"
        label="${label%"${label##*[! ]}"}"   # trim trailing spaces

        echo "----------------------------------------------------------------------"
        echo "  [Running] $label (G=$g B=$b S=$s, threads=$threads)"
        echo "----------------------------------------------------------------------"

        tmp=$(mktemp)
        ./test_spot "$g" "$b" "$s" | tee "$tmp"
        echo ""

        tput_val=$(grep "Tput    :" "$tmp" | awk '{print $3}')
        src_val=$(grep "Source baseline:" "$tmp" | awk '{print $3}')
        n_val=$(grep "N images:" "$tmp" | awk '{print $3}')
        eff_val=$(grep "vs Src  :" "$tmp" | awk '{print $3}')
        rm -f "$tmp"

        SUM_LABELS+=("$label")
        SUM_THREADS+=("$threads")
        SUM_NIMGS+=("$n_val")
        SUM_TPUTS+=("$tput_val")
        SUM_SRCS+=("$src_val")
        SUM_EFFS+=("$eff_val")
    done

    echo ""
    echo "======================================================================"
    echo "  SUMMARY"
    echo "  Config              | Threads | N images | Tput (img/s) | Source (img/s) | vs Src"
    echo "  ------------------------------------------------------------------"
    for i in "${!SUM_LABELS[@]}"; do
        printf "  %-20s| %-8s| %-9s| %-13s| %-15s| %s%%\n" \
            "${SUM_LABELS[$i]}" "${SUM_THREADS[$i]}" "${SUM_NIMGS[$i]}" \
            "${SUM_TPUTS[$i]}" "${SUM_SRCS[$i]}" "${SUM_EFFS[$i]}"
    done
    echo "======================================================================"

    echo ""
    echo "CSV_START"
    echo "config,threads,num_images,throughput_img_s,source_img_s,efficiency_pct"
    for i in "${!SUM_LABELS[@]}"; do
        label_csv=$(echo "${SUM_LABELS[$i]}" | tr ' ' '_' | tr -s '_')
        echo "${label_csv},${SUM_THREADS[$i]},${SUM_NIMGS[$i]},${SUM_TPUTS[$i]},${SUM_SRCS[$i]},${SUM_EFFS[$i]}"
    done
    echo "CSV_END"

} | tee "$OUTPUT"

echo "" >&2
echo "Done. Results: $OUTPUT" >&2
