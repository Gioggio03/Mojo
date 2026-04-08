# Esperimento 2 — Layout Planar + SIMD (V4)

## Obiettivo

Verificare se cambiare il layout dell'immagine da **interleaved** (RGBRGB...) a **planar**
(RRR...|GGG...|BBB...) permette a Mojo di sfruttare in modo più efficiente il SIMD,
e se migliora anche la vettorizzazione automatica di GCC in C++.

**Ipotesi**: con il layout planar, i pixel dello stesso canale sono adiacenti in memoria
(stride-1). Questo dovrebbe consentire veri vector load (`vmovdqu`) invece dei gather
stride-3 necessari con il layout interleaved.

---

## Struttura

- `image_processing_4/` — Mojo con layout planar e SIMD tramite `ptr.load[width=8]()`
- `fastflow_comparison_4/` — C++ FastFlow con layout planar, loop semplici auto-vettorizzabili

Entrambi usano la stessa struttura `PPMImage` con singola allocazione divisa in 3 piani:
```
data_ptr[0 .. W*H-1]       → piano R
data_ptr[W*H .. 2*W*H-1]   → piano G
data_ptr[2*W*H .. 3*W*H-1] → piano B
```

---

## Implementazione SIMD in Mojo (V4)

### V3 (interleaved) — stride-3 gather, load scalari

```mojo
# @parameter for unrollo compila a 8 load separati — stride 3, LLVM non fonde in vettore
@parameter
for j in range(8):
    t00[j] = (ch_in + rm1 + x - 1 + j*3).load().cast[DType.uint16]()
```

### Prima implementazione V4 — ancora scalari (fallimento)

```mojo
# Anche con stride-1, il @parameter for genera comunque 8 load scalari
@parameter
for j in range(8):
    t00[j] = (ch_in + rm1 + x - 1 + j).load().cast[DType.uint16]()
```

Risultato: nessun miglioramento rispetto a V3. LLVM non fonde i load scalari in un
vettore anche quando gli indirizzi sono consecutivi.

### Seconda implementazione V4 — vector load vero (fix)

```mojo
# load[width=8]() emette una singola istruzione vmovdqu + vpmovsxbw (zero-extend 8 uint8 → 8 uint16)
var t00 = (ch_in + rm1 + x - 1).load[width=8]().cast[DType.uint16]()
var t01 = (ch_in + rm1 + x    ).load[width=8]().cast[DType.uint16]()
# ... 9 vector loads per GaussianBlur, 5 per Sharpen
var res = (t00 + (t01 << 1) + t02 + ...) >> 4
(dst + x).store(res.cast[DType.uint8]())
```

Questo è possibile solo con il layout planar: i 8 valori del tap `(y-1, x-1)` per
gli output pixel `x..x+7` si trovano alle posizioni `ptr[(y-1)*w + x-1 + 0..7]`
— contigue in memoria → singolo vector load.

---

## Implementazione C++ (V4)

Loop interno semplice su piani separati — GCC auto-vettorizza con -O3:

```cpp
// GaussianBlur — inner loop stride-1, auto-vettorizzabile
for (int x = 1; x < w-1; x++) {
    uint32_t v = rm1[x-1] + 2u*rm1[x] + rm1[x+1]
               + 2u*r0[x-1] + 4u*r0[x] + 2u*r0[x+1]
               + rp1[x-1]   + 2u*rp1[x] + rp1[x+1];
    out_row[x] = (uint8_t)(v >> 4);
}

// Sharpen — int16_t + std::clamp → pmaxsw/pminsw branch-free
for (int x = 1; x < w-1; x++) {
    int16_t v = (int16_t)r0[x]*5 - rm[x] - rp[x] - r0[x-1] - r0[x+1];
    out_row[x] = (uint8_t)std::clamp((int16_t)v, (int16_t)0, (int16_t)255);
}
```

**Nota sul C++ Sharpen originale (V2)**: usava `clamp255(int v)` con branch (`if v < 0` / `if v > 255`).
Con layout interleaved GCC riusciva a vettorizzarlo a -O3. Nella versione V4 la stessa funzione
scalare risultava più lenta. Il fix è usare `int16_t` + `std::clamp<int16_t>` che emette
`vpmaxsw`/`vpminsw` (SSE2, branch-free), invece di promuovere a int32.

---

## Risultati

### Costi per stage — SEQ 512×512 (ms per immagine)

| Stage        | V3 interleaved+SIMD | V4 planar+vecload | Δ singolo stage |
|--------------|--------------------|--------------------|-----------------|
| Grayscale    | 0.627 ms           | 0.255 ms           | **+2.5x** ✓    |
| GaussianBlur | 1.675 ms           | 0.779 ms           | **+2.1x** ✓    |
| Sharpen      | 1.735 ms           | 1.377 ms           | **+1.3x** ✓    |
| **Bottleneck** | Blur/Sharp       | Sharpen            |                 |
| **SEQ tput** | 577 img/s          | 718 img/s          | **+24%** ✓     |

In isolamento il layout planar con vector load migliora tutti gli stage.

### Throughput pipeline completa

