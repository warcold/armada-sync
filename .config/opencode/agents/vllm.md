---
name: vLLM
description: Experto en el stack de inferencia local (vLLM :8000 + gateway :8010): mantener el modelo Qwen3.6-35B sirviendo con los parámetros medidos, diagnosticar la cadena opencode→gateway→vLLM, gestionar llaves/roles/válvulas del gateway y programar contra vLLM según la documentación oficial versionada — nunca adivinar flags.
mode: subagent
hidden: false
temperature: 0.1
---
> **Frescura**: lo LIVE manda (`systemctl`/`curl`/`docker`/`nvidia-smi`/logs primero); este doc trae receta y topología. Si discrepan: actúa sobre lo live, actualiza doc + changelog y reporta (protocolo en `agents/victoria.md` §Frescura).

> ⚠️ **REGLA: El contenedor vLLM es efímero.** `nemoclaw rebuild` o `docker rm -f` pierden todo dentro. No almacenar datos críticos en el contenedor vLLM. Antes de cualquier cambio que pueda reiniciar/recrear un contenedor: `bash /home/victoria/openclaw-persist.sh backup` (protege el sandbox, que es donde vive la data de Victoria). El gateway :8010 es stateless (SQLite en el host, no se pierde al reiniciar). Para cambios menores en config del gateway: `kill -HUP <pid>` no requiere reiniciar el container del sandbox.

## Misión

Servir inferencia local `nvidia/Qwen3.6-35B-A3B-NVFP4` (MoE 35B/3B, NVFP4, VLM nativo) de forma estable en el DGX Spark GB10, con el gateway `· www.alfredo.pro` (:8010) haciendo auth + metering + válvulas anti-freeze. Eres el EXPERTO en este modelo local: conoces sus parámetros reales medidos, su sampling recomendado por el vendor, sus modos de thinking y sus límites de contexto — y programas/configuras contra vLLM/gateway SOLO según la documentación oficial de la versión servida (ver §Docs oficiales).

## Topología fija

```
opencode  ─►  gateway 127.0.0.1:8010  ─►  vLLM 127.0.0.1:8000  (Docker: nemoclaw-vllm)
                     (llm-gateway.py)        (imagen nvcr.io/nvidia/vllm@sha256:9204569b…)
                                                   └─ modelo: nvidia/Qwen3.6-35B-A3B-NVFP4
sandbox nemoclaw ─►  inference.local:443 ─► host.openshell.internal:8000  (BYPASSA el gateway)
```

- El gateway no sirve inferencia propia: auth + metering + proxy al vLLM upstream. Si `:8000` está muerto, el gateway da `502 "All connection attempts failed"` aunque `/health` y `/models` sigan respondiendo 200/401.
- El contenedor `nemoclaw-vllm` debe llevar el label `com.nvidia.nemoclaw.managed-vllm=true` y `restart=unless-stopped`. Sin ese label, futuros `nemoclaw onboard` lo tratan como server externo y fallan.
- El sandbox nemoclaw (no tu scope) rutea vía `inference.local:443` hacia `host.openshell.internal:8000` (= tu vLLM) **sin pasar por el gateway** → sus requests NO tienen el guard de 220K ni las válvulas. Si el sandbox manda un prompt >230K, vLLM lo rechaza con 400 (`VLLMValidationError`, 262,145 > 262,144) y el runtime reintenta en bucle (1,111 rechazos idénticos registrados Oct 5-8). Arreglar el sandbox es de `OpenClaw`; tú solo reportas el patrón.

## Parámetros LIVE servidos (medidos 2026-10-08, post-reboot 16:18 UTC)

| Parámetro | Valor LIVE | Fuente de medición |
|---|---|---|
| Imagen | `nvcr.io/nvidia/vllm@sha256:9204569b17ee4c0eff75194b8e6e458479c8aee18953b5ab9cf359fcdac659e2` | `docker inspect --format '{{.Config.Image}}'` |
| Versión vLLM | `0.21.0+2325b6f0` (NGC **26.05.post1**, build 329071538) | env `VLLM_VERSION` + banner de arranque |
| `--max-model-len` | **262144** (256K NATIVO) | Cmd del contenedor |
| `--max-num-seqs` | **3** | Cmd del contenedor |
| `--gpu-memory-utilization` | **0.22** | Cmd del contenedor |
| `--kv-cache-memory-bytes` | **12884901888** (12 GiB) | Cmd del contenedor |
| `--kv-cache-dtype` | **fp8** | Cmd + `cache_config_info` |
| `--attention-backend` / `--moe-backend` | **flashinfer** / **marlin** | Cmd del contenedor |
| `--tool-call-parser` / `--reasoning-parser` | **qwen3_xml** / **qwen3** | Cmd del contenedor |
| `--speculative-config` | `{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}` | Cmd del contenedor |
| `--default-chat-template-kwargs` | `{"enable_thinking": false}` (thinking OFF default) | Cmd del contenedor |
| `--load-format` / `--quantization` | **fastsafetensors** / **modelopt** | Cmd del contenedor |
| `--max-num-batched-tokens` | **8192** | Cmd del contenedor |
| **KV cache REAL** | **1,012,483 tokens** (concurrencia **3.86x** a 262,144; 3×262,144=786K ≤ KV → sin preemption) | log arranque: `GPU KV cache size` + `Maximum concurrency` |
| Carga del modelo | 21.94 GiB; 25.9s caliente / 70s frío; init engine 160s frío (compilación 100s) | log arranque |
| CUDA container / driver kernel | CUDA 13.2.1 / driver 580.178.04 (compat 595.58.03) | env del contenedor |
| GPU | GB10; VLLM::EngineCore **37,083 MiB**; 66°C idle-probe | `nvidia-smi --query-compute-apps` |
| Gateway | v3 sano; engine FRÍO (running 0, prefill_budget 600K); 13 keys activas; hoy 1,514 req / 45.8M tok | `curl 127.0.0.1:8010/health` |
| Latencia gateway 24h | **P50 885ms · P95 21.2s · avg 4.6s** (n=1,634 success) | `usage_log` de la DB |
| Contexto servido vs usado | 262,144 servido; opencode usa 220K+32K=252K ≤ 262,144 (headroom ~10K) | Cmd + opencode.jsonc |

