#!/bin/bash

set -e

# ========== Arguments ==========
RECLONE="${1:-n}"
REMOVE_TEMP_DATA="${2:-n}"
SKIP_SYSTEM_INSTALL="${3:-n}"  # New parameter: default to 'n' (install system deps), 'y' to skip
USE_TIMEOUT="${4:-y}"  # New parameter: default to 'y' (use random timeout), 'n' to skip timeout
# ===============================

# Check if we should skip system installation
if [[ "$SKIP_SYSTEM_INSTALL" =~ ^(y|Y|yes|YES)$ ]]; then
    echo "📋 SKIP_SYSTEM_INSTALL=$SKIP_SYSTEM_INSTALL detected. Skipping system dependency installation..."
else
    echo "📋 Installing system dependencies.."
    
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
fi

# Clean up old screen sessions and port 3000
echo "🧹 Cleaning up old processes..."
screen -ls | grep "\.gensyn" | cut -d. -f1 | awk '{print $1}' | xargs -r kill 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# Get current directory where script is run from
BASE_DIR="$(pwd)"
echo "📁 Base directory: $BASE_DIR"

# Clone or update RL Swarm repo
if [ "$RECLONE" == "y" ]; then
    echo "📥 Removing old rl-swarm and cloning fresh copy..."
    rm -rf rl-swarm
    git clone https://github.com/abz-coder/rl-swarm-cpu-autorestart.git rl-swarm
    cd rl-swarm
else
    if [ ! -d "rl-swarm" ]; then
        echo "📥 rl-swarm directory not found. Cloning..."
        git clone https://github.com/abz-coder/rl-swarm-cpu-autorestart.git rl-swarm
    fi
    cd rl-swarm
    echo "🔄 Pulling latest changes from git..."
    git pull
fi

echo "✅ Repository setup complete"

# ========== Clean up existing data ==========
echo "🧹 Cleaning up existing data files..."
[ -d "$BASE_DIR/rl-swarm/modal-login/temp-data" ] && rm -rf "$BASE_DIR/rl-swarm/modal-login/temp-data"/*
[ -f "$BASE_DIR/rl-swarm/swarm.pem" ] && rm -f "$BASE_DIR/rl-swarm/swarm.pem"
[ -d "$BASE_DIR/rl-swarm/logs" ] && rm -rf "$BASE_DIR/rl-swarm/logs"
echo "✅ Data cleanup complete"

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

# ========== Random timeout before starting ==========
if [[ "$USE_TIMEOUT" =~ ^(y|Y|yes|YES)$ ]]; then
    # Generate random timeout between 10 minutes (600s) and 3 hours (10800s)
    MIN_TIMEOUT=600     # 10 minutes in seconds
    MAX_TIMEOUT=10800   # 3 hours in seconds
    TIMEOUT_RANGE=$((MAX_TIMEOUT - MIN_TIMEOUT + 1))
    RANDOM_TIMEOUT=$((MIN_TIMEOUT + (RANDOM % TIMEOUT_RANGE)))
    
    # Convert seconds to human readable format
    HOURS=$((RANDOM_TIMEOUT / 3600))
    MINUTES=$(((RANDOM_TIMEOUT % 3600) / 60))
    SECONDS=$((RANDOM_TIMEOUT % 60))
    
    echo "⏰ USE_TIMEOUT=$USE_TIMEOUT detected. Random timeout generated: ${RANDOM_TIMEOUT}s"
    echo "⏰ Waiting for ${HOURS}h ${MINUTES}m ${SECONDS}s before starting rl-swarm..."
    echo "💡 This helps distribute network load across different start times"
    
    sleep $RANDOM_TIMEOUT
    echo "✅ Timeout completed. Proceeding with rl-swarm startup..."
else
    echo "⏰ USE_TIMEOUT=$USE_TIMEOUT detected. Skipping random timeout..."
fi

# ========== Run auto_restart in screen ==========
echo "🚀 Starting auto_restart in screen session..."
echo "📋 SKIP_SYSTEM_INSTALL parameter: $SKIP_SYSTEM_INSTALL"
echo "📋 USE_TIMEOUT parameter: $USE_TIMEOUT"

chmod +x auto_restart.sh

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
    ./run_rl_swarm.sh
    exec bash -i
" &
disown

echo "✅ Screen session 'gensyn' created successfully!"
echo "📋 To check the session: screen -ls"
echo "📋 To attach to the session: screen -r gensyn"
echo "📋 To view logs: tail -f $BASE_DIR/gensyn.log"
