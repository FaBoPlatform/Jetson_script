#!/bin/bash

# Jetson Orin Nano, AGX Orin
# JetPack6.2.1用
# LeRobotのInstall Script
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

# set -e 対策で || true を付けて、既に同意済みでも落ちないようにする
if command -v conda >/dev/null 2>&1; then
  if conda tos --help >/dev/null 2>&1; then
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
  fi
fi

# ~/.bashrc に一度だけ lerobot 環境の自動有効化を追記
LERO_TAG="### lerobot auto-activate (robot script)"
grep -qxF "$LERO_TAG" "$HOME/.bashrc" || cat >>"$HOME/.bashrc" <<'BASHRC'
### lerobot auto-activate (robot script)
# Miniconda が使えるときだけ有効化する
if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
  . "$HOME/miniconda/etc/profile.d/conda.sh"
  conda activate lerobot
fi
### End lerobot auto-activate
BASHRC

source "$HOME/.bashrc"

eval "$(conda shell.bash hook)"

conda create -y -n lerobot python=3.10
conda activate lerobot
 
# ===== lerobot by Huggingface=====
pip3 install lerobot==0.4.0

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

# --- JetPack 6.2.1 用 GPU wheel（URL内hashを固定しない） ---
pip3 uninstall -y torch torchvision || true

JETSON_INDEX_URL="https://pypi.jetson-ai-lab.io/jp6/cu126"
TORCH_VER="2.8.0"
TV_VER="0.23.0"

# 1) index から該当 wheel をダウンロード（hash/path は index 側から解決される）
python3 -m pip download \
  --no-deps \
  --only-binary=:all: \
  --no-cache-dir \
  --index-url "$JETSON_INDEX_URL" \
  -d "$TMP" \
  "torch==${TORCH_VER}" "torchvision==${TV_VER}"

# 2) 落ちてきた wheel を特定
TORCH_WHL="$(find "$TMP" -maxdepth 1 -type f -name "torch-${TORCH_VER}-*-linux_aarch64.whl" | sort | head -n 1)"
TV_WHL="$(find "$TMP" -maxdepth 1 -type f -name "torchvision-${TV_VER}-*-linux_aarch64.whl" | sort | head -n 1)"

[ -n "$TORCH_WHL" ] || { echo "❌ torch wheel not found in $TMP" >&2; exit 1; }
[ -n "$TV_WHL" ] || { echo "❌ torchvision wheel not found in $TMP" >&2; exit 1; }

# 3) sha256 を“実行時に”計算（＝動的生成）
TORCH_SHA="$(sha256sum "$TORCH_WHL" | awk '{print $1}')"
TV_SHA="$(sha256sum "$TV_WHL" | awk '{print $1}')"

echo "torch wheel sha256      : $TORCH_SHA"
echo "torchvision wheel sha256: $TV_SHA"

# （任意）Jetson AI Lab の +f URL 形式（例と同じ規則）を“実行時に生成”して表示
# ※ このURL形式が将来変わる可能性はあるので「表示だけ」に留めるのが無難です
echo "torch direct-url (generated): ${JETSON_INDEX_URL}/+f/${TORCH_SHA:0:3}/${TORCH_SHA:3:13}/$(basename "$TORCH_WHL")#sha256=${TORCH_SHA}"
echo "tv    direct-url (generated): ${JETSON_INDEX_URL}/+f/${TV_SHA:0:3}/${TV_SHA:3:13}/$(basename "$TV_WHL")#sha256=${TV_SHA}"

# 4) ローカル wheel からインストール（依存は通常通り PyPI から入る）
python3 -m pip install "$TORCH_WHL" "$TV_WHL"

# Dynamixel SDK
pip3 install dynamixel-sdk
pip3 install feetech-servo-sdk

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

curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g @anthropic-ai/claude-code

rm -rf "$TMP"

# USB Speakerの認識
# pactl list short sinks
# 0   alsa_output.platform-sound.analog-stereo    module-alsa-card.c  s16le 2ch 44100Hz   SUSPENDED
# 1   alsa_output.usb-C-Media_INC._USB_Sound_Device-00.analog-stereo  module-alsa-card.c  s16le 2ch 44100Hz   RUNNING
# pactl set-default-sink alsa_output.usb-C-Media_INC._USB_Sound_Device-00.analog-stereo
# spd-say "warmup record"
