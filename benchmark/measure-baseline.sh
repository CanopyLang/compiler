#!/bin/bash
# Measure baseline performance (current compiler with NO optimizations)

cd /home/quinten/fh/canopy

echo "Measuring baseline performance - small project (10 runs)"
rm -f benchmark/measurements/baseline-small.txt

for i in {1..10}; do
  echo "Run $i/10..."
  /usr/bin/time -f "%e" stack exec -- canopy make \
    benchmark/projects/small/src/Main.canopy \
    --output=/tmp/baseline-test.js \
    2>> benchmark/measurements/baseline-small.txt
done

echo ""
echo "Baseline measurements complete!"
echo "Results saved to: benchmark/measurements/baseline-small.txt"
echo ""
echo "Times (seconds):"
grep "^[0-9]" benchmark/measurements/baseline-small.txt
