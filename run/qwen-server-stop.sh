#!/usr/bin/env bash
# Detiene el llama-server iniciado por qwen-server-start.sh.
PIDFILE=$HOME/.local/state/qwen-llama/server.pid
if [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")"
  for _ in $(seq 1 30); do kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break; sleep 1; done
  kill -9 "$(cat "$PIDFILE")" 2>/dev/null || true
  echo "Detenido."
else
  echo "No estaba en ejecución."
fi
rm -f "$PIDFILE"
