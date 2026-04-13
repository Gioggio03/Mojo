# Test Spot — V3 stages (SIMD Blur+Sharpen), configurazione singola da linea di comando
#
# Uso:
#   mojo run test_spot.mojo <G> <B> <S>
#
# Esempio:
#   mojo run test_spot.mojo 3 8 8
#
# Esegue una sola pipeline per 60 secondi con G worker per Grayscale,
# B worker per GaussianBlur, S worker per Sharpen, e stampa il throughput.
#
# Per il benchmark completo (sweep P=2..7 + configurazione ottimale)
# usare benchmark_full.mojo.

from MoStream import Pipeline, seq, parallel
from image_stages_3 import TimedImageSource, ImageSource, Grayscale, GaussianBlur, Sharpen, PassThrough, ImageSink
from time import perf_counter_ns
from sys import argv

comptime W: Int = 512
comptime H: Int = 512
comptime DURATION: Int = 60
comptime BASELINE_N: Int = 5000

fn elapsed_ms(t0: UInt) -> Float64:
    return Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0

fn throughput(n: Int, ms: Float64) -> Float64:
    if ms <= 0.0: return 0.0
    return Float64(n) / (ms / 1000.0)

fn run_source_baseline() raises -> Float64:
    var source = ImageSource[W, H, BASELINE_N]()
    var pt = PassThrough()
    var sink = ImageSink()
    _ = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(pt), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    _ = pipeline
    return ms

fn run_config(g: Int, b: Int, s: Int) raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, g), parallel(blur, b), parallel(sharp, s), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

def main():
    var args = argv()
    if len(args) != 4:
        print("Uso: mojo run test_spot.mojo <G> <B> <S>")
        print("  G = parallelismo Grayscale")
        print("  B = parallelismo GaussianBlur")
        print("  S = parallelismo Sharpen")
        print("Esempio: mojo run test_spot.mojo 3 8 8")
        return

    var g = Int(args[1])
    var b = Int(args[2])
    var s = Int(args[3])
    var threads = g + b + s + 2  # source + sink + workers

    print("=" * 70)
    print("  Test Spot (V3 stages — SIMD Blur+Sharpen) — configurazione singola")
    print("  Image: " + String(W) + "x" + String(H) + " | Duration=" + String(DURATION) + "s")
    print("  Config: G=" + String(g) + " B=" + String(b) + " S=" + String(s) + " | threads=" + String(threads))
    print("=" * 70)

    print("\n[Warmup]...")
    try: _ = run_source_baseline()
    except: pass
    print("[Warmup] done.\n")

    var t_source = run_source_baseline()
    var tput_source = throughput(BASELINE_N, t_source)
    print("Source baseline: " + String(tput_source) + " img/s\n")

    var res = run_config(g, b, s)
    var n = res[0]; var ms = res[1]
    var tput = throughput(n, ms)
    var eff = tput / tput_source * 100.0

    print("Risultato:")
    print("  Config  : G=" + String(g) + " B=" + String(b) + " S=" + String(s))
    print("  Threads : " + String(threads))
    print("  N images: " + String(n))
    print("  Time    : " + String(ms) + " ms")
    print("  Tput    : " + String(tput) + " img/s")
    print("  vs Src  : " + String(eff) + "%")
    print("=" * 70)

    print("CSV_START")
    print("config,num_images,time_ms,throughput_img_s,efficiency_pct")
    print("source_baseline," + String(BASELINE_N) + "," + String(t_source) + "," + String(tput_source) + ",100.0")
    print("g" + String(g) + "b" + String(b) + "s" + String(s) + "," + String(n) + "," + String(ms) + "," + String(tput) + "," + String(eff))
    print("CSV_END")
