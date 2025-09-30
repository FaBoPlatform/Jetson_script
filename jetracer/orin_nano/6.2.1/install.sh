#!/bin/bash
# Jetson Orin Nano / JetPack 6.2.1
# FaBo JetFormer / FaBo JetRacer install script
set -Eeuo pipefail

###############################################################################
# 0) 環境変数・一時ディレクトリ（$TMP）設定
###############################################################################
# ユーザー/ホーム（必要に応じて変更）
USER_NAME="${USER_NAME:-jetson}"
HOME_DIR="${HOME_DIR:-/home/${USER_NAME}}"
JUPYTER_HOME_DIR="${JUPYTER_HOME_DIR:-${HOME_DIR}/notebooks/}"

# $TMP を用意（未設定なら自動作成）。作成した場合のみ後で削除する。
if [[ -z "${TMP:-}" ]]; then
  TMP="$(mktemp -d -t jetsetup.XXXXXX)"
  TMP_CREATED=1
else
  mkdir -p "$TMP"
  TMP_CREATED=0
fi

# pip / npm / 一時ファイルの作業場所を $TMP に寄せる
export TMPDIR="$TMP"
export PIP_CACHE_DIR="$TMP/pip-cache"
export npm_config_cache="$TMP/npm-cache"

# PATH
export PATH="$HOME_DIR/.local/bin:$PATH"

echo "[INFO] TMP = $TMP"

###############################################################################
# 1) sudo キープアライブ（終了時に kill）
###############################################################################
sudo -v
( while true; do sudo -n true; sleep 60; done ) &
SUDO_PID=$!

cleanup() {
  # sudo keepalive 終了
  if [[ -n "${SUDO_PID:-}" ]]; then
    kill "$SUDO_PID" 2>/dev/null || true
  fi
  # 自分で作った $TMP のみ削除
  if [[ "${TMP_CREATED:-0}" -eq 1 && -n "${TMP:-}" && -d "${TMP}" ]]; then
    echo "[INFO] Cleaning TMP: $TMP"
    rm -rf "${TMP}"
  fi
}
trap cleanup EXIT

###############################################################################
# 2) 必要パッケージ
###############################################################################
sudo apt-get update
sudo apt-get install -y \
  python3-pip curl libopenblas-base libopenblas-dev \
  libjpeg-dev zlib1g-dev libpng-dev \
  python3-libnvinfer python3-packaging

python3 -m pip install --upgrade pip
python3 -m pip install \
  smbus==1.1.post2 setuptools==59.6.0 wheel==0.37.1 \
  testresources==2.0.1 pytz==2022.7.1 tqdm==4.67.1

###############################################################################
# 3) FaBo PCA9685（$TMP に一時 clone → インストール）
###############################################################################
git clone https://github.com/FaBoPlatform/FaBoPWM-PCA9685-Python "$TMP/FaBoPWM-PCA9685-Python"
python3 -m pip install "$TMP/FaBoPWM-PCA9685-Python"

###############################################################################
# 4) JetRacer（常駐：$HOME/jetracer）
###############################################################################
mkdir -p "$JUPYTER_HOME_DIR"
cd "$HOME_DIR"
if [[ ! -d "$HOME_DIR/jetracer" ]]; then
  git clone https://github.com/FaBoPlatform/jetracer "$HOME_DIR/jetracer"
fi
cd "$HOME_DIR/jetracer"
git fetch --all --tags || true
git checkout AI86 || true
python3 -m pip install -e .
# notebooks をユーザー用にコピー（上書きしない）
cp -rn notebooks "$JUPYTER_HOME_DIR" || true
cd "$HOME_DIR"

###############################################################################
# 5) JetCam（pip から。キャッシュは $TMP）
###############################################################################
python3 -m pip install "git+https://github.com/NVIDIA-AI-IOT/jetcam.git"

###############################################################################
# 6) PyTorch / TorchVision (aarch64 wheels を $TMP に保存してからインストール)
###############################################################################
wget -O "$TMP/torch-2.8.0-cp310-cp310-linux_aarch64.whl" \
  "https://pypi.jetson-ai-lab.io/jp6/cu129/+f/72e/b2fce22ddccb4/torch-2.8.0-cp310-cp310-linux_aarch64.whl"
python3 -m pip install "$TMP/torch-2.8.0-cp310-cp310-linux_aarch64.whl"

wget -O "$TMP/torchvision-0.23.0-cp310-cp310-linux_aarch64.whl" \
  "https://pypi.jetson-ai-lab.io/jp6/cu129/+f/565/6a8a5e3672c15/torchvision-0.23.0-cp310-cp310-linux_aarch64.whl"
python3 -m pip install "$TMP/torchvision-0.23.0-cp310-cp310-linux_aarch64.whl"

###############################################################################
# 7) torch2trt（$TMP に一時 clone → インストール）
###############################################################################
git clone https://github.com/NVIDIA-AI-IOT/torch2trt "$TMP/torch2trt"
cd "$TMP/torch2trt"
python3 -m pip install --upgrade "Cython<3" || true
python3 -m pip install --install-option="--plugins" .
cd "$HOME_DIR"

###############################################################################
# 8) ResNet18 / 50 の事前ダウンロード（~/.cache に保存）
###############################################################################
python3 - <<'PY'
import torchvision
# torchvision 0.23 の新API。重みをダウンロードしてローカルにキャッシュ
torchvision.models.resnet18(weights="IMAGENET1K_V1")
torchvision.models.resnet50(weights="IMAGENET1K_V1")
PY

