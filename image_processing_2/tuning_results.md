# Bottleneck-Tuned Parallelism — Tuning Log

V2 stage costs (sequential, 512x512):
- Grayscale: 0.617 ms/img → 1 worker = 1620 img/s capacity
- GaussianBlur: 2.219 ms/img → 1 worker = 450 img/s capacity
- Sharpen: 2.939 ms/img → 1 worker = 340 img/s capacity
- Source ceiling: ~16321 img/s

**Capacity = P_workers × (1000 / ms_per_img_per_worker) — il bottleneck è lo stage con capacity minore.**

| Config | Tput (img/s) | Gray (ms → cap) | Blur (ms → cap) | Sharp (ms → cap) | Bottleneck | N imgs |
|---|---|---|---|---|---|---|
| SEQ G1 B1 S1 (5t) | 340 | 0.617 ms → 1620 img/s | 2.219 ms → 450 img/s | 2.939 ms → 340 img/s | **Sharp** | 23529 |
| G=1 B=1 S=2 (6t) | 441 | 0.653 ms → 1532 img/s | 2.268 ms → 441 img/s | 2.970 ms → 673 img/s | **Blur** | 28577 |
| G=1 B=4 S=4 (11t) | 1355 | 0.644 ms → 1554 img/s | 2.259 ms → 1771 img/s | 2.950 ms → 1356 img/s | **Sharp** | 84464 |
| G=1 B=4 S=5 (12t) | 1676 | 0.596 ms → 1679 img/s | 2.216 ms → 1805 img/s | 2.934 ms → 1704 img/s | **Gray** | 101851 |
| G=2 B=4 S=5 (13t) | 1685 | 0.641 ms → 3121 img/s | 2.267 ms → 1764 img/s | 2.965 ms → 1687 img/s | **Sharp** | 104294 |
| G=2 B=4 S=6 (14t) | 1789 | 0.625 ms → 3198 img/s | 2.235 ms → 1790 img/s | 3.053 ms → 1965 img/s | **Blur** | 109503 |
| G=2 B=5 S=6 (15t) | 2009 | 0.659 ms → 3034 img/s | 2.294 ms → 2180 img/s | 2.984 ms → 2010 img/s | **Sharp** | 123704 |
| G=2 B=7 S=9 (20t) | 3045 | 0.653 ms → 3065 img/s | 2.278 ms → 3072 img/s | 2.951 ms → 3049 img/s | **Sharp** | 184742 |
| G=2 B=7 S=10 (21t) | 3055 | 0.654 ms → 3060 img/s | 2.280 ms → 3070 img/s | 3.041 ms → 3288 img/s | **Gray** | 184531 |

