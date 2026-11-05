# local-ai

Qwen3.8-27B corriendo 100 % local en una **AMD RX 6900 XT (16 GB)** como modelo de agentes de programación
(Qwen Code, Claude Code), servido con `llama-server` (llama.cpp + ROCm) en una API compatible con OpenAI y Anthropic.

## Requisitos

- Linux con ROCm funcionando para la GPU (gfx1030).
- [Ollama](https://ollama.com) instalado: se reutiliza su `llama-server` y su backend HIP (`/usr/local/lib/ollama`).
- El modelo [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF), cuantización `UD-IQ4_XS` (14,25 GB), en `~/models/qwen3.8-27b/`.

## Uso

```bash
run/make-chat-template.sh        # plantilla de chat que acepta mensajes de sistema a mitad de conversación
run/qwen-server-start.sh         # http://127.0.0.1:8081/v1  (131k de contexto, todo en GPU)
run/qwen-server-stop.sh
run/install-service.sh           # opcional: servicio systemd de usuario, arranca al iniciar sesión
```

Por defecto escucha en el puerto **8081**. El 8080 queda libre para las apps que se desarrollan.

## Conectar clientes

**Qwen Code** (`~/.qwen/settings.json`, dentro de `modelProviders.openai`):

```json
{ "id": "qwen3.8-27b", "name": "Qwen3.8-27B local", "envKey": "LLAMACPP_API_KEY",
  "baseUrl": "http://127.0.0.1:8081/v1",
  "generationConfig": { "timeout": 600000, "contextWindowSize": 131072 } }
```

**Claude Code**, usando el endpoint Anthropic de `llama-server`:

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:8081 ANTHROPIC_AUTH_TOKEN=local
export ANTHROPIC_MODEL=qwen3.8-27b ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.8-27b ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.8-27b
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=110000   # compactar antes del límite de 131k
```

## Lo que hizo falta para que funcione con agentes

| Problema | Solución |
|---|---|
| El `llama-server` de Ollama no encontraba la GPU (corría en CPU a ~2 tok/s) | `GGML_BACKEND_PATH=.../rocm_v7_2/libggml-hip.so` |
| El Q4_K_M (18 GB) no cabe en 16 GB: Ollama lo partía 76 % GPU / 24 % CPU | `UD-IQ4_XS` (14,25 GB) todo en GPU |
| La plantilla de Qwen aborta con mensajes de sistema intermedios (Claude Code los envía) | [`run/make-chat-template.sh`](run/make-chat-template.sh) |
| Bucles de razonamiento de 20k tokens que bloqueaban a un agente | `--reasoning-budget 4096` |
| Contexto de 64k insuficiente para un agente real (~72k) | 131k con KV `q4_0` y `-ub 256` |

Medidas de los perfiles (contexto, MTP, descarga a CPU): [docs/server-benchmark](docs/server-benchmark/INDEX.md).
