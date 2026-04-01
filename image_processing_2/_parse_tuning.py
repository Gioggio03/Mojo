"""Legge l'output del benchmark da stdin e appende la riga a tuning_results.md."""
import sys, re

text = sys.stdin.read()

m = re.search(r'\| G=(\d+) B=(\d+) S=(\d+) \((\d+) threads\) \| ([\d.]+) img/s \| (\d+) imgs \|', text)
if not m:
    print("ERROR: could not parse result line", file=sys.stderr)
    print("--- output ricevuto ---", file=sys.stderr)
    print(text, file=sys.stderr)
    sys.exit(1)

g, b, s = int(m.group(1)), int(m.group(2)), int(m.group(3))
threads, tput, n_imgs = m.group(4), float(m.group(5)), int(m.group(6))

def ms_per_img(name):
    """Tempo medio per immagine su UN singolo worker (media dei worker)."""
    times = [float(x) for x in re.findall(rf'\[{name}\] compute time:\s*([\d.]+)\s*ms', text)]
    if not times or n_imgs == 0:
        return 0.0
    # Ogni worker ha processato n_imgs/len(times) immagini
    # ms_per_img = compute_time_worker / (n_imgs / num_workers)
    #            = mean(worker_times) / (n_imgs / num_workers)
    avg_worker_time = sum(times) / len(times)
    imgs_per_worker = n_imgs / len(times)
    return avg_worker_time / imgs_per_worker if imgs_per_worker > 0 else 0.0

gray_ms  = ms_per_img("Grayscale")
blur_ms  = ms_per_img("GaussianBlur")
sharp_ms = ms_per_img("Sharpen")

# Capacità effettiva di ogni stage = P_workers / ms_per_img * 1000
gray_cap  = g  * (1000.0 / gray_ms)  if gray_ms  > 0 else 0.0
blur_cap  = b  * (1000.0 / blur_ms)  if blur_ms  > 0 else 0.0
sharp_cap = s  * (1000.0 / sharp_ms) if sharp_ms > 0 else 0.0

bottleneck = min(
    ("Gray",  gray_cap),
    ("Blur",  blur_cap),
    ("Sharp", sharp_cap),
    key=lambda x: x[1]
)[0]

row = (f"| G={g} B={b} S={s} ({threads}t)"
       f" | {tput:.0f}"
       f" | {gray_ms:.3f} ms → {gray_cap:.0f} img/s"
       f" | {blur_ms:.3f} ms → {blur_cap:.0f} img/s"
       f" | {sharp_ms:.3f} ms → {sharp_cap:.0f} img/s"
       f" | **{bottleneck}**"
       f" | {n_imgs} |")

with open("tuning_results.md", "a") as f:
    f.write(row + "\n")

print(f"\n=== Salvato in tuning_results.md ===")
print(row)
