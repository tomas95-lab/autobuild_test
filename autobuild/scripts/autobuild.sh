#!/usr/bin/env bash
set -Eeuo pipefail

# Default Gemini CLI version; can be overridden by --gemini-cli-version or env GEMINI_CLI_VERSION
gemini_cli_version="${GEMINI_CLI_VERSION:-0.21.2}"
GCLOUD_CREDS_JSON=""

# Prompts directory (can be overridden by AUTOBUILD_PROMPTS_DIR env variable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${AUTOBUILD_PROMPTS_DIR:-$(cd "$SCRIPT_DIR/../prompts" && pwd)}"

# Cleanup tracking
CLEANUP_ENABLED="true"
declare -a CREATED_CONTAINERS=()
declare -a CREATED_IMAGES=()

# Verification file placement (--verify-script-in-workdir copies contents to workdir instead of verify/ subfolder)
VERIFY_SCRIPT_IN_WORKDIR="false"

# Custom verification command (--verify-command to override command file)
VERIFY_COMMAND=""

# Task validation control (--skip-validation to bypass requirements check)
SKIP_VALIDATION="false"

# Trap to ensure cleanup runs on exit (success, error, or interrupt)
trap 'cleanup_artifacts' EXIT


# Helpers
# Accumulate user-provided bind mounts (e.g., -v host:container[:mode])
# Explicitly declare arrays so set -u won't choke when unused.
declare -a VOLUME_BINDS=()
declare -a VOLUME_ARGS=()

declare -a USER_ENV_KV=()     # from --env NAME=VALUE and expanded --env-mount
declare -a ENV_MOUNT=()       # raw --env-mount entries
declare -a EXEC_ENV_ARGS=()   # translated to -e NAME=VALUE for docker run/exec
declare -a DOCKER_RUN_ARGS=() # additional docker run arguments (e.g., -p 5678:5678)
# Autobuild v2: same structure as v1, with optional --env-file support for docker run
#
# Modes:
#  - feedback: build image, run container, install/run Gemini CLI with Prompt 1, then run verify, then Prompt 2 if verify passes
#  - verify:   build image and run customer sequence using npx Gemini CLI
#  - both:     feedback then verify with a fresh container for verify
#  - audit:    install Gemini, create _context and run an audit prompt

log_info() { echo "[INFO]  $*"; }
log_warn() { echo "[WARN]  $*" 1>&2; }
log_error(){ echo "[ERROR] $*" 1>&2; }
die()      { log_error "$*"; exit 1; }

cleanup_artifacts() {
  if [ "$CLEANUP_ENABLED" != "true" ]; then
    log_info "Cleanup disabled, keeping artifacts"
    return 0
  fi
  
  log_info "Cleaning up artifacts..."
  
  # Remove containers
  for container in "${CREATED_CONTAINERS[@]+"${CREATED_CONTAINERS[@]}"}"; do
    if [ -n "$container" ]; then
      log_info "Removing container: $container"
      docker rm -f "$container" >/dev/null 2>&1 || log_warn "Failed to remove container: $container"
    fi
  done
  
  # Remove images
  for image in "${CREATED_IMAGES[@]+"${CREATED_IMAGES[@]}"}"; do
    if [ -n "$image" ]; then
      log_info "Removing image: $image"
      docker rmi -f "$image" >/dev/null 2>&1 || log_warn "Failed to remove image: $image"
    fi
  done
  
  log_info "Cleanup complete"
}

