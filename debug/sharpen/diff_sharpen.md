# Sharpen V1 vs V2 — Differenze fondamentali

## Cosa fa il filtro

Applica il kernel di sharpening 3×3:

```
[ 0  -1   0]
[-1   5  -1]
[ 0  -1   0]
```

Cioè per ogni pixel: `result = 5*center - top - bottom - left - right`, clampato a [0, 255].
È un filtro *stencil a croce* (4 vicini diretti, nessun diagonale).

---

## V1 — originale

```mojo
for y in range(h):
    for x in range(w):
        var sum_r: Int32 = input.get_r(x, y).cast[DType.int32]() * 5
        var sum_g: Int32 = input.get_g(x, y).cast[DType.int32]() * 5
        var sum_b: Int32 = input.get_b(x, y).cast[DType.int32]() * 5
        for i in range(4):           # loop sui 4 vicini
            var nx = x; var ny = y
            if i == 0:   ny = y - 1
            elif i == 1: ny = y + 1
            elif i == 2: nx = x - 1
            else:        nx = x + 1
            if nx < 0: nx = 0        # clamp
            ...
            sum_r -= input.get_r(nx, ny).cast[DType.int32]()
            ...
        if sum_r < 0: sum_r = 0      # clamp output
        if sum_r > 255: sum_r = 255
        ...
        out.set_pixel(x, y, ...)
```

**Problemi:**
- Loop interno `for i in range(4)`: per ogni pixel si esegue un mini-loop che il
  compilatore deve analizzare come loop generale, non come 4 operazioni fisse
- Clamp `nx/ny` ad ogni iterazione del loop interno: 4 coppie di branch per pixel,
  eseguite **su tutti i pixel** anche quelli lontani dal bordo
- Selezione della direzione via `if/elif/else` dentro il loop: il compilatore vede
  un pattern condizionale complesso invece di 4 accessi espliciti
- `get_r/get_g/get_b` chiamati 5 volte per canale (1 center + 4 vicini): ognuno
  ricalcola l'indice `(y * width + x) * 3 + offset`
- Cast `cast[DType.int32]()` su ogni lettura

---

## V2 — ottimizzata

```mojo
# Interior: y in [1, h-2], x in [1, w-2] — nessun clamp
for y in range(1, h - 1):
    for x in range(1, w - 1):
        var c  = (y * w + x) * 3
        var up = ((y-1) * w + x) * 3
        var dn = ((y+1) * w + x) * 3
        var lt = (y * w + (x-1)) * 3
        var rt = (y * w + (x+1)) * 3
        for ch in range(3):
            var v = load_byte(in_ptr, c+ch)*5
                  - load_byte(in_ptr, up+ch)
                  - load_byte(in_ptr, dn+ch)
                  - load_byte(in_ptr, lt+ch)
                  - load_byte(in_ptr, rt+ch)
            (out_ptr + c + ch).store(clamp255(v))

# Border: solo i pixel sul perimetro — con clamp
for y in range(h):
    for x in range(w):
        if x != 0 and x != w-1 and y != 0 and y != h-1: continue
        ...  # stesso calcolo di V1 ma con pointer diretti
```

**Cambiamenti chiave:**

### 1. Eliminazione del loop interno sui 4 vicini
Il `for i in range(4)` con `if/elif/else` scompare. Al suo posto ci sono
**5 indirizzi calcolati esplicitamente** (`c`, `up`, `dn`, `lt`, `rt`) prima del
loop sui canali. Il compilatore vede codice straight-line con operandi fissi invece
di un mini-loop con pattern di accesso condizionale.

### 2. Separazione interior / border — clamp fuori dal hot path
In V1, il clamp su `nx/ny` viene eseguito per tutti i W×H pixel.
In V2, solo i pixel sul perimetro (circa `2*(W+H)` pixel, una frazione minuscola)
passano per il path con clamp. La stragrande maggioranza dei pixel (l'interior)
esegue **zero branch** per il clamp.

Su un'immagine 512×512:
- Pixel totali: 262.144
- Pixel di bordo: ~2.044 (~0.8%)
- Pixel interior: ~260.100 (~99.2%) → nessun clamp

### 3. Accesso diretto tramite puntatore
Stesso principio del Blur V2: letture via `load_byte(in_ptr, offset)` invece di
`get_r/get_g/get_b`. Gli indirizzi `up`, `dn`, `lt`, `rt` sono calcolati una volta
per pixel e riusati per tutti e 3 i canali tramite `+ch`.

### 4. Clamp dell'output semplificato
`clamp255(v)` è una funzione `@always_inline` con due branch semplici. In V1
c'erano 6 branch separati (`if sum_r < 0`, `if sum_r > 255`, ecc.) scritti
esplicitamente. L'inlining della funzione produce lo stesso codice ma con una
struttura più chiara per il compilatore.

---

## Perché il guadagno è maggiore che nel Grayscale (~2.3x)

Lo Sharpen è uno **stencil filter**: ogni pixel dipende da 5 pixel dell'input
(center + 4 vicini). Questo porta due conseguenze:

1. **Più lavoro computazionale per pixel** → più margine per ottimizzare
2. **Il clamp sui vicini domina il costo in V1** → eliminarlo nell'interior è un
   guadagno netto significativo

A differenza del Grayscale (solo banda di memoria), qui il collo di bottiglia
è anche il calcolo — e V2 lo rende più semplice per il compilatore.

---

## Risultati test (512x512, immagine random)

| Versione | Tempo | Checksum |
|----------|-------|----------|
| V1       | ~8.5 ms | ✓ identico |
| V2       | ~3.4 ms | ✓ identico |

Speedup: **~2.3-2.5x** su immagini random, ~2x su gradiente.

---

## Confronto con Blur V2

| Aspetto | Blur V2 | Sharpen V2 |
|---------|---------|------------|
| Vicini nel kernel | 9 (3×3 completo) | 5 (croce) |
| Loop interno eliminato | `ky, kx` (2 loop) | `i` (1 loop) |
| Clamp separato | sì | sì |
| Accesso diretto ptr | sì | sì |
| Speedup atteso | ~4x | ~2.3x |

La strategia è identica. Il guadagno è proporzionalmente minore perché
il kernel è più piccolo (5 tap vs 9) e il loop interno era già solo 1 livello.

---

## Cosa rimane uguale

- Kernel matematico identico: `5*center - top - bottom - left - right`
- Clamp output identico: [0, 255]
- Gestione bordi identica: clamp sui vicini fuori immagine
- Output pixel-per-pixel identico (verificato su gradiente, random, 4×4, 3×3)
