"""
Plot script for test_spot results — V4 (planar layout + SIMD).

Reads files matching results/test_spot_*.txt and produces:
  1. Throughput bar chart
  2. Per-stage compute time breakdown
  3. Stage cost distribution (stacked bar)

Run:
    python3 plot_test_spot.py
"""

import os
import re
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
import matplotlib.patches as mpatches
matplotlib.rcParams['figure.dpi'] = 150

RESULTS_DIR = 'results'
PLOTS_DIR = os.path.join(RESULTS_DIR, 'plots')
os.makedirs(PLOTS_DIR, exist_ok=True)

def parse_results():
    throughput_rows = []
    stage_rows = []

    for filename in sorted(os.listdir(RESULTS_DIR)):
        if not filename.startswith('test_spot_') or not filename.endswith('.txt'):
            continue
        m = re.search(r'test_spot_(\d+)', filename)
        file_size = f"{m.group(1)}x{m.group(1)}" if m else 'unknown'
        filepath = os.path.join(RESULTS_DIR, filename)

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
                        throughput_rows.append({
                            'size':           file_size,
                            'config':         parts[0],
                            'num_images':     int(parts[1]),
                            'time_ms':        float(parts[2]),
                            'throughput':     float(parts[3]),
                            'efficiency_pct': float(parts[4]),
                        })
                m_stage = re.match(r'\[(\w+)\] compute time:\s*([\d.]+)\s*ms', line)
                if m_stage:
                    stage_rows.append({
                        'size':    file_size,
                        'stage':   m_stage.group(1),
                        'time_ms': float(m_stage.group(2)),
                    })

    return pd.DataFrame(throughput_rows), pd.DataFrame(stage_rows)


STAGE_ORDER  = ['Grayscale', 'GaussianBlur', 'Sharpen']
STAGE_COLORS = ['#90CAF9', '#1E88E5', '#0D47A1']


def plot_throughput(df):
    for size in df[df['config'] != 'source_baseline']['size'].unique():
        df_size = df[df['size'] == size]
        src_row = df_size[df_size['config'] == 'source_baseline']
        if src_row.empty: continue
        source_tput = src_row.iloc[0]['throughput']

        configs_labels = [
            ('source_baseline', 'Source\n(ceiling)'),
            ('seq',             'Sequential'),
            ('uniform_p2',      'Uniform P=2'),
            ('uniform_p3',      'Uniform P=3'),
            ('uniform_p4',      'Uniform P=4'),
            ('uniform_p5',      'Uniform P=5'),
            ('uniform_p6',      'Uniform P=6'),
            ('uniform_p7',      'Uniform P=7'),
            ('optimal_g3b8s8',  'Optimal\nG3 B8 S8'),
        ]
        labels, tputs, colors = [], [], []
        for c, lbl in configs_labels:
            row = df_size[df_size['config'] == c]
            if not row.empty:
                tputs.append(row.iloc[0]['throughput'])
                labels.append(lbl)
                if c == 'source_baseline':   colors.append('#4CAF50')
                elif c.startswith('optim'):  colors.append('#FF9800')
                elif c.startswith('unifor'): colors.append('#2196F3')
                else:                        colors.append('#9E9E9E')

        if not tputs: continue

        fig, ax = plt.subplots(figsize=(14, 6))
        bars = ax.bar(labels, tputs, color=colors, edgecolor='black', linewidth=0.7, width=0.6)
        ax.axhline(y=source_tput, color='#4CAF50', linestyle='--', linewidth=1.5,
                   label=f'Source ceiling ({source_tput:.0f} img/s)')
        for bar, tput in zip(bars, tputs):
            eff = tput / source_tput * 100.0
            txt = f'{tput:.0f} img/s' if tput == source_tput else f'{tput:.0f}\n({eff:.1f}%)'
            ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + source_tput*0.01,
                    txt, ha='center', va='bottom', fontsize=9, fontweight='bold')
        ax.set_ylabel('Throughput (img/s)', fontsize=11)
        ax.set_title(f'V4 Throughput Scaling — Planar Layout + SIMD  ({size})\n'
                     'Pipeline: Source → Gray → Blur → Sharp → Sink',
                     fontsize=12, fontweight='bold')
        ax.grid(axis='y', alpha=0.3)
        ax.set_ylim(0, source_tput * 1.25)
        plt.xticks(rotation=45, ha='right')
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, f'test_spot_1_throughput_{size.split("x")[0]}.png'))
        plt.close()
        print(f'  -> Plot 1: Throughput saved ({size}).')


