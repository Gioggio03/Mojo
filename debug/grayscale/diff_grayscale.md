# Grayscale V1 vs V2 — Differenze fondamentali

## Cosa fa il filtro

Converte ogni pixel RGB in scala di grigi usando la formula a virgola fissa:

```
gray = (77*R + 150*G + 29*B) >> 8
```

che approssima i pesi percettivi `0.299*R + 0.587*G + 0.114*B`.
L'output mantiene 3 canali con R=G=B=gray per compatibilità con PPMImage.

---

## V1 — originale

```mojo
for y in range(h):
    for x in range(w):
        var r = input.get_r(x, y).cast[DType.uint32]()
        var g = input.get_g(x, y).cast[DType.uint32]()
        var b = input.get_b(x, y).cast[DType.uint32]()
        var gray = UInt8(((r * 77 + g * 150 + b * 29) >> 8).cast[DType.uint8]())
        out.set_pixel(x, y, gray, gray, gray)
```

**Problemi:**
- Loop annidato `y, x`: introduce un indice 2D che il compilatore deve gestire
- Tre chiamate a `get_r/get_g/get_b` per pixel: ognuna ricalcola `(y * width + x) * 3 + offset` separatamente
- `set_pixel` ricalcola ancora una volta lo stesso indice e scrive i 3 canali in 3 assegnazioni separate
- Cast esplicito `cast[DType.uint32]()` su ogni lettura
- In totale: **6 ricalcoli dell'indice per pixel** (3 in lettura + 1 in set_pixel che internamente ne fa altri 3)

---

## V2 — ottimizzata

```mojo
var n_pixels = input.width * input.height
var in_ptr  = input.data_ptr
var out_ptr = out.data_ptr
for i in range(n_pixels):
    var base = i * 3
    var r = Int((in_ptr + base    ).load())
    var g = Int((in_ptr + base + 1).load())
    var b = Int((in_ptr + base + 2).load())
    var gray = UInt8((r * 77 + g * 150 + b * 29) >> 8)
    (out_ptr + base    ).store(gray)
    (out_ptr + base + 1).store(gray)
    (out_ptr + base + 2).store(gray)
```

**Cambiamenti chiave:**

### 1. Loop piatto invece di loop annidato
Il loop `y, x` diventa un singolo `for i in range(n_pixels)`. Il compilatore vede un
iteratore lineare semplice invece di un loop nest 2D, che facilita l'auto-vectorization
e riduce il loop overhead.

### 2. Un solo calcolo dell'indice base per pixel
`base = i * 3` viene calcolato una volta sola. Tutte le letture e scritture
usano `base`, `base+1`, `base+2` — offset costanti dal punto di vista del compilatore.
In V1 lo stesso indice veniva ricalcolato 6 volte tramite le funzioni accessor.

### 3. Accesso diretto tramite puntatore
`in_ptr` e `out_ptr` sono `UnsafePointer` esposti direttamente. Le letture
`(ptr + base).load()` sono carichi di memoria singoli e lineari, senza
overhead di chiamata a funzione o logica di bounds checking implicita.

### 4. Scrittura diretta dei 3 canali
In V1, `set_pixel` scriveva i 3 canali con 3 assegnazioni separate dopo aver
ricalcolato l'indice. In V2, `store(gray)` sugli offset `base`, `base+1`, `base+2`
è equivalente ma con indirizzo già noto al compilatore — 3 store consecutivi
in memoria, ideali per essere ottimizzati o vettorizzati.

---

## Perché il guadagno è limitato

A differenza di Blur e Sharpen, il Grayscale **non ha vicini** da leggere.
È un filtro *point-wise*: ogni pixel output dipende solo dal pixel input corrispondente.
Questo significa che il collo di bottiglia è la **banda di memoria** (leggere e scrivere
`W×H×3` byte), non la complessità del calcolo.

V2 riduce l'overhead computazionale ma non può ridurre la quantità di dati letti/scritti.
Per questo il guadagno è modesto (~1-2x) rispetto ai ~2x dello Sharpen e ai ~4x del Blur.

---

---

## V3 — SIMD (8 pixel alla volta)

```mojo
alias CHUNK = 8
while i < limit:
    var base = i * 3
    var r = SIMD[DType.uint16, CHUNK](0)
    var g = SIMD[DType.uint16, CHUNK](0)
    var b = SIMD[DType.uint16, CHUNK](0)
    @parameter
    for j in range(CHUNK):
        r[j] = (in_ptr + base + j * 3    ).load().cast[DType.uint16]()
        g[j] = (in_ptr + base + j * 3 + 1).load().cast[DType.uint16]()
        b[j] = (in_ptr + base + j * 3 + 2).load().cast[DType.uint16]()
    var gray = (r * 77 + g * 150 + b * 29) >> 8
    @parameter
    for j in range(CHUNK):
        var gv = gray[j].cast[DType.uint8]()
        (out_ptr + base + j * 3    ).store(gv)
        (out_ptr + base + j * 3 + 1).store(gv)
        (out_ptr + base + j * 3 + 2).store(gv)
    i += CHUNK
# resto scalare per i pixel non multipli di 8
```

**Cambiamenti chiave rispetto a V2:**

### 1. Aritmetica vettoriale su 8 pixel simultaneamente
`r * 77 + g * 150 + b * 29` e `>> 8` operano su `SIMD[UInt16, 8]` — il
compilatore emette istruzioni AVX2/SSE4 che processano 8 moltiplicazioni e
addizioni in un singolo ciclo di clock invece di 8 cicli separati.

### 2. `@parameter for` — loop unrollato a compile-time
Il `for j in range(8)` sui load/store viene completamente unrollato dal
compilatore, eliminando il branch overhead del loop e permettendo di schedulare
le istruzioni in modo ottimale.

### 3. UInt16 invece di Int per l'aritmetica
V2 usava `Int` (64-bit) per il calcolo intermedio. V3 usa `UInt16` (16-bit),
dimezzando la larghezza dei registri SIMD e raddoppiando il numero di elementi
processati per istruzione (8 × UInt16 = 128 bit = 1 registro XMM).

### 4. Remainder loop scalare
I pixel non multipli di 8 (al massimo 7) vengono gestiti con il loop scalare
identico a V2 — nessuna perdita di correttezza.

---

## Risultati test (512x512)

| Versione | Gradiente | Random | Checksum |
|----------|-----------|--------|----------|
| V1 | ~1.37 ms | ~0.67 ms | ✓ |
| V2 | ~1.25 ms | ~0.65 ms | ✓ identico a V1 |
| V3 | ~1.00 ms | ~0.42 ms | ✓ identico a V1 |

Speedup V3 vs V2: **~1.55x** su immagini random, **~1.25x** su gradiente.
Il gradiente beneficia meno perché i valori uniformi permettono al compilatore
di ottimizzare già bene il caso scalare.

---

## Cosa rimane uguale

- Formula matematica identica: `(77*R + 150*G + 29*B) >> 8`
- Output pixel-per-pixel identico (verificato su gradiente, random, piccole immagini)
- Gestione bordi invariata (non necessaria: non c'è stencil)
