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

# Install global npm packages
sudo npm install -g yarn
sudo npm install -g n
sudo n lts
n 20.18.0

# Clean up old screen sessions and port 3000
screen -ls | grep "\.gensyn" | cut -d. -f1 | awk '{print $1}' | xargs -r kill
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# ========== Arguments ==========
RECLONE="${1:-n}"
USE_CPU_FLAG="${2:-}"
REMOVE_TEMP_DATA="${3:-n}"
# ===============================

# Get current directory where script is run from
BASE_DIR="$(pwd)"

# Clone or update RL Swarm repo
if [ "$RECLONE" == "y" ]; then
    echo "📥 Removing old rl-swarm and cloning fresh copy..."
    rm -rf rl-swarm
    git clone https://github.com/abz-coder/rl-swarm.git
    cd rl-swarm
else
    if [ ! -d "rl-swarm" ]; then
        echo "📥 rl-swarm directory not found. Cloning..."
        git clone https://github.com/abz-coder/rl-swarm.git
    fi
    cd rl-swarm
    echo "🔄 Pulling latest changes from git..."
    git pull
fi

# ========== Archive Extraction and temp-data cleanup ==========
ARCHIVE_FOUND=$(find "$BASE_DIR" -maxdepth 1 -type f -name '[0-9]*.tar' | head -n 1)
if [ -n "$ARCHIVE_FOUND" ]; then
    echo "📦 Found archive $ARCHIVE_FOUND. Extracting..."
    tar -xvf "$ARCHIVE_FOUND" -C "$BASE_DIR"
    echo "✅ Archive extracted successfully."

    if [ "$REMOVE_TEMP_DATA" == "y" ]; then
        TEMP_DATA_DIR="$BASE_DIR/rl-swarm/modal-login/temp-data"
        if [ -d "$TEMP_DATA_DIR" ]; then
            echo "🗑  Cleaning up files in $TEMP_DATA_DIR..."
            rm -rf "$TEMP_DATA_DIR"/*
            echo "✅ temp-data cleaned successfully."
        else
            echo "ℹ️  temp-data directory not found."
        fi
    fi
else
    echo "ℹ️  No archive found in $BASE_DIR."
fi

# ========== Run rl-swarm in screen ==========
screen -L -Logfile "$BASE_DIR/gensyn.log" -dmS gensyn bash -c "
    cd '$BASE_DIR/rl-swarm'
    if [ ! -d '.venv' ]; then python3 -m venv .venv; fi
    source .venv/bin/activate
    pip install --upgrade pip
    pip install accelerate==1.7
    trap '' SIGINT
    USE_CPU='$USE_CPU_FLAG' ./run_rl_swarm.sh
    exec bash -i
" &
disown
