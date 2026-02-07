#!/bin/bash
set -e

echo "Running verification..."

# Simple verification example
if [ -f "output.txt" ]; then
    echo "SUCCESS: output.txt exists"
    exit 0
else
    echo "FAILURE: output.txt not found"
    exit 1
fi
