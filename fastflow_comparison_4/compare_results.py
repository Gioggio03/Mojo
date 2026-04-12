"""
Comparison plot: Mojo V4 (planar SIMD) vs FastFlow V4 (planar, -O3).

Reads CSV results from both frameworks and generates:
  1. Side-by-side throughput bar chart
  2. Speedup ratio (FastFlow / Mojo) per configuration
  3. Latency comparison (ms per image)

Mojo results:     ../image_processing_4/results/test_spot_512.txt
FastFlow results: results/test_spot_512_O3.txt  (or --ff-file)

Run:
    python3 compare_results.py
    python3 compare_results.py --ff-file results/test_spot_512_O2.txt
"""

import os
import re
import sys
import argparse
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
import matplotlib.patches as mpatches
import numpy as np
matplotlib.rcParams['figure.dpi'] = 150

_parser = argparse.ArgumentParser()
_parser.add_argument('--ff-file',    default=None)
_parser.add_argument('--mojo-file',  default=None)
_parser.add_argument('--plots-dir',  default=None)
_args = _parser.parse_args()

FF_RESULTS_DIR   = 'results'
MOJO_RESULTS_DIR = os.path.join('..', 'image_processing_4', 'results')
PLOTS_DIR        = _args.plots_dir or os.path.join(FF_RESULTS_DIR, 'plots')
os.makedirs(PLOTS_DIR, exist_ok=True)

def parse_csv_results(filepath, framework):
    rows = []
    in_csv = False
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line == 'CSV_START':
                in_csv = True; continue
            if line == 'CSV_END':
                in_csv = False; continue
            if in_csv and line and not line.startswith('config,'):
                parts = [p.strip() for p in line.split(',')]
                if len(parts) >= 5:
                    config_name = parts[0]
                    threads = 1
                    if 'seq' in config_name:              threads = 5
                    elif 'uniform_p' in config_name:
                        p = int(config_name.split('_p')[1]); threads = p * 3 + 2
                    elif 'optimal_g3b8s8'  in config_name: threads = 21
                    elif 'optimal_g2b7s10' in config_name: threads = 21
                    elif 'source_baseline' in config_name: threads = 3
                    rows.append({
                        'framework':     framework,
                        'config':        config_name,
                        'total_threads': threads,
                        'num_images':    int(parts[1]),
                        'time_ms':       float(parts[2]),
                        'throughput':    float(parts[3]),
                        'efficiency':    float(parts[4]),
                    })
    return rows

def load_results():
    all_rows = []
    mojo_file = _args.mojo_file or os.path.join(MOJO_RESULTS_DIR, 'test_spot_512.txt')
    if os.path.exists(mojo_file):
        all_rows.extend(parse_csv_results(mojo_file, 'Mojo'))
        print(f"Loaded Mojo results: {mojo_file}")
    else:
        print(f"WARNING: Mojo results not found: {mojo_file}")

    ff_file = _args.ff_file or os.path.join(FF_RESULTS_DIR, 'test_spot_512_O3.txt')
    if os.path.exists(ff_file):
        all_rows.extend(parse_csv_results(ff_file, 'FastFlow'))
        print(f"Loaded FastFlow results: {ff_file}")
    else:
        print(f"WARNING: FastFlow results not found: {ff_file}")

    return pd.DataFrame(all_rows)

# Configs shown in plots (updated after tuning for Mojo optimal)
CONFIGS = [
    ('seq',              'SEQ\nG1 B1 S1'),
    ('uniform_p2',       'P2\nG2 B2 S2'),
    ('uniform_p3',       'P3\nG3 B3 S3'),
    ('uniform_p4',       'P4\nG4 B4 S4'),
    ('uniform_p5',       'P5\nG5 B5 S5'),
    ('uniform_p6',       'P6\nG6 B6 S6'),
    ('uniform_p7',       'P7\nG7 B7 S7'),
    ('optimal_g3b8s8',   'Mojo Opt\nG3 B8 S8'),
    ('optimal_g2b7s10',  'FF Opt\nG2 B7 S10'),
]

MOJO_COLOR = '#FF6F00'
FF_COLOR   = '#1565C0'

