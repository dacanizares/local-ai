#!/usr/bin/env bash
# Matriz de perfiles del servidor: arranca cada configuración y mide generación con prompt corto,
# ingesta y generación con un prompt largo (~35k tokens) y VRAM usada.
# Uso: docs/server-benchmark/server-matrix.sh [salida.tsv]
#      ONLY='run nombre ctx ngl "spec" "extra"; ...' para correr solo esos perfiles (añade filas)
# Detiene qwen-llama.service mientras corre; vuelve a iniciarlo después con systemctl --user start qwen-llama.
set -u
cd "$(dirname "$0")/../.."
HERE=docs/server-benchmark
OUT=${1:-$HERE/results.tsv}
R=run
TMP=${TMPDIR:-/tmp}/local-ai-bench; mkdir -p "$TMP"
systemctl --user stop qwen-llama 2>/dev/null; $R/qwen-server-stop.sh >/dev/null

# prompts de prueba generados con los propios archivos del repo (repetidos hasta ~120k caracteres)
python3 -I - "$TMP" <<'PY'
import json,glob,sys
tmp=sys.argv[1]
src="".join(open(f,errors='ignore').read() for f in sorted(glob.glob('run/*')+glob.glob('docs/**/*.md',recursive=True)))
src=(src*200)[:120000]
json.dump({"model":"x","max_tokens":120,"messages":[{"role":"user","content":src+"\n\nResume en una frase qué hace este código."}]},open(f'{tmp}/long.json','w'))
json.dump({"model":"x","max_tokens":300,"messages":[{"role":"user","content":"Escribe una función Python que invierta una lista enlazada, con explicación breve."}]},open(f'{tmp}/short.json','w'))
PY

[ -n "${ONLY:-}" ] || printf 'name\tstatus\tctx\tngl\tshort_tg\tlong_prompt_tokens\tlong_pp\tlong_tg\tvram_used_mb\tmtp_accept\n' > "$OUT"
MTP="--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-type-k q4_0 --spec-draft-type-v q4_0"
run() { # nombre ctx ngl "spec" "extra"
  local name=$1 ctx=$2 ngl=$3 spec=$4 extra=$5
  $R/qwen-server-stop.sh >/dev/null; sleep 2
  if ! CTX=$ctx NGL=$ngl SPEC_ARGS="$spec" EXTRA_ARGS="$extra" $R/qwen-server-start.sh >/dev/null 2>&1; then
    printf '%s\tFAIL_START\t%s\t%s\t\t\t\t\t\t\n' "$name" "$ctx" "$ngl" >> "$OUT"; return; fi
  read -r stg acc < <(curl -s localhost:8081/v1/chat/completions -d @"$TMP/short.json" | python3 -I -c "import sys,json;t=json.load(sys.stdin)['timings'];print(round(t['predicted_per_second'],1), (round(t['draft_n_accepted']/max(t['draft_n'],1),2) if t.get('draft_n') else '-'))")
  read -r lpt lpp ltg < <(curl -s -m 1500 localhost:8081/v1/chat/completions -d @"$TMP/long.json" | python3 -I -c "
import sys,json
d=json.load(sys.stdin)
if 'error' in d: print('ERR 0 0')
else: print(d['usage']['prompt_tokens'], round(d['timings']['prompt_per_second']), round(d['timings']['predicted_per_second'],1))")
  local vram; vram=$(rocm-smi --showmeminfo vram 2>/dev/null | awk '/Used/{printf "%d", $NF/1048576}')
  printf '%s\tOK\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$ctx" "$ngl" "$stg" "$lpt" "$lpp" "$ltg" "$vram" "$acc" >> "$OUT"
}
# el modelo tiene 65 bloques: -ngl >= 65 lo carga todo en GPU
if [ -n "${ONLY:-}" ]; then eval "$ONLY"; else
run base_131k_q4      131072 99 ""     ""
run mtp_82k           81920  99 "$MTP" ""
run mtp_ngl58_131k    131072 58 "$MTP" ""
run ngl57_196k        196608 57 ""     ""
run kvram_262k_ngl99  262144 99 ""     "--no-kv-offload"
run ngl52_262k        262144 52 ""     ""
run mtp_ngl53_196k    196608 53 "$MTP" ""
fi
$R/qwen-server-stop.sh >/dev/null