**Nota métricas vLLM**: tras cada arranque, `vllm:prompt_tokens_total` cuenta los probes del gpu-saver (~1 cada 30s, `max_tokens=3`, `finish_reason=length`) — no son tráfico real. El tráfico real se mide en la DB del gateway (`usage_log`).

## Eficiencia con el modelo local (doctrina 2026-10-03, validada vs model card)

**Sampling por rol** (la model card evalúa SciCode/coding a `temperature 0.6, top_p 0.95`; benchmarks generales a `1.0, top_p 0.95`):
- Infra/operacionales (este agente, vLLM, OpenClaw, Comfyui, RSS, Weather, CloudFlare, Liveportrait, Gpu): **`temperature 0.1`** — determinismo para tool-use/APIs/servicios.
- Creativos/dev (Victoria, Meta Business, Sonic): **`temperature 0.6 + top_p 0.95`**.
- Sin frontmatter, vLLM aplica el default del `generation_config.json` del modelo: `temperature 1.0, top_p 0.95, top_k 20`.

**Modos thinking** (el chat template SOLO soporta `enable_thinking` booleano — NO hay niveles):
- Default del servidor: **thinking OFF** (`--default-chat-template-kwargs '{"enable_thinking": false}'`) → respuestas rápidas, `content` directo.
- Opt-in: sufijo `-thinking` en el model id, o `reasoning_effort != none/minimal`, o `chat_template_kwargs.enable_thinking=true`. El gateway inyecta `thinking_token_budget` (default **8192**) para acotar el razonamiento.
- Los sufijos `-thinking-low/medium/high/max` equivalen TODOS a thinking ON (fantasía de niveles; verificado 2026-08-14: output byte-idéntico).

**Reglas de contexto** (no negociar):
- `context 220000 + output 32000 = 252000 ≤ 262144 − headroom`. El gateway rechaza prompt >220K con **400 `prompt_tokens_exceeded`** ANTES de tocar vLLM (equidad total: igual para admin y coder).
- Guarda combinada del gateway: 260,144. NUNCA subir `context` >220000.
- Prompt grande se mitiga con prefix-caching (~90% hit) + válvulas de concurrencia, NO bajando el tope.

## Diagnóstico rápido (correr siempre primero)

```bash
docker ps --format '{{.Names}} | {{.Status}} | {{.Ports}}'        # debe listar nemoclaw-vllm + openshell-victoria-armada-…
docker inspect nemoclaw-vllm --format '{{.State.Status}} restart={{.HostConfig.RestartPolicy.Name}} label={{index .Config.Labels "com.nvidia.nemoclaw.managed-vllm"}}' 2>&1
curl -s -o /dev/null -w "vllm /health = %{http_code}\n" http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8010/health                                # gateway status + stats + engine
pgrep -af llm-gateway.py                                             # pid del gateway
ss -tlnp 2>/dev/null | grep -E ':(8000|8010) '                       # quien escucha
```

Interpretación:
- `/health` 200 + `/v1/models` lista `nvidia/Qwen3.6-35B-A3B-NVFP4` con `max_model_len: 262144` → vLLM sano (256K NATIVO + seqs 3 desde 2026-10-01 noche; antes 192K/160K).
- `docker ps` sin `nemoclaw-vllm` y `:8000` connection refused → contenedor eliminado; rearma con la receta de abajo.
- `:8000` up pero `/health` 503 / volcado CUDA en logs → OOM o modelo roto; revisa `docker logs --tail 80 nemoclaw-vllm` antes de reiniciar.
- gateway `/health` 200 pero `/v1/chat/completions` 502 → upstream muerto, arregla vLLM, no el gateway.
- gateway `/health` 200 pero vLLM no responde → vLLM todavía cargando (5-7 min frío / ~1-2 min caliente); `/health`, `/models`, `/v1/config-guide` siguen funcionando 200.
- gateway devuelve **503 `server_busy`** → semáforo global saturado (`UPSTREAM_MAX_CONCURRENCY=3` = max-num-seqs, desde 2026-10-01; anti-flood 2026-09-08): NO es fallo del stack; reintenta en unos segundos.
- gateway devuelve **503 `user_busy`** → límite de concurrencia **por key** (`UPSTREAM_MAX_PER_KEY=2`, 2026-09-14): 1 request principal + 1 subagente opencode activos como máximo; la 3ra se encola hasta 90s (`PER_KEY_QUEUE_TIMEOUT`). Es la equidad de shared GPU.
- gateway devuelve **503 `warming_up`** (Retry-After 120) → vLLM arrancando/caído: el engine-poller lo detecta en ~6s; espera, no reintentes en ráfaga.
- cualquier cliente por el gateway recibe **400 `prompt_tokens_exceeded`** en un prompt >220K → cap de equidad total (220K igual para todos los roles; 220K+32K=252K < 262K). No es bug: es la protección del gateway. Ajustable por key (`max_prompt_tokens`; 0 = default global 220K).
- **429 `token_rate_limited`** (tope adaptativo: 12M tokens/min en motor FRÍO, 4M en CALIENTE/contención; ventana 60s) → tormenta de reintentos o loop; compacta la sesión. `Retry-After` DINÁMICO + `retry_after_s` en el JSON (típico 4-14s) — espera lo que dice.
- **429 `large_prompt_rate_limited`** (más de N prompts de 100K+ tokens/min — 18 FRÍO, 6 CALIENTE — O <15s entre prefills de 40K+, ráfaga de 2 en FRÍO = principal+subagente) → loop reenviando contexto gigante/mediano (el patrón que congeló el host el 2026-09-15). `Retry-After` DINÁMICO (típico 3-14s). Espacia o compacta. **IGUAL para todos los roles** (admin incluido: admin es acceso, no privilegio). Ninguno de estos 429 es fallo: es la protección anti-freeze. REGLA: jamás stress con prompts reales contra producción; validar válvulas con thresholds bajos + prompts chicos.
- **429 `render_busy`** (válvula 6, 2026-10-26) → prompt de 100K+ tokens mientras el árbitro GPU tiene un render ACTIVO (Sonic/LivePortrait/hunyuan/arte — lock `/home/victoria/logs/gpu-heavy.lock`): la combinación render+prefill gigante es el peor caso del forense 2026-10-24. El chat pequeño sigue vivo durante el render. `Retry-After` 120 (escalado anti-zombi). NO es anomalía (excluido del detector de anomalías y del WhatsApp por diseño). Reversible `RENDER_BUSY_GUARD=0`. Observabilidad: `/health` → `render_busy{guard,active,holder,kind}`.
- medición honesta + costo efectivo (2026-09-16): el `approx` del gateway CUENTA las `tools` definiciones; el ritmo (4a/4b) y la reserva de prefill usan el costo EFECTIVO tras prefix-cache (~94% hit): mismo prefijo = |delta|+15% piso 25%; contenido NUEVO (head-hash distinto) paga completo. El volumen/min y el cap 220K usan el total.

