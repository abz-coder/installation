#!/bin/bash

set -e

# Install base dependencies
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg

# Install Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/yarn.gpg >/dev/null
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Install Node.js via custom script
curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

# Install required system packages
sudo apt-get update
sudo apt-get install -y build-essential software-properties-common

# Install Python 3.12 (fallback to 3.10-dev if needed)
if sudo add-apt-repository -y ppa:deadsnakes/ppa && \
   sudo apt-get update && \
   sudo apt-get install -y python3.12 python3.12-dev; then
    echo "✅ Python 3.12 and python3.12-dev installed"
else
    echo "⚠️  Python 3.12 not available, installing python3.10-dev instead..."
    sudo apt-get install -y python3.10-dev
fi

export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc 2>/dev/null || true

# Install global npm packages (with error handling)
echo "📦 Installing global npm packages..."
sudo npm install -g n || echo "⚠️  Failed to install n, continuing..."
sudo n lts || echo "⚠️  Failed to install LTS Node.js, continuing..."
n 20.18.0 || echo "⚠️  Failed to switch to Node.js 20.18.0, continuing..."

# Skip yarn installation if it already exists
if ! command -v yarn &> /dev/null; then
    echo "📦 Installing yarn via npm..."
    sudo npm install -g yarn || echo "⚠️  Failed to install yarn via npm, continuing..."
else
    echo "✅ Yarn already installed, skipping npm installation"
fi

# Clean up old screen sessions and port 3000
echo "🧹 Cleaning up old processes..."
screen -ls | grep "\.gensyn" | cut -d. -f1 | awk '{print $1}' | xargs -r kill 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# ========== Arguments ==========
RECLONE="${1:-n}"
USE_VLLM_FLAG="${2:-y}"
# ===============================

# Get current directory where script is run from
BASE_DIR="$(pwd)"
echo "📁 Base directory: $BASE_DIR"

# Clone or update RL Swarm repo
if [ "$RECLONE" == "y" ]; then
    echo "📥 Removing old rl-swarm-optimized and cloning fresh copy..."
    rm -rf rl-swarm
    git clone https://github.com/abz-coder/rl-swarm-optimized.git rl-swarm
    cd rl-swarm
else
    if [ ! -d "rl-swarm" ]; then
        echo "📥 rl-swarm-optimized directory not found. Cloning..."
        git clone https://github.com/abz-coder/rl-swarm-optimized.git rl-swarm
    fi
    cd rl-swarm
    echo "🔄 Pulling latest changes from git..."
    git pull
fi

echo "✅ Repository setup complete"

# ========== Archive Extraction ==========
ARCHIVE_FOUND=$(find "$BASE_DIR" -maxdepth 1 -type f -name '[0-9]*.tar' | head -n 1)
if [ -n "$ARCHIVE_FOUND" ]; then
    echo "📦 Found archive $ARCHIVE_FOUND. Extracting..."
    tar -xvf "$ARCHIVE_FOUND" -C "$BASE_DIR"
    echo "✅ Archive extracted successfully."
else
    echo "ℹ️  No archive found in $BASE_DIR."
fi

# ========== Run rl-swarm in screen ==========
echo "🚀 Starting rl-swarm in screen session..."
screen -L -Logfile "$BASE_DIR/gensyn.log" -dmS gensyn bash -c "
    cd '$BASE_DIR/rl-swarm'
    echo 'Setting up Python virtual environment...'
    if [ ! -d '.venv' ]; then 
        python3 -m venv .venv
        echo 'Virtual environment created'
    fi
    source .venv/bin/activate
    echo 'Installing Python dependencies...'
    pip install --upgrade pip
    pip install accelerate==1.7
    echo 'Starting rl-swarm...'
    trap '' SIGINT
    USE_VLLM='$USE_VLLM_FLAG' ./run_rl_swarm.sh
    exec bash -i
" &
disown

echo "✅ Screen session 'gensyn' created successfully!"
echo "📋 To check the session: screen -ls"
echo "📋 To attach to the session: screen -r gensyn"
echo "📋 To view logs: tail -f $BASE_DIR/gensyn.log" 
