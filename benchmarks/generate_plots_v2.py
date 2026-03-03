"""
Generate scalability plots for the v2 benchmark results (T = 10ms, 1ms, 100us, 10us).
Reads both pinning and no-pinning result files and generates comparison plots.
"""
import re
import os
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np


# ─────────────────────────────────────────────────────────────────────
# Parser
# ─────────────────────────────────────────────────────────────────────

def parse_scalability_results(filename):
    """Parse scalability results with headers '--- Size=XB, T=Yms ---'."""
    data = []
    current_queue = None
    current_size = None
    current_t = None

    with open(filename, 'r') as f:
        for line in f:
            queue_match = re.search(r'Queue:\s+(\S+)', line)
            if queue_match:
                current_queue = queue_match.group(1)
                continue

            combined = re.search(r'--- Size=(\d+)B, T=([\d.e\-+]+)ms ---', line)
            if combined:
                current_size = int(combined.group(1))
                current_t = float(combined.group(2))
                continue

            data_match = re.search(
                r'N=\s*(\d+).*SleepPerStage=\s*([\d.e\-+]+)\s*ms'
                r'.*mean:\s*([\d.e\-+]+)\s*ms'
                r'.*B:\s*([\d.e\-+]+)\s*msg/s'
                r'.*E\(N\):\s*([\d.e\-+]+)'
                r'.*S\(N\):\s*([\d.e\-+]+)',
                line
            )
            if data_match and current_t is not None:
                n = int(data_match.group(1))
                sleep_ms = float(data_match.group(2))
                size_in_line = re.search(r'Size=\s*(\d+)\s*B', line)
                size = current_size if current_size else int(size_in_line.group(1))
                queue = current_queue if current_queue else 'MPMC_padding_optional_v2'
                data.append({
                    'Queue': queue,
                    'Size': size,
                    'T_ms': current_t,
                    'N': n,
                    'SleepMs': sleep_ms,
                    'MeanTime': float(data_match.group(3)),
                    'Throughput': float(data_match.group(4)),
                    'Efficiency': float(data_match.group(5)),
                    'Speedup': float(data_match.group(6))
                })
    return pd.DataFrame(data)


# ─────────────────────────────────────────────────────────────────────
# Color/marker maps for T values (in ms)
# ─────────────────────────────────────────────────────────────────────

T_COLORS = {10.0: '#2c3e50', 1.0: '#2980b9', 0.1: '#27ae60', 0.01: '#e74c3c'}
T_MARKERS = {10.0: 'o', 1.0: 's', 0.1: '^', 0.01: 'D'}

def t_label(t_ms):
    """Human-readable label for T in ms."""
    if t_ms >= 1:
        return f'T = {t_ms:.0f} ms'
    elif t_ms >= 0.1:
        return f'T = {t_ms*1000:.0f} μs'
    else:
        return f'T = {t_ms*1000:.0f} μs'


# ─────────────────────────────────────────────────────────────────────
# Plot 1: Scalability S(N) — one plot per Size (pinning vs no-pinning)
# ─────────────────────────────────────────────────────────────────────

