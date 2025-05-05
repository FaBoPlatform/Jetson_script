#!/bin/bash

# Jetson Orin Nano, AGX Orin
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

TMP=$(mktemp -d)

# ===== APT =====
sudo apt-get update
sudo apt-get install -y \
    python3-pip curl build-essential \
    libopenblas-base libopenblas-dev \
    libjpeg-dev zlib1g-dev libpng-dev \
    python3-libnvinfer python3-packaging \
    cuda-runtime-12-6 libcublas-12-6 \
    libcublas-dev-12-6 cuda-cupti-12-6 

# ===== Miniconda (非対話) =====
MINI="$HOME/miniconda"
if [ ! -d "$MINI" ]; then
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O "$TMP/miniconda.sh"
  bash "$TMP/miniconda.sh" -b -p "$MINI"
fi
source "$MINI/etc/profile.d/conda.sh"

# ~/.bashrc に一度だけ Miniconda 初期化を追記
BASHRC_TAG="### Miniconda init (robot script)"
grep -qxF "$BASHRC_TAG" "$HOME/.bashrc" || cat >>"$HOME/.bashrc" <<'BASHRC'
### Miniconda init (robot script)
if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
  . "$HOME/miniconda/etc/profile.d/conda.sh"
  export PATH="$HOME/miniconda/bin:$PATH"
fi
### End Miniconda init
BASHRC

source "$HOME/.bashrc"

conda create -y -n robot python=3.10
conda activate robot
 
# ===== lerobot by Huggingface=====
git clone https://github.com/huggingface/lerobot ~/lerobot || true
cd ~/lerobot
pip install -e ".[feetech]"

# ===== OttherARM by FaBo ====
cd ~/
git clone https://github.com/FaBoPlatform/otterarm/ ~/otter || true

# ===== OpenCV は pip で入れる =====
conda install -y -c conda-forge "opencv>=4.10.0.84"
conda remove -y opencv        # ← 自動で Yes
pip3 install --no-cache-dir opencv-python==4.10.0.84

# ===== conda パッケージ =====
conda install -y -c conda-forge ffmpeg libpng 

# ===== pip パッケージ =====
pip3 install --upgrade pip wheel

# (PyTorch 系は NumPy<2 が必須)
pip3 install "numpy<2" --no-cache-dir

# --- JetPack 6.2 用 GPU wheel (2.5.0 固定) ---
pip3 uninstall -y torch torchvision || true 

# ---- PyTorch 2.5.0 (CUDA 12.6, aarch64) ----
wget -O "$TMP/torch-2.5.0-cp310-cp310-linux_aarch64.whl" \
  http://jetson.webredirect.org/jp6/cu126/+f/5cf/9ed17e35cb752/torch-2.5.0-cp310-cp310-linux_aarch64.whl
pip3 install "$TMP/torch-2.5.0-cp310-cp310-linux_aarch64.whl"

# ---- TorchVision 0.20.0 (ビルド済み aarch64) ----
wget -O "$TMP/torchvision-0.20.0-cp310-cp310-linux_aarch64.whl" \
  http://jetson.webredirect.org/jp6/cu126/+f/5f9/67f920de3953f/torchvision-0.20.0-cp310-cp310-linux_aarch64.whl
pip3 install "$TMP/torchvision-0.20.0-cp310-cp310-linux_aarch64.whl"

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

rm -rf "$TMP"

# USB Speakerの認識
# pactl list short sinks
# 0   alsa_output.platform-sound.analog-stereo    module-alsa-card.c  s16le 2ch 44100Hz   SUSPENDED
# 1   alsa_output.usb-C-Media_INC._USB_Sound_Device-00.analog-stereo  module-alsa-card.c  s16le 2ch 44100Hz   RUNNING
# pactl set-default-sink alsa_output.usb-C-Media_INC._USB_Sound_Device-00.analog-stereo
# spd-say "warmup record"