usage() {
  cat <<'EOF'
Usage:
  autobuild.sh feedback        --task <abs_task_dir> [options...]
  autobuild.sh verify          --task <abs_task_dir> [options...]
  autobuild.sh both            --task <abs_task_dir> [options...]
  autobuild.sh audit           --task <abs_task_dir> [options...]
  autobuild.sh solution        --task <abs_task_dir> [options...]
  autobuild.sh solution_audit  --task <abs_task_dir> [options...]
  autobuild.sh solution_verify --task <abs_task_dir> [options...]
  autobuild.sh auto_review     --task <abs_task_dir> [options...]

Arguments:
  --task                 Absolute path to the task (must contain env/, verify/, and prompt or prompt.txt)
  --image-tag            Docker image tag (default: autobuild-<task_name>:<timestamp>-<rand>)
  --container-name       Container base name (a unique suffix is added per run)
  --workdir              Override container WORKDIR (default parsed from Dockerfile or /workspace)
  --api-key              Gemini API key (default: $GEMINI_API_KEY)
  --output-dir           Root dir for logs (default: <repo>/logs/<task>/<timestamp>/<mode>)
  --env-file             .env file to pass to docker run (auto-detects <task>/.env if omitted)
  --env NAME=VALUE       Repeatable. Export NAME with VALUE in container (docker run & docker exec).
  --env-mount NAME=HOST->CTR[:MODE]
                         Repeatable. Bind-mount HOST to CTR and export NAME=CTR.
                         Multiple names allowed comma-separated: NAME1,NAME2=HOST->CTR[:MODE]
  --mount                Bind mount (repeatable). Format: host_path:container_path[:mode]
                         - Defaults to :ro if mode omitted (safer for secrets)
                         - Equivalent short flag: -v
                         - Host path may be file or directory; relative paths are resolved to absolute when they exist
  --gemini-cli-version   Version of @google/gemini-cli to use (default: 0.21.2; env: GEMINI_CLI_VERSION)
  --no-cache             Build without cache (DEFAULT behavior)
  --cache                Enable Docker cache (faster but may use stale layers)
  --keep-artifacts       Keep containers and images after completion (by default they are removed)
  --skip-validation      Skip task structure validation (use with caution - for debugging only)
  --verify-script-in-workdir
                         Copy verify folder CONTENTS directly into $WORKDIR (instead of as verify/ subfolder)
                         Use this when command file contains: bash verify.sh (instead of bash verify/verify.sh)
  --verify-command       Override verification command (bypasses 'command' file requirement)
                         Example: --verify-command "bash verify/verify.sh"
  --docker-arg           Additional argument to pass to docker run (repeatable)
                         Example: --docker-arg "-p 5678:5678" --docker-arg "-v /var/run/docker.sock:/var/run/docker.sock"
  --gcloud-creds         (DEPRECATED) Path to a Google Cloud service account JSON; copied to /secrets/gcloud.json

Modes:
  feedback:        Build image, install Gemini, run prompts 1 & 2 (if verify passes)
  verify:          Build image, run Gemini via npx (customer sequence), then run verification
  both:            Run feedback then verify with fresh containers
  audit:           Install Gemini, create _context/, analyze task quality (prompt/verify/solution)
  solution:        Run pre-made solution script, then verify (no Gemini, tests golden response)
  solution_audit:  Analyze solution quality WITHOUT running it (static analysis by Gemini)
  solution_verify: Run solution, verify it, then analyze results with Gemini (validates golden response)
  auto_review:     Combined review: runs solution_verify, audit, and verify sequentially for full analysis

Notes:
  - Prefer --env-mount over --gcloud-creds. Example:
      --env-mount GOOGLE_APPLICATION_CREDENTIALS=/abs/sa.json->/secrets/gcloud.json:ro
  - If --env-file is not specified, the script will automatically use <task_dir>/.env if present.
  - solution_audit and solution_verify modes require a solution/ folder in the task directory
  - All outputs are saved under the logs root (default: <workspace>/logs). Override via AUTOBUILD_LOGS_ROOT or --output-dir.

Examples:
  # Test if provided solution passes verification
  autobuild.sh solution_verify --task /abs/task --api-key $GEMINI_API_KEY
  
  # Audit solution quality without running it
  autobuild.sh solution_audit --task /abs/task --api-key $GEMINI_API_KEY
  
  # Run basic task audit (checks prompt/verify quality)
  autobuild.sh audit --task /abs/task --api-key $GEMINI_API_KEY

EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

validate_prompt_templates() {
  local required_prompts=("prompt1_template.txt" "prompt2_template.txt" "audit_prompt_template.txt")
  local optional_prompts=("solution_audit_prompt_template.txt" "solution_verify_prompt_template.txt")
  local missing=()
  
  if [ ! -d "$PROMPTS_DIR" ]; then
    die "Prompts directory not found: $PROMPTS_DIR"
  fi
  
  for prompt in "${required_prompts[@]}"; do
    if [ ! -f "$PROMPTS_DIR/$prompt" ]; then
      missing+=("$prompt")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required prompt template(s) in $PROMPTS_DIR:"
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi
  
  # Warn about optional prompts
  for prompt in "${optional_prompts[@]}"; do
    if [ ! -f "$PROMPTS_DIR/$prompt" ]; then
      log_warn "Optional prompt template not found: $prompt (solution testing features limited)"
    fi
  done
}

validate_task_requirements() {
  local task_dir="$1"
  local log_file="${2:-}"  # Optional log file path
  local errors=()
  local warnings=()
  
  log_info "Validating task structure and requirements..."
  
  # Write validation header to log if provided
  if [ -n "$log_file" ]; then
    {
      echo "=== Task Validation Report ==="
      echo "Task: $task_dir"
      echo "Date: $(date)"
      echo ""
    } > "$log_file"
  fi
  
  # 1. Check Dockerfile
  # First check for case-sensitive filename (use ls to get actual filename)
  local actual_dockerfile
  actual_dockerfile=$(find "$task_dir/env" -maxdepth 1 -name "Dockerfile" -o -name "dockerfile" -o -name "DOCKERFILE" 2>/dev/null | head -1)
  
  if [ -z "$actual_dockerfile" ]; then
    errors+=("Dockerfile not found in $task_dir/env/")
  else
    local dockerfile_basename
    dockerfile_basename=$(basename "$actual_dockerfile")
    
    # Check exact casing
    if [ "$dockerfile_basename" != "Dockerfile" ]; then
      errors+=("Dockerfile must be capitalized as 'Dockerfile' (found: '$dockerfile_basename')")
    fi
    
    # Check Dockerfile content
    local dockerfile="$actual_dockerfile"
    
    # Check if debian-based (matches debian, ubuntu, or node:VERSION variants)
    # node:VERSION, node:VERSION-slim, node:VERSION-bookworm/bullseye/buster are all Debian-based
    # Using grep -i without ^ anchor to handle BOM or other leading characters
    if ! grep -Eiq 'FROM[[:space:]]+(debian|ubuntu|node:[0-9]+(-slim|-bookworm|-bullseye|-buster)?)' "$dockerfile"; then
      # Check if it's Alpine (explicitly not Debian)
      if grep -Eiq 'FROM[[:space:]]+.*alpine' "$dockerfile"; then
        warnings+=("Dockerfile uses Alpine base image - should be Debian-based (debian, ubuntu, or node:XX-bookworm)")
      else
        warnings+=("Dockerfile should be Debian-based (debian or ubuntu base image)")
      fi
    fi
    
    # Check Node.js version 20 or above
    if grep -Eiq 'node.*:.*[0-9]+' "$dockerfile"; then
      local node_version
      node_version=$(grep -Eio 'node.*:.*[0-9]+' "$dockerfile" | grep -Eo '[0-9]+' | head -1)
      if [ -n "$node_version" ] && [ "$node_version" -lt 20 ]; then
        errors+=("Dockerfile must install Node.js 20 or above (found version $node_version)")
      fi
    else
      warnings+=("Could not verify Node.js version in Dockerfile (should be 20+)")
    fi
    
    # Check for disallowed directives
    if grep -Eiq '^USER ' "$dockerfile"; then
      errors+=("Dockerfile must not contain USER directive")
    fi
    if grep -Eiq '^CMD ' "$dockerfile"; then
      errors+=("Dockerfile must not contain CMD directive")
    fi
    if grep -Eiq '^ENTRYPOINT ' "$dockerfile"; then
      errors+=("Dockerfile must not contain ENTRYPOINT directive")
    fi
    
    # Check gemini-cli is not installed
    if grep -Eiq 'gemini-cli|@google/gemini-cli' "$dockerfile"; then
      errors+=("Dockerfile must not install Gemini CLI (autobuild handles this)")
    fi
  fi
  
  # 2. Check prompt file
  if [ ! -f "$task_dir/prompt" ]; then
    errors+=("prompt file not found (must be named 'prompt' with no extension)")
  fi
  if [ -f "$task_dir/prompt.md" ] || [ -f "$task_dir/prompt.txt" ]; then
    errors+=("prompt file must not have extension (found .md or .txt)")
  fi
  
  # 3. Check verify folder
  if [ ! -d "$task_dir/verify" ]; then
    errors+=("verify/ folder not found")
  else
    # Check verify.sh exists
    if [ ! -f "$task_dir/verify/verify.sh" ]; then
      errors+=("verify/verify.sh not found")
    else
      # Check bash syntax (REQUIRED - blocking)
      local syntax_check
      syntax_check=$(bash -n "$task_dir/verify/verify.sh" 2>&1)
      if [ $? -ne 0 ]; then
        errors+=("verify.sh has bash syntax errors: $syntax_check")
      fi
      
      # Check for SUCCESS/FAILURE outputs in echo statements (REQUIRED - blocking)
      # Must be EXACT strings, not substring matches
      local has_success=false
      local has_failure=false
      
      # Check for exact SUCCESS in echo statements (word boundaries or end of string)
      if grep -Eiq '(echo|printf).*["\x27]SUCCESS["\x27]' "$task_dir/verify/verify.sh"; then
        has_success=true
      fi
      
      # Check for exact FAILURE in echo statements (word boundaries or end of string)
      if grep -Eiq '(echo|printf).*["\x27]FAILURE["\x27]([[:space:]]|$)' "$task_dir/verify/verify.sh"; then
        has_failure=true
      fi
      
      # Check for common mistakes
      # 1. FAIL instead of FAILURE
      if grep -Eq 'echo.*"FAIL"[[:space:]]*$' "$task_dir/verify/verify.sh"; then
        errors+=("verify.sh outputs 'FAIL' instead of 'FAILURE' - must use the complete word 'FAILURE'")
      fi
      
      # 2. FAILUREs or other variations (FAILURE with extra characters)
      if grep -Eiq '(echo|printf).*["\x27]FAILURE[a-zA-Z]' "$task_dir/verify/verify.sh"; then
        errors+=("verify.sh outputs 'FAILURE' with extra characters (e.g., 'FAILUREs') - must output exactly 'FAILURE'")
      fi
      
      # 3. SUCCESSs or other variations
      if grep -Eiq '(echo|printf).*["\x27]SUCCESS[a-zA-Z]' "$task_dir/verify/verify.sh"; then
        errors+=("verify.sh outputs 'SUCCESS' with extra characters - must output exactly 'SUCCESS'")
      fi
      
      if [ "$has_success" = false ] && [ "$has_failure" = false ]; then
        errors+=("verify.sh MUST output 'SUCCESS' for passing tests and 'FAILURE' for failing tests (in echo/printf statements)")
      elif [ "$has_success" = false ]; then
        errors+=("verify.sh MUST output 'SUCCESS' for passing tests (in echo/printf statements)")
      elif [ "$has_failure" = false ]; then
        errors+=("verify.sh MUST output 'FAILURE' for failing tests (in echo/printf statements)")
      fi
    fi
    
    # Check command file exists
    if [ ! -f "$task_dir/verify/command" ]; then
      errors+=("verify/command file not found (required)")
    else
      # Check command runs from workdir (should reference verify/ path)
      local cmd_content
      cmd_content=$(cat "$task_dir/verify/command")
      
      # REQUIRED: command MUST contain verify/ path (unless using --verify-script-in-workdir)
      if ! echo "$cmd_content" | grep -q 'verify/'; then
        errors+=("verify/command MUST reference verify/ path (e.g., 'bash verify/verify.sh'). Found: '$cmd_content'. Note: Use --verify-script-in-workdir flag only if verify files are in workdir root.")
      fi
      
      # Check for common mistakes
      if echo "$cmd_content" | grep -Eq '^\s*pwd\s+[^;|&]+\s*(&&|\|\|)'; then
        errors+=("verify/command has invalid syntax: 'pwd' command should not take arguments (did you mean 'cd'?)")
      fi
      
      if echo "$cmd_content" | grep -Eq 'cd\s+verify\s*(&&|\|\|)'; then
        warnings+=("verify/command uses 'cd verify' - consider using 'bash verify/verify.sh' from workdir instead")
      fi
    fi
  fi
  
  # 4. Check solution folder (if exists)
  if [ -d "$task_dir/solution" ]; then
    # Check solution_script.sh exists
    if [ ! -f "$task_dir/solution/solution_script.sh" ]; then
      errors+=("solution/solution_script.sh not found")
    else
      # Check bash syntax (REQUIRED - blocking)
      local syntax_check
      syntax_check=$(bash -n "$task_dir/solution/solution_script.sh" 2>&1)
      if [ $? -ne 0 ]; then
        errors+=("solution_script.sh has bash syntax errors: $syntax_check")
      fi
      
      # Check solution_script.sh does not run verification
      if grep -Eiq 'verify\.sh|verification' "$task_dir/solution/solution_script.sh"; then
        warnings+=("solution_script.sh should not run verification (verify.sh) - autobuild handles this")
      fi
    fi
    
    # Check solution.patch exists
    if [ ! -f "$task_dir/solution/solution.patch" ]; then
      errors+=("solution/solution.patch not found")
    fi
    
    # Check for extra files in solution folder (REQUIRED: only 2 files allowed)
    local file_count
    file_count=$(find "$task_dir/solution" -maxdepth 1 -type f | wc -l | tr -d ' ')
    if [ "$file_count" -gt 2 ]; then
      local extra_files
      extra_files=$(find "$task_dir/solution" -maxdepth 1 -type f ! -name "solution_script.sh" ! -name "solution.patch" -exec basename {} \; | tr '\n' ', ' | sed 's/,$//')
      errors+=("solution/ folder MUST only contain solution_script.sh and solution.patch (found extra file(s): $extra_files)")
    fi
    
    # Check for subdirectories in solution folder (REQUIRED: no subdirectories allowed)
    local dir_count
    dir_count=$(find "$task_dir/solution" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [ "$dir_count" -gt 0 ]; then
      local extra_dirs
      extra_dirs=$(find "$task_dir/solution" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | tr '\n' ', ' | sed 's/,$//')
      errors+=("solution/ folder MUST NOT contain subdirectories (found: $extra_dirs)")
    fi
  fi
  
  # 5. Check for extra files/folders in task root directory
  # Only allowed: env/, verify/, solution/, prompt
  local extra_items=()
  while IFS= read -r item; do
    local basename_item
    basename_item=$(basename "$item")
    # Skip allowed items
    case "$basename_item" in
      env|verify|solution|prompt|.DS_Store)
        continue
        ;;
      *)
        extra_items+=("$basename_item")
        ;;
    esac
  done < <(find "$task_dir" -maxdepth 1 -mindepth 1 ! -name "." 2>/dev/null)
  
  if [ ${#extra_items[@]} -gt 0 ]; then
    local extra_list
    extra_list=$(printf '%s, ' "${extra_items[@]}" | sed 's/, $//')
    errors+=("Task root directory must only contain: env/, verify/, solution/, prompt. Found extra item(s): $extra_list")
  fi
  
  # Report results
  if [ ${#errors[@]} -gt 0 ]; then
    log_error "Task validation FAILED with ${#errors[@]} error(s):"
    printf '  [ERROR] %s\n' "${errors[@]}" >&2
    
    # Write to log file
    if [ -n "$log_file" ]; then
      {
        echo "=== Validation Result: FAILED ==="
        echo ""
        echo "ERRORS (${#errors[@]}):"
        printf '  - %s\n' "${errors[@]}"
        echo ""
      } >> "$log_file"
    fi
    
    if [ ${#warnings[@]} -gt 0 ]; then
      log_warn "Also found ${#warnings[@]} warning(s):"
      printf '  [WARN] %s\n' "${warnings[@]}" >&2
      
      # Write warnings to log file
      if [ -n "$log_file" ]; then
        {
          echo "WARNINGS (${#warnings[@]}):"
          printf '  - %s\n' "${warnings[@]}"
          echo ""
        } >> "$log_file"
      fi
    fi
    
    # Write footer to log
    if [ -n "$log_file" ]; then
      {
        echo "=== Fix the errors above and re-run validation ==="
        log_info "Validation report saved to: $log_file"
      } >> "$log_file"
    fi
    
    return 1
  fi
  
  if [ ${#warnings[@]} -gt 0 ]; then
    log_warn "Task validation passed with ${#warnings[@]} warning(s):"
    printf '  [WARN] %s\n' "${warnings[@]}" >&2
    
    # Write to log file
    if [ -n "$log_file" ]; then
      {
        echo "=== Validation Result: PASSED (with warnings) ==="
        echo ""
        echo "WARNINGS (${#warnings[@]}):"
        printf '  - %s\n' "${warnings[@]}"
        echo ""
        echo "=== Task can proceed but consider addressing warnings ==="
      } >> "$log_file"
      log_info "Validation report saved to: $log_file"
    fi
  else
    log_info "Task validation passed - all requirements met"
    
    # Write to log file
    if [ -n "$log_file" ]; then
      {
        echo "=== Validation Result: PASSED ==="
        echo ""
        echo "All requirements met. No errors or warnings."
        echo ""
        echo "=== Task is ready for execution ==="
      } >> "$log_file"
      log_info "Validation report saved to: $log_file"
    fi
  fi
  
  return 0
}
resolve_abs_path() { local p="$1"; if [ -d "$p" ] || [ -f "$p" ]; then echo "$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"; else echo "$p"; fi; }
derive_task_name() { basename "$1"; }
derive_image_tag() {
  local task_name
  task_name="$(basename "$1")"
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local rand
  rand="$RANDOM"
  echo "autobuild-${task_name}:${ts}-${rand}"
}

is_abs_path() { case "$1" in /*) return 0 ;; *) return 1 ;; esac; }

# normalize "-v" style spec; ensures absolute host path and default ':ro' if not provided
build_bind() {
  local spec="$1"
  IFS=':' read -r host container mode <<<"$spec"
  [ -n "$host" ] && [ -n "$container" ] || { echo "[ERROR] invalid --mount spec '$spec' (host:container[:mode])" >&2; exit 1; }
  if [ -e "$host" ] && [[ "$host" != /* ]]; then
    host="$(cd "$(dirname "$host")" && pwd -P)/$(basename "$host")"
  fi
  [ -n "$mode" ] || mode="ro"
  printf "%s:%s:%s" "$host" "$container" "$mode"
}

# Return "<base>-YYYYMMDD_HHMMSS-<rand>"
unique_name() {
  local base="$1"
  printf "%s-%s-%s" "$base" "$(date +%Y%m%d_%H%M%S)" "$RANDOM"
}

copy_gcloud_creds_into_container() {
  local json="$1" container="$2" dest="/secrets/gcloud.json"
  [ -n "${json:-}" ] || return 0
  [ -f "$json" ] || { log_warn "gcloud creds JSON not found: $json"; return 0; }

  log_info "Installing gcloud credentials into container: $dest"
  docker exec -u root "$container" bash -lc "mkdir -p /secrets && chmod 700 /secrets"
  docker cp "$json" "$container:$dest"
  docker exec -u root "$container" bash -lc "chmod 600 $dest"
}

# Expand --env-mount entries into VOLUME_BINDS and USER_ENV_KV
expand_env_mount() {
  local entry names rhs host after ctr mode
  for entry in "${ENV_MOUNT[@]:-}"; do
    # Skip empties or sentinel values
    if [ -z "${entry//[[:space:]]/}" ]; then continue; fi
    case "$entry" in
      "-"|"none"|"null") continue ;;
    esac
    names="${entry%%=*}"          # NAME or NAME1,NAME2
    rhs="${entry#*=}"             # HOST->CTR[:MODE]
    host="${rhs%%->*}"
    after="${rhs#*->}"
    ctr="${after%%:*}"
    mode="${after#*:}"
    if [ "$after" = "$ctr" ]; then mode=""; fi
    if [ -z "$host" ] || [ -z "$ctr" ]; then
      die "Invalid --env-mount '${entry}'. Expected NAME=HOST->CTR[:MODE]"
    fi
    
    # Resolve host to absolute path if it exists and is relative
    if [ -e "$host" ] && [[ "$host" != /* ]]; then
      host="$(cd "$(dirname "$host")" && pwd -P)/$(basename "$host")"
    fi
    
    if [ -n "$mode" ] && [ "$mode" != "$after" ]; then
      VOLUME_BINDS+=("${host}:${ctr}:${mode}")
    else
      VOLUME_BINDS+=("${host}:${ctr}")
    fi
    IFS=',' read -r -a _nm <<< "$names"
    local n
    for n in "${_nm[@]}"; do
      USER_ENV_KV+=("${n}=${ctr}")
    done
  done
}

run_and_capture() {
  local logfile="$1"; shift
  mkdir -p "$(dirname "$logfile")"
  set +e
  "$@" 2>&1 | tee -a "$logfile"
  local rc=${PIPESTATUS[0]}
  set -e
  return $rc
}

parse_workdir_from_dockerfile() {
  local env_dir="$1"; local dockerfile="$env_dir/Dockerfile"
  if [ -f "$dockerfile" ]; then
    local wd
    wd=$(grep -iE '^[[:space:]]*WORKDIR[[:space:]]+' "$dockerfile" | tail -n 1 | awk '{print $2}') || true
    if [ -n "${wd:-}" ]; then echo "$wd"; return 0; fi
  fi
  echo "/workspace"
}

select_prompt_file() {
  local prompt_dir="$1"
  if [ -f "$prompt_dir/prompt.txt" ]; then echo "$prompt_dir/prompt.txt"; return 0; fi
  local first_file; first_file=$(find "$prompt_dir" -maxdepth 1 -type f -print | head -n 1 || true)
  [ -n "${first_file:-}" ] || die "No prompt file found in: $prompt_dir"
  echo "$first_file"
}

get_prompt_path() {
  local task_dir="$1"
  local p="$task_dir/prompt"
  if [ -f "$p" ]; then echo "$p"; return 0; fi
  if [ -d "$p" ]; then select_prompt_file "$p"; return 0; fi
  # Also allow prompt.txt directly under task
  if [ -f "$task_dir/prompt.txt" ]; then echo "$task_dir/prompt.txt"; return 0; fi
  die "Missing prompt file or directory: expected $task_dir/prompt or $task_dir/prompt.txt"
}

read_verification_command_from_path() {
  local verify_path="$1"
  local log_file="${2:-}"  # Optional: log file path for error logging
  
  # If --verify-command was provided, use it directly
  if [ -n "$VERIFY_COMMAND" ]; then
    echo "$VERIFY_COMMAND"
    return 0
  fi
  
  if [ -d "$verify_path" ]; then
    if [ -f "$verify_path/verification_command" ]; then cat "$verify_path/verification_command"; return 0; fi
    if [ -f "$verify_path/command" ]; then cat "$verify_path/command"; return 0; fi
    # No fallback to verify.sh - require explicit command file
    local err_msg="No verification command found in directory: $verify_path (expected 'command' or 'verification_command' file, or use --verify-command flag)"
    if [ -n "$log_file" ]; then
      {
        echo "=== Verification Command ==="
        echo "ERROR: $err_msg"
        echo "Verify path: $verify_path"
        echo "=== Output ==="
        echo ""
      } > "$log_file"
    fi
    die "$err_msg"
  fi
  if [ -f "$verify_path" ]; then
    cat "$verify_path"; return 0
  fi
  die "Verification path not found: $verify_path"
}

build_image() {
  local env_dir="$1"; local image_tag="$2"; local logfile="${3:-}"; local no_cache_flag="${4:-false}"
  log_info "Building image: $image_tag from $env_dir (no-cache=$no_cache_flag)"

  local extra_args=()
  if [ "$no_cache_flag" = "true" ]; then
    extra_args+=(--no-cache --pull)
  fi

  if [ -n "$logfile" ]; then
    if [ "${#extra_args[@]}" -gt 0 ]; then
      run_and_capture "$logfile" docker build "${extra_args[@]}" -t "$image_tag" "$env_dir"
    else
      run_and_capture "$logfile" docker build -t "$image_tag" "$env_dir"
    fi
  else
    if [ "${#extra_args[@]}" -gt 0 ]; then
      docker build "${extra_args[@]}" -t "$image_tag" "$env_dir"
    else
      docker build -t "$image_tag" "$env_dir"
    fi
  fi
  
  # Track image for cleanup
  CREATED_IMAGES+=("$image_tag")
}

run_container_keepalive() {
  local image_tag="$1"; local container_name="$2"; local env_file_path="${3:-}"
  log_info "Starting container: $container_name"
  if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
   docker run -v /var/run/docker.sock:/var/run/docker.sock \
     ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
     ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
     ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
     --env-file "$env_file_path" --name "$container_name" -d -i "$image_tag" tail -f /dev/null >/dev/null
  else
   docker run -v /var/run/docker.sock:/var/run/docker.sock \
     ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
     ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
     ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
     --name "$container_name" -d -i "$image_tag" tail -f /dev/null >/dev/null
  fi
  
  # Track container for cleanup
  CREATED_CONTAINERS+=("$container_name")
}

run_container_customer_exact() {
  local image_tag="$1"; local container_name="$2"; local env_file_path="${3:-}"
  log_info "Starting container (customer sequence): $container_name"
  if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
   docker run -v /var/run/docker.sock:/var/run/docker.sock \
     ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
     ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
     ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
     --env-file "$env_file_path" --name "$container_name" -d -i "$image_tag" >/dev/null || true
  else
   docker run -v /var/run/docker.sock:/var/run/docker.sock \
     ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
     ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
     ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
     --name "$container_name" -d -i "$image_tag" >/dev/null || true
  fi
  
  # Track container for cleanup
  CREATED_CONTAINERS+=("$container_name")
}

ensure_container_running() {
  local container_name="$1"
  docker ps --format '{{.Names}}' | grep -qx "$container_name" || die "Container $container_name is not running after docker run"
}

container_id_of() { local container_name="$1"; docker ps -aqf name="^${container_name}$"; }

configure_gemini_telemetry() {
  local container_name="$1"
  log_info "Configuring Gemini telemetry in container"
  docker exec -u root "$container_name" bash -lc '
    mkdir -p /root/.gemini
    cat > /root/.gemini/settings.json << '\''EOFTELEMETRY'\''
{
  "model": "gemini-3-pro-preview",
  "telemetry": {
    "enabled": true,
    "target": "local",
    "otlpEndpoint": "",
    "outfile": "/root/.gemini/telemetry.log"
  }
}
EOFTELEMETRY
  '
}

extract_telemetry_log() {
  local container_name="$1"
  local log_dir="$2"
  
  if [ -z "$container_name" ] || [ -z "$log_dir" ]; then
    return 0
  fi
  
  log_info "Extracting telemetry log from container"
  docker cp "$container_name:/root/.gemini/telemetry.log" "$log_dir/telemetry.log" 2>/dev/null || \
    log_warn "No telemetry log found in container (may not have been created yet)"
}

copy_prompt_into_container() {
  local prompt_file="$1"; local container_name="$2"; local workdir="$3"
  log_info "Copying prompt.txt into container"
  docker cp "$prompt_file" "$container_name:$workdir/prompt.txt"
}


copy_verify_to_container() {
  local verify_path="$1"; local container_name="$2"; local workdir="$3"
  if [ -d "$verify_path" ]; then
    if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
      log_info "Copying verify contents directly into workdir: $workdir/"
      # Copy contents directly into workdir (verify.sh will be at $workdir/verify.sh)
      docker cp "$verify_path/." "$container_name:$workdir/"
    else
      log_info "Copying verify directory into container: $workdir/verify/"
      # Copy verify directory as-is (creates $workdir/verify/ with contents inside)
      docker cp "$verify_path" "$container_name:$workdir/"
    fi
  elif [ -f "$verify_path" ]; then
    log_info "Copying verify file into container workdir: $workdir"
    docker cp "$verify_path" "$container_name:$workdir/"
  else
    die "Verify path does not exist: $verify_path"
  fi
}

compose_prompt1_file() {
  local src_prompt_file="$1"; local out_file="$2"
  local template_file="$PROMPTS_DIR/prompt1_template.txt"
  
  [ -f "$template_file" ] || die "Prompt template not found: $template_file"
  
  cat "$template_file" > "$out_file"
  echo >> "$out_file"
  cat "$src_prompt_file" >> "$out_file"
}

compose_prompt2_file() {
  local out_file="$1"
  local template_file="$PROMPTS_DIR/prompt2_template.txt"
  
  [ -f "$template_file" ] || die "Prompt template not found: $template_file"
  
  cat "$template_file" > "$out_file"
}

# --- build the Task Quality Audit Prompt into a file
compose_audit_prompt_file() {
  local out_file="$1"
  local template_file="$PROMPTS_DIR/audit_prompt_template.txt"
  
  [ -f "$template_file" ] || die "Prompt template not found: $template_file"
  
  cat "$template_file" > "$out_file"
}

# --- build the Solution Quality Audit Prompt into a file
compose_solution_audit_prompt_file() {
  local out_file="$1"
  local template_file="$PROMPTS_DIR/solution_audit_prompt_template.txt"
  
  [ -f "$template_file" ] || die "Prompt template not found: $template_file"
  
  cat "$template_file" > "$out_file"
}

# --- build the Solution Verification Analysis Prompt into a file
compose_solution_verify_prompt_file() {
  local out_file="$1"
  local template_file="$PROMPTS_DIR/solution_verify_prompt_template.txt"
  
  [ -f "$template_file" ] || die "Prompt template not found: $template_file"
  
  cat "$template_file" > "$out_file"
}

# --- copy prompt/verify/Dockerfile[/solution] into WORKDIR/_context inside container
copy_context_into_container() {
  local task_dir="$1"; local container_name="$2"; local workdir="$3"
  local include_solution="${4:-false}"
  local env_dir="$task_dir/env"
  local verify_dir="$task_dir/verify"
  local solution_dir="$task_dir/solution"

  local prompt_path; prompt_path="$(get_prompt_path "$task_dir")"
  [ -f "$prompt_path" ] || die "Prompt file not found (resolved to: $prompt_path)"
  [ -f "$verify_dir/verify.sh" ] || die "Missing $verify_dir/verify.sh"
  [ -f "$env_dir/Dockerfile" ]  || die "Missing $env_dir/Dockerfile"
  
  log_info "Using PROMPT:     $prompt_path"
  log_info "Using VERIFY DIR: $verify_dir"
  log_info "Using DOCKERFILE: $env_dir/Dockerfile"
  
  docker exec -u root "$container_name" bash -lc "mkdir -p '$workdir/_context/verify'"

  docker cp "$prompt_path"        "$container_name:$workdir/_context/prompt.txt"
  docker cp "$verify_dir/."       "$container_name:$workdir/_context/verify/"
  docker cp "$env_dir/Dockerfile" "$container_name:$workdir/_context/Dockerfile"

  # Optionally copy solution folder
  if [ "$include_solution" = "true" ] && [ -d "$solution_dir" ]; then
    log_info "Using SOLUTION DIR: $solution_dir"
    docker exec -u root "$container_name" bash -lc "mkdir -p '$workdir/_context/solution'"
    docker cp "$solution_dir/." "$container_name:$workdir/_context/solution/"
  fi

  docker exec -u root "$container_name" bash -lc "set -e; echo '[_context tree]'; ls -la '$workdir/_context'; echo; echo '[_context/verify tree]'; ls -la '$workdir/_context/verify' || true; echo; echo '[_context/solution tree]'; ls -la '$workdir/_context/solution' 2>/dev/null || echo '(solution not included)'"
}

feedback() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local gemini_api_key="$5"
  local log_dir="$6"
  local env_file_path="${7:-}"

  local env_dir="$task_dir/env"
  local verify_dir_candidate="$task_dir/verify"
  local verify_file_candidate="$task_dir/command"
  local prompt_path; prompt_path=$(get_prompt_path "$task_dir")

  [ -d "$env_dir" ] || die "Missing env directory: $env_dir"

  local verify_path=""
  if [ -d "$verify_dir_candidate" ] || [ -f "$verify_dir_candidate" ]; then
    verify_path="$verify_dir_candidate"
  elif [ -f "$verify_file_candidate" ]; then
    verify_path="$verify_file_candidate"
  else
    die "Missing verify path: expected $verify_dir_candidate (dir or file) or $verify_file_candidate (file)"
  fi

  mkdir -p "$log_dir"

  build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"

  # Determine and normalize workdir
  if [ -z "$workdir" ]; then
    workdir=$(parse_workdir_from_dockerfile "$env_dir")
    log_info "Using WORKDIR from Dockerfile: $workdir"
  fi
  workdir=$(echo "$workdir" | tr -d '\r')
  workdir="${workdir%/}"

  run_container_keepalive "$image_tag" "$container_name" "$env_file_path"
  ensure_container_running "$container_name"
  copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"
  docker exec -u root "$container_name" bash -lc "mkdir -p '$workdir' || true"

  copy_verify_to_container "$verify_path" "$container_name" "$workdir"
  copy_prompt_into_container "$prompt_path" "$container_name" "$workdir"

  # Prepare prompts on host and copy into container and logs
  local tmpdir; tmpdir=$(mktemp -d)
  compose_prompt1_file "$prompt_path" "$tmpdir/prompt1.txt"
  compose_prompt2_file "$tmpdir/prompt2.txt"
  cp "$tmpdir/prompt1.txt" "$log_dir/prompt1.txt"
  cp "$tmpdir/prompt2.txt" "$log_dir/prompt2.txt"
  docker cp "$tmpdir/prompt1.txt" "$container_name:$workdir/prompt1.txt"
  docker cp "$tmpdir/prompt2.txt" "$container_name:$workdir/prompt2.txt"

  # Install Gemini CLI globally inside the container
  log_info "Installing Gemini CLI v ${gemini_cli_version} inside container"
  run_and_capture "$log_dir/gemini_install.log" docker exec -u root "$container_name" bash -lc \
  "which npm >/dev/null 2>&1 || (echo 'npm is required in the image' >&2; exit 1); npm install -g @google/gemini-cli@${gemini_cli_version}"

  # Configure telemetry before running Gemini
  configure_gemini_telemetry "$container_name"

  # Run Prompt 1
  log_info "Running Prompt 1 with gemini CLI"
  run_and_capture "$log_dir/gemini_prompt1.log" docker exec -i ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" -e AUTOBUILD_WORKDIR="$workdir" "$container_name" \
    bash -lc 'cd "$AUTOBUILD_WORKDIR" && PROMPT=$(cat prompt1.txt) && gemini --debug -y --prompt "$PROMPT"'

  # Run verification
  local verification_cmd; verification_cmd=$(read_verification_command_from_path "$verify_path" "$log_dir/verification.log")
  printf '%s' "$verification_cmd" > "$log_dir/verification_command.txt"
  log_info "Running verification: $verification_cmd"

  local exec_prefix=""
  if [ -n "${GCLOUD_CREDS_JSON:-}" ]; then
    exec_prefix="export GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json; "
  fi

  # Log verification command info to verification.log
  {
    echo "=== Verification Command ==="
    echo "Command: $verification_cmd"
    echo "Workdir: $workdir"
    echo "Verify script in workdir: $VERIFY_SCRIPT_IN_WORKDIR"
    echo "=== Output ==="
    echo ""
  } > "$log_dir/verification.log"

  # Always execute from workdir; chmod the verify.sh wherever it was copied
  set +e
  if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
    run_and_capture "$log_dir/verification.log" docker exec -u root "$container_name" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify.sh 2>/dev/null || true && $verification_cmd"
  else
    run_and_capture "$log_dir/verification.log" docker exec -u root "$container_name" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify/verify.sh 2>/dev/null || true && $verification_cmd"
  fi
  local verify_rc=$?
  set -e

  if [ "$verify_rc" -eq 0 ]; then
    log_info "Verification passed; running Prompt 2"
    run_and_capture "$log_dir/gemini_prompt2.log" docker exec -i ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" -e AUTOBUILD_WORKDIR="$workdir" "$container_name" \
      bash -lc 'cd "$AUTOBUILD_WORKDIR" && PROMPT=$(cat prompt2.txt) && gemini --debug -y --prompt "$PROMPT"'
  else
    log_warn "Verification failed; skipping Prompt 2. Exit code: $verify_rc"
  fi

  # Extract telemetry log before cleanup
  extract_telemetry_log "$container_name" "$log_dir"

  log_info "Feedback step complete"
}

verify() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local gemini_api_key="$5"
  local log_dir="$6"
  local env_file_path="${7:-}"

  local env_dir="$task_dir/env"
  local verify_dir_candidate="$task_dir/verify"
  local verify_file_candidate="$task_dir/command"
  local prompt_path; prompt_path=$(get_prompt_path "$task_dir")

  [ -d "$env_dir" ] || die "Missing env directory: $env_dir"

  local verify_path=""
  if [ -d "$verify_dir_candidate" ] || [ -f "$verify_dir_candidate" ]; then
    verify_path="$verify_dir_candidate"
  elif [ -f "$verify_file_candidate" ]; then
    verify_path="$verify_file_candidate"
  else
    die "Missing verify path: expected $verify_dir_candidate (dir or file) or $verify_file_candidate (file)"
  fi

  mkdir -p "$log_dir"

  # Read RAW prompt content and log it
  local prompt_raw; prompt_raw=$(cat "$prompt_path")
  printf '%s' "$prompt_raw" > "$log_dir/prompt_raw.txt"

  build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"
  run_container_customer_exact "$image_tag" "$container_name" "$env_file_path"
  ensure_container_running "$container_name"
  copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"

  # Initialize npm global directory
  log_info "Initializing npm global directory structure"
  docker exec "$container_name" bash -lc "mkdir -p ~/.npm-global/{lib,bin} && npm config set prefix ~/.npm-global" \
    2>&1 | tee -a "$log_dir/npm_init.log" || true

  # Configure telemetry before running Gemini
  configure_gemini_telemetry "$container_name"

  log_info "Running Gemini via npx in container (customer sequence)"
  run_and_capture "$log_dir/gemini_npx.log" docker exec -i ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" "$container_name" \
  npx --yes @google/gemini-cli@${gemini_cli_version} --yolo --debug --prompt "$prompt_raw"

  local cid; cid=$(container_id_of "$container_name")
  log_info "docker inspect $cid"
  docker inspect "$cid" > "$log_dir/docker_inspect.json"

  # Determine and normalize workdir
  if [ -z "$workdir" ]; then
    workdir=$(parse_workdir_from_dockerfile "$env_dir")
    log_info "Using WORKDIR from Dockerfile: $workdir"
  fi
  workdir=$(echo "$workdir" | tr -d '\r')
  workdir="${workdir%/}"

  docker exec -u root "$cid" bash -lc "mkdir -p '$workdir' || true"

  # Copy verify and prompt into container after Gemini run
  copy_verify_to_container "$verify_path" "$container_name" "$workdir"
  copy_prompt_into_container "$prompt_path" "$container_name" "$workdir"

  local verification_cmd; verification_cmd=$(read_verification_command_from_path "$verify_path" "$log_dir/verification.log")
  printf '%s' "$verification_cmd" > "$log_dir/verification_command.txt"
  log_info "Executing verification in container: $verification_cmd"

  local exec_prefix=""
  if [ -n "${GCLOUD_CREDS_JSON:-}" ]; then
    exec_prefix="export GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json; "
  fi

  # Log verification command info to verification.log
  {
    echo "=== Verification Command ==="
    echo "Command: $verification_cmd"
    echo "Workdir: $workdir"
    echo "Verify script in workdir: $VERIFY_SCRIPT_IN_WORKDIR"
    echo "=== Output ==="
    echo ""
  } > "$log_dir/verification.log"

  # Always execute from workdir; chmod the verify.sh wherever it was copied
  if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
    run_and_capture "$log_dir/verification.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify.sh 2>/dev/null || true && $verification_cmd"
  else
    run_and_capture "$log_dir/verification.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify/verify.sh 2>/dev/null || true && $verification_cmd"
  fi

  # Extract telemetry log before cleanup
  extract_telemetry_log "$container_name" "$log_dir"

  log_info "Verify step complete"
}

audit() {
    local task_dir="$1"
    local image_tag="$2"
    local container_name="$3"
    local workdir="$4"
    local gemini_api_key="$5"
    local log_dir="$6"
    local env_file_path="${7:-}"
    local env_dir="$task_dir/env"

    # Ensure env_dir exists
    [ -d "$env_dir" ] || die "Missing env directory: $env_dir"
    mkdir -p "$log_dir"

    # Build Docker image
    build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"

    # Determine workdir if not provided
    if [ -z "$workdir" ]; then
        workdir=$(parse_workdir_from_dockerfile "$env_dir")
        log_info "Using WORKDIR from Dockerfile: $workdir"
    fi
    workdir=$(echo "$workdir" | tr -d '\r')  # strip Windows \r
    workdir="${workdir%/}"                   # remove trailing slash

    # Start container WITHOUT mounting host directory
    log_info "Starting container: $container_name"
    if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
      docker run -d -i \
        ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
        ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
        ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
        --env-file "$env_file_path" \
        --name "$container_name" \
        "$image_tag" tail -f /dev/null
    else
      docker run -d -i \
        ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
        ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
        ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
        --name "$container_name" \
        "$image_tag" tail -f /dev/null
    fi
    ensure_container_running "$container_name"
    copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"

    # Ensure _context exists and copy task files using your helper
    log_info "Ensuring _context exists and copying task files"
    copy_context_into_container "$task_dir" "$container_name" "$workdir" "true"

    # Prepare and copy audit prompt
    local tmpdir
    tmpdir=$(mktemp -d)
    compose_audit_prompt_file "$tmpdir/audit_prompt.txt"
    cp "$tmpdir/audit_prompt.txt" "$log_dir/audit_prompt.txt"
    docker cp "$tmpdir/audit_prompt.txt" "$container_name:$workdir/_context/audit_prompt.txt"

    # Install Gemini CLI
    log_info "Installing Gemini CLI v ${gemini_cli_version} inside container"
    run_and_capture "$log_dir/gemini_install.log" docker exec -u root "$container_name" bash -lc \
  "command -v npm >/dev/null 2>&1 || { echo 'npm is required'; exit 1; }; npm install -g @google/gemini-cli@${gemini_cli_version}"

    # Configure telemetry before running Gemini
    configure_gemini_telemetry "$container_name"

    # Run audit and capture logs
    log_info "Running audit prompt"
    run_and_capture "$log_dir/gemini_audit.log" docker exec ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" "$container_name" bash -lc "\
set -Eeuo pipefail; \
cd '$workdir/_context'; \
[ -s audit_prompt.txt ] || { echo '[ERROR] audit_prompt.txt missing or empty in $(pwd)' >&2; ls -la >&2; exit 1; }; \
gemini --debug -y < audit_prompt.txt"

    # Extract telemetry log before cleanup
    extract_telemetry_log "$container_name" "$log_dir"

    log_info "Audit complete. Logs at: $log_dir"
}

solution() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local log_dir="$5"
  local env_file_path="${6:-}"

  local env_dir="$task_dir/env"
  local solution_dir="$task_dir/solution"
  local verify_dir_candidate="$task_dir/verify"
  local verify_file_candidate="$task_dir/command"

  [ -d "$env_dir" ] || die "Missing env directory: $env_dir"
  [ -d "$solution_dir" ] || die "Missing solution directory: $solution_dir"
  [ -f "$solution_dir/solution_script.sh" ] || die "Missing solution_script.sh in: $solution_dir"

  local verify_path=""
  if [ -d "$verify_dir_candidate" ] || [ -f "$verify_dir_candidate" ]; then
    verify_path="$verify_dir_candidate"
  elif [ -f "$verify_file_candidate" ]; then
    verify_path="$verify_file_candidate"
  else
    die "Missing verify path: expected $verify_dir_candidate (dir or file) or $verify_file_candidate (file)"
  fi

  mkdir -p "$log_dir"

  # Build Docker image
  build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"

  # Run container with keepalive
  log_info "Starting container: $container_name"
  if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
    docker run -d -i "${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"}" ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} --env-file "$env_file_path" --name "$container_name" "$image_tag" tail -f /dev/null
  else
    docker run -d -i "${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"}" ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} --name "$container_name" "$image_tag" tail -f /dev/null
  fi
  ensure_container_running "$container_name"
  copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"

  # Determine and normalize workdir
  if [ -z "$workdir" ]; then
    workdir=$(parse_workdir_from_dockerfile "$env_dir")
    log_info "Using WORKDIR from Dockerfile: $workdir"
  fi
  workdir=$(echo "$workdir" | tr -d '\r')
  workdir="${workdir%/}"

  local cid; cid=$(container_id_of "$container_name")
  docker exec -u root "$cid" bash -lc "mkdir -p '$workdir' || true"

  # Copy solution folder into container
  log_info "Copying solution/ folder into container at $workdir/solution"
  docker cp "$solution_dir" "$container_name:$workdir/"
  docker exec -u root "$cid" bash -lc "chmod +x '$workdir/solution/solution_script.sh'"

  # Copy verify folder to workdir/verify/
  copy_verify_to_container "$verify_path" "$container_name" "$workdir"

  # Run solution script
  log_info "Running solution_script.sh in container"
  local exec_prefix="export SOLUTION_DIR='$workdir/solution'; export WORKDIR='$workdir'; "
  if [ -n "${GCLOUD_CREDS_JSON:-}" ]; then
    exec_prefix+="export GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json; "
  fi
  run_and_capture "$log_dir/solution_script.log" docker exec -u root "$cid" bash -lc \
    "${exec_prefix}cd '$workdir' && '$workdir/solution/solution_script.sh'"

  # Run verification
  local verification_cmd; verification_cmd=$(read_verification_command_from_path "$verify_path" "$log_dir/verification.log")
  printf '%s' "$verification_cmd" > "$log_dir/verification_command.txt"
  log_info "Executing verification in container: $verification_cmd"

  # Log verification command info to verification.log
  {
    echo "=== Verification Command ==="
    echo "Command: $verification_cmd"
    echo "Workdir: $workdir"
    echo "Verify script in workdir: $VERIFY_SCRIPT_IN_WORKDIR"
    echo "=== Output ==="
    echo ""
  } > "$log_dir/verification.log"

  # Always execute from workdir; chmod the verify.sh wherever it was copied
  if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
    run_and_capture "$log_dir/verification.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify.sh 2>/dev/null || true && $verification_cmd"
  else
    run_and_capture "$log_dir/verification.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify/verify.sh 2>/dev/null || true && $verification_cmd"
  fi

  log_info "Solution step complete"
}

solution_audit() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local gemini_api_key="$5"
  local log_dir="$6"
  local env_file_path="${7:-}"

  local env_dir="$task_dir/env"
  local solution_dir="$task_dir/solution"

  [ -d "$env_dir" ] || die "Missing env directory: $env_dir"
  [ -d "$solution_dir" ] || die "Missing solution directory: $solution_dir (required for solution_audit mode)"

  mkdir -p "$log_dir"

  # Build Docker image
  build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"

  # Determine and normalize workdir
  if [ -z "$workdir" ]; then
    workdir=$(parse_workdir_from_dockerfile "$env_dir")
    log_info "Using WORKDIR from Dockerfile: $workdir"
  fi
  workdir=$(echo "$workdir" | tr -d '\r')
  workdir="${workdir%/}"

  # Start container
  log_info "Starting container: $container_name"
  if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
    docker run -d -i \
      ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
      ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
      ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
      --env-file "$env_file_path" \
      --name "$container_name" \
      "$image_tag" tail -f /dev/null
  else
    docker run -d -i \
      ${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"} \
      ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
      ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
      --name "$container_name" \
      "$image_tag" tail -f /dev/null
  fi
  ensure_container_running "$container_name"
  copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"

  # Copy all context including solution
  log_info "Copying context (prompt, verify, Dockerfile, solution) into _context/"
  copy_context_into_container "$task_dir" "$container_name" "$workdir" "true"

  # Prepare solution audit prompt
  local tmpdir; tmpdir=$(mktemp -d)
  compose_solution_audit_prompt_file "$tmpdir/solution_audit_prompt.txt"
  cp "$tmpdir/solution_audit_prompt.txt" "$log_dir/solution_audit_prompt.txt"
  docker cp "$tmpdir/solution_audit_prompt.txt" "$container_name:$workdir/_context/solution_audit_prompt.txt"

  # Install Gemini CLI
  log_info "Installing Gemini CLI v ${gemini_cli_version} inside container"
  run_and_capture "$log_dir/gemini_install.log" docker exec -u root "$container_name" bash -lc \
    "command -v npm >/dev/null 2>&1 || { echo 'npm is required'; exit 1; }; npm install -g @google/gemini-cli@${gemini_cli_version}"

  # Configure telemetry before running Gemini
  configure_gemini_telemetry "$container_name"

  # Run solution audit
  log_info "Running solution audit (quality check without execution)"
  run_and_capture "$log_dir/gemini_solution_audit.log" docker exec ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" "$container_name" bash -lc "\
set -Eeuo pipefail; \
cd '$workdir/_context'; \
[ -s solution_audit_prompt.txt ] || { echo '[ERROR] solution_audit_prompt.txt missing' >&2; exit 1; }; \
gemini --debug -y < solution_audit_prompt.txt"

  # Extract telemetry log before cleanup
  extract_telemetry_log "$container_name" "$log_dir"

  log_info "Solution audit complete. Logs at: $log_dir"
}

solution_verify() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local gemini_api_key="$5"
  local log_dir="$6"
  local env_file_path="${7:-}"

  local env_dir="$task_dir/env"
  local solution_dir="$task_dir/solution"
  local verify_dir_candidate="$task_dir/verify"
  local verify_file_candidate="$task_dir/command"

  [ -d "$env_dir" ] || die "Missing env directory: $env_dir"
  [ -d "$solution_dir" ] || die "Missing solution directory: $solution_dir (required for solution_verify mode)"

  local verify_path=""
  if [ -d "$verify_dir_candidate" ] || [ -f "$verify_dir_candidate" ]; then
    verify_path="$verify_dir_candidate"
  elif [ -f "$verify_file_candidate" ]; then
    verify_path="$verify_file_candidate"
  else
    die "Missing verify path: expected $verify_dir_candidate (dir or file) or $verify_file_candidate (file)"
  fi

  mkdir -p "$log_dir"

  # Build Docker image
  build_image "$env_dir" "$image_tag" "$log_dir/docker_build.log" "$no_cache"

  # Determine and normalize workdir
  if [ -z "$workdir" ]; then
    workdir=$(parse_workdir_from_dockerfile "$env_dir")
    log_info "Using WORKDIR from Dockerfile: $workdir"
  fi
  workdir=$(echo "$workdir" | tr -d '\r')
  workdir="${workdir%/}"

  # Start container
  log_info "Starting container: $container_name"
  if [ -n "${env_file_path:-}" ] && [ -f "$env_file_path" ]; then
    docker run -d -i "${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"}" \
      ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
      ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
      --env-file "$env_file_path" --name "$container_name" "$image_tag" tail -f /dev/null
  else
    docker run -d -i "${VOLUME_ARGS[@]+"${VOLUME_ARGS[@]}"}" \
      ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} \
      ${DOCKER_RUN_ARGS[@]+"${DOCKER_RUN_ARGS[@]}"} \
      --name "$container_name" "$image_tag" tail -f /dev/null
  fi
  ensure_container_running "$container_name"
  copy_gcloud_creds_into_container "$GCLOUD_CREDS_JSON" "$container_name"

  local cid; cid=$(container_id_of "$container_name")
  docker exec -u root "$cid" bash -lc "mkdir -p '$workdir' || true"

  # Copy verify folder FIRST (before solution) to run initial verification
  copy_verify_to_container "$verify_path" "$container_name" "$workdir"

  # STEP 1: Run verification BEFORE applying solution (should FAIL)
  log_info "Running verification BEFORE applying solution (should show FAILURE)"
  local verification_cmd; verification_cmd=$(read_verification_command_from_path "$verify_path" "$log_dir/verification_failure.log")
  
  # Log verification command info to verification_failure.log
  {
    echo "=== Pre-Solution Verification (Expected: FAILURE) ==="
    echo "Command: $verification_cmd"
    echo "Workdir: $workdir"
    echo "Verify script in workdir: $VERIFY_SCRIPT_IN_WORKDIR"
    echo "=== Output ==="
    echo ""
  } > "$log_dir/verification_failure.log"

  local exec_prefix="export WORKDIR='$workdir'; "
  if [ -n "${GCLOUD_CREDS_JSON:-}" ]; then
    exec_prefix+="export GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json; "
  fi

  # Run pre-solution verification (expect failure)
  # Use && ... || pattern to capture exit code without triggering set -e
  local pre_verify_rc=0
  if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
    run_and_capture "$log_dir/verification_failure.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify.sh 2>/dev/null || true && $verification_cmd" \
      && pre_verify_rc=0 || pre_verify_rc=$?
  else
    run_and_capture "$log_dir/verification_failure.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify/verify.sh 2>/dev/null || true && $verification_cmd" \
      && pre_verify_rc=0 || pre_verify_rc=$?
  fi

  if [ $pre_verify_rc -eq 0 ]; then
    log_warn "Pre-solution verification passed (expected to fail) - verification may not be catching the issue"
  else
    log_info "Pre-solution verification failed as expected (exit code: $pre_verify_rc)"
  fi

  # STEP 2: Copy and execute solution
  log_info "Copying and executing solution"
  docker cp "$solution_dir" "$container_name:$workdir/"
  docker exec -u root "$cid" bash -lc "chmod +x '$workdir/solution/solution_script.sh'"

  # Run solution script
  exec_prefix="export SOLUTION_DIR='$workdir/solution'; export WORKDIR='$workdir'; "
  if [ -n "${GCLOUD_CREDS_JSON:-}" ]; then
    exec_prefix+="export GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json; "
  fi
  run_and_capture "$log_dir/solution_script.log" docker exec -u root "$cid" bash -lc \
    "${exec_prefix}cd '$workdir' && '$workdir/solution/solution_script.sh'"

  # STEP 3: Run verification AFTER applying solution (should SUCCEED)
  log_info "Running verification AFTER applying solution (should show SUCCESS)"
  printf '%s' "$verification_cmd" > "$log_dir/verification_command.txt"

  # Log verification command info to verification_success.log
  {
    echo "=== Post-Solution Verification (Expected: SUCCESS) ==="
    echo "Command: $verification_cmd"
    echo "Workdir: $workdir"
    echo "Verify script in workdir: $VERIFY_SCRIPT_IN_WORKDIR"
    echo "=== Output ==="
    echo ""
  } > "$log_dir/verification_success.log"

  # Run post-solution verification (expect success)
  # Use && ... || pattern to capture exit code without triggering set -e
  local verify_rc=0
  if [ "$VERIFY_SCRIPT_IN_WORKDIR" = "true" ]; then
    run_and_capture "$log_dir/verification_success.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify.sh 2>/dev/null || true && $verification_cmd" \
      && verify_rc=0 || verify_rc=$?
  else
    run_and_capture "$log_dir/verification_success.log" docker exec -u root "$cid" bash -lc \
      "${exec_prefix}cd '$workdir' && chmod +x verify/verify.sh 2>/dev/null || true && $verification_cmd" \
      && verify_rc=0 || verify_rc=$?
  fi

  # Copy context for Gemini analysis
  log_info "Copying context for post-verification analysis"
  copy_context_into_container "$task_dir" "$container_name" "$workdir" "true"

  # Install Gemini CLI
  log_info "Installing Gemini CLI v ${gemini_cli_version}"
  run_and_capture "$log_dir/gemini_install.log" docker exec -u root "$container_name" bash -lc \
    "command -v npm >/dev/null 2>&1 || { echo 'npm is required'; exit 1; }; npm install -g @google/gemini-cli@${gemini_cli_version}"

  # Configure telemetry before running Gemini
  configure_gemini_telemetry "$container_name"

  # Prepare solution verify prompt
  local tmpdir; tmpdir=$(mktemp -d)
  compose_solution_verify_prompt_file "$tmpdir/solution_verify_prompt.txt"
  cp "$tmpdir/solution_verify_prompt.txt" "$log_dir/solution_verify_prompt.txt"
  docker cp "$tmpdir/solution_verify_prompt.txt" "$container_name:$workdir/_context/solution_verify_prompt.txt"

  # Run Gemini analysis on results
  log_info "Running Gemini analysis on solution execution results (verify_rc=$verify_rc)"
  run_and_capture "$log_dir/gemini_solution_verify.log" docker exec ${EXEC_ENV_ARGS[@]+"${EXEC_ENV_ARGS[@]}"} -e GEMINI_API_KEY="$gemini_api_key" "$container_name" bash -lc "\
set -Eeuo pipefail; \
cd '$workdir/_context'; \
[ -s solution_verify_prompt.txt ] || { echo '[ERROR] solution_verify_prompt.txt missing' >&2; exit 1; }; \
gemini --debug -y < solution_verify_prompt.txt"

  # Extract telemetry log before cleanup
  extract_telemetry_log "$container_name" "$log_dir"

  log_info "Solution verification and analysis complete. Logs at: $log_dir"
  log_info "Verification exit code: $verify_rc"
}

auto_review() {
  local task_dir="$1"
  local image_tag="$2"
  local container_name="$3"
  local workdir="$4"
  local gemini_api_key="$5"
  local log_dir="$6"
  local env_file_path="${7:-}"

  log_info "=== AUTO REVIEW: Starting comprehensive review ==="
  log_info "This will run: solution_verify → audit → verify"
  
  mkdir -p "$log_dir"
  
  # Step 1: Run solution_verify
  log_info "=== STEP 1/3: Running solution_verify ==="
  local sv_log_dir="$log_dir/solution_verify"
  mkdir -p "$sv_log_dir"
  local cname_sv="${container_name}-solution-verify-$(date +%s)"
  local sv_image_tag="${image_tag:-$(derive_image_tag "$task_dir")}"
  
  solution_verify "$task_dir" "$sv_image_tag" "$cname_sv" "$workdir" "$gemini_api_key" "$sv_log_dir" "${env_file_path:-}"
  
  log_info ""
  log_info ">>> SOLUTION_VERIFY completed"
  log_info ""
  
  # Step 2: Run audit
  log_info "=== STEP 2/3: Running audit ==="
  local audit_log_dir="$log_dir/audit"
  mkdir -p "$audit_log_dir"
  local cname_audit="${container_name}-audit-$(date +%s)"
  local audit_image_tag="${image_tag:-$(derive_image_tag "$task_dir")}"
  
  audit "$task_dir" "$audit_image_tag" "$cname_audit" "$workdir" "$gemini_api_key" "$audit_log_dir" "${env_file_path:-}"
  
  log_info ""
  log_info ">>> AUDIT completed"
  log_info ""
  
  # Step 3: Run verify
  log_info "=== STEP 3/3: Running verify ==="
  local verify_log_dir="$log_dir/verify"
  mkdir -p "$verify_log_dir"
  local cname_verify="${container_name}-verify-$(date +%s)"
  local verify_image_tag="${image_tag:-$(derive_image_tag "$task_dir")}"
  
  verify "$task_dir" "$verify_image_tag" "$cname_verify" "$workdir" "$gemini_api_key" "$verify_log_dir" "${env_file_path:-}"
  
  log_info ""
  log_info ">>> VERIFY completed"
  log_info ""
  
  # Create review_summary folder with consolidated key logs
  log_info "=== Creating review_summary folder ==="
  local summary_dir="$log_dir/review_summary"
  mkdir -p "$summary_dir"
  
  # From solution_verify: solution_script.log, verification.log → verification_solution_success.log, gemini_solution_verify.log
  if [ -f "$sv_log_dir/solution_script.log" ]; then
    cp "$sv_log_dir/solution_script.log" "$summary_dir/solution_script.log"
  fi
  if [ -f "$sv_log_dir/verification.log" ]; then
    cp "$sv_log_dir/verification.log" "$summary_dir/verification_solution_success.log"
  fi
  if [ -f "$sv_log_dir/gemini_solution_verify.log" ]; then
    cp "$sv_log_dir/gemini_solution_verify.log" "$summary_dir/gemini_solution_verify.log"
  fi
  
  # From audit: gemini_audit.log
  if [ -f "$audit_log_dir/gemini_audit.log" ]; then
    cp "$audit_log_dir/gemini_audit.log" "$summary_dir/gemini_audit.log"
  fi
  
  # From verify: verification.log → verify.log
  if [ -f "$verify_log_dir/verification.log" ]; then
    cp "$verify_log_dir/verification.log" "$summary_dir/verify.log"
  fi
  
  log_info "=== AUTO REVIEW COMPLETE ==="
  log_info ""
  log_info "Review summary files consolidated at: $summary_dir"
  log_info "  - solution_script.log"
  log_info "  - verification_solution_success.log"
  log_info "  - gemini_solution_verify.log"
  log_info "  - gemini_audit.log"
  log_info "  - verify.log"
  log_info ""
  log_info "Full logs for each step available in:"
  log_info "  - $sv_log_dir"
  log_info "  - $audit_log_dir"
  log_info "  - $verify_log_dir"
}

main() {
  require_cmd docker
  validate_prompt_templates
  no_cache="true"  # Default to no-cache for reliability
  local mode="" task_dir="" image_tag="" container_name="" workdir="" api_key="${GEMINI_API_KEY:-}" output_dir="" env_file="${AUTOBUILD_ENV_FILE:-}"
  [ $# -ge 1 ] || { usage; exit 1; }
  mode="$1"; shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --task)               task_dir="$(resolve_abs_path "$2")"; shift 2;;
      --image-tag)          image_tag="$2"; shift 2;;
      --container-name)     container_name="$2"; shift 2;;
      --workdir)            workdir="$2"; shift 2;;
      --api-key)            api_key="$2"; shift 2;;
      --output-dir)         output_dir="$2"; shift 2;;
      --env-file)           env_file="$(resolve_abs_path "$2")"; shift 2;;
      -h|--help)            usage; exit 0;;
      --no-cache)           no_cache="true"; shift ;;
      --cache)              no_cache="false"; shift ;;
      --keep-artifacts)     CLEANUP_ENABLED="false"; shift ;;
      --skip-validation)    SKIP_VALIDATION="true"; shift ;;
      --verify-script-in-workdir) VERIFY_SCRIPT_IN_WORKDIR="true"; shift ;;
      --verify-command)     VERIFY_COMMAND="$2"; shift 2;;
      --verify-command=*)   VERIFY_COMMAND="${1#*=}"; shift 1;;
      --docker-arg)         read -ra _docker_args <<< "$2"; DOCKER_RUN_ARGS+=("${_docker_args[@]}"); shift 2;;
      --docker-arg=*)       read -ra _docker_args <<< "${1#*=}"; DOCKER_RUN_ARGS+=("${_docker_args[@]}"); shift 1;;
      --gemini-cli-version) gemini_cli_version="$2"; shift 2;;
      --gcloud-creds)       GCLOUD_CREDS_JSON="$2"; log_warn "--gcloud-creds is deprecated; use --env-mount"; shift 2 ;;
      --gcloud-creds=*)     GCLOUD_CREDS_JSON="${1#*=}"; log_warn "--gcloud-creds is deprecated; use --env-mount"; shift 1 ;;
      --mount)              VOLUME_BINDS+=("$(build_bind "$2")"); shift 2;;
      --mount=*)            VOLUME_BINDS+=("$(build_bind "${1#*=}")"); shift 1;;
      -v)                   VOLUME_BINDS+=("$(build_bind "$2")"); shift 2;;
      -v=*)                 VOLUME_BINDS+=("$(build_bind "${1#*=}")"); shift 1;;
      --env)                USER_ENV_KV+=("${2:?format NAME=VALUE}"); shift 2;;
      --env=*)              USER_ENV_KV+=("${1#*=}"); shift 1;;
      --env-mount)
        # Allow empty values (useful when flag comes from an optional var)
        if [ -n "${2:-}" ]; then ENV_MOUNT+=("${2}"); fi
        shift 2;;
      --env-mount=*)
        _val="${1#*=}"
        if [ -n "${_val:-}" ]; then ENV_MOUNT+=("${_val}"); fi
        shift 1;;

      *)                    log_error "Unknown arg: $1"; usage; exit 1;;
    esac
  done

  # Expand combined flags before building docker args
  expand_env_mount

  # Build EXEC_ENV_ARGS (docker run & docker exec -e ...)
  EXEC_ENV_ARGS=()
  local kv
  for kv in "${USER_ENV_KV[@]-}"; do
    if [[ -n "$kv" && "$kv" == *=* ]]; then
      EXEC_ENV_ARGS+=(-e "$kv")
    fi
  done

  # Legacy safety:
  if [ -n "${GCLOUD_CREDS_JSON:-}" ] && [ "${#USER_ENV_KV[@]}" -eq 0 ]; then
    EXEC_ENV_ARGS+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcloud.json")
  fi

  [ -n "$task_dir" ] || die "--task is required"; [ -d "$task_dir" ] || die "Task dir not found: $task_dir"

  # Auto-detect .env if not explicitly provided
  if [ -z "${env_file:-}" ]; then
    if [ -f "$task_dir/.env" ]; then
      env_file="$task_dir/.env"
      log_info "Using detected env file: $env_file"
    elif [ -f "$task_dir/env/.env" ]; then
      env_file="$task_dir/env/.env"
      log_info "Using detected env file: $env_file"
    fi
  else
    [ -f "$env_file" ] || die "--env-file not found: $env_file"
    log_info "Using env file: $env_file"
  fi

  local task_name; task_name=$(derive_task_name "$task_dir")
  if [ -z "$image_tag" ]; then image_tag=$(derive_image_tag "$task_name"); fi
  if [ -z "$container_name" ]; then container_name="$task_name"; fi
  # API key only required for modes that use Gemini (not solution mode without analysis)
  if [[ "$mode" != "solution" ]] && [ -z "$api_key" ]; then 
    die "Gemini API key is required for mode '$mode' (use --api-key or GEMINI_API_KEY env)"
  fi

  # Determine default output directory at workspace level: <workspace>/logs/<task_name>/<timestamp>
  local script_dir; script_dir=$(cd "$(dirname "$0")" && pwd -P)
  local workspace_root; workspace_root=$(cd "$script_dir/.." && pwd -P)
  local base_logs_dir="${AUTOBUILD_LOGS_ROOT:-$workspace_root/logs}"
  if [ -z "$output_dir" ]; then output_dir="$base_logs_dir/$task_name/$(date +%Y%m%d_%H%M%S)"; fi
  mkdir -p "$output_dir"

  # Validate task structure and requirements (unless --skip-validation is used)
  if [ "$SKIP_VALIDATION" != "true" ]; then
    local validation_log="$output_dir/task_validation.log"
    validate_task_requirements "$task_dir" "$validation_log" || die "Task validation failed - fix errors above before running"
  else
    log_warn "Skipping task validation (--skip-validation enabled)"
  fi

  # Build -v args from parsed specs
  VOLUME_ARGS=()
  for spec in ${VOLUME_BINDS[@]+"${VOLUME_BINDS[@]}"}; do
    VOLUME_ARGS+=(-v "$spec")
  done

  # (Optional) Log what will be passed to `docker run`
  if [ "${#VOLUME_ARGS[@]}" -gt 0 ]; then
     log_info "Mounting ${#VOLUME_BINDS[@]} volumes:"
    printf '  -v %s\n' ${VOLUME_BINDS[@]+"${VOLUME_BINDS[@]}"}
   fi

  case "$mode" in
    feedback)
      local cname_fb="${container_name}-feedback-$(date +%s)"
      local out_fb="$output_dir/feedback"; mkdir -p "$out_fb"
      feedback "$task_dir" "$image_tag" "$cname_fb" "$workdir" "$api_key" "$out_fb" "${env_file:-}"
      ;;
    verify)
      local cname_v="${container_name}-verify-$(date +%s)"
      local out_v="$output_dir/verify"; mkdir -p "$out_v"
      verify   "$task_dir" "$image_tag" "$cname_v" "$workdir" "$api_key" "$out_v" "${env_file:-}"
      ;;
    both)
      local ts; ts=$(date +%s)
      local out_fb="$output_dir/feedback"; mkdir -p "$out_fb"
      local out_v="$output_dir/verify"; mkdir -p "$out_v"
      local cname_fb="${container_name}-feedback-${ts}"
      local cname_v="${container_name}-verify-${ts}"
      feedback "$task_dir" "$image_tag" "$cname_fb" "$workdir" "$api_key" "$out_fb" "${env_file:-}"
      verify   "$task_dir" "$image_tag" "$cname_v" "$workdir" "$api_key" "$out_v" "${env_file:-}"
      ;;
    audit)
      local base="$(basename "$task_dir")"
      # Use a unique image tag instead of "<base>:latest"
      local img="${image_tag:-$(derive_image_tag "$task_dir")}"
      # Treat --container-name as a base and always suffix for uniqueness
      local base_cname="${container_name:-$base-audit}"
      local cname="$(unique_name "$base_cname")"
      local ts="$(date +%Y%m%d_%H%M%S)"
      # if output_dir was pre-set, append /audit; otherwise create the default with /audit
      local out
      if [ -n "$output_dir" ]; then
        out="$output_dir/audit"
      else
        out="$base_logs_dir/$base/$ts/audit"
      fi
      mkdir -p "$out"
      audit "$task_dir" "$img" "$cname" "$workdir" "$api_key" "$out" "${env_file:-}"
      ;;
    solution)
      local cname_s="${container_name}-solution-$(date +%s)"
      local out_s="$output_dir/solution"; mkdir -p "$out_s"
      solution "$task_dir" "$image_tag" "$cname_s" "$workdir" "$out_s" "${env_file:-}"
      ;;
    solution_audit)
      local base="$(basename "$task_dir")"
      local img="${image_tag:-$(derive_image_tag "$task_dir")}"
      local base_cname="${container_name:-$base-solution-audit}"
      local cname="$(unique_name "$base_cname")"
      local ts="$(date +%Y%m%d_%H%M%S)"
      local out
      if [ -n "$output_dir" ]; then
        out="$output_dir/solution_audit"
      else
        out="$base_logs_dir/$base/$ts/solution_audit"
      fi
      mkdir -p "$out"
      solution_audit "$task_dir" "$img" "$cname" "$workdir" "$api_key" "$out" "${env_file:-}"
      ;;
    solution_verify)
      local cname_sv="${container_name}-solution-verify-$(date +%s)"
      local out_sv="$output_dir/solution_verify"; mkdir -p "$out_sv"
      solution_verify "$task_dir" "$image_tag" "$cname_sv" "$workdir" "$api_key" "$out_sv" "${env_file:-}"
      ;;
    auto_review)
      local out_ar="$output_dir"
      auto_review "$task_dir" "$image_tag" "$container_name" "$workdir" "$api_key" "$out_ar" "${env_file:-}"
      ;;
    *)
      log_error "Unknown mode: $mode"; usage; exit 1;;
  esac
  
  # Note: cleanup_artifacts is called automatically via EXIT trap
}

main "$@"