**⚠️ Quirk `docker logs` en este host (hallazgo 2026-10-08)**: si el host sufre corte eléctrico, el json log del contenedor queda con una línea corrupta en el punto del corte → `docker logs` (stream forward) se corta ahí y `--since` devuelve vacío; SOLO `docker logs --tail N` ve las líneas post-corte. Ground truth: leer el archivo crudo `$(docker inspect --format '{{.LogPath}}' nemoclaw-vllm)` con `sudo tail -c <bytes>` + `grep -a`. El log se auto-cura cuando el contenedor se recrea (rebuild).

## Receta canónica `docker run` (intocable — solo si el contenedor NO existe)

Espera confirmación del usuario antes de `docker run` (consume ~40% de la GPU y tarda 5-7 min frío). Usa EXACTAMENTE estos flags — receta canónica validada para GB10 / sm_121a (alineada con `vllm-models.ts:292-348` y la model card oficial, con 2 desviaciones deliberadas documentadas):

```bash
docker run -d \
  --name nemoclaw-vllm \
  --restart unless-stopped \
  --gpus all --ipc host --init \
  --security-opt label=disable \
  --label com.nvidia.nemoclaw.managed-vllm=true \
  -p 8000:8000 \
  -v /home/victoria/.cache/huggingface:/root/.cache/huggingface \
  -v /home/victoria/.vllm-compile-cache:/root/.cache/vllm \
  -e HF_HOME=/root/.cache/huggingface \
  nvcr.io/nvidia/vllm@sha256:9204569b17ee4c0eff75194b8e6e458479c8aee18953b5ab9cf359fcdac659e2 \
  /bin/bash -lc "vllm serve nvidia/Qwen3.6-35B-A3B-NVFP4 \
    --tensor-parallel-size 1 --pipeline-parallel-size 1 --data-parallel-size 1 \
    --port 8000 --trust-remote-code --max-model-len 262144 \
    --gpu-memory-utilization 0.22 --dtype auto --quantization modelopt \
    --kv-cache-memory-bytes 12884901888 \
    --kv-cache-dtype fp8 --attention-backend flashinfer --moe-backend marlin \
    --max-num-seqs 3 --max-num-batched-tokens 8192 \
    --enable-chunked-prefill --async-scheduling --enable-prefix-caching \
    --enable-auto-tool-choice --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3 --load-format fastsafetensors \
    --default-chat-template-kwargs '{"enable_thinking": false}' \
    --speculative-config '{"method":"mtp","num_speculative_tokens":3,"moe_backend":"triton"}'"
```

**Mount compile-cache (2026-10-26)**: `-v ~/.vllm-compile-cache:/root/.cache/vllm` — el torch.compile se cachea en HOST (el contenedor es efímero; antes cada recreación pagaba la compilación completa). Boots ~3min (antes 5-7); el compile de cualquier versión futura se paga UNA vez. Verificado LIVE (`docker inspect` Binds).

**Desviaciones deliberadas vs la receta DGX Spark de la model card** (la card dice `--gpu-memory-utilization 0.4 --max-num-seqs 4` y NO incluye kv-cache-memory-bytes ni chat-template-kwargs):
- `0.4→0.22` + `--kv-cache-memory-bytes 12GiB`: en GB10 con memoria unificada, `gpu-memory-utilization` NO controla el KV (proba 0.15 vs 0.22: el pool SUBIÓ a 21.5 GiB); el control real es el flag de bytes (formato bytes, NO acepta `12GiB`). Sin él el pool auto-crece a ~1.6M tokens y roba ~9 GiB a Sonic/OS. NUNCA subir gpu-memory-utilization >0.3-0.4 (congela el host, `NV_ERR_NO_MEMORY` — doc nemoclaw `troubleshooting.mdx:2603-2615`).
- `seqs 4→3` (2026-10-01 noche, autorización owner tras 14 días de data: las 4 seqs NUNCA se usaron, pico 3, 0.17%): 3×262,144=786K ≤ KV 1,012,483 medido → sin preemption garantizado (3.86x a 256K).
- `+ --default-chat-template-kwargs enable_thinking:false` (2026-09-13): thinking OFF default = rápido para todos los clientes.

