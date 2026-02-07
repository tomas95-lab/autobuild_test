# Example Task: Simple Hello World

This is a minimal example task for testing Autobuild Web.

## Structure

```
simple-task/
├── env/
│   └── Dockerfile          # Debian + Node.js 20
├── verify/
│   ├── verify.sh          # Check if output.txt exists
│   └── command            # Run verify.sh
└── prompt                 # "Create output.txt with Hello, Autobuild!"
```

## What it does

1. AI receives prompt to create `output.txt`
2. AI writes the file with the requested content
3. Verification checks if file exists
4. Reports SUCCESS if found, FAILURE otherwise

## How to test

### Create ZIP
```bash
cd examples/simple-task
zip -r ../../simple-task.zip .
```

### Upload via Web UI
1. Go to your deployed Autobuild Web
2. Upload `simple-task.zip`
3. Select mode: "verify"
4. Click "Run Autobuild"
5. Wait ~5 minutes
6. Download and check logs

### Expected Result
- ✅ Docker build: SUCCESS
- ✅ Gemini execution: Creates output.txt
- ✅ Verification: SUCCESS
- ✅ Final status: PASSED

## Troubleshooting

If verification fails:
1. Check `gemini_npx.log` - Did AI create the file?
2. Check `verification.log` - What did verify.sh output?
3. Check `docker_inspect.json` - Was container set up correctly?

## Variations

You can modify this task to test different scenarios:

### Test 1: Math Problem
**Prompt:**
```
Create a file named "result.txt" containing the result of 42 + 58.
```

**verify.sh:**
```bash
if grep -q "100" result.txt; then
    echo "SUCCESS"
else
    echo "FAILURE"
fi
```

### Test 2: JSON Creation
**Prompt:**
```
Create a JSON file named "data.json" with: {"name": "Autobuild", "version": "2.6"}
```

**verify.sh:**
```bash
if jq -e '.name == "Autobuild"' data.json > /dev/null; then
    echo "SUCCESS"
else
    echo "FAILURE"
fi
```

### Test 3: Simple API
**Prompt:**
```
Create a simple Express.js server in server.js that responds "Hello World" on port 3000.
```

**verify.sh:**
```bash
node server.js &
SERVER_PID=$!
sleep 2
RESPONSE=$(curl -s http://localhost:3000)
kill $SERVER_PID

if [[ "$RESPONSE" == *"Hello World"* ]]; then
    echo "SUCCESS"
else
    echo "FAILURE"
fi
```

## Notes

- This is a MINIMAL example for testing
- Real tasks should be more complex
- Verification should test actual functionality
- Always output exactly "SUCCESS" or "FAILURE"
