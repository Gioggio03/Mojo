#!/usr/bin/env python3
"""
Iterative bottleneck tuning — V4 (planar SIMD stages).

Starts from a low config (G=3, B=5, S=5) and adds one worker to the
bottleneck stage each iteration, up to MAX_WORKERS total workers.

Usage:
    python3 run_tuning_v4.py

Output: tuning_results.md
"""

import subprocess
import re
import os
import sys

MAX_WORKERS = 20          # source + sink add 2 → max 22 total threads
MOJO_BIN    = 'mojo'
BENCH_FILE  = 'bottleneck_tuned_benchmark.mojo'
RESULTS_MD  = 'tuning_results.md'
DURATION    = 60          # seconds per run (must match comptime DURATION in .mojo)

def set_config(g, b, s):
    """Patch G/B/S values in bottleneck_tuned_benchmark.mojo."""
    with open(BENCH_FILE, 'r') as f:
        src = f.read()
    src = re.sub(r'(comptime G: Int = )\d+', rf'\g<1>{g}', src)
    src = re.sub(r'(comptime B: Int = )\d+', rf'\g<1>{b}', src)
    src = re.sub(r'(comptime S: Int = )\d+', rf'\g<1>{s}', src)
    with open(BENCH_FILE, 'w') as f:
        f.write(src)

def run_config(g, b, s):
    """Run the benchmark and return (throughput, per_stage_times)."""
    set_config(g, b, s)
    print(f"  Running G={g} B={b} S={s} (total={g+b+s+2} threads)...", flush=True)
    result = subprocess.run(
        [MOJO_BIN, 'run', BENCH_FILE],
        capture_output=True, text=True, timeout=DURATION * 2 + 30
    )
    output = result.stdout + result.stderr

    # Parse throughput
    tput = 0.0
    m = re.search(r'(\d+(?:\.\d+)?)\s+img/s', output)
    if m:
        tput = float(m.group(1))

    # Parse per-stage compute times
    stage_times = {}
    for stage in ('Grayscale', 'GaussianBlur', 'Sharpen'):
        m2 = re.search(rf'\[{stage}\] compute time:\s+([\d.]+)\s+ms', output)
        if m2:
            stage_times[stage] = float(m2.group(1))

    print(f"    → {tput:.0f} img/s  | stage times: {stage_times}", flush=True)
    return tput, stage_times

def capacity(ms_per_img_per_worker, n_workers):
    """Throughput capacity of a stage in img/s."""
    if ms_per_img_per_worker <= 0:
        return float('inf')
    return n_workers * (1000.0 / ms_per_img_per_worker)

def bottleneck_stage(stage_times, g, b, s):
    """Return which stage is the bottleneck (lowest capacity)."""
    caps = {
        'Grayscale':    capacity(stage_times.get('Grayscale',    1e9), g),
        'GaussianBlur': capacity(stage_times.get('GaussianBlur', 1e9), b),
        'Sharpen':      capacity(stage_times.get('Sharpen',      1e9), s),
    }
    bottleneck = min(caps, key=caps.get)
    return bottleneck, caps

def main():
    g, b, s = 3, 5, 5
    history = []
    best_tput = 0.0
    best_config = (g, b, s)

    print("=" * 60)
    print("  Iterative Bottleneck Tuning — V4 (planar SIMD)")
    print(f"  Starting config: G={g} B={b} S={s}")
    print(f"  Max workers: {MAX_WORKERS}  (+ source + sink = {MAX_WORKERS+2} total)")
    print("=" * 60)

    while g + b + s <= MAX_WORKERS:
        tput, stage_times = run_config(g, b, s)
        history.append((g, b, s, tput, dict(stage_times)))

        if tput > best_tput:
            best_tput = tput
            best_config = (g, b, s)

        # Identify bottleneck
        bn, caps = bottleneck_stage(stage_times, g, b, s)
        print(f"    Capacities: Gray={caps['Grayscale']:.0f}  Blur={caps['GaussianBlur']:.0f}  Sharp={caps['Sharpen']:.0f}")
        print(f"    Bottleneck: {bn}")

        if g + b + s >= MAX_WORKERS:
            print("  Max workers reached.")
            break

        # Add one worker to the bottleneck stage
        if bn == 'Grayscale':
            g += 1
        elif bn == 'GaussianBlur':
            b += 1
        else:
            s += 1

    # Write results
    with open(RESULTS_MD, 'w') as f:
        f.write("# V4 Tuning Results (planar SIMD)\n\n")
        f.write(f"Max workers: {MAX_WORKERS} (+ source + sink = {MAX_WORKERS+2} total)\n\n")
        f.write("| Config | Threads | Throughput | Gray ms | Blur ms | Sharp ms |\n")
        f.write("|--------|---------|------------|---------|---------|----------|\n")
        for (g_, b_, s_, t_, st_) in history:
            gray_ms  = st_.get('Grayscale',    0)
            blur_ms  = st_.get('GaussianBlur', 0)
            sharp_ms = st_.get('Sharpen',      0)
            marker = " ← best" if (g_, b_, s_) == best_config else ""
            f.write(f"| G{g_}B{b_}S{s_} | {g_+b_+s_+2} | {t_:.0f} img/s | "
                    f"{gray_ms:.3f} | {blur_ms:.3f} | {sharp_ms:.3f} |{marker}\n")
        f.write(f"\n**Optimal: G{best_config[0]}B{best_config[1]}S{best_config[2]} "
                f"({best_config[0]+best_config[1]+best_config[2]+2} threads) = {best_tput:.0f} img/s**\n")

    print(f"\n{'='*60}")
    print(f"  OPTIMAL: G{best_config[0]} B{best_config[1]} S{best_config[2]} "
          f"({best_config[0]+best_config[1]+best_config[2]+2} threads) = {best_tput:.0f} img/s")
    print(f"  Results saved to {RESULTS_MD}")
    print(f"{'='*60}")

    # Restore optimal config
    set_config(*best_config)
    print(f"  bottleneck_tuned_benchmark.mojo restored to optimal G{best_config[0]}B{best_config[1]}S{best_config[2]}")

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    main()