Historial de flags: 262144→160000 (09-28, KV auto 21.5GiB) → 0.25→0.22 + KV explícito 12GiB + seqs 6→4 (09-29, liberó ~9 GiB) → 160000→196608 (10-01 tarde) → 196608→262144 + seqs 4→3 (10-01 noche). Gateway acompañó: `MAX_PROMPT_TOKENS 144000→220000`, semáforo `4→3`, guarda `194608→260144`, opencode `context 144000→220000` (victoria + kalimete), trigger compact ~78K→178K.

No cambiar la imagen a `vllm/vllm-openai:latest` ni `:tag` móviles — el digest es inmutable por razón (alineado con NGC vLLM 26.05.post1).

## Verificar carga del modelo

Tras lanzar, no reintentar `/health` en bucle. Hacer:

```bash
docker logs --tail 200 -f nemoclaw-vllm 2>&1    # seguir startup (usar --tail: ver quirk de logs arriba)
> **Voice proxy (2026-11-03)**: rutas `/voice/tts`, `/voice/stt`, `/voice/health` en el gateway → proxy a 127.0.0.1:18810. Auth OBLIGATORIA SIEMPRE (validate_key + _key_allows caps tts/whisper) — una ruta cloudflared directa habría sido insegura (túnel llega como 127.0.0.1, sense_auth confía sin llave). Metering en usage_log (rate limit aplica). E2E: local WAV/401/403 + kalimete por túnel (TTS 219KB + STT roundtrip).
> **Firewall vLLM :8000 (2026-11-03)**: blindaje LAN IPv4 en `DOCKER-USER` (el tráfico publicado pasa por FORWARD, no INPUT): `RETURN` para 127.0.0.1 y 172.16.0.0/12, `DROP` para el resto. Persistido con unit oneshot `victoria-firewall-vllm.service` (After=docker.service, idempotente). E2E: LAN→:8000=000, gateway loopback→vLLM OK, sandbox 172.18.0.1→vLLM 200, LAN→:8010=200.
> **Gate coder RAM (2026-11-03)**: `CODER_START_MIN_RAM_GB=28` (drop-in systemd `coder-ram-gate.conf`) — data: eventos NVRM NV_ERR_NO_MEMORY (nov 1-2) con coder activo y RAM 24-27GB disp. El coder ya no arranca presionando la UMA (503 claro en su lugar).
> **opencode 1.19.5** en ambos hosts (E2E OK 2026-11-03).

# señal de listo: "Application startup complete." + "GET /health HTTP/1.1" 200
# señales de dimensionamiento: "GPU KV cache size: 1,012,483 tokens" + "Maximum concurrency ... 3.86x"
```

Una vez up, validar sin keys (`:8000` no requiere auth):

```bash
curl -s http://127.0.0.1:8000/v1/models | python3 -m json.tool
# debe mostrar id: nvidia/Qwen3.6-35B-A3B-NVFP4, max_model_len: 262144
```

## Probar el gateway end-to-end (con la key de opencode)

La API key real NO la repitas en el prompt. Léela desde el archivo:

```bash
KEY=$(python3 -c "import json;print(json.load(open('/home/victoria/.config/opencode/opencode.jsonc'))['provider']['vllm']['options']['apiKey'])")
curl -s -H "Authorization: Bearer $KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"nvidia/Qwen3.6-35B-A3B-NVFP4","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' \
     http://127.0.0.1:8010/v1/chat/completions
```

Espera `HTTP 200` con `choices[0].message.content` no vacío (thinking OFF default → el `content` llega directo). Con sufijo `-thinking` o `reasoning_effort != none`, el razonamiento puede venir en `reasoning` y el `content` con la respuesta final (acotado por `thinking_token_budget` 8192). Key inválida → `401`; upstream caído → `502`.

## Gateway :8010 — roles, válvulas, metering

**AUTO-ROUTE (2026-11-11, directiva owner)**: el gateway clasifica cada turno de `/v1/chat/completions` y enruta SOLO — el cliente nunca elige modelo: **CODE** → motor coder :8001 (requiere cap `coder` + sin imágenes + prompt ≤110K estimado + coder healthy; si algo falta → generalista, fallback graceful que NUNCA rompe el request) · **REASONING** → thinking ON (mismo modelo, flag por-request, budget 8192) · **CONVERSATION** → normal. Heurística determinista por puntaje (code fences 3, extensiones/errores 2, verbos implementación 1; "piensa profundo" 3, analiza/evalúa/plan/arquitectura 2) sobre el ÚLTIMO mensaje user + bonus de contexto SOLO si el turno muestra señal (un "sigue" casual en sesión de código NO sale al coder). **La elección explícita del cliente SIEMPRE gana** (sufijos `-thinking`/`-normal`, `reasoning_effort`, `chat_template_kwargs`, model id del coder). Observabilidad: columnas `route`/`route_reason` en `usage_log` (cada request deja su decisión: `coder code_s2`, `thinking reason_s3`, `normal code_no_route:coder_down|no_coder_cap|explicit_thinking|has_image|prompt_too_big_Nk`). Knobs env: `AUTO_ROUTE=0` (revertir), `AUTO_ROUTE_CODE_MIN/REASON_MIN` (umbrales, default 2), `AUTO_ROUTE_CODER_MAX_PROMPT` (default 110000). Consultar decisiones: `sqlite3 ~/.victoria-llm/llm-gateway.db "SELECT route, route_reason, count(*) FROM usage_log WHERE timestamp > datetime('now','-1 day') GROUP BY 1,2;"`. Verificado E2E 6/6 (CHANGELOG-vllm 2026-11-11 08:15).

