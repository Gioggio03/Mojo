import re
import os
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np


# ─────────────────────────────────────────────────────────────────────
# Parsers
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

            # New combined header: "--- Size=64B, T=100.0ms ---"
            combined = re.search(r'--- Size=(\d+)B, T=([\d.]+)ms ---', line)
            if combined:
                current_size = int(combined.group(1))
                current_t = float(combined.group(2))
                continue

            # Also support old formats
            t_header = re.search(r'--- T = (\d+) ms ---', line)
            if t_header:
                current_t = int(t_header.group(1))
                continue

            size_header = re.search(r'--- Payload Size:\s+(\d+)B ---', line)
            if size_header:
                current_size = int(size_header.group(1))
                continue

            data_match = re.search(
                r'N=\s*(\d+).*SleepPerStage=\s*([\d.]+)\s*ms'
                r'.*mean:\s*([\d.]+)\s*ms'
                r'.*B:\s*([\d.]+)\s*msg/s'
                r'.*E\(N\):\s*([\d.]+)'
                r'.*S\(N\):\s*([\d.]+)',
                line
            )
            if data_match and current_queue and current_t is not None:
                n = int(data_match.group(1))
                sleep_ms = float(data_match.group(2))
                # Infer size from data line if not set by combined header
                size_in_line = re.search(r'Size=\s*(\d+)\s*B', line)
                size = current_size if current_size else int(size_in_line.group(1))
                data.append({
                    'Queue': current_queue,
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


def parse_benchmark_results(filename):
    """Parse zero-computation benchmark results."""
    data = []
    current_queue = None

    with open(filename, 'r') as f:
        for line in f:
            queue_match = re.search(r'Queue:\s+(\S+)', line)
            if queue_match:
                current_queue = queue_match.group(1)
                continue

            # Old format: "1. MPMC_naif (BlockingSpinLock + List)"
            old_queue = re.search(r'\d+\.\s+([A-Za-z0-9_]+)\s', line)
            if old_queue and 'MPMC' in old_queue.group(1):
                current_queue = old_queue.group(1)
                continue

            # New format: "  N= 3 , Size= 64 B   -> mean: 1.644 ms ..."
            data_match = re.search(
                r'N=\s*(\d+)\s*,\s*Size=\s*(\d+)\s*B'
                r'.*mean:\s*([\d.]+)\s*ms'
                r'.*min:\s*([\d.]+)\s*ms'
                r'.*max:\s*([\d.]+)\s*ms'
                r'.*iters:\s*(\d+)',
                line
            )
            if not data_match:
                # Old format: "  N=2,  Size=8B      -> mean:   0.548 ms ..."
                data_match = re.search(
                    r'N=(\d+),\s*Size=(\d+)B'
                    r'.*mean:\s*([\d.]+)\s*ms'
                    r'.*min:\s*([\d.]+)\s*ms'
                    r'.*max:\s*([\d.]+)\s*ms'
                    r'.*iters:\s*(\d+)',
                    line
                )
            if data_match and current_queue:
                data.append({
                    'Queue': current_queue,
                    'N': int(data_match.group(1)),
                    'Size': int(data_match.group(2)),
                    'MeanTime': float(data_match.group(3)),
                    'MinTime': float(data_match.group(4)),
                    'MaxTime': float(data_match.group(5)),
                    'Iters': int(data_match.group(6))
                })
    return pd.DataFrame(data)


# ─────────────────────────────────────────────────────────────────────
# Plot generators
# ─────────────────────────────────────────────────────────────────────

def plot_scalability(df):
    """
    Plot A: Relative Scalability S(N) vs N.
    One plot per payload size, V2 only, lines per T value.
    Only points where SleepMs > 0.
    """
    df_valid = df[(df['SleepMs'] > 0)]
    if df_valid.empty:
        print("  No valid scalability data found, skipping.")
        return

    sizes = sorted(df_valid['Size'].unique())
    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)

    t_colors = {100: '#2c3e50', 50: '#2980b9', 25: '#27ae60', 10: '#e67e22', 5: '#e74c3c'}
    t_markers = {100: 'o', 50: 's', 25: '^', 10: 'D', 5: 'x'}

    for size in sizes:
        fig, ax = plt.subplots(figsize=(10, 6))
        subset = df_valid[df_valid['Size'] == size]

        for t_ms in t_values:
            t_data = subset[subset['T_ms'] == t_ms].sort_values('N')
            if not t_data.empty:
                ax.plot(t_data['N'], t_data['Speedup'],
                        color=t_colors.get(t_ms, 'gray'),
                        marker=t_markers.get(t_ms, 'o'),
                        label=f'T = {t_ms} ms', linewidth=2, markersize=7)

        # Ideal line S(N) = N
        n_range = range(2, 13)
        ax.plot(n_range, n_range, '--', color='gray', alpha=0.5, linewidth=1.5, label='Ideal S(N) = N')

        ax.set_xlabel('Number of Stages (N)', fontsize=12)
        ax.set_ylabel('Relative Scalability S(N)', fontsize=12)
        ax.set_title(f'Pipeline Scalability — Payload {size}B', fontsize=14)
        ax.legend(fontsize=10)
        ax.grid(True, alpha=0.3)
        ax.set_xticks(range(2, 13))
        plt.tight_layout()
        fig.savefig(f'plots/scalability_{size}B.png', dpi=150, bbox_inches='tight')
        plt.close(fig)
        print(f"  Generated plots/scalability_{size}B.png")


def plot_efficiency_degradation(df):
    """
    Plot B: Efficiency E(N) vs N, all T values overlaid.
    V2 only. Filter SleepMs > 0.
    """
    df_valid = df[df['SleepMs'] > 0]
    if df_valid.empty:
        return

    # Use the first available queue (should be V2)
    queues = df_valid['Queue'].unique()
    ref_queue = queues[0]

    # Pick a representative size (64B)
    sizes = df_valid['Size'].unique()
    ref_size = 64 if 64 in sizes else sizes[0]

    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)
    t_colors = {100: '#2c3e50', 50: '#2980b9', 25: '#27ae60', 10: '#e67e22', 5: '#e74c3c'}
    t_markers = {100: 'o', 50: 's', 25: '^', 10: 'D', 5: 'x'}

    fig, ax = plt.subplots(figsize=(10, 6))

    for t_ms in t_values:
        subset = df_valid[(df_valid['Queue'] == ref_queue) &
                          (df_valid['Size'] == ref_size) &
                          (df_valid['T_ms'] == t_ms)].sort_values('N')
        if not subset.empty:
            ax.plot(subset['N'], subset['Efficiency'],
                    color=t_colors.get(t_ms, 'gray'),
                    marker=t_markers.get(t_ms, 'o'),
                    label=f'T = {t_ms} ms', linewidth=2, markersize=7)

    ax.axhline(y=1.0, color='gray', linestyle='--', alpha=0.4, label='Ideal')
    ax.set_xlabel('Number of Stages (N)', fontsize=12)
    ax.set_ylabel('Efficiency E(N)', fontsize=12)
    ax.set_title(f'Efficiency Degradation vs. Computation Time\n({ref_queue}, Payload {ref_size}B)',
                 fontsize=13)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0.5, 1.05)
    ax.set_xticks(range(2, 13))
    plt.tight_layout()
    fig.savefig('plots/efficiency_degradation.png', dpi=150, bbox_inches='tight')
    plt.close(fig)
    print("  Generated plots/efficiency_degradation.png")


