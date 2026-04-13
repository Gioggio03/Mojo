# Makefile — FastFlow V4 (planar layout)
#
#   make                          -> compila entrambi i binari con -O3 (default)
#   make OPT=O2                   -> compila con -O2
#   make run_benchmark_full       -> compila -O3, esegui sweep completo, genera grafici
#   make run_benchmark_full OPT=O2
#   make run_test_spot G=2 B=7 S=10  -> compila -O3, esegui configurazione singola
#
# test_spot    : una sola configurazione G B S da linea di comando (./test_spot 2 7 10)
# benchmark_full: sweep completo P=2..7 + configurazione ottimale

FF_HOME ?= ../fastflow
OPT     ?= O3

CXX      = g++
CXXFLAGS = -std=c++17 -$(OPT) -DNDEBUG -I$(FF_HOME) -DFF_BOUNDED_BUFFER -DDEFAULT_BUFFER_CAPACITY=1024
LDFLAGS  = -pthread

RESULTS = results
PYTHON  ?= /disc1/homes/gcappello/Mojo/benchmarks/.venv/bin/python3

G ?= 2
B ?= 7
S ?= 10

.PHONY: all clean run_benchmark_full run_test_spot check_ff

all: check_ff benchmark_full test_spot

benchmark_full: benchmark_full.cpp ppm_image.hpp image_stages.hpp
	$(CXX) $(CXXFLAGS) -o benchmark_full benchmark_full.cpp $(LDFLAGS)
	@echo "Built benchmark_full with -$(OPT)"

test_spot: test_spot.cpp ppm_image.hpp image_stages.hpp
	$(CXX) $(CXXFLAGS) -o test_spot test_spot.cpp $(LDFLAGS)
	@echo "Built test_spot with -$(OPT)"

check_ff:
	@if [ ! -d "$(FF_HOME)/ff" ]; then \
		echo "ERROR: FastFlow not found at $(FF_HOME)"; \
		exit 1; \
	fi

run_benchmark_full: benchmark_full
	@mkdir -p $(RESULTS)/plots
	./benchmark_full | tee $(RESULTS)/benchmark_full_512_$(OPT).txt
	$(PYTHON) compare_results.py --ff-file $(RESULTS)/benchmark_full_512_$(OPT).txt

run_test_spot: test_spot
	@mkdir -p $(RESULTS)
	./test_spot $(G) $(B) $(S) | tee $(RESULTS)/test_spot_g$(G)b$(B)s$(S)_$(OPT).txt

clean:
	rm -f test_spot benchmark_full