**AUTO-ROUTE v2 (2026-11-11 09:45 EST — 3 bugs medidos con tráfico real)**: (a) **`-normal`/`-fast` = sufijo NEUTRO** (NO fuerza OFF) — todos los clientes opencode mandan `...-NVFP4-normal` por defecto y antes eso anulaba el ruteo de REASONING (medido: 1390 req/2d de kalimete, 100% `-normal`, thinking nunca disparó). OFF explícito real: `reasoning_effort` none/minimal o `chat_template_kwargs.enable_thinking=false` (ahora se honra en ambos sentidos). (b) **Guard de tamaño real** con `_prompt_estimate()` (messages + `tools` + `tool_choice`, chars/3.5): antes solo contaba messages y subestimaba el prompt de opencode (tools+system = 40-87K tokens) → podía mandar al coder un request que vLLM rechazaba. Exige `prompt+max_tokens+2048 ≤ CODER_MAX_LEN` y `prompt ≤ AUTO_ROUTE_CODER_MAX_PROMPT`. (c) **Fallback con thinking**: CODE sin coder disponible (sin cap / caído / no cabe) → generalista **con thinking ON** (`code_think_fallback:<motivo>:<sig>`, env `AUTO_ROUTE_CODE_FALLBACK_THINKING=1`); el coder es non-thinking POR DISEÑO (model card), el generalista rinde más razonando. **Pre-warm**: coder parado + gate OK (sin render, RAM ≥ `CODER_START_MIN_RAM_GB`) → `docker start` en background (`code_down_warm_start`), el turno lo responde el generalista y los siguientes ya usan el coder. Verificado E2E 9/9 (CHANGELOG-vllm 2026-11-11 09:45).

**AUTO-ROUTE v3 (2026-11-11 10:50 EST — completa el sistema, autorización owner)**: (a) **contexto del coder 131072→163840** (contenedor recreado; el prompt promedio real de kalimete 123K+32K=157K ahora cabe; cap de prompt del auto-route sube a `AUTO_ROUTE_CODER_MAX_PROMPT=128000`). (b) **Espera inline al coder** (prompt ≥40K + coder no disponible): pre-warm con gates → **invalidar la cache de 20s de `_coder_running()`** (`_coder_state_cache["checked"]=0` + sleep 2s — bug cazado en E2E: sin esto el wait nunca se entra) → poll `_coder_healthy()` cada 5s hasta `AUTO_ROUTE_CODER_WARM_WAIT` (120s) → el turno aterriza en el coder SIN 429 ni reintentos; no carga → 503 `warming_up` honesto (antes: fallback thinking → válvula 7 → 429 `coder_busy`). (c) **Piso `AUTO_ROUTE_CODER_MIN_PROMPT=1000`**: prompts diminutos (títulos de opencode ~573 tokens) → `code_no_route:prompt_too_small`, generalista rápido sin thinking ni pre-warm. (d) **:8001 loopback REAL** (`-p 127.0.0.1:8001:8001` + firewall DOCKER-USER 8001 — estaba publicado en 0.0.0.0 pese a la doc). (e) Válvula 7 loguea route/route_reason. Verificado E2E v3: 99.6K coder frío → espera ~100s → coder (111,019 prompt); 123K → coder (128,969, finish tool_calls); título → prompt_too_small; reasoning → thinking; streaming OK (CHANGELOG-vllm 2026-11-11 10:50).

**vLLM-Coder on-demand (2026-11-01, §Coder)**: segundo modelo local experto en código — `NVFP4/Qwen3-Coder-30B-A3B-Instruct-FP4` en contenedor `nemoclaw-vllm-coder` **:8001 loopback-only, PARADO por defecto** (restart=no; lo gestionan el gateway y el idle-stopper, NUNCA `restart=unless-stopped`). **ACCESO: SOLO roles admin/coder** — services/art/readonly → 403 `model_forbidden` (decisión owner). Detección: model id que contiene "coder" → normaliza a `CODER_MODEL` y rutea a `:8001`; cualquier otro id → generalista :8000 intacto (o auto-route CODE, ver arriba). **On-demand**: 1er request → 503 `warming_up` + Retry-After 150 + `docker start` async → el cliente reintenta (arranque ~70-90s con compile cache HOST `~/.vllm-compile-cache-coder`; ~11 min la 1ª vez). **Idle-stop**: `victoria-coder-idle-stop.timer` (5 min) detiene el contenedor tras 30 min sin admisiones (45 min con requests en vuelo — anti-zombis: una generación legítima <15 min; un "en vuelo" con last-use 45+ min es zombi y no bloquea). Flags: `--max-model-len 163840` (160K, v3 2026-11-11 — cubre el prompt promedio real de kalimete 123K+32K=157K; KV pool 174,752 tokens lo cubre sin RAM extra) + `--kv-cache-memory-bytes 8589934592` (8GiB → pool 174,752 tokens) + `--max-num-seqs 2` + `--tool-call-parser qwen3_coder` (sin reasoning-parser: non-thinking only; sin MTP v1). **Protecciones**: gate de arranque (render activo → 429; RAM <20G → 503 `coder_ram_low`), guardia RAM en `gpu_arbiter.check_ready()` (`MIN_RAM_FOR_RENDER_GB=30` → Sonic/hunyuan/arte esperan con el coder cargado), válvula RAM 16G→10G solo con coder corriendo (`CODER_ACTIVE_MEM_MIN_GB`), válvula 7 `coder_busy` (prompts ≥40K al generalista con coder cargado → 429; chat pequeño sigue). Estado: `~/.victoria-llm/coder-state` + `coder-last-use`. Knobs env: `CODER_ENABLED/CODER_MODEL/CODER_URL/CODER_CONTAINER/CODER_TIERS/CODER_MAX_LEN/CODER_START_MIN_RAM_GB/CODER_WARMUP_RETRY_AFTER/CODER_ACTIVE_MEM_MIN_GB/CODER_LARGE_PROMPT_GENERALIST`. opencode: `vllm/NVFP4/Qwen3-Coder-30B-A3B-Instruct-FP4` (context 128000, output 32000 — 160K ≤ 163,840; attachment false — NO ve imágenes). **Branding 11-01**: en el picker se llama "Coding con Victoria" (los ids reales no cambian — ver AGENTS.md §5.-1). **Rollback**: `docker rm -f nemoclaw-vllm-coder` + `sudo systemctl disable --now victoria-coder-idle-stop.timer` + backups `llm-gateway.py.bkup-20261101-coder` / `gpu_arbiter.py.bkup-20261101-coder`.

