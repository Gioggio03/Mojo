import os
import re
import pandas as pd
import matplotlib.pyplot as plt

# Configuration
RESULTS_DIR = 'results'
PLOTS_DIR = os.path.join(RESULTS_DIR, 'plots')
os.makedirs(PLOTS_DIR, exist_ok=True)

def parse_results():
    if not os.path.exists(RESULTS_DIR):
        print(f"Directory {RESULTS_DIR} not found.")
        return []

    data = []
    
    # Regex patterns
    size_pattern = re.compile(r'Image Size:\s+(\d+)x(\d+)')
    msg_pattern = re.compile(r'Messages per run:\s+(\d+)')
    
    # Tables parsing
    # Table 1: Stages | Time (ms) | Throughput (img/s) | Scalability
    seq_pattern = re.compile(r'\s*(\d+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)')
    # Table 2: Stages | P=2 T | P=2 img/s | P=2 Sp | P=2 Eff | P=4 T | P=4 img/s | P=4 Sp | P=4 Eff
    par_pattern = re.compile(r'\s*(\d+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)')

    for filename in os.listdir(RESULTS_DIR):
        if not filename.endswith('.txt'):
            continue
            
        filepath = os.path.join(RESULTS_DIR, filename)
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        current_w = current_h = None
        current_n = None
        in_seq_table = False
        in_par_table = False
        
        # Temporary storage for seq metrics to merge with par
        # curr_metrics = { stages: { 'seq_time': x, 'seq_tput': y, 'scalability': z} }
        curr_metrics = {}
        
        for line in lines:
            if "Image Size:" in line:
                m = size_pattern.search(line)
                if m:
                    current_w, current_h = int(m.group(1)), int(m.group(2))
            elif "Messages per run:" in line:
                m = msg_pattern.search(line)
                if m:
                    current_n = int(m.group(1))
            elif "--- Summary (Sequential P=1) ---" in line:
                in_seq_table = True
                in_par_table = False
                curr_metrics = {} # reset for new image size block
            elif "--- Summary (Parallel Performance vs Sequential Baseline) ---" in line:
                in_seq_table = False
                in_par_table = True
            elif line.strip() == "" or "-------|" in line or "Stages |" in line:
                continue
            else:
                if in_seq_table:
                    m = seq_pattern.match(line)
                    if m:
                        stages = int(m.group(1))
                        curr_metrics[stages] = {
                            'time_seq': float(m.group(2)),
                            'tput_seq': float(m.group(3)),
                            'scalability': float(m.group(4))
                        }
                elif in_par_table:
                    m = par_pattern.match(line)
                    if m:
                        stages = int(m.group(1))
                        seq_data = curr_metrics.get(stages, {})
                        
                        row = {
                            'resolution': f"{current_w}x{current_h}",
                            'messages': current_n,
                            'stages': stages,
                            'time_seq': seq_data.get('time_seq', None),
                            'tput_seq': seq_data.get('tput_seq', None),
                            'scalability': seq_data.get('scalability', None),
                            'time_p2': float(m.group(2)),
                            'tput_p2': float(m.group(3)),
                            'speedup_p2': float(m.group(4)),
                            'effic_p2': float(m.group(5)),
                            'time_p4': float(m.group(6)),
                            'tput_p4': float(m.group(7)),
                            'speedup_p4': float(m.group(8)),
                            'effic_p4': float(m.group(9))
                        }
                        data.append(row)
    
    return pd.DataFrame(data)

