from MoStream import Pipeline, seq, parallel
from image_stages import ImageSource, Grayscale, GaussianBlur, ImageSink

def main():
    var source = ImageSource[64, 64, 10]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sink = ImageSink()
    var p = Pipeline((seq(source), seq(gray), parallel(blur, 2), seq(sink)))
    p.setPinning(True)
    p.run()
    print("Done")
