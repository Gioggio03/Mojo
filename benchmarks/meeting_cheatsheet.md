# Cheatsheet: Scalability & Benchmark Analysis

Prepare for your meeting with these key points about the project's performance evaluation.

---

## 1. Zero-Computation Benchmark (`benchmark_pipe.mojo`)
*   **Objective**: Measure the **pure overhead** of the pipeline (queues + task scheduling).
*   **Logic**: Every stage passes the message immediately (no `sleep`).
*   **Key Metric**: **Mean Time (ms)** per 1000 messages.
*   **What to explain**: We compare different `MPMCQueue` implementations (standard, padded, naif) to see which one minimizes communication latency.

## 2. Scalability Benchmark (`scalability_bench.mojo`)
*   **Objective**: Measure how the pipeline scales when real work is added.
*   **The "Fixed T" Logic**:
    - We fix a total computation time $T$ (e.g., 100ms) for one message.
    - We divide that work across $N$ stages. Each stage does $T/N$ work (using `sleep`).
    - **Ideal Parallelism**: The throughput should be **N times faster** than sequential, because while stage 1 is working on message $M_2$, stage 2 is working on $M_1$.

### Key Metrics to Explain:
1.  **Throughput ($B$)**: Messages processed per second.
2.  **Scalability ($S(N)$)**: $B \times T$.
    - *Explain*: "It tells us how many 'sequential CPUs' the pipeline is effectively using."
    - *Ideal*: $S(N) = N$.
3.  **Efficiency ($E(N)$)**: $\frac{B}{N} \times T$.
    - *Explain*: "A value of 1.0 means 100% efficiency (no overhead). Values < 1.0 show the cost of communication."
    - *Trend*: Efficiency typically drops as $N$ increases because we add more queues and more context switches.

## 3. Python Plotting (`generate_plots.py`)
*   **Libraries**: `matplotlib`, `pandas`, `re` (regex).
*   **Parsing**: We use **regular expressions** to extract data from `.txt` logs.
*   **Plots**:
    - **Scalability Plot**: Shows $S(N)$ vs $N$. We look for how close the lines stay to the diagonal "Ideal" line.
    - **Efficiency Plot**: Shows how much performance we lose as the pipeline gets longer.
    - **Overhead Histogram**: Uses a **logarithmic scale** to compare queue latencies (needed because `MPMC_naif` is much slower than the padded versions).

---

## 4. Key Observations (Data-Driven)

### Efficiency Trends:
- **High Load ($T=100ms$)**: The pipeline is very efficient ($E \approx 0.97$ for $N=2$ and still $\approx 0.80$ for $N=12$). This shows the architecture is solid for heavy workloads.
- **Low Load ($T=10ms$)**: Efficiency drops faster ($E \approx 0.75$ for $N=10$). This proves that communication overhead becomes dominant when stages do very little work.
- **The "Integer Division" Edge Case**: For $T=5ms$ and $N \ge 6$, the work per stage becomes $0ms$. Our benchmarks correctly identify this, showing $E(N)=0$ because there is no computation to scale!

### Queue Comparison:
- **Lock-Free vs Naif**: `MPMC_naif` (with locks) is **2-3x slower** than the lock-free versions even at small $N$. This is the best argument for your implementation.
- **Overhead Scaling**: In the zero-computation test, adding a stage adds roughly **0.1ms** of delay per 1000 messages. This is the "cost of a stage".

---

## Potential "Killer" Questions from the Prof:
1.  **"Why does efficiency drop for small payloads?"**
    - *Answer*: For small payloads, the communication overhead of the queue is large compared to the payload size. For larger payloads, the cost of moving data is amortized.
2.  **"Why use padded queues?"**
    - *Answer*: To avoid **False Sharing**. Padding ensures that the read/write indices of the queue reside on different Cache Lines, preventing CPU cores from fighting over the same memory cache ($MPMC\_padding$).
3.  **"What is T?"**
    - *Answer*: $T$ is the "Sequential Time". It's the total time a message would take if one single thread did all the work. By keeping $T$ fixed and increasing $N$, we are measuring "Strong Scaling".
