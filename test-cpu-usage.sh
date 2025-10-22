#!/bin/bash

# Test CPU usage during parallel compilation
#
# This script monitors CPU usage to verify parallel execution

set -e

echo "=========================================="
echo "CPU USAGE MONITORING TEST"
echo "=========================================="
echo ""

# Create a test Haskell program that does CPU-intensive work
cat > /tmp/test-parallel-cpu.hs << 'EOF'
{-# LANGUAGE ScopedTypeVariables #-}
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Async as Async
import System.IO (hFlush, stdout)

-- CPU-intensive function
fibonacci :: Integer -> Integer
fibonacci 0 = 0
fibonacci 1 = 1
fibonacci n = fibonacci (n-1) + fibonacci (n-2)

-- Simulate module compilation
compileModule :: String -> IO ()
compileModule name = do
  tid <- Concurrent.myThreadId
  putStrLn $ "[" ++ show tid ++ "] Compiling " ++ name
  hFlush stdout
  -- CPU-intensive work
  let result = fibonacci 38
  putStrLn $ "[" ++ show tid ++ "] Finished " ++ name ++ " (result: " ++ show result ++ ")"
  hFlush stdout

main :: IO ()
main = do
  putStrLn "Starting parallel compilation test..."
  numCap <- Concurrent.getNumCapabilities
  putStrLn $ "Capabilities: " ++ show numCap

  let modules = ["A", "B", "C", "D", "E", "F", "G", "H"]

  putStrLn "\n=== Parallel Execution ==="
  _ <- Async.mapConcurrently compileModule modules

  putStrLn "\nDone!"
EOF

echo "Compiling test program..."
ghc -threaded -rtsopts -O2 /tmp/test-parallel-cpu.hs -o /tmp/test-parallel-cpu 2>&1 | tail -3

echo ""
echo "=== Test 1: Sequential (1 thread) ==="
echo "Monitor CPU - should be ~100% (1 core)"
echo ""

# Run in background and monitor
/tmp/test-parallel-cpu +RTS -N1 -RTS &
PID=$!

# Monitor for a few seconds
for i in {1..5}; do
    if ps -p $PID > /dev/null 2>&1; then
        CPU=$(ps -p $PID -o %cpu= 2>/dev/null || echo "0")
        echo "CPU usage: ${CPU}%"
        sleep 1
    fi
done

wait $PID 2>/dev/null || true

echo ""
echo "=== Test 2: Parallel (all cores) ==="
echo "Monitor CPU - should be >100% (multiple cores)"
echo ""

/tmp/test-parallel-cpu +RTS -N -RTS &
PID=$!

# Monitor for a few seconds
MAX_CPU=0
for i in {1..5}; do
    if ps -p $PID > /dev/null 2>&1; then
        CPU=$(ps -p $PID -o %cpu= 2>/dev/null || echo "0")
        CPU_INT=$(echo "$CPU" | cut -d'.' -f1)
        if [ "$CPU_INT" -gt "$MAX_CPU" ]; then
            MAX_CPU=$CPU_INT
        fi
        echo "CPU usage: ${CPU}%"
        sleep 1
    fi
done

wait $PID 2>/dev/null || true

echo ""
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo ""
echo "Maximum CPU usage observed: ${MAX_CPU}%"
echo ""

if [ "$MAX_CPU" -gt 150 ]; then
    echo "✅ PARALLEL EXECUTION CONFIRMED!"
    echo "   CPU usage >150% means multiple cores are being used"
elif [ "$MAX_CPU" -gt 100 ]; then
    echo "✅ Parallel execution detected"
    echo "   CPU usage >100% indicates multiple cores"
    echo "   (May need more CPU-intensive work to saturate cores)"
else
    echo "❌ NO PARALLEL EXECUTION DETECTED"
    echo "   CPU usage ≤100% suggests single-threaded execution"
fi

echo ""
echo "Note: This test uses Async.mapConcurrently which is the"
echo "      same function used in Build.Parallel.hs"
echo "=========================================="
