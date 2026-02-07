#!/bin/bash
# Test that all required files exist

echo "🔍 Checking project structure..."
echo ""

failed=0

# Required files
required_files=(
    ".github/workflows/autobuild-v2.yml"
    ".github/workflows/deploy.yml"
    ".gitignore"
    "ARCHITECTURE.md"
    "DEPLOY.md"
    "LICENSE"
    "QUICKSTART.md"
    "README.md"
    "SUMMARY.md"
    "package.json"
    "public/index.html"
    "public/app-v2.js"
    "public/config.template.js"
    "scripts/process-task.sh"
    "setup.sh"
    "setup.ps1"
    "examples/simple-task/env/Dockerfile"
    "examples/simple-task/verify/verify.sh"
    "examples/simple-task/verify/command"
    "examples/simple-task/prompt"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ MISSING: $file"
        failed=$((failed + 1))
    fi
done

echo ""
echo "================================================"

if [ $failed -eq 0 ]; then
    echo "✅ All files present! Project is ready."
    echo ""
    echo "Next steps:"
    echo "1. Run ./setup.sh (or setup.ps1 on Windows)"
    echo "2. Follow the instructions"
    echo "3. Push to GitHub"
    echo ""
    exit 0
else
    echo "❌ $failed file(s) missing. Please check above."
    exit 1
fi