def plot_overhead_histograms(df):
    """
    Plot C: Queue overhead histograms (zero computation).
    One plot per N. All queues. Grouped bars by payload size.
    Logarithmic Y axis.
    """
    if df.empty:
        print("  No benchmark data found, skipping histograms.")
        return

    n_values = sorted(df['N'].unique())
    queues = sorted(df['Queue'].unique())
    sizes = sorted(df['Size'].unique())
    size_labels = [f'{s}B' for s in sizes]

    # Color palette for queues
    colors = ['#e74c3c', '#3498db', '#2ecc71', '#9b59b6', '#e67e22']

    for n in n_values:
        subset = df[df['N'] == n]
        if subset.empty:
            continue

        fig, ax = plt.subplots(figsize=(12, 6))

        x = np.arange(len(sizes))
        width = 0.8 / len(queues)

        for i, queue in enumerate(queues):
            q_data = subset[subset['Queue'] == queue]
            means = []
            for s in sizes:
                row = q_data[q_data['Size'] == s]
                means.append(row['MeanTime'].values[0] if not row.empty else 0)
            offset = (i - len(queues) / 2 + 0.5) * width
            ax.bar(x + offset, means, width, label=queue,
                   color=colors[i % len(colors)], alpha=0.85)

        ax.set_xlabel('Payload Size', fontsize=12)
        ax.set_ylabel('Mean Time (ms) per 1000 messages', fontsize=12)
        ax.set_title(f'Queue Overhead (Zero Computation) — N={n}', fontsize=14)
        ax.set_xticks(x)
        ax.set_xticklabels(size_labels)
        ax.legend(fontsize=9)
        ax.grid(axis='y', alpha=0.3)
        ax.set_yscale('log')
        plt.tight_layout()
        fig.savefig(f'plots/overhead_N{n}.png', dpi=150, bbox_inches='tight')
        plt.close(fig)
        print(f"  Generated plots/overhead_N{n}.png")


# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not os.path.exists('plots'):
        os.makedirs('plots')

    # Scalability plots (with simulated computation)
    scal_file = 'results/scalability_results.txt'
    if os.path.exists(scal_file):
        print(f"Parsing {scal_file}...")
        df_scal = parse_scalability_results(scal_file)
        if not df_scal.empty:
            print(f"  {len(df_scal)} data points loaded.")
            plot_scalability(df_scal)
            plot_efficiency_degradation(df_scal)
        else:
            print("  No data parsed from scalability results.")
    else:
        print(f"{scal_file} not found, skipping scalability plots.")

    # Zero-computation overhead histograms
    bench_file = 'results/benchmark_results.txt'
    if os.path.exists(bench_file):
        print(f"Parsing {bench_file}...")
        df_bench = parse_benchmark_results(bench_file)
        if not df_bench.empty:
            print(f"  {len(df_bench)} data points loaded.")
            plot_overhead_histograms(df_bench)
        else:
            print("  No data parsed from benchmark results.")
    else:
        print(f"{bench_file} not found, skipping overhead plots.")

    print("\nDone!")
