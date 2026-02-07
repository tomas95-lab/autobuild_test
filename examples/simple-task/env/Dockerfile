FROM node:20-bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Verify Node.js version
RUN node --version && npm --version

# Note: Gemini CLI will be installed by autobuild.sh
# Do not install it here
