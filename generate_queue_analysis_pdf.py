#!/usr/bin/env python3
"""Genera ANALYSIS_QUEUE_PROBLEMI.pdf — analisi dei problemi della coda nelle pipeline."""

from fpdf import FPDF
import os

OUTPUT = os.path.join(os.path.dirname(__file__), "ANALYSIS_QUEUE_PROBLEMI.pdf")

SECTIONS = [
    {
        "title": "Analisi: Problemi della Coda nella Pipeline",
        "subtitle": "MoStream vs FastFlow — Dove la Coda Causa Colli di Bottiglia",
        "is_cover": True,
    },
    {
        "title": "0. Struttura della Pipeline e Ruolo della Coda",
        "blocks": [
            {
                "heading": "Come funziona la pipeline",
                "body": (
                    "La pipeline è composta da stage connessi da code MPMC (Multi-Producer "
                    "Multi-Consumer). Ogni stage gira su uno o più thread dedicati.\n\n"
                    "Struttura con parallelismo P per stage:\n\n"
                    "  Source (1 thread)\n"
                    "     |\n"
                    "    coda_1  <-- immagine passa qui\n"
                    "     |\n"
                    "  Grayscale (G thread)\n"
                    "     |\n"
                    "    coda_2\n"
                    "     |\n"
                    "  GaussianBlur (B thread)\n"
                    "     |\n"
                    "    coda_3\n"
                    "     |\n"
                    "  Sharpen (S thread)\n"
                    "     |\n"
                    "    coda_4\n"
                    "     |\n"
                    "  Sink (1 thread)\n\n"
                    "Ad ogni attraversamento di una coda avviene un trasferimento di dati "
                    "tra thread. Questo trasferimento ha costi che dipendono dal framework "
                    "e dalla dimensione del messaggio."
                ),
            },
            {
                "heading": "MoStream vs FastFlow: strategia di passaggio dati diversa",
                "body": (
                    "I due framework gestiscono il trasferimento in modo opposto:\n\n"
                    "  MoStream: la coda contiene VALORI (copie dell'immagine)\n"
                    "    Source produce img → [copia 786 KB in coda] → Blur legge copia\n"
                    "    Il tipo PPMImage implementa ImplicitlyCopyable: ogni volta che\n"
                    "    un'immagine entra in coda, viene chiamato __copyinit__ (memcpy).\n\n"
                    "  FastFlow: la coda contiene PUNTATORI (8 byte)\n"
                    "    Source produce img → [ptr 8B in coda] → Blur legge via ptr\n"
                    "    new PPMImage() alloca sull'heap, delete libera dopo l'uso.\n\n"
                    "  Costo per immagine 512x512 (786.432 byte):\n\n"
                    "  Framework   | In coda      | Alloc/free      | Totale per stage\n"
                    "  ------------|--------------|-----------------|------------------\n"
                    "  MoStream    | memcpy 786KB | tcmalloc veloce | memcpy dominante\n"
                    "  FastFlow    | ptr 8B       | mmap syscall    | syscall dominante\n\n"
                    "  Source ceiling misurata: MoStream ~13.955 img/s, FastFlow ~15.929 img/s\n"
                    "  Differenza ~14%: FastFlow paga meno per la coda (solo ptr),\n"
                    "  MoStream paga meno per l'alloc (tcmalloc vs mmap), si bilanciano."
                ),
            },
        ],
    },
    {
        "title": "1. Problema: La Copia Profonda a Ogni Stage Boundary",
        "blocks": [
            {
                "heading": "Il costo nascosto per immagine",
                "body": (
                    "In MoStream, ogni immagine attraversa 4 code nella pipeline completa "
                    "(Source -> Gray -> Blur -> Sharp -> Sink). Ad ogni coda: 1 memcpy.\n\n"
                    "  Timeline di una singola immagine:\n\n"
                    "  Source:  [alloc 786KB] [memcpy 786KB] --> coda_1\n"
                    "  Gray:    [legge 786KB] [alloc 786KB] [memcpy 786KB] --> coda_2\n"
                    "  Blur:    [legge 786KB] [alloc 786KB] [memcpy 786KB] --> coda_3\n"
                    "  Sharpen: [legge 786KB] [alloc 786KB] [memcpy 786KB] --> coda_4\n"
                    "  Sink:    [legge 786KB] [free]\n\n"
                    "  Totale memcpy per immagine: 4 x 786KB = ~3 MB di dati spostati\n\n"
                    "A 6323 img/s (throughput ottimale V4): 6323 x 3MB = ~18 GB/s solo di copie.\n"
                    "La bandwidth RAM di questa macchina (DDR3) è ~40 GB/s: la copia usa il 45%\n"
                    "della bandwidth disponibile, sottraendola al compute degli stage."
                ),
            },
            {
                "heading": "Impatto per versione",
                "body": (
                    "Il peso relativo della copia cambia al migliorare del compute:\n\n"
                    "  V2 (Sharpen 2.97 ms/img): copia ~0.07 ms/img --> 2.3% del tempo totale\n"
                    "  V3 (Sharpen 1.74 ms/img): copia ~0.07 ms/img --> 4.0% del tempo totale\n"
                    "  V4 (Sharpen 0.55 ms/img): copia ~0.07 ms/img --> 12.7% del tempo totale\n\n"
                    "Man mano che ottimizziamo il compute, la copia diventa una frazione\n"
                    "sempre maggiore del tempo totale. Questo è il motivo per cui a V4\n"
                    "un buffer pool (zero-copy) avrebbe impatto misurabile, mentre a V2 no."
                ),
            },
        ],
    },
    {
        "title": "2. Problema: Cache Coherence tra Thread",
        "blocks": [
            {
                "heading": "Il trasferimento inter-core invalida la cache",
                "body": (
                    "Quando un thread del Grayscale (Core 0) scrive un'immagine e la passa\n"
                    "al thread del Blur (Core 1), si innesca il protocollo MESI:\n\n"
                    "  Core 0 (Gray, finisce):    scrive 786KB in L2 di Core 0\n"
                    "  Core 0 invia a coda:       segnale atomico alla coda MPMC\n"
                    "  Core 1 (Blur, riceve):     vuole leggere 786KB\n"
                    "                             ma la sua L2 non ha quei dati!\n"
                    "  Core 1 deve caricare:      786KB da L3 (o RAM se L3 non ha)\n\n"
                    "  Questo accade per OGNI immagine che attraversa un confine di stage.\n\n"
                    "  Latenza del cache miss:\n"
                    "    L1 hit:  ~4 cicli\n"
                    "    L2 hit:  ~12 cicli\n"
                    "    L3 hit:  ~36 cicli   <-- caso migliore inter-core\n"
                    "    RAM:     ~200 cicli  <-- caso peggiore\n\n"
                    "  Per 786KB con cache line da 64B: 786432/64 = 12.288 cache line.\n"
                    "  Se tutte sono in L3: 12288 x 36 cicli = 442.368 cicli extra per img.\n"
                    "  A 2.4 GHz: ~184 microsecondi di latenza solo per il trasferimento."
                ),
            },
            {
                "heading": "Confronto con messaggi piccoli",
                "body": (
                    "Il problema di cache coherence esiste in qualsiasi pipeline, ma\n"
                    "la sua gravità dipende dalla dimensione del messaggio:\n\n"
                    "  Messaggio 8 byte (ptr FastFlow):  1/8 di cache line --> quasi gratis\n"
                    "  Messaggio 786 KB (img MoStream):  12.288 cache line --> costoso\n\n"
                    "Questo spiega parzialmente perché FastFlow ha source ceiling più alta:\n"
                    "il trasferimento inter-core costa pochissimo quando si passano puntatori."
                ),
            },
        ],
    },
    {
        "title": "3. Problema: Contesa MPMC ad Alto Parallelismo",
        "blocks": [
            {
                "heading": "Come funziona la coda MPMC lock-free",
                "body": (
                    "La coda usa operazioni atomiche CAS (Compare-And-Swap) su head e tail.\n"
                    "Per accodare un elemento:\n\n"
                    "  1. Leggi tail (load atomico)\n"
                    "  2. CAS(tail, old, old+1) -- se tail cambiato nel frattempo, riprova\n"
                    "  3. Scrivi il dato nella posizione\n\n"
                    "Con P worker che scrivono/leggono contemporaneamente dalla stessa coda,\n"
                    "le variabili head e tail sono scritte da P thread simultaneamente.\n"
                    "Questo causa cache line bouncing: la cache line con head/tail viene\n"
                    "invalidata su tutti i core ogni volta che un thread la aggiorna.\n\n"
                    "  P=1: 0 contese, CAS sempre riesce al primo tentativo\n"
                    "  P=4: ~3 contese medie per operazione\n"
                    "  P=7: ~6 contese medie --> overhead O(P^2) nel caso peggiore"
                ),
            },
            {
                "heading": "Evidenza sperimentale: regressioni FastFlow a P=5 e P=7",
                "body": (
                    "FastFlow V4, throughput per config uniform:\n\n"
                    "  P=2: 1106 img/s  (aumento regolare)\n"
                    "  P=3: 1610 img/s  (aumento regolare)\n"
                    "  P=4: 2197 img/s  (aumento regolare)\n"
                    "  P=5: 1874 img/s  <-- REGRESSIONE! peggio di P=4\n"
                    "  P=6: 3180 img/s  (recupera)\n"
                    "  P=7: 1925 img/s  <-- REGRESSIONE! peggio di P=6\n\n"
                    "Le regressioni a P=5 e P=7 coincidono con il superamento di soglie NUMA:\n"
                    "il server Xeon E5-2695 v2 ha 12 core fisici (24 HT). FastFlow con P=5\n"
                    "crea 3x5+2 = 17 thread, alcuni vengono schedulati su core gia' occupati\n"
                    "(hyperthreading), causando contesa L1/L2 tra coppie HT dello stesso core.\n\n"
                    "MoStream non mostra questa regressione perche' usa CPU pinning esplicito:\n"
                    "ogni worker viene bloccato su un core fisico distinto, evitando HT sharing.\n\n"
                    "  MoStream V4:\n"
                    "  P=4: 3033, P=5: 3936, P=6: 4737, P=7: 5506  <-- scaling monotono"
                ),
            },
            {
                "heading": "Perche' MoStream scala meglio",
                "body": (
                    "MoStream imposta esplicitamente l'affinita' dei thread (CPU pinning):\n\n"
                    "  Thread 0 --> Core 0 (fisico)\n"
                    "  Thread 1 --> Core 1 (fisico)\n"
                    "  ...\n"
                    "  Thread N --> Core N (fisico)\n\n"
                    "Questo garantisce che due worker dello stesso stage non condividano\n"
                    "mai la stessa L1/L2, eliminando la contesa di cache all'interno di\n"
                    "uno stage. Le code tra stage (inter-core) continuano a pagare il\n"
                    "costo di cache coherence, ma in modo prevedibile e senza regressioni.\n\n"
                    "FastFlow non applica pinning di default: il sistema operativo schedula\n"
                    "i thread liberamente, potendo mapparli su core gia' occupati."
                ),
            },
        ],
    },
    {
        "title": "4. Problema: Queue Overflow e Memory Pressure",
        "blocks": [
            {
                "heading": "Il collo di bottiglia crea backpressure",
                "body": (
                    "Nella config sequenziale G=1 B=1 S=1, i tempi per stage sono (V4):\n\n"
                    "  Grayscale:   ~0.07 ms/img  -> capacita' ~14.000 img/s\n"
                    "  GaussianBlur:~0.55 ms/img  -> capacita'  ~1.818 img/s\n"
                    "  Sharpen:     ~1.81 ms/img  -> capacita'    ~552 img/s  <-- bottleneck\n\n"
                    "Il Blur produce a 1818 img/s, il Sharpen consuma a 552 img/s.\n"
                    "La coda tra Blur e Sharpen si riempie di 1266 immagini al secondo.\n\n"
                    "  Ogni immagine in coda occupa: 786 KB\n"
                    "  Dopo 1 secondo di accumulo: 1266 x 786KB ≈ 960 MB in coda!\n\n"
                    "  L3 cache totale: 30 MB\n"
                    "  Coda dopo 0.03s: gia' 37MB > L3 --> tutte le immagini in coda vanno in RAM"
                ),
            },
            {
                "heading": "Effetto: il Blur si blocca (backpressure)",
                "body": (
                    "La coda ha capacita' massima BUFFER_CAPACITY=1024 elementi.\n\n"
                    "  1024 x 786KB = 780 MB di immagini al massimo in volo\n\n"
                    "Quando la coda e' piena, il Blur si blocca in spin-wait finche'\n"
                    "il Sharpen non consuma almeno un elemento. Questo crea il flusso:\n\n"
                    "  Source --> [Gray] --> coda_2 --> [Blur] --> coda_3 (PIENA!) --> [Sharpen]\n"
                    "                                               |\n"
                    "                                          Blur bloccato\n"
                    "                                          (spin-wait)\n\n"
                    "  Il Blur spreca cicli CPU in attesa invece di elaborare.\n"
                    "  Questo e' corretto come meccanismo di backpressure,\n"
                    "  ma riduce l'utilizzo effettivo della CPU."
                ),
            },
            {
                "heading": "Effetto sulla cache: working set esplode",
                "body": (
                    "Con la coda piena, ci sono fino a 1024 immagini 'in volo' tra Blur e Sharpen.\n\n"
                    "  Working set totale del sistema:\n"
                    "    Immagine in elaborazione al Blur:    786 KB\n"
                    "    Immagine in elaborazione al Sharpen: 786 KB\n"
                    "    Coda tra i due (worst case):         780 MB\n"
                    "    Totale: ~781 MB\n\n"
                    "  L3 cache disponibile: 30 MB\n"
                    "  Tutto cio' che supera 30 MB va in RAM.\n\n"
                    "  Conseguenza: ogni volta che il Sharpen prende un'immagine dalla coda,\n"
                    "  e' praticamente certa una serie di cache miss sulla RAM (cold miss),\n"
                    "  perche' quell'immagine e' stata scritta in coda molto tempo prima\n"
                    "  e i suoi dati sono stati evicti dalla L3 nel frattempo."
                ),
            },
        ],
    },
    {
        "title": "5. Riepilogo per Versione",
        "blocks": [
            {
                "heading": "Quale problema domina in ogni versione",
                "table": {
                    "headers": ["Versione", "Compute/img", "Copia (% tempo)", "Problema dominante"],
                    "rows": [
                        ["V2", "~3.0 ms", "~2%", "Compute (SIMD assente)"],
                        ["V3", "~1.7 ms", "~4%", "Compute (gather stride-3)"],
                        ["V4", "~0.55 ms", "~13%", "Cache eviction + copia coda"],
                    ],
                },
            },
            {
                "heading": "Confronto impatto coda: MoStream vs FastFlow per versione",
                "table": {
                    "headers": ["Config", "MoStream (img/s)", "FastFlow (img/s)", "Vantaggio Mojo"],
                    "rows": [
                        ["V3 SEQ G1B1S1",  "577",  "~500", "1.15x"],
                        ["V3 Optimal",     "4568", "2508", "1.82x"],
                        ["V4 SEQ G1B1S1",  "787",  "558",  "1.41x"],
                        ["V4 P=4",         "3033", "2197", "1.38x"],
                        ["V4 P=6",         "4737", "3180", "1.49x"],
                        ["V4 Optimal",     "6323", "2511", "2.52x"],
                    ],
                },
            },
            {
                "heading": "Perche' il vantaggio Mojo cresce con il parallelismo",
                "body": (
                    "A parallelismo basso (SEQ), entrambi i framework pagano gli stessi\n"
                    "costi di compute. MoStream e' ~1.4x piu' veloce principalmente per\n"
                    "il SIMD esplicito (V4).\n\n"
                    "A parallelismo alto (P=6, Optimal), il vantaggio di MoStream cresce\n"
                    "fino a 2.5x. I fattori:\n\n"
                    "  1. CPU pinning MoStream: no regressioni HT, scaling monotono\n"
                    "  2. FastFlow scala male oltre P=4 (regressioni a P=5 e P=7)\n"
                    "  3. tcmalloc di Mojo gestisce meglio le allocazioni frequenti\n"
                    "     rispetto a mmap syscall di glibc per buffer da 786KB\n\n"
                    "Il vantaggio totale e' quindi la combinazione di:\n"
                    "  - Stage piu' veloci (SIMD esplicito): contributo ~1.4x\n"
                    "  - Framework piu' scalabile (pinning): contributo ~1.8x\n"
                    "  - Prodotto: ~2.5x all'ottimale"
                ),
            },
            {
                "heading": "La soluzione naturale: buffer pool (zero-copy)",
                "body": (
                    "Il problema della copia 786KB ad ogni stage boundary si risolve\n"
                    "con un buffer pool condiviso:\n\n"
                    "  Idea: pre-allocare N buffer al lancio della pipeline.\n"
                    "  Ogni stage 'prende' un buffer libero dal pool, ci scrive il\n"
                    "  risultato, e passa il puntatore alla coda (8 byte, come FastFlow).\n"
                    "  Lo stage successivo usa il buffer direttamente, senza copiare.\n"
                    "  Quando il Sink ha finito, il buffer torna al pool.\n\n"
                    "  Struttura:\n"
                    "  Pool: [buf_0][buf_1][buf_2]...[buf_N]   (N = profondita' coda)\n\n"
                    "  Source: prende buf libero, riempie, invia ptr\n"
                    "  Blur:   riceve ptr, legge in-place, alloca nuovo buf, invia ptr\n"
                    "  Sink:   riceve ptr, legge, restituisce buf al pool\n\n"
                    "  Vantaggi:\n"
                    "    - Nessuna memcpy nella coda (vs 786KB attuali)\n"
                    "    - Nessuna alloc/free nel hot path\n"
                    "    - Buffer sempre 'caldi' in cache (riutilizzati ciclicamente)\n\n"
                    "  Stima impatto: -45% bandwidth di memoria --> +20-30% throughput totale\n"
                    "  (basato sul 13% di overhead copia in V4 x fattore di amplificazione\n"
                    "  per riduzione dei cache miss secondari)"
                ),
            },
        ],
    },
]

