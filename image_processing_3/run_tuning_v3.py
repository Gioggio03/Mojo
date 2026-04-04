#!/usr/bin/env python3
"""
Iterative tuning for V3 SIMD pipeline.
Starts from G=3 B=5 S=5, adds 1 worker to the bottleneck stage each step,
stops at max_workers = 22.
Logs every step to tuning_results.md.
"""
import subprocess, re, os, sys

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
SRC         = os.path.join(SCRIPT_DIR, 'bottleneck_tuned_benchmark.mojo')
BIN         = os.path.join(SCRIPT_DIR, 'tune_v3')
RESULTS_MD  = os.path.join(SCRIPT_DIR, 'tuning_results.md')
MOSTREAM    = os.path.dirname(SCRIPT_DIR)
MAX_WORKERS = 20  # 20 workers + source + sink = 22 total threads

# ── helpers ──────────────────────────────────────────────────────────────────

def set_config(g, b, s):
    with open(SRC) as f:
        src = f.read()
    src = re.sub(r'(comptime G: Int = )\d+', rf'\g<1>{g}', src)
    src = re.sub(r'(comptime B: Int = )\d+', rf'\g<1>{b}', src)
    src = re.sub(r'(comptime S: Int = )\d+', rf'\g<1>{s}', src)
    with open(SRC, 'w') as f:
        f.write(src)

def compile_config():
    env = os.environ.copy()
    env['MOSTREAM_HOME'] = MOSTREAM
    r = subprocess.run(
        ['mojo', 'build', '-O3', '-I', '..', 'bottleneck_tuned_benchmark.mojo', '-o', 'tune_v3'],
        cwd=SCRIPT_DIR, env=env, capture_output=True, text=True
    )
    if r.returncode != 0:
        print("COMPILE ERROR:", r.stderr)
        sys.exit(1)

def run_config():
    env = os.environ.copy()
    env['MOSTREAM_HOME'] = MOSTREAM
    r = subprocess.run([BIN], cwd=SCRIPT_DIR, env=env, capture_output=True, text=True, timeout=120)
    return r.stdout + r.stderr

def parse_output(out, g, b, s, n_imgs):
    """Parse compute times and compute per-stage capacity."""
    gray_times  = [float(x) for x in re.findall(r'\[Grayscale\] compute time: ([\d.]+)', out)]
    blur_times  = [float(x) for x in re.findall(r'\[GaussianBlur\] compute time: ([\d.]+)', out)]
    sharp_times = [float(x) for x in re.findall(r'\[Sharpen\] compute time: ([\d.]+)', out)]

    tput_m = re.search(r'(\d+(?:\.\d+)?) img/s$', out.strip().split('\n')[-1])
    tput = float(tput_m.group(1)) if tput_m else 0.0

    sink_m = re.search(r'Images received: (\d+)', out)
    n = int(sink_m.group(1)) if sink_m else n_imgs

    def cap(times, workers):
        if not times: return 0
        avg = sum(times) / len(times)          # avg per-worker compute (ms)
        n_per_w = n / workers                   # images per worker
        ms_per_img = avg / n_per_w             # ms/img per worker
        return workers * 1000.0 / ms_per_img   # total capacity (img/s)

    gc = cap(gray_times,  g)
    bc = cap(blur_times,  b)
    sc = cap(sharp_times, s)
    return tput, n, gc, bc, sc

def bottleneck(gc, bc, sc):
    m = min(gc, bc, sc)
    if m == gc: return 'G'
    if m == bc: return 'B'
    return 'S'

def log_row(g, b, s, tput, n, gc, bc, sc, bn_stage):
    row = (f"| G{g}B{b}S{s} | {g+b+s} | "
           f"{gc:.0f} | {bc:.0f} | {sc:.0f} | "
           f"{bn_stage} | **{tput:.0f}** | {n} |")
    with open(RESULTS_MD, 'a') as f:
        f.write(row + '\n')
    print(row)

# ── main loop ────────────────────────────────────────────────────────────────

g, b, s = 3, 6, 7  # resuming from last completed step
print(f"Starting tuning from G{g}B{b}S{g}, max {MAX_WORKERS} workers")
print(f"Logging to {RESULTS_MD}\n")

while True:
    print(f"\n>>> Running G{g}B{b}S{s} ({g+b+s} workers, {g+b+s+2} threads) ...", flush=True)
    set_config(g, b, s)
    compile_config()
    out = run_config()
    tput, n, gc, bc, sc = parse_output(out, g, b, s, 0)
    bn = bottleneck(gc, bc, sc)
    log_row(g, b, s, tput, n, gc, bc, sc, bn)

    if g + b + s >= MAX_WORKERS:
        print(f"\nReached {MAX_WORKERS} workers. Done.")
        break

    if   bn == 'G': g += 1
    elif bn == 'B': b += 1
    else:           s += 1

print(f"\nOptimal config found: G{g}B{b}S{s} → {tput:.0f} img/s")
