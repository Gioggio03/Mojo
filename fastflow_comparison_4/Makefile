# Makefile — FastFlow V4 (planar layout)
#
#   make                     -> compila con -O3 (default)
#   make OPT=O2              -> compila con -O2
#   make run_test_spot       -> compila -O3, esegui, genera grafici
#   make run_test_spot OPT=O2

FF_HOME ?= ../fastflow
OPT     ?= O3

CXX      = g++
CXXFLAGS = -std=c++17 -$(OPT) -DNDEBUG -I$(FF_HOME) -DFF_BOUNDED_BUFFER -DDEFAULT_BUFFER_CAPACITY=1024
LDFLAGS  = -pthread

RESULTS = results
PYTHON  ?= /disc1/homes/gcappello/Mojo/benchmarks/.venv/bin/python3

.PHONY: all clean run_test_spot check_ff

all: check_ff test_spot

test_spot: test_spot.cpp ppm_image.hpp image_stages.hpp
	$(CXX) $(CXXFLAGS) -o test_spot test_spot.cpp $(LDFLAGS)
	@echo "Built with -$(OPT)"

check_ff:
	@if [ ! -d "$(FF_HOME)/ff" ]; then \
		echo "ERROR: FastFlow not found at $(FF_HOME)"; \
		exit 1; \
	fi

run_test_spot: test_spot
	@mkdir -p $(RESULTS)/plots
	./test_spot | tee $(RESULTS)/test_spot_512_$(OPT).txt
	$(PYTHON) compare_results.py --ff-file $(RESULTS)/test_spot_512_$(OPT).txt

clean:
	rm -f test_spot