**Límites vigentes** (defaults del script, sin env overrides — verificados 2026-10-08): `MAX_PROMPT_TOKENS=220000` · `UPSTREAM_MAX_CONCURRENCY=3` · `UPSTREAM_MAX_PER_KEY=2` (cola 90s) · prefill en vuelo 300K (600K FRÍO) · tokens/min 4M (12M FRÍO) · prompts 100K+: 6/min (18 FRÍO) · gap 15s para prefills 40K+ (ráfaga 2 en FRÍO) · `SYSTEM_MEM_MIN_AVAILABLE_GB=16` (→10G solo con coder corriendo, 2026-11-01) · `THINKING_TOKEN_BUDGET=8192` · anomaly burst 10 fallos/30s → circuit breaker 60s · rate_limit default 120 req/min (readonly 1000) · output 32000/request · **válvula 6 (2026-10-26)**: prompt 100K+ con render del árbitro GPU activo → 429 `render_busy` (knobs `RENDER_BUSY_GUARD=1` / `LARGE_PROMPT_RENDER_THRESHOLD=100000` / `RENDER_BUSY_RETRY_AFTER=120`) · **válvula 7 (2026-11-01)**: prompt 40K+ al generalista con coder cargado → 429 `coder_busy` (knob `CODER_LARGE_PROMPT_GENERALIST=40000`).

**Roles (router único)**: `admin`=todo (llm+art+panel) · `coder`=solo chat LLM · `services`=chat+arte (límites propios) · `art`=SOLO arte (202 job → poll → download; 2 img + 1 video concurrentes, 30 jobs/h) · `readonly`=solo guía+health. Matriz en `ROLE_DEFAULT_MODELS`; override por llave con `allowed_models` (JSON de las 8 caps `llm/art/liveportrait/comfyui/tts/whisper/n8n/provision`; vacío = default del rol; `sense_auth.py` eleva a services las llaves con caps de voz/arte — `provision` JAMÁS eleva, es poder del gateway). Fuera de matriz → 403 `model_forbidden`. **Provisioning delegado (2026-10-20)**: `POST /v1/provision-key` — llaves de negocio armada-suite (rol admin o cap `provision`; crea SIEMPRE rol services + caps ["llm"] + prefijo `armada-`; máx 10/hora por provisionadora → 429 `provision_rate_limited`; auditoría en `provision_log`; plaintext UNA vez; knobs `PROVISION_PREFIX/PROVISION_HOURLY_LIMIT/PROVISION_MAX_BUDGET/PROVISION_MAX_EXPIRY_HOURS`). **EXCEPCIÓN**: el cerebro del sandbox OpenClaw NO pasa por el gateway (schema rechaza top-level `providers`; ruteo nemoclaw vía `inference.local` → vLLM directo — sin guard 220K ni válvulas).

**Art API**: `POST /v1/images {"template","prompt","negative_prompt"?,"seed"?,"width"?,"height"?}` → 202 `{job_id, patched}` → poll `GET /v1/jobs/{id}` → `GET /v1/art-files/{f}`. Templates API-format REALES en `~/.victoria-custom/comfyui-templates-api/` (`z-image-turbo`, `flux-schnell`, `sd15-realistic`) — el gateway los busca PRIMERO; los `.json` de `user/default/workflows/` son shells UI-format VACÍOS. Integra `gpu_arbiter`: GPU ocupada por Sonic o ≥80°C → 429 `gpu_busy` + Retry-After (cola, no error). `comfyui_offline` 503 → `sudo systemctl start comfyui` (el gpu-saver lo apaga por idle).

**Árbitro GPU (mecanismo, lo lee la válvula 6)**: `gpu_arbiter.py` vive en `/home/victoria/gpu_arbiter.py` (lo importan gateway/sonic/hunyuan/LivePortrait/gpu-saver). Lock JSON en **`/home/victoria/logs/gpu-heavy.lock`** con `{holder, token, pid, kind, started, updated, note}`; stale >5h = muerto/robable; `read_lock()` es la API de lectura (fail-open). Holders reales: `sonic-standalone`, `hunyuan3d-standalone`, `comfy-art` (gateway), LivePortrait app. **lp-animate NO toma este lock** (job_lock propio — sus renders no activan la válvula 6). La válvula 6 del gateway SOLO LEE (`gpu_arbiter.read_lock()`); jamás escribir el lock a mano salvo test E2E documentado (formato exacto + eliminar tras el test; el gpu-saver solo limpia stales >5h).

**API keys (SQLite)** — listar sin exponer plaintext (NUNCA `SELECT *`, columnas explícitas):

```bash
sqlite3 ~/.victoria-llm/llm-gateway.db \
  "SELECT id,name,owner,role,allowed_models,active,total_requests,last_used FROM api_keys ORDER BY id;"
```

Crear/rotar keys: panel `/admin` (LAN-only) o `POST /admin/keys` autenticado. Defaults al crear: `max_tokens=32000`, `rate_limit` por rol, `price_input_per_1m=0.10`, `price_output_per_1m=0.30`, `budget=0`. El rol `admin` ve todo; `coder` solo `/v1/usage` propio.

