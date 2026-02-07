# Autobuild Web - Arquitectura y Flujo

## 📊 Diagrama de Flujo Completo

```
┌─────────────────────────────────────────────────────────────┐
│                        USUARIO                               │
│  1. Sube task.zip                                           │
│  2. Selecciona modo (verify, feedback, etc.)                │
│  3. Click "Run Autobuild"                                   │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              GITHUB PAGES (Frontend)                         │
│  • HTML/CSS/JavaScript estático                             │
│  • Tailwind CSS para estilos                                │
│  • Sin servidor backend                                     │
│  • Hosting: GRATIS en GitHub Pages                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ GitHub API
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              GITHUB RELEASES (Storage)                       │
│  1. Crea release temporal con tag único                     │
│  2. Sube task.zip como asset del release                    │
│  3. Release es pre-release (no visible en releases)         │
│  Storage: GRATIS (hasta 2GB por repo)                       │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Trigger Workflow
                 ▼
┌─────────────────────────────────────────────────────────────┐
│           GITHUB ACTIONS (Execution)                         │
│                                                              │
│  JOB: run-autobuild                                         │
│  ┌────────────────────────────────────────────────┐        │
│  │ 1. Checkout repo                                │        │
│  │ 2. Download task from release                   │        │
│  │ 3. Validate task structure                      │        │
│  │ 4. Setup Docker + Node.js                       │        │
│  │ 5. Run: bash autobuild.sh <mode> --task ...    │        │
│  │    ├─ Build Docker image                        │        │
│  │    ├─ Run container                             │        │
│  │    ├─ Install Gemini CLI                        │        │
│  │    ├─ Execute prompts/verification              │        │
│  │    └─ Generate logs                             │        │
│  │ 6. Upload logs as artifacts                     │        │
│  │ 7. Cleanup Docker & delete release              │        │
│  └────────────────────────────────────────────────┘        │
│                                                              │
│  Time: 5-15 minutos por ejecución                          │
│  Cost: GRATIS (2000 min/mes en plan free)                  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Artifacts
                 ▼
┌─────────────────────────────────────────────────────────────┐
│            GITHUB ARTIFACTS (Results)                        │
│  • Logs (.log files)                                        │
│  • Summaries (.txt, .md)                                    │
│  • Docker inspection (JSON)                                 │
│  • Telemetry logs                                           │
│  Retention: 30 días                                         │
│  Storage: GRATIS (500 MB)                                   │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ Download
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                        USUARIO                               │
│  • Descarga logs comprimidos (.zip)                         │
│  • Revisa resultados                                        │
│  • Verifica SUCCESS/FAILURE                                 │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 Flujo Detallado

### Fase 1: Upload (Frontend)
```javascript
// app-v2.js
async function uploadTaskAsRelease(file, taskName) {
  // 1. Create GitHub release
  POST /repos/{owner}/{repo}/releases
  {
    "tag_name": "task-{name}-{timestamp}",
    "prerelease": true
  }
  
  // 2. Upload ZIP as release asset
  POST {upload_url}
  Content-Type: application/zip
  Body: <task.zip binary>
}
```

### Fase 2: Trigger (GitHub API)
```javascript
// app-v2.js
async function triggerWorkflow(releaseTag, mode) {
  POST /repos/{owner}/{repo}/actions/workflows/autobuild-v2.yml/dispatches
  {
    "ref": "main",
    "inputs": {
      "mode": "verify",
      "release_tag": "task-mytask-1234567890",
      "keep_artifacts": "false"
    }
  }
}
```

### Fase 3: Execution (GitHub Actions)
```yaml
# .github/workflows/autobuild-v2.yml
steps:
  - name: Download task
    run: |
      curl -L "$DOWNLOAD_URL" -o task.zip
      unzip task.zip -d ./task
  
  - name: Run autobuild
    env:
      GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
    run: |
      bash ./autobuild/scripts/autobuild.sh verify \
        --task ./task \
        --output-dir ./output
  
  - name: Upload logs
    uses: actions/upload-artifact@v4
    with:
      name: autobuild-logs-${{ github.run_number }}
      path: ./output/
