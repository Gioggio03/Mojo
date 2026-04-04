# V3 Tuning Results (SIMD Blur + Sharpen)

Baseline V3 ms/img: Gray=0.627ms  Blur=1.675ms  Sharp=1.735ms
Max threads totali: 22 (workers + source + sink)

| Config | Workers | Threads | Gray cap | Blur cap | Sharp cap | Bottleneck | Throughput | N imgs |
|--------|---------|---------|----------|----------|-----------|------------|------------|--------|
| G3B5S5 | 13 | 15 | 4577 | 2997 | 2672 | Sharp | **2670** | 163246 |
| G3B5S6 | 14 | 16 | 4606 | 2927 | 3269 | Blur | **2925** | 177699 |
| G3B6S6 | 15 | 17 | 4462 | 3570 | 3412 | Sharp | **3409** | 207818 |
| G3B6S7 | 16 | 18 | 4594 | 3569 | 3829 | Blur | **3566** | 216199 |
| G3B7S7 | 17 | 19 | 4366 | 4120 | 3965 | Sharp | **3961** | 240958 |
| G3B7S8 | 18 | 20 | 4500 | 4062 | 4325 | Blur | **4058** | 245718 |
| G3B8S8 | 19 | 21 | 4526 | 4634 | 4530 | Gray | **4519** | 272441 |
| G4B8S8 | 20 | 22 | 5490 | 4489 | 4490 | Blur | **4485** | 271249 | ← aggiungere Gray sposta bottleneck su Blur, peggiora |

**Ottimale: G3B8S8 — 21 thread totali — 4519 img/s**
(G4B8S8 a 22 thread è peggiore: Gray→Blur shift, 4485 img/s)