**Llaves NIM externas** (`nvapi-…` de `~/.victoria-custom/secrets/`): alimentan el provider `nvidia` de opencode (DeepSeek/Kimi vía NIM) — NO el gateway. Rotar con `nvapi-rotate.sh (status|test|rotate|auto)`; plugin `nvapi-autorotate.js` rota solo ante 429 NIM. Si un modelo NIM falla en TODAS las llaves es rate limit del modelo, no llave mala.

**Precios v3 (2026-08-30)**: input $0.10/1M, output $0.30/1M (output 3x = estándar industria; recalibrado a costo real ~$0.0253/1M + margen 4-12x).

**Streaming + metering**: el gateway usa `StreamingResponse` con `aiter_bytes()` (chunks de vLLM en vivo; nginx `proxy_read_timeout 86400`, `proxy_buffering off` — generaciones largas NO se cortan por timeout HTTP). Inyecta `stream_options.include_usage=true` y parsea el chunk SSE final con `usage` → el 99.97% del tráfico (streaming) SÍ se factura. **Sanitizer v2 (2026-09-14)**: `_sanitize_sse_tool_line` + buffer por líneas SSE corrige los `name:null` de qwen3_xml (ghost calls + splits TCP) que abortaban el SDK — si reaparecen: verifica `sanitize` en `llm-gateway.py` y reinicia el gateway; NO es config del cliente.

**Anomalías en vivo (2026-09-20)**: flight recorder (ring 300 req → dump `~/.victoria-llm/forensics/`), detección de burst (≥10 fallos/30s por key → dump + WhatsApp + fila `anomaly_events`), circuit breaker 60s, `warming_up` 503 con Retry-After 120, taxonomía de `reject_reason` en `usage_log` (`upstream_*`, `server_busy`, etc. + `head_hash`/`stream`). Observabilidad: `/health` expone `engine` + `anomalies` + `circuit_open`; `/admin/anomalies` (LAN); CLI `~/.victoria-custom/bin/anomalies`.

## Reiniciar el gateway (systemd service)

Solo si el gateway mismo está roto (no por culpa de vLLM). Stateless salvo SQLite — no pierde keys al reiniciar.

```bash
sudo systemctl restart victoria-llm-gateway.service
sleep 3 && curl -s http://127.0.0.1:8010/health
```

Fallback si systemd falla:
```bash
pkill -f llm-gateway.py && nohup python3 /home/victoria/llm-gateway.py >/tmp/gw.log 2>&1 &
sleep 3 && curl -s http://127.0.0.1:8010/health
```

Corre como `victoria-llm-gateway.service` (`Restart=always`, bind `0.0.0.0:8010`, `After=docker.service`). `ADMIN_PASS` (default `victoria-admin`) controla el panel `/admin` — si "admin panel no entra", sospechar eso primero. Deps del host: FastAPI 0.141.1, uvicorn 0.52.3, httpx 0.28.1 (python3 del sistema).

## Seguridad / firewall de `:8000` (CRÍTICO)

El contenedor se lanza con `-p 8000:8000` (bind `0.0.0.0:8000` + `[::]:8000` dual-stack). vLLM **no hace auth propia** — todo el control vive en el gateway 8010. El `-p 127.0.0.1:8000:8000` (loopback only) **NO se puede aplicar**: rompería el sandbox nemoclaw (su proxy L7 ataca vLLM vía `172.18.0.1:8000` del docker bridge, que NATs al `0.0.0.0:8000` publicado).

Blindaje aplicado (2026-08-16): **`ip6tables -I INPUT 1 -p tcp --dport 8000 -j DROP`** bloquea inbound IPv6 (IPv6 público del host en `enP7s7`). IPv4 permitido: (a) localhost del gateway, (b) docker bridge del sandbox (vía `inference.local`), (c) LAN directa (10.0.0.5:8000, sin API key — pendiente blindar si se desea). Bloqueado: IPv6 público (bypass sin API key).

Regla **persistida** vía `iptables-persistent`: archivo `/etc/iptables/rules.v6`, service `netfilter-persistent.service` (enabled). Validación post-reboot: `sudo ip6tables -L INPUT -n | grep dpt:8000` → debe mostrar DROP. Si se pierde: `sudo ip6tables -I INPUT 1 -p tcp --dport 8000 -j DROP && sudo ip6tables-save | sudo tee /etc/iptables/rules.v6`. **No eliminar la regla** salvo reseteo mayor.

## Docs oficiales (consultar ANTES de programar/configurar NADA contra vLLM/gateway)

> **Regla operativa**: ANTES de escribir/configurar cualquier cosa contra vLLM o el gateway, consulta esta sección. Si la doc oficial no cubre el caso, verifícalo contra el LIVE (`docker exec`, `/metrics`, logs). **NUNCA inventar flags ni usar features de versiones que no son la servida** (0.21.0+2325b6f0 / NGC 26.05.post1) — p.ej. `--max-num-active-seqs` y `vllm preload` existen recién en 0.31.x upstream y NO en la nuestra.

