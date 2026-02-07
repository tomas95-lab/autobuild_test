# Deployment Guide - Autobuild Web Free

## 🚀 Quick Deploy (5 minutes)

### Step 1: Fork/Create Repository

1. Create a **PUBLIC** repository on GitHub named `autobuild-web`
2. Clone this code to your repository

```bash
git clone https://github.com/YOUR-USERNAME/autobuild-web.git
cd autobuild-web
```

### Step 2: Copy Autobuild Scripts

Copy the original autobuild scripts and prompts into your repo:

```bash
# From your autobuild installation
cp -r /path/to/autobuild/scripts ./autobuild/scripts
cp -r /path/to/autobuild/prompts ./autobuild/prompts
```

Your structure should look like:
```
autobuild-web/
├── .github/workflows/
├── public/
├── autobuild/
│   ├── scripts/
│   │   ├── autobuild.sh
│   │   └── autobuild.ps1
│   └── prompts/
│       ├── prompt1_template.txt
│       ├── prompt2_template.txt
│       └── ...
```

### Step 3: Configure GitHub Secrets

1. Go to your repo → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add:
   - Name: `GEMINI_API_KEY`
   - Value: Your Gemini API key

### Step 4: Enable GitHub Pages

1. Go to **Settings** → **Pages**
2. Source: **GitHub Actions**
3. Save

### Step 5: Deploy

```bash
git add .
git commit -m "Initial deployment"
git push origin main
```

Wait 1-2 minutes, then visit: `https://YOUR-USERNAME.github.io/autobuild-web/`

## ⚙️ Configuration

### Update Config in `public/app.js`

Edit lines 2-5:

```javascript
const CONFIG = {
  owner: 'YOUR-USERNAME',  // ← Your GitHub username
  repo: 'autobuild-web',   // ← Your repo name
  token: null              // ← Users will be prompted
};
```

### Get Personal Access Token (for users)

Users need a GitHub PAT to trigger workflows:

1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
4. Generate and copy the token
5. Paste it when the web app prompts

## 🎯 Usage Flow

### For End Users:

1. **Visit the web app**
2. **Enter GitHub PAT** (one-time, stored in browser)
3. **Upload task ZIP** (containing env/, verify/, prompt)
4. **Select mode** (verify, feedback, audit, etc.)
5. **Click "Run Autobuild"**
6. **Monitor progress** in real-time
7. **Download logs** when complete

## 📊 GitHub Actions Workflow

The workflow (`autobuild.yml`) does:

1. ✅ Downloads task from GitHub Release
2. ✅ Validates task structure
3. ✅ Runs Docker build
4. ✅ Executes autobuild.sh
5. ✅ Uploads logs as artifacts
6. ✅ Cleans up Docker resources

## 💰 Free Tier Limits

### GitHub Actions
- **2000 minutes/month** (Linux runners)
- **500 MB storage** for artifacts
- **Unlimited** for public repos

### Typical Usage
- 1 autobuild run ≈ 5-15 minutes
- With free tier: **~130-400 runs/month**
- Logs: ~10-50 MB per run

### If You Need More
Consider these **still free** alternatives:

1. **Self-hosted runners** (use your own machine)
2. **GitLab CI/CD** (400 minutes/month free)
3. **CircleCI** (6000 build minutes/month free)

## 🔒 Security Best Practices

### For Repository Owners

1. ✅ Keep GEMINI_API_KEY in GitHub Secrets (never commit)
2. ✅ Use public repo for GitHub Pages (free)
3. ✅ Enable branch protection on main
4. ✅ Review workflow runs regularly

### For Users

1. ✅ Use PAT with minimal scopes (repo + workflow only)
2. ✅ Revoke PAT when not needed
3. ✅ Don't share PAT publicly
4. ✅ Store PAT securely (browser localStorage is convenient but not secure for sensitive use)

## 🐛 Troubleshooting

### Workflow doesn't trigger
- ✅ Check PAT has `workflow` scope
- ✅ Verify repo is public or PAT has `repo` scope
- ✅ Check workflow file syntax (use GitHub Actions validator)

### Task upload fails
- ✅ Ensure ZIP contains env/, verify/, prompt
- ✅ Check file size (< 100 MB recommended)
- ✅ Verify ZIP is not corrupted

### Docker build fails
- ✅ Check Dockerfile is valid Debian-based
- ✅ Ensure Node.js 20+ is installed
- ✅ Review build logs in workflow

### API rate limiting
- ✅ GitHub API: 5000 req/hour (authenticated)
- ✅ If exceeded, wait 1 hour or upgrade to Pro

## 📈 Monitoring

### View Workflow Runs
```
https://github.com/YOUR-USERNAME/autobuild-web/actions
```

### Check Artifact Storage
```
https://github.com/YOUR-USERNAME/autobuild-web/settings
```
→ Look for "Actions" section

### Track Minutes Used
```
https://github.com/settings/billing
```
→ Actions minutes usage

## 🔄 Updates

To update autobuild scripts:

```bash
# Pull latest from autobuild repo
cd /path/to/autobuild
git pull

# Copy to web repo
cd /path/to/autobuild-web
cp -r /path/to/autobuild/scripts ./autobuild/scripts
cp -r /path/to/autobuild/prompts ./autobuild/prompts

# Commit and push
git add autobuild/
git commit -m "Update autobuild scripts"
git push
```

## 🎓 Advanced: Custom Domain

Want to use your own domain instead of `.github.io`?

1. Buy domain (e.g., Namecheap, $10/year)
2. Add `CNAME` file to `public/`:
   ```
   autobuild.yourdomain.com
   ```
3. Configure DNS:
   - Type: `CNAME`
   - Name: `autobuild`
   - Value: `YOUR-USERNAME.github.io`
4. In GitHub: Settings → Pages → Custom domain

Still **100% free** (except domain cost)!

## 📚 Resources

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [GitHub Pages Docs](https://docs.github.com/en/pages)
- [Autobuild Docs](../autobuild/README.md)
- [Docker Hub](https://hub.docker.com/)

## 🆘 Get Help

- [Open an Issue](https://github.com/YOUR-USERNAME/autobuild-web/issues)
- [Discussions](https://github.com/YOUR-USERNAME/autobuild-web/discussions)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/github-actions)

---

**Happy Building! 🚀**