def generate_plots(df):
    if df.empty:
        print("No data found to plot.")
        return
        
    print(f"Generating plots using {len(df)} records...")
    
    # 1. Throughput vs Resolution (constant N=1000, 6 stages)
    df_tput = df[(df['stages'] == 6) & (df['messages'] == 1000)].copy()
    if not df_tput.empty:
        # Sort by resolution size
        df_tput['res_val'] = df_tput['resolution'].apply(lambda x: int(x.split('x')[0]))
        df_tput = df_tput.sort_values('res_val')
        
        plt.figure(figsize=(10, 6))
        plt.plot(df_tput['resolution'], df_tput['tput_seq'], marker='o', label='Sequential (P=1)')
        plt.plot(df_tput['resolution'], df_tput['tput_p2'], marker='s', label='Parallel (P=2)')
        plt.plot(df_tput['resolution'], df_tput['tput_p4'], marker='^', label='Parallel (P=4)')
        
        plt.title('Throughput vs. Image Resolution (6 Stages, N=1000)')
        plt.xlabel('Resolution')
        plt.ylabel('Throughput (Images/sec)')
        plt.yscale('log')
        plt.grid(True, which="both", ls="--", alpha=0.7)
        plt.legend()
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, '1_throughput_vs_resolution.png'))
        plt.close()

    # 2. Stage Scalability (Time cost of stages) (constant N=1000, 512x512)
    df_scal = df[(df['resolution'] == '512x512') & (df['messages'] == 1000)].copy()
    if not df_scal.empty:
        df_scal = df_scal.sort_values('stages')
        
        plt.figure(figsize=(10, 6))
        plt.plot(df_scal['stages'], df_scal['scalability'], marker='o', color='purple')
        plt.title('Sequential Pipeline Scalability vs Pipeline Depth (512x512, N=1000)')
        plt.xlabel('Number of Stages')
        plt.ylabel('Scalability Factor (Relative to 3 Stages)')
        plt.grid(True, alpha=0.3)
        plt.xticks([3, 4, 5, 6])
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, '2_stage_scalability.png'))
        plt.close()

    # 3. Speedup (Amdahl's Law) - constant N=1000, 6 stages
    df_speedup = df[(df['stages'] == 6) & (df['messages'] == 1000)].copy()
    if not df_speedup.empty:
        df_speedup['res_val'] = df_speedup['resolution'].apply(lambda x: int(x.split('x')[0]))
        df_speedup = df_speedup.sort_values('res_val')
        
        plt.figure(figsize=(10, 6))
        
        for res in df_speedup['resolution'].unique():
            row = df_speedup[df_speedup['resolution'] == res].iloc[0]
            y_vals = [1.0, row['speedup_p2'], row['speedup_p4']]
            x_vals = [1, 2, 4]
            plt.plot(x_vals, y_vals, marker='o', label=res)
            
        # Ideal line
        plt.plot([1, 2, 4], [1, 2, 4], 'k--', label='Ideal Linear Speedup')
        
        plt.title('Parallel Speedup vs Replica Degree (6 Stages, N=1000)')
        plt.xlabel('Parallel Replicas per Transform Stage (P)')
        plt.ylabel('Speedup')
        plt.xticks([1, 2, 4])
        plt.grid(True, alpha=0.3)
        plt.legend()
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, '3_speedup_vs_replicas.png'))
        plt.close()

    # 4. Efficiency - constant N=1000, 512x512
    df_eff = df[(df['resolution'] == '512x512') & (df['messages'] == 1000)].copy()
    if not df_eff.empty:
        df_eff = df_eff.sort_values('stages')
        
        plt.figure(figsize=(10, 6))
        plt.plot(df_eff['stages'], df_eff['effic_p2'], marker='s', label='P=2 Efficiency')
        plt.plot(df_eff['stages'], df_eff['effic_p4'], marker='^', label='P=4 Efficiency')
        
        plt.title('Hardware Efficiency vs Pipeline Depth (512x512, N=1000)')
        plt.xlabel('Number of Stages')
        plt.ylabel('Efficiency (Speedup / P)')
        plt.ylim(0, 1.1)
        plt.xticks([3, 4, 5, 6])
        plt.grid(True, alpha=0.3)
        plt.legend()
        plt.tight_layout()
        plt.savefig(os.path.join(PLOTS_DIR, '4_efficiency_vs_depth.png'))
        plt.close()
        
    print(f"Done. Plots saved to '{PLOTS_DIR}'.")

if __name__ == '__main__':
    df = parse_results()
    generate_plots(df)
