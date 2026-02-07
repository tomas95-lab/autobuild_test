# Setup script for Autobuild Web deployment (Windows)
# Run in PowerShell

$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Autobuild Web - Setup Script (Windows)" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're in the right directory
if (-not (Test-Path "package.json")) {
    Write-Host "Error: Must run from autobuild-web-free directory" -ForegroundColor Red
    exit 1
}

# 1. Copy autobuild scripts
Write-Host "📦 Step 1/5: Copying autobuild scripts..." -ForegroundColor Yellow
Write-Host ""

$autobuildPath = Read-Host "Enter path to autobuild directory (e.g., ..\autobuild)"

if (-not (Test-Path $autobuildPath)) {
    Write-Host "Error: Autobuild directory not found: $autobuildPath" -ForegroundColor Red
    exit 1
}

$scriptPath = Join-Path $autobuildPath "scripts\autobuild.sh"
if (-not (Test-Path $scriptPath)) {
    Write-Host "Error: autobuild.sh not found in $autobuildPath\scripts\" -ForegroundColor Red
    exit 1
}

# Create autobuild directory
New-Item -ItemType Directory -Path "autobuild" -Force | Out-Null

# Copy scripts
Write-Host "  Copying scripts..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $autobuildPath "scripts") -Destination "autobuild\" -Recurse -Force
Write-Host "  ✓ Scripts copied" -ForegroundColor Green

# Copy prompts
Write-Host "  Copying prompts..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $autobuildPath "prompts") -Destination "autobuild\" -Recurse -Force
Write-Host "  ✓ Prompts copied" -ForegroundColor Green

Write-Host ""
Write-Host "✓ Autobuild scripts copied successfully" -ForegroundColor Green
Write-Host ""

# 2. Configure GitHub repository
Write-Host "📝 Step 2/5: Configure GitHub repository..." -ForegroundColor Yellow
Write-Host ""

$githubUser = Read-Host "Enter your GitHub username"
$githubRepoInput = Read-Host "Enter repository name (default: autobuild-web)"
$githubRepo = if ($githubRepoInput) { $githubRepoInput } else { "autobuild-web" }

# Update config in app-v2.js
Write-Host "  Updating app-v2.js configuration..." -ForegroundColor Gray
$appJsPath = "public\app-v2.js"
$appJsContent = Get-Content $appJsPath -Raw
$appJsContent = $appJsContent -replace "YOUR-USERNAME", $githubUser
$appJsContent = $appJsContent -replace "repo: 'autobuild-web'", "repo: '$githubRepo'"
Set-Content -Path $appJsPath -Value $appJsContent
Write-Host "  ✓ Configuration updated" -ForegroundColor Green

Write-Host ""
Write-Host "✓ Repository configured" -ForegroundColor Green
Write-Host ""

# 3. Initialize git (if not already)
Write-Host "🔧 Step 3/5: Initialize Git repository..." -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path ".git")) {
    git init
    Write-Host "  ✓ Git initialized" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Git already initialized" -ForegroundColor Yellow
}

# Add remote if not exists
$hasOrigin = git remote | Select-String -Pattern "origin" -Quiet
if (-not $hasOrigin) {
    git remote add origin "https://github.com/$githubUser/$githubRepo.git"
    Write-Host "  ✓ Remote 'origin' added" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Remote 'origin' already exists" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✓ Git configured" -ForegroundColor Green
Write-Host ""

# 4. Create initial commit
Write-Host "📤 Step 4/5: Create initial commit..." -ForegroundColor Yellow
Write-Host ""

git add .
git commit -m "Initial commit: Autobuild Web setup" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠ Already committed or nothing to commit" -ForegroundColor Yellow
} else {
    Write-Host "  ✓ Initial commit created" -ForegroundColor Green
}

Write-Host ""
Write-Host "✓ Commit ready" -ForegroundColor Green
Write-Host ""

# 5. Instructions for final steps
Write-Host "================================================" -ForegroundColor Green
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps to deploy:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Create a PUBLIC repository on GitHub:" -ForegroundColor White
Write-Host "   https://github.com/new" -ForegroundColor Green
Write-Host "   Name: $githubRepo" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Add GEMINI_API_KEY to GitHub Secrets:" -ForegroundColor White
Write-Host "   https://github.com/$githubUser/$githubRepo/settings/secrets/actions" -ForegroundColor Green
Write-Host "   Secret name: GEMINI_API_KEY" -ForegroundColor Gray
Write-Host "   Value: Your Gemini API key" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Enable GitHub Pages:" -ForegroundColor White
Write-Host "   https://github.com/$githubUser/$githubRepo/settings/pages" -ForegroundColor Green
Write-Host "   Source: GitHub Actions" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Push to GitHub:" -ForegroundColor White
Write-Host "   git push -u origin main" -ForegroundColor Yellow
Write-Host ""
Write-Host "5. Wait 2-3 minutes, then access your app:" -ForegroundColor White
Write-Host "   https://$githubUser.github.io/$githubRepo/" -ForegroundColor Green
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "For detailed instructions, see:" -ForegroundColor White
Write-Host "  - README.md" -ForegroundColor Gray
Write-Host "  - DEPLOY.md" -ForegroundColor Gray
Write-Host "  - QUICKSTART.md" -ForegroundColor Gray
Write-Host ""
