#!/bin/bash
# Benchmark script for the toy sorting project.
# This is what autoresearch.sh would look like for this project.
set -euo pipefail

# Pre-check: syntax validation
python3 -c "import sort" 2>&1

# Run benchmark
RESULT=$(python3 -c "
import time, random

from sort import sort_numbers

random.seed(42)
data = random.sample(range(100000), 5000)

# Warm up
sort_numbers(data[:100])

# Benchmark: average of 3 runs
times = []
for _ in range(3):
    start = time.perf_counter_ns()
    sort_numbers(data)
    elapsed = (time.perf_counter_ns() - start) / 1000  # nanoseconds to microseconds
    times.append(elapsed)

avg_us = sum(times) / len(times)
print(f'sort_us: {avg_us:.1f}')
")

echo "$RESULT"

# Extract and output metric
TIME=$(echo "$RESULT" | sed -n 's/sort_us: \([0-9.]*\)/\1/p')
echo "METRIC sort_us=$TIME"
