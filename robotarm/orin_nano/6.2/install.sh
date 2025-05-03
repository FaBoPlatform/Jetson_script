#!/bin/bash

# Jetson Orin Nano
# JetPack6.2用
# FaBo RobotARMのInstall Script
#!/usr/bin/env bash

set -euo pipefail

# ===== 基本設定 =====
trap 'kill ${SUDO_PID:-0} >/dev/null 2>&1 || true' EXIT

# sudo keep-alive
sudo -v
( while true; do sudo -n true; sleep 60; done ) &
SUDO_PID=$!

# ===== APT =====
sudo apt-get update
sudo apt-get install -y \
    python3-pip curl build-essential \
    libopenblas-base libopenblas-dev \
    libjpeg-dev zlib1g-dev libpng-dev \
    python3-libnvinfer python3-packaging

# ===== Miniconda (非対話) =====
MINI="$HOME/miniconda"
if [ ! -d "$MINI" ]; then
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p "$MINI"
fi
source "$MINI/etc/profile.d/conda.sh"

conda create -y -n robotarm python=3.10
conda activate robotarm
 
# ===== lerobot by Huggingface=====
git clone https://github.com/huggingface/lerobot ~/lerobot || true
pip install -e ~/lerobot

# ===== OttherARM by FaBo ====
git clone https://github.com/FaBoPlatform/otterarm/ ~/otter || true

# ===== conda パッケージ =====
conda install -y -c conda-forge ffmpeg libpng jpeg

# ===== opencv パッケージ =====
conda install -y -c conda-forge "opencv>=4.10.0.84"  
conda remove opencv   # Uninstall OpenCV 
pip3 install opencv-python==4.10.0.84 

# ===== pip パッケージ =====
pip install --upgrade pip wheel

# (PyTorch 系は NumPy<2 が必須)
pip install "numpy<2" --no-cache-dir

# --- JetPack 6.2 用 GPU wheel (2.5.0 固定) ---
pip3 uninstall -y torch torchvision || true   # ← パッケージ名修正 & エラー無視

# PyTorchのインストール
wget http://jetson.webredirect.org/jp6/cu126/+f/5cf/9ed17e35cb752/torch-2.5.0-cp310-cp310-linux_aarch64.whl#sha256=5cf9ed17e35cb7523812aeda9e7d6353c437048c5a6df1dc6617650333049092
pip3 install torch-2.5.0-cp310-cp310-linux_aarch64.whl

# TorchVisionのインストール
wget http://jetson.webredirect.org/jp6/cu126/+f/5f9/67f920de3953f/torchvision-0.20.0-cp310-cp310-linux_aarch64.whl#sha256=5f967f920de3953f2a39d95154b1feffd5ccc06b4589e51540dc070021a9adb9
pip3 install torchvision-0.20.0-cp310-cp310-linux_aarch64.whl 

# Dynamixel SDK
pip3 install dynamixel-sdk

# モデルを事前ダウンロード
python - <<'PY'
import torchvision
for name in ("resnet18", "resnet50"):
    torchvision.models.get_model(name, weights="DEFAULT")
PY

# ===== ttyACM0/1 を 0666 に固定する udev ルール =====
sudo tee /etc/udev/rules.d/99-otterarm-ttyacm.rules >/dev/null <<'EOF'
KERNEL=="ttyACM0", MODE="0666"
KERNEL=="ttyACM1", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger   # 既存デバイスにも即適用

# ===== CUDA 動作確認 =====
python - <<'PY'
import sys, torch
print("PyTorch :", torch.__version__)
print("CUDA OK :", torch.cuda.is_available())
if not torch.cuda.is_available():
    sys.exit("❌  GPU (CUDA) が利用できません")
print("Device  :", torch.cuda.get_device_name(0))
print("✅  CUDA が正常に認識されました")
PY

echo "✅ Installation completed."
