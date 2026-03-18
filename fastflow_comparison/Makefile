# Makefile for FastFlow image processing benchmark
#
# FastFlow is header-only. Set FF_HOME to the root of your FastFlow installation.
# Example: make FF_HOME=/path/to/fastflow
#
# If FastFlow is not installed, clone it:
#   git clone https://github.com/fastflow/fastflow.git

FF_HOME ?= ../fastflow

CXX      = g++
CXXFLAGS = -std=c++17 -O3 -DNDEBUG -I$(FF_HOME)
LDFLAGS  = -pthread

# Optional: enable native arch optimizations (same machine compilation)
# CXXFLAGS += -march=native

SRCS     = source_rate_benchmark.cpp
TARGET   = source_rate_benchmark
RESULTS  = results

.PHONY: all clean run help

all: check_ff $(TARGET)

$(TARGET): $(SRCS) ppm_image.hpp image_stages.hpp
	$(CXX) $(CXXFLAGS) -o $@ $(SRCS) $(LDFLAGS)

check_ff:
	@if [ ! -d "$(FF_HOME)/ff" ]; then \
		echo "ERROR: FastFlow not found at $(FF_HOME)"; \
		echo ""; \
		echo "Options:"; \
		echo "  1. Clone FastFlow:  git clone https://github.com/fastflow/fastflow.git"; \
		echo "  2. Set FF_HOME:     make FF_HOME=/path/to/fastflow"; \
		echo ""; \
		exit 1; \
	fi

run: $(TARGET)
	@mkdir -p $(RESULTS)/plots
	./$(TARGET) | tee $(RESULTS)/source_rate_512.txt

clean:
	rm -f $(TARGET)

help:
	@echo "Targets:"
	@echo "  all     - Build the benchmark (default)"
	@echo "  run     - Build and run, saving results to results/"
	@echo "  clean   - Remove compiled binary"
	@echo ""
	@echo "Variables:"
	@echo "  FF_HOME - Path to FastFlow root (default: ../fastflow)"
	@echo ""
	@echo "Example:"
	@echo "  make FF_HOME=/usr/local/include run"
