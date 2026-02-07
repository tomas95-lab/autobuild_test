#!/bin/bash
# Setup script for Autobuild Web deployment

set -e

echo "================================================"
echo "Autobuild Web - Setup Script"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: Must run from autobuild-web-free/ directory${NC}"
    exit 1
fi

# 1. Copy autobuild scripts
echo "📦 Step 1/5: Copying autobuild scripts..."
echo ""

# Prompt for autobuild path
read -p "Enter path to autobuild directory (e.g., ../autobuild): " AUTOBUILD_PATH

if [ ! -d "$AUTOBUILD_PATH" ]; then
    echo -e "${RED}Error: Autobuild directory not found: $AUTOBUILD_PATH${NC}"
    exit 1
fi

if [ ! -f "$AUTOBUILD_PATH/scripts/autobuild.sh" ]; then
    echo -e "${RED}Error: autobuild.sh not found in $AUTOBUILD_PATH/scripts/${NC}"
    exit 1
fi

# Create autobuild directory
mkdir -p autobuild

# Copy scripts
echo "  Copying scripts..."
cp -r "$AUTOBUILD_PATH/scripts" autobuild/
echo -e "  ${GREEN}✓${NC} Scripts copied"

# Copy prompts
echo "  Copying prompts..."
cp -r "$AUTOBUILD_PATH/prompts" autobuild/
echo -e "  ${GREEN}✓${NC} Prompts copied"

echo ""
echo -e "${GREEN}✓ Autobuild scripts copied successfully${NC}"
echo ""

# 2. Configure GitHub repository
echo "📝 Step 2/5: Configure GitHub repository..."
echo ""

read -p "Enter your GitHub username: " GITHUB_USER
read -p "Enter repository name (default: autobuild-web): " GITHUB_REPO
GITHUB_REPO=${GITHUB_REPO:-autobuild-web}

# Update config in app-v2.js
echo "  Updating app-v2.js configuration..."
sed -i.bak "s/YOUR-USERNAME/$GITHUB_USER/g" public/app-v2.js
sed -i.bak "s/repo: 'autobuild-web'/repo: '$GITHUB_REPO'/g" public/app-v2.js
rm public/app-v2.js.bak 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Configuration updated"

echo ""
echo -e "${GREEN}✓ Repository configured${NC}"
echo ""

# 3. Initialize git (if not already)
echo "🔧 Step 3/5: Initialize Git repository..."
echo ""

if [ ! -d ".git" ]; then
    git init
    echo -e "  ${GREEN}✓${NC} Git initialized"
else
    echo -e "  ${YELLOW}⚠${NC} Git already initialized"
fi

# Add remote if not exists
if ! git remote | grep -q origin; then
    git remote add origin "https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
    echo -e "  ${GREEN}✓${NC} Remote 'origin' added"
else
    echo -e "  ${YELLOW}⚠${NC} Remote 'origin' already exists"
fi

echo ""
echo -e "${GREEN}✓ Git configured${NC}"
echo ""

# 4. Create initial commit
echo "📤 Step 4/5: Create initial commit..."
echo ""

git add .
git commit -m "Initial commit: Autobuild Web setup" || echo "Already committed"
echo -e "${GREEN}✓ Initial commit created${NC}"
echo ""

# 5. Instructions for final steps
echo "================================================"
echo "✅ Setup Complete!"
echo "================================================"
echo ""
echo "Next steps to deploy:"
echo ""
echo "1. Create a PUBLIC repository on GitHub:"
echo "   ${GREEN}https://github.com/new${NC}"
echo "   Name: $GITHUB_REPO"
echo ""
echo "2. Add GEMINI_API_KEY to GitHub Secrets:"
echo "   ${GREEN}https://github.com/$GITHUB_USER/$GITHUB_REPO/settings/secrets/actions${NC}"
echo "   Secret name: GEMINI_API_KEY"
echo "   Value: Your Gemini API key"
echo ""
echo "3. Enable GitHub Pages:"
echo "   ${GREEN}https://github.com/$GITHUB_USER/$GITHUB_REPO/settings/pages${NC}"
echo "   Source: GitHub Actions"
echo ""
echo "4. Push to GitHub:"
echo "   ${YELLOW}git push -u origin main${NC}"
echo ""
echo "5. Wait 2-3 minutes, then access your app:"
echo "   ${GREEN}https://$GITHUB_USER.github.io/$GITHUB_REPO/${NC}"
echo ""
echo "================================================"
echo ""
echo "For detailed instructions, see:"
echo "  - README.md"
echo "  - DEPLOY.md"
echo "  - QUICKSTART.md"
echo ""
