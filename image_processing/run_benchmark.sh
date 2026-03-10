#!/bin/bash
export MOSTREAM_HOME="/home/gcappello/Mojo"
mojo build -O3 -I /home/gcappello/Mojo image_pipeline.mojo -o image_pipeline_par
./image_pipeline_par
