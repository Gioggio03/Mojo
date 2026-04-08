# Esperimento 2 — FastFlow V4 (Layout Planar)

Controparte C++ di `image_processing_4/` per l'Esperimento 2.

Leggi `image_processing_4/EXPERIMENT.md` per la documentazione completa dell'esperimento,
la motivazione, l'analisi dei risultati e le conclusioni.

## Differenze rispetto a V2

- `ppm_image.hpp`: layout planar (R|G|B piani separati) invece di interleaved (RGBRGB...)
- `image_stages.hpp`: inner loop stride-1 su piani separati → GCC auto-vettorizza a -O3
- Sharpen usa `int16_t + std::clamp<int16_t>` → `vpmaxsw`/`vpminsw` (branch-free)

## Risultati SEQ (512×512)

| Stage        | V2 -O3 interleaved | V4 -O3 planar |
|--------------|--------------------|---------------|
| Grayscale    | 0.644 ms           | 0.843 ms      |
| GaussianBlur | 0.600 ms           | 0.548 ms      |
| Sharpen      | 1.102 ms           | 1.812 ms      |

| Config    | C++ V2 -O3 | C++ V4 -O3 |
|-----------|-----------|-----------|
| SEQ       | 906       | 551       |
| Optimal   | 2508      | 2438      |

Vedi `image_processing_4/EXPERIMENT.md` per la spiegazione del peggioramento.
