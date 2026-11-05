#!/usr/bin/env bash
# Instala qwen-llama.service (systemd de usuario) apuntando a los scripts de este repo y lo habilita al iniciar sesión.
set -euo pipefail
RUN="$(cd "$(dirname "$0")" && pwd)"
UNIT=$HOME/.config/systemd/user/qwen-llama.service
mkdir -p "$(dirname "$UNIT")"
cat > "$UNIT" <<EOF
[Unit]
Description=Qwen3.8-27B llama-server (RX 6900 XT)

[Service]
Type=forking
PIDFile=%h/.local/state/qwen-llama/server.pid
ExecStart=$RUN/qwen-server-start.sh
ExecStop=$RUN/qwen-server-stop.sh
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable qwen-llama.service
echo "Instalado: $UNIT (iniciar ahora: systemctl --user start qwen-llama)"
