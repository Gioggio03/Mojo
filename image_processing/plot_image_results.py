#!/usr/bin/env python3
"""
Parse image processing pipeline benchmark results and generate plots.
Reads output from image_pipeline and produces:
  1. Speedup vs. number of stages (per image size)
  2. Throughput vs. image size (per pipeline depth)
"""

import re
import sys
import os

# Try to import matplotlib
try:
    import matplotlib
    matplotlib.use('Agg')  # non-interactive backend
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("WARNING: matplotlib not available, will only print parsed data")

def parse_results(filepath):
    """Parse the benchmark output file into structured data."""
    data = {}  # {(width, height): {stages: {seq_ms, pipe_ms, speedup}}}
    
    current_size = None
    
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            
            # Parse image size header
            m = re.match(r'Image Size:\s*(\d+)x(\d+)', line)
            if m:
                w, h = int(m.group(1)), int(m.group(2))
                current_size = (w, h)
                if current_size not in data:
                    data[current_size] = {}
                continue
            
            # Parse summary table rows: "  3      | 4.232 | 110.754 | 0.038"
            m = re.match(r'(\d+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)', line)
            if m and current_size:
                stages = int(m.group(1))
                seq_ms = float(m.group(2))
                pipe_ms = float(m.group(3))
                speedup = float(m.group(4))
                data[current_size][stages] = {
                    'seq_ms': seq_ms,
                    'pipe_ms': pipe_ms,
                    'speedup': speedup,
                    'seq_throughput': 200.0 / (seq_ms / 1000.0) if seq_ms > 0 else 0,
                    'pipe_throughput': 200.0 / (pipe_ms / 1000.0) if pipe_ms > 0 else 0,
                }
    
    return data


def print_summary(data):
    """Print a text summary of parsed results."""
    for size in sorted(data.keys()):
        w, h = size
        print(f"\n{'='*60}")
        print(f"  Image Size: {w}x{h} ({w*h*3} bytes)")
        print(f"{'='*60}")
        print(f"  {'Stages':>6} | {'Seq (ms)':>10} | {'Pipe (ms)':>10} | {'Speedup':>8} | {'Pipe Thr (img/s)':>16}")
        print(f"  {'------':>6}-+-{'-'*10}-+-{'-'*10}-+-{'-'*8}-+-{'-'*16}")
        for stages in sorted(data[size].keys()):
            d = data[size][stages]
            print(f"  {stages:>6} | {d['seq_ms']:>10.2f} | {d['pipe_ms']:>10.2f} | {d['speedup']:>8.3f} | {d['pipe_throughput']:>16.1f}")


def plot_speedup(data, output_dir):
    """Plot speedup vs. number of stages for each image size."""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7']
    markers = ['o', 's', '^', 'D', 'v']
    
    sizes = sorted(data.keys())
    for i, size in enumerate(sizes):
        w, h = size
        stages_list = sorted(data[size].keys())
        speedups = [data[size][s]['speedup'] for s in stages_list]
        label = f"{w}×{h} ({w*h*3//1024}KB)"
        ax.plot(stages_list, speedups, 
                marker=markers[i % len(markers)], 
                color=colors[i % len(colors)],
                linewidth=2, markersize=8, label=label)
    
    # Ideal speedup line
    all_stages = sorted(set(s for size_data in data.values() for s in size_data.keys()))
    ax.plot(all_stages, all_stages, '--', color='gray', alpha=0.5, label='Ideal (linear)')
    
    ax.set_xlabel('Number of Pipeline Stages', fontsize=12)
    ax.set_ylabel('Speedup S(N)', fontsize=12)
    ax.set_title('Pipeline Speedup vs. Number of Stages', fontsize=14, fontweight='bold')
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xticks(all_stages)
    
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'speedup_vs_stages.png'), dpi=150)
    print(f"  Saved {output_dir}/speedup_vs_stages.png")
    plt.close()


def plot_throughput(data, output_dir):
    """Plot throughput vs. image size for each pipeline depth."""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4']
    markers = ['o', 's', '^', 'D']
    
    all_stages = sorted(set(s for size_data in data.values() for s in size_data.keys()))
    sizes = sorted(data.keys())
    size_labels = [f"{w}×{h}" for w, h in sizes]
    
    for i, stages in enumerate(all_stages):
        throughputs = []
        for size in sizes:
            if stages in data[size]:
                throughputs.append(data[size][stages]['pipe_throughput'])
            else:
                throughputs.append(0)
        
        ax.plot(range(len(sizes)), throughputs,
                marker=markers[i % len(markers)],
                color=colors[i % len(colors)],
                linewidth=2, markersize=8, label=f'{stages} stages (pipeline)')
    
    ax.set_xlabel('Image Size', fontsize=12)
    ax.set_ylabel('Throughput (img/s)', fontsize=12)
    ax.set_title('Pipeline Throughput vs. Image Size', fontsize=14, fontweight='bold')
    ax.set_xticks(range(len(sizes)))
    ax.set_xticklabels(size_labels)
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_yscale('log')
    
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'throughput_vs_size.png'), dpi=150)
    print(f"  Saved {output_dir}/throughput_vs_size.png")
    plt.close()


def plot_seq_vs_pipe(data, output_dir):
    """Plot sequential vs. pipeline execution times."""
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    
    sizes = sorted(data.keys())
    colors_seq = '#FF6B6B'
    colors_pipe = '#4ECDC4'
    
    for idx, size in enumerate(sizes):
        ax = axes[idx // 2][idx % 2]
        w, h = size
        
        stages_list = sorted(data[size].keys())
        seq_times = [data[size][s]['seq_ms'] for s in stages_list]
        pipe_times = [data[size][s]['pipe_ms'] for s in stages_list]
        
        x = range(len(stages_list))
        bar_width = 0.35
        
        ax.bar([xi - bar_width/2 for xi in x], seq_times, bar_width, 
               label='Sequential', color=colors_seq, alpha=0.8)
        ax.bar([xi + bar_width/2 for xi in x], pipe_times, bar_width, 
               label='Pipeline', color=colors_pipe, alpha=0.8)
        
        ax.set_xlabel('Stages')
        ax.set_ylabel('Time (ms)')
        ax.set_title(f'{w}×{h} ({w*h*3//1024}KB)')
        ax.set_xticks(list(x))
        ax.set_xticklabels(stages_list)
        ax.legend(fontsize=9)
        ax.grid(True, alpha=0.3, axis='y')
    
    fig.suptitle('Sequential vs. Pipeline Execution Time', fontsize=14, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'seq_vs_pipe.png'), dpi=150)
    print(f"  Saved {output_dir}/seq_vs_pipe.png")
    plt.close()


def main():
    results_file = "results/image_pipeline_results.txt"
    output_dir = "plots"
    
    if len(sys.argv) > 1:
        results_file = sys.argv[1]
    
    if not os.path.exists(results_file):
        print(f"ERROR: Results file not found: {results_file}")
        sys.exit(1)
    
    print("Parsing benchmark results...")
    data = parse_results(results_file)
    
    if not data:
        print("ERROR: No data parsed from results file")
        sys.exit(1)
    
    print_summary(data)
    
    if HAS_MATPLOTLIB:
        print("\nGenerating plots...")
        os.makedirs(output_dir, exist_ok=True)
        plot_speedup(data, output_dir)
        plot_throughput(data, output_dir)
        plot_seq_vs_pipe(data, output_dir)
        print("Done!")
    else:
        print("\nSkipping plots (matplotlib not available)")


if __name__ == "__main__":
    main()