def plot_throughput_comparison(df):
    if len(df['framework'].unique()) < 2:
        print("  Skipping throughput comparison (need both frameworks)"); return

    fig, ax = plt.subplots(figsize=(16, 7))
    x = np.arange(len(CONFIGS))
    bar_width = 0.35

    for i, (cfg, label) in enumerate(CONFIGS):
        for fw, color, offset in [('Mojo', MOJO_COLOR, -bar_width/2), ('FastFlow', FF_COLOR, bar_width/2)]:
            row = df[(df['config'] == cfg) & (df['framework'] == fw)]
            if not row.empty:
                tput = row.iloc[0]['throughput']
                ax.bar(i + offset, tput, bar_width, color=color, edgecolor='black', linewidth=0.5)
                ax.text(i + offset, tput + 5, f'{tput:.0f}',
                        ha='center', va='bottom', fontsize=6, rotation=45)

    for fw, color, ls in [('Mojo', MOJO_COLOR, '--'), ('FastFlow', FF_COLOR, ':')]:
        src = df[(df['config'] == 'source_baseline') & (df['framework'] == fw)]
        if not src.empty:
            ax.axhline(y=src.iloc[0]['throughput'], color=color, linestyle=ls, linewidth=1.5, alpha=0.7,
                       label=f'{fw} source ceiling ({src.iloc[0]["throughput"]:.0f} img/s)')

    ax.set_xticks(x)
    ax.set_xticklabels([lbl for _, lbl in CONFIGS], fontsize=7)
    ax.set_title('Throughput Comparison: Mojo V4 vs FastFlow V4 (planar layout)\n512x512 images, 60s runs',
                 fontsize=13, fontweight='bold')
    ax.set_ylabel('Throughput (img/s)', fontsize=11)
    ax.set_xlabel('Pipeline Configuration', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    legend = [mpatches.Patch(color=MOJO_COLOR, label='Mojo (MoStream, planar SIMD)'),
              mpatches.Patch(color=FF_COLOR,   label='FastFlow (planar, auto-vec)')]
    ax.legend(handles=legend + ax.get_legend_handles_labels()[0], fontsize=9, loc='upper left')
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_1_throughput.png'))
    plt.close()
    print('  -> Plot 1: Throughput comparison saved.')

def plot_speedup_ratio(df):
    if len(df['framework'].unique()) < 2:
        print("  Skipping speedup ratio (need both frameworks)"); return

    labels, ratios, colors = [], [], []
    for cfg, lbl in CONFIGS:
        mojo = df[(df['config'] == cfg) & (df['framework'] == 'Mojo')]
        ff   = df[(df['config'] == cfg) & (df['framework'] == 'FastFlow')]
        if not mojo.empty and not ff.empty:
            ratio = ff.iloc[0]['throughput'] / mojo.iloc[0]['throughput']
            labels.append(lbl); ratios.append(ratio)
            colors.append('#4CAF50' if ratio >= 1.0 else '#F44336')

    if not ratios: return

    fig, ax = plt.subplots(figsize=(14, 6))
    bars = ax.bar(range(len(ratios)), ratios, color=colors, edgecolor='black', linewidth=0.5)
    ax.axhline(y=1.0, color='#9E9E9E', linestyle='--', linewidth=2, label='Parity')
    for bar, ratio in zip(bars, ratios):
        ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 0.02,
                f'{ratio:.2f}x', ha='center', va='bottom', fontsize=9, fontweight='bold')
    ax.set_xticks(list(range(len(ratios))))
    ax.set_xticklabels(labels, fontsize=7)
    ax.set_title('FastFlow / Mojo Throughput Ratio — V4 Planar\n> 1.0 = FastFlow faster, < 1.0 = Mojo faster',
                 fontsize=13, fontweight='bold')
    ax.set_ylabel('Throughput Ratio (FF / Mojo)', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    ax.legend(handles=[mpatches.Patch(color='#4CAF50', label='FastFlow faster'),
                       mpatches.Patch(color='#F44336', label='Mojo faster')], fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_2_speedup_ratio.png'))
    plt.close()
    print('  -> Plot 2: Speedup ratio saved.')

def plot_latency_comparison(df):
    if len(df['framework'].unique()) < 2:
        print("  Skipping latency comparison (need both frameworks)"); return

    fig, ax = plt.subplots(figsize=(14, 6))
    x = np.arange(len(CONFIGS))
    bar_width = 0.35
    for fw, color, offset in [('Mojo', MOJO_COLOR, -bar_width/2), ('FastFlow', FF_COLOR, bar_width/2)]:
        latencies, positions = [], []
        for i, (cfg, _) in enumerate(CONFIGS):
            row = df[(df['config'] == cfg) & (df['framework'] == fw)]
            if not row.empty:
                tput = row.iloc[0]['throughput']
                latencies.append(1000.0/tput if tput > 0 else 0)
                positions.append(i)
        if latencies:
            ax.bar(np.array(positions)+offset, latencies, bar_width, color=color,
                   edgecolor='black', linewidth=0.5, label=fw)
            for pos, lat in zip(positions, latencies):
                ax.text(pos+offset, lat+0.1, f'{lat:.1f}',
                        ha='center', va='bottom', fontsize=6, rotation=45)
    ax.set_xticks(x)
    ax.set_xticklabels([lbl for _, lbl in CONFIGS], fontsize=7)
    ax.set_title('Latency per Image — V4 Planar (lower is better)', fontsize=13, fontweight='bold')
    ax.set_ylabel('Latency (ms/image)', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    ax.legend(fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_3_latency.png'))
    plt.close()
    print('  -> Plot 3: Latency comparison saved.')

def print_summary_table(df):
    if len(df['framework'].unique()) < 2: return
    print("\n" + "="*80)
    print("  COMPARISON SUMMARY: Mojo V4 vs FastFlow V4 (planar layout)")
    print("="*80)
    print(f"  {'Config':<25} {'Mojo (img/s)':>14} {'FF (img/s)':>14} {'Ratio (FF/Mojo)':>16}")
    print("  " + "-"*74)
    for cfg, lbl in [('source_baseline', 'Source ceiling')] + CONFIGS:
        mojo = df[(df['config'] == cfg) & (df['framework'] == 'Mojo')]
        ff   = df[(df['config'] == cfg) & (df['framework'] == 'FastFlow')]
        m_t = mojo.iloc[0]['throughput'] if not mojo.empty else 0
        f_t = ff.iloc[0]['throughput']   if not ff.empty   else 0
        ratio = f_t / m_t if m_t > 0 else 0
        label = lbl.replace('\n', ' ')
        print(f"  {label:<25} {m_t:>14.1f} {f_t:>14.1f} {ratio:>14.2f}x")
    print("="*80)

if __name__ == '__main__':
    df = load_results()
    if df.empty:
        print("No results found. Run both benchmarks first."); sys.exit(1)
    print(f"Frameworks: {list(df['framework'].unique())}, records: {len(df)}")
    plot_throughput_comparison(df)
    plot_speedup_ratio(df)
    plot_latency_comparison(df)
    print_summary_table(df)
    print(f"\nAll plots saved to '{PLOTS_DIR}'.")
