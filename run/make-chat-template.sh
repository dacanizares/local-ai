#!/usr/bin/env bash
# Descarga la plantilla de chat oficial de Qwen3.8-27B y genera la versión para agentes:
# la oficial aborta con "System message must be at the beginning" cuando un cliente (Claude Code)
# envía mensajes de sistema a mitad de conversación; aquí se renderizan como un turno de usuario.
set -euo pipefail
DIR=${1:-$HOME/models/qwen3.8-27b}
mkdir -p "$DIR"
curl -sfL -o "$DIR/chat_template.orig.jinja" https://huggingface.co/Qwen/Qwen3.8-27B/resolve/main/chat_template.jinja
python3 -I - "$DIR" <<'PY'
import sys
d=sys.argv[1]
s=open(f'{d}/chat_template.orig.jinja').read()
old="""        {%- if not loop.first %}
            {{- raise_exception('System message must be at the beginning.') }}
        {%- endif %}"""
new="""        {%- if not loop.first %}
            {{- '<|im_start|>user\\n' + content + '<|im_end|>' + '\\n' }}
        {%- endif %}"""
assert old in s, "la plantilla oficial cambió: revisar el parche"
open(f'{d}/chat_template.agent.jinja','w').write(s.replace(old,new))
PY
echo "OK: $DIR/chat_template.agent.jinja"
