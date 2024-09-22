#!/bin/bash

# Jetson Orin Nano
# JetPack5.1.4用
# FaBo JetFormer, FaBo JetRacerのInstall Script

# スクリプト開始時に sudo のパスワードを一度入力
sudo -v

# スクリプトが終了するまで sudo セッションを維持
( while true; do sudo -v; sleep 60; done ) &
SUDO_PID=$!

# パッケージリストの更新
sudo apt-get update

# 必要なパッケージのインストール
sudo apt-get install -y python3-pip curl libopenblas-base libopenblas-dev libjpeg-dev zlib1g-dev libpng-dev python3-libnvinfer

# Pythonパッケージのインストール
pip3 install smbus==1.1.post2 setuptools==59.6.0 wheel==0.37.1 testresources==2.0.1 pytz==2022.7.1 

# FaBo PCA9685のインストール
git clone https://github.com/FaBoPlatform/FaBoPWM-PCA9685-Python
pip3 install FaBoPWM-PCA9685-Python/

# FaBo JetRacerのインストール
git clone https://github.com/FaBoPlatform/jetracer
cd jetracer
pip install -e .
cp -r notebooks ~/notebooks
cd ..

# JetCamのインストール
git clone https://github.com/NVIDIA-AI-IOT/jetcam
cd jetcam
pip install -e .
cd ..

# PyTorchのインストール
wget https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl
pip3 install torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl

# TorchVisionのインストール
git clone --branch v0.16.1 https://github.com/pytorch/vision torchvision
cd torchvision/
export BUILD_VERSION=0.16.1
python3 setup.py install --user
cd ..

# Torch2trt
git clone https://github.com/NVIDIA-AI-IOT/torch2trt
cd torch2trt
pip install --install-option="--plugins" .
cd ..

# Nodejsのインストール
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 
sudo apt-get install -y nodejs 

# ~/.local/bin を PATH に追加（必要な場合）
export PATH="$HOME/.local/bin:$PATH"

# JupyterLabのインストール
pip3 install jupyter  jupyterlab==3.2.9
jupyter labextension install @jupyter-widgets/jupyterlab-manager

# jupyter_clickable_image_widgetのインストール
git clone -b dev-ipywidgets8 https://github.com/tokk-nv/jupyter_clickable_image_widget
cd jupyter_clickable_image_widget
pip3 install -e .
jupyter labextension install js
cd ..

# JupyterLab の新しい設定ファイルを生成する
if [ -f "$HOME/.jupyter/jupyter_server_config.py" ]; then
    rm "$HOME/.jupyter/jupyter_server_config.py"
    echo "既存の設定ファイルを削除しました。"
fi
jupyter server --generate-config
echo "新しい設定ファイルを生成しました。"

# JupyterLab のパスワードを設定
PASSWORD='jetson'
HASHED_PASSWORD=$(python3 -c "from jupyter_server.auth import passwd; print(passwd('$PASSWORD'))")
echo "c.ServerApp.password = '$HASHED_PASSWORD'" >> ~/.jupyter/jupyter_server_config.py

# Jupyter Lab 自動保存を無効化
mkdir -p "$HOME/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension"
cat << EOF > "$HOME/.jupyter/lab/user-settings/@jupyterlab/docmanager-extension/plugin.jupyterlab-settings"
{
    // Autosave Documents
    "autosave": false
}
EOF

# Jupyter Lab ターミナルのダークテーマ設定
mkdir -p "$HOME/.jupyter/lab/user-settings/@jupyterlab/terminal-extension"
cat << EOF > "$HOME/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings"
{
    // Theme
    "theme": "dark"
}
EOF

# ターミナルのカラー設定を変更（必要に応じて）
# この部分は JupyterLab のバージョンや構成によって動作しない可能性があります
# ファイルパスを取得
JUPYTER_TERMINAL_COLOR_FILE=$(find "$(jupyter --data-dir)/lab/static/" -type f -name "*.js" -exec grep -l "#3465a4" {} + 2>/dev/null)

if [ -n "$JUPYTER_TERMINAL_COLOR_FILE" ]; then
    # JupyterLab のカラーコードを一括置換
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

# JupyterLab の起動を systemd サービスとして設定
USER_NAME="jetson"  # 実際のユーザー名に変更してください
HOME_DIR="/home/jetson"  # 実際のホームディレクトリに変更してください

# サービスファイルの内容を作成
SERVICE_FILE_CONTENT="[Unit]
Description=JupyterLab

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${HOME_DIR}/jetracer/utils
ExecStart=$(which jupyter) lab --ip=0.0.0.0 --no-browser --ServerApp.root_dir=/ --LabApp.default_url=\"/lab?file-browser-path=${HOME_DIR}\"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"

# サービスファイルを作成
echo "JupyterLab の systemd サービスファイルを作成しています..."
echo "$SERVICE_FILE_CONTENT" | sudo tee /etc/systemd/system/jupyterlab.service > /dev/null

# systemd デーモンをリロード
echo "systemd デーモンをリロードしています..."
sudo systemctl daemon-reload

# サービスを有効化
echo "JupyterLab サービスを有効化しています..."
sudo systemctl enable jupyterlab.service

# サービスを開始
echo "IP Status サービスを開始しています..."
sudo systemctl start jupyterlab.service

sudo pip3 install Adafruit-SSD1306==1.6.2

# サービスファイルの内容を作成
SERVICE_FILE_CONTENT="[Unit]
Description=ip_stats

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${HOME_DIR}
ExecStart=/usr/bin/python3 ${HOME_DIR}/jetracer/utils/stats.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"

# サービスファイルを作成
echo "IP Status の systemd サービスファイルを作成しています..."
echo "$SERVICE_FILE_CONTENT" | sudo tee /etc/systemd/system/ip_status.service > /dev/null

# systemd デーモンをリロード
echo "systemd デーモンをリロードしています..."
sudo systemctl daemon-reload

# サービスを有効化
echo "IP Status サービスを有効化しています..."
sudo systemctl enable ip_status.service

# サービスを開始
echo "IP Status  サービスを開始しています..."
sudo systemctl start ip_status.service

