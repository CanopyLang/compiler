# Quick Benchmark Guide

## Run All Projects

```bash
cd /home/quinten/fh/canopy/benchmark/projects

# Small
cd small && time stack exec -- canopy make src/Main.canopy --output=/tmp/small.js && cd ..

# Medium
cd medium && time stack exec -- canopy make src/Main.can --output=/tmp/medium.js && cd ..

# Large
cd large && time stack exec -- canopy make src/Main.can --output=/tmp/large.js && cd ..
```

## One-Liner Test

```bash
cd /home/quinten/fh/canopy/benchmark/projects && \
for p in small medium large; do \
  echo "=== Testing $p ==="; \
  cd $p; \
  if [ "$p" = "small" ]; then \
    time stack exec -- canopy make src/Main.canopy --output=/tmp/${p}.js; \
  else \
    time stack exec -- canopy make src/Main.can --output=/tmp/${p}.js; \
  fi; \
  cd ..; \
  echo; \
done
```

## Profiling

### Time Measurement

```bash
# Small
cd small && /usr/bin/time -v stack exec -- canopy make src/Main.canopy --output=/tmp/small.js

# Medium
cd medium && /usr/bin/time -v stack exec -- canopy make src/Main.can --output=/tmp/medium.js

# Large
cd large && /usr/bin/time -v stack exec -- canopy make src/Main.can --output=/tmp/large.js
```

### Memory Profiling (if using GHC profiling)

```bash
# Compile with profiling
stack build --profile

# Run with profiling
cd large && stack exec --profile -- canopy make src/Main.can --output=/tmp/large.js +RTS -p -h
```

## Expected Results

| Project | Modules | Lines | Expected Time |
|---------|---------|-------|---------------|
| Small   | 1       | 10    | < 1s          |
| Medium  | 4       | 260   | 1-3s          |
| Large   | 13      | 1,086 | 3-10s         |

## Verify Outputs

```bash
# Check all files compiled
ls -lh /tmp/small.js /tmp/medium.js /tmp/large.js

# Check file sizes
du -h /tmp/small.js /tmp/medium.js /tmp/large.js
```
