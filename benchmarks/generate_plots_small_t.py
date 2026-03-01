import os
import matplotlib.pyplot as plt
import pandas as pd
from generate_plots import parse_scalability_results

def plot_small_t_scalability_comparison(df_no_pin, df_with_pin, size):
    if not df_no_pin.empty:
        df_no_pin['Pinning'] = 'No Pinning'
    if not df_with_pin.empty:
        df_with_pin['Pinning'] = 'Pinned'

    df = pd.concat([df_no_pin, df_with_pin], ignore_index=True)
    if df.empty or df[df['SleepMs'] > 0].empty:
        return

    df_valid = df[df['SleepMs'] > 0]
    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)

    t_colors = {2.0: '#2980b9', 1.0: '#e74c3c'}
    
    fig, ax = plt.subplots(figsize=(10, 6))
    subset = df_valid[df_valid['Size'] == size]

    for t_ms in t_values:
        for pin_state in ['Pinned', 'No Pinning']:
            sub_data = subset[(subset['T_ms'] == t_ms) & (subset['Pinning'] == pin_state)].sort_values('N')
            if not sub_data.empty:
                linestyle = '-' if pin_state == 'Pinned' else '--'
                alpha_val = 1.0 if pin_state == 'Pinned' else 0.7
                ax.plot(sub_data['N'], sub_data['Speedup'],
                        color=t_colors.get(t_ms, 'gray'),
                        marker='o',
                        linestyle=linestyle,
                        alpha=alpha_val,
                        label=f'T = {t_ms} ms ({pin_state})', linewidth=2, markersize=7)

    n_range = range(2, 13)
    ax.plot(n_range, n_range, ':', color='gray', alpha=0.5, linewidth=1.5, label='Ideal S(N) = N')

    ax.set_xlabel('Number of Stages (N)')
    ax.set_ylabel('Relative Scalability S(N)')
    ax.set_title(f'Pipeline Scalability — Payload {size}B (Small T)')
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xticks(range(2, 13))
    plt.tight_layout()
    fig.savefig(f'plots/scalability_small_t_{size}B.png', dpi=150)
    plt.close(fig)

def plot_small_t_efficiency_comparison(df_no_pin, df_with_pin):
    if not df_no_pin.empty:
        df_no_pin['Pinning'] = 'No Pinning'
    if not df_with_pin.empty:
        df_with_pin['Pinning'] = 'Pinned'

    df = pd.concat([df_no_pin, df_with_pin], ignore_index=True)
    if df.empty or df[df['SleepMs'] > 0].empty:
        return

    df_valid = df[df['SleepMs'] > 0]
    
    queues = df_valid['Queue'].unique()
    if len(queues) == 0: return
    ref_queue = queues[0]

    sizes = df_valid['Size'].unique()
    if len(sizes) == 0: return
    ref_size = 64 if 64 in sizes else sizes[0]

    t_values = sorted(df_valid['T_ms'].unique(), reverse=True)
    t_colors = {2.0: '#2980b9', 1.0: '#e74c3c'}

    fig, ax = plt.subplots(figsize=(10, 6))

    for t_ms in t_values:
        for pin_state in ['Pinned', 'No Pinning']:
            subset = df_valid[(df_valid['Queue'] == ref_queue) &
                              (df_valid['Size'] == ref_size) &
                              (df_valid['T_ms'] == t_ms) &
                              (df_valid['Pinning'] == pin_state)].sort_values('N')
            if not subset.empty:
                linestyle = '-' if pin_state == 'Pinned' else '--'
                alpha_val = 1.0 if pin_state == 'Pinned' else 0.7
                ax.plot(subset['N'], subset['Efficiency'],
                        color=t_colors.get(t_ms, 'gray'),
                        marker='o',
                        linestyle=linestyle,
                        alpha=alpha_val,
                        label=f'T = {t_ms} ms ({pin_state})', linewidth=2, markersize=7)

    ax.axhline(y=1.0, color='gray', linestyle=':', alpha=0.4, label='Ideal')
    ax.set_xlabel('Number of Stages (N)')
    ax.set_ylabel('Efficiency E(N)')
    ax.set_title(f'Efficiency Degradation vs. Computation Time (Small T)\n({ref_queue}, Payload {ref_size}B)')
    ax.legend(fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0.5, 1.05)
    ax.set_xticks(range(2, 13))
    plt.tight_layout()
    fig.savefig('plots/efficiency_small_t.png', dpi=150)
    plt.close(fig)

if __name__ == "__main__":
    if not os.path.exists('plots'):
        os.makedirs('plots')

    file_no_pin = 'results/scalability_small_t_no_pinning.txt'
    file_with_pin = 'results/scalability_small_t_with_pinning.txt'

    df_no = pd.DataFrame()
    if os.path.exists(file_no_pin):
        df_no = parse_scalability_results(file_no_pin)

    df_yes = pd.DataFrame()
    if os.path.exists(file_with_pin):
        df_yes = parse_scalability_results(file_with_pin)
        
    for size in [8, 64, 512, 4096]:
        plot_small_t_scalability_comparison(df_no, df_yes, size)
    
    plot_small_t_efficiency_comparison(df_no, df_yes)
    print("Done generating small T plots!")
