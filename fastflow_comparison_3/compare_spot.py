"""
Comparison plot: Mojo V3 (MoStream) vs FastFlow V2 — usando i risultati dello spot sweep.

Legge spot_sweep_512_O3.txt di FastFlow V2 (ogni config = processo separato)
e benchmark_full_512_O3.txt di Mojo V3 per confronto.

Genera 3 grafici in results/plots_spot/.

Run:
    python3 compare_spot.py
"""

import os
import sys
import argparse
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
import matplotlib.patches as mpatches
import numpy as np
matplotlib.rcParams['figure.dpi'] = 150

_parser = argparse.ArgumentParser()
_parser.add_argument('--ff-file',   default=None)
_parser.add_argument('--mojo-file', default=None)
_parser.add_argument('--plots-dir', default=None)
_args = _parser.parse_args()

RESULTS_DIR   = 'results'
MOJO_RESULTS  = os.path.join('..', 'image_processing_3', 'results', 'benchmark_full_512_O3.txt')
FF_SPOT_FILE  = os.path.join('..', 'fastflow_comparison_2', 'results', 'spot_sweep_512_O3.txt')
PLOTS_DIR     = _args.plots_dir or os.path.join(RESULTS_DIR, 'plots_spot')
os.makedirs(PLOTS_DIR, exist_ok=True)

_CONFIG_MAP = {
    'g1b1s1':    'seq',
    'g2b2s2':    'uniform_p2',
    'g3b3s3':    'uniform_p3',
    'g4b4s4':    'uniform_p4',
    'g5b5s5':    'uniform_p5',
    'g6b6s6':    'uniform_p6',
    'g7b7s7':    'uniform_p7',
    'g2b7s10':   'optimal_g2b7s10',
}

# Mojo V3 optimal is G3 B8 S8; FF V2 optimal tested is G2 B7 S10.
# Both are shown — each will have only one bar.
CONFIGS = [
    ('seq',             'SEQ\nG1 B1 S1'),
    ('uniform_p2',      'P2\nG2 B2 S2'),
    ('uniform_p3',      'P3\nG3 B3 S3'),
    ('uniform_p4',      'P4\nG4 B4 S4'),
    ('uniform_p5',      'P5\nG5 B5 S5'),
    ('uniform_p6',      'P6\nG6 B6 S6'),
    ('uniform_p7',      'P7\nG7 B7 S7'),
    ('optimal_g3b8s8',  'Mojo Opt\nG3 B8 S8'),
    ('optimal_g2b7s10', 'FF Opt\nG2 B7 S10'),
]

MOJO_COLOR = '#FF6F00'
FF_COLOR   = '#1565C0'

# ─── Parsing ──────────────────────────────────────────────────────────────────

def parse_spot_sweep(filepath):
    rows = {}
    src_tputs = []
    in_csv = False
    block_rows = []

    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line == 'CSV_START':
                in_csv = True
                block_rows = []
                continue
            if line == 'CSV_END':
                in_csv = False
                for r in block_rows:
                    parts = [p.strip() for p in r.split(',')]
                    if len(parts) < 4:
                        continue
                    name = parts[0]
                    if name == 'config':
                        continue
                    try:
                        if name == 'source_baseline':
                            src_tputs.append(float(parts[3]))
                        else:
                            canonical = _CONFIG_MAP.get(name)
                            if canonical:
                                rows[canonical] = {
                                    'config':     canonical,
                                    'num_images': int(parts[1]),
                                    'throughput': float(parts[3]),
                                    'efficiency': float(parts[4]) if len(parts) > 4 else 0.0,
                                }
                    except (ValueError, IndexError):
                        pass
                continue
            if in_csv:
                block_rows.append(line)

    avg_src = sum(src_tputs) / len(src_tputs) if src_tputs else 0.0
    return rows, avg_src


def parse_mojo_benchmark(filepath):
    rows = {}
    source_tput = 0.0
    in_csv = False

    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line == 'CSV_START':
                in_csv = True
                continue
            if line == 'CSV_END':
                in_csv = False
                continue
            if not in_csv or not line or line.startswith('config,'):
                continue
            parts = [p.strip() for p in line.split(',')]
            if len(parts) < 4:
                continue
            name = parts[0]
            try:
                tput = float(parts[3])
                n    = int(parts[1])
            except (ValueError, IndexError):
                continue

            if name == 'source_baseline':
                source_tput = tput
            else:
                rows[name] = {'config': name, 'num_images': n, 'throughput': tput}

    return rows, source_tput


