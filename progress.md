# Progress — V4 Sharpen fix

## Step 1: git pull — COMPLETATO
Il professore aveva già committato il timing per-stage sui FF stages.

## Step 2: Investigate V4 Sharpen regression — COMPLETATO

### Risultato misure (test_spot P=5, immagine 512×512)
- V2 Sharpen: 1.08 ms/img
- V4 Sharpen: 1.79 ms/img  → +66% più lento

### Root cause (analisi assembly)
Struttura loop V4:
```
for ch = 0, 1, 2:            ← 3 passate separate sul dato
    for y = 1..h-1:
        for x = 1..w-1:      ← SIMD: 16 pixel/iter, 1 canale
            sharpen(ch, x, y)
```
→ `pmullw` nella .L616: **2 istruzioni** per 16 pixel × 1 canale  
→ Loop iterations: 3 canali × 510 righe × 32 = **48 960**

Struttura loop V2:
```
for y = 1..h-1:
    for x = 1..w-1:          ← SIMD: 16 pixel × 3 canali insieme
        sharpen(ch=0,1,2, x, y)
```
→ `pmullw` nella .L600: **6 istruzioni** per 16 pixel × 3 canali  
→ Loop iterations: 510 righe × 32 = **16 320** (3× meno!)

V4 ha 3× più iterazioni del loop col medesimo overhead (aliasing check +
branch + counter). GCC genera "loop versioned for vectorization because of
possible aliasing" in entrambi, ma in V4 questo costo viene pagato 3 volte
per riga. Totale istruzioni stimate: V4 ~1.52M vs V2 ~0.90M → ratio 1.69
(vicino al 1.66 misurato).

### Fix pianificato (Step 3)
Unire il ciclo su ch dentro il ciclo su y: elaborare i 3 canali nella stessa
iterazione sull'asse x, con 12 puntatori __restrict__ + #pragma GCC ivdep.
Atteso: 6 pmullw/iter, 16 320 istruzioni, performance ≈ V2.

## Step 3: Fix V4 Sharpen — BLOCCATO

### Tentativi eseguiti

**Tentativo 1 — loop fusion 3-canali (12 puntatori __restrict__)**  
Unire il ciclo su ch dentro il ciclo su y: 12 puntatori attivi nel loop interno.  
Risultato: **peggio** (1.84 ms vs 1.79 ms originale).  
Causa: 12 puntatori superano i 16 registri GP di x86-64 → GCC spilla sullo stack
(214 accessi `(%rsp)` generati).

**Tentativo 2 — solo #pragma GCC ivdep**  
Aggiunto ivdep al loop originale per eliminare il runtime aliasing check.  
Risultato: invariato (1.79 ms).  
Causa: il check runtime era già assente in V4; ivdep non aveva effetto reale.

**Tentativo 3 — puntatori center-based**  
Riscrittura con puntatori `c0`, `cm1`, `cp1` per ridurre i calcoli d'indirizzo.  
Risultato: invariato (1.79 ms).

**Tentativo 4 — PLANE_PAD in ppm_image.hpp**  
Aggiunto padding di 128 byte tra i piani R, G, B per rompere l'aliasing sulle
cache L1/L2. Per immagini 512×512: plane_size = 262144 = 64×4096 = 8×32768,
ovvero multiplo esatto dei cicli di aliasing di L1 (ogni 4096 B) e L2
(ogni 32768 B). Il padding sposta l'offset a 262272 ≡ 128 (mod 4096) e
262272 ≡ 128 (mod 32768) → nessun aliasing.  
Risultato: invariato (1.79 ms). Il micro-benchmark a singolo canale conferma che
il costo è 0.28 ms indipendente dall'offset (0, 128, 4096 B).

### Analisi micro-benchmark finale

In isolamento (nessuna pipeline, allocazioni fresche):
- V4 SoA P=1: 0.411 ms/img
- V2 AoS P=1: 0.416 ms/img
- V4 SoA P=5: 0.363 ms/img
- V2 AoS P=5: 0.345 ms/img

**V4 ≈ V2 fuori pipeline.** La differenza (1.79 vs 1.08 ms) si manifesta
solo dentro la pipeline FastFlow con worker reali. Probabile causa: NUMA
binding dei worker, cache coherence tra thread, o pattern di allocazione
specifico di FF che non si replica nel micro-benchmark.

### Stato finale
- `image_stages.hpp`: ripristinato al codice originale
- `ppm_image.hpp`: mantenuto con PLANE_PAD=128 (correzione cache-aliasing
  tecnicamente corretta anche se non risolve il problema specifico dello Sharpen)
- Root cause del gap pipeline (1.79 vs 1.08 ms): **non risolta**

## Step 4: Profiling con /usr/bin/time -v (getrusage) — COMPLETATO

Poiché `perf_event_paranoid=4` blocca l'accesso al PMU, si è usato
`/usr/bin/time -v` (getrusage) per confrontare V4 e V2 con G=5 B=5 S=5.

| Metrica                   | V4 (planar) | V2 (interleaved) | Ratio  |
|---------------------------|-------------|------------------|--------|
| Immagini processate       | 191,452     | 297,193          | —      |
| Minor page faults totali  | 10,110,052  | 7,259,628        | —      |
| **Faults per immagine**   | **52.8**    | **24.4**         | **×2.16** |
| Voluntary ctx-switch      | 5,953       | 1,898            | ×3.1   |
| Involuntary ctx-switch    | 619,663     | 595,499          | ≈1     |
| Max RSS                   | ~22,212 MB  | ~22,178 MB       | ≈1     |

### Interpretazione

**Page faults (×2.16)**: ogni PPMImage (~768 KB) supera la soglia mmap di glibc
(128 KB), quindi ogni `new` usa `mmap()` e ogni `delete[]` fa `munmap()`. Le
pagine vengono rilasciate al kernel e ri-allocate fresh. V4 elabora immagini più
lentamente → intervallo più lungo tra free e riutilizzo → il kernel evicta più
pagine → più page fault al prossimo accesso. Il PLANE_PAD=128 aggiunge solo 1
pagina in più per allocation (193 vs 192): contributo trascurabile.

**Voluntary ctx-switch (×3.1)**: conseguenza del collo di bottiglia Sharpen.
Il Blur produce immagini più veloce di quanto Sharpen le consumi → code FF si
riempiono → i Blur worker si bloccano in attesa → switch volontari.

**RSS e involuntary switch**: identici → nessuna differenza strutturale nell'uso
totale di memoria o nella competizione sul CPU.

### Conclusione
I page fault in eccesso di V4 aggiungono overhead reale ma probabilmente non
spiegano l'intero gap (0.71 ms/img). Per isolare la causa residua servirebbero
i contatori hardware L1/L2/LLC miss, non accessibili senza perf_event_paranoid ≤ 1.
