#!/bin/bash

set -e

# Установка зависимостей
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg

# Установка Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/yarn.gpg >/dev/null
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Установка Node
curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

# Установка необходимых системных пакетов
sudo apt-get update
sudo apt-get install -y build-essential software-properties-common

# Установка Python
if sudo add-apt-repository -y ppa:deadsnakes/ppa && \
   sudo apt-get update && \
   sudo apt-get install -y python3.12 python3.12-dev; then
    echo "✅ Установлен Python 3.12 и python3.12-dev"
else
    echo "⚠️  Python 3.12 не найден, устанавливаю python3.10-dev..."
    sudo apt-get install -y python3.10-dev
fi

export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc 2>/dev/null || true

# Глобальные npm пакеты
sudo npm install -g yarn
sudo npm install -g n
sudo n lts
n 20.18.0

# Закрытие старых screen-сессий и очистка порта
screen -ls | grep "\.gensyn" | cut -d. -f1 | awk '{print $1}' | xargs -r kill
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# ========= ⚙️ Аргументы =========
RECLONE="${1:-n}"
USE_CPU_FLAG="${2:-}"
REMOVE_TEMP_DATA="${3:-n}"
# ================================

# Получаем абсолютный путь к директории, где запускается скрипт
BASE_DIR="$(pwd)"

# Работа с репозиторием RL Swarm
if [ "$RECLONE" == "y" ]; then
    echo "📥 Удаляю старую папку и клонирую заново..."
    rm -rf rl-swarm
    git clone https://github.com/odovich-dev/rl-swarm.git
    cd rl-swarm
else
    if [ ! -d "rl-swarm" ]; then
        echo "📥 Папка не найдена, клонирую..."
        git clone https://github.com/odovich-dev/rl-swarm.git
    fi
    cd rl-swarm
    echo "🔄 Обновляю репозиторий через git pull..."
    git pull
fi

# ========= 📦 Работа с архивом и temp-data =========
ARCHIVE_FOUND=$(find "$BASE_DIR" -maxdepth 1 -type f -name '[0-9]*.tar' | head -n 1)
if [ -n "$ARCHIVE_FOUND" ]; then
    echo "📦 Найден архив $ARCHIVE_FOUND. Распаковываю..."
    tar -xvf "$ARCHIVE_FOUND" -C "$BASE_DIR"
    echo "✅ Архив успешно распакован!"

    if [ "$REMOVE_TEMP_DATA" == "y" ]; then
        TEMP_DATA_DIR="$BASE_DIR/rl-swarm/modal-login/temp-data"
        if [ -d "$TEMP_DATA_DIR" ]; then
            echo "🗑  Удаляю файлы из $TEMP_DATA_DIR..."
            rm -rf "$TEMP_DATA_DIR"/*
            echo "✅ Файлы из temp-data успешно удалены!"
        else
            echo "ℹ️  Папка temp-data не найдена."
        fi
    fi
else
    echo "ℹ️  Архивов для распаковки не найдено в $BASE_DIR."
fi

# ========= 🚀 Запуск в screen =========
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