def build_dataframe():
    ff_file   = _args.ff_file   or FF_SPOT_FILE
    mojo_file = _args.mojo_file or MOJO_RESULTS

    records = []

    if os.path.exists(ff_file):
        ff_rows, ff_src = parse_spot_sweep(ff_file)
        print(f"Loaded FastFlow spot sweep: {ff_file}  (avg source={ff_src:.0f} img/s)")
        records.append({'framework': 'FastFlow', 'config': 'source_baseline',
                        'throughput': ff_src, 'num_images': 0})
        for cfg, d in ff_rows.items():
            records.append({**d, 'framework': 'FastFlow'})
    else:
        print(f"WARNING: FastFlow spot sweep not found: {ff_file}")

    if os.path.exists(mojo_file):
        mojo_rows, mojo_src = parse_mojo_benchmark(mojo_file)
        print(f"Loaded Mojo results:        {mojo_file}  (source={mojo_src:.0f} img/s)")
        records.append({'framework': 'Mojo', 'config': 'source_baseline',
                        'throughput': mojo_src, 'num_images': 0})
        for cfg, d in mojo_rows.items():
            records.append({**d, 'framework': 'Mojo'})
    else:
        print(f"WARNING: Mojo results not found: {mojo_file}")

    return pd.DataFrame(records)

# ─── Plots ────────────────────────────────────────────────────────────────────