```

### Fase 4: Monitoring (Frontend)
```javascript
// app-v2.js
async function updateStatus() {
  // Poll every 5 seconds
  GET /repos/{owner}/{repo}/actions/runs/{run_id}
  
  if (run.status === 'completed') {
    stopPolling()
    loadResults(run)
  }
}
```

### Fase 5: Results (Artifacts)
```javascript
// app-v2.js
async function loadResults(run) {
  GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts
  
  artifacts.forEach(artifact => {
    // Display download link
    artifact.archive_download_url
  })
}
```

## 🏗️ Estructura de Archivos

```
autobuild-web-free/
│
├── .github/
│   └── workflows/
│       ├── autobuild-v2.yml       # Main execution workflow
│       └── deploy.yml             # Deploy frontend to GitHub Pages
│
├── public/                        # Frontend (served by GitHub Pages)
│   ├── index.html                 # Main UI
│   ├── app-v2.js                  # Frontend logic
│   └── config.template.js         # Configuration template
│
├── autobuild/                     # Autobuild scripts (from original repo)
│   ├── scripts/
│   │   ├── autobuild.sh          # Main bash script
│   │   └── autobuild.ps1         # Windows wrapper
│   └── prompts/
│       ├── prompt1_template.txt
│       ├── prompt2_template.txt
│       └── ...
│
├── scripts/
│   └── process-task.sh            # Helper script for workflow
│
├── README.md                      # Main documentation
├── QUICKSTART.md                  # Quick start guide
├── DEPLOY.md                      # Deployment instructions
└── package.json                   # Project metadata
```

## 💾 Data Flow

### Input (Task)
```
task.zip
├── env/
│   └── Dockerfile         # Image definition
├── verify/
│   ├── verify.sh          # Verification script
│   └── command            # Verification command
└── prompt                 # Task prompt (no extension)
```

### Output (Logs)
```
autobuild-logs-{run_number}.zip
└── output/
    ├── feedback/          # (if mode=feedback)
    │   ├── docker_build.log
    │   ├── gemini_prompt1.log
    │   ├── gemini_prompt2.log
    │   ├── verification.log
    │   └── telemetry.log
    │
    ├── verify/            # (if mode=verify)
    │   ├── docker_build.log
    │   ├── gemini_npx.log
    │   ├── verification.log
    │   └── docker_inspect.json
    │
    └── EXECUTION_SUMMARY.md
```

## 🔒 Security Model

### Secrets Management
```
GitHub Secrets (Repository level)
└── GEMINI_API_KEY
    ├── Never exposed to frontend
    ├── Only accessible in workflow via ${{ secrets.GEMINI_API_KEY }}
    └── Encrypted at rest

User PAT (Personal Access Token)
└── Stored in browser localStorage
    ├── Used for GitHub API calls from frontend
    ├── Required scopes: repo, workflow
    └── User can revoke anytime
```

### Access Control
```
Repository (Public)
├── Code: ✅ Public (read-only)
├── GitHub Pages: ✅ Public (anyone can access UI)
├── GitHub Actions: 🔒 Protected (only owner can trigger)
└── Secrets: 🔐 Private (never exposed)

Workflows
├── Triggered by: Frontend (via PAT)
├── Executed by: GitHub Actions runner
└── Access to: Secrets (GEMINI_API_KEY)
```

## 💰 Cost Breakdown

### Free Tier Limits
```
GitHub Actions (Public Repo)
├── Minutes: 2000/month (Linux)
├── Storage: 500 MB artifacts
└── API requests: 5000/hour

Typical Autobuild Run
├── Duration: 5-15 minutes
├── Artifact size: 10-50 MB
└── API calls: ~20 per run

Monthly Capacity (Free)
├── Runs: 130-400 (depending on duration)
├── Storage: ~10-50 runs concurrent
└── API: Unlimited for practical use
```

### If Limits Exceeded
```
Option 1: Self-hosted runners (FREE)
├── Use your own machine
└── No minute limits

Option 2: Paid GitHub Actions
├── $0.008/minute (Linux)
└── $0.25/GB storage

Option 3: Alternative CI/CD (FREE)
├── GitLab CI: 400 min/month
├── CircleCI: 6000 min/month
└── Travis CI: Limited free
```

## 🎯 Optimization Tips

### Reduce Execution Time
```bash
# Use Docker cache (faster builds)
--cache

# Skip validation (when debugging)
--skip-validation

# Use smaller base image
FROM node:20-slim
```

### Reduce Storage
```yaml
# Shorter artifact retention
retention-days: 7  # instead of 30

# Compress logs before upload
tar -czf logs.tar.gz ./output/
```

### Reduce API Calls
```javascript
// Poll less frequently when long-running
const pollInterval = status === 'in_progress' ? 10000 : 5000;
```

## 🔧 Troubleshooting

### Common Issues

1. **Workflow doesn't trigger**
   - Check PAT has `workflow` scope
   - Verify repository is public
   - Check workflow file syntax

2. **Task download fails**
   - Ensure ZIP uploaded to release
   - Check release tag matches workflow input
   - Verify ZIP size < 100 MB

3. **Docker build fails**
   - Check Dockerfile syntax
   - Ensure Debian-based image
   - Verify Node.js 20+ installed

4. **Verification fails**
   - Check verify.sh outputs SUCCESS/FAILURE
   - Ensure command file references verify/
   - Review verification logs

## 📚 Referencias

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [GitHub API Reference](https://docs.github.com/en/rest)
- [Docker Documentation](https://docs.docker.com/)
- [Autobuild README](../autobuild/README.md)
