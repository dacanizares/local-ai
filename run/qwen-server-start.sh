#!/usr/bin/env bash
# Inicia llama-server (llama.cpp, backend ROCm/HIP de Ollama) con Qwen3.8-27B en una RX 6900 XT (16 GB).
# Perfil por defecto: 131k de contexto todo en GPU (~25 tok/s). Perfil rápido con MTP (~46 tok/s, 82k):
#   CTX=81920 SPEC_ARGS="--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-type-k q4_0 --spec-draft-type-v q4_0"
# Medidas: docs/server-benchmark/INDEX.md
# Variables: MODEL, PORT, CTX, NGL, KV_TYPE, UBATCH, SPEC_ARGS, EXTRA_ARGS, REASONING_BUDGET, CHAT_TEMPLATE
set -euo pipefail

OLLAMA_LIB=/usr/local/lib/ollama
MODEL=${MODEL:-$HOME/models/qwen3.8-27b/Qwen3.8-27B-UD-IQ4_XS.gguf}
PORT=${PORT:-8081}
CTX=${CTX:-131072}
NGL=${NGL:-99}                              # el modelo tiene 65 bloques: >= 65 = todo en GPU
KV_TYPE=${KV_TYPE:-q4_0}                    # KV pequeño (atención completa 1 de cada 4 capas); q4_0 da margen de VRAM
UBATCH=${UBATCH:-256}                       # menor buffer de cómputo = más VRAM para contexto
SPEC_ARGS=${SPEC_ARGS-}                     # MTP desactivado por defecto: no cabe con 131k
EXTRA_ARGS=${EXTRA_ARGS-}                   # banderas extra de llama-server (p.ej. --no-kv-offload)
REASONING_BUDGET=${REASONING_BUDGET:-4096}  # tope de tokens de razonamiento por respuesta (evita bucles de thinking)
CHAT_TEMPLATE=${CHAT_TEMPLATE:-$HOME/models/qwen3.8-27b/chat_template.agent.jinja}  # run/make-chat-template.sh
STATE=$HOME/.local/state/qwen-llama
PIDFILE=$STATE/server.pid
LOG=$STATE/server.log

mkdir -p "$STATE"
if [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Ya en ejecución (pid $(cat "$PIDFILE")), puerto $PORT"; exit 0
fi
[[ -f $MODEL ]] || { echo "No existe el modelo: $MODEL" >&2; exit 1; }

# Ollama usa la misma GPU: descargar sus modelos para liberar VRAM.
if command -v ollama >/dev/null && ollama ps 2>/dev/null | tail -n +2 | grep -q .; then
  ollama ps | tail -n +2 | awk '{print $1}' | xargs -r -n1 ollama stop
fi

export LD_LIBRARY_PATH=$OLLAMA_LIB:$OLLAMA_LIB/rocm_v7_2${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export HIP_VISIBLE_DEVICES=0
export GGML_BACKEND_PATH=$OLLAMA_LIB/rocm_v7_2/libggml-hip.so

nohup "$OLLAMA_LIB/llama-server" \
  -m "$MODEL" --alias qwen3.8-27b \
  --host 127.0.0.1 --port "$PORT" \
  -ngl "$NGL" -c "$CTX" -fa on \
  -ctk "$KV_TYPE" -ctv "$KV_TYPE" \
  --jinja --chat-template-file "$CHAT_TEMPLATE" --no-mmproj \
  --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0 \
  --reasoning-budget "$REASONING_BUDGET" \
  --reasoning-budget-message "Tiempo de razonamiento agotado; responde ahora con lo analizado." \
  $SPEC_ARGS \
  -ub "$UBATCH" $EXTRA_ARGS \
  --parallel 1 \
  >"$LOG" 2>&1 &
echo $! >"$PIDFILE"

for _ in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
    echo "Listo: http://127.0.0.1:$PORT/v1 (pid $(cat "$PIDFILE"))"; exit 0
  fi
  kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { echo "El servidor terminó; ver $LOG" >&2; tail -20 "$LOG" >&2; exit 1; }
  sleep 1
done
echo "Timeout esperando al servidor; ver $LOG" >&2; exit 1
