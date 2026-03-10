from MoStream import Pipeline, seq, parallel
from image_stages import ImageSource, Grayscale, GaussianBlur, Sharpen, Brightness, ImageSink
from time import perf_counter_ns

fn main() raises:
    print("Running PAR(P=2) 5 stages...")
    var source = ImageSource[64, 64, 200]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), parallel(gray, 2), parallel(blur, 2), parallel(sharp, 2), seq(sink)))
    pipeline.setPinning(False)
    pipeline.run()
    print("Done!")
