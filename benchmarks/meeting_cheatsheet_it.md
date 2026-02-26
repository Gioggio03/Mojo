# Appunti per l'incontro con il Prof: Scalabilità e Analisi Benchmark

Preparati per l'incontro con questi punti chiave sulla valutazione delle performance del progetto.

---

## 1. Benchmark Zero-Computation (`benchmark_pipe.mojo`)
*   **Obiettivo**: Misurare l'**overhead puro** della pipeline (code + scheduling dei task).
*   **Logica**: Ogni stage passa il messaggio immediatamente (niente `sleep`).
*   **Metrica Chiave**: **Mean Time (ms)** per 1000 messaggi.
*   **Cosa spiegare**: Confrontiamo diverse implementazioni di `MPMCQueue` (standard, padded, naif) per vedere quale minimizza la latenza di comunicazione.

## 2. Benchmark di Scalabilità (`scalability_bench.mojo`)
*   **Obiettivo**: Misurare come scala la pipeline quando viene aggiunto del lavoro reale.
*   **La logica "T Fisso"**:
    - Fissiamo un tempo di calcolo totale $T$ (es. 100ms) per un singolo messaggio.
    - Dividiamo quel lavoro tra $N$ stage. Ogni stage lavora per $T/N$ (usando `sleep`).
    - **Parallelismo Ideale**: Il throughput dovrebbe essere **N volte più veloce** rispetto al caso sequenziale, perché mentre lo stage 1 lavora sul messaggio $M_2$, lo stage 2 sta già lavorando su $M_1$.

### Metriche da Spiegare:
1.  **Throughput ($B$)**: Messaggi elaborati al secondo.
2.  **Scalabilità ($S(N)$)**: $B \times T$.
    - *Spiegazione*: "Indica quante 'CPU sequenziali' la pipeline sta effettivamente sfruttando."
    - *Ideale*: $S(N) = N$.
3.  **Efficienza ($E(N)$)**: $\frac{B}{N} \times T$.
    - *Spiegazione*: "Un valore di 1.0 significa efficienza del 100% (zero overhead). Valori < 1.0 mostrano il costo della comunicazione."
    - *Trend*: L'efficienza cala all'aumentare di $N$ perché aggiungiamo più code e più context switch.

---

## 3. Analisi dei Risultati (Osservazioni basate sui dati)

### Trend di Efficienza:
- **Carico Alto ($T=100ms$)**: La pipeline è molto efficiente ($E \approx 0.97$ per $N=2$ e ancora $\approx 0.80$ per $N=12$). Questo dimostra che l'architettura è solida per carichi di lavoro pesanti.
- **Carico Basso ($T=10ms$)**: L'efficienza cala più velocemente ($E \approx 0.75$ per $N=10$). Questo prova che l'overhead di comunicazione diventa dominante quando gli stage fanno poco lavoro.
- **Il caso limite della divisione intera**: Per $T=5ms$ e $N \ge 6$, il lavoro per stage diventa $0ms$ (per via della divisione intera `5/6 = 0`). I benchmark identificano correttamente questo punto mostrando $E(N)=0$.

### Confronto tra Code:
- **Lock-Free vs Naif**: La `MPMC_naif` (con lock) è **2-3 volte più lenta** delle versioni lock-free anche con pochi stage. Questo è l'argomento principale a favore della tua implementazione.
- **Costo per Stage**: Nel test a zero computazione, ogni stage aggiuntivo introduce circa **0.1ms** di ritardo per ogni 1000 messaggi. Questo è il "costo fisso" di uno stage.

---

## Domande "Scomode" del Prof:
1.  **"Perché l'efficienza cala con messaggi piccoli (8B)?"**
    - *Risposta*: Il costo della gestione della coda è fisso. Se il payload è piccolissimo, il tempo speso a spostare dati è trascurabile rispetto al tempo speso a gestire i puntatori della coda. Con payload grandi, il costo è più ammortizzato.
2.  **"Perché usare code con padding?"**
    - *Risposta*: Per evitare il **False Sharing**. Il padding assicura che gli indici di lettura e scrittura della coda si trovino su linee di cache diverse, evitando che i core della CPU "litighino" per la stessa memoria ($MPMC\_padding$).
3.  **"Cos'è T?"**
    - *Risposta*: $T$ è il "Tempo Sequenziale". È il tempo totale che un messaggio impiegherebbe se un singolo thread facesse tutto il lavoro. Tenendo $T$ fisso e aumentando $N$, stiamo misurando la "Strong Scaling".