def plot_throughput(df):
    frameworks = df['framework'].unique()
    if len(frameworks) < 2:
        print("  Skipping throughput (need both frameworks)")
        return

    fig, ax = plt.subplots(figsize=(16, 7))
    x = np.arange(len(CONFIGS))
    bw = 0.35

    for i, (cfg, _) in enumerate(CONFIGS):
        for fw, color, off in [('Mojo', MOJO_COLOR, -bw/2), ('FastFlow', FF_COLOR, bw/2)]:
            row = df[(df['config'] == cfg) & (df['framework'] == fw)]
            if not row.empty:
                tput = row.iloc[0]['throughput']
                ax.bar(i + off, tput, bw, color=color, edgecolor='black', linewidth=0.5)
                ax.text(i + off, tput + 30, f'{tput:.0f}',
                        ha='center', va='bottom', fontsize=6, rotation=45)

    for fw, color, ls in [('Mojo', MOJO_COLOR, '--'), ('FastFlow', FF_COLOR, ':')]:
        src = df[(df['config'] == 'source_baseline') & (df['framework'] == fw)]
        if not src.empty:
            s = src.iloc[0]['throughput']
            ax.axhline(y=s, color=color, linestyle=ls, linewidth=1.5, alpha=0.7,
                       label=f'{fw} source ceiling ({s:.0f} img/s)')

    ax.set_xticks(x)
    ax.set_xticklabels([lbl for _, lbl in CONFIGS], fontsize=7)
    ax.set_title('Throughput: Mojo V3 (MoStream) vs FastFlow V2 — Spot Sweep\n'
                 '512×512 images, 60s per config, processo separato',
                 fontsize=13, fontweight='bold')
    ax.set_ylabel('Throughput (img/s)', fontsize=11)
    ax.set_xlabel('Pipeline Configuration', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    legend = [mpatches.Patch(color=MOJO_COLOR, label='Mojo V3 (MoStream)'),
              mpatches.Patch(color=FF_COLOR,   label='FastFlow V2')]
    ax.legend(handles=legend + ax.get_legend_handles_labels()[0], fontsize=9, loc='upper left')
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_1_throughput.png'))
    plt.close()
    print('  -> Plot 1: throughput saved')


def plot_speedup(df):
    frameworks = df['framework'].unique()
    if len(frameworks) < 2:
        print("  Skipping speedup (need both frameworks)")
        return

    labels, ratios, colors = [], [], []
    for cfg, lbl in CONFIGS:
        mojo = df[(df['config'] == cfg) & (df['framework'] == 'Mojo')]
        ff   = df[(df['config'] == cfg) & (df['framework'] == 'FastFlow')]
        if not mojo.empty and not ff.empty and mojo.iloc[0]['throughput'] > 0 and ff.iloc[0]['throughput'] > 0:
            r = ff.iloc[0]['throughput'] / mojo.iloc[0]['throughput']
            labels.append(lbl)
            ratios.append(r)
            colors.append('#4CAF50' if r >= 1.0 else '#F44336')

    if not ratios:
        return

    fig, ax = plt.subplots(figsize=(14, 6))
    bars = ax.bar(range(len(ratios)), ratios, color=colors, edgecolor='black', linewidth=0.5)
    ax.axhline(y=1.0, color='#9E9E9E', linestyle='--', linewidth=2, label='Parity')

    for bar, r in zip(bars, ratios):
        ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 0.02,
                f'{r:.2f}x', ha='center', va='bottom', fontsize=9, fontweight='bold')

    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, fontsize=7)
    ax.set_title('FastFlow V2 / Mojo V3 Throughput Ratio — Spot Sweep\n'
                 '> 1.0 = FastFlow faster  |  < 1.0 = Mojo faster',
                 fontsize=13, fontweight='bold')
    ax.set_ylabel('Ratio (FF / Mojo)', fontsize=11)
    ax.set_xlabel('Pipeline Configuration', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    ax.legend(handles=[mpatches.Patch(color='#4CAF50', label='FastFlow faster'),
                       mpatches.Patch(color='#F44336', label='Mojo faster')], fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_2_speedup_ratio.png'))
    plt.close()
    print('  -> Plot 2: speedup ratio saved')


def plot_latency(df):
    frameworks = df['framework'].unique()
    if len(frameworks) < 2:
        print("  Skipping latency (need both frameworks)")
        return

    fig, ax = plt.subplots(figsize=(14, 6))
    x = np.arange(len(CONFIGS))
    bw = 0.35

    for fw, color, off in [('Mojo', MOJO_COLOR, -bw/2), ('FastFlow', FF_COLOR, bw/2)]:
        lats, pos = [], []
        for i, (cfg, _) in enumerate(CONFIGS):
            row = df[(df['config'] == cfg) & (df['framework'] == fw)]
            if not row.empty:
                t = row.iloc[0]['throughput']
                lats.append(1000.0 / t if t > 0 else 0)
                pos.append(i)
        if lats:
            ax.bar(np.array(pos) + off, lats, bw, color=color,
                   edgecolor='black', linewidth=0.5, label=fw)
            for p, l in zip(pos, lats):
                ax.text(p + off, l + 0.1, f'{l:.2f}',
                        ha='center', va='bottom', fontsize=6, rotation=45)

    ax.set_xticks(x)
    ax.set_xticklabels([lbl for _, lbl in CONFIGS], fontsize=7)
    ax.set_title('Latency per Image: Mojo V3 vs FastFlow V2 — Spot Sweep\n(lower is better)',
                 fontsize=13, fontweight='bold')
    ax.set_ylabel('Latency (ms/image)', fontsize=11)
    ax.set_xlabel('Pipeline Configuration', fontsize=11)
    ax.grid(axis='y', alpha=0.3)
    ax.legend(fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(PLOTS_DIR, 'compare_3_latency.png'))
    plt.close()
    print('  -> Plot 3: latency saved')


def print_summary(df):
    print('\n' + '=' * 72)
    print('  SUMMARY: Mojo V3 (MoStream) vs FastFlow V2 — Spot Sweep')
    print('=' * 72)
    print(f"  {'Config':<22} {'Mojo (img/s)':>13} {'FF (img/s)':>13} {'FF/Mojo':>9}")
    print('  ' + '-' * 60)
    for cfg, lbl in [('source_baseline', 'Source ceiling')] + CONFIGS:
        mojo = df[(df['config'] == cfg) & (df['framework'] == 'Mojo')]
        ff   = df[(df['config'] == cfg) & (df['framework'] == 'FastFlow')]
        m = mojo.iloc[0]['throughput'] if not mojo.empty else 0
        f = ff.iloc[0]['throughput']   if not ff.empty   else 0
        r = f / m if m > 0 else 0
        lbl_short = lbl.replace('\n', ' ')
        print(f"  {lbl_short:<22} {m:>13.1f} {f:>13.1f} {r:>8.2f}x")
    print('=' * 72)


if __name__ == '__main__':
    df = build_dataframe()
    if df.empty:
        print("No results found.")
        sys.exit(1)

    print(f"\nGenerating plots in '{PLOTS_DIR}'...")
    plot_throughput(df)
    plot_speedup(df)
    plot_latency(df)
    print_summary(df)
    print(f"\nDone. Plots saved to '{PLOTS_DIR}'.")