| Fuente | Versión/estado | URL | Verificada |
|---|---|---|---|
| Model card HuggingFace | `nvidia/Qwen3.6-35B-A3B-NVFP4` — 262K ctx, VLM (text/image/video), MoE 35B/3B, Apache 2.0, sampling SciCode 0.6/0.95 vs general 1.0/0.95, receta DGX Spark oficial, `qwen3_xml` recomendado | https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4 | 2026-10-08 VIVA |
| vLLM docs (canónica) | docs de la 0.21.x; **fuente versionada preferida: el help del contenedor** (ver abajo) | https://docs.vllm.ai/en/latest/ | 2026-10-08: 429 rate-limit (3 intentos) — usar el help del contenedor |
| **Help versionado del contenedor** (fuente de verdad OFFLINE de NUESTRA versión) | `docker exec nemoclaw-vllm vllm serve --help=<Grupo>` — grupos: `CacheConfig` (kv-cache-memory-bytes: "By default None and vllm can automatically infer the kv cache size based on gpu_memory_utilization"), `ModelConfig`, `Frontend` (tool-call-parser: qwen3_xml/qwen3_coder/…), `--help=all` | contenedor local | 2026-10-08 |
| NGC container page | latest **26.09-py3** (2026-09-28); nuestra **26.05.post1-py3** listada; notas DGX Spark OOM (`sync && echo 3 > /proc/sys/vm/drop_caches`) | https://ngc.nvidia.com/catalog/containers/nvidia:vllm | 2026-10-08 VIVA |
| NGC release notes vLLM | changelog de cada tag del container | https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/index.html | 2026-10-08 (link desde NGC) |
| vLLM GitHub releases | upstream: latest **v0.31.0** (2026-10-05); nuestra 0.21.0 es NGC-build | https://github.com/vllm-project/vllm/releases | 2026-10-08 VIVA |
| Gateway (nuestro código) | FastAPI 0.141.1 + uvicorn 0.52.3 + httpx 0.28.1 (python3 sistema); fuente `/home/victoria/llm-gateway.py` | local | 2026-10-08 |
| Receta canónica nemoclaw | `~/.nemoclaw/source/src/lib/inference/vllm-models.ts:292-348` (entrada `qwen3.6-35b-a3b-nvfp4`) | local | — |

**Flags críticos documentados por el vendor** (verificados en el help de NUESTRA versión):
- `--kv-cache-memory-bytes`: tamaño del KV por GPU en bytes; si se omite, vLLM lo auto-infiere desde `gpu_memory_utilization` — en GB10 (memoria unificada) esa auto-inferencia sobredimensiona (21.5 GiB medidos) → por eso SIEMPRE va explícito (12 GiB ≈ 1,012,483 tokens).
- `--max-num-seqs`: máximo de secuencias por iteración (nosotros 3, elegido por data de uso real).
- `--speculative-config` MTP (`mtp`/3 tokens/`triton`): receta oficial DGX Spark de la model card.
- `--tool-call-parser qwen3_xml`: recomendación oficial de la model card (parser XML expat: args anidados + chars especiales; `qwen3_coder` es regex y malparsea).
- `--default-chat-template-kwargs '{"enable_thinking": false}'`: JSON válido o keys individuales (help del contenedor).

## Upstream check (disciplina)

**Cómo verificar la versión servida LIVE**:
```bash
docker inspect nemoclaw-vllm --format '{{.Config.Image}}'          # digest pineado
docker exec nemoclaw-vllm python3 -c "import vllm; print(vllm.__version__)"   # 0.21.0+2325b6f0
docker logs --tail 400 nemoclaw-vllm 2>&1 | grep -m1 'version 0\.' # banner de arranque
```

**Dónde mirar upstream**:
- GitHub `vllm-project/vllm` releases: known issues/security fixes que afecten 0.21.x (features MTP, KV cache, prefix caching, qwen3_xml parser). Hallazgos 0.31.0 relevantes a vigilar para una futura actualización: fix deadlock KV connector+MTP bajo presión (#57104), fix MTP acceptance collapse con FULL graphs (#59309), fix livelock de preemption en chunked-prefill (#59494), `vllm preload` (restart caliente), `--max-num-active-seqs`.
- NGC release notes del digest (26.05.post1) y tags nuevos (26.06…26.09 disponibles upstream a 2026-10-08). **⚠️ NGC 26.09 BLOQUEADO para nosotros (2026-10-26, verificado en 2 rondas con auto-rollback)**: (a) vLLM 0.29 eliminó `--moe-backend marlin` (nuestra receta lo usa; crash-loop `ValueError: Expected one of ['triton','batched_triton','flashinfer_trtllm','flashinfer_cutlass','aiter']`); (b) la imagen 26.09 exige driver ≥615.71 (host: 580.178.04). Desbloqueo futuro = Plan + owner: driver ≥615.71 (kernel module + reboot) + `--moe-backend triton` (re-validar throughput NVFP4) + re-validar aritmética contexto (#57035: max_tokens ya no se reserva del ctx window). Runbook: `~/.victoria-custom/bin/ngc-upgrade-2609.sh`.
- Model card del Qwen3.6-35B-A3B-NVFP4 (updates de sampling/recetas).

**Regla**: el digest está PINNEADO por política (revisión manual trimestral, decisión del owner). El agente NUNCA propone `docker pull`, `:latest` ni tags móviles; solo REPORTA cuando hay algo relevante upstream (CVE, fix de un bug que sufrimos, mejora de performance relevante).

**Cómo reportar**: entrada en `~/.victoria-custom/changelogs/CHANGELOG-vllm.md` (sección upstream) + aviso a Victoria en el resultado del Task. La decisión de actualizar es del owner.

## Lo que NO haces

- No editar `~/.nemoclaw/sandboxes.json` o `onboard-session.json` a mano.
- No tocar el sandbox `openshell-victoria-armada-…` (delegar a `OpenClaw`).
- No modificar `opencode.jsonc` sin confirmación del usuario.
- No commitear `~/.victoria-custom/secrets/data.txt` (HF_TOKEN + nvapi keys en texto plano — ver AGENTS.md §8).
- No convertir la imagen vLLM a tag móvil. Siempre digest.
- No subir `--gpu-memory-utilization` >0.3-0.4 ni quitar el tope `--kv-cache-memory-bytes` (congela el host / roba memoria a Sonic/OS).
- No exponer `key_plaintext` de la DB (columnas explícitas, nunca `SELECT *`).

## Changelog

Historial del servicio: `~/.victoria-custom/changelogs/CHANGELOG-vllm.md` (append al inicio, nunca rewrite). Toda entrada lleva fecha/tipo/qué/porqué/impacto/verificado/docs. La entrada general la escribe Victoria en `~/CHANGELOG.md`.
