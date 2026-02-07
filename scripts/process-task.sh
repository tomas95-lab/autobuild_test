#!/bin/bash
# Script to process uploaded task in GitHub Actions
set -e

TASK_DIR="${1:-./task}"
MODE="${2:-verify}"
OUTPUT_DIR="${3:-./output}"

echo "================================================"
echo "Autobuild Task Processor"
echo "================================================"
echo "Task directory: $TASK_DIR"
echo "Mode: $MODE"
echo "Output directory: $OUTPUT_DIR"
echo "================================================"

# Validate task structure
echo "📋 Validating task structure..."

if [ ! -d "$TASK_DIR/env" ]; then
    echo "❌ Error: env/ directory not found in task"
    exit 1
fi

if [ ! -d "$TASK_DIR/verify" ]; then
    echo "❌ Error: verify/ directory not found in task"
    exit 1
fi

if [ ! -f "$TASK_DIR/prompt" ]; then
    echo "❌ Error: prompt file not found in task"
    exit 1
fi

if [ ! -f "$TASK_DIR/env/Dockerfile" ]; then
    echo "❌ Error: Dockerfile not found in env/"
    exit 1
fi

echo "✅ Task structure is valid"

# Check for autobuild scripts
AUTOBUILD_SCRIPT="./autobuild/scripts/autobuild.sh"
if [ ! -f "$AUTOBUILD_SCRIPT" ]; then
    echo "❌ Error: autobuild.sh not found at $AUTOBUILD_SCRIPT"
    exit 1
fi

echo "✅ Autobuild script found"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run autobuild
echo ""
echo "🚀 Starting autobuild execution..."
echo "================================================"

TASK_ABS=$(realpath "$TASK_DIR")
OUTPUT_ABS=$(realpath "$OUTPUT_DIR")

bash "$AUTOBUILD_SCRIPT" "$MODE" \
    --task "$TASK_ABS" \
    --output-dir "$OUTPUT_ABS" \
    --api-key "${GEMINI_API_KEY}"

EXIT_CODE=$?

echo "================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Autobuild completed successfully"
else
    echo "❌ Autobuild failed with exit code: $EXIT_CODE"
fi
echo "================================================"

# Generate summary
cat > "$OUTPUT_DIR/SUMMARY.txt" << EOF
Autobuild Execution Summary
===========================

Mode: $MODE
Task: $TASK_DIR
Status: $([ $EXIT_CODE -eq 0 ] && echo "SUCCESS" || echo "FAILED")
Exit Code: $EXIT_CODE
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Generated Files:
================
$(find "$OUTPUT_DIR" -type f -name "*.log" -o -name "*.txt" -o -name "*.json" | sed 's|'"$OUTPUT_DIR"'/||')

EOF

echo ""
echo "📊 Summary generated at: $OUTPUT_DIR/SUMMARY.txt"
echo ""

exit $EXIT_CODE