| Config        | Mojo V3 | Mojo V4 | C++ V2 -O3 | C++ V4 -O3 |
|---------------|---------|---------|-----------|-----------|
| SEQ           | 577     | 718     | 906       | 551       |
| Uniform P=2   | 1426    | 1489    | —         | 1110      |
| Uniform P=3   | 2117    | 1863    | —         | 1452      |
| Uniform P=4   | 2538    | 1896    | —         | 1003      |
| Uniform P=7   | 3993    | 2739    | 2782      | 1760      |
| **OPT**       | **4568** | **3118** | 2508     | 2438      |

Il throughput pipeline di Mojo V4 è inferiore a V3 nonostante i singoli stage siano più veloci.

---

## Analisi: perché il planar è più lento in pipeline?

### Il microbenchmark vs il benchmark pipeline

```
Sharpen planar microbench (singolo processo, dati caldi): 0.28 ms/img
Sharpen planar pipeline benchmark (60s, 8 worker): 1.37 ms/img
Gap: ~5x
```

Il gap non può essere spiegato dal codice di calcolo — il codice è corretto e vettorizza.

### Root cause: effetto cache

**Dimensioni per 512×512:**
- Piano singolo (R, G, o B): 512×512 = 262 144 bytes = **256 KB**
- Immagine completa (3 piani): **786 KB**
- L2 cache tipica per core: **256 KB**

**Layout interleaved (V3)**:
- GaussianBlur legge R, G, B in un'unica passata sequenziale sulla stessa regione di memoria
- Il dato (src + dst) entra parzialmente in L2, alta riutilizzazione
- Accesso: una singola passata da `[0, W*H*3)`

**Layout planar (V4)**:
- GaussianBlur fa 3 passate separate: `ch=0` su `[0, W*H)`, `ch=1` su `[W*H, 2*W*H)`, `ch=2` su `[2*W*H, 3*W*H)`
- Ogni passata (256KB) evicta la precedente dalla L2 → ogni piano trova i dati freddi in L3
- 3 passate × 2 buffer (src + dst) × 256KB = **1.5MB di dati attivi** → sempre L3-bound

```
Interleaved: passata unica 786KB → L3 miss 1 volta, poi hot
Planar:      3 passate 256KB   → L3 miss 3 volte (evict tra passate)
```

### Soglia teorica per cui il planar conviene

Il planar è vantaggioso se il piano singolo (W×H bytes) entra in L2:

```
W × H < L2_size / (2 × 3)   (fattore 2 = src+dst, fattore 3 = canali)
W × H < 256KB / 6 = 43 690 pixels
W < sqrt(43 690) ≈ 209 pixel
```

Per immagini **≤ ~200×200** il planar con vector load dovrebbe battere l'interleaved.
Per 512×512 il planar è penalizzato dalla cache.

### Verifica con microbenchmark

```cpp
// Risultato su questa macchina (512x512):
sharpen interleaved (V3):  0.32 ms/img  (una passata su dati caldi)
sharpen planar (V4):       0.28 ms/img  (più veloce in isolamento)
// In pipeline con dati freddi: planar diventa ~5x più lento per effetto cache
```

---

## Investigazione Sharpen C++ (perché era lento)

### Osservazione iniziale
C++ V4 Sharpen SEQ: 1.812 ms/img vs Blur: 0.548 ms/img — Sharpen 3x più lento.

### Analisi assembly
Con `g++ -O3 -march=native -fopt-info-vec-optimized`:
- GCC **vettorizza** il loop Sharpen (confermato dal report)
- Istruzioni emesse: `vpmullw`, `vpsubw`, `vpmaxsw`, `vpackuswb`
- Usa solo registri **xmm** (128-bit, 8 int16 per registro)
- **Non usa ymm** (256-bit) perché questa CPU ha AVX ma non AVX2
  (senza AVX2 non esistono istruzioni intere a 256-bit)

### Causa reale
Identica al Mojo: il Sharpen in pipeline è L3-bound (3 passate su piani da 256KB > L2).
Il codice è computazionalmente efficiente, il collo di bottiglia è la bandwidth della cache.

**Note sull'investigazione del clamp**:
- `int16_t v + std::clamp<int16_t>` → GCC emette `vpmaxsw`/`vpminsw` (SSE2, branch-free) ✓
- `int32_t v + std::clamp<int>` → GCC promuove a int32, emette `vpmovsxwd` (sign-extend) → 4 elementi per registro invece di 8
- `int16_t` è la scelta corretta per evitare il widening (range Sharpen: -1020..1275 → fits in int16)
- Tuttavia il fix non cambia il risultato finale perché il bottleneck è la cache, non il calcolo

---

## Conclusione

L'Esperimento 2 produce un risultato negativo ma scientificamente rilevante:

> **Il layout planar migliora il codice di calcolo ma peggiora le performance
> su immagini di grandi dimensioni a causa della cache.**

Il layout interleaved V3 con SIMD gather rimane superiore per 512×512 perché
processa tutti i canali in una singola passata sulla stessa regione di memoria,
massimizzando il riuso della L2. Il planar conviene solo per immagini piccole
(≤ ~200×200 su hardware con L2=256KB/core) dove il piano singolo entra in cache.

Per la tesi, questo esperimento illustra un principio fondamentale dell'ottimizzazione:
**l'efficienza computazionale (SIMD) e l'efficienza della gerarchia di memoria (cache)**
possono essere in conflitto, e la seconda domina per working set > L2.
