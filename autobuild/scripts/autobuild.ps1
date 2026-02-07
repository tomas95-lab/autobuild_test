# autobuild.ps1
param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet('feedback','verify','both','audit','solution','solution_audit','solution_verify','auto_review')]
  [string]$Mode,

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Rest
)

function Fail($msg){ Write-Error $msg; exit 1 }
function Info($msg){ Write-Host "[INFO]  $msg" }
function Warn($msg){ Write-Warning $msg }

function Convert-MountSpecToWSL([string]$spec) {
  # Expect: host:container[:mode]
  $firstColon = $spec.IndexOf(':')
  if ($firstColon -lt 0) { return $spec }

  $host = $spec.Substring(0, $firstColon)
  $rest = $spec.Substring($firstColon + 1)

  # Convert drive-style paths like C:\... -> /mnt/c/...
  if ($host -match '^[A-Za-z]:\\') {
    # Escape backslashes for WSL/bash
    $hostEscaped = $host -replace '\\', '\\'
    $hostWsl = wsl.exe wslpath -a "$hostEscaped" 2>$null
    if (-not $hostWsl) { throw "Cannot convert host path '$host' to WSL path." }
    return "${hostWsl}:$rest"
  }

  # If already WSL-style (/mnt/c/...), or UNC, leave as-is
  return $spec
}

# --- prerequisites ---
$wsl = (Get-Command wsl.exe -ErrorAction SilentlyContinue)
if (-not $wsl) { Fail "WSL is required. Install WSL (wsl.exe) and a Linux distro (Ubuntu recommended)." }

# script locations
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bashScriptWin = Join-Path $scriptDir 'autobuild.sh'
if (-not (Test-Path $bashScriptWin)) { Fail "Could not find autobuild.sh next to autobuild.ps1 at: $bashScriptWin" }

# Convert Windows path to WSL even if it doesn't exist (FIXED)
function To-WSLPath([string]$p){
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  # Escape backslashes for WSL/bash (\ -> \\)
  $escaped = $p -replace '\\', '\\'
  # If it's a drive-letter path, try wslpath regardless of existence
  if ($p -match '^[A-Za-z]:\\') {
    $converted = & wsl.exe wslpath -a -u "$escaped" 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($converted)) { return $converted.Trim() }
  }
  # Else fall back to existing behavior
  if (Test-Path $p) {
    $converted = & wsl.exe wslpath -a -u "$escaped" 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($converted)) { return $converted.Trim() }
  }
  return $p
}

# Expand equals-style args and convert path values (FIXED: added --gcloud-creds, --mount, -v)
function Maybe-Convert-EqualsArg([string]$a){
  $pathFlags = @('--task','--output-dir','--workdir','--env-file','--gcloud-creds')
  foreach ($pf in $pathFlags) {
    if ($a -like "$pf=*") {
      $kv = $a.Split('=',2)
      $key = $kv[0]; $val = $kv[1]
      $conv = To-WSLPath $val
      return @("$key=$conv")
    }
  }
  # equals-style mount forms: --mount=host:ctr[:mode] and -v=host:ctr[:mode]
  if ($a -like '--mount=*') {
    $spec = $a.Substring(8)
    return @("--mount=$(Convert-MountSpecToWSL $spec)")
  }
  if ($a -like '-v=*') {
    $spec = $a.Substring(3)
    return @("-v=$(Convert-MountSpecToWSL $spec)")
  }
  # Pass --verify-command=value as-is (no path conversion needed)
  if ($a -like '--verify-command=*') {
    return @($a)
  }
  return @($a)
}

# Build arg list for bash
$argList = @($Mode)
for ($i=0; $i -lt $Rest.Count; $i++){
  $a = $Rest[$i]

  # First normalize equals-form flags
  $expanded = (Maybe-Convert-EqualsArg $a)
  if ($expanded.Count -gt 1) {
    $argList += $expanded
    continue
  }

  # Non-equals flags that take a value next
  $argList += $a
  if ($a -in @('--task','--output-dir','--workdir','--env-file','--gcloud-creds','--image-tag','--container-name','--api-key','--mount','-v','--verify-command','--gemini-cli-version','--docker-arg')){
    if ($i + 1 -lt $Rest.Count){
      $val = $Rest[$i+1]
      switch ($a) {
        '--task'          { $argList += (To-WSLPath $val); $i++ ; continue }
        '--output-dir'    { $argList += (To-WSLPath $val); $i++ ; continue }
        '--workdir'       { $argList += (To-WSLPath $val); $i++ ; continue }
        '--env-file'      { $argList += (To-WSLPath $val); $i++ ; continue }
        '--gcloud-creds'  { $argList += (To-WSLPath $val); $i++ ; continue }
        '--image-tag'     { $argList += $val; $i++ ; continue }
        '--container-name'{ $argList += $val; $i++ ; continue }
        '--api-key'       { $argList += $val; $i++ ; continue }
        '--verify-command'{ $argList += $val; $i++ ; continue }  # Pass command as-is
        '--gemini-cli-version' { $argList += $val; $i++ ; continue }
        '--docker-arg'    { $argList += $val; $i++ ; continue }  # Pass docker arg as-is
        '--mount'         { $argList += (Convert-MountSpecToWSL $val); $i++ ; continue }
        '-v'              { $argList += (Convert-MountSpecToWSL $val); $i++ ; continue }
      }
    }
  }
}

# Single robust API key presence check (FIXED: supports equals form)
# Solution mode doesn't require API key
$hasApiKey = $Rest | Where-Object { $_ -eq '--api-key' -or $_ -like '--api-key=*' } | ForEach-Object { $true } | Select-Object -First 1
$envExport = @()
if (-not $hasApiKey -and $Mode -ne 'solution') {
  if ($env:GEMINI_API_KEY) {
    $envExport += "GEMINI_API_KEY=$($env:GEMINI_API_KEY)"
  } else {
    Fail "Gemini API key is required for mode '$Mode' (use --api-key or set GEMINI_API_KEY env)."
  }
}

# Build command to run in WSL
$scriptDirWSL = To-WSLPath $scriptDir
$bashScriptWSL = "$scriptDirWSL/autobuild.sh"

function Quote-Bash([string]$s){
  if ($null -eq $s) { return "''" }
  # Escape single quotes for bash: replace ' with '"'"'
  $escaped = $s -replace "'", "'`"'`"'"
  return "'" + $escaped + "'"
}

$argLine = ($argList | ForEach-Object { Quote-Bash $_ }) -join ' '
$exportLine = ($envExport | ForEach-Object { "export $_" }) -join '; '
if ($exportLine) { $exportLine += '; ' }

$cmd = "$exportLine cd $(Quote-Bash $scriptDirWSL); bash $(Quote-Bash $bashScriptWSL) $argLine"

Info "Invoking autobuild.sh inside WSL..."
wsl.exe bash -lc "$cmd"
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { Fail "autobuild.sh exited with code $exitCode" } else { Info "Done." }