def plot_scalability_comparison(df_pin, df_nopin):
    """
    For each payload size, plot S(N) vs N with all T values.
    Solid lines = Pinning, dashed = No Pinning.
    """
    if not df_pin.empty:
        df_pin = df_pin.copy()
        df_pin['Pinning'] = 'Pinned'
    if not df_nopin.empty:
        df_nopin = df_nopin.copy()
        df_nopin['Pinning'] = 'No Pinning'

    df = pd.concat([df_pin, df_nopin], ignore_index=True)
    df_valid = df[df['SleepMs'] > 0]
    if df_valid.empty:
        print("  No valid scalability data found, skipping.")
        return

    sizes = sorted(df_valid['Size'].unique())
    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)

    for size in sizes:
        fig, ax = plt.subplots(figsize=(10, 6))
        subset = df_valid[df_valid['Size'] == size]

        for t_ms in t_values:
            for pin_state in ['Pinned', 'No Pinning']:
                sub = subset[(subset['T_ms'] == t_ms) & (subset['Pinning'] == pin_state)].sort_values('N')
                if not sub.empty:
                    ls = '-' if pin_state == 'Pinned' else '--'
                    alpha = 1.0 if pin_state == 'Pinned' else 0.7
                    ax.plot(sub['N'], sub['Speedup'],
                            color=T_COLORS.get(t_ms, 'gray'),
                            marker=T_MARKERS.get(t_ms, 'o'),
                            linestyle=ls, alpha=alpha,
                            label=f'{t_label(t_ms)} ({pin_state})',
                            linewidth=2, markersize=7)

        # Ideal line
        n_range = range(2, 13)
        ax.plot(n_range, n_range, ':', color='gray', alpha=0.5, linewidth=1.5, label='Ideal S(N) = N')

        ax.set_xlabel('Number of Stages (N)', fontsize=12)
        ax.set_ylabel('Relative Scalability S(N)', fontsize=12)
        ax.set_title(f'Pipeline Scalability — Payload {size}B\n(T = 10ms, 1ms, 100μs, 10μs — 5000 messages)', fontsize=13)
        ax.legend(fontsize=9, ncol=2)
        ax.grid(True, alpha=0.3)
        ax.set_xticks(range(2, 13))
        plt.tight_layout()
        fig.savefig(f'plots/scalability_v2_{size}B.png', dpi=150, bbox_inches='tight')
        plt.close(fig)
        print(f"  Generated plots/scalability_v2_{size}B.png")


# ─────────────────────────────────────────────────────────────────────
# Plot 2: Efficiency E(N) — comparison pinning vs no-pinning
# ─────────────────────────────────────────────────────────────────────

def plot_efficiency_comparison(df_pin, df_nopin):
    """
    Plot efficiency E(N) vs N for all T values, comparing pinned vs unpinned.
    Uses a representative payload size (64B).
    """
    if not df_pin.empty:
        df_pin = df_pin.copy()
        df_pin['Pinning'] = 'Pinned'
    if not df_nopin.empty:
        df_nopin = df_nopin.copy()
        df_nopin['Pinning'] = 'No Pinning'

    df = pd.concat([df_pin, df_nopin], ignore_index=True)
    df_valid = df[df['SleepMs'] > 0]
    if df_valid.empty:
        return

    sizes = df_valid['Size'].unique()
    ref_size = 64 if 64 in sizes else sizes[0]
    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)

    fig, ax = plt.subplots(figsize=(10, 6))

    for t_ms in t_values:
        for pin_state in ['Pinned', 'No Pinning']:
            sub = df_valid[(df_valid['Size'] == ref_size) &
                           (df_valid['T_ms'] == t_ms) &
                           (df_valid['Pinning'] == pin_state)].sort_values('N')
            if not sub.empty:
                ls = '-' if pin_state == 'Pinned' else '--'
                alpha = 1.0 if pin_state == 'Pinned' else 0.7
                ax.plot(sub['N'], sub['Efficiency'],
                        color=T_COLORS.get(t_ms, 'gray'),
                        marker=T_MARKERS.get(t_ms, 'o'),
                        linestyle=ls, alpha=alpha,
                        label=f'{t_label(t_ms)} ({pin_state})',
                        linewidth=2, markersize=7)

    ax.axhline(y=1.0, color='gray', linestyle=':', alpha=0.4, label='Ideal')
    ax.set_xlabel('Number of Stages (N)', fontsize=12)
    ax.set_ylabel('Efficiency E(N)', fontsize=12)
    ax.set_title(f'Efficiency Degradation — Payload {ref_size}B\n(Pinned vs No Pinning)', fontsize=13)
    ax.legend(fontsize=9, ncol=2)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0, 1.05)
    ax.set_xticks(range(2, 13))
    plt.tight_layout()
    fig.savefig('plots/efficiency_v2.png', dpi=150, bbox_inches='tight')
    plt.close(fig)
    print("  Generated plots/efficiency_v2.png")


