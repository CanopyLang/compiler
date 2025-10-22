#!/bin/bash

echo "==================================="
echo "Canopy Test Projects Verification"
echo "==================================="
echo ""

cd "$(dirname "$0")"

# Small project
echo "Testing Small Project..."
cd small
if stack exec -- canopy make src/Main.canopy --output=/tmp/small_test.js 2>&1 | grep -q "Success"; then
    echo "✓ Small project compiles successfully"
else
    echo "✗ Small project failed to compile"
fi
cd ..
echo ""

# Medium project
echo "Testing Medium Project..."
cd medium
if stack exec -- canopy make src/Main.can --output=/tmp/medium_test.js 2>&1 | grep -q "Success"; then
    echo "✓ Medium project compiles successfully"
else
    echo "✗ Medium project failed to compile"
fi
cd ..
echo ""

# Large project
echo "Testing Large Project..."
cd large
if stack exec -- canopy make src/Main.can --output=/tmp/large_test.js 2>&1 | grep -q "Success"; then
    echo "✓ Large project compiles successfully"
else
    echo "✗ Large project failed to compile"
fi
cd ..
echo ""

echo "==================================="
echo "Verification Complete"
echo "==================================="