def plot_stage_times(df_tput, df_stage):
    for size in df_stage['size'].unique():
        df_s = df_stage[df_stage['size'] == size]
        stages, times = [], []
        for stage in STAGE_ORDER:
            row = df_s[df_s['stage'] == stage]
            if not row.empty:
                stages.append(stage); times.append(row.iloc[0]['time_ms'])
        if not stages: continue

        total_ms = sum(times)
        fig, ax = plt.subplots(figsize=(8, 5))
        colors = [STAGE_COLORS[STAGE_ORDER.index(s)] for s in stages]
        bars = ax.bar(stages, times, color=colors, edgecolor='black', linewidth=0.7, width=0.5)
        for bar, t in zip(bars, times):
            pct = t / total_ms * 100.0 if total_ms > 0 else 0.0
            ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + total_ms*0.01,
                    f'{t:.1f} ms\n({pct:.0f}%)', ha='center', va='bottom', fontsize=9, fontweight='bold')
        ax.set_ylabel('Total compute time (ms)', fontsize=11)
        ax.set_title(f'Per-Stage Compute Time — V4 Planar  ({size})', fontsize=11, fontweight='bold')
        ax.grid(axis='y', alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, f'test_spot_2_stage_times_{size.split("x")[0]}.png'))
        plt.close()
        print(f'  -> Plot 2: Stage times saved ({size}).')


def plot_stage_breakdown(df_stage):
    for size in df_stage['size'].unique():
        df_s = df_stage[df_stage['size'] == size]
        stages, times = [], []
        for stage in STAGE_ORDER:
            row = df_s[df_s['stage'] == stage]
            if not row.empty:
                stages.append(stage); times.append(row.iloc[0]['time_ms'])
        if not stages: continue

        total_ms = sum(times)
        pcts = [t / total_ms * 100.0 for t in times]
        fig, ax = plt.subplots(figsize=(10, 3))
        left = 0.0
        for stage, pct, color in zip(stages, pcts, [STAGE_COLORS[STAGE_ORDER.index(s)] for s in stages]):
            ax.barh(['Transform'], [pct], left=left, color=color, edgecolor='white', linewidth=1.5,
                    height=0.5, label=f'{stage} ({pct:.0f}%)')
            if pct > 5:
                ax.text(left + pct/2., 0, f'{stage}\n{pct:.0f}%',
                        ha='center', va='center', fontsize=9, fontweight='bold', color='white')
            left += pct
        ax.set_xlim(0, 100)
        ax.set_xlabel('% of total compute time', fontsize=11)
        ax.set_title(f'Stage Cost Distribution — V4 Planar  ({size})  —  total: {total_ms:.0f} ms',
                     fontsize=11, fontweight='bold')
        ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.35), ncol=len(stages), fontsize=9)
        ax.set_yticks([])
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, f'test_spot_3_stage_breakdown_{size.split("x")[0]}.png'),
                    bbox_inches='tight')
        plt.close()
        print(f'  -> Plot 3: Stage breakdown saved ({size}).')


if __name__ == '__main__':
    df_tput, df_stage = parse_results()
    if df_tput.empty and df_stage.empty:
        print("No results found. Run: ./run_test_spot.sh")
    else:
        if not df_tput.empty:  plot_throughput(df_tput)
        if not df_stage.empty: plot_stage_times(df_tput, df_stage); plot_stage_breakdown(df_stage)
    print(f"\nAll plots saved to '{PLOTS_DIR}'.")