# ─────────────────────────────────────────────────────────────────────
# Plot 3: Scalability per-T (separate plots, pinning only)
# ─────────────────────────────────────────────────────────────────────

def plot_scalability_per_t(df, label_suffix=''):
    """
    One plot per T value, all payload sizes overlaid.
    Helps see the effect of payload size (should be minimal).
    """
    df_valid = df[df['SleepMs'] > 0]
    if df_valid.empty:
        return

    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)
    size_colors = {8: '#e74c3c', 64: '#3498db', 512: '#2ecc71', 4096: '#9b59b6'}
    size_markers = {8: 'o', 64: 's', 512: '^', 4096: 'D'}

    for t_ms in t_values:
        fig, ax = plt.subplots(figsize=(10, 6))
        t_data = df_valid[df_valid['T_ms'] == t_ms]
        sizes = sorted(t_data['Size'].unique())

        for size in sizes:
            sub = t_data[t_data['Size'] == size].sort_values('N')
            if not sub.empty:
                ax.plot(sub['N'], sub['Speedup'],
                        color=size_colors.get(size, 'gray'),
                        marker=size_markers.get(size, 'o'),
                        label=f'Size = {size}B', linewidth=2, markersize=7)

        n_range = range(2, 13)
        ax.plot(n_range, n_range, ':', color='gray', alpha=0.5, linewidth=1.5, label='Ideal S(N) = N')

        ax.set_xlabel('Number of Stages (N)', fontsize=12)
        ax.set_ylabel('Relative Scalability S(N)', fontsize=12)
        ax.set_title(f'Pipeline Scalability — {t_label(t_ms)}{label_suffix}', fontsize=14)
        ax.legend(fontsize=10)
        ax.grid(True, alpha=0.3)
        ax.set_xticks(range(2, 13))
        plt.tight_layout()

        # filename-safe T
        t_tag = f'{t_ms:.2f}ms'.replace('.', '_')
        fig.savefig(f'plots/scalability_v2_T{t_tag}{label_suffix.replace(" ", "_").lower()}.png',
                    dpi=150, bbox_inches='tight')
        plt.close(fig)
        print(f"  Generated scalability_v2_T{t_tag} plot")


# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    os.makedirs('plots', exist_ok=True)

    file_pin = 'results/scalability_v2_with_pinning.txt'
    file_nopin = 'results/scalability_v2_no_pinning.txt'

    df_pin = pd.DataFrame()
    df_nopin = pd.DataFrame()

    if os.path.exists(file_pin):
        print(f"Parsing {file_pin}...")
        df_pin = parse_scalability_results(file_pin)
        print(f"  {len(df_pin)} data points loaded.")
    else:
        print(f"{file_pin} not found.")

    if os.path.exists(file_nopin):
        print(f"Parsing {file_nopin}...")
        df_nopin = parse_scalability_results(file_nopin)
        print(f"  {len(df_nopin)} data points loaded.")
    else:
        print(f"{file_nopin} not found.")

    if df_pin.empty and df_nopin.empty:
        print("No data found, exiting.")
        exit(1)

    # Plot 1: Scalability comparison (pinning vs no-pinning), one per size
    print("\n--- Scalability comparison plots ---")
    plot_scalability_comparison(df_pin, df_nopin)

    # Plot 2: Efficiency comparison
    print("\n--- Efficiency comparison plot ---")
    plot_efficiency_comparison(df_pin, df_nopin)

    # Plot 3: Per-T scalability (pinning only, all sizes overlaid)
    if not df_pin.empty:
        print("\n--- Per-T scalability plots (with pinning) ---")
        plot_scalability_per_t(df_pin, label_suffix=' (Pinned)')

    if not df_nopin.empty:
        print("\n--- Per-T scalability plots (no pinning) ---")
        plot_scalability_per_t(df_nopin, label_suffix=' (No Pinning)')

    print("\nDone generating v2 plots!")
