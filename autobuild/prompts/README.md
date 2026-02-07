# Autobuild Prompts

This directory contains the prompt templates used by the autobuild script when interacting with Gemini CLI.

## Prompt Files

### Core Prompts (Feedback & Verify Modes)

#### 1. `prompt1_template.txt` (Feedback Mode - Initial Task)
**Used in:** `feedback` and `both` modes  
**Function:** `compose_prompt1_file()` in `autobuild.sh`

This is the first prompt sent to Gemini in feedback mode. It:
- Asks Gemini to read and execute the task from the user's prompt file
- Instructs Gemini to use `verify.sh` to test the solution
- Requests an analysis of the verifier's effectiveness (sufficiency, over-testing, scope)

**Note:** The actual task prompt content is appended to the end of this template at runtime.

#### 2. `prompt2_template.txt` (Feedback Mode - Follow-up Analysis)
**Used in:** `feedback` and `both` modes (only if verification passes)  
**Function:** `compose_prompt2_file()` in `autobuild.sh`

This prompt is sent after verification succeeds. It:
- Asks Gemini to reflect on whether it could have completed the task without the verifier
- Requests identification of ambiguities or under-specified elements in the prompt or verifier

### Audit Prompts

#### 3. `audit_prompt_template.txt` (Task Quality Audit)
**Used in:** `audit` mode  
**Function:** `compose_audit_prompt_file()` in `autobuild.sh`

This prompt performs a static analysis of the task, verifier, and environment. It:
- Analyzes whether the verifier is valid for the task
- Evaluates if the prompt is clear enough to verify
- Determines if the verifier would accept other valid implementations
- Assesses overall task quality and solvability
- Outputs results in a structured XML-like format

**Key Focus Areas:**
- Behavior vs implementation testing
- Over-constraint vs legitimate invariants
- Environment/path assumptions
- Functional coverage
- Prompt-verify alignment
- Task solvability by AI agents

### Solution Testing Prompts (NEW)

#### 4. `solution_audit_prompt_template.txt` (Solution Quality Audit)
**Used in:** `solution_audit` mode  
**Function:** `compose_solution_audit_prompt_file()` in `autobuild.sh`

**Purpose:** Validate that worker-provided solutions (golden responses) are high quality **without executing them**.

This prompt analyzes:
- **Completeness:** Does the solution address all requirements?
- **Correctness:** Is the implementation logically sound?
- **Verifiability:** Would it pass the verification tests?
- **Quality:** Code quality, best practices, maintainability
- **Script Validity:** Is `solution_script.sh` correct?

Output includes structured tags for automated processing and specific recommendations.

#### 5. `solution_verify_prompt_template.txt` (Solution Verification Analysis)
**Used in:** `solution_verify` mode  
**Function:** `compose_solution_verify_prompt_file()` in `autobuild.sh`

**Purpose:** Analyze results **after** running the solution and verification tests.

This prompt evaluates:
- **Verification Results:** Did the tests pass/fail?
- **Implementation Correctness:** Was the solution applied correctly?
- **Root Cause Analysis:** Why did verification fail (if applicable)?
- **Alignment:** How well do prompt, solution, and verification align?
- **Golden Response Acceptance:** Should this be accepted as the reference implementation?
- **Task Quality:** Overall assessment of the task design

## Usage in the Script

These templates are now **externalized** as separate files and loaded by the `autobuild.sh` script at runtime for easier maintenance and customization.

### Current Implementation (External Files):

The script loads prompts from the `prompts/` directory:

```bash
# In autobuild.sh (line ~9):
PROMPTS_DIR="${AUTOBUILD_PROMPTS_DIR:-$(cd "$SCRIPT_DIR/../prompts" && pwd)}"

# Functions read from external files:
compose_prompt1_file() {
  cat "$PROMPTS_DIR/prompt1_template.txt" > "$out_file"
  cat "$src_prompt_file" >> "$out_file"
}

compose_prompt2_file() {
  cat "$PROMPTS_DIR/prompt2_template.txt" > "$out_file"
}

compose_audit_prompt_file() {
  cat "$PROMPTS_DIR/audit_prompt_template.txt" > "$out_file"
}
```

### Benefits of This Approach:
- ✅ Edit prompts without modifying code
- ✅ Version control tracks prompt changes separately
- ✅ Non-developers can modify prompts easily
- ✅ Quick A/B testing of different prompts
- ✅ Environment variable override: `AUTOBUILD_PROMPTS_DIR=/custom/path`
- ✅ Validation checks ensure all required templates exist at startup

## Workflow

### Feedback Mode:
1. Build Docker image
2. Start container
3. Copy task files and verifier
4. Send **Prompt 1** → Gemini solves the task
5. Run verification script
6. If verification passes → Send **Prompt 2** → Gemini reflects on the task

### Audit Mode:
1. Build Docker image
2. Start container
3. Copy task files, verifier, and Dockerfile to `_context/`
4. Copy solution to `_context/solution/` (if present)
5. Send **Audit Prompt** → Gemini analyzes task quality
6. Output structured analysis

### Verify Mode:
Uses the raw task prompt directly (not these templates) with `npx @google/gemini-cli`.

### Solution Mode:
Doesn't use Gemini at all—just runs a pre-made solution script and verifies it.

### Solution Audit Mode (NEW):
1. Build Docker image
2. Start container
3. Copy task files, verifier, Dockerfile, and **solution** to `_context/`
4. Send **Solution Audit Prompt** → Gemini analyzes solution quality WITHOUT running it
5. Output structured analysis of solution completeness, correctness, quality

**Use Case:** Validate worker submissions before accepting them as golden responses.

### Solution Verify Mode (NEW):
1. Build Docker image
2. Start container
3. Copy and execute the solution script
4. Run verification tests
5. Copy context for analysis
6. Send **Solution Verify Prompt** → Gemini analyzes execution results
7. Output detailed analysis of whether solution should be accepted as golden response

**Use Case:** Comprehensive validation that solution works correctly and meets quality standards.

## Solution Testing Workflow

The solution testing prompts are designed for quality assurance of worker-provided solutions:

```bash
# Quick quality check (no execution)
autobuild.sh solution_audit --task /path/to/task --api-key $KEY

# Full validation (execute + verify + analyze)
autobuild.sh solution_verify --task /path/to/task --api-key $KEY

# Simple execution test (no Gemini analysis)
autobuild.sh solution --task /path/to/task
```

**Expected Task Structure for Solution Testing:**
```
task/
├── env/
│   └── Dockerfile
├── prompt (or prompt.txt)
├── verify/
│   ├── verify.sh
│   └── [test files]
└── solution/          ← Required for solution_* modes
    ├── solution_script.sh
    ├── solution.patch (or other solution files)
    └── [additional files]
```