# ---------------------------------------------------------------------------
# PDF generation (same engine as generate_analysis_pdf.py)
# ---------------------------------------------------------------------------

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FONT_R  = f"{FONT_DIR}/DejaVuSans.ttf"
FONT_B  = f"{FONT_DIR}/DejaVuSans-Bold.ttf"
FONT_I  = f"{FONT_DIR}/DejaVuSans-Oblique.ttf"
FONT_BI = f"{FONT_DIR}/DejaVuSans-BoldOblique.ttf"
MONO_R  = f"{FONT_DIR}/DejaVuSansMono.ttf"
MONO_B  = f"{FONT_DIR}/DejaVuSansMono-Bold.ttf"


class PDF(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.add_font("DVSans", "",   FONT_R,  uni=True)
        self.add_font("DVSans", "B",  FONT_B,  uni=True)
        self.add_font("DVSans", "I",  FONT_I,  uni=True)
        self.add_font("DVSans", "BI", FONT_BI, uni=True)
        self.add_font("DVMono", "",   MONO_R,  uni=True)
        self.add_font("DVMono", "B",  MONO_B,  uni=True)
        self.set_auto_page_break(auto=True, margin=20)
        self.set_margins(20, 20, 20)
        self.set_left_margin(20)

    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("DVSans", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 6, "Analisi Code Pipeline — MoStream Thesis", align="R")
        self.ln(4)
        self.set_draw_color(180, 180, 180)
        self.line(20, self.get_y(), 190, self.get_y())
        self.ln(3)
        self.set_text_color(0, 0, 0)

    def footer(self):
        if self.page_no() == 1:
            return
        self.set_y(-15)
        self.set_font("DVSans", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 10, f"Pagina {self.page_no() - 1}", align="C")
        self.set_text_color(0, 0, 0)

    def cover_page(self, title, subtitle):
        self.add_page()
        self.set_fill_color(20, 60, 60)
        self.rect(0, 0, 210, 297, "F")
        self.set_y(80)
        self.set_font("DVSans", "B", 22)
        self.set_text_color(255, 255, 255)
        self.multi_cell(0, 12, title, align="C")
        self.ln(8)
        self.set_font("DVSans", "", 14)
        self.set_text_color(160, 220, 210)
        self.multi_cell(0, 8, subtitle, align="C")
        self.ln(20)
        self.set_font("DVSans", "I", 11)
        self.set_text_color(120, 180, 170)
        self.cell(0, 8, "MoStream — Studio delle performance Mojo vs FastFlow C++", align="C")
        self.ln(8)
        self.set_font("DVSans", "I", 10)
        self.cell(0, 8, "Aprile 2026", align="C")
        self.set_text_color(0, 0, 0)

    def section_title(self, text):
        self.add_page()
        self.set_font("DVSans", "B", 16)
        self.set_text_color(20, 60, 60)
        self.cell(0, 10, text, ln=True)
        self.set_draw_color(20, 60, 60)
        self.set_line_width(0.5)
        self.line(20, self.get_y(), 190, self.get_y())
        self.ln(5)
        self.set_line_width(0.2)
        self.set_draw_color(0, 0, 0)
        self.set_text_color(0, 0, 0)

    def block_heading(self, text):
        self.ln(3)
        self.set_font("DVSans", "B", 12)
        self.set_text_color(20, 100, 90)
        self.cell(0, 7, text, ln=True)
        self.set_text_color(0, 0, 0)

    def body_text(self, text):
        self.set_font("DVSans", "", 10)
        lines = text.split("\n")
        for line in lines:
            stripped = line.lstrip()
            indent = len(line) - len(stripped)
            if stripped == "":
                self.ln(2)
            elif indent > 0:
                self.set_x(20 + min(indent * 1.8, 20))
                self.set_font("DVMono", "", 8.5)
                self.set_text_color(30, 30, 30)
                self.multi_cell(170 - min(indent * 1.8, 20), 4.8, stripped)
                self.set_font("DVSans", "", 10)
                self.set_text_color(0, 0, 0)
                self.set_x(20)
            else:
                self.set_x(20)
                self.multi_cell(0, 5.5, stripped)

    def draw_table(self, headers, rows):
        self.ln(3)
        col_w = 170 / len(headers)
        self.set_fill_color(20, 60, 60)
        self.set_text_color(255, 255, 255)
        self.set_font("DVSans", "B", 9)
        for h in headers:
            self.cell(col_w, 7, h, border=1, fill=True)
        self.ln()
        self.set_text_color(0, 0, 0)
        for i, row in enumerate(rows):
            if i % 2 == 0:
                self.set_fill_color(225, 245, 243)
            else:
                self.set_fill_color(255, 255, 255)
            self.set_font("DVSans", "", 8.5)
            for cell in row:
                self.cell(col_w, 6, cell, border=1, fill=True)
            self.ln()
        self.ln(3)


def build_pdf():
    pdf = PDF()
    for section in SECTIONS:
        if section.get("is_cover"):
            pdf.cover_page(section["title"], section["subtitle"])
            continue
        pdf.section_title(section["title"])
        for block in section.get("blocks", []):
            pdf.block_heading(block["heading"])
            if "body" in block:
                pdf.body_text(block["body"])
            if "table" in block:
                t = block["table"]
                pdf.draw_table(t["headers"], t["rows"])
    pdf.output(OUTPUT)
    print(f"PDF generato: {OUTPUT}")


if __name__ == "__main__":
    build_pdf()
