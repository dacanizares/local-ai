# Benchmark de perfiles del servidor

Qué configuración de `llama-server` le saca más a una **RX 6900 XT (16 GB VRAM)** + 62 GB RAM con
**Qwen3.8-27B `UD-IQ4_XS`** (14,25 GB), dedicando toda la máquina a **un solo agente** (`--parallel 1`).

- Script: [server-matrix.sh](server-matrix.sh) — arranca cada perfil con `run/qwen-server-start.sh` y mide.
- Resultados: [results.tsv](results.tsv).

## Resultados (2026-11-04)

| Perfil | Contexto | Capas en GPU | Gen. prompt corto (tok/s) | Prompt 35k: ingesta / gen. (tok/s) | VRAM (MB) |
|---|---:|---:|---:|---:|---:|
| **base** (elegido) | **131 072** | 65/65 | **24,7** | 412 / 17,2 | 16 347 |
| MTP (`draft-mtp`, n-max 2) | 81 920 | 65/65 | **45,8** | 366 / **30,1** | 16 356 |
| MTP + capas en CPU | 131 072 | 58 | 23,0 | 363 / 12,5 | 16 340 |
| capas en CPU | 196 608 | 57 | 11,3 | 373 / 8,3 | 16 125 |
| KV cache en RAM (`--no-kv-offload`) | 262 144 | 65/65 | 11,2 | 372 / 7,8 | 14 851 |
| capas en CPU | 262 144 | 52 | 8,8 | 355 / 6,5 | 16 350 |
| MTP + capas en CPU | 196 608 | 53 | no arranca (sin VRAM) | | |

Todos con KV `q4_0`, flash attention y `-ub 256`. Aceptación de los tokens especulados con MTP: ~75 %.

## Conclusiones

- **Todo en GPU o nada.** Mover capas o el KV a la CPU cuesta entre la mitad y dos tercios de la velocidad; la CPU no compensa.
- **El MTP casi duplica la generación**, pero su drafter necesita su propio KV y a 16 GB solo cabe con ~82k de contexto.
- **131k todo en GPU** es el máximo contexto a velocidad completa. Se eligió porque un agente de código real
  (Claude Code implementando un backend) llegó a ~75k tokens de contexto: con 82k no hay margen.
- En tareas de agente, el **~88 % del tiempo es generación**; la ingesta de prompt casi no pesa gracias a la caché de prefijos.
  Por eso, si el contexto cabe, el perfil MTP es el que más acelera.

## Notas del modelo

- 65 bloques (64 + 1 de MTP), atención completa 1 de cada 4 capas, 4 cabezas KV: el KV ocupa ~18 KB por token en `q4_0`.
- Sin `GGML_BACKEND_PATH` apuntando a `libggml-hip.so`, el `llama-server` de Ollama cae a CPU (~2 tok/s).
