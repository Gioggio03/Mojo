"""
Plot script for source_rate_benchmark results.

Reads files matching results/source_rate_*.txt and produces 3 plots:
  1. Throughput bar chart — all configs vs source ceiling
  2. Efficiency (% of source ceiling) — uniform sweep vs smart configs
  3. Speedup & parallel efficiency vs sequential baseline

Run:
    python plot_source_rate.py
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

PHYSICAL_CORES = 24

# ============================================================================
# Parsing
# ============================================================================

def parse_results():
    all_rows = []
    for filename in sorted(os.listdir(RESULTS_DIR)):
        if not filename.startswith('source_rate_') or not filename.endswith('.txt'):
            continue
        m = re.search(r'source_rate_(\d+)', filename)
        file_size = f"{m.group(1)}x{m.group(1)}" if m else 'unknown'
        filepath = os.path.join(RESULTS_DIR, filename)
        in_csv = False
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line == 'CSV_START':
                    in_csv = True
                    continue
                if line == 'CSV_END':
                    in_csv = False
                    continue
                if in_csv and line and not line.startswith('config,'):
                    parts = [p.strip() for p in line.split(',')]
                    if len(parts) >= 8:
                        all_rows.append({
                            'size':          file_size,
                            'config':        parts[0],
                            'gray_p':        int(parts[1]),
                            'blur_p':        int(parts[2]),
                            'sharp_p':       int(parts[3]),
                            'total_threads': int(parts[4]),
                            'time_ms':       float(parts[5]),
                            'throughput':    float(parts[6]),
                            'efficiency':    float(parts[7]),
                        })
    return pd.DataFrame(all_rows)


UNIFORM_CFGS = ['uniform_p2', 'uniform_p3', 'uniform_p4', 'uniform_p5', 'uniform_p6', 'uniform_p7']
SMART_CFGS   = ['smart_g1_b2_s1', 'smart_g1_b4_s2', 'smart_g2_b8_s4', 'smart_g2_b14_s6']

CONFIG_DISPLAY = [
    ('seq',              'SEQ\nG1 B1 S1',           '#9E9E9E'),
    ('uniform_p2',       'Uniform P2\nG2 B2 S2',    '#90CAF9'),
    ('uniform_p3',       'Uniform P3\nG3 B3 S3',    '#64B5F6'),
    ('uniform_p4',       'Uniform P4\nG4 B4 S4',    '#42A5F5'),
    ('uniform_p5',       'Uniform P5\nG5 B5 S5',    '#2196F3'),
    ('uniform_p6',       'Uniform P6\nG6 B6 S6',    '#1E88E5'),
    ('uniform_p7',       'Uniform P7\nG7 B7 S7\n(23 threads)', '#0D47A1'),
    ('smart_g1_b2_s1',   'Smart\nG1 B2 S1',         '#FFCC80'),
    ('smart_g1_b4_s2',   'Smart\nG1 B4 S2',         '#FFA726'),
    ('smart_g2_b8_s4',   'Smart\nG2 B8 S4',         '#EF6C00'),
    ('smart_g2_b14_s6',  'Smart\nG2 B14 S6\n(24 threads)', '#BF360C'),
]

# ============================================================================
# Plot 1: Throughput bar chart
# ============================================================================

def plot_throughput(df):
    sizes = df[df['config'] != 'source_baseline']['size'].unique()
    for size in sizes:
        df_size = df[df['size'] == size]
        source_row = df_size[df_size['config'] == 'source_baseline']
        if source_row.empty:
            continue
        source_tput = source_row.iloc[0]['throughput']

        labels, tputs, colors = [], [], []
        for cfg, lbl, col in CONFIG_DISPLAY:
            row = df_size[df_size['config'] == cfg]
            if row.empty:
                continue
            labels.append(lbl)
            tputs.append(row.iloc[0]['throughput'])
            colors.append(col)

        if not tputs:
            continue

        fig, ax = plt.subplots(figsize=(15, 6))
        x = range(len(tputs))
        bars = ax.bar(x, tputs, color=colors, edgecolor='black', linewidth=0.5)
        ax.axhline(y=source_tput, color='#4CAF50', linestyle='--', linewidth=2,
                   label=f'Source ceiling ({source_tput:.0f} img/s)')
        for bar, tput in zip(bars, tputs):
            eff = tput / source_tput * 100.0
            ax.text(bar.get_x() + bar.get_width() / 2., bar.get_height() + source_tput * 0.01,
                    f'{eff:.0f}%', ha='center', va='bottom', fontsize=8, fontweight='bold')
        ax.set_xticks(list(x))
        ax.set_xticklabels(labels, fontsize=8)
        ax.set_title(f'Throughput vs Source Ceiling  ({size})\n'
                     f'Hardware: {PHYSICAL_CORES} physical cores',
                     fontsize=12, fontweight='bold')
        ax.set_ylabel('Throughput (img/s)', fontsize=11)
        ax.set_xlabel('Pipeline Configuration', fontsize=11)
        ax.grid(axis='y', alpha=0.3)
        legend_patches = [
            mpatches.Patch(color='#9E9E9E', label='Sequential'),
            mpatches.Patch(color='#1E88E5', label='Uniform (all stages = P)'),
            mpatches.Patch(color='#EF6C00', label='Smart (proportional to cost)'),
            plt.Line2D([0], [0], color='#4CAF50', linestyle='--', linewidth=2, label='Source ceiling'),
        ]
        ax.legend(handles=legend_patches, loc='lower right', fontsize=9)
        plt.tight_layout()
        res_val = size.split('x')[0]
        plt.savefig(os.path.join(PLOTS_DIR, f'source_rate_1_throughput_{res_val}.png'))
        plt.close()
        print(f'  -> Plot 1: Throughput saved ({size}).')

# ============================================================================
# Plot 2: Efficiency (%) vs total threads
# ============================================================================

def plot_efficiency(df):
    sizes = df[df['config'] != 'source_baseline']['size'].unique()
    for size in sizes:
        df_size = df[df['size'] == size]
        source_row = df_size[df_size['config'] == 'source_baseline']
        if source_row.empty:
            continue
        source_tput = source_row.iloc[0]['throughput']

        fig, ax = plt.subplots(figsize=(12, 6))

        seq_row = df_size[df_size['config'] == 'seq']
        if not seq_row.empty:
            seq_t = seq_row.iloc[0]['total_threads']
            seq_e = seq_row.iloc[0]['throughput'] / source_tput * 100.0
            ax.scatter([seq_t], [seq_e], color='#9E9E9E', s=100, zorder=6,
                       label=f'Sequential ({seq_e:.1f}%)', marker='D')

        u_threads, u_eff = [], []
        for cfg in UNIFORM_CFGS:
            row = df_size[df_size['config'] == cfg]
            if row.empty:
                continue
            u_threads.append(row.iloc[0]['total_threads'])
            u_eff.append(row.iloc[0]['throughput'] / source_tput * 100.0)
        if u_threads:
            ax.plot(u_threads, u_eff, marker='o', color='#1E88E5', linewidth=2,
                    markersize=8, label='Uniform (G=B=S=P)')
            for t, e in zip(u_threads, u_eff):
                ax.annotate(f'{e:.0f}%', (t, e), textcoords='offset points',
                            xytext=(0, 9), ha='center', fontsize=8, color='#1E88E5')

        s_threads, s_eff = [], []
        for cfg in SMART_CFGS:
            row = df_size[df_size['config'] == cfg]
            if row.empty:
                continue
            s_threads.append(row.iloc[0]['total_threads'])
            s_eff.append(row.iloc[0]['throughput'] / source_tput * 100.0)
        if s_threads:
            ax.plot(s_threads, s_eff, marker='s', color='#EF6C00', linewidth=2,
                    markersize=8, linestyle='--', label='Smart (proportional to stage cost)')
            for t, e in zip(s_threads, s_eff):
                ax.annotate(f'{e:.0f}%', (t, e), textcoords='offset points',
                            xytext=(0, -15), ha='center', fontsize=8, color='#EF6C00')

        ax.axvline(x=PHYSICAL_CORES, color='#F44336', linestyle=':', linewidth=1.5,
                   label=f'{PHYSICAL_CORES} physical cores limit')
        ax.axhline(y=100.0, color='#4CAF50', linestyle=':', linewidth=1.5,
                   label='Source ceiling (100%)')
        ax.set_title(f'Efficiency vs Threads Used  ({size})',
                     fontsize=12, fontweight='bold')
        ax.set_xlabel('Total Threads (source + gray + blur + sharp + sink)', fontsize=11)
        ax.set_ylabel('Efficiency (% of source throughput)', fontsize=11)
        ax.set_ylim(0, 115)
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=9)
        plt.tight_layout()
        res_val = size.split('x')[0]
        plt.savefig(os.path.join(PLOTS_DIR, f'source_rate_2_efficiency_{res_val}.png'))
        plt.close()
        print(f'  -> Plot 2: Efficiency saved ({size}).')

# ============================================================================
# Plot 3: Speedup & Parallel Efficiency vs sequential baseline
# ============================================================================

def plot_speedup(df):
    sizes = df[df['config'] != 'source_baseline']['size'].unique()
    for size in sizes:
        df_size = df[df['size'] == size]
        seq_row = df_size[df_size['config'] == 'seq']
        if seq_row.empty:
            continue
        seq_tput = seq_row.iloc[0]['throughput']

        ps, speedups, efficiencies = [], [], []
        for cfg in UNIFORM_CFGS:
            row = df_size[df_size['config'] == cfg]
            if row.empty:
                continue
            p = row.iloc[0]['gray_p']
            sp = row.iloc[0]['throughput'] / seq_tput
            ps.append(p)
            speedups.append(sp)
            efficiencies.append(sp / p * 100.0)

        if not ps:
            continue

        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 9))

        # --- Top: Speedup ---
        ax1.plot(ps, speedups, marker='o', color='#1E88E5', linewidth=2,
                 markersize=8, label='Actual speedup')
        ax1.plot(ps, ps, linestyle='--', color='#9E9E9E', linewidth=1.5,
                 label='Ideal (linear)')
        ax1.axvline(x=PHYSICAL_CORES / 3, color='#F44336', linestyle=':',
                    linewidth=1.5, label=f'P=7 ({PHYSICAL_CORES}-core budget / 3 stages)')
        for p, sp in zip(ps, speedups):
            ax1.annotate(f'{sp:.1f}x', (p, sp), textcoords='offset points',
                         xytext=(0, 8), ha='center', fontsize=9)
        ax1.set_title(f'Speedup vs Sequential  ({size})\n'
                      f'Uniform parallelism: all stages at P workers',
                      fontsize=12, fontweight='bold')
        ax1.set_ylabel('Speedup (T_seq / T_par)', fontsize=10)
        ax1.set_xlabel('Workers per stage (P)', fontsize=10)
        ax1.grid(True, alpha=0.3)
        ax1.legend(fontsize=9)

        # --- Bottom: Parallel efficiency ---
        eff_colors = ['#4CAF50' if e >= 90 else '#FFA726' if e >= 70 else '#F44336'
                      for e in efficiencies]
        bars = ax2.bar(ps, efficiencies, color=eff_colors, edgecolor='black',
                       linewidth=0.5, width=0.6)
        ax2.axhline(y=100.0, color='#9E9E9E', linestyle='--', linewidth=1.5,
                    label='100% efficiency (ideal)')
        ax2.axhline(y=70.0, color='#FF9800', linestyle=':', linewidth=1,
                    label='70% threshold')
        for bar, e in zip(bars, efficiencies):
            ax2.text(bar.get_x() + bar.get_width() / 2., bar.get_height() + 0.5,
                     f'{e:.0f}%', ha='center', va='bottom', fontsize=9, fontweight='bold')
        ax2.set_title('Parallel Efficiency per Stage Worker\n'
                      'efficiency = speedup / P  (100% = perfect linear scaling)',
                      fontsize=12, fontweight='bold')
        ax2.set_ylabel('Efficiency (%)', fontsize=10)
        ax2.set_xlabel('Workers per stage (P)', fontsize=10)
        ax2.set_ylim(0, 130)
        ax2.set_xticks(ps)
        ax2.grid(axis='y', alpha=0.3)
        legend_patches = [
            mpatches.Patch(color='#4CAF50', label='>= 90% (excellent)'),
            mpatches.Patch(color='#FFA726', label='70-90% (good)'),
            mpatches.Patch(color='#F44336', label='< 70% (poor)'),
            plt.Line2D([0], [0], color='#9E9E9E', linestyle='--', label='Ideal (100%)'),
        ]
        ax2.legend(handles=legend_patches, fontsize=8, loc='upper right')
        plt.tight_layout()
        res_val = size.split('x')[0]
        plt.savefig(os.path.join(PLOTS_DIR, f'source_rate_4_speedup_{res_val}.png'))
        plt.close()
        print(f'  -> Plot 3: Speedup & efficiency saved ({size}).')

# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    df = parse_results()
    if df.empty:
        print("No source_rate results found in results/.")
        print("Run: ./run_source_rate.sh")
    else:
        sizes = df['size'].unique()
        print(f"Parsed {len(df)} records across {len(sizes)} image size(s): {list(sizes)}")
        plot_throughput(df)
        plot_efficiency(df)
        plot_speedup(df)
    print(f"\nAll plots saved to '{PLOTS_DIR}'.")