###############################################################################
# 9) Node.js（セットアップスクリプトを $TMP に保存してから）
###############################################################################
curl -fsSL https://deb.nodesource.com/setup_20.x -o "$TMP/nodesource_setup.sh"
sudo -E bash "$TMP/nodesource_setup.sh"
sudo apt-get install -y nodejs

###############################################################################
# 10) JupyterLab + クリック可能ウィジェット
###############################################################################
python3 -m pip install "jupyter" "jupyterlab==3.2.9"
# labmanager
jupyter labextension install @jupyter-widgets/jupyterlab-manager

# jupyter_clickable_image_widget（$TMP に clone → インストール）
git clone -b dev-ipywidgets8 https://github.com/tokk-nv/jupyter_clickable_image_widget "$TMP/jciw"
python3 -m pip install "$TMP/jciw"
# ローカル JS ソースから拡張を追加
jupyter labextension install "$TMP/jciw/js"

###############################################################################
# 11) Jupyter 設定（パスワード/テーマ/保存設定）
###############################################################################
# 既存設定を消す
if [ -f "$HOME_DIR/.jupyter/jupyter_server_config.py" ]; then
  rm "$HOME_DIR/.jupyter/jupyter_server_config.py"
  echo "既存の設定ファイルを削除しました。"
fi

# 設定生成
jupyter server --generate-config
echo "新しい設定ファイルを生成しました。"

# パスワード設定
PASSWORD='jetson'
HASHED_PASSWORD=$(python3 -c "from jupyter_server.auth import passwd; print(passwd('$PASSWORD'))")
echo "c.ServerApp.password = '$HASHED_PASSWORD'" >> "$HOME_DIR/.jupyter/jupyter_server_config.py"

# 自動保存OFF
mkdir -p "$HOME_DIR/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension"
cat > "$HOME_DIR/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension/plugin.jupyterlab-settings" <<'JSON'
{
  // Autosave Documents
  "autosave": false
}
JSON

# ターミナル ダークテーマ
mkdir -p "$HOME_DIR/.jupyter/lab/user-settings/@jupyterlab/terminal-extension"
cat > "$HOME_DIR/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings" <<'JSON'
{
  // Theme
  "theme": "dark"
}
JSON

# ターミナル配色（該当ファイルがあれば置換）
JUPYTER_TERMINAL_COLOR_FILE=$(
  find "$(jupyter --data-dir)/lab/static/" -type f -name "*.js" -exec grep -l "#3465a4" {} + 2>/dev/null || true
)
if [ -n "${JUPYTER_TERMINAL_COLOR_FILE:-}" ]; then
  sed -i 's/#2e3436/#000000/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#cc0000/#cd0000/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#4e9a06/#00cd00/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#c4a000/#cdcd00/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#3465a4/#add8e6/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#75507b/#cd00cd/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#06989a/#00cdcd/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#d3d7cf/#faebd7/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#555753/#404040/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#ef2929/#ff0000/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#8ae234/#00ff00/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#fce94f/#ffff00/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#729fcf/#7fffd4/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#ad7fa8/#ff00ff/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#34e2e2/#00ffff/g' "$JUPYTER_TERMINAL_COLOR_FILE"
  sed -i 's/#eeeeec/#ffffff/g' "$JUPYTER_TERMINAL_COLOR_FILE"
else
  echo "ターミナルのカラー設定ファイルが見つかりませんでした。"
fi

###############################################################################
# 12) systemd: JupyterLab サービス
###############################################################################
JUPYTER_BIN="$(command -v jupyter)"
cat <<EOF | sudo tee /etc/systemd/system/jupyterlab.service > /dev/null
[Unit]
Description=JupyterLab

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${HOME_DIR}/jetracer/utils
ExecStart=${JUPYTER_BIN} lab --ip=0.0.0.0 --no-browser --ServerApp.root_dir=/ --LabApp.default_url="/lab?file-browser-path=${JUPYTER_HOME_DIR}"
Restart=always
RestartSec=10
Environment=HOME=${HOME_DIR}
Environment=PATH=${HOME_DIR}/.local/bin:/usr/local/bin:/usr/bin

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jupyterlab.service
sudo systemctl start jupyterlab.service
echo "JupyterLab サービスを開始しました。"

###############################################################################
# 13) SSD1306
###############################################################################
sudo python3 -m pip install Adafruit-SSD1306==1.6.2

###############################################################################
# 14) 環境変数
###############################################################################
if ! grep -q "^export JETSON_MODEL_NAME=JETSON_ORIN_NANO$" "$HOME_DIR/.bashrc"; then
  echo 'export JETSON_MODEL_NAME=JETSON_ORIN_NANO' >> "$HOME_DIR/.bashrc"
  echo "環境変数 JETSON_MODEL_NAME=JETSON_ORIN_NANO を ~/.bashrc に追加しました。"
else
  echo "環境変数 JETSON_MODEL_NAME は ~/.bashrc に既に設定済みです。"
fi

###############################################################################
# 15) systemd: IP Status サービス
###############################################################################
cat <<EOF | sudo tee /etc/systemd/system/ip_status.service > /dev/null
[Unit]
Description=ip_stats

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${HOME_DIR}
ExecStart=/usr/bin/python3 ${HOME_DIR}/jetracer/utils/wifi_stats.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ip_status.service
sudo systemctl start ip_status.service
echo "IP Status サービスを開始しました。"

###############################################################################
# 16) apt キャッシュを最後にクリーン
###############################################################################
sudo apt-get clean

# IMX219 カメラの有効化(手動)
# sudo /opt/nvidia/jetson-io/jetson-io.py
# [Configure Jetson 24pin CSI Connector] -> [Configure for compatible hardware] -> [Camera IMX219 Dual] を有効化
