#!/bin/bash
# Create example task ZIP for testing

echo "Creating example task ZIP..."

cd examples/simple-task
zip -r ../../simple-task-example.zip .

cd ../..

if [ -f "simple-task-example.zip" ]; then
    echo "✅ Created: simple-task-example.zip"
    echo "   Size: $(du -h simple-task-example.zip | cut -f1)"
    echo ""
    echo "You can now test this by uploading it to your Autobuild Web app!"
else
    echo "❌ Failed to create ZIP"
    exit 1
fi
