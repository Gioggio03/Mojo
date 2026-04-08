# Bottleneck-Tuned Parallel Benchmark — V4 (planar SIMD stages)
#
# Modifica G, B, S poi esegui con: mojo run bottleneck_tuned_benchmark.mojo
# oppure usa run_tuning_v4.py per il tuning automatico.

from MoStream import Pipeline, seq, parallel
from image_stages_4 import TimedImageSource, Grayscale, GaussianBlur, Sharpen, ImageSink
from time import perf_counter_ns

comptime W: Int = 512
comptime H: Int = 512
comptime DURATION: Int = 60

# ============================================================================
# >>> CAMBIA QUI <<<
comptime G: Int = 3   # Grayscale workers
comptime B: Int = 8   # GaussianBlur workers
comptime S: Int = 8   # Sharpen workers
# ============================================================================

fn elapsed_ms(t0: UInt) -> Float64:
    return Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0

fn throughput(n: Int, ms: Float64) -> Float64:
    if ms <= 0.0: return 0.0
    return Float64(n) / (ms / 1000.0)

fn run_config() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray   = Grayscale()
    var blur   = GaussianBlur()
    var sharp  = Sharpen()
    var sink   = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, G), parallel(blur, B), parallel(sharp, S), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

def main():
    var total_threads = G + B + S + 2
    var res = run_config()
    var n = res[0]; var t = res[1]
    var tput = throughput(n, t)
    print("G=" + String(G) + " B=" + String(B) + " S=" + String(S)
          + " | threads=" + String(total_threads)
          + " | " + String(n) + " imgs | " + String(tput) + " img/s")
