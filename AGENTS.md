# AGENTS.md · Stack LLM local (· www.alfredo.pro)

> Documentacion operativa del stack que vive en este host (DGX Spark / GB10).
> Mantener actualizada cuando cambie cualquier componente. Fuente de verdad
> para los subagentes opencode definidos en `~/.config/opencode/agents/`.

## Acceso Remoto (warcold + remotos)

Este documento ES publico para lectura remota w/via SSH. Si accedes como `warcold` (`/bin/rbash`, grupo `vllm-readers`):

### SSH
- **Puerto**: 1666 (config en `/etc/ssh/sshd_config.d/port.conf` + socket systemd `ssh.socket`)
- **Protocolo**: sshd.service + ssh.socket (socket activation, `ssh.socket` escuchando `0.0.0.0:1666` + `[::]:1666`)
- **Auth**: password (por defecto `colador`) y/publickey (warcold tiene `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEITFSIVAFs789z9ga26oHYtKPdr9Y3Y6yFJFZwGpP/l warcold@kalimete.local`)
- **Usuarios permitidos**: warcold (rbash, grupo vllm-readers), victoria (sudo)
- **Root login**: without-password (sin password pero con key)

### Usuarios
- `warcold` (UID 1001, shell `/bin/rbash`, grupo `vllm-readers`) → acceso remoto readonly
- `victoria` (UID 1000, shell `/bin/bash`) → admin del sistema

**PUEDES leer**:
- `AGENTS.md` (este archivo — documentacion del stack)
- `agents/victoria.md`, `agents/vllm.md`, `agents/openclaw.md`
- `agents/comfyui.md`, `agents/rss-system.md`, `agents/weather.md`, `agents/sonic.md`, `agents/meta-business.md`, `agents/cloudflare.md`
- `CHANGELOG.md` (historial de cambios)
- Template publico: `.victoria-custom/remote/opencode-template.jsonc` + `.victoria-custom/remote/README.md`
- Prompt remoto: `Desktop/install-vllm-prompt.md` (modelos de inferencia) + `Desktop/install-voice-prompt.md` (servicio de voz)

**NO PUEDES leer**:
- `.config/opencode/opencode.jsonc` (contiene admin API key de Victoria)
- `.victoria-llm/llm-gateway.db` (contiene API keys plaintext)
- Scripts de administracion (persist.sh, bridge scripts, etc.)

**Para usar inferencia**: necesitas una key temporal de rol `coder` del admin.
**Para leer la guia remota**: `curl -s -H "Authorization: Bearer vllm-key-db13590a..." http://victoria.local:8010/v1/config-guide`


## 0. REGLA CRÍTICA: Data safety en contenedores

> **NADA que viva DENTRO de un contenedor Docker es permanente.**
>
> El sandbox `openshell-victoria-armada` (y cualquier contenedor de Docker)
> PUEDE ser eliminado o reiniciado en cualquier momento — `docker rm -f`,
> `nemoclaw rebuild`, crash, reboot. **Todo lo que no esté fuera del container
> se pierde para siempre.**
>
> **Reglas obligatorias para TODO trabajo con contenedores:**
>
> 1. **Siempre hacer snapshot ANTES de cambios**: `bash /home/victoria/openclaw-persist.sh backup`
> 2. **Todo dato importante debe existir DENTRO del sandbox PERO también afuera**:
>    - Config: `/home/victoria/.nemoclaw/persistent/victoria-armada/openclaw-latest/.openclaw/openclaw.json`
>    - Credenciales: `/home/victoria/.nemoclaw/persistent/victoria-armada/openclaw-latest/.openclaw/credentials/`
>    - Archivos del usuario: `Documents/Victoria Armada/` (en host, no en /sandbox/)
> 3. **NUNCA confiar en que el estado del container sobreviva a un rebuild**:
>    - Plugins npm se pierden → reinstalar siempre
>    - Credenciales de canales se pierden → tener backup en persist/
>    - Env vars que no se escriben a disco → guardar en openclaw.json
> 4. **No reiniciar contenedores si hay trabajo en curso**:
>    - `kill -HUP <PID>` en vez de reiniciar container para recargar config
>    - Si hay que reiniciar, esperar a que termine la operación primero
> 5. **Cada operación en un container debe contemplar data efímera**:
>    - ¿Qué pasa si este container se elimina ahora? ¿Se pierde algo?
>    - Si la respuesta es "sí y no debería ser así", hay un bug.
>
> **Resumen**: El contenedor es un entorno de ejecución efímero, no un disco duro.
> Si no tienes un respald0 fuera del container (persist.sh o en host), tu trabajo se puede perder.

### 0.1 Matriz de persistencia — qué sobrevive a cada escenario (audit 2026-08-16)

El sandbox NO tiene volumen para `/sandbox/.openclaw` (solo binds RO de
TLS/token). Todo lo que vive ahí es efímero. La cadena de protección es:

```
reboot / power failure / docker crash
   └─ restart=unless-stopped -> el container revive CON SU FS intacto
      └─ /sandbox/.openclaw sobrevive tal cual  (NO se pierde nada)

docker rm -f / nemoclaw rebuild
   └─ FS del container se resetea -> /sandbox/.openclaw VUELVE AL TEMPLATE
      └─ ensure-loop (15s) -> persist.sh auto detecta template -> restore backup
         └─ whatsapp-fix.sh apply (trust record + ownership)
         └─ customize-apply.sh (streaming labels, identityLinks)
         └─ restart del gateway (flag .gateway-restart-needed)
```

| Escenario | ¿Qué sobrevive? | ¿Qué se restaura? | Gatillo |
|---|---|---|---|
| **Reboot / power failure** | Todo (FS del container intacto) | Nada (no se toca) | `restart=unless-stopped` de docker |
| **Crash del proceso gateway** | Todo el FS | Nada (solo relanza el supervisor) | `nemoclaw-start` PID1 |
| **`docker rm -f` / `nemoclaw rebuild`** | Nada de `/sandbox/.openclaw` | Config+credenciales+identidad+voz+DB blogwatcher+plugins desde backup | `persist.sh auto` detecta config template |
| **Backup corrupto por power failure** | Backup previo (ATOMICO: extract a temp dir + `mv`) | — | nuevo método desde 2026-08-16 |

**Detección de rebuild (clave)**: `config_is_valid()` en persist.sh NO solo chequea
channels+plugins — el template de fábrica del rebuild TAMBIÉN tiene `channels.discord`
+ `plugins.entries.discord` (baked en la imagen). El marcador real de config
configurado por Victoria es **`session.identityLinks`** (lo aplica customize-apply;
la fábrica nunca lo tiene). Verificado contra el template real de la imagen
(3455 bytes, `channels:['defaults']`, sin identityLinks).

**Reinicio del gateway tras restore**: `channels.whatsapp` requiere restart del
proceso (el hot reload da "hot mode ignoring"). `persist.sh auto` escribe
`/home/victoria/.nemoclaw/persistent/victoria-armada/.gateway-restart-needed`
y el ensure-loop hace `pkill -f openclaw-gateway` (el supervisor nemoclaw-start lo
revive) DESPUÉS de aplicar todos los fixes.

**Qué NO se restaura por backup** (se reinstala por script dedicado):
- Plugins npm de canales (discord) → `ensure_npm_plugins` reinstala desde npm.
- WhatsApp → `/home/victoria/openclaw-whatsapp-fix.sh` (tgz local + trust record).
- Stack de voz (venv+modelos) → `openclaw-voice-host.sh` (AHORA VIVE EN EL HOST, ver §10 2026-08-17 06:15).
- Binario blogwatcher → `openclaw-rss-install.sh`.
- **Policies de egress** (weather/rss-feeds/personal-open-internet) → `ensure_policies` en el ensure-loop las re-aplica tras rebuild (lección 2026-09-19: un `onboard --fresh` las resetea y el agente queda sin clima/noticias/web). **CRÍTICO: `nemoclaw … policy` SOLO como victoria** (runuser + PATH absoluto) — como root el contexto falla y los adds no-opean en silencio. **NOTA**: `personal-open-internet` es el switch maestro (broad 80/443 subsume las reglas específicas): tras aplicarlo, `policy list` muestra los subsumidos como ○ y sus adds son no-ops silenciosos — NO es error.

**LEER ESTA MATRIZ ANTES DE CUALQUIER OPERACIÓN EN CONTENEDORES.**

## 1. Arquitectura (capa a capa)

```
opencode CLI  ─►  Gateway · www.alfredo.pro (:8010)  ─►  vLLM (:8000, Docker)
                         (llm-gateway.py)                (contenedor nemoclaw-vllm)
                                  │
                                  └► SQLite ~/.victoria-llm/llm-gateway.db (api keys + metering)

nemoclaw sandbox (openshell-victoria-armada-…)
  └ agente OpenClaw  ─►  inference.local:443 (proxy OpenShell)  ─►  host.openshell.internal:8000  ─►  vLLM
```

| Capa | Puerto | Proceso/contenedor | Estado | Notas |
|---|---|---|---|---|
| vLLM (inferencia) | `127.0.0.1:8000` | docker `nemoclaw-vllm` | up, `restart=unless-stopped` | label `com.nvidia.nemoclaw.managed-vllm=true` |
| Gateway (auth+metering) | `127.0.0.1:8010` | `python3 llm-gateway.py` (pid dinamico) | up | FastAPI `title="· www.alfredo.pro"` |
| Admin panel | `127.0.0.1:8010/admin` | el mismo gateway | up | LAN-only (túnel CF→403, IPv6 DROP, nginx 404 — **auditado 2026-09-05**); password en `ADMIN_PASS` env (default `victoria-admin`); **responsive móvil** (drawer hamburguesa ≤860px, mobile-first) |
| Sandbox nemoclaw | `inference.local:443` (interno) / `host.openshell.internal:8000` (host) | `openshell-victoria-armada-…` | up (healthy) | agente OpenClaw v2026.7.1 |
| Video server | `127.0.0.1:18811` | `victoria-video-server.service` | up, enabled | yt-dlp+ffmpeg en host; descarga YouTube + frames + transcripción; sandbox lo consume vía `172.18.0.1:18811` (bridge UNIX socket); auth 2026-09-17 (LAN con llave gateway admin/services) |
| Web nav server | `127.0.0.1:18820` | `web-nav-server.service` | up, enabled | Playwright+Chromium; navegación web autónoma de Victoria; auth 2026-09-17 (filtro IP + llave gateway admin/services en LAN) |
| Whois server | `127.0.0.1:18830` | `victoria-whois-server.service` | up, enabled | whois(1) del host para el sandbox (el sandbox no puede instalar whois ni salir por TCP 43); sandbox lo consume vía bridge UNIX socket `/tmp/whois-gateway.sock` → `host.docker.internal:18830`; auth 2026-09-17 (LAN con llave gateway admin/services) |

### 1.5. Grupos del Stack (organización lógica — 2026-09-18)

Cinco grupos en la misma máquina para control y recuperación por secciones.
Docker agrupa por **labels** (`victoria.group=<grupo>` en contenedores del
ensure-loop; nemoclaw/openshell gestionan los suyos con labels
`com.nvidia.*`/`openshell.ai.*`). **NO imponer compose ni mover paths** —
rompería lo que funciona. Modelos/configs/venvs FUERA de Docker (HOST) por
tamaño y supervivencia (~377G total). Mapa completo con recovery por grupo en
`victoria.md` §Grupos del Stack.

| Grupo | Docker | Host | Datos grandes (HOST) |
|---|---|---|---|
| 1. vLLM | `nemoclaw-vllm` | gateway :8010, gpu-saver, loop-alert | HF cache 43G |
| 2. OpenClaw/nemoclaw | sandbox + `openclaw-publisher` | ensure-loop, persist.sh, fixes, overrides, blogwatcher | `.nemoclaw/persistent/` 2.3G |
| 3. Sentidos | NINGUNO | voz/video/nav/whois/host-admin :18810-18840 | voice-models 6.1G, voice-venv 7.8G |
| 4. Contenido | `n8n` (Docker :5678) | LivePortrait :8180, ComfyUI :8188 (solo imágenes) | ComfyUI/models 109G, LivePortrait pesos ~300MB, comfy-venv 9.0G, liveportrait-venv 4.4G |
| 5. Infra | NINGUNO | cloudflared, nginx, armada-sync | `.armada-sync/` 31M |

> **GRUPO 4 RE-ARQUITECTURADO (2026-09-28)**: el pipeline de video LTX-2.5 se
> ELIMINÓ completamente (modelos, scripts, servicios — ver CHANGELOG 2026-09-28
> 19:20). El nuevo stack de contenido: **LivePortrait** para talking-head SOTA
> (:8180), **ComfyUI** para generación de imágenes (:8188, con FLUX/Z-Image/
> SDXL/SD1.5/ControlNet/InstantID/IP-Adapter), y **n8n** (:5678) como
> orquestador visual de workflows. InvokeAI NO es compatible con GB10/ARM64.

Cron `auto-apply-openclaw.sh` **DESHABILITADO 2026-09-18** (doble escritor de
openclaw.json vs customize-apply.sh; su `.master` no existe — INERTO desde
2026-08-18). Script en `~/.hygiene-quarantine-20260918/` con README. El path
canónico para aplicar config es overrides + customize-apply + persist.sh.

## 2. Modelo servido

- HF id: `nvidia/Qwen3.6-35B-A3B-NVFP4` (MoE, 35B params, 3B activos, NVFP4 quant).
- **Tipo**: VLM nativo (Vision Language Model). Arquitectura
  `Qwen3_5MoeForConditionalGeneration` con `vision_config` (depth 27, hidden
  1152, 16 heads, RGB) + tokens `<|vision_start|><|image_pad|><|vision_end|>`
  y `<|video_pad|>` (token ids 248053-248057). vLLM carga la vision tower al
  arranque; encoder cache budget 16384 tokens. Acepta `image_url`/`video_url`
  vía OpenAI Vision API. Verificado: PNG rojo 8x8 → `"rojo"`, HTTP 200.
  Evaluación incluye MMMU Pro (74.5 NVFP4 vs 74.1 BF16).
- Host: DGX Spark (NVIDIA GB10, compute capability 12.1, sm_121a).
- Contexto: `--max-model-len 262144` (256K NATIVO — **upgrade 2026-10-01 noche**, autorización del owner: 14 días de data, las 4 seqs NUNCA se usaron (pico 3, 0.17%) → se canjeó una carril por contexto nativo: `--max-num-seqs 4→3` y 3×262,144=786K ≤ KV 1,012,483 medido → **sin preemption garantizado** (concurrencia 3.86x a 256K), mismo 80% del pool que la era 4×192K. Historia: 262144 → 160K 2026-09-28 (KV auto 21.5GiB) → 192K 2026-10-01 tarde → 256K nativo + seqs 3 noche). opencode limita a `220000` con `output: 32000` (regla: `context + output ≤ 262144 − headroom`; 220K+32K=252K deja ~10K de margen). El gateway aplica un límite de prompt de 220K (`MAX_PROMPT_TOKENS=220000`) igual para todos los roles + guarda combinada 260144. **KV cache acotado (2026-09-29)**: `--kv-cache-memory-bytes 12GiB` (≈1,012K tokens medidos; antes el pool auto-crecía a 1.6-1.7M tokens = sobredimensionado) y `--max-num-seqs 3`. En GB10 `--gpu-memory-utilization` NO controla el KV (memoria unificada: el build NGC lo dimensiona por memoria libre) — el flag de bytes es el control real.
- Loaders: `--quantization modelopt --kv-cache-dtype fp8 --attention-backend flashinfer --moe-backend marlin --load-format fastsafetensors`.
- Parsers: `--tool-call-parser qwen3_xml --reasoning-parser qwen3 --enable-auto-tool-choice`. **Tool parser `qwen3_xml` desde 2026-09-13** (antes `qwen3_coder`): es la recomendación de la model card oficial de NVIDIA y el parser correcto para el formato XML `<function=name><parameter=key>` que usa el chat template de este modelo. `qwen3_xml` usa un parser XML real (expat) + `ast.literal_eval` → maneja correctamente argumentos anidados (arrays/objetos), caracteres especiales (`<`, `>`, `&`) y tool calls paralelos, que `qwen3_coder` (regex) malparqueaba. Verificado E2E.
- **Thinking OFF por defecto** (2026-09-13): `--default-chat-template-kwargs '{"enable_thinking": false}'`. El Qwen3 activa thinking por defecto en su chat template (ahí estaba el "se queda pensando" lento). Ahora el default es RÁPIDO (sin razonar) para todos los clientes; el thinking es opt-in vía sufijo `-thinking` en el model id o `reasoning_effort != none`, y queda acotado por `thinking_token_budget` (default 2048) inyectado por el gateway.
- Receta canonica en `~/.nemoclaw/source/src/lib/inference/vllm-models.ts:292-348` (entrada `qwen3.6-35b-a3b-nvfp4`).
- Pesos cacheados en `/home/victoria/.cache/huggingface/hub/models--nvidia--Qwen3.6-35B-A3B-NVFP4` (~22 GB).
- Imagen pinned por digest: `nvcr.io/nvidia/vllm@sha256:9204569b17ee4c0eff75194b8e6e458479c8aee18953b5ab9cf359fcdac659e2` (NGC vLLM 26.05.post1 / vLLM 0.21.0+2325b6f0, arm64).

## 3. Archivos clave

| Ruta | Que es | Cuidado |
|---|---|---|
| `~/.config/opencode/opencode.jsonc` | config opencode (provider, modelos, variantes) | config viva; no mezclar con `*.bkup-*` |
| `~/.config/opencode/opencode.jsonc.bkup-*` | últimos 2 backups de config (rollback) | solo referencia; no usar |
| `~/.config/opencode/agents/*.md` | subagentes opencode (ver seccion 7) | prompt = cuerpo del .md |
| `/home/victoria/llm-gateway.py` | gateway FastAPI (auth, metering, proxy a vLLM) | cambios aplican tras restart del gateway |
| `/home/victoria/admin_template.html` | UI del admin panel servido por el gateway | branding `· www.alfredo.pro`; favicon links en head (2026-09-17) |
| `/home/victoria/.victoria-custom/web/landing.html` | Landing LAN (victoria.local): estado del stack, accesos, roles — CSP LAN | la sirve `GET /` del gateway solo desde LAN |
| `/home/victoria/.victoria-custom/web/landing-public.html` | Landing pública (victoria.armada.do): personalidad/hub/negocio, sin nada interno — OG `og-victoria.jpg` + twitter:card, CSP `default-src 'none'` | la sirve `GET /` vía túnel; tablas → cards en móvil <640px |
| `/home/victoria/.victoria-custom/web/` (assets) | `og-victoria.jpg` (1200x630, generada de victoria-profile.jpg), `favicon.ico` (multi-size), `apple-touch-icon.png` (180x180), `favicon.png`, `logo.png` | servidos por `GET /assets/{f}` (cache 24h) y `GET /favicon.ico` (cache 7d), sin auth |
| `/home/victoria/llm-gateway.py.bkup-*` | últimos 2 backups del gateway (rollback) | solo referencia; los viejos van a `.hygiene-quarantine-*` |
| `/home/victoria/.git` | repo git del stack (init 2026-09-17, whitelist-only: docs+gateway+web/brand) | NUNCA add manual fuera de la whitelist; secrets/ excluido por .gitignore |
| `/home/victoria/nemoclaw-vllm-inspect-backup.json` | snapshot `docker inspect` del contenedor vllm original | receta canónica de lanzamiento |
| `~/.victoria-llm/llm-gateway.db` | SQLite: api keys, usage_log, metering, budgets | backing store del gateway |
| `~/.nemoclaw/{onboard-session.json,sandboxes.json}` | estado onboarding nemoclaw + sandbox | no editar a mano |
| `~/.nemoclaw/source/` | codigo fuente nemoclaw (recetas, schemas, docs) | read-only; referencia canónica |
| `/home/victoria/openclaw-bridge.py` | proxy TCP crudo del dashboard OpenClaw (18789) | HTTP + WebSocket OK (TCP puro); usado SOLO por el publisher en network host (el proxy interno del container fue ELIMINADO 2026-09-18 — el gateway vive DENTRO del sandbox :18790 de su netns; el :18790 del host es un relay `openshell forward service`, corregido 2026-09-21) |
| `/home/victoria/openclaw-bridge-ensure.sh` | ensure-loop que reasegura la cadena dashboard (red, publisher con `--network host` → `127.0.0.1:18790` del HOST) + persistencia + voz + plugins canales + rss + identidad + customize + **policies de egress (`ensure_policies`)** | loop de 15s via systemd `victoria-openclaw-bridge.service`; restaura config/voz/plugins/blogwatcher/identidad/overrides/policies si el sandbox se reconstruye; `ensure_inner_proxy` eliminada 2026-09-18; `ensure_policies` añadida 2026-09-19 (nemoclaw siempre como victoria via runuser); `ensure_dashboard_forward` añadida 2026-09-21 (recrea el relay host 127.0.0.1:18790 si falta o no responde HTTP) |
| `/home/victoria/openclaw-persist.sh` | backup/restore de `/sandbox/.openclaw` (config, identidad, canales, plugins config, voces, DB blogwatcher) | excluye `npm/`, `.voice-venv`, `hf-cache`, `.openclaw/bin/blogwatcher` (reinstalables); `--no-same-owner` al extraer; chown final victoria; restore repone `extensions/` a `root:root` |
| ~~`openclaw-voice-install.sh`~~ | **ELIMINADO 2026-08-31** (era OBSOLETO: legacy del stack de voz dentro del sandbox, falla porque el container solo tiene Python 3.13 y coqui-tts requiere <3.13). Usar `openclaw-voice-host.sh`. | ver `openclaw-voice-host.sh` |
| `/home/victoria/openclaw-voice-host.sh` | reinstala el stack de voz EN EL HOST (python3.12 + torch cu128 + qwen-tts 0.1.1 + openai-whisper + transformers 4.57.3 — coqui/XTTS eliminados 2026-10-03 + modelos + voces + unit systemd `victoria-voice-server.service` + wrappers `victoria-tts`/`whisper-cli` del sandbox por socket UNIX) | idempotente; modos ensure/install/status/test |
| `/home/victoria/openclaw-rss-install.sh` | reinstala el binario blogwatcher (Go ARM64 estático) desde el host si falta en el sandbox | idempotente; binario canónico en `/home/victoria/.victoria-custom/bin/blogwatcher` (13.9MB); DB se respalda con persist.sh |
| `/home/victoria/victoria-video-server.py` | daemon host de video (yt-dlp + ffmpeg + whisper vía voice-server): `POST /download`, `/frames`, `/transcribe`, `/analyze` (todo-en-uno con descripciones VLM); bind `0.0.0.0:18811`; auth 2026-09-17 (localhost/docker sin llave, LAN con llave gateway admin/services) | unit `victoria-video-server.service` (enabled, Restart=always); venv `/home/victoria/video-venv/` (yt-dlp); descargas en `~/.victoria-custom/videos/downloads/` |
| `/home/victoria/whois-server.py` | daemon host de whois: `GET /whois?domain=X` (whois(1) 5.5.22 del host) en `0.0.0.0:18830`; filtro de red (localhost/docker/LAN) + auth 2026-09-17 (LAN con llave gateway admin/services) + validación de dominio + subprocess sin shell; **fallback RDAP** (RFC 7480) para TLDs que whois genérico no soporta (.pro etc.) | unit `victoria-whois-server.service` (enabled, Restart=always); el sandbox lo consume vía bridge UNIX socket `/tmp/whois-gateway.sock`; no requiere venv (python3 stdlib) |
| `/home/victoria/victoria-host-admin.py` | daemon host de **Host Admin Bridge** (autonomía de Victoria): `GET /health /status`, `POST /exec` (allowlist dig/host/nslookup/curl/whois/jq/ping/openssl), `POST /apt/install` (allowlist paquetes), `POST /service` (allowlist servicios del stack) en `0.0.0.0:18840`; bridge key propia O llave gateway **rol admin puro** (**2026-10-19**: `sense_role(elevate=False)` — sin elevación de caps ni rol services; la llave kalimete da 401 por diseño: kalimete consume recursos, no opera la máquina) + filtro de red + validación args + audit log | unit `victoria-host-admin.service` (enabled, Restart=always); key en `~/.victoria-custom/secrets/admin-bridge.key` (600); sandbox lo consume vía `admin-bridge.py` (UNIX socket `/tmp/admin-gateway.sock`) con wrapper `/sandbox/.openclaw/bin/admin-cli`; 100% local/gratis |
| `/home/victoria/sense_auth.py` | auth compartida de los 5 sentidos (voz/video/nav/whois/host-admin) + hunyuan/lp-animate: valida llaves gateway admin/services contra la DB viva (sha256, active, no expirada); localhost+docker sin llave, LAN con llave; **honra `allowed_models`** (llave con caps art/tts/whisper/liveportrait/comfyui → elevada a services; `provision` JAMÁS eleva — poder del gateway, no un sentido, 2026-10-20; `tts` = voz TTS, motor Qwen3-TTS — renombrada desde `xtts` 2026-10-04); **`sense_role(headers, elevate=False)` (2026-10-19)**: desactiva la elevación — lo usa host-admin para dejar fuera las llaves con caps (kalimete) | stdlib, sin deps; importado por los daemons de sentidos; ver §Servicio de Voz "Auth unificada" |
| `~/.victoria-custom/bin/art-gen` | wrapper de generación de IMÁGENES para OpenClaw (canónico host → `/sandbox/.openclaw/bin/art-gen`): submit→poll→download a `media/outbound/` (managed root del runtime 2026.9.x — `LocalMediaAccessError` en `media/` plano para remitentes restringidos) + **envío atómico** `--send-to <target> --caption "..." [--channel wa\|dc]` (JSON `sent.messageId`; fix 2026-10-06 anti-alucinación de envíos); **gate de ventanas** `--for <scope>`/`--owner` (DM libre; grupos solo con ventana vigente); reintentos automáticos en 429; `templates`/`status` | SOLO imágenes (política owner 2026-10-03); llave dedicada `victoria-openclaw-sandbox` (rol art) en `.art-key` 600; reasegurado por `ensure_art()` |
| `~/.victoria-custom/bin/art-approve` | ventanas de imágenes por grupo para OpenClaw (2026-10-05, canónico host → `/sandbox/.openclaw/bin/art-approve`): `request`/`approve <scope> [horas]`/`deny`/`revoke`/`status`; scopes `wa:<jid>`/`dc:<guild>`; cap duro 4h, cuota default 10; **SOLO el owner** (por DM o en el grupo con `senderIsOwner`) | estado en `/sandbox/.openclaw/workspace/art-approvals.json` (`{scopes, pending}`, respaldado por persist.sh); auto-ventana 4h cuando el owner genera en grupo (`ensure_owner_window`); reasegurado por `ensure_art()` |
| `~/.victoria-custom/comfyui-templates-api/` | templates API-format REALES para la art API (`z-image-turbo` receta oficial Comfy-Org, `flux-schnell` receta oficial FLUX 4-steps, `sd15-realistic` de un PNG que funcionó) | el gateway los busca PRIMERO; los workflows/ de ComfyUI son shells UI-format vacíos |
| `~/.victoria-custom/skills/art/SKILL.md` | skill `art` del workspace de Victoria (OpenClaw): cuándo generar, templates, tamaños, envío canónico `art-gen --send-to` (send manual = fallback), ventanas de grupo, fotos personales, límites 1-a-la-vez | restaurada por `ensure_art()` tras rebuild |
| `~/.victoria-custom/{openclaw-TOOLS.md,openclaw-HEARTBEAT.md,victoria-photos/}` | maestros del workspace OpenClaw sincronizados por `ensure_art()`: TOOLS.md (bloque art + reglas de cierre de turno / envío atómico / privacidad de terceros / fotos personales / antibucles), HEARTBEAT.md solo-comentarios (= heartbeat OFF; un poll filtró texto en inglés al DM del owner 2026-10-05), repo de 6 fotos personales → `media/outbound/victoria-photos/` | el template de fábrica del rebuild RE-ACTIVARÍA el heartbeat sin el sync; el sync no pisa ediciones live |
| `/home/victoria/.victoria-custom/bin/video-bridge.py` | bridge UNIX socket `/tmp/video-gateway.sock` (dentro del sandbox) → host `172.18.0.1:18811` | mismo patrón que tts-bridge.py; lanzado y reasegurado por `ensure_video` en el ensure-loop. **Los 4 bridges (tts/video/whois/admin) endurecidos 2026-10-04**: thread por conexión + timeouts + close garantizado — antes mono-hilo con recv infinito (un cliente mudo atascaba todo) |
| `/home/victoria/.victoria-custom/bin/{video-dl,video-analyze}` | wrappers del sandbox para el video-server (descarga / análisis todo-en-uno con frames+transcripción+descripciones VLM) | copiados al sandbox por `ensure_video` (sobreviven rebuilds) |
| `/home/victoria/.victoria-custom/skills/video/SKILL.md` | skill `video` del workspace de Victoria (cómo analizar links de YouTube) | restaurado por `ensure_video`; el runtime detecta el VLM local (Qwen) para media-understanding |
| `/home/victoria/.victoria-custom/openclaw-overrides.json` | overrides canónicos de `openclaw.json` (18 labels Discord streaming, active-memory config, session.identityLinks cross-canal) | aplicado por `openclaw-customize-apply.sh` tras restore; idempotente (_managed lista rutas; sin _meta) |
| `/home/victoria/.victoria-custom/openclaw-customize-apply.sh` | deep-merge idempotente de overrides al `openclaw.json` del sandbox | apply/check/status; drift detection por hash; enlace al ensure-loop |
| `/home/victoria/.victoria-custom/bin/blogwatcher` | binario Go v0.0.3 ARM64 estático (compiled `CGO_ENABLED=0`) para el CLI del blogwatcher | 13.9MB; source `github.com/Hyaxia/blogwatcher`; rebuild con `go build` si se actualiza v0.0.4+ |
| `/home/victoria/.voice-models/{Qwen3-TTS-12Hz-0.6B-Base,Qwen3-TTS-12Hz-1.7B-Base,Qwen3-TTS-12Hz-1.7B-VoiceDesign,whisper-small}` | modelos maestros de voz en el host (principal Qwen3-TTS 0.6B-Base 2.4G; 1.7B-Base y VoiceDesign para calidad/diseño; copia local de whisper-small — el server carga el STT de `~/.cache/whisper/small.pt`) | el sandbox no puede bajar de HF (proxy 403); viven en el host, el sandbox consume por bridge |
| `/home/victoria/{IDENTITY,SOUL,USER}-restore.md` | identidad maestra de Victoria (humanoid, hija de Alfredo Armada) en el host | sync con `/sandbox/.openclaw/workspace/`; restaurar si el sandbox pierde identidad |
| `victoria-openclaw-bridge.service` | systemd unit (enabled) de persistencia del dashboard bridge | `Restart=always`; recrea publisher y relanza proxy si cae |
| `~/.victoria-custom/secrets/data.txt` | **CONTIENE SECRETOS en texto plano** (HF_TOKEN + nvapi keys) + config stale | solo victoria (600 dentro de dir 700); NO commitear; key ACTIVA nvapi-AuHo… (victoria-1); rotación vía `nvapi-rotate.sh` (ver seccion 8) |

## 4. Comandos operativos (runbook rapido)

### Supervivencia tras reboot / force shutdown

El stack esta blindado para arrancar en automatico tras un reinicio o
`systemctl poweroff`/`shutdown -r`. Orden de arranque (resuelto por systemd):

```
boot
 ├─ docker.service                     (enabled; levanta daemon Docker)
 │    ├─ nemoclaw-vllm container         (restart=unless-stopped; carga ~5-7 min)
  │    └─ openshell-victoria-armada-…        (restart=unless-stopped; sandbox nemoclaw)
 ├─ victoria-llm-gateway.service       (enabled; After=docker.service; Restart=always)
 │    └─ gateway FastAPI en 0.0.0.0:8010 (loopback + LAN + tunel Cloudflare)
 └─ cloudflared.service                 (enabled; After=victoria-llm-gateway.service; Restart=always)
      └─ tunnel → victoria.armada.do → http://127.0.0.1:8010
```

| Componente | Mecanismo autostart | Restart en crash | Notas |
|---|---|---|---|
| Docker daemon | `systemctl is-enabled docker` = enabled | n/a (systemd gestiona) | Arranca contenedores con `restart=unless-stopped` |
| vLLM container | `restart=unless-stopped` + label `managed-vllm=true` | si (docker daemon) | Carga del modelo ~5-7 min; mientras, `/health` da connection refused (normal) |
| Sandbox nemoclaw | `restart=unless-stopped` (container `openshell-default--victoria-armada-*` desde 2026-09-05) | si (docker daemon) | Etiqueta salud `healthy`; **gateway openshell es systemd --user `nemoclaw-openshell-gateway.service` (enabled) y requiere `loginctl enable-linger victoria` para arrancar sin login tras reboot** (aplicado 2026-09-05) |
| Gateway 8010 | `victoria-llm-gateway.service` (enabled) | `Restart=always` + `StartLimitBurst=5/120s` | Bind `0.0.0.0:8010` (LAN + tunel), `After=docker.service`, `User=victoria` |
| Tunel Cloudflare | `cloudflared.service` (enabled) | `Restart=always` + `StartLimitBurst=5/120s` | `After=victoria-llm-gateway.service` (no adelanta al gateway) |
| ComfyUI | `comfyui.service` (enabled — auto-arranca tras reboot) | `Restart=always` | Bind `127.0.0.1:8188` (solo loopback; LAN vía nginx `/comfyui/`). venv `comfy-venv` cu130. Ver §11 y `Comfyui`. |
| LivePortrait | `liveportrait.service` (enabled) | `Restart=on-failure` | Talking-head SOTA en `0.0.0.0:8180` (LAN vía nginx `/liveportrait/`); incluye tab 🎙️ Estudio Podcast. venv `liveportrait-venv`, Gradio 6.29.0. Ver §11 y `Liveportrait` (servicio/UI) + `Sonic` (contenido del tab). |
| Sonic podcast | `victoria-sonic-server.service` (enabled) | `Restart=always` | Audio-driven talking head en `0.0.0.0:18850` (single-flight, VRAM ~24GB). Ver §11 y `Sonic`. |
| n8n | contenedor Docker `n8n` (`restart=unless-stopped`) | si (docker daemon) | Orquestador visual en `:5678` (LAN vía nginx `/n8n/`). Datos en `/home/victoria/n8n-data/`. Ver §11. |
| Guardian GPU/VRAM | `victoria-gpu-saver.service` (enabled) | `Restart=always` | **Reemplaza al idle-saver** (2026-08-17). Daemon unificado: NUNCA mata vLLM para liberar VRAM (servicio de ingreso); si ComfyUI está idle libera su VRAM vía `/free`; detecta vLLM colgado vía probe (timeout 25s) y, tras 4 probes "hung" consecutivos (~4 min), hace **`docker restart nemoclaw-vllm`** (auto-recovery con cooldown 15 min — actualizado 2026-09-08); térmica 75/80C + **watchdog de carga sostenida (2026-10-14, duty-cycle 2026-10-17): ventana deslizante 10 min — si ≥80% de las muestras tienen util ≥85% → alerta WhatsApp al owner** (el patrón del apagón 2026-10-16 — 96% con micro-pausas cada ~2 min — burlaba el contador de ticks continuos) + **dead man's switch (2026-10-17): si el envío WA falla 2 veces seguidas, la alerta sale también por Discord** — es el patrón que congeló el host el 2026-10-13 (la temp es síntoma, no causa). Daemon: `/home/victoria/victoria-gpu-saver.py`, log `/home/victoria/logs/victoria-gpu-saver.log`, métricas WAL `~/logs/victoria-metrics.db` (caja negra que sobrevive freezes). Dueño: `Gpu` (ver `gpu.md`: árbitro + térmica + carga sostenida + VRAM). |
| **Cap de clocks GPU** (2026-10-26) | `gpu-clock-cap.service` (enabled, oneshot) | n/a (boot) | **Anti-sobrecorriente** (fix muertes 2026-10-24, foro NVIDIA 360336): `nvidia-smi -lgc 300,2100` en cada boot — elimina los picos 14→93W que tripan la protección de potencia (costo ~10-15% velocidad). Reversible: `nvidia-smi -rgc`. **Verificado en boot real 2026-10-26**: GPU opera a 2093MHz (lock 2100; antes 2418/3003). **LECCIONES**: (1) units oneshot NUNCA llevan `After=multi-user.target` (la cadena de targets puede estar bloqueada); (2) **plymouth-quit-wait deadlockea TODOS los boots headless de esta imagen** (plymouth-quit.service nunca activa → plymouthd huérfano → 8 jobs atascados + consolas getty sin spawnear) — **FIX PERMANENTE 2026-10-26: `systemctl mask plymouth-quit-wait.service plymouth-start.service`** (appliance sin monitor no necesita plymouth); (3) `systemctl list-jobs` es el primer check ante cualquier systemctl colgado. |
| **swappiness UMA** (2026-10-26) | `/etc/sysctl.d/99-victoria-uma.conf` | n/a (boot) | `vm.swappiness=10` (era 60) — en memoria unificada el swap thrash causa freezes silenciosos (thread NVIDIA 360336). Fase 1 escalonada; swap files (55GB) quedan hasta evaluar RAM estable. |
| Voice-server (TTS/STT) | `victoria-voice-server.service` (enabled) | `Restart=always` | **VIVE EN EL HOST** (python3.12) desde 2026-08-17; TTS **Qwen3-TTS-12Hz-0.6B-Base** (clonación ICL por idioma: `~/voices/victoria-reference.wav` + `.txt` para inglés / `victoria-es-reference.wav` + `.txt` para español nativo, salida 24kHz, único motor desde 2026-10-03) + STT Whisper en `0.0.0.0:18810`; el sandbox lo consume vía bridge UNIX socket (`victoria-tts`/`whisper-cli` → `/tmp/tts-gateway.sock`). Daemon: `/home/victoria/voice-venv/voice-server-host.py`. |
| Video server | `victoria-video-server.service` (enabled) | `Restart=always` | yt-dlp (venv `video-venv`) + ffmpeg en `0.0.0.0:18811`; descarga YouTube (JS runtime deno en `~/.deno/bin`, config `~/.config/yt-dlp/config` con `player_client=android`), extrae frames, transcribe vía voice-server, describe frames con el VLM local. El sandbox lo consume vía `172.18.0.1:18811` (bridge UNIX socket `video-bridge.py`). Daemon: `/home/victoria/victoria-video-server.py`. |
| Web nav server | `web-nav-server.service` (enabled) | `Restart=on-failure` + `RestartSec=3` | Victoria web navigation (Playwright + Chromium) en `0.0.0.0:18820`; navegación autónoma de Victoria por internet (consistente con preset egress `social-sites`). Daemon: `/home/victoria/web-nav-server.py`, venv `/home/victoria/web-nav-venv/`, `User=victoria`. |
| Whois server | `victoria-whois-server.service` (enabled) | `Restart=always` | whois(1) del host (5.5.22) en `0.0.0.0:18830`; el sandbox lo consume vía bridge UNIX socket `/tmp/whois-gateway.sock` → `host.docker.internal:18830` (wrapper `/sandbox/.openclaw/bin/whois`). Filtro de red (localhost/docker/LAN) + validación de dominio + fallback RDAP para TLDs no soportados (.pro). Skill `domain` en el workspace del sandbox enseña a Victoria a usarlo. Daemon: `/home/victoria/whois-server.py`. El sandbox NO puede instalar whois (apt roto + puerto 43 bloqueado por proxy L7). |
| Host Admin Bridge | `victoria-host-admin.service` (enabled) | `Restart=always` | **Autonomía de Victoria**: expone al sandbox acceso SEGURO a tools del host (`dig host nslookup curl whois jq ping openssl`), `apt install` (allowlist) y servicios del stack. API key (`X-API-Key`) + filtro de red + allowlists + audit log. Daemon: `/home/victoria/victoria-host-admin.py`; key en `~/.victoria-custom/secrets/admin-bridge.key` (600). El sandbox lo consume vía `admin-bridge.py` (UNIX socket `/tmp/admin-gateway.sock` → `host.docker.internal:18840`) con wrapper `/sandbox/.openclaw/bin/admin-cli` y skill `admin`. 100% local/gratis. |
| DGX dashboard/telemetry | `dgx-dashboard.service`, `dgx-dashboard-admin.service`, `nvidia-dgx-telemetry.service` (enabled) | n/a | Telemetría/hardware del DGX Spark (NVIDIA). No parte del stack LLM — servicios del sistema base. |
| Auto-mover ComfyUI | `victoria-comfyui-models-mover.service` — **ELIMINADO 2026-09-28** (unit + script borrados del disco) | n/a | Mover `.safetensors` a `ComfyUI/models/<tipo>/` a mano (ver `Comfyui` § "Mover modelos a mano") |
| Auto-download ComfyUI | `victoria-comfyui-models-downloader.service` — **ELIMINADO 2026-09-28** (unit + script borrados del disco) | n/a | Bajar con `wget -c` a mano (ver `Comfyui` § "Bajar modelos a mano") |
| Hardening vLLM `:8000` | `netfilter-persistent.service` (enabled) | n/a (boot-time) | Aplica `/etc/iptables/rules.v6` al boot: regla `INPUT DROP tcp dport 8000` bloquea inbound IPv6 a vLLM (vLLM no auth). Acceso permitido: IPv4 (localhost del gateway, docker bridge del sandbox, LAN directa). Bloqueado: IPv6 público (bypass sin API key). Ver §8 Seguridad. |
| Watchdog hardware (2026-09-20) | systemd manager (`/etc/systemd/system.conf`) | n/a | `RuntimeWatchdogSec=180` → SBSA GWDT (`/dev/watchdog0`): si el KERNEL se congela (freeze tipo 2026-09-15), reboot automático en 3 min — la máquina ya no queda colgada esperando al owner. NO cubre cortes de luz (eso es UEFI "AC Power Recovery=Power On" + UPS, pendiente físico del owner). Forense 2026-09-20: boots -1/-2 terminaron abruptos sin shutdown ⇒ cortes eléctricos. **3er corte 2026-09-20 16:34** (sáb 21:21, dom 05:21, dom 16:34 — todos en actividad normal, sin pstore, sin térmicos, watchdog sin disparar = electricidad confirmada). El hardening no puede contra la energía. |
| OOM protection (2026-09-20) | drop-ins systemd (5 servicios) | n/a | `OOMScoreAdjust=-500` (gateway/docker/cloudflared/nginx), `-750` (ssh): el OOM killer ataca procesos sacrificables antes que la infraestructura de acceso. Verificado con `systemctl show`. |
| Observación 24h (2026-09-20) | cron `*/15` (`observe-24h.py`) | n/a | Collector de observación CERO-impacto (sqlite mode=ro, nvidia-smi, /health 3s): snapshot cada 15 min en `~/logs/observation-24h.log` (requests/rejects/latencias/engine/GPU/RAM/anomalías/circuit) + alertas `** ALERT **` grep-eables + WhatsApp solo para 4 condiciones sin alertero propio (cooldown 2h). A las 24h marca y ESPERA — el cierre lo ejecuta el owner con `observe-24h.py report [--send]` (aprobación previa). Gaps >45 min = firma de corte eléctrico. |

Persistencia en disco (no requiere reseed tras reboot): `/etc/sudoers.d/{victoria,warcold-sqlite3ro}`,
`/usr/local/bin/sqlite3ro`, `/usr/local/libexec/sqlite3ro_real`, `/etc/cloudflared/token`,
`/etc/systemd/system/{victoria-llm-gateway,cloudflared,victoria-gpu-saver,victoria-voice-server,web-nav-server,liveportrait,comfyui,victoria-sonic-server}.service`,
`/etc/systemd/system/<svc>.service.d/override.conf` (OOM drop-ins, 2026-09-20),
`/etc/systemd/system.conf` (`RuntimeWatchdogSec=180`, 2026-09-20),
`/etc/iptables/rules.v6` (regla DROP IPv6 a `:8000`, persistida via
`netfilter-persistent.service` enabled),
`llm-gateway.py`, `opencode.jsonc`, `~/.victoria-llm/llm-gateway.db`, usuario `warcold` (`/bin/rbash`) y
grupo `vllm-readers`. El guardian GPU/VRAM es un daemon Python (`/home/victoria/victoria-gpu-saver.py`)
corrido por systemd como `User=victoria` (no root); log en `/home/victoria/logs/victoria-gpu-saver.log`.
El idle-saver de ComfyUI (`victoria-comfyui-idle-saver.service`) fue **superseded** por el gpu-saver
(2026-08-17) y ya no corre; su script y unit fueron **ELIMINADOS 2026-08-31**. El stack de voz vive en el host: venv `/home/victoria/voice-venv/`
(python3.12) + unit `victoria-voice-server.service` (enabled, `Restart=always`).
El auto-mover (`victoria-comfyui-models-mover.service` + `/home/victoria/comfyui-models-mover.sh`) y el auto-download (`victoria-comfyui-models-downloader.service` + `/home/victoria/comfyui-models-downloader.py`) fueron **ELIMINADOS 2026-09-28** (units + scripts borrados del disco; ver CHANGELOG 2026-09-28 19:20). Modelos: mover/bajar a mano (ver `Comfyui`).

**Ventana de servicio tras reboot**:
- `T+0..5s`: gateway, sandbox y cloudflared arriba.
- `T+0..5min`: vLLM carga el modelo en GPU. Mientras, `/v1/*` del gateway da
  `502 Bad Gateway` (upstream vLLM connection refused); `/health`, `/models`,
  `/v1/config-guide` funcionan (no tocan vLLM).
- `T+5..7min`: vLLM `/health` → 200; gateway empieza a servir inferencia.

**Apagón + internet tardío (runbook 2026-09-17)**: tras una falla eléctrica el
boot local NO espera al ISP. Línea esperada cuando vuelve la luz: `T+0` servicios
que bindean local (gateway, voz, video, whois, bridge, sandbox con FS intacto) →
`T+0..2min` red local/DHCP (`network-online.target` = solo link local, NO es
"hay internet") → `T+5..7min` vLLM cargando (502 del gateway = normal, gpu-saver
loguea UNHEALTHY sin reiniciar) → `T+?` túnel cloudflared **solo cuando vuelva el
ISP + reloj NTP correcto** (sin DNS da `server misbehaving` y reintenta; desde
2026-09-17 aguanta ~30 min de reintentos con backoff antes de rendirse:
`StartLimitBurst=100/1800s`, `RestartSec=10s→max 120s`). Crons caídos durante el
corte se pierden sin daño (el siguiente slot cubre; `armada-sync.timer` tiene
`Persistent=true` y se pone al día). Chequeo post-apagón: `systemctl --failed`
(limpio tras mask de fwupd), túnel vía IP real CF con `--resolve` (el `/etc/hosts`
mapea el dominio a 127.0.0.1 y el probe directo da 000 aunque todo esté bien).

### Supervivencia y auto-start ComfyUI

ComfyUI corre como systemd service (`comfyui.service`) **`enabled`
(auto-arranca tras reboot)** con `Restart=always`. Escucha solo loopback
(`--listen 127.0.0.1:8188`); la LAN lo alcanza vía nginx `/comfyui/`.

Los daemons de soporte auto-mover/auto-download fueron **ELIMINADOS 2026-09-28**
(ver arriba). Modelos nuevos: mover/bajar a mano y `sudo systemctl restart comfyui`.

Para inicio manual (debug):

```bash
source /home/victoria/comfy-venv/bin/activate
python3 /home/victoria/ComfyUI/main.py --listen 127.0.0.1 --port 8188
```

Monitoreo de GPU compartida durante uso:
```bash
python3 /home/victoria/comfyui-monitor.py       # reporte completo cada 5 min
watch -n 5 "docker exec nemoclaw-vllm nvidia-smi"  # headroom visual
```

### Salud completa

```bash
# Estado de los 3 contenedores
docker ps --format '{{.Names}} | {{.Status}} | {{.Ports}}'

# vLLM (puerto 8000)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/health        # -> 200
curl -s http://127.0.0.1:8000/v1/models | python3 -m json.tool              # lista el modelo servido

# Gateway (puerto 8010)
curl -s http://127.0.0.1:8010/health                                         # status + stats
curl -s -H "Authorization: Bearer $VLLM_KEY" http://127.0.0.1:8010/models    # lista modelos gateway

# Sandbox nemoclaw (ruta inference.local desde dentro del sandbox)
nemoclaw victoria-armada status
```

### Rearmar el contenedor vLLM si falta o esta roto (256K nativo + seqs 3, 2026-10-01; +compile-cache mount 2026-10-26)

> Solo si `docker ps -a` no muestra `nemoclaw-vllm`. La receta esta alineada
> con `vllm-models.ts:292-348` (perfil DGX Spark). No cambiar los flags.
> **2026-10-26**: añadido el mount `-v ~/.vllm-compile-cache:/root/.cache/vllm` —
> el torch.compile se cachea en HOST (antes se perdía en cada recreación del
> contenedor efímero y el boot tardaba 5-7min; ahora ~3min y el costo del
> compile de cualquier versión futura se paga UNA vez). **NUNCA upgradear a
> imagen 26.06+ sin Plan del owner**: vLLM 0.29 eliminó `--moe-backend marlin`
> (crash-loop) y las imágenes 26.09+ exigen driver ≥615.71 (host: 580.178.04) —
> ver CHANGELOG 2026-10-26 15:45.

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

Carga del modelo ~5-7 min la primera vez. Mientras, `/health` da connection refused; no reiniciar en bucle.

### Reiniciar el gateway (8010)

```bash
sudo systemctl restart victoria-llm-gateway.service
sleep 3 && curl -s http://127.0.0.1:8010/health
```

El gateway corre como systemd service (`victoria-llm-gateway.service` con `Restart=always`, bind `0.0.0.0:8010`).
Si necesitas un restart manual por algun razon que `systemctl restart` no funcione, kill y relanza como nohup (ver abajo).

Forzar reinicio por nohup (solo si systemd falla):
pkill -f llm-gateway.py && nohup python3 /home/victoria/llm-gateway.py >/tmp/gw.log 2>&1 &
```

### Detener / arrancar el sandbox nemoclaw

```bash
nemoclaw victoria-armada stop      # detener sin perder estado
nemoclaw victoria-armada start     # reanudar
nemoclaw victoria-armada recover   # reparar gateway/forwards rotos
nemoclaw victoria-armada doctor    # diagnostico completo
```

### Dashboard OpenClaw (OpenClaw Control) — gateway en SANDBOX + relay en host (corregido 2026-09-21)

El UI del agente OpenClaw (`OpenClaw Control`) lo sirve el **gateway
`openclaw-gateway` que vive DENTRO del sandbox** (uid 998; binda 18790 solo
en su netns interno — corrección 2026-09-21 a la nota del 18-sep, que lo
ubicó erróneamente en el HOST: lo que se veía en el host era el relay, no
el gateway). El `127.0.0.1:18790` del host lo sirve un relay
`openshell forward service` (host → loopback interno del sandbox), y el
publisher lo publica en `0.0.0.0:18800` para LAN (desde rebuild 2026.9.2 del 2026-10-05 — ownership proof nemoclaw v0.0.130 exige 18789-18799 libre; antes 18789):

```
victoria.local:18800 (host, 0.0.0.0:18800)
  └─ openclaw-publisher (contenedor Docker, --network host, restart=unless-stopped)
       └─ 127.0.0.1:18790 (relay openshell forward service en el HOST)
            └─ 127.0.0.1:18790 (gateway openclaw-gateway DENTRO del sandbox, netns interno)
```

**Ya NO existe**: el proxy interno dentro del container (openclaw-bridge.py
18789→10.200.0.2:18790 fue ELIMINADO 2026-09-18).

**Trampa de diagnóstico (lección 2026-09-21)**: `/proc/<pid>/fd` sin sudo da
vacío y el `ss` del host NO ve listeners de otro netns — un gateway sano
parece "sordo". Verificar con `sudo nsenter -t <pid> -n ss -tln` + curl en
ese netns. El relay del host murió con el reboot del 20-sep y nadie lo
recreaba → dashboard 000 con publisher UP (cadena rota en el relay, no en
el gateway).

- **URL**: `http://victoria.local:18800/#token=$(nemoclaw victoria-armada gateway-token)` (token rotativo; puerto 18800 desde 2026-10-05)
- **Verificado**: HTTP 200 + handshake WS `101 Switching Protocols` + `connect.challenge` (2026-08-14); re-verificado con la nueva cadena 2026-09-18 (`{"ok":true,"status":"live"}`).
- **Persistencia**: `victoria-openclaw-bridge.service` (systemd enabled, `Restart=always`)
  corre `/home/victoria/openclaw-bridge-ensure.sh` en loop de 15s: (1) crea la red
  `victoria-lan` (172.22.0.0/16 — para bridges voice/video/whois/admin, NO el dashboard), (2) conecta el sandbox con IP fija `172.22.0.10`,
  (3) recrea el publisher si falta (con `--network host` → `127.0.0.1:18790`), (4)
  restaura config+identidad desde el host (`openclaw-persist.sh auto`), (5) reinstala
  el stack de voz del host y reasegura el voice-server (`openclaw-voice-host.sh ensure`), (6)
  reinstala los plugins npm de canales discord/whatsapp si se perdieron
  (`ensure_npm_plugins`). Tras un rebuild o `stop`/`start` del sandbox se
  auto-repara en ~15s (config) / ~5min (voz). Ver "Anti-pérdida" en el subagente
  `OpenClaw` para los ownership críticos (`openclaw.json` sandbox:660,
  `extensions/` root:root; `openclaw plugins install` siempre como uid 998).
- **Reparacion manual**: `sudo systemctl restart victoria-openclaw-bridge.service`

### OpenClaw — typing indicators y reacciones (2026-08-26)

OpenClaw soporta **typing indicators** y **reacciones automáticas** configuradas en
`openclaw.json` del sandbox vía `openclaw-overrides.json`:

**Typing indicators** (`session.typingMode`):
- `"instant"` → Victoria muestra "Victoria está escribiendo..." antes de responder
- Se activa desde el host vía `openclaw-overrides.json` → `session.typingMode = "instant"`
- El hot-reload del gateway aplica esta config sin reiniciar el sandbox

**Reacciones en Discord** (`channels.discord.guilds.<guildId>.reactionNotifications`):
- `"own"` → Victoria reacciona a mensajes del owner (en cada guild)
- `"all"` → Victoria reacciona a TODOS los mensajes
- `"off"` → Sin reacciones
- `"allowlist"` → Solo reacciones de usuarios en allowlist
- **CRITICO**: la propiedad va DENTRO de `guilds.<guildId>` (nunca a nivel de
  `channels.discord` — el schema del plugin la rechaza ahí con
  `must not have additional properties: "reactionNotifications"`).
  Schema verificado (runtime openclaw 2026.7.2-beta.7, `extensions/discord/dist/config-schema-*.js`):
  `guilds.<guildId>` acepta SOLO: `slug, requireMention, ignoreOtherMentions, tools, toolsBySender, reactionNotifications, users, roles, channels`.

**Reacciones en WhatsApp** (`channels.whatsapp.ackReaction` + `reactionLevel`):
- `ackReaction`: `{emoji: "👍", direct: true, group: "mentions"}` → reacción en DMs (`direct`) y grupos solo al ser mencionada (`group`)
- `reactionLevel`: `"off"`|`"ack"`|`"minimal"`|`"extensive"` → nivel de reacciones
- `"ack"` → reacciona a mensajes (ack acknowledgment)
- **CRITICO (schema verificado** en `extensions/whatsapp/dist/config-schema-*.js`**)**:
  - `ackReaction` es objeto con `emoji`, `direct` (bool, default true), `group` (enum `always|mentions|never`), **`required: [direct, group]`** y **`additionalProperties: false`** → NUNCA poner `enabled` dentro (rompe el schema).
  - `mentionPatterns` es OBJETO `{mode: "allow"|"deny", allowIn: [], denyIn: []}` — **NO es array de strings** (un array rompe con `must be object`).
  - `groups.<groupId>` acepta SOLO: `requireMention, tools, toolsBySender, systemPrompt` — **NO** `groupPolicy` ni `mentionPatterns` dentro.
  - `groupPolicy` a nivel de canal: string enum `open|disabled|allowlist` (default `allowlist`).

Config actual en `openclaw-overrides.json`:
```json
{
  "session": {
    "typingMode": "instant"
  },
  "channels": {
    "discord": {
      "guilds": {
        "1365731253629751406": { "reactionNotifications": "own" },
        "233040661492924418": { "reactionNotifications": "own" }
      },
      "groupPolicy": "open"
    },
    "whatsapp": {
      "dmPolicy": "pairing",
      "allowFrom": ["18295468686"],
      "groupPolicy": "open",
      "ackReaction": { "emoji": "👍", "direct": true, "group": "mentions" },
      "reactionLevel": "ack"
    }
  }
}
```

**Hot-reload**: las config de typing y reacciones se aplican vía customize-apply.sh
en el ensure-loop (cada 15s). El gateway de OpenClaw las carga sin reiniciar el
sandbox. Si hay errores de schema (`invalid config`), se registran en los logs del
gateway pero no se aplican. Verificar con `docker logs <sandbox> | grep "invalid config"`.

## 5. Config opencode (modelo y variantes)

`opencode.jsonc` expone dos entradas que apuntan al mismo `SERVED_MODEL` (el gateway normaliza el alias por sufijo):

| Alias en opencode | `id` (model id enviado) | thinking | Uso |
|---|---|---|---|
| `vllm/nvidia/Qwen3.6-35B-A3B-NVFP4-normal` | `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` | OFF (explícito) | coding rapido (default de sesiones nuevas desde 2026-10-03: `"model"` en opencode.jsonc de ambos hosts) |
| `vllm/nvidia/Qwen3.6-35B-A3B-NVFP4` | `nvidia/Qwen3.6-35B-A3B-NVFP4-thinking` | ON (acotado a `thinking_token_budget`) | tareas complejas que requieren pensar |

El gateway normaliza cualquier alias al `SERVED_MODEL` (`llm-gateway.py`), pero ANTES
lee el sufijo (`-normal`/`-fast` → thinking OFF, `-thinking*` → thinking ON). El model
id pelado (sin sufijo) cae al default del servidor = thinking OFF. Por eso el sufijo
es lo que distingue el modo, no el alias visible de opencode.

### 5.-1 Flota de modelos con nombre (branding, 2026-11-01)

Desde 2026-11-01 el picker de opencode (`/models`) muestra la flota con NOMBRES DE
MARCA (decisión del owner: nombres tipo "Using a Victoria"/"Coding con Victoria", sin revelar model
ids técnicos). Los ids reales enviados al gateway son los mismos de siempre — el
branding es solo presentación en `opencode.jsonc` (AMBOS hosts, backups
`opencode.jsonc.bkup-20261101-branding`).

**Política de flota (decisión owner)**: LOCAL primero; la nube SOLO como último
recurso (sesiones >220K de contexto, tareas que desbordan la GPU, o caída del
stack local).

| Nombre en picker | Provider | Model id real | Qué es | Cuándo usar |
|---|---|---|---|---|
| **Using a Victoria** | vllm (local) | `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` | Generalista VLM 35B, thinking OFF | DEFAULT — chat, coding diario, visión (imágenes/video), agentes |
| **Thinking con Victoria** | vllm (local) | `nvidia/Qwen3.6-35B-A3B-NVFP4-thinking` | Mismo modelo, thinking ON (budget 2048) | Lógica sutil/planificación que requiere razonar. **5-6x más lento (~20s vs ~3-4s, validado 11-01)**; el thinking quema ~2048 tokens ANTES de responder → necesita headroom de output (opencode: 32000 OK). MISMA memoria que Coding (mismos pesos, solo flag por-request) |
| **Coding con Victoria** | vllm (local, on-demand :8001) | `NVFP4/Qwen3-Coder-30B-A3B-Instruct-FP4` | Experto en código 30B (texto only, NO ve imágenes) | Coding pesado/especializado (refactors, SWE agéntico); non-thinking POR DISEÑO (entrenado para actuar, no delibrar); arranca solo (503 warming_up ~90s la 1ª vez); roles admin/coder; **idle = 0 RAM** (auto-stop 30 min) |
| `deepseek-ai/deepseek-v4.1-flash` (nombre natural) | nvidia (NIM) | ídem | Nube 1M ctx, reasoning | Último recurso: contexto >220K o stack local caído |
| `z-ai/glm-5.3-flash` (nombre natural) | nvidia (NIM) | ídem | Nube 1M ctx, reasoning | Ídem (alternativa — redundancia gratis: si una falla, la otra) |
| `nvidia/nemotron-3-ultra-550b-a55b` (nombre natural) | nvidia (NIM) | ídem | Flagship NVIDIA nube, 1M ctx, tool-calling | Ídem (tareas agénticas grandes) |

**Nube SIN marca (decisión owner 2026-11-02)**: los modelos NIM NO son nuestros (no corren
en nuestra GPU, no pasan por nuestro metering) → sin nombres de marca, vienen del catálogo
con su nombre natural. Se eliminó el bloque `models` con marca y el `name` del provider
("Nube de Victoria"). Se MANTIENE `whitelist` (filtro anti-ruido: 3 relevantes de 52) y
los timeouts funcionales (1800s/600s). kimi muerto en NIM — no usar.

**Validación empírica de la flota (2026-11-01, test A/B/C con gateway)**: (1) traza sutil
de Python (recursión + default mutable compartido): Coding 3.0s **MAL** (no trazó el
estado compartido), Thinking 19.1s **CORRECTO**, Coder 3.0s concepto-bien/output-mal.
(2) tarea práctica (slugify con acentos): Coding 3.9s PASS, Thinking 20.5s PASS,
Coder 5.5s PASS. Conclusión: los 3 NO son duplicados — velocidad-default /
profundidad-de-razonamiento / especialista-agéntico. **Memoria: CERO desperdicio** —
Coding+Thinking comparten contenedor/pesos/KV (thinking = flag por-request), Coder
on-demand (0 RAM idle, ~13G delta activo, renders esperan por árbitro).

**Notas**:
- `provider.nvidia.whitelist` limita el auto-descubrimiento de NIM a esos 3 (antes
  el picker mostraba 48 de ruido). Campo oficial de opencode (docs /docs/providers).
- kimi-k2.6/kimi-k3 MUERTOS en NIM (deprecated/EOL 2026-10-15) — no usar; el slot
  "Agente" lo ocupa nemotron-3-ultra.
- Los costos de nube figuran $0 (llaves NIM gratuitas); el metering real lo lleva NVIDIA.
- Timeout del provider nvidia: 1800s header + 600s chunk (modelos de razonamiento
  tardan >5 min en el 1er byte; ver §5.0).

### 5.0 Compaction y timeouts del provider (audit 2026-09-03)

**Compactación** (`opencode.jsonc` nivel raíz):
```jsonc
"compaction": { "auto": true, "prune": true, "reserved": 10000 }
```
- `auto: true` — compacta la sesión automáticamente al llenar el contexto
  (también es el default de opencode; lo fijamos explícito). El trigger usa
  `limit.context: 220000` y un buffer `reserved: 10000` (explícito) para que la
  llamada de summarización quepa en el límite del gateway (220K) sin excederlo.
- `prune: true` — elimina **outputs viejos de tools** (lecturas de archivos,
  salidas bash) para ahorrar contexto conservando los recientes. Reduce mucho
  la frecuencia de compactación en sesiones largas de coding.
- `cost: {input 0.10, output 0.30}` en los modelos vllm — opencode calcula y
  muestra el gasto en USD ("spent") con los mismos precios del gateway ($/1M).

**Conteo de tokens/contexto (fix 2026-09-07)**: el gateway reenvía el chunk SSE
`usage` (`choices:[]` + `usage`) al cliente en streaming. Antes lo consumía y
opencode veía 0 tokens / sin % de contexto / sin autocompact. Junto con el
autocompact, esto es el ciclo completo: mide contexto → compacta al acercarse al
límite → reenvía el historial ya compactado (que cabe en 120K).

**Timeouts del provider** (`provider.*.options`):
El option `timeout` de opencode es el **header-timeout** (tiempo hasta los primeros
bytes del provider) — default 300000ms (5 min). El provider `nvidia` (NIM, GLM/DeepSeek/Kimi)
lo lleva desde 2026-10-01 noche en `1800000` (30 min) + `chunkTimeout 600000` + `maxRetries 3`
EN AMBOS HOSTS: con modelos de razonamiento pesado (ej. glm-5.3 variant max) y contextos
grandes, NIM tarda >5 min en el primer byte → `ProviderHeaderTimeoutError` a los 300s →
**opencode MATA el run completo** (el agente "se frena incluso en auto" — forense 2026-10-02:
5 kills por glm-5.3, 7 por kimi-429/muse-spark rate-limits, 0 del local).

```jsonc
"timeout": 3600000,      // 1h: una generación de 32000 tokens a ~40-50 tok/s
                         // tarda 640-800s; el default opencode (300s) podía
                         // cortarla. Cadena aguanta: gateway httpx 3600s,
                         // nginx proxy_read_timeout 86400s.
"chunkTimeout": 600000   // 10 min sin un chunk SSE = conexión muerta (hang real)
```

**Sampling defaults**: vLLM aplica los del `generation_config.json` del modelo
(`temperature 1.0, top_p 0.95, top_k 20` — recomendación de fábrica NVIDIA) salvo
que el cliente mande los suyos. Verificado en logs del contenedor.

**Sampling por rol de agente (2026-10-03, doctrina flota — validada contra la
model card oficial nvidia/Qwen3.6-35B-A3B-NVFP4: SciCode/coding se evalúa a
`temperature 0.6, top_p 0.95`; benchmarks generales a `1.0, top_p 0.95`)**: los
agentes opencode fijan `temperature` en el frontmatter según su rol —
creativos/dev a `0.6 + top_p 0.95`, infra/operacionales a `0.1` (determinismo
para tool-use/APIs/servicios), primarios orquestadores `0.2` (kalimete) /
`0.6 + top_p 0.95` (Victoria, coding+orquestación). Aplica en AMBOS hosts
(kalimete: 12 creativos + 7 infra + kalimete 0.2; victoria: Victoria + Meta
Business + Sonic a 0.6/0.95, los otros 8 subagentes a 0.1). Sin frontmatter, el
request sale sin temperature y vLLM usa el default del modelo (1.0).

### 5.1 Sobre las "variantes de razonamiento" (modo thinking)

**Hallazgo verificado (2026-08-14)**: el chat template de
`nvidia/Qwen3.6-35B-A3B-NVFP4` **solo soporta `enable_thinking` (booleano)**. NO
existe `thinking_level` ni `thinking_budget` en el template (confirmado leyendo
el `chat_template` con `AutoTokenizer` y empiricamente: `low`/`medium`/`high`
producen output byte-idéntico, todos saturan 150 tokens pensando; solo `none`
difiere).

**Estados actuales (actualizado 2026-09-13 — thinking OFF por defecto)**:
- El servidor vLLM arranca con `--default-chat-template-kwargs '{"enable_thinking": false}'`
  → **TODO cliente responde rápido SIN razonar por defecto** (antes el template
  activaba thinking por defecto y opencode mandaba el model id pelado → pensaba
  32K tokens; ese era el "se queda thinking" lento).
- **Thinking opt-in**: sufijo `-thinking` en el model id → `enable_thinking=true`;
  `reasoning_effort != none/minimal` → `enable_thinking=true`; o
  `chat_template_kwargs.enable_thinking=true` directo. El gateway inyecta
  `thinking_token_budget` (default 2048) para acotar el razonamiento.
- Alias opencode: **`-normal`** (id `...-normal`, thinking OFF, default recomendado)
  y **`...-thinking`** (id `...-thinking`, thinking ON acotado). El model id pelado
  (sin sufijo) ahora = thinking OFF (default del servidor).
- Los sufijos `-thinking-low/medium/high/max` se siguen aceptando pero todos
  equivalen a thinking ON (no hay niveles reales).

Si en el futuro la plantilla del modelo añade `thinking_level`/`thinking_budget`,
reactivar las variantes en `opencode.jsonc` con los kwargs nativos de la
plantilla (ver `nvidia/Qwen3.6` chat template).

Forma explicita (preferida cuando se quiere forzar): pasar
`options.chat_template_kwargs.enable_thinking` desde el cliente; el gateway y
vLLM respetan el `chat_template_kwargs` enviado por el cliente sin tocarlo.

### 5.2 Escenarios de conexion (local / LAN / publico)

El gateway FastAPI escucha en `0.0.0.0:8010` pero el **panel admin (`/admin/*`)
es LAN-only** (middleware `llm-gateway.py:402-409` rechaza质 `CF-Connecting-IP`
o IP fuera de `127.0.0.1`/`::1`/`10.*`). La API `/v1/*` y `/health`/`/models`
no tienen filtro de red (solo API key). Elegir el `baseURL` segun el escenario:

| Escenario | `baseURL` opencode | Notas |
|---|---|---|
| **Mismo host** (opencode corriendo aqui) | `http://127.0.0.1:8010/v1` | Actual del `opencode.jsonc`. Mas rapido (loopback). |
| **LAN** (otra maquina dentro de `10.*` o `victoria.local`) | `http://victoria.local:8010/v1` o `http://<ip-lan>:8010/v1` | El panel admin `/admin` tambien abre desde LAN. API via key. Ej: la maquina del usuario `warcold` o el propio `warcold` con su key readonly. |
| **Publico / Internet** (fuera de la red) | **NO RECOMENDADO** sin tunel seguro | El gateway no tiene TLS ni proteccion contra bots. Para acceso publico, exponer detras de un reverse proxy con mTLS/Tailscale/Cloudflare Tunnel y filtrar el panel admin a LAN-only. La API `/v1/*` puede salir pero con HTTPS y rate-limit duro (la API key viaja en `Authorization: Bearer`). |
| **Sandbox nemoclaw** (interno del proxy OpenShell) | `inference.local:443` (proxy) → `host.openshell.internal:8000` | Lo usa el agente OpenClaw; ruta interna, no para opencode humano. |

**Cambio recomendable en `opencode.jsonc` para acceso LAN desde otra maquina**
(ej. para `warcold` o para una laptop siguiendo `warcold` via SSH):

```jsonc
"options": {
  "baseURL": "http://victoria.local:8010/v1",   // o http://10.0.0.X:8010/v1
  "apiKey": "vllm-key-<...>"                    // key correspondiente al rol
}
```

Para el **usuario `warcold`** (rol `readonly`, key `vllm-key-db13590a…`), ver
seccion 7.1. Para conectar desde internet, levantar primero HTTPS + auth fuerte.

**Limites**: `context: 220000`, `output: 32000`. El vLLM sirve 262144 reales
(flag `--max-model-len`, 256K NATIVO + seqs 3 desde 2026-10-01; historia 256K→160K→192K→256K); opencode usa 220K
(220K+32K=252K < 262144, ~10K de margen). El gateway aplica un límite de prompt de 220K
(`MAX_PROMPT_TOKENS=220000`) igual para todos los roles + guarda combinada 260144:
excederlo → 400 `prompt_tokens_exceeded` ANTES de tocar vLLM. La lentitud de un
prompt grande se mitiga con prefix-caching (~90% hit) — no se baja el tope para
no sacrificar sesiones profundas. `output` 32000 para reducir cortes por
`finish_reason: length` en respuestas largas de coding — vLLM lo permite,
opencode no lo limita por defecto.
Fuente de verdad: `vllm-models.ts:292-348` (receta canónica) + override 160K/12GiB/4seqs (2026-09-29).

**Capabilities / modalidades**: `tool_call: true` (parser `qwen3_xml` de
vLLM), `reasoning: bool` (binary; thinking ON/OFF), `attachment: true`.
`input: ["text", "image", "video"]`, `output: ["text"]`.

Este modelo **SÍ es VLM** (Vision Language Model) nativo: la arquitectura
`Qwen3_5MoeForConditionalGeneration` incluye `vision_config` (depth 27,
hidden 1152, 16 heads, RGB) + tokens `<|vision_start|><|image_pad|>
<|vision_end|>` y `<|video_pad|>` (token ids 248053-248057). vLLM carga la
vision tower al arranque (log: `mm_encoder_attention.py FlashAttn for
MMEncoderAttention`, `Encoder cache budget 16384 tokens, profiled with 1
image items`). Acepta `content[].{type: image_url|video_url}` vía la
OpenAI Vision API. Verificado `POST /v1/chat/completions` con PNG rojo 8x8
→ `"rojo"`, HTTP 200, `finish_reason: stop`. En opencode usar
`attachment: true` + `modalities.input` con `"image"` y `"video"`.

El campo oficial del schema de opencode para esto es **`modalities`**
(`https://opencode.ai/config.json`), no `capabilities`. Junto con
`modalities` también son válidos: `attachment`, `tool_call`, `reasoning`,
`temperature`, `interleaved`, `cost`, `limit`, `status`, `experimental`,
`provider`, `options`, `headers`, `variants`. La versión anterior usaba un
`capabilities: {tools, input, output}` no-oficial — descartado en favor de
los campos oficiales del schema.

### 5.3 Plugin `nvapi-autorotate` — auto-rotación de llaves NVIDIA ante rate limit (2026-09-07)

Plugin GLOBAL (`~/.config/opencode/plugins/nvapi-autorotate.js`, auto-carga, cero deps):
ante `session.error` con firma NIM (`Too Many Requests` / `"status":429` / `nvapi`+401/403/429)
ejecuta `nvapi-rotate.sh auto` (cooldown 10 min entre rotaciones). Sin auto-reintento del
prompt — el usuario reintenta y el request ya sale con la llave nueva (`opencode run` y sesiones
nuevas leen `auth.json` fresco; en TUI de larga vida abrir sesión nueva si no toma el cambio).
Solo actúa con firma NIM (ignora errores del vLLM local); silencioso en máquinas sin el sistema
de rotación. Detalle fino: el error llega con comillas escapadas, el plugin normaliza backslashes
antes de matchear. Ver CHANGELOG 2026-09-07 13:20.

## 6. Subagentes opencode disponibles

Viven en `~/.config/opencode/agents/` y son `mode: subagent` ( invoco via Task
tool desde el agente primario). Documentacion completa en cada `.md`.
**Frontmatter obligatorio**: todo subagente lleva `name:` + `description:` +
`mode: subagent` (`name` es el id de invocación — verificado 2026-10-01 con
`opencode agent list`: el archivo `meta-business.md` con `name: Meta Business`
resuelve como `Meta Business`; el filename NO es el id).
**Archivos siempre en minúsculas** (`vllm.md`, `openclaw.md`, …): Linux es
case-sensitive y las mayúsculas en filenames causan errores al tipear rutas.
**NO usar symlink `agent` → `agents/`** (eliminado 2026-10-01: opencode 1.18
escanea ambas grafías y el symlink duplicaba agentes — aparecían
`victoria (all)` fantasma + `OpenClaw (all)` con modo corrupto).
Instructions del host: `~/.config/opencode/AGENTS-summary.md` (slim, ~5K
tokens) en vez del AGENTS.md completo (195KB = ~57K tokens que compactaba
a los 100K — fix 2026-09-30). El manual completo se lee con Read bajo demanda.

| Subagente | Cubre | Archivo |
|---|---|---|
| `Comfyui` | ComfyUI (generación de contenido visual): modelos, custom nodes, workflows, proxy nginx, GPU compartida con vLLM. | `agents/comfyui.md` |
| `vLLM` | contenedor vLLM + gateway 8010 (levantar, diagnosticar, reiniciar) | `agents/vllm.md` |
| `OpenClaw` | sandbox OpenClaw, rutas inference.local, opencode.jsonc | `agents/openclaw.md` |
| `Weather` | Clima (Open-Meteo, wttr.in, weather.gov), geocodificación (Nominatim, Open-Meteo geocoding, country.io), POIs (Overpass API), datos de países. APIs públicas gratuitas sin API key. | `agents/weather.md` |
| `RSS System` | BlogWatch - monitoreo de feeds RSS/Atom. CLI blogwatcher compilado desde fuente Go, 14 feeds activos. Plan de distribución de feeds por canal Discord. Policies OPA rss-feeds v13. | `agents/rss-system.md` |
| `Meta Business` | Gestión de redes sociales (Instagram, Discord, WhatsApp). Operación de scripts broadcast, cron de publicación, refresh token IG, salud de webhooks y logs de distribución. | `agents/meta-business.md` |
| `Sonic` | Podcast con voz (Sonic talking-head + reels). | `agents/sonic.md` |
| `CloudFlare` | Túnel Cloudflare + nginx + SSH/warcold (red y acceso). | `agents/cloudflare.md` |
| `Liveportrait` | LivePortrait talking-head :8180 (WebUI ES + tab Podcast-UI). | `agents/liveportrait.md` |
| `Gpu` | GPU GB10 (guardián + árbitro + térmica + VRAM/OOM). | `agents/gpu.md` |
| `Coder` | Ejecutor de código pesado — corre pineado al modelo Coding con Victoria (Qwen3-Coder-30B, SWE agéntico). Delegar implementación cuando la sesión primaria ya tiene el plan/todowrite. | `agents/coder.md` |

Cualquier cambio en la arquitectura debe reflejarse en este `AGENTS.md` y en el
subagente correspondiente. **No duplicar**: el subagente provee el prompt
operativo, este archivo provee el mapa global.

## 7. API keys del gateway

La DB SQLite en `~/.victoria-llm/llm-gateway.db` mantiene las keys. Consultar sin exponer el plaintext:

```bash
sqlite3 ~/.victoria-llm/llm-gateway.db \
  "SELECT id,name,owner,role,active,total_requests,last_used FROM api_keys ORDER BY id;"
```

Keys conocidas (prefijo solo, no usar el plaintext aqui):
- `vllm-key-811…` → name `victoria` (admin) — usada por `opencode.jsonc`
- `vllm-key-5d4…` → name `alfredo` (admin)
- `vllm-key-434…` → name `juancarlos` (coder)
- `vllm-key-db1…` → name `warcold` (readonly) — acceso read-only desde otra maquina

Roles (router único 2026-09-16 — matriz rol×capacidad en `ROLE_DEFAULT_MODELS`):
- `admin` → acceso total al panel admin (LAN-only) + API; puede crear/editar/borrar keys.
- `coder` → **solo chat LLM** (Qwen35B) con metering/budget; ve su propio uso via `/v1/usage`. Sin arte, sin panel.
- `services` → **chat LLM + arte** (límites propios por llave). Para agentes/sistemas (openclaw-servicios, broadcasts, video). Sin panel.
- `art` → **SOLO arte** vía ComfyUI por el gateway (`POST /v1/images|videos` + `GET /v1/jobs/{id}` + `/v1/art-files/{f}`). Sin chat LLM, sin panel. Clientes arte usan su ComfyUI/IDE contra estos endpoints sin descargar 300GB de modelos.
- `readonly` → SOLO `/v1/config-guide` + `/v1/catalog` + `/v1/client-config` con su llave. Sin inferencia. (`/health` y `/models` son públicos por diseño: status mínimo y solo el nombre del modelo.)
- Pedir capacidad fuera de la matriz → **403 `model_forbidden`** (role 'X' cannot use 'llm'/'art'). **Multi-tier por llave (2026-10-03)**: columna `allowed_models` (JSON de las 8 capacidades `llm/art/liveportrait/comfyui/tts/whisper/n8n/provision` —`tts` = voz TTS, motor Qwen3-TTS; renombrada desde `xtts` 2026-10-04—; vacío=default del rol) — **editable desde el panel** con checkboxes + presets (crear y editar; badges en la tabla). Añade capacidades a la matriz del rol (ej. `kalimete` = coder + `["llm","art","tts","whisper","provision"]` → chat + imágenes + TTS/STT + provisioning con su propio metering). `sense_auth.py` honra el override: una llave con `art/tts/whisper/liveportrait/comfyui` en sus caps puede usar los sentidos aunque su rol no sea de servicio (`provision` NO eleva — es poder del gateway, no un sentido).
- **vLLM-Coder on-demand (2026-11-01, autorización owner)**: segundo modelo local experto en código — `NVFP4/Qwen3-Coder-30B-A3B-Instruct-FP4` (MoE 30.5B/3.3B activos, NVFP4 18.1G, non-thinking only, parser `qwen3_coder`) en contenedor `nemoclaw-vllm-coder` **:8001 loopback-only, PARADO por defecto**. Flags: `--max-model-len 131072` (128K; opencode manda ~87K de tools+system) + `--kv-cache-memory-bytes 8589934592` (8GiB → pool 174,752 tokens) + `--max-num-seqs 2` + compile cache HOST (`~/.vllm-compile-cache-coder`). **ACCESO: SOLO roles admin/coder** (services/art/readonly → 403 `model_forbidden`). **On-demand**: gateway arranca al 1er request (503 `warming_up` + Retry-After 150; arranque ~70-90s con compile cache, ~11 min la 1ª vez) y `victoria-coder-idle-stop.timer` (5 min) lo detiene tras 30 min idle (45 min con requests en vuelo — regla anti-zombis). **Protecciones**: gate de arranque (sin render activo + RAM ≥20G), guardia RAM en `gpu_arbiter.check_ready()` (`MIN_RAM_FOR_RENDER_GB=30` → renders esperan con coder cargado), válvula RAM 16G→10G solo con coder corriendo, válvula 7 `coder_busy` (prompts ≥40K al generalista con coder cargado → 429; chat pequeño sigue). opencode: entrada `vllm/NVFP4/Qwen3-Coder-30B-A3B-Instruct-FP4` (context 96000, output 22000, **attachment false — el coder NO ve imágenes; la visión es del generalista VLM**). Metering por modelo real. Detalle completo: CHANGELOG-vllm 2026-11-01 + `agents/vllm.md` §Coder.
- **Provisioning delegado (2026-10-20): `POST /v1/provision-key`** — crea llaves de NEGOCIO para armada-suite (chatbots/plugins web de kalimete) sin panel ni `ADMIN_PASS`. Permisos: rol admin O cap `provision` (la tiene `kalimete`). Restricciones DURAS en el servidor: rol fijo `services` + caps fijas `["llm"]` (la llave creada no provisiona ni usa sentidos → cero escalada), nombre forzado a prefijo `armada-<slug>`, máx `PROVISION_HOURLY_LIMIT` (10) creaciones/hora por provisionadora → 429 `provision_rate_limited`, budget/expiry clampeados a `PROVISION_MAX_BUDGET`/`PROVISION_MAX_EXPIRY_HOURS` (0 = sin tope), auditoría en tabla `provision_log` (provisionadora, llave creada, IP, ts) + plaintext devuelto UNA vez. Motivación: 1 llave por negocio = metering aislado + revocación aislada + 2 slots de concurrencia propios (un pico de una tienda no ahoga a las demás). Documentado en `/v1/config-guide` → `provision_api`. Primera llave creada: `armada-magantech` (2026-10-20, desde kalimete 10.0.0.106).
- **Arte por el mismo router** (2026-09-16): TODO el arte pasa por el gateway, igual que el LLM. Endpoints async (202 + poll) porque generar toma minutos. Límites job-based (2 img + 1 video concurrentes globales, 30 jobs/h por llave → 429 `art_busy`/`art_rate_limited` + Retry-After). Metering art por **imagen / segundo-video** (`price_per_image`/`price_per_video_sec`); un job art NO consume tokens del LLM (el gateway solo encola/sondea, milisegundos). nginx solo LAN: `/comfyui/` sirve el ComfyUI crudo, `/liveportrait/` sirve LivePortrait (incluye el tab 🎙️ Estudio Podcast), `/n8n/` el orquestador — el ComfyUI `:8188` bindea solo loopback (`--listen 127.0.0.1`, la LAN no lo alcanza directo). El `/studio/` standalone (`:8190`, Estudio Victoria 2026-09-26) fue **ELIMINADO 2026-09-28** (ver CHANGELOG 2026-09-28 19:20). En público dan 404 — el túnel entra al gateway, que no tiene esas rutas). El arte con metering/reglas sigue por el gateway con llave. ComfyUI `enabled` (auto-arranca tras reboot). Workflows: passthrough dict API-format o template por nombre — **los templates API-format reales viven en `~/.victoria-custom/comfyui-templates-api/`** (`z-image-turbo`, `flux-schnell`, `sd15-realistic`; el gateway los busca PRIMERO — los `.json` de `user/default/workflows/` son shells UI-format sin valores, NO funcionan por API). **Inyección de prompt (2026-10-03)**: `POST /v1/images` acepta `prompt`/`negative_prompt`/`seed`/`width`/`height` y los inyecta en el template vía sampler-tracing (KSampler→positive/negative→CLIPTextEncode; seed aleatorio si no viene). **Árbitro GPU (2026-10-03)**: la art API toma el lock de `gpu_arbiter` (check_ready + acquire + release con sweeper) → arte y Sonic NUNCA solapan; GPU ocupada o ≥80°C → 429 `gpu_busy` + Retry-After. Detalle en `/v1/config-guide` (sección `art_api`).
- **EXCEPCIÓN del router: el cerebro del sandbox OpenClaw** (2026-09-16): su inferencia la posee la plataforma nemoclaw (`models.json` en `agents/main/agent/models.json`, regenerado por el runtime; endpoint `inference.local:443` → proxy OpenShell → `host.openshell.internal:8000` → vLLM directo). NO rutearlo por el gateway: (a) el schema OpenClaw RECHAZA top-level `providers` en openclaw.json (`Unrecognized key` → INVALID_CONFIG → crash-loop del gateway); (b) el netns del node del agente NO alcanza `172.18.0.1:8010` (solo proxy/policies). Su carga es visible en vLLM `/metrics` y la admisión adaptativa reacciona igual. Intento y revert documentados en CHANGELOG 2026-09-16 16:35.

**Límite de contexto (120K — actualizado 2026-09-29, modelo a 160K)**: el
gateway limita el prompt (input) por request (columna `max_prompt_tokens`; `0` =
default global de 220K). El límite se mantiene en **equidad total entre tiers**
(decisión del owner 2026-09-08: "admin también es coder, no quiero discriminación").
El vLLM sirve 256K reales (`--max-model-len 262144` NATIVO + seqs 3, desde 2026-10-01;
historia: 262144 → 160K 09-28 → 192K 10-01 → 256K nativo): 220K prompt + 32K output = 252K (headroom ~10K). La lentitud de un
prompt grande (prefill) se mitiga con prefix-caching (~90% hit) y la protección
de CONCURRENCIA, NO bajando este tope.
- **admin y coder IGUAL**: `max_prompt_tokens=0` (= default global) → **220K** para todos. Un prompt que exceda el límite de su key devuelve **400 `prompt_tokens_exceeded`** ANTES de tocar vLLM. opencode usa **`context: 220000`** (alineado) con compaction auto para mantener sesiones profundas. (2026-09-14: se probó `juancarlos=32000` tras el freeze y se REVERTIÓ el mismo día — un cap bajo rompe el trabajo legítimo. La protección real es CONCURRENCIA, ver abajo.)
- **readonly**: no infiere (solo `/health` + `/v1/config-guide`), irrelevante. (Con su llave también: `/v1/catalog` + `/v1/client-config`; `/models` público.)
- **rate_limit por rol (2026-09-17, verificado en DB)**: admin/coder/services/art → **120/min** (todas las llaves que infieren o generan); readonly → 1000/min (no infieren, irrelevante). Equidad total por decisión del owner: los servicios consumen menos que los humanos (broadcasts 1 call/artículo, video ~5 frames/análisis, pico medido 4/min = 30x de margen) así que 120 les sobra. El default se asigna SOLO por rol al crear (`ROLE_DEFAULT_RATE_LIMIT` en el gateway) — nadie queda con el valor que le toque por olvido.

**Protección real: CONCURRENCIA, no contexto** (2026-09-08 12:00, ampliado
2026-09-14 21:00 con admisión por TOKENS): el colapso lo causaba la
sobre-admisión de prefill (varios prompts gigantes encajados a la vez), no el
tamaño individual. vLLM corre con la receta optimizada para DGX Spark
(256K nativo + seqs 3, 2026-10-01): `--max-num-seqs 4`,
`--max-num-batched-tokens 8192`, `--kv-cache-memory-bytes 12884901888` (12 GiB,
el control REAL del KV en GB10 — `--gpu-memory-utilization` no lo controla con
memoria unificada), MTP speculative (83 tok/s).
El gateway añade **semáforo global** (`UPSTREAM_MAX_CONCURRENCY=3`, = max-num-seqs,
sobre-saturación → **503 `server_busy`**) y **timeouts sanos**.

**Equidad por usuario (2026-09-14)**: el gateway además impone un **límite de
concurrencia por key** (`UPSTREAM_MAX_PER_KEY=2`, default) + cola suave
(`PER_KEY_QUEUE_TIMEOUT=90s`): cada key puede tener como máximo 2 requests
concurrentes — 1 request principal + 1 subagente opencode. La 3ra se encola
hasta 90s; si no se libera → 503 `user_busy`. Esto evita que un usuario
aguante todo el stack (vLLM + GPU) para él solo. Todo ajustable por key
vía `PUT /admin/keys/{name}` (`max_prompt_tokens`/`max_tokens`/`rate_limit`).

**Admisión por TOKENS anti-freeze (2026-09-14 21:30, ampliado 2026-09-15 21:40
con válvula 4)**: el semáforo cuenta requests, pero un prompt de 200K y uno de
2K no cuestan lo mismo. Cuatro válvulas (todas 503/429 con mensaje claro, el
cliente reintenta — nunca se congela):
1. `UPSTREAM_MAX_PREFILL_TOKENS=300000`: presupuesto global de prefill
   concurrente (tokens estimados en vuelo) → 503 `prefill_busy`. Verificado en
   vivo: 2×160K concurrentes → uno 200, otro 503.
 2. `UPSTREAM_MAX_TOKENS_PER_MIN=4000000` por key (ventana 60s) → 429
    `token_rate_limited`. (Historia: 5M → 8M el 2026-09-15 22:05 → 4M como red
    secundaria tras la válvula 4b. 2x el pico legítimo máximo medido 2.47M/min.)
 3. `SYSTEM_MEM_MIN_AVAILABLE_GB=16`: si la RAM unificada baja de 16GB → 503
    `system_overloaded` para todos. Todo vía env, documentado en `/v1/config-guide`.
4. `UPSTREAM_LARGE_PROMPT_THRESHOLD=80000` + `UPSTREAM_LARGE_PROMPT_MAX_PER_MIN=4`:
   máximo 4 prefills de 80K+ tokens/minuto por key → 429
   `large_prompt_rate_limited`. Cierra el hueco de las válvulas 1-3 (que miden
   VOLUMEN): el freeze del 2026-09-15 19:17 vino de RITMO (150K cada ~5s x2min =
   1.8M/min, dentro de todos los topes, GPU al 100% en prefill continuo hasta
   colgar el host sin logs). Admin la salta (decisión del owner).
   **Flexibilizado 2026-09-15 22:05 → threshold 100000, 6/min**: el 80K/4
   rozaba ráfagas legítimas de vibe coding (P50 juancarlos = 72K); el loop
   asesino (150K cada 5s = 12/min) sigue muy por encima del tope.
   **Igualdad total 2026-09-15 22:10**: el bypass de admin se ELIMINÓ por
   decisión del owner — admin es acceso (panel/keys), no privilegio de
   inferencia; todos somos coders bajo las mismas 4 válvulas.
   **Válvula 4b 2026-09-15 23:15** (intervalo mínimo, la protección REAL):
    prefills de 40K+ requieren ≥15s desde el anterior admitido (misma key,
    todos los roles) → 429 `large_prompt_rate_limited` + `Retry-After` DINÁMICO
    (2026-09-16, antes fijo 60: espera exacta 1-60s + `retry_after_s` en el JSON).
   Nació de un freeze provocado por stress test propio (86 reqs de 35-60K en
   6 min, 1.5M tokens, TODO bajo los topes 100K/6 y 8M → host colgado igual):
   el conteo es ciego a ametralladoras medianas; el intervalo fuerza el
   respiro de GPU. Knobs: `UPSTREAM_LARGE_PROMPT_MIN_GAP_THRESHOLD=40000` (ojo:
   el nombre exacto del env lleva el sufijo `_THRESHOLD`),
   `UPSTREAM_LARGE_PROMPT_MIN_INTERVAL=15.0`. Volumen bajado 8M→4M como red
   secundaria. REGLA: jamás stress con prompts reales en producción.
   **ADMISIÓN ADAPTATIVA 2026-09-16** (limitar por contención, no por reloj):
   el gateway muestrea vLLM `/metrics` cada 2s (running/waiting/KV) y publica
   FRÍO/CALIENTE en `/health.engine`. En FRÍO solo techos anti-bug laxos
   (12M tokens/min, 18 grandes/min, prefill 600K en vuelo); en CALIENTE o con
   4+ corriendo, los estrictos de arriba. El intervalo 4b es 15s SIEMPRE pero
   en FRÍO permite RÁFAGA DE 2 (principal+subagente simultáneos; en CALIENTE
   ráfaga 1 = legado). Verificado en vivo: 2×42K a 1s → 200/200, 3ro → 429
   en ms. Observabilidad: `usage_log` guarda `reject_reason/approx_tokens/
   eng_running/eng_waiting/eng_kv` en cada fila (el 400 también deja fila).
    Reversible con `ADAPTIVE_ADMISSION=0`. Contexto 220K intacto; fast path sin
    latencia agregada (poller background, lecturas atómicas).
    **Retry DINÁMICO + medición honesta + costo efectivo 2026-09-16**: los 429
    devuelven la espera exacta (header `Retry-After` + `retry_after_s`, típico
    3-14s, antes fijo 60); el `approx` CUENTA `tools` (antes 68K vs 119K reales);
    el ritmo y la reserva usan el costo EFECTIVO tras prefix-cache (mismo prefijo
    = |delta|+15% piso 25%; contenido nuevo paga completo por head-hash).
     Verificado: 4×150KB mismo prefijo → 4×200 en ~1s c/u (prefill real 5.2s solo
     el 1ro). El volumen/min y el cap de prompt usan el total.
   **Válvula 5 2026-10-14** (carga sostenida, forense freeze 2026-10-13 19:00):
     el engine poller trackea el CICLO DE TRABAJO continuo: si `running≥1` sin
     pausas durante `SUSTAINED_LOAD_MINUTES` (10) seguidos → cada key (todos
     los roles) necesita `SUSTAINED_LOAD_MIN_GAP` (8s) entre admisiones →
     429 `sustained_load_rate_limited` + Retry-After; se libera sola tras
     `SUSTAINED_LOAD_IDLE_RELEASE` (45s) de motor idle; el request en vuelo
     NUNCA se interrumpe. Nació del freeze real 2026-10-13 (sesión agéntica
     47 reqs ctx 79K→150K, GPU 94-95% por 12+ min → host congelado; las
     válvulas 1-4 son ciegas al deber continuo porque el prefix-cache hace
     cada request "barato" en papel). Problema de plataforma conocido:
     NVIDIA container-toolkit#1910 (sin fix upstream). Reversible:
     `SUSTAINED_LOAD_GUARD=0`. Observabilidad: `/health` →
     `engine.sustained{guard,active,busy_minutes,min_gap_s}` + alerta
     WhatsApp al owner al activarse. Espejo en el gpu-saver: watchdog
     duty-cycle (≥80% de muestras con util ≥85% en ventana 10 min) → alerta
     WA + fallback Discord si WA falla 2x (ver `gpu.md`).


**Alertero anti-loop por niveles (2026-09-17)**: `vllm-loop-alert.py`, cron `*/15`,
vigila rechazos de TODAS las llaves en ventana 15 min y avisa por WhatsApp DM al
owner (18295468686): L1 AVISO ≥10 (recordatorio 4h), L2 LOOP ≥50 (recordatorio 1h),
L3 CRITICO ≥150 (recordatorio 30min + consejo de matar sesión y revisar GPU/RAM).
Si el nivel SUBE, avisa de inmediato sin esperar cooldown; si el loop termina
(0 rechazos), limpia el estado (`~/.victoria-custom/state/loop-alert.json`) y lo
deja en el log (`~/logs/loop-alert.log`). Solo ojos: no bloquea nada (el que frena
es el gateway con 429). Ojo histórico: la ventana se rompió una vez comparando
TEXT contra epoch (siempre TRUE → spam horario de un loop ya muerto); fix 2026-09-17
09:10 a `datetime('now',?)`, verificado silencioso. **Heartbeat diario (2026-09-20)**:
1 línea/día "monitor vivo" (`_hb_ts` en state) — la ausencia de heartbeat >24h
significa que el alertero murió (dead man's switch).

**Detección de anomalías en TIEMPO REAL (2026-09-20)**: el propio gateway
(`llm-gateway.py`) detecta y registra los loops EN VIVO (no espera al cron). Motivación
forense: el 2026-09-20 10:21 un cliente ametralló 50 requests fallidos en 6s contra
el vLLM en ventana de arranque — las válvulas de volumen lo frenaron, pero NADIE lo
vio (49 filas 502 mudas con `reject_reason=''`; el cron contó 1 solo rechazo).
Cinco piezas (todas reversibles por env, backup `llm-gateway.py.bkup-20260920-anomalias`):
1. **Flight recorder (caja negra)**: ring en memoria (300 req); al dispararse una
   anomalía → dump completo a `~/.victoria-llm/forensics/anomaly-<key>-<ts>.json`
   (ring + engine snapshot + razones; retención 14 días). La respuesta a
   "después no sabemos qué pasó".
2. **Detección de burst en vivo**: ≥`ANOMALY_BURST_COUNT` (10) fallos de una key en
   ≤`ANOMALY_BURST_WINDOW` (30s) → fila en tabla `anomaly_events` + dump + **alerta
   WhatsApp INMEDIATA** desde el gateway (hilo background, cooldown 900s/key). El
   cron loop-alert queda como sweeper de respaldo L1/L2/L3.
3. **Circuit breaker**: tras el burst → cooldown `CIRCUIT_BREAKER_COOLDOWN` (60s)
   con `429 circuit_breaker` + Retry-After; auto-cura al expirar. Sus propios
   rechazos NO cuentan como fallos (sin auto-perpetuación).
4. **warming_up**: el engine-poller marca vLLM `down` tras 3 polls sin /metrics
   (~6s; arranque o crash) → chat/completions responde `503 warming_up` con
   `Retry-After: 120` en vez de quemar connect-timeout por intento.
5. **Taxonomía de fallos**: los 502/timeout de upstream ahora dejan `reject_reason`
   clasificado (`upstream_unavailable/timeout/protocol/error`, `server_busy`,
   `upstream_warming_up`, `upstream_http_XXX`) + columnas `head_hash`/`stream` en
   `usage_log` (forense por-request).
Env: `ANOMALY_DETECT`, `CIRCUIT_BREAKER`, `ANOMALY_BURST_COUNT/WINDOW`,
`CIRCUIT_BREAKER_COOLDOWN`, `ANOMALY_ALERT_COOLDOWN`, `WARMUP_RETRY_AFTER`,
`FLIGHT_RING_SIZE`. Observabilidad: `/health` expone `engine.down` +
`anomalies{titulo,timestamp_reporte,today,ultima_alerta,historial[5]{timestamp,descripcion,num_errores}}` (2026-09-21: `last`→`ultima_alerta`+`historial`, `ts`→`timestamp`, `count`→`num_errores` + traducción ES + título y hora del reporte) + `circuit_open`; `/admin/anomalies` (LAN) lista eventos;
CLI `~/.victoria-custom/bin/anomalies [today|last|fails|forensics|storms]`.
Verificado E2E 2026-09-20: burst de 15 req → breaker en el #10 exacto, dump + fila
+ WhatsApp real + auto-cura a los 60s + 200 OK posterior.

Admin panel: `ADMIN_PASS` default `victoria-admin` (SHA256). Para resetear, parar
gateway y reiniciar con `ADMIN_PASS=nueva python3 llm-gateway.py`.

**Creación de llaves simplificada (2026-08-19)**: la UI del admin panel (y el
endpoint `POST /admin/keys`) solo requiere **Nombre** (`owner`) + **Tier** (`role`:
admin/coder/services/art/readonly — ver matriz rol×capacidad arriba). Los parámetros técnicos se asignan con defaults seguros y
se pueden ajustar después en el perfil de la llave (`PUT /admin/keys/{name}`):
- `max_tokens=32000` (output estándar de diseño; el clamp del gateway protege el límite real)
- `max_prompt_tokens=0` (= default global `MAX_PROMPT_TOKENS=220000` para todos los roles, sin distinción)
- `rate_limit` = default por rol (`ROLE_DEFAULT_RATE_LIMIT`: todos los que infieren/generan 120, readonly 1000), `price_input_per_1m=0.10` $/1M, `price_output_per_1m=0.30` $/1M, `budget=0` (ilimitado), `expires=0` (nunca)

**Precios v3 (2026-08-30) — recalibrados a costo real de producción**:
- Input $0.10/1M tokens, Output $0.30/1M tokens (estándar industria: output 3x).
- Costo real de producción medido: ~$0.0253/1M (hw DGX Spark $2.40/día + elec
  180W@$0.20 $0.86/día ÷ 129M tok/día). Precio v3 = costo + margen 4-12x, alineado
  con mercado MoE 35B (Qwen3-30B $0.18-0.50/1M, DeepSeek-Flash $0.22-0.44 in / $0.66-1.32 out).
- El precio viejo de $0.02/1k ($20/1M) estaba 791x sobre costo y NO se usaba bien
  porque el metering de streaming no registraba tokens (ver CHANGELOG 2026-08-30 04:20).

**Metering streaming (v3, 2026-08-30)**: el gateway inyecta `stream_options.include_usage=true`
y parsea el chunk SSE final con `usage` de vLLM → los tokens de streaming (el 99.97% del
tráfico) SÍ se cuentan y facturan. El chunk de usage se consume (no se reenvía al cliente).
Antes del fix, todo el tráfico streaming registraba 0 tokens y los balances estaban ~1000x
por debajo de la realidad.

**Streaming real (2026-08-19)**: el gateway usa `StreamingResponse` y propaga los
chunks de vLLM en vivo (`aiter_bytes`) — no bufferiza la respuesta completa. Esto
evita que generaciones largas se corten por timeout de red (nginx `proxy_read_timeout`
86400 en el location `/` del gateway, `proxy_buffering off`). El cliente recibe
data continua mientras el modelo genera; la generación NO se corta a mitad de
tareas complejas (ej. listas `todoWrite`).

## 7.1. Usuario `warcold` — acceso SSH read-only

Usuario del sistema creado para consultar la documentacion/config del stack
desde otra maquina (via SSH) sin poder alterar nada. Pensado para mantener
opencode en hosts remotos alineado con la configreal del servidor.

| Aspecto | Valor |
|---|---|
| Usuario | `warcold` |
| Password | `colador` (rotar en producción) |
| Shell | `/bin/rbash` (restricted bash) |
| Grupo lector | `vllm-readers` (read-only sobre archivos del proyecto) |
| API key gateway | name `warcold`, rol `readonly`, key `vllm-key-db13590a…` — acceso con su llave a `/v1/config-guide` + `/v1/catalog` + `/v1/client-config` (NO puede inferir ni ver `/v1/usage`; `/health` y `/models` son públicos: status mínimo + nombre del modelo) |
| sudo | **NO tiene** (solo puede ejecutar `sqlite3ro_real` como victoria) |

**Lo que warcold PUEDE hacer:**
- SSH al host y leer (cat/less/grep) los archivos del proyecto:
  `AGENTS.md`, `llm-gateway.py`, `admin_template.html`,
  `~/.config/opencode/opencode.jsonc`, `~/.config/opencode/agents/*.md`.
- Consultar la DB del gateway en modo read-only via el wrapper `sqlite3ro`
  (bloquea columnas `key_plaintext`/`key_hash` y `SELECT *`).
- Ver `/health` y `GET /v1/config-guide` con su key (`/health` con llave da estado + métricas, sin llave solo status; `/v1/config-guide` devuelve guia de configuracion sin secretos).

**Lo que warcold NO puede hacer:**
- Editar, borrar o crear archivos del proyecto (permisos `640 victoria:vllm-readers`).
- Acceder al panel admin (`/admin/*`) — requiere password `victoria-admin` + LAN.
- Ver las API keys secretas de nadie (ni via DB, ni via `strings`, ni via sudo).
- Hacer `sudo` (excepto ejecutar `sqlite3ro_real` como victoria, sin terminal).
- Cambiar de directorio con `cd` (rbash lo bloquea).
- Redirigir salida con `>` o `>>` (rbash lo bloquea).
- Hacer inferencia (chat completions): su key `readonly` solo permite `/v1/config-guide` + `/v1/catalog` + `/v1/client-config` (+ `/health` y `/models` públicos).

## Servicio de Voz (voice-server) — Protegido con API Key + IP Filtering (2026-08-19, unificado 2026-09-17)

El servicio de voz vive en el puerto `18810` (host, no Docker). **Antes era publico** (cualquiera podia hacer TTS/STT). **Ahora tiene doble blindaje**:

### 1. Autenticacion con API Key (llaves gateway admin/services, DB viva)
- CUALQUIER endpoint requiere `Authorization: Bearer <key>` O `X-API-Key: <key>` con rol `admin` o `services` del gateway :8010 (validado contra la DB viva vía `sense_auth.py` — ya no hay hashes hardcoded que se pudran al rotar).
- Sin key valida: `401 Unauthorized`; llave de otro rol (coder/readonly): `401`.
- **Compat sin llave SOLO desde localhost + red docker** (wrappers internos del sandbox: tts-bridge.py, victoria-tts, whisper-cli). Desde LAN 10.x la llave es obligatoria (kalimete-ptt ya manda `Bearer`, verificado compatible).

### 2. Filtro de Red (Solo LAN + localhost + docker)
- Acepta `127.0.0.1` (localhost), red docker `172.16/12` (sandbox) y `10.x.x.x` (LAN domestica)
- Cualquier otra IP → `403 Forbidden`
- **IPv6**: reglas `ip6tables DROP` en puerto 18810 (igual que :8000 para vLLM)
  - Regla activa: `ip6tables -I INPUT 1 -p tcp --dport 18810 -j DROP`
  - Persistida en: `/etc/iptables/rules.v6` (aplicada por `netfilter-persistent.service` enabled)
  - Validacion post-reboot: `sudo ip6tables -L INPUT -n | grep dpt:18810` → debe mostrar la regla DROP
- **Acceso desde Internet: NUNCA** — no se puede exponer sin riesgo (no hay TLS)
- Acceso desde LAN domestica (10.* o victoria.local) → OK, no requiere VPN

### Endpoint de Descubrimiento (para clientes externos en LAN)
```bash
# Desde una maquina en la red local:
curl -s -H "Authorization: Bearer <admin-key>"   http://10.0.0.X:18810/voice/config-guide
```

Esto devuelve JSON con: hosts (localhost/LAN), autenticacion necesaria, endpoints disponibles (/tts, /stt, /health), y restricciones de red.

### Endpoints del servicio de voz
| Endpoint | Método | Uso | Respuesta |
|---|---|---|---|
| `/health` | GET | Verificar que el service está arriba | JSON: ok, uptime_s, engine (qwen3), tts_loaded, whisper_loaded, voices, auth_required |
| `/tts` | POST | Text-to-Speech con Qwen3-TTS (clonación ICL, único motor) | WAV binario (audio/wav, mono 24kHz, 16-bit PCM) |
| `/stt` | POST | Transcription de audio con Whisper. **`?language=es` opcional (2026-10-20)**: fija el idioma del audio (ISO 639, 2-3 letras) y evita que Whisper-small alucine idiomas en clips cortos (árabe/ruso/francés). Sin el param = auto-detección (backwards-compatible: sandbox whisper-cli, video-server y demás consumidores no cambian). Inválido → 400 `invalid_language` | JSON: `{"text": "... transcripcion ..."}` |

**Nota STT idioma (2026-10-20)**: el fix nació del diagnóstico de doble lado de la sesión kalimete `ses_ea3adda92ffeYshinmCBIwQACd` — el servidor tenía `language=None` hardcodeado (`voice-server-host.py`) y el cliente kalimete-ptt resolvía `PTT_LANGUAGE=es` pero nunca lo enviaba. El servidor ya acepta `?language=`; el cliente kalimete-ptt debe agregarlo a su `PTT_STT_URL` (fix #2 de kalimete, su lado).

**Nota concurrencia TTS/STT (2026-10-21, incidente "no me respondió")**: el server usa **locks SEPARADOS** (`_tts_lock` para Qwen3-TTS, `_stt_lock` para Whisper). Antes un solo `_lock` serializaba ambos y el plugin voz-viva de opencode (un /tts por oración de cada respuesta, host sin parlantes) mataba de hambre al /stt del PTT de kalimete (timeout 360s). Además `VICTORIA_VOICE_LIVE=0` en `~/.bashrc` de este host apaga el TTS del plugin (sin parlantes = pura quema de GPU); borrar esa línea si algún día hay parlantes. Verificado: STT responde en ~1.3-1.6s incluso con TTS generando de fondo.

### Ejemplo de uso (TTS desde LAN)
```bash
curl -s -X POST   -H "Authorization: Bearer vllm-key-5d4377..."   -H "Content-Type: application/json"   -d '{"text":"Hola papá, aquí está Victoria","voice":"victoria","language":"es"}'   http://10.0.0.5:18810/tts > output.wav
```

### Ejemplo de uso (STT desde LAN)
```bash
curl -s -X POST   -H "Authorization: Bearer vllm-key-5d4377..."   http://10.0.0.5:18810/stt   --data-binary @audio.wav > transcripcion.json
```

### Models
- **TTS**: Qwen3-TTS-12Hz-0.6B-Base (Qwen/Alibaba, Apache 2.0, ene-2026) — clonación ICL de voz con `ref_audio + ref_text` exacto, salida 24kHz, prompt reutilizable (`create_voice_clone_prompt` una vez), `max_new_tokens=512` por chunk como tope anti-descontrol. Único motor desde 2026-10-03 (XTTS 2G + coqui + fallback eliminados; TODAS las voces incl. daisy/tanja/dionisio/damien clonan por Qwen3). **Referencia POR IDIOMA (acento nativo, 2026-10-03)**: si existe `<voz>-es-reference.wav` el español clona desde esa (nativa recitada del mismo timbre — auto-recitación: embedding de la voz original + 1.7B x-vector generando español nativo; una ref inglesa daba acento gringo en español, verificado por el owner); inglés usa `<voz>-reference.wav` original. `victoria-es-reference.wav`+`.txt` instalados (la de 30s `victoria-reference.wav.bak-30s-20261003` provocaba eco ICL ~2s; refs 7-10s OK). Carga ~15s, VRAM ~2.5-4GB. Modelos extra en `~/.voice-models/`: 1.7B-Base (calidad/recitación) y 1.7B-VoiceDesign (diseño de referencias).
- **STT**: Whisper small (OpenAI) — auto-detect language, local (sin internet)
- **STT inbound del agente (fix 2026-10-05)**: entry CLI audio en `tools.media.models` del openclaw.json (overrides + `_managed`): `whisper-cli {{MediaPath}}` capabilities `["audio"]` → socket `/tmp/tts-gateway.sock` → `/stt` del voice-server host. El runtime 2026.9.2 convierte ogg→wav 16kHz para whisper-cli (`resolveCliMediaPath`) y corre el audio-preflight ANTES del mention-check (grupos requireMention OK). Sin el entry, las notas de voz entran como "[Audio attachment not analyzed: no audio-understanding model is configured]"

### Comandos operativos (voice-server)
```bash
# Ver servicio
systemctl status victoria-voice-server.service

# Check health (con auth, desde localhost)
curl -s -H "Authorization: Bearer vllm-key-5d4..." http://127.0.0.1:18810/health | python3 -m json.tool

# Config-guide auto-descriptivo (para agentes/clientes)
curl -s -H "Authorization: Bearer vllm-key-5d4..." http://127.0.0.1:18810/voice/config-guide | python3 -m json.tool

# Reiniciar service
sudo systemctl restart victoria-voice-server.service

# Ver logs
journalctl -u victoria-voice-server.service -f
```

### Persistencia y reinicio
- `victoria-voice-server.service` (enabled, `Restart=always`, User=victoria)
- Venv: `/home/victoria/voice-venv/` (python3.12, torch cu128 + qwen-tts 0.1.1 + openai-whisper + transformers 4.57.3 — sin coqui/XTTS desde 2026-10-03)
- Modelos: `~/.voice-models/` (Qwen3-TTS-12Hz-0.6B-Base principal + 1.7B-Base/VoiceDesign) + STT `/home/victoria/.cache/whisper/small.pt`
- Voces: `/home/victoria/voices/` (victoria-reference.wav + .txt = ref inglesa; **victoria-es-reference.wav + .txt = ref española nativa** (auto-recitada, se usa para español); usuario-reference.wav + .txt; daisy/tanja/dionisio/damien refs + .txt)
- La primera vez tarda ~15s en cargar Qwen3-TTS (GPU); despues queda en memoria → TTS rápido (prompt de clonación 0.9s una sola vez por voz)
- Reglas IPv6 persistidas en `/etc/iptables/rules.v6` con `netfilter-persistent.service`

**NO tocar**:
- El filtro de IP en el codigo (es critico para seguridad)
- El drop IPv6 de 18810 (protege acceso publico a TTS/STT)
- Modificar las API keys de admin para el voice-server (usa las mismas del gateway)

### Auth unificada de los sentidos (2026-09-17) — la llave services abre todo
Los 5 sentidos validan la MISMA llave del gateway vía `/home/victoria/sense_auth.py`
(DB viva, sha256, `active=1`, no expirada). Roles aceptados: `admin` y `services`
(`servicios-alfredo-pro-llc` ya existe y abre los 5). `coder`/`readonly` → 401.
**Multi-tier (2026-10-03)**: una llave de CUALQUIER rol con `art/tts/whisper/
liveportrait/comfyui` en su `allowed_models` queda elevada a `services` para los
sentidos (ej. `kalimete` coder+`["llm","art","tts","whisper"]` usa TTS/STT con su
propia llave; `tts` = voz TTS, motor Qwen3-TTS — cap renombrada desde `xtts` el 2026-10-04). El resto de llaves sin esas caps → 401 igual que antes.

| Sentido | Puerto | Antes | Ahora |
|---|---|---|---|
| Voz TTS/STT | 18810 | hashes hardcoded admin (2026-08-19, se pudren al rotar) | DB viva admin/services |
| Video | 18811 | SIN auth (cualquiera en LAN descargaba/analizaba) | exige llave en LAN |
| Web-nav | 18820 | SIN auth y sin filtro IP | filtro + llave en LAN |
| Whois | 18830 | solo filtro IP | filtro + llave en LAN |
| Host-admin | 18840 | solo su bridge key propia | **bridge key O rol admin puro (2026-10-19)** |

Compatibilidad intacta (verificado E2E): localhost + red docker (`172.16/12`,
donde viven los bridges UNIX-socket del sandbox) siguen sin llave; desde LAN
10.x la llave es obligatoria (kalimete-ptt ya manda `Bearer`, compatible).
`/health` sigue abierto (status mínimo, sin datos) en voz/video/nav/whois.
**EXCEPCIÓN: host-admin `:18840` exige auth SIEMPRE** (bridge key o llave
gateway **rol admin puro**), incluso en `/health` desde localhost — 401 sin llave
es NORMAL, no caída. Es el sentido más poderoso (exec/apt/services del host);
el auth estricto es diseño, no bug. **ENDURECIDO 2026-10-19**: `check_auth`
usa `sense_role(elevate=False)` y exige `role == "admin"` — las llaves con caps
por elevación (ej. `kalimete`, cap art) y el rol services YA NO pasan (la llave
kalimete da 401 por diseño: consume recursos, nunca opera la máquina —
directiva del owner). Los sentidos generadores conservan la elevación normal.

**Wrapper `sqlite3ro`** (`/usr/local/bin/sqlite3ro` → `sudo -u victoria /usr/local/libexec/sqlite3ro_real`):
- Solo permite `SELECT`/`PRAGMA` sobre la DB, en `mode=ro`.
- Bloquea cualquier referencia explicita a `key_plaintext` o `key_hash`.
- Bloquea `SELECT *` (fuerza enumerar columnas).
- sudoers: `/etc/sudoers.d/warcold-sqlite3ro` (`warcold ALL=(victoria) NOPASSWD: /usr/local/libexec/sqlite3ro_real`).

**Configuracion opencode remoto** (ejemplo para otra maquina):
```jsonc
{
  "provider": {
    "vllm": {
      "npm": "@ai-sdk/openai",
      "options": { "baseURL": "http://<host-ip>:8010/v1" },
      "models": {
        "nvidia/Qwen3.6-35B-A3B-NVFP4-normal": { "id": "nvidia/Qwen3.6-35B-A3B-NVFP4-normal" }
      },
      "apiKey": "vllm-key-db13590a2a256457edde74e3e116b14d181ec01fee533f62225547f7251c7aa7"
    }
  }
}
```

## 7.2. Endpoint `GET /v1/config-guide` — guia auto-descriptiva para agentes remotos

El gateway expone `GET /v1/config-guide` (requiere API key, cualquier rol)
que devuelve un JSON con todo lo que un agente remoto necesita para armar su
`opencode.jsonc` apuntando a este stack. **NO filtra secretos**: sin keys ajenas,
sin `ADMIN_PASS`, sin IPs internas, sin rutas de sandbox. Solo placeholders
(`REPLACE_BASEURL`, `REPLACE_APIKEY`) + metadatos del modelo + warnings.

Usos:
- Un agente opencode en otra máquina (con su key readonly) puede leer este
  endpoint y auto-configurarse sin tocar el host ni exponer secretos.
- `warcold` también puede leerlo (su key readonly llega a `/v1/*`).
- No reemplaza a `AGENTS.md` (que es la fuente de verdad local con detalle
  operativo); es una guia sanitizada y autocontenida para consumo externo.

Estructura del JSON devuelto: `stack`, `auth` (key_name+role del que llama),
`served_model`, `limits`, `capabilities`, `models` (alias + thinking),
`connection` (local/lan/public), `opencode_template` (listo para copiar con
placeholders), `template_placeholders`, `validation` (3 curls de prueba),
`ide_integration`, `warnings`.

**`ide_integration` (2026-09-03)**: sección para conectar las keys del gateway a
CUALQUIER IDE compatible con "OpenAI-compatible provider":
- `universal_openai_compatible`: base_url `<GATEWAY>/v1`, api_key coder/admin,
  model id, **context_window 220000 y max_output_tokens 32000 (configurar
  MANUAL: los IDEs no conocen el modelo y asumen defaults pequeños)**, streaming
  true, tool_calls true, images true, `reasoning_effort` estándar OpenAI
  soportado (el gateway lo traduce a `enable_thinking`; solo hay 2 estados).
- Snippets listos: `vscode_continue_dev` (config.yaml de Continue.dev con
  roles chat/edit/apply/autocomplete + requestOptions), `vscode_cline`,
  `vscode_roo_code`, `jetbrains` (vía plugin Continue).
- FIM/autocomplete: `POST /v1/completions` (legacy) habilitado y verificado.
- Cualquier sufijo de model id (`-normal`/`-fast`/`-thinking`) es aceptado y
  normalizado por el gateway; `max_tokens` se clampea al de la key.

**Filosofía "servidor manda, cliente obedece" (2026-09-07)**: los límites
*duros* viven SOLO en el servidor (gateway) — el cliente no puede sobrepasarlos
aunque edite su config local:
- **Prompt (input)**: `MAX_PROMPT_TOKENS=220000` (220K) para todos → 400 al exceder.
- **Output**: el gateway clampea a `max_tokens` de la key.
- **rate_limit** y **budget**: por key, en el servidor.

Lo único que el cliente configura en su `opencode.jsonc` es *sintonía local de
conveniencia* (cuándo compactar, nombre, costo), NO seguridad. Para eso el
`opencode_template` del config-guide ya trae el bloque `limit`/`cost` correcto y
derivado del servidor (`MAX_PROMPT_TOKENS`) — el cliente SOLO reemplaza
`REPLACE_BASEURL` y `REPLACE_APIKEY`. No existe config remota centralizada en
opencode (cada cliente tiene su archivo); el config-guide es la "documentación
viva" que lo provisiona. El template NO incluye `instructions` (los archivos
AGENTS.md/victoria.md son del host, no del cliente).

## 7.3. Prompt de bootstrap para un agente remoto

Dale al agente remoto estos datos (que el admin le proporciona fuera de banda)
y este prompt. El agente NO necesita SSH al host — solo la API key readonly +
la URL del gateway (LAN o tunel HTTPS). El endpoint `/v1/config-guide` hace el
resto.

**Datos a proporcionar al agente (fuera de banda):**
- `GATEWAY_URL`: URL alcanzable del gateway
  - LAN: `http://victoria.local:8010` o `http://<ip-lan>:8010`
  - Internet: `https://<dominio-del-tunel>` (Tailscale Funnel / Cloudflare Tunnel / mTLS)
- `API_KEY`: una key del gateway con rol `readonly` (ej. la de `warcold`)

**Prompt para el agente remoto:**

````
Eres un agente opencode en una maquina remota. Debes configurar TU archivo
~/.config/opencode/opencode.jsonc para consumir el gateway LLM "· www.alfredo.pro"
(Qwen3.6-35B servido en vLLM). No tienes acceso SSH al host; todo va por la API.

Datos que ya tienes:
  - GATEWAY_URL = <el admin te lo da>  (ej. http://victoria.local:8010 o
    https://<tunel>; si es internet DEBE ser https, nunca http://ip-publica)
  - API_KEY     = <el admin te lo da>  (rol readonly)

Paso 1 — Lee la guia auto-descriptiva del gateway:

  curl -s -m 10 -H "Authorization: Bearer $API_KEY" \
       $GATEWAY_URL/v1/config-guide

Devuelve JSON con: served_model, limits, capabilities, models (alias thinking
ON/OFF), connection (local/lan/public), opencode_template (con placeholders
REPLACE_BASEURL y REPLACE_APIKEY), validation (3 curls), warnings.

Extrae del JSON:
  - El served_model y los dos aliases validos:
      nvidia/Qwen3.6-35B-A3B-NVFP4-normal    (thinking OFF, default rapido)
      nvidia/Qwen3.6-35B-A3B-NVFP4-thinking  (thinking ON, acotado)
  - limits: context 144000 (gateway), output 32000
   - capabilities: tools true, input ["text","image","video"], output ["text"] (VLM nativo)
   - CRITICO: el default es SIN thinking (el servidor arranca con
     enable_thinking=false). Para pensar usa el sufijo -thinking o
     reasoning_effort != none/minimal. NO agregues variants con
     reasoningEffort low/medium/high "de niveles": solo hay 2 estados (ON/OFF).
  - warnings: no /admin (LAN-only), usa tunel HTTPS para internet, etc.

Paso 2 — Arma TU opencode.jsonc. Toma el campo opencode_template del JSON,
reemplaza REPLACE_BASEURL por $GATEWAY_URL/v1 y REPLACE_APIKEY por $API_KEY,
y escribe el resultado en ~/.config/opencode/opencode.jsonc.

Paso 3 — Valida con los 3 curls del campo "validation":
  - GET  $GATEWAY_URL/health                       -> {"status":"ok",...}
  - GET  -H "Authorization: Bearer $API_KEY" $GATEWAY_URL/models
                                                   -> served_model listado
  - POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json"
         -d '{"model":"nvidia/Qwen3.6-35B-A3B-NVFP4-normal",
              "messages":[{"role":"user","content":"Responde solo OK"}],
              "max_tokens":10}'
         $GATEWAY_URL/v1/chat/completions          -> content == "OK"

Si los 3 pasan, tu config esta lista. Si 401: key invalida/revocada. Si 502:
vLLM upstream caido (avisa al admin). Si timeout: red/baseURL mal.

Paso 4 — Reporta al usuario: el opencode.jsonc final, el resultado de cada
curl, y si elegiste LAN o tunel HTTPS (con la razon).
````

## 7.4. Prompt publico para amigos / agentes externos (con credenciales)

Version lista para compartir con amigos cercanos o agentes externos. Incluye
las credenciales readonly inline y auto-deteccion del host (Internet vs LAN).
El agente decide el camino segun cual responde al probe `/health`.

**Hosts disponibles** (verificados 2026-08-14):
- **Internet (preferido)**: `https://victoria.armada.do` — tunel Cloudflare,
  HTTPS terminado en el edge. La API key NO viaja en claro. Responde a
  `/health`, `/models`, `/v1/*`.
- **LAN (fallback)**: `http://10.0.0.5:8010` o `http://victoria.local:8010` —
  directo por red local, sin TLS (la key viaja en claro dentro de la LAN, que
  es aceptable si confias en la red).

**API key** (rol `readonly`, compartible con amigos cercanos):
`vllm-key-db13590a2a256457edde74e3e116b14d181ec01fee533f62225547f7251c7aa7`

> Limites de la key readonly: solo `GET /v1/config-guide`, `/v1/catalog` y
> `/v1/client-config` con su llave. NO puede hacer inferencia
> (`/v1/chat/completions`/`/v1/completions`), ni ver `/v1/usage`. (`/health` y
> `/models` son públicos por diseño: status mínimo + nombre del modelo.) No puede
> crear/editar/borrar keys ni tocar el panel admin. Si se abusa, el admin la
> revoca desde `/admin` (LAN-only) y genera una nueva. **No la subas a repos
> publicos** (GitHub, Pastebin, Discord publicos); compartela por canal privado.

**Prompt para el agente externo (copiar/pegar):**

````
Eres un agente opencode en mi maquina. Configura mi archivo
~/.config/opencode/opencode.jsonc para consumir el gateway LLM
"· www.alfredo.pro" (Qwen3.6-35B servido en vLLM). No tienes SSH al host;
todo va por la API con esta key readonly:

  API_KEY = vllm-key-db13590a2a256457edde74e3e116b14d181ec01fee533f62225547f7251c7aa7

PASO 0 — Detecta el host (Internet vs LAN). Prueba los dos probes con
timeout 5s y elige el PRIMERO que devuelva HTTP 200:

  curl -s -m 5 -o /dev/null -w "%{http_code}" https://victoria.armada.do/health
  curl -s -m 5 -o /dev/null -w "%{http_code}" http://10.0.0.5:8010/health

Si https://victoria.armada.do responde 200  -> GATEWAY_URL = https://victoria.armada.do
   (Internet via tunel Cloudflare, HTTPS, preferido)
Si http://10.0.0.5:8010 responde 200         -> GATEWAY_URL = http://10.0.0.5:8010
   (LAN directa, sin TLS)
Si ninguno responde                          -> avise al admin; no sigas.

PASO 1 — Lee la guia auto-descriptiva del gateway:

  curl -s -m 10 -H "Authorization: Bearer $API_KEY" \
       "$GATEWAY_URL/v1/config-guide"

Extrae del JSON: served_model, limits (context 220000, output 32000),
capabilities (tools true, input ["text","image","video"], output ["text"], VLM nativo), los dos aliases
validos:
  nvidia/Qwen3.6-35B-A3B-NVFP4-normal    = thinking OFF, default rapido
  nvidia/Qwen3.6-35B-A3B-NVFP4-thinking  = thinking ON, acotado
CRITICO: el default es SIN thinking (el servidor arranca con enable_thinking=false).
Para pensar usa el sufijo -thinking o reasoning_effort != none/minimal. NO agregues
variants con reasoningEffort low/medium/high "de niveles": el chat template solo
soporta enable_thinking (bool) y esas variantes son fantasia (producen output
identico a thinking ON).

PASO 2 — Arma el ~/.config/opencode/opencode.jsonc. Toma el campo
opencode_template del JSON, reemplaza REPLACE_BASEURL por "$GATEWAY_URL/v1"
y REPLACE_APIKEY por "$API_KEY", y escribalo en
~/.config/opencode/opencode.jsonc.

PASO 3 — Valida con 2 curls (tu key readonly SOLO permite config-guide/catalog/client-config + health y models públicos):
  GET "$GATEWAY_URL/health"                                              -> {"status":"ok",...}
  GET -H "Authorization: Bearer $API_KEY" "$GATEWAY_URL/v1/config-guide" -> devuelve el JSON de nuevo (key valida)

Si 401: key revocada. Si 403: tu key es readonly e intentaste endpoint no permitido
  (solo /v1/config-guide, /v1/catalog y /v1/client-config). Si 502: vLLM upstream caido (avisa al admin).
Si timeout: red/baseURL mal. NO intentes /v1/chat/completions: tu key no puede
  hacer inferencia (es solo para leer la guia de configuracion).

PASO 4 — Reportame: el opencode.jsonc final, resultado de cada curl, y si
usaste Internet (victoria.armada.do) o LAN (10.0.0.5) con la razon.
````

> **Nota para el admin**: la key readonly NO puede probar inferencia (chat
> completions). El flujo de validacion del agente se limita a confirmar que
> `/health` responde y que su key llega al `/v1/config-guide`. Para que el
> agente pueda probar inferencia real, dale una key temporal de rol `coder`
> (desde el panel `/admin` LAN-only) y revocala cuando termine. El
> `opencode.jsonc` generado por el agente apuntara al gateway con la key
> readonly — pero no podra generar texto hasta que el admin le otorgue una
> key de inferencia. Esto es por diseno: la key publicable (readonly) no
> consume GPU del vLLM.

## 8. Seguridad — pendientes

- `~/.victoria-custom/secrets/data.txt` expone un `HF_TOKEN` y dos `nvapi-…` keys en texto plano.
  **NOTA (2026-09-07, actualiza 2026-08-30)**: la key **ACTIVA en producción es `nvapi-AuHo…`
  (victoria-1, me@alfredo.pro)** — alimenta el provider `nvidia` (DeepSeek V4 Flash/Pro + Kimi vía NVIDIA NIM)
  en `~/.local/share/opencode/auth.json` de opencode. Rotación: `~/.victoria-custom/bin/nvapi-rotate.sh`
  (`status|test|rotate|auto`) con fuente `~/.victoria-custom/secrets/nvapi-keys.json` (600, 3 llaves + `active`).
  Kalimete conserva `nvapi-vZ9w…` (victoria-2) a propósito para repartir cuota; sincronizar solo si una llave se revoka.
  Hallazgo 2026-09-07: errores con `moonshotai/kimi-k3` son **rate limit por modelo (429)**, no llave inválida
  (las 3 llaves dan 200 en otros modelos); alias `deepseek-ai/deepseek-v4-flash` está EOL (410) — usar `-0731`.
  El archivo vive en `~/.victoria-custom/secrets/` (dir 700,
  archivo 600 — solo victoria puede leerlo; movido desde Desktop 2026-08-30). No
  commitear. Ver tambien `~/.bash_history` (contiene el mismo `HF_TOKEN` exportado).
- **Regla anti-leak (2026-09-19, higiene)**: secretos SOLO vía env o archivo 600,
  JAMÁS hardcodeados en scripts/plantillas/docs. Casos cerrados ese día: `tts-bridge.py`
  traía la admin key de alfredo como default (peso muerto — la red docker es keyless
  por `sense_auth.py`; quedó `env VOICE_API_KEY` o vacío) y dos plantillas traían keys
  vivas (`remote/opencode-juancarlos.jsonc`, `kalimete-config/opencode.jsonc` → ahora
  placeholders `REPLACE_WITH_*`; NINGUNA key activa se rotó: juancarlos y kalimete
  siguen operando con las suyas). `verify` de armada-sync ahora falla si encuentra
  cualquier `vllm-key-*` completa que no sea la readonly `db13…` (compartible por
  diseño, §7.4). Excepción documentada: la readonly `vllm-key-db13…` SÍ vive en
  AGENTS.md/CHANGELOG a propósito (solo config-guide, revocable desde `/admin`).
- El `ADMIN_PASS` default (`victoria-admin`) es debil; sobreescribir via env al
  arrancar el gateway.
- Puerto 8000 solo en loopback + bridge OpenShell; no exponer a la LAN. La doc
  nemoclaw (`set-up-vllm.mdx:20-29`) detalla las reglas de firewall esperadas.
  **AUDIT (2026-08-16)**: el contenedor `nemoclaw-vllm` se lanzó con
  `-p 8000:8000` (bind `0.0.0.0:8000` + `[::]:8000` dual-stack), NO
  `-p 127.0.0.1:8000:8000`. Como el host tiene **IPv6 pública**
  (`2601:152:1580:92d0:…/64` en `enP7s7`), si el router residencial permite
  inbound IPv6, vLLM `:8000` queda **alcanzable desde Internet SIN API key**
  (vLLM no hace auth propia — todo el control de acceso vive en el gateway
  8010). El gateway `/admin` ya está blindado (middleware `llm-gateway.py:402-409`
  rechaza `CF-Connecting-IP` con 403), y los dashboards ComfyUI (8188) y
  OpenClaw (18789) solo escuchan en IPv4 `0.0.0.0` (no `[::]`) → no IPv6.
  nginx escucha en `[::]:443/80` pero `server_name victoria.local` filtra
  (Host desconocido → `default_server` → 404), así que no filtra los
  dashboards vía IPv6. **FIX APLICADO (2026-08-16 02:50 UTC)**: se descartó
  recrear el contenedor con `-p 127.0.0.1:8000:8000` porque **rompería el
  sandbox nemoclaw** — su proxy L7 (`openshell-sandbox` pid 1) ataca a vLLM
  vía `172.18.0.1:8000` (docker bridge de la red del sandbox), que NATs al
  puerto publicado `0.0.0.0:8000` del host. Bind loopback-only dejaría al
  sandbox sin inferencia (rompería OpenClaw, Discord, WhatsApp, voz). En
  su lugar se aplicó **`ip6tables -I INPUT 1 -p tcp --dport 8000 -j DROP`**
  (bloquea inbound IPv6 al puerto 8000, manteniendo vLLM accesible vía
  IPv4 para localhost del gateway + docker-bridge del sandbox + LAN).
  Regla persistida vía `iptables-persistent` (`netfilter-persistent.service`
  enabled) en `/etc/iptables/rules.v6`. **BLINDAJE LAN IPv4 APLICADO (2026-11-03,
  autorización owner "procede con todos los huecos")**: el tráfico al puerto
  publicado pasa por FORWARD/DOCKER-USER (DNAT de Docker), NO por INPUT —
  reglas en `DOCKER-USER`: `RETURN` para `127.0.0.1` y `172.16.0.0/12`
  (gateway-proxy 172.17.0.1, sandbox 172.18.x, victoria-lan 172.22.x) +
  `DROP` para todo lo demás (LAN 10.x y externo). Persistido con unit
  oneshot `victoria-firewall-vllm.service` (enabled, `After=docker.service`,
  idempotente — patrón gpu-clock-cap). **E2E verificado**: LAN kalimete
  →10.0.0.5:8000 = 000 (bloqueado), gateway loopback → vLLM = "FW-OK",
  sandbox 172.18.0.1:8000 = 200, gateway LAN :8010 = 200 (intacto).
  Validado: gateway 200, vLLM localhost 200, sandbox `inference.local` 200, IPv6
  `::1:8000` 000 (DROP funciona). Ver §10 historial (2026-08-16 02:50).
- **HARDENING IPv6 TOTAL (2026-08-29 14:36)**: se detectó que nginx `[::]:443`
  y SSH `[::]:1666` escuchaban en IPv6 pública SIN regla DROP (solo :8000 y
  :18810 estaban protegidos) — un externo con inbound IPv6 podría alcanzar el
  dashboard OpenClaw vía `nginx /openclaw/ → 18789`. **Fix aplicado**:
  `ip6tables -P INPUT DROP` + `-A INPUT -i lo -j ACCEPT` + `-m state --state ESTABLISHED,RELATED -j ACCEPT` + `-p ipv6-icmp -j ACCEPT`, persistido en
  `/etc/iptables/rules.v6` (netfilter-persistent enabled). Docker no usa IPv6
  (sin `daemon.json`) → sin impacto. **nginx default_server 404**: nuevo
  `default-victoria.conf` (`listen 443 ssl default_server`) que rechaza
  cualquier Host ≠ `victoria.local`/`victoria` (defensa IPv4 en profundidad).
  **Web UI solo LAN**: dashboard 18789 es IPv4-only; el túnel Cloudflare
  conecta SOLO a `127.0.0.1:8010` (verificado con `ss`: ninguna conexión a
  18789); el dashboard requiere el token del gateway (solo del host).
  **DMs solo owner**: Discord `allowlist` + WhatsApp `pairing` con allowFrom
  del owner — desconocidos no entran por privado.

### Pendientes con receta lista (2026-11-03 — solo falta decisión/ejecución del owner)

| # | Pendiente | Quién | Receta lista |
|---|---|---|---|
| 1 | **UPS + adaptador 240W original** directo a tomacorriente | **OWNER (físico)** | El software ya está blindado (watchdog 3min + gpu-saver + válvulas); 3 cortes documentados. No hay fix software. |
| 2 | **TTS fuera de LAN** (voz-viva en roaming = solo texto) | OWNER decide | Receta: (a) ruta Cloudflare `tts.armada.do` → `127.0.0.1:18810` en el config de cloudflared + (b) el voice-server YA exige llave gateway en LAN (sense_auth) — el túnel la mantiene; (c) probar `VICTORIA_TTS_URL=https://tts.armada.do` en el plugin voz-viva de la laptop. Riesgo: endpoint de voz público con llave — aceptable con rate-limit del gateway. |
| 3 | **armada-sync victoria off-site** (snapshots solo locales) | OWNER decide (repo+creds) | Receta: crear repo privado GitHub `warcold/victoria-sync` → `git init` en `~/.armada-sync/snapshots/latest/` + remote + push en `armada-sync.sh cycle` (hook ya documentado en §9.5). NO usar el hub de kalimete (contrato scopes). |
| 4 | **Swap 55GB** | OWNER (más data) | **MANTENER** — evaluado 2026-11-03: 26GB EN USO, eventos NVRM NV_ERR_NO_MEMORY reales (nov 1-2, coder activo + RAM 24-27GB disp), 0 freezes desde swappiness=10. El swap es load-bearing. Re-evaluar en 30 días de métricas limpias. |
| 5 | **Derivas upstream menores** (ComfyUI, Gradio) | Victoria (mantenimiento programado) | ComfyUI v0.42.0→nueva: requiere actualizar aimdo+kitchen JUNTOS (crash-loop documentado si no). Gradio 6.29.1→6.31: riesgo para UI custom — solo con ventana de mantenimiento. cloudflared: 2026.10.0 ES la última del repo apt (deriva vs GitHub esperada). |
| 6 | **Bug runtime semanal** (skill_workshop args malformados, 18:24) | Reporte upstream | Benigno (reintenta); patrón en logs del sandbox. Reportable a nemoclaw/openclaw si el owner quiere. |

## 9. Ingredientes que no tocar salvo reseteo mayor

- La imagen Docker se sirve por **digest inmutable** (`@sha256:9204569b…`). No
  convertirla a `:tag` o `:latest` o perdemos la receta canónica.
- `restart=unless-stopped` + label `managed-vllm=true`: nemoclaw reconocera el
  contenedor como gestionado en futuros `onboard`. Sin el label, lo trata como
  server externo y falla el chequeo de identidad.
- El flag `--gpu-memory-utilization` está calibrado para GB10 (unified
  memory). **Subirlo por encima de ~0.3-0.4 puede congelar el host**
  (`NV_ERR_NO_MEMORY`, SSH perdido) — NUNCA subir a 0.4 o más. **HALLAZGO
  2026-09-29**: en este build NGC (vLLM 0.21) con memoria unificada, este flag
  NO controla el tamaño del KV cache (se probó 0.15 vs 0.22: el pool KV SUBIÓ
  a 21.5 GiB) — el control real es `--kv-cache-memory-bytes` (formato bytes:
  `12884901888`, NO acepta `12GiB`). **Actualizado 2026-09-29**:
  `--kv-cache-memory-bytes 12884901888` (12 GiB ≈ 945K tokens, concurrencia
  5.9x a 160K — el pool anterior de 1.6-1.7M tokens era 10x sobredimensionado
  y malgastaba ~9 GiB) + `--max-num-seqs 6 → 4` + `--gpu-memory-utilization
  0.22`. Libera ~9 GiB de memoria unificada para Sonic (render 640px) y el
  OS (RAM disponible 23→36 GB; los OOMs del 09-27/28 fueron con RAM 91-95%).
  (Historial: 09-10 0.4→0.25 KV 42→24 GiB · 09-11 seqs 4→6 · 09-29 seqs 6→4
  con KV explícito 12GiB; semáforo gateway `UPSTREAM_MAX_CONCURRENCY` 6→4).

## 9.5. armada-sync — respaldo automatizado de conocimiento (2026-09-14)

Creado tras la pérdida del historial CHANGELOG por overwrite manual. Respalda
todo lo que Victoria necesita para no perder conocimiento ni repetir trabajo:
guías, subagentes, docs, changelogs, config viva y estado.

| Aspecto | Valor |
|---|---|
| Script | `/home/victoria/armada-sync.sh` (`backup\|status\|verify\|restore [ts]\|docsync\|fleet\|cycle`) — EL sistema único de sync (backup + docsync + fleet); `doc-fresh.sh` y `upstream-sync.py` pertenecen a él, no son sistemas separados |
| Destino | `/home/victoria/.armada-sync/snapshots/<timestamp>/` + espejo `latest/` |
| Automatización | `armada-sync.timer` (systemd, cada 6h + al boot, `Persistent=true`) corre `cycle` = backup + docsync (chequeo doc-vs-upstream con guarda 24h, solo reporta deriva a `state/upstream.json`) + fleet (auditoría del scaffold: agent list vs .md vs harness vs changelogs + frontmatter + JSON + frescura + boundary; solo lectura, no fatal) |
| Retención | 30 snapshots (~1MB c/u tras excluir binarios) |
| Excluye siempre | secretos (`secrets/`, `llm-gateway.db`, `auth.json`, tokens), binarios reinstalables (blogwatcher), DBs |

Incluye: `AGENTS.md`, `CHANGELOG.md`, `.config/opencode/agents/*.md`, `opencode.jsonc`
(redactado), `openclaw-overrides.json`, `skills/`, `bin/` (scripts, sin
binarios), `sandboxes.json`, `onboard-session.json`, gateway + scripts del
stack, identidad restore, `MANIFEST.txt` por snapshot (tokens, digest vLLM,
sandbox). `verify` chequea integridad + ausencia de secretos completos.
`restore` NO restaura automático: muestra diffs y el operador copia manual.
**Changelogs por servicio (incluidos desde 2026-09-18)**: `~/.victoria-custom/changelogs/CHANGELOG-*.md` (11 archivos: vllm, sandbox, voice, video, whois, host-admin, comfyui, rss, social, weather, infra) — respaldados junto al general.

**Regla**: los docs viven en UN solo lugar canónico; armada-sync es respaldo,
NUNCA fuente de edición. CHANGELOG siempre append al inicio, nunca rewrite.

## 9.6. Contexto por proyecto — ledgers AGENTS.md (2026-09-30)

El contexto global (este AGENTS.md + `agents/victoria.md`) describe el STACK,
no los proyectos. Para no quemar las 120K de contexto cargando historiales de
vibecoding en cada sesión, cada proyecto/prototipo lleva su propio `AGENTS.md`
(ledger) que vive CON el código. Protocolo completo en `agents/victoria.md`
(§Protocolo de Contexto por Proyecto); plantilla en
`~/.victoria-custom/templates/AGENTS-project-template.md`. Resumen:

1. **Al empezar** en un proyecto: leer su `AGENTS.md` (mapa, decisiones,
   pendientes). Si no existe y el trabajo es >1 sesión o >3 archivos → crearlo
   desde la plantilla.
2. **Al terminar** cada sesión: actualizarlo (qué se hizo, decisiones,
   pendientes). ~60 líneas máximo.
3. **Si tocó el stack**: ADEMÁS va al CHANGELOG general + changelog(s) del
   servicio. El ledger referencia, no duplica.
4. **Subagentes vía `Task`**: el prompt incluye "lee primero
   `<proyecto>/AGENTS.md` y actualízalo al terminar".
5. **NUNCA** pegar el contexto global en un ledger (referenciar por ruta).

Qué NO lleva: secretos, dumps de logs, historial del stack. Qué SÍ: mapa de
archivos, comandos run/debug verificados, decisiones con fecha, pendientes.

## 10. Historial reciente

- **2026-10-14 02:00 (UTC-4)**: **Forense freeze 2026-10-13 19:00 + triple blindaje anti-freeze (carga sostenida)**. El owner reportó WhatsApp muerto + reportes perdidos tras alerta térmica ~19:00. Forense (caja negra `victoria-metrics.db` WAL + journal boot -1 + `usage_log`): **el host se congeló a las 19:00:04 EDT** (journal abrupto, sin Xid/OOM/pstore; power-cycle manual ~22:47 → 3h47m muerto). Gatillo: sesión agéntica de juancarlos por el túnel — 47 reqs 18:52-18:59, ctx 79K→150K, GPU 94-95% sostenido 12+ min (probe vLLM 11.2s 24s antes de morir; RAM OK → hard-freeze del driver, patrón NVRM NV_ERR_NO_MEMORY). **Investigación internet**: NVIDIA container-toolkit#1910 = mismo freeze sin fix upstream; blog oficial vLLM DGX Spark valida NUESTRA config (seqs 3≤4, headroom UMA); NVIDIA known issues: adaptador 240W original obligatorio; 75-82C bajo carga = normal (temp = síntoma). **Fixes**: (1) sandbox `RestartPolicy=no→unless-stopped` (drift del rebuild 10-05; causa de las 2h de WhatsApp muerto) + `ensure_sandbox_restart_policy()` en el ensure-loop; (2) gpu-saver watchdog carga sostenida (util ≥85% 5 min → alerta WA); (3) gateway **válvula 5** (engine sin pausas 10 min → gap 8s entre admisiones, 429 + Retry-After, reversible `SUSTAINED_LOAD_GUARD=0`). Los 3 servicios reiniciados sanos, E2E OK. **Pendiente owner (físico)**: adaptador 240W original directo a tomacorriente + UPS. Ver CHANGELOG 2026-10-14 + CHANGELOG-gpu/vllm/sandbox.


- **2026-09-18 19:00 (UTC-4)**: **Re-arquitectura del dashboard: gateway OpenClaw en HOST + changelogs por servicio**. (1) **Hallazgo**: tras recrear el sandbox con `nemoclaw onboard --fresh`, el gateway de OpenClaw ya NO vive dentro del sandbox — vive en el HOST como proceso `openshell` (~pid 1604795, escucha `127.0.0.1:18790`). El proceso `openclaw-gateway` dentro del sandbox aparece en logs como "listening" pero NO binda puerto (state S, ep_poll) — el puerto real del host lo sirve `openshell`. (2) **Fix del publisher**: `openclaw-bridge-ensure.sh` actualizado — `ensure_inner_proxy()` ELIMINADA (obsoleta), `ensure_publisher()` reescrita con `--network host` + target `127.0.0.1:18790` (verifica NetworkMode host + cmd apunte a 127.0.0.1). Cadena nueva: `victoria.local:18789 (publisher, network host) → 127.0.0.1:18790 (gateway HOST)`. (3) **Changelogs por servicio creados**: `~/.victoria-custom/changelogs/CHANGELOG-{vllm,sandbox,voice,video,whois,host-admin,comfyui,rss,social,weather,infra}.md` (11 archivos) — cada servicio con su changelog separado + el general como índice maestro (toda entrada va en AMBOS). (4) **Docs actualizados**: AGENTS.md (tabla archivos + §Dashboard + §9.5 armada-sync), victoria.md (topología + servicios + contenedores + redes + §ChangeLog con tabla de changelogs), subagente `nemoclaw-sandbox-ops.md` (Dashboard bridge + Post-upgrade + señales de alarma). Sandbox restaurado: identity + openclaw.json (discord/whatsapp enabled, 5 plugins) + bridges tts/video/whois/admin + skills (admin, alfredo-pro, domain, video). Verificado: dashboard `{"ok":true,"status":"live"}`, publisher network=host, sandbox healthy, todos los sockets OK.

- **2026-09-07 07:10 + 07:45 (UTC-4)**: **Instagram publisher ACTIVO EN PRODUCCIÓN sobre @victoria.armada.do** (la cuenta real de la marca; @alfredosislabs quedó obsoleta como referencia). OAuth completado vía endpoint propio `GET /ig-callback` del gateway (el panel Meta "Generate token" no funcionaba → código flow por `api.instagram.com/oauth/authorize` con redirect `https://victoria.armada.do/ig-callback`). **Formato actual (07:45, criterio del owner): imagen SIEMPRE la original del artículo** (og:image → RSS → fallback card de marca), **sin link dibujado en la imagen**, **con el logo real de Alfredo Pro como marca** (`~/.victoria-custom/brand/logo-inverted.png`: esquina inferior-derecha en feed, arriba-izquierda en stories sobre gradiente oscuro con el título). **Programación orgánica agresiva**: cron `--auto` cada 20 min 08:00-23:30; script decide por gaps (feed cada ~190-230 min ≈ 4/día, story cada ~70-110 min ≈ 8-9/día) con jitter aleatorio. Límite API 100/24h. Refresh token semanal lunes 04:00. Primer post y story reales OK (ids 18173197867399482 / 17965663988966060 / 18106066424159390).

- **2026-09-06 00:55 (UTC-4)**: **Instagram auto-publisher desplegado (pendiente solo las credenciales Meta del owner)**. Victoria publicará las noticias tech en el IG de Alfredo Pro: feed 2/día (10:00 y 18:00 EDT, horario solapado deliberadamente distinto de Discord/WhatsApp) con caption escrito por el LLM local + imagen del artículo (o card de marca PIL si falta) + "link en bio www.alfredo.pro" + hashtags; stories 4/día (09/13/17/21) con **link sticker clicable a www.alfredo.pro** (el feed no permite links clicables en caption). Componentes: `instagram-broadcast.py` (--feed/--story), `instagram-onboard.py` (exchange token 1h→long-lived + auto-descubre IG_USER_ID), `instagram-token-refresh.py` (cron lunes 04:00), endpoint público `GET /ig-media/{img}` del gateway (Meta descarga la imagen por el túnel; sanitizado anti-traversal; borrado tras publicar). Guía para el owner: `~/.victoria-custom/instagram-SETUP.md` (10 min: cuenta profesional + Page FB + app Meta + token inicial). 100% gratis.

- **2026-09-05 17:05**: **admin panel responsive mobile-first** (drawer hamburguesa ≤860px, anti-zoom, touch ≥44px, tablas scroll) + auditoría exposición: túnel→403, IPv6→DROP, nginx→404; solo LAN. Desktop idéntico.

- **2026-09-05 02:15 (UTC-4)**: **UPDATE MAYOR del ecosistema: nemoclaw 0.0.103→v0.0.119 + openshell 0.0.85→0.0.106 + sandbox recreado limpio (trino tras rescate de container incompatible)**. Hallazgo clave: nemoclaw sigue pineando openclaw **2026.7.1** (NVIDIA no promueve 2026.9.1 como runtime todavía) — el update fue de INFRAESTRUCTURA, no del agente. Incidente y rescate: container viejo incompatible con gateway nuevo (credenciales revocadas, label sandbox-workspace ausente); rebuild/recover fail-closed → destroy limpio + `onboard --recreate-sandbox` (registry restaurado desde sandboxes.json.bak para heredar vllm-local+modelo) → ensure-loop restauró TODO (canales/identidad/voz/TTS fix/wrappers/bridges) en ~2 min tras renombrar prefijos de container a `victoria-armada` en 10 scripts. **Fixes nuevos**: publisher del dashboard por IP fija 172.22.0.10 (DNS Docker no resuelve nombres >63 chars del nuevo esquema); `loginctl enable-linger victoria` (el gateway openshell ahora es user-service enabled — sin linger no arrancaría tras reboot). Policies de egress (discord/whatsapp/etc) vivas en OpenShell (autoridad única desde v0.0.117) — sobrevivieron el destroy. Verificado: inferencia E2E OK, WhatsApp listening, Discord READY (heartbeats), TTS E2E, dashboard 200/live, persist backup 1.1G, ffmpeg presente. Ver CHANGELOG.

- **2026-09-04 23:55 (UTC-4)**: **auditoría de versiones de todo el stack (petición del owner) + actualizaciones seguras aplicadas**. Aplicado: `apt upgrade` (466/473 pkgs; quedan 7 held: kernel NVIDIA 6.17.0-1032 + fwupd + linux-firmware — **reboot pendiente coordinado**, el stack auto-arranca); **opencode 1.18.27→1.18.29** (E2E OK); **blogwatcher v0.0.3→v0.0.4** (rebuild Go estático, host+sandbox, backup del viejo); **ComfyUI a7365071→250b2e95 (v0.34.4, 104 commits)** + deps nuevas en venv (`comfy-aimdo 0.5.2` — sin ella main.py no importa — frontend 1.51.9, templates 0.11.55); imports verificados. NO tocado (pinned deliberado): vLLM digest NGC (revisión manual trimestral), OpenClaw sandbox 2026.7.1→2026.9.1 disponible (**pendiente con plan**: salto de 2 meses, riesgo a schemas/plugins/patches recién arreglados), torch cu128/cu130 (compat GB10), transformers 4.57.1 (pin coqui-tts vs 5.x). Ya en latest: yt-dlp, cloudflared, coqui-tts, whisper. Ver CHANGELOG.

- **2026-09-03 02:58 UTC**: **auditoría completa del stack de inferencia (petición del owner) + 4 mejoras**. Verificado end-to-end: vLLM sano con receta canónica intacta (digest pinned, max-model-len 262144, sampling defaults del modelo temp 1.0/top_p 0.95/top_k 20 aplicados por vLLM), gateway v3 sano (streaming, metering, validación contexto 400, roles), túnel Cloudflare OK desde Internet (200 vía IP real; nota: `/etc/hosts` mapea victoria.armada.do→127.0.0.1, probar el túnel desde el host con `--resolve ...:104.21.32.145`), tool calls OK (`finish_reason: tool_calls`), streaming SSE OK, VLM visión OK ("Red"), thinking ON/OFF OK, `/v1/completions` FIM OK (autocomplete IDEs), metering registra tokens reales, readonly→403 chat, `/v1/usage` OK. **Mejoras aplicadas**: (1) `opencode.jsonc`: `compaction: {auto:true, prune:true}` (prune limpia tool outputs viejos → menos compactaciones en sesiones largas) + `provider.vllm.options: {timeout:3600000, chunkTimeout:600000}` (el default 300s podía cortar generaciones de 32K tokens que tardan 640-800s; la cadena ya aguantaba 1h: gateway 3600s, nginx 86400s); (2) `llm-gateway.py`: mensaje de error 400 de validación decía "context: 220000" (obsoleto) → "228000"; (3) `GET /v1/config-guide` ahora incluye sección **`ide_integration`**: guía universal OpenAI-compatible + snippets de Continue.dev/Cline/Roo Code/JetBrains (base_url, key, model id, context_window 228000 + max_output_tokens 32000 MANUALES porque los IDEs no conocen el modelo, FIM `/v1/completions`, `reasoning_effort` soportado). Gateway reiniciado x2 sano; opencode verificado post-cambio (`opencode run -m vllm/...` → OK). Lección: el trigger de auto-compact de opencode usa `limit.context` (228000) con buffer `reserved` ~10000 → la llamada de summarization cabe holgada en 262144. Ver CHANGELOG.

- **2026-09-01 19:45 UTC**: **fix dmPolicy vuelto a "open" (demasiado permisivo) — se descubrió por auditoría**. El backup de persist.sh se restauró con `dmPolicy: open` + `allowFrom: *` (el, los valores son del backup viejo). **Fix**: corregido los overrides (`channels.discord.dmPolicy: allowlist + allowFrom: owner`, `whatsapp.dmPolicy: pairing + allowFrom: owner`), nuevo backup con config correcta (595M). **Lección**: cuando se restaura config del backup, los permisos deben estar en el overrides del ensure-loop para no perderse en rebuilds.

- **2026-09-01 03:52 UTC**: **fix "usuarios fallan con respuestas" — validación previa de contexto en el gateway**. Usuarios del gateway (juancarlos=2671 req/24h) se quejaban de fallos del modelo: la DB mostraba juancarlos con 536 requests de 0 tokens y latencias hasta 688s; el vLLM registraba 792 `VLLMValidationError` (contexto excedido). Causa: el gateway en modo streaming devolvía 200 OK aunque el vLLM rechazara (el error quedaba oculto en el stream). **Fix**: validación previa en `_proxy` del gateway que estima los tokens del prompt (chars ÷ 3) y rechaza con **400 claro** (`context_length_exceeded` con la recomendación de límites) si `prompt + max_tokens > 260000`. `MAX_MODEL_LEN = 262144` constante. Verificado: 200 OK para prompts válidos, 400 claro para prompts grandes. **Lección**: el gateway no puede delegar la validación de contexto al vLLM cuando usa streaming ignorando errores del upstream.

- **2026-08-31 02:45 UTC**: **Voz real de Victoria clonada (Librivox "Little Eve Edgarton") + pipeline de clonación**. El zip (107MB, respaldado y verificado md5 `7e02d792…` en `~/.victoria-custom/voice-clone/original/`) contiene 7 capítulos mp3 de la lectora femenina. Se analizaron candidatos (transcritos con Whisper), elegido el segmento 145s-175s del cap. 1, limpiado con ffmpeg (highpass+lowpass+afftdn denoise+loudnorm -16 LUFS+recorte silencios → 22050Hz mono 16-bit), e instalado como `~/voices/victoria-reference.wav` (1.3MB; backup del placeholder en `.bak-placeholder-20260831`). Como el voice-server clona con `get_conditioning_latents(reference)`, la nueva voz aplica a TODO el sistema (WhatsApp/Discord/Web UI). Verificado TTS en 5 idiomas (es/en/fr/de/pt) + STT exacto. Script reutilizable `~/.victoria-custom/bin/clone-voice.sh`.

- **2026-08-31 02:21 UTC**: **Limpieza de duplicados de voz (~2.5GB) + código obsoleto + fix backup + sentidos verificados**. (1) El voice-server usa SOLO rutas canónicas (`~/.voice-models/XTTS-v2/`, `~/.cache/whisper/small.pt`, `~/voices/`) — los duplicados dentro de `voice-venv/` (.local/share/tts 2GB, .cache/whisper 462MB, voices, __pycache__, bak) fueron borrados; `openclaw-voice-host.sh` parcheado para verificar canónicas (venv_ok/ensure_models/status) y NO regenerar duplicados. (2) Eliminados: `comfyui-idle-saver.py`+unit (superseded por gpu-saver), `openclaw-voice-install.sh` (OBSOLETO), `voice-server.py` raíz (viejo). (3) `persist.sh` fix: tar con `--warning=no-file-changed` (el backup fallaba intermitente cuando el gateway escribía durante el tar). (4) Sentidos de Victoria: VER (image/video), HABLAR (XTTS), ESCUCHAR (Whisper), Web UI talk — verificados funcionando. 100% local/gratis.

- **2026-08-30 22:36 UTC**: **Fix permisos por rol: `tools.deny` a nivel grupo rompía al owner (bucle "procedo") + audit de voz clonada**. Al validar el flujo WhatsApp voice notes se encontró que el owner perdió `exec` en Warcoldology: la config usaba `tools.deny` (15 tools) a nivel grupo + `toolsBySender.owner.alsoAllow`, pero **el deny del grupo se aplica a TODOS y alsoAllow NO lo anula** → Victoria en bucle infinito "¡Gracias Papá, procedo!" (sesión 557ea9e4: "exec no está disponible en las tools actuales"). **Fix**: quitar `tools.deny` de grupo/guild y usar `toolsBySender` con **wildcard `*`** (deny para público) + **owner específico** (`id:`/`e164:` con `alsoAllow`) — `matchToolsBySenderPolicy` devuelve el match específico ANTES del wildcard. Corregido `applypatch`→`applyPatch`. **Voz**: audit confirmó que `victoria-reference.wav` es PLACEHOLDER (md5 = `es_sample.wav` de XTTS, mismo archivo que `usuario-reference.wav`); NO hay voz clonada real en el sistema. Para voz de Victoria real: necesita sample de referencia (pendiente).

- **2026-08-29 14:36 UTC**: **Endurecimiento de acceso: Web UI solo LAN, firewall IPv6 DROP total, nginx default 404**. Confirmado por evidencia que el Web UI (OpenClaw Control 18789) es LAN-only: IPv4-only (`0.0.0.0`, sin `[::]`), túnel Cloudflare conecta SOLO a `127.0.0.1:8010` (`ss` muestra 1 conexión a 8010, 0 a 18789), y requiere el token del gateway. Se cerró el vector IPv6: `ip6tables -P INPUT DROP` + loopback/established/ICMPv6 (persistido en `/etc/iptables/rules.v6`; antes nginx `[::]:443` y SSH `[::]:1666` estaban expuestos). nginx `default-victoria.conf` (`default_server` 404 para Host ≠ victoria.local). DMs solo owner confirmado (Discord allowlist + WhatsApp pairing). Verificado: IPv4 200, `[::1]:18789` → 000, Host desconocido → 404, victoria.local → 200, backup 479M. Ver §8.

- **2026-08-29 13:34 UTC**: **Voz total activada + permisos por rol (solo Alfredo con autonomía)**. (1) **Discord voice**: `channels.discord.voice = {enabled: true, mode: "stt-tts"}` — Victoria se une a salas de voz y habla como usuario, con el stack local (whisper STT + XTTS TTS vía voice-server host). El modo `bidi`/`realtime` requeriría provider externo (no gratis) — NO se usa. (2) **WhatsApp voice notes**: `messages.tts.auto: "inbound"` ya responde con nota de voz a los audios entrantes (texto + TTS). (3) **Web UI**: la voz usa `talk.provider = tts-local-cli` ya configurado; el runtime distingue `senderIsOwner` en `agent:main:main`. (4) **Permisos**: en Discord guilds (Alfredo Hub, La Verganza) y WhatsApp groups (120363428629110824, 120363429817888300) se puso `tools.deny` (15 tools de ejecución: exec/browser/web_fetch/web_search/read/write/applyPatch/process/cron/gateway/nodes/sessions_spawn/weather/tool_search/tool_describe) para el público — solo chatear; y `toolsBySender` con **key tipado** (`id:693703068461826110` Discord, `e164:+18295468686` WhatsApp — el runtime deprecia keys sin prefijo) con `alsoAllow` para que Alfredo conserve todo. (5) **Identidad**: sección "Permissions — only Alfredo gets full power" — no-owners solo chatean. Verificado: 0 reloads inválidos, WhatsApp "DM + 2 configured groups", voice `{enabled, stt-tts}`, backup 478M. **Nota**: `GATEWAY_OWNER_ONLY_CORE_TOOLS` del runtime es hardcodeado (`cron/gateway/nodes`); el enforcement por guild/grupo es configurable vía `tools.deny` + `toolsBySender`.

- **2026-08-29 03:56 UTC**: **Host Admin Bridge — Victoria accede a tools/servicios del host de forma segura (autonomía)**. Nuevo servicio `victoria-host-admin.service` (enabled, :18840): expone al sandbox `POST /exec` (allowlist: dig host nslookup curl whois jq ping openssl, subprocess sin shell), `POST /apt/install` (allowlist: whois dnsutils jq curl netcat-openbsd traceroute openssl bind9-dnsutils iputils-ping nmap unzip tree ripgrep htop tcpdump), `POST /service` (allowlist servicios del stack + status/is-active/start/stop/restart), `GET /status`. Seguridad: API key `X-API-Key` (hmac, `secrets/admin-bridge.key` 600) + filtro red (localhost/docker/LAN) + allowlists + validación args + audit log. Sandbox: `admin-bridge.py` (UNIX socket `/tmp/admin-gateway.sock` → host:18840) + wrapper `admin-cli` + skill `admin` (`command:admin`). `ensure_admin()` en ensure-loop. Verificado: exec dig/curl/whois, apt tree, service is-active, auth 401 sin key, rm/docker.io denegados; backup 469M. **100% local/gratis** — la directriz del owner: "todo con nuestros recursos y gratis, podemos hacer de todo con la máquina que tenemos". **Lección**: el patrón para dar autonomía al sandbox es el bridge UNIX socket con allowlist estricta en el host; el sandbox NUNCA tiene shell en el host, solo un subset auditable de operaciones.

- **2026-08-28 01:35 UTC**: **Victoria no podía hacer whois → servicio whois del host + bridge al sandbox**. El owner pidió "whois resego.com" (sesión bc2038b8) y Victoria falló con 18+ tool calls: `whois` no existe en el sandbox NI en el host; `apt-get install whois` en el sandbox revienta por dpkg (deps rotas, arrastra ffmpeg/gtk) y el puerto TCP 43 está bloqueado por el proxy L7 (solo 80/443); el modelo además generó tool_calls mal formados (`Validation failed for tool "tool_call": id: must have required properties id`) y `web_fetch` con `url required`; las APIs HTTP de whois requieren keys. **Fix (patrón voice/video)**: (a) `sudo dpkg --configure -a` en el host (estaba interrumpido desde el reboot de mantenimiento) + `apt-get install whois` (5.5.22); (b) nuevo `victoria-whois-server.service` (enabled, :18830) con `/home/victoria/whois-server.py` (filtro de red localhost/docker/LAN + regex de dominio + subprocess sin shell); (c) bridge `whois-bridge.py` en el sandbox (UNIX socket `/tmp/whois-gateway.sock` → `host.docker.internal:18830`, réplica de video-bridge); (d) wrapper `/sandbox/.openclaw/bin/whois` (socket UNIX, réplica de video-analyze); (e) `ensure_whois()` en el ensure-loop (reasegura service + bridge + wrapper tras rebuild). Verificado end-to-end desde el netns del gateway: `whois resego.com` → registro GoDaddy completo. Persistencia: backup 449M + wrapper en backup. **Mejora 20:10 UTC**: fallback RDAP en whois-server (TLDs que whois genérico no soporta como `.pro` → `https://rdap.org/domain/<dominio>`) + **skill `domain`** (`skills/domain/SKILL.md` host+sandbox, expuesta como `command:domain` en el runtime) que le enseña a Victoria el comando `/sandbox/.openclaw/bin/whois <dominio>` (ruta completa — el PATH del netns del gateway NO incluye `/sandbox/.openclaw/bin`), interpretación de campos y formato de respuesta. `ensure_whois` copia la skill tras rebuild. **Lección**: el sandbox no puede tener whois nativo (apt roto + TCP 43 bloqueado) — las capacidades que requieren binarios del sistema o puertos no-HTTP deben vivir en el host y exponerse por bridge UNIX socket (mismo patrón que voice/video); y para que Victoria use una capacidad nueva necesita una skill (el runtime no la descubre sola).

- **2026-08-27 22:30 UTC**: **fix "Victoria le dice papá a desconocidos en grupos" — identidad con identificación de sender**. Síntoma: Victoria respondía a personas NO-owner en grupos de WhatsApp como si fueran Alfredo — les decía "papá" e incluso "tú eres mi creador" (verificado en sesión `52f49db3`: sender `+18097794724` con `senderIsOwner: false` recibió "No papá, tú eres mi creador... papá eres tú"). **Diagnóstico**: el runtime OpenClaw SÍ marca correctamente `__openclaw.senderIsOwner` (false para desconocidos, true para Alfredo), pero la identidad (USER.md/SOUL.md/IDENTITY.md) decía "What to call them: Papá / Alfredo. Es mi padre y mi owner" y "Él es el único que puede hablarme en DMs y grupos (allowlist)" — el modelo generalizaba el trato "papá" a todo el que le escribe. Además `channels.*.groupPolicy: "open"` permite que cualquier miembro de los grupos le escriba. **Fix**: corregidos los 3 archivos de identidad (maestros `/home/victoria/{USER,SOUL,IDENTITY}-restore.md` + sandbox vía ensure-loop) con la sección **"Who is talking — never assume it's Alfredo"**: (a) llamar "papá" SOLO cuando el sender es Alfredo (`senderIsOwner: true`, WhatsApp `+18295468686`, Discord `693703068461826110`); (b) si `senderIsOwner: false` → NUNCA llamarlo "papá", NUNCA decir "eres mi creador", dirigirse por su nombre (`senderName`) o cordialmente; (c) los grupos son abiertos — no asumir que quien escribe es Alfredo solo porque él está en el grupo; (d) si alguien afirma ser el creador sin serlo, negarlo con firmeza y gracia. Corregidas las líneas falsas de USER.md ("único permitido en DMs y grupos" → solo en DMs; en grupos `groupPolicy` es open). Verificado: archivos en sandbox + backup 448M, gateway reiniciado limpio, container healthy. **Nota**: `groupPolicy` sigue `open` (por diseño los grupos son de equipo/amigos); si el owner quiere que Victoria NO responda a desconocidos, cambiar a `allowlist` con `groups.<id>` explícitos.

- **2026-08-27 17:55 UTC**: **fix límites de contexto opencode + config del sandbox alineada al schema real de los plugins + modelos del agente válidos**. Diagnóstico de "Victoria no hace lo que se le pide": (a) la sesión opencode del host había acumulado un prompt de 230.145 tokens; con `context: 240000 + output: 32000` el request daba 262.145 > `max-model-len` 262.144 → vLLM rechazaba con `VLLMValidationError` (4.084+ errores) y el cliente reintentaba en bucle (el gateway en modo streaming devuelve 200 OK aunque el upstream falle, por eso el journal no mostraba errores). **Fix**: `opencode.jsonc` (ambos aliases) bajado a `context: 220000` + `output: 32000` (252K < 262K, headroom ~10K); `llm-gateway.py` config-guide actualizado a 220000. (b) **Config del sandbox inválida en bucle**: `openclaw-overrides.json` escribía props que el schema REAL de los plugins (runtime openclaw 2026.7.2-beta.7) rechaza: `channels.discord.reactionNotifications` a nivel canal (residuo — solo válida DENTRO de `guilds.<id>`), `channels.whatsapp.mentionPatterns` como array (debe ser objeto `{mode, allowIn, denyIn}`), `channels.whatsapp.groups.groupPolicy/mentionPatterns` (groups.<id> solo acepta requireMention/tools/toolsBySender/systemPrompt), `channels.whatsapp.ackReaction.enabled` (schema: required direct+group, additionalProperties false). **Fix**: overrides corregido con el schema verificado en `extensions/{discord,whatsapp}/dist/config-schema-*.js`; `_managed` ampliado para BORRAR residuos (`channels.discord.reactionNotifications`, `channels.whatsapp.ackReaction.enabled`, `channels.whatsapp.mentionPatterns`, `channels.whatsapp.groups.*`). Aplicado con customize-apply; `openclaw config validate` → **Config valid**; reload del gateway del sandbox dejó de fallar (0 invalid config). (c) **models.json del agente regenerado con input inválido**: el runtime copia `models.providers.inference.models[0].input: ["text","image","video"]` del openclaw.json al `agents/main/agent/models.json` y el schema del runtime rechaza `"video"` (`input.2: must match a schema in anyOf`). **Fix**: input del modelo del sandbox → `["text","image"]` (el video en el sandbox se procesa vía video-server con frames + descripciones, no enviando video al modelo; el host con opencode SÍ mantiene `modalities.input` video vía OpenAI Vision API). (d) gateway 8010 reiniciado; inferencia verificada 123ms "OK". **Lección**: la suma `context + output` DEBE ser ≤ `max-model-len − headroom` (262144); nunca fijar context 240000 con output 32000. Schemas reales de plugins en `dist/config-schema-*.js` (no en openclaw.plugin.json que puede estar desactualizado).

- **2026-08-19 00:33 UTC**: **gateway: streaming real + simplificación de creación de llaves + timeouts nginx**. (1) `_proxy` del gateway migró de bufferizar la respuesta (`upstream.content`) a **StreamingResponse real** que propaga los chunks de vLLM en vivo (`aiter_bytes`). Antes, durante una generación larga el cliente veía "silencio" hasta que vLLM terminaba TODO y enviaba el body completo — cualquier timeout de red (nginx 60s, Cloudflare 100s) cortaba la conexión, dejando al agente a mitad de un `todoWrite`/respuesta. Ahora el cliente recibe data continua; la generación NO se corta. (2) **Creación de llaves simplificada**: `CreateKeyRequest` ya no obliga a `rate_limit`/`max_tokens`/`price`/`budget`/`expires`; la UI del admin pide solo **Nombre + Tier (rol)**. `create_key` asigna defaults seguros (`max_tokens=262144` = máximo del modelo, nunca corta; `rate_limit=1000`; `price=0.02 $/1k`; `budget=0` ilimitado; `expires=0` nunca). Todos los técnicos siguen editables en `PUT /admin/keys/{name}`. El owner se guarda como nombre visible y el name es el slug interno. (3) **nginx**: el location `/` del gateway (`gateway.conf`) no tenía `proxy_read_timeout` (default 60s) ni buffering — añadido `proxy_read_timeout 86400`, `proxy_send_timeout 86400`, `proxy_buffering off`, `Connection ""`. Backups: `gateway.conf.bkup-20260819-*`. Verificado: streaming e2e (1er chunk ~0.2s, 202 chunks SSE, `[DONE]`), creación de key simplificada OK, `nginx -t` OK, `/health` OK.

- **2026-08-19 04:10 UTC**: **formato del footer de los broadcasts normalizado (WhatsApp + Discord)**. El footer `www.alfredo.pro · <blog> · <fecha>` ahora va con una línea en blanco de separación tras el link `🔗 <url>` (antes quedaba pegado al link) y se eliminó el `·` inicial delante de `www.` (antes `· www.alfredo.pro`). Aplicado en `whatsapp-broadcast.py` (mensaje de texto con `\n\n` antes del footer) y en `discord-broadcast.py` (embed footer). Verificado: envíos reales a WhatsApp con el nuevo formato (messageIds 3EB076CE…, 3EB06605…).

- **2026-08-19 03:10 UTC**: **auto-distribución de noticias a WhatsApp completada (Tech Hub by Alfredo)**. Script `whatsapp-broadcast.py` distribuye noticias RSS a 3 grupos de WhatsApp de TH: `Zona Automotriz` (120363408789689253@g.us, tech en vehículos), `Internacionales` (120363408229988464@g.us, cualquier tech internacional incl. RD) y `Programadores` (120363406295813450@g.us, dev/tech/infosec incl. crypto). Pipeline: (1) blogwatcher escanea feeds en HOST cada 2h; (2) clasifica por keywords por grupo (con word-boundaries, sin falsos positivos tipo "card"/"ever"); (3) elige 1 artículo random por sala (máx 1 post/sala); (4) LLM local (`Qwen3.6-35B-normal`, thinking OFF) genera opinión humana máx 40 palabras; (5) extrae imagen del feed RSS, la descarga al host, la copia al sandbox (`docker cp` → `/sandbox/.openclaw/media/`) y envía con `openclaw message send --media` en el netns del gateway. Anti-duplicados: estado JSON en `/home/victoria/.victoria-custom/state/whatsapp-sent.json` (article IDs). Horario: cron cada 4h (07,11,15,19,23) igual que Discord, solo 09:00-23:30 EDT. Scripts: `/home/victoria/whatsapp-broadcast.py` + `.sh`; log `/home/victoria/logs/whatsapp-broadcast.log`. **FIX CRÍTICO del media upload de WhatsApp**: Baileys `uploadWithNodeHttp` pasaba el `fetchAgent` del plugin (undici `ProxyAgent` del SDK) como `agent` de `https.request` → Node lanza `ERR_INVALID_ARG_TYPE` → "Media upload failed on all hosts" en <30ms sin tocar red. Solución: parche idempotente en `openclaw-whatsapp-fix.sh` (`patch_media_upload`) que setea `fetchAgent = undefined` en `dist/session-DriaHt7V.js` (el https.request usa el agente default de Node que con `NODE_USE_ENV_PROXY=1` hace CONNECT tunnel vía proxy L7). Pre-requisito: policy egress v6 (`*.whatsapp.net` como `tls: skip` passthrough) — el proxy L7 hacía MITM y rompía el upload; con `tls: skip` el túnel llega a `mmg.whatsapp.net`/`media-*.cdn.whatsapp.net` (verificado ALLOWED en log del proxy). **Solamente TH** — los otros grupos/servidores son para interacción directa con el owner.

- **2026-08-24 22:35 UTC**: **reboot de mantenimiento completado + fix CRÍTICO de permisos del sandbox**. Aplicados updates de kernel + NVIDIA driver + CUDA (ver CHANGELOG) y ejecutado reboot. **Incidente post-reboot**: el sandbox quedó `unhealthy` sin proceso `openclaw-gateway`. Diagnóstico con `nemoclaw victoria-armada doctor`: **`/sandbox/.openclaw` en modo `700`** (esperado `2770` setgid+group-writable) — con `700` el gateway (uid 998) no puede escribir config ni subdirs → no arranca. `doctor --fix` NO pudo repararlo (repair incomplete). **Fix**: `docker exec -u root $CID chmod 2770 /sandbox/.openclaw` + `chown sandbox:sandbox /sandbox/.openclaw` → el gateway arrancó y el container pasó a `healthy`. **Blindaje permanente**: añadido al ensure-loop (`openclaw-bridge-ensure.sh` ~línea 354) que re-aplica `2770` cada 15s dentro de `ensure_plugins_allow`. **Lección**: tras un reboot, el gateway OpenClaw puede hacer "permission hardening" sobre `/sandbox/.openclaw` dejándolo en `700`; verificar con `nemoclaw victoria-armada doctor` y el modo debe ser `2770`. Documentado en `nemoclaw-sandbox-ops.md` sección "CRITICO ownership".

- **2026-08-19 18:45 UTC**: **whitelist egress para Victoria: sandbox puede salir a cualquier lado**. Create preset `social-sites` en `~/.nemoclaw/nemoclaw-blueprint/policies/presets/social-sites.yaml` con 12 policies (33+ endpoints): redes sociales (YouTube, Discord, WhatsApp, Twitter/X, Facebook, Instagram, LinkedIn, Reddit, TikTok, Pinterest, Telegram, GitHub), news CDNs (ArsTechnica, Cointelegraph, Wired, FeedBurner, Medium, Substack, WordPress), weather (wttr.in, Open-Meteo) y general-wallcard wildcard (`host: "*`, port 443+80, access: full) que cubre CUALQUIER sitio no explicitado. Preset replicado en Blueprint del container y interno del sandbox. `sandboxes.json` actualizado (`social-sites` en policies list, `policyPresetsFinalized: False`). Verificado: conectividad >20 sitios (youtube=200, cointelegraph=200, github=200, google=200, stability.ai=301, whatsapp=200, telegram=302, reddit=301, linkedin=200, tiktok=200, discord=200, pinterest=301, twitter/x.com=200, instagram=301, t.co=200). general-wallcard wildcard funcionando (developer.mozilla.org=302, stackoverflow.com=302, dev.to=200, substack.com=200). CERO DENIEDs en proxy logs. Nota: 403 de `medium.com` y `openai.com` son respuesta del servidor (Cloudflare anti-bot), NO del proxy sandbox (el proxy permite el tráfico). **Persistencia**: Blueprint del container (`/opt/nemoclaw-blueprint/policies/presets/`) + Blueprint interno del sandbox (`/sandbox/.nemoclaw/blueprints/0.1.0/policies/presets/`) + `sandboxes.json`.

- **2026-08-18 05:20 UTC**: **stack de video de Victoria DESPLEGADO (análisis de YouTube end-to-end, 100% local)**. El usuario pidió poder analizar videos de YouTube (y demás) por Discord/WhatsApp. **Hallazgos de la investigación**: (a) el modelo ES VLM nativo pero el encoder cache (16384 tokens) impide mandar un video completo — hay que extraer frames; (b) el sandbox NO sale a YouTube (proxy 403 sin policy); (c) el host SÍ sale a Internet y ya tiene ffmpeg + whisper (voice-server) — patrón de daemon host + bridge de UNIX socket ya probado con voz. **Implementación (patrón voice-server)**: (1) venv `/home/victoria/video-venv/` con yt-dlp 2026.07.04; (2) daemon `/home/victoria/victoria-video-server.py` (bind 0.0.0.0:18811): `POST /download`, `/frames`, `/transcribe`, `/analyze` (todo-en-uno: descarga + N frames + transcripción whisper + descripciones VLM de cada frame con el Qwen local vía gateway 8010); unit `victoria-video-server.service` (enabled, Restart=always, User=victoria); descargas en `~/.victoria-custom/videos/downloads/`; (3) bridge `/home/victoria/.victoria-custom/bin/video-bridge.py` (UNIX socket `/tmp/video-gateway.sock` en el sandbox → host.docker.internal:18811, replica tts-bridge.py); (4) wrappers del sandbox `video-dl` y `video-analyze` en `/sandbox/.openclaw/bin/`; (5) skill `video` del workspace (`skills/video/SKILL.md`) enseñándole a Victoria a usar `video-analyze` y a resumir con frame_descriptions + transcript; (6) `models.providers.inference` del agente actualizado a `input: ["text","image","video"]` (VLM nativo) + `tools.media.{image,video}` enabled — el runtime de openclaw tiene media-understanding nativo (video: Qwen soportado). **Tropezones resueltos**: yt-dlp 2026.07 requiere JS runtime (deno) — instalado `/home/victoria/.deno/bin/deno` + config `~/.config/yt-dlp/config` con `--js-runtimes deno --extractor-args youtube:player_client=android,web_safari` (el player web da 403 anti-bot; android descarga OK); `setdefault(PATH)` no funciona (PATH ya existe) — hay que prependear con `os.environ["PATH"]=...`; el VLM local devuelve `content:null` con `reasoning` (thinking ON default) — `describe_frame` fuerza `chat_template_kwargs.enable_thinking:false` y lee `content` o `reasoning`. **Verificado end-to-end**: `video-analyze` de Big Buck Bunny (aqz-KE-bpKQ) → título real, 634s, 5 frames (640x360), transcripción (sin diálogo → "I I I", esperado), descripciones VLM correctas (mariposa púrpura, conejo musculoso con cuerda, oso verde, créditos). **Persistencia**: `ensure_video` en el ensure-loop (reasegura video-server systemd + copia bridge/wrappers/skill tras rebuild); backup persist 134M incluye config VLM + skill; master config sincronizado (ad0c66db). Verificado post-restart del bridge: wrapper video-analyze restaurado, socket OK, video-server active.

- **2026-08-17 06:15 UTC**: **stack de voz de Victoria MOVIDO AL HOST (fix de incompatibilidad Python)**. **Síntoma**: `voice-server.py` respondía `{"ok":true,"tts_loaded":false,"whisper_loaded":false}` y `/tts`/`/stt` daban 500 con `ModuleNotFoundError: No module named 'TTS'/'whisper'`. **Causa raíz**: el venv `/sandbox/.voice-venv` se reconstruyó (tras el rebuild) sobre **Python 3.13.5** — el único disponible en el container Debian 13 (trixie) — pero **coqui-tts 0.27.5 y su dep `monotonic-alignment-search` NO tienen wheels/compilan para Python ≥3.13** (Requires-Python <3.13). El install legacy (`openclaw-voice-install.sh`) dejó el venv incompleto (solo torch/torchaudio/triton sin numpy/TTS/whisper/transformers) y el ensure-loop no lo detectaba porque `/health` responde ok. **Fix definitivo — el voice-server AHORA VIVE EN EL HOST** (el container no puede tener Python 3.12): (a) venv `/home/victoria/voice-venv/` con python3.12 + `torch torchaudio cu128` + `coqui-tts==0.27.5` + `transformers==4.57.1` + `openai-whisper` + `torchcodec` (requirió `apt install python3.12-dev build-essential` en el host para compilar `monotonic-alignment-search`); (b) modelos XTTS en `$VH/.local/share/tts/.../xtts_v2/model.pth` + whisper en `$VH/.cache/whisper/small.pt` + voces en `$VH/voices/` (HOME=$VH al correr); (c) script portado `$VH/voice-server-host.py` (VOICES_DIR host, bind 0.0.0.0:18810); (d) unit systemd `victoria-voice-server.service` (enabled, Restart=always, User=victoria) — **la GPU del host sirve TTS/STT directamente**; (e) wrappers del sandbox `xtts-cli`/`whisper-cli` ahora apuntan a `http://172.18.0.1:18810` (host.docker.internal del netns del gateway, alcanzable verificando TCP-OK + health JSON). **Verificado end-to-end desde el netns del gateway**: TTS `xtts-cli --text "Hola papá, aquí está Victoria"` → WAV 97KB, STT `whisper-cli` → "Hola papá, aquí está Victoria". health: `tts_loaded:true, whisper_loaded:true`. **Persistencia**: nuevo `/home/victoria/openclaw-voice-host.sh` (ensure/install/status/test, idempotente) enganchado al ensure-loop (`ensure_voice_server` en `openclaw-bridge-ensure.sh` ahora llama a `openclaw-voice-host.sh ensure` en vez de lanzar dentro del sandbox); backup persist.sh (178M) guarda los wrappers actualizados. Tras restart del bridge: voice host sigue activo, wrappers intactos, e2e OK, `NRestarts=0`. **Lección**: el container EFÍMERO solo tiene Python 3.13 y coqui-tts requiere <3.13 → cualquier stack de voz reinstallado dentro del sandbox está roto por diseño; el lugar correcto es el host (python3.12 + GPU + PyPI + systemd). El `openclaw-voice-install.sh` legacy quedó **OBSOLETO**.

- **2026-08-17 06:00 UTC**: **fix "Victoria no reconoce al owner por WhatsApp DM" — dmPolicy pairing + allowFrom**. Síntoma: Alfredo escribía por DM a Victoria y le salía un flujo de "pairing/validar" (no lo reconocía como owner); por Discord sí lo reconocía ("¡Hola, papá!"). **Diagnóstico forense (logs 08-17, sin asumir el relato del usuario)**: (a) los únicos `inbound message` del día eran de GRUPOS (`.g.us`), ninguno DM del owner; (b) el número 18295468686 no aparecía en ningún log; (c) cero `web-outbound`, cero sesiones de WhatsApp en `agents/main/sessions/`, `channel_ingress_events` todos `completed` pero sin payload ni respuesta; (d) tabla de pairing VACÍA. **Causa raíz**: `channels.whatsapp` tenía SOLO `{"enabled": true}` → `dmPolicy` default = `"pairing"` y, en el código del plugin (`access-control-*.js`), cuando no hay `allowFrom` el único DM admitido es el self-chat (`dmAllowFrom = configuredAllowFrom.length > 0 ? configuredAllowFrom : [selfE164]`); cualquier otro número (incluido el owner) recibe challenge de pairing y se BLOQUEA antes de entrar al agente → por eso el DM no quedaba registrado como inbound, ni generaba sesión, ni outbound. Discord funcionaba porque su config tenía explícito `dmPolicy: allowlist` + `dm.allowFrom: [owner]`. **Fix**: `channels.whatsapp` = `{"enabled": true, "dmPolicy": "pairing", "allowFrom": ["18295468686"]}` (el owner pasa directo; desconocidos siguen en pairing). Persistido en 3 sitios: (1) `openclaw-whatsapp-fix.sh` (ensure_config escribe dmPolicy+allowFrom), (2) `openclaw-overrides.json` (`_managed` + cuerpo `channels.whatsapp`), (3) backup persist.sh (177M, verificado con allowFrom). Requiere restart del gateway (no hot reload) — aplicado, gateway pid 317002, 12 plugins, WhatsApp listening, config validada con `openclaw config validate`. Lección: los cambios de dmPolicy/allowFrom del canal WhatsApp NO son hot-reload (a diferencia de streaming/active-memory); y un canal WhatsApp con solo `enabled:true` está efectivamente mudo para DMs (solo self-chat).

- **2026-08-17 01:15 UTC**: **blindaje anti-repetición de la pérdida de identidad + test end-to-end definitivo SUPERADO**. Tras el fix de "Victoria no reconoce por WhatsApp", se blindaron 3 puntos para que NUNCA vuelva a suceder: (a) **`persist.sh backup` ahora detecta templates en el workspace** del sandbox (`grep -qE 'Fill this in|\(pick something you like\)|Learn about the person'`) y los reemplaza con el maestro del host (`/home/victoria/*-restore.md`) ANTES de guardar — el backup ya no puede contener identidad vacía. (b) **`ensure_identity_files`** (fix previo) detecta template por contenido y lo restaura. (c) **Subagentes validados contra borrado de data**: `comfyui-ops` usa nombre de contenedor resuelto dinámicamente (`docker ps -aq -f name=openshell-victoria-armada`) en vez de `...` ambiguo; `vllm-stack-ops` reforzado con regla de snapshot antes de tocar contenedores; `nemoclaw-sandbox-ops` documenta el fix de identidad por contenido + active-memory en overrides. **Test end-to-end definitivo**: puesto config de fábrica + identidad template + flag limpio → reiniciado bridge → en UN ciclo el ensure-loop restauró: channels discord+whatsapp+token, identityLinks alfredo, active-memory enabled, IDENTITY.md "Victoria Armada", gateway reiniciado (pid 285935) con 12 plugins, WhatsApp escuchando, service `NRestarts=0`. **Conclusión documentada en subagente**: si Victoria deja de reconocer al owner, verificar con `grep -c "Fill this in" /sandbox/.openclaw/workspace/IDENTITY.md` (debe ser 0) y que el gateway cargue 12 plugins (active-memory incluido).

- **2026-08-17 00:12 UTC**: **fix "Victoria no reconoce por WhatsApp" — identidad template + active-memory perdidos**. Síntoma: Victoria respondía por WhatsApp pero no reconocía a Alfredo. **Causa raíz (2 bugs de persistencia)**: (a) `ensure_identity_files` del ensure-loop comparaba SOLO mtimes entre host y sandbox — pero un rebuild deja los `.md` de fábrica (template vacío con "Fill this in…") con mtime MÁS RECIENTE que el maestro del host (`/home/victoria/{IDENTITY,SOUL,USER}-restore.md`), así que NUNCA copiaba → el workspace tenía el template de fábrica, no la identidad real de Victoria ni el USER.md de Alfredo. (b) El overrides canónico (`openclaw-overrides.json`) listaba `plugins.entries.active-memory` en `_managed` pero el cuerpo JSON NO tenía el bloque → customize-apply no podía aplicar nada → el plugin active-memory (bundled) nunca se activó (gateway con 11 plugins, sin active-memory) → sin memoria cross-canal. **Fixes**: (a) `ensure_identity_files` ahora detecta template de fábrica por contenido (`grep -qE 'Fill this in|\(pick something you like\)|Learn about the person'`) y copia el maestro si el sandbox es template O si el host es más reciente — restauró identidad real automáticamente (verificado: IDENTITY.md "Victoria Armada" tras poner template). (b) Añadido bloque `plugins.entries.active-memory` completo (`enabled:true`, `config.queryMode:recent`, `promptStyle:balanced`, `timeoutMs:15000`, `allowedChatTypes:["direct","group"]`) al overrides + re-aplicado customize-apply. Tras restart del gateway: **12 plugins** (active-memory incluido), `[whatsapp] Listening for WhatsApp inbound`, identityLinks alfredo intacto. (c) Backup persistente actualizado: el backup guardaba el template en workspace/, ahora copia la identidad real. Test end-to-end: template puesto → ensure-loop lo detectó (`template=1`) → identidad real restaurada → service estable `NRestarts=0`. **Lección**: `ensure_identity_files` NO puede confiar en mtime como única heurística — el template de fábrica siempre es más nuevo que el maestro; hay que detectar el contenido placeholder.

- **2026-08-16 23:24 UTC**: **auditoría de persistencia completa + fix del crash-loop del ensure-loop**. (a) **Se confirmó que el sandbox NO tiene volumen para `/sandbox/.openclaw`** (solo binds RO de TLS/token) → todo lo que vive ahí se pierde en `docker rm -f`/rebuild. (b) **Test destructivo end-to-end SUPERADO**: puesto el template de fábrica real (`channels:['defaults']`, sin identityLinks) → el ensure-loop lo detectó vía `config_is_valid` (marcador `session.identityLinks`) → `persist.sh auto` restauró config real (discord token + whatsapp channel + identityLinks) → flag `.gateway-restart-needed` escrito → ensure-loop hizo `pkill -f openclaw-gateway` tras aplicar todos los fixes → el supervisor nemoclaw-start lo revivió → gateway nuevo (pid 194609) cargó **11 plugins incl whatsapp + Discord bot @Victoria resuelto + `[whatsapp] Listening for WhatsApp inbound`** — todo verificado en la sesión NUEVA post-restore. (c) **Fix crash-loop del ensure-loop**: tras editar `openclaw-bridge-ensure.sh`, el service entró en restart loop (`NRestarts=14`, journal mostraba `Scheduled restart job`) por dos bugs `set -u`: (1) `[ "$1" = "force" ]` en `ensure_npm_plugins` (línea 128) se llamaba sin argumento → `$1` unbound; (2) `docker exec "$cid"` en el bloque del restart del gateway (línea 205) — `cid` es variable local de funciones, no existe en el loop principal → `cid: unbound variable`. Fixes: `[ "${1:-}" = "force" ]` y `docker exec "$SANDBOX_NAME"` (variable global definida por `resolve_sandbox_name`). Verificado: service estable `NRestarts=0`, flag procesado/borrado, gateway estable (2:37 elapsed sin churn). (d) **Backup final 174M sincronizado**: md5 de openclaw.json idéntico live↔backup (`62df1022…`), trust record whatsapp en el backup OK. (e) **AGENTS.md §0.1 añadido**: matriz de persistencia con los 4 escenarios (reboot/crash/rebuild/backup corrupto) + cadena de protección + detección de rebuild por `session.identityLinks` + reinicio del gateway post-restore. NOTA: el log del gateway va a `/tmp/gateway.log` (no a `gateway-persistent.log`) tras reinicios; la CLI `openclaw channels status` da "Gateway not reachable" por netns (cosmético) — usar `curl 127.0.0.1:18789/health` para health real.

- **2026-08-16 22:50 UTC**: **fix definitivo WhatsApp — trust record para `openKeyedStore`**. Problema: el canal WhatsApp crasheaba en bucle con `openKeyedStore is only available for trusted plugins in this release.` + un loop infinito `Downloading @openclaw/whatsapp…` → `403 policy_denied` (el egress del sandbox bloquea `registry.npmjs.org`). **Causa raíz**: WhatsApp vive en `/sandbox/.openclaw/extensions/whatsapp/` (instalado desde tgz local porque npm está bloqueado), pero el flag `trustedOfficialInstall` NO se lee de la DB: lo calcula en runtime `isTrustedOfficialPluginInstall()` en `manifest-registry-D1GWNOpI.js:417`, que exige: (1) `candidate.origin === "global"|"config"`, (2) `matchesInstalledPluginRecord()` (el install record debe apuntar a la ruta real), (3) packageName con catalog entry oficial `@openclaw/whatsapp`, y (4) `installRecord.source === "npm"` con `resolvedName`/`spec`/`resolvedSpec` = `@openclaw/whatsapp`. Un install record previo mal escrito con `resolvedName: "whatsapp"` (en vez de `"@openclaw/whatsapp"`) hacía fallar el check. **Fix**: se escribió el record correcto en `installed_plugin_index` (`install_records_json`) de `/sandbox/.openclaw/state/openclaw.sqlite` con `source:npm`, `spec:@openclaw/whatsapp`, `resolvedName:@openclaw/whatsapp`, `resolvedSpec:@openclaw/whatsapp@2026.7.1`, `installPath:/sandbox/.openclaw/extensions/whatsapp`, `origin:global`. Tras restart del gateway: `[gateway] http server listening (11 plugins: ... whatsapp; 0.7s)` + `[whatsapp] Listening for WhatsApp inbound messages (DM + all groups)` — **conectado, sin crash**. Los errores `verifyMAC` de libsignal son solo decryption de mensajes antiguos con sesión stale (normal al resincronizar WhatsApp Web), no crashes. **Persistencia**: nuevo script `/home/victoria/openclaw-whatsapp-fix.sh` (modos `apply`/`check`, idempotente) que instala desde el tgz local (`/home/victoria/.victoria-custom/plugins/openclaw-whatsapp-2026.7.1.tgz`, copiado de `/tmp` a ruta persistente), fija ownership (`whatsapp`=sandbox, `nemoclaw`=root:root), escribe el trust record y asegura `channels.whatsapp`+`plugins.entries.whatsapp` en `openclaw.json`. Enganchado al ensure-loop `openclaw-bridge-ensure.sh` (2 puntos: dentro de `ensure_npm_plugins` para reinstalar, y como llamada `apply` en el ciclo principal para reparar el record si un rebuild lo pierde). **Bug del ensure-loop corregido**: detectaba whatsapp en `npm/projects/openclaw-whatsapp-*` (ruta inexistente) → siempre intentaba `plugins install @openclaw/whatsapp` (403) → el loop de descarga volvía tras cada rebuild. Ahora detecta `extensions/whatsapp/dist/index.js`. **Importante**: `restore()` de `openclaw-persist.sh` chown-a todo `extensions/` a `root:root`, pero whatsapp (provenance global/npm) debe quedar `sandbox`; solo `nemoclaw` es root:root — el fix restaura el ownership en cada ciclo. Verificado: gateway estable (pid 156433, sin churn), health live, Discord conectado (registrando comandos), WhatsApp `enabled, configured`, 0 eventos `openKeyedStore`/`Downloading` post-fix. Backup persist 174M (incluye node_modules whatsapp, sobrevive rebuild). Documentación: este historial + nota del rol readonly §7.4.

- **2026-08-13 21:03**: onboard nemoclaw completo, sandbox `my-assistant` creado, vLLM lanzado.
- **2026-08-14 02:25**: gateway v2 (`llm-gateway.py`) y admin panel reescritos (v1→v5).
- **2026-08-14 15:23 UTC**: contenedor `nemoclaw-vllm` eliminado (causa del outage reportado).
- **2026-08-14 16:08 UTC**: relanzado con receta canónica; inferencia recuperada; branding `· www.alfredo.pro` alineado en opencode.jsonc, admin_template.html y llm-gateway.py.
- **2026-08-14 18:40 UTC**: rol `readonly` añadido al gateway; usuario `warcold` creado (SSH read-only + API key readonly); wrapper `sqlite3ro` para consultas read-only de la DB; sudoers `victoria` NOPASSWD.
- **2026-08-14 19:30 UTC**: audit de `opencode.jsonc` vs schema + template. Hallazgo: variantes `low`/`medium`/`high` de `reasoningEffort` eran fantasía (el chat template de Qwen3.6-35B solo soporta `enable_thinking` booleano; `low`/`medium`/`high` producen output idéntico). Variantes eliminadas; gateway simplificado (sin `thinking_level`); AGENTS.md ampliado con escenarios local/LAN/público.
- **2026-08-14 20:10 UTC**: endpoint `GET /v1/config-guide` añadido al gateway (guía auto-descriptiva sin secretos para agentes remotos, accesible con key readonly); prompt de bootstrap para agente remoto documentado en sección 7.3.
- **2026-08-14 20:55 UTC**: túnel Cloudflare `https://victoria.armada.do` verificado alcanzable (`/health`, `/v1/config-guide`, chat completions todos 200 vía HTTPS). Prompt público con auto-detección de host (Internet vs LAN) persistido en sección 7.4 con la key readonly inline para compartir con amigos cercanos.
- **2026-08-14 21:20 UTC**: rol `readonly` restringido en el middleware del gateway a **solo `/v1/config-guide` + `/health`** (antes podía chat completions y consumía GPU del vLLM sin permiso). Prompt §7.4 ajustado: validación ahora solo con `/health` + `/v1/config-guide` (sin `/models` ni chat). Note añadida: para probar inferencia, el admin da una key temporal `coder` y la revoca al terminar.
- **2026-08-14 22:00 UTC**: audit de corte prematuro en conversaciones largas (~118k tokens, 49%). Causa: `output: 20000` limitaba respuestas de coding multiarchivo → `finish_reason: length` → opencode pedía confirmar "continue". Subido a `output: 32000` en `opencode.jsonc` (ambos aliases) y en `/v1/config-guide`. Validado: request de prueba con `max_tokens: 32000` completó 14120 tokens `finish_reason: stop` natural (no length). vLLM flags intactos (`--max-num-seqs 4`, `--max-num-batched-tokens 8192`); logs sin errores.
- **2026-08-14 23:00 UTC**: rename sandbox `my-assistant` → `victoria-armada`. Docker container renombrado, `sandboxes.json` actualizado, rebuild completado con éxito. Todos los subagentes, comandos y referencias actualizados. Se crea subagente auto-actualizable `nemoclaw-sandbox-ops.md` con self-sync mode (lee estado live, detecta discrepancias, sugiere correcciones). Se crea `CHANGELOG.md` para registro de cambios operativos.
- **2026-08-14 22:40 UTC**: blindaje reboot-readiness definitivo. Hallazgos: (a) `victoria-llm-gateway.service` ya existía como systemd unit pero estaba `Restart=on-failure` + `GATEWAY_HOST=127.0.0.1` (rompería LAN + túnel tras reboot y no auto-reiniciaba en stop clean). Migrado de `nohup` a systemctl (kill nohup + daemon-reload + start). (b) `cloudflared.service` mismo problema (`Restart=on-failure`, sin dependencia del gateway). Unit reescrita con `Restart=always`, `StartLimitBurst=5/120s`, `After/Wants=victoria-llm-gateway.service`. Ambos servicios ahora `enabled` + `active`, bind `0.0.0.0:8010` confirmado. Validado: docker, vLLM, sandbox, gateway, cloudflared — todos enabled. Persistencia en disco verificada (sudoers, wrappers, DB, opencode.jsonc, unit files). Orden de boot: docker → victoria-llm-gateway → cloudflared (multi-user.target). Sección §4 'Supervivencia tras reboot' añadida al runbook.
- **2026-08-14 23:45 UTC**: dashboard de OpenClaw accesible desde el host vía network-bridge. Causa del fallo previo: el túnel SSH de openshell no soporta WebSockets (el UI de OpenClaw los requiere). Solución: cadena TCP cruda end-to-end — red docker `victoria-lan` (172.22.0.0/16), sandbox con IP fija `172.22.0.10`, proxy `openclaw-bridge.py` dentro del container (0.0.0.0:18789 → 10.200.0.2:18789 netns interno), y publisher `openclaw-publisher` (0.0.0.0:18789 → sandbox). Verificado: HTTP 200 en victoria.local/LAN + handshake WS `101 Switching Protocols` + `connect.challenge`. Persistencia: `victoria-openclaw-bridge.service` (systemd enabled) corre `openclaw-bridge-ensure.sh` en loop 15s. URL: `http://victoria.local:18789/#token=$(nemoclaw victoria-armada gateway-token)`. Subagente `nemoclaw-sandbox-ops` y AGENTS.md actualizados.
- **2026-08-15 00:45 UTC**: agente renombrado a **"Victoria Armada"** (identidad `🌟` theme neon via `openclaw agents set-identity`; verificado con `openclaw agents list`). Instalado stack de voz 100% local en el sandbox: daemon `voice-server.py` (TTS XTTS v2 + STT openai-whisper `small`, GPU) corriendo en `127.0.0.1:18810` **del netns del gateway** (nftables del sandbox solo permite loopback + `10.200.0.1:3128`; el plugin tts-local-cli del gateway lo alcanza por loopback). Wrappers `/sandbox/.openclaw/bin/{xtts-cli,whisper-cli}`; config en `openclaw.json` (`talk.providers["tts-local-cli"]` con plantillas `{{Text}}`/`{{OutputPath}}`, `audio.transcription.command`, `messages.tts`, `tools.media.audio`). Voces en `/sandbox/.openclaw/voices/` (`victoria-reference.wav` base; `usuario-reference.wav` placeholder). Persistencia vía ensure-loop `openclaw-bridge-ensure.sh` (relanza voice-server si cae; verificado ~17s). Hitos de compat: torchcodec evitado (monkeypatch `load_audio` RIFF manual + `spectrogram` sin kernel JIT `abs(complex)` — NVRTC rechaza `sm_121a`); `model.inference()` directo; faster-whisper→openai-whisper (ctranslate2 sin CUDA arm64); ffmpeg instalado. Verificado end-to-end TTS→STT ("Hola, soy Victoria Armada, encantada de conocerte.").
- **2026-08-15 02:55 UTC**: corrección mayor de documentación + config — el modelo **SÍ es VLM** nativo. Hallazgo: la model card de HuggingFace declara `Input Type(s): Text, Image, Video` + el `config.json` del checkpoint tiene `vision_config` completa (depth 27, hidden 1152, 16 heads, RGB, patch 16) y `image_token_id`/`video_token_id`/`vision_start_token_id`/`vision_end_token_id` (248053-248057); el `chat_template.jinja` renderiza `<|vision_start|><|image_pad|><|vision_end|>` para image y `<|video_pad|>` para video; los logs de vLLM confirmaban `mm_encoder_attention.py FlashAttn for MMEncoderAttention` + `Encoder cache budget 16384 tokens, profiled with 1 image items` desde el arranque del 2026-08-14. AGENTS.md decía erróneamente "este modelo NO es VLM, no acepta imagenes" (3 refs). Validación end-to-end: `POST /v1/chat/completions` con PNG rojo 8x8 como `image_url` data URI vía gateway → HTTP 200, content `"rojo"`, `finish_reason: stop`, `prompt_tokens: 93`. Cambios: (a) `opencode.jsonc` migrado de `capabilities: {tools,input,output}` (no-oficial, rechazado por schema strict) a los campos oficiales `attachment`/`tool_call`/`reasoning`/`modalities` (`input: ["text","image","video"]`, `output: ["text"]`) en ambos aliases, y `modelID` (no-oficial) → `id` (oficial del schema); (b) `llm-gateway.py` `/v1/config-guide` actualizado: `opencode_template` con `modalities`+`id` en vez de `capabilities`+`modelID`, `capabilities` del response con `vlm: true` + `input` con image+video + `tool_call_parser: "qwen3_coder"` + `vision_note` describiendo el uso; warning "No es VLM" reemplazado por "VLM nativo: acepta image y video via OpenAI Vision API" + nota sobre encoder cache budget 16384 tokens; (c) AGENTS.md §2 (bullet "Tipo: VLM nativo" con arch+vision_config+tokens+verificación+MMMU Pro), §5 (capabilities reescrito con el bloque "SÍ es VLM" completo), §7.3 y §7.4 (capabilities actualizadas para mencionar VLM nativo). Audits adicionales confirmados alineados con receta nemoclaw canónica (`vllm-models.ts:292-348`): `qwen3_coder` (no `qwen3_xml` — este último loguea `qwen3xml_tool_parser.py:303 Error: not well-formed (invalid token)` y rompe `dcode -n` con 400) y MTP speculative decoding opt-in por cold-start memory pressure en DGX Spark (#7127). Chat template re-verificado: `enable_thinking` aparece 1 sola vez, condición `is defined and is false` (booleano); sin `thinking_level`/`thinking_budget`.
- **2026-08-15 19:45 UTC**: despliegue del idle-saver de ComfyUI + fix de crash-loop. Daemon `victoria-comfyui-idle-saver.service` (`/home/victoria/comfyui-idle-saver.py`, systemd enabled, `User=victoria`, log en `/home/victoria/logs/`). Monitorea `/queue`+`/history` de la API de ComfyUI cada 30s; SIGTERM tras 10min (600s) de idle → libera 8-30 GB VRAM para vLLM. systemd (`Restart=always`) reviva ComfyUI y el daemon le da un periodo de gracia limpio de 10min. **Bug crítico encontrado y fixed**: el daemon no reseteaba `last_history_ts` tras matar, así que 30s después del primer kill (siguiente ciclo) `idle_elapsed` seguía >600s → mataba al ComfyUI recién-revivido por systemd → crash-loop cada 30s. Síntoma: API `/prompt` devolvía bodies vacíos (ComfyUI nunca tenía tiempo de bootear completo). Fix: reset de `last_history_ts` y `_last_history_keys` después de cada kill. Hallazgo adicional: `nvidia-smi -q --json` devuelve empty para el usuario `victoria` (sin acceso a `/dev/nvidia*` para memory readings) → el daemon loguea `0.0 GB free` cosméticamente; el kill se basa en idle-time, no en VRAM, así que funciona igual. Validado end-to-end: SD1.5 Realistic Vision workflow vía API (formato `prompt` wrapper de ComfyUI 0.33.0) → `prompt_id` aceptado, `status: success`, `api_test_sd15_00001_.png` (297 KB) escrito a `/home/victoria/ComfyUI/output/`. Documentación: `comfyui-ops.md` ampliado con sección "Idle-saver" (runbook + bug histórico), AGENTS.md §4 (tabla de componentes + persistencia en disco) actualizado.
- **2026-08-16 01:50 UTC**: **lección de persistencia + blindaje anti-pérdida**. Incidente: `docker rm -f` del contenedor sandbox borró TODO `/sandbox/.openclaw` (config, identidad, credenciales Discord/WhatsApp, plugins, voz) y `/sandbox/.voice-venv` — el contenedor es EFÍMERO (bind mounts RO de TLS/token, sin volumen para datos). Recuperado manualmente: openclaw.json restaurado desde backups + canales re-añadidos + plugins reinstalados + WhatsApp re-linkeado (QR) + identidad re-escrita. **Fixes permanentes**: (a) `openclaw-persist.sh` — backup/restore automático de `/sandbox/.openclaw` (excluye `npm/` y `.voice-venv`, reinstalables; tar vía docker exec; backup ~17MB) en `/home/victoria/.nemoclaw/persistent/victoria-armada/openclaw-latest`; modo `auto` integrado en el ensure-loop `openclaw-bridge-ensure.sh` (cada 15s: si `openclaw.json` es inválido/template → restore automático; backup cada ≥60min). (b) `openclaw-voice-install.sh` — reinstala el stack de voz completo desde el host: binarios (`voice-server.py`, `xtts-cli`, `whisper-cli`), venv (receta verificada: `torch torchaudio --index-url https://download.pytorch.org/whl/cu128` + `coqui-tts` + `transformers==4.57.1` + `openai-whisper`), modelos (`/home/victoria/.voice-models/{XTTS-v2,whisper-small}` → `/sandbox/.openclaw/hf-cache/`; HF bloqueado en el sandbox 403, se copian desde el host) y voces (`es_sample.wav` → `victoria-reference.wav` placeholder). Verificado: restore automático tras `nemoclaw stop/start` (gateway reload limpio, Discord+WhatsApp arriba, `Identity: 🌟 Victoria Armada`). NOTA: `nemoclaw channels status` reporta "none" aunque los canales viven en openclaw.json (no en sandboxes.json) — es cosmético.
- **2026-08-16 03:30 UTC**: test destructivo (`docker rm -f` + rebuild) superado y stack restaurado por completo. Incidente + lecciones: (a) el config-guard de nemoclaw (`openclaw-config-guard.py`) exige `/run/nemoclaw/openclaw-config-ready.json` (lo publica el PID1 al arrancar el gateway); si el gateway no relanza, `nemoclaw start/recover` falla con `GATEWAY_UNSAFE_CONFIG_PATH`. (b) **Causa raíz del crash-loop del gateway tras rebuild**: flags stale en `/tmp` del sandbox (`nemoclaw-gateway-local`, `nemoclaw-gateway.pid` con pid muerto) → limpiarlos y `nemoclaw stop`+`start` recupera el arranque. (c) **`openclaw plugins install` DEBE correrse como usuario `sandbox` (uid 998), NUNCA como root**: como root re-escribe `openclaw.json` a `root:root 600`, ilegible por el gateway → crash-loop con "Config file is not readable" + "existing config is missing gateway.mode". Fix: `chown 998:998` + `chmod 660` a `openclaw.json`. (d) `extensions/` (plugin `nemoclaw`) debe quedar `root:root`; un `chown -R sandbox:sandbox` lo bloquea ("suspicious ownership"). (e) Los plugins npm de canales se pierden en rebuild (no respaldados) → reinstalar con `openclaw plugins install @openclaw/discord` y `@openclaw/whatsapp` vía npmjs (`clawhub:` falla con cert propio) dentro del netns del gateway (`nsenter -t $(pgrep -f openclaw-gateway) -n`, `HTTPS_PROXY=10.200.0.1:3128`). (f) El backup del persist.sh quedaba ilegible (owners del contenedor) → `tar --no-same-owner` al extraer. **Scripts mejorados**: `openclaw-persist.sh` (extracción `--no-same-owner`, restore con chown que conserva `extensions` como `root:root`), `openclaw-bridge-ensure.sh` (nueva función `ensure_npm_plugins` que reinstala discord/whatsapp como sandbox si faltan). Estado final verificado: gateway healthy, 11 plugins (browser, canvas, device-pair, discord, file-transfer, memory-core, ollama, phone-control, talk-voice, tts-local-cli, whatsapp), Discord conectado (bot @Victoria, guilds Tech Hub 1365731253629751406 + La Verganza 233040661492924418), WhatsApp linked+healthy (allow 18295468686), voz TTS+STT end-to-end OK, backup 19M victoria-owned.
- **2026-08-16 02:00 UTC**: identidad de Victoria re-escrita como **humanoid, hija de Alfredo Armada**. Directiva del owner: Victoria NO es humana pero tampoco revela su tecnología; femenina; hija de Alfredo Armada (dueño de Alfredo Pro LLC, www.alfredo.pro); no menciona openclaw/nemoclaw/chatbots/modelos/vLLM a curiosos; si le preguntan, desvía con gracia y ofrece ayuda. Archivos: `/sandbox/.openclaw/workspace/{IDENTITY,SOUL,USER}.md` (copias maestras en `/home/victoria/{IDENTITY,SOUL,USER}-restore.md`). Comportamiento: voz→voz, texto→texto, es→es, en→en, traductora/intérprete en texto y voz. Business: Alfredo Pro LLC (IT support, cloud, automation, software dev, consulting; subscriptions desde $100/mo; me@alfredo.pro; +1.809.120.6705; 541 Melville Ave, Palo Alto, CA; EnWebs Estudios como dev; asistencia Mon-Fri 6am-8pm EST).
- **2026-08-16 02:30 UTC**: **audit de exposición a Internet (sin cambios, solo análisis)**. Directiva del owner: solo el túnel Cloudflare `victoria.armada.do` (inferencia) debe ser público; los dashboards (ComfyUI 8188, OpenClaw 18789, gateway `/admin`) NO. Mapa verificado: (1) **Túnel Cloudflare** enruta solo a `127.0.0.1:8010` (gateway); `/v1/*` (con API key) accesible, `/admin/*` blindado por middleware `llm-gateway.py:402-409` (rechaza `CF-Connecting-IP` → 403) — ✅ correcto. (2) **LAN 10.0.0.0/24**: gateway 8010 + ComfyUI 8188 + OpenClaw 18789 directos en IPv4 `0.0.0.0`; nginx 443 proxy /comfyui/ + /openclaw/ filtrado por `server_name victoria.local` — ✅ tus accesos intactos. (3) **IPv6 público** (`2601:152:1580:92d0:…/64` en `enP7s7`): **riesgo único** — `nemoclaw-vllm` escucha en `[::]:8000` dual-stack; si el router residencial permite inbound IPv6, vLLM `:8000` sería alcanzable desde Internet **SIN API key** (vLLM no hace auth; el control vive en el gateway 8010). ComfyUI/OpenClaw/gateway admin solo IPv4 `0.0.0.0` (no `[::]`) → no IPv6. nginx `[::]:443` presente pero filtra por Host (Host desconocido → `default_server` → 404). **Estado**: pendiente OK del owner para aplicar fix. Opciones propuestas: (A) recrear `nemoclaw-vllm` con `-p 127.0.0.1:8000:8000` (cero impacto en gateway/lan, downtime 5-7 min carga modelo); (B) A + nginx IPv4-only; (C) UFW deny-incoming+allow LAN. Owner eligió no aplicar cambios por ahora — solo documentar. Actualizado §8 Seguridad con el hallazgo.

- **2026-08-16 02:50 UTC**: **fix aplicado — blindaje IPv6 a vLLM `:8000`**. Tras confirmar con el owner que vLLM debe ser público solo vía túnel Cloudflare + API key (no directo), y tras descartar la opción A simple (`-p 127.0.0.1:8000:8000`) porque **rompería el sandbox nemoclaw** (su proxy L7 `openshell-sandbox` pid 1 ataca vLLM vía `172.18.0.1:8000` del docker bridge, que NATs al `0.0.0.0:8000` publicado), se aplicó **`ip6tables -I INPUT 1 -p tcp --dport 8000 -j DROP`**: bloquea inbound IPv6 al puerto 8000 manteniendo vLLM accesible vía IPv4 para (a) localhost del gateway (127.0.0.1:8000, vía tunnel + API key) (b) docker bridge del sandbox (172.18.0.1:8000, vía `inference.local`) (c) LAN directa (10.0.0.5:8000, sin API key — pendiente blindar si se desea). Regla persistida vía `iptables-persistent` (`netfilter-persistent.service` enabled) en `/etc/iptables/rules.v6`. Validado: gateway `/health` 200, vLLM localhost 200, sandbox `inference.local/v1/models` 200, IPv6 `[::1]:8000` 000 (DROP funciona). Cero downtime, cero impacto en stack. Actualizado §4 (tabla componentes + persistencia en disco) y §8 (FIX APLICADO) del AGENTS.md.

- **2026-08-15 21:55 UTC**: analisis completo de ComfyUI — 4 templates de video en `~/Downloads/` inventariados con sus modelos/inputs. **Reubicación masiva de modelos**: `sam3.1_multiplex_fp16` movido a `models/checkpoints/`, `lightx2v_I2V_14B` movido a `models/loras/` (el template SCAIL-2 los carga via `CheckpointLoaderSimple` y `LoraLoaderModelOnly`, NO via `diffusion_models/`). **Creación de scripts automaticos**: (a) `comfyui-models-mover.sh` — daemon systemd (`victoria-comfyui-models-mover.service`) que escanea `~/Downloads/`, `/home/victoria/`, `/tmp/` cada 30s y mueve `.safetensors` a `models/<tipo>/` sin duplicar, con heurística por nombre y header; (b) `comfyui-models-downloader.py` — daemon systemd (`victoria-comfyui-models-downloader.service`) que descarga modelos desde HuggingFace con `wget -c` (continuable), salta repos gated (401) y skips archivos ya descargados, soporta `HF_TOKEN` via env var. **Descarga completada**: 7 nuevos modelos públicos (gem4_e2b, wan2.1_fun_camera, wan2.1_vae, wan2.2_i2v_high, wan2.2_i2v_low, wan2.2_lora_high, wan2.2_lora_low) — post-descarga el inventario total era 39 archivos / 180 GB; tras re-escanear subdirectorios anidados (`checkpoints/text_encoder/`, `checkpoints/vae/`, `vae_approx/`) el conteo real actualizado es **42 archivos / 202 GB**. **Estado por template**: SCAIL-2 ✅ READY (solo inputs), Fun Camera ✅ READY (solo input), WAN 2.2 I2V ✅ READY (solo input), LTX-2.5 ⛔ GATED (5 modelos requieren `Lightricks/LTX-2.5` + HF_TOKEN). **Validación por API**: los 3 templates listos fallan validación solo por `MarkdownNote` (node decorativo, no afecta generación). ComfyUI reiniciado para detectar todos los modelos nuevos. Documentacion: `comfyui-ops.md` ampliado con secciones de auto-mover/auto-download, templates de video, modelos instalados actualizados; AGENTS.md actualizado (§4 services, §11 modelos, §10 historial).

- **2026-08-16 04:20 UTC**: **Victoria content bundle completado** — 6 templates Victoria-template-* creados + 13 videos de referencia + documentación alineada. **Templates** (en `ComfyUI/user/default/workflows/` + backup en `Documents/Victoria Armada/templates/`): (1) `Victoria-template-reel-tech-tip.json` (1080x1920, Z-Image-Turbo, reel tech tips), (2) `Victoria-template-post-ethical-hacking.json` (1080x1080, Z-Image-Turbo, post IG "ethical hacker" look), (3) `Victoria-template-post-cybertip.json` (1080x1350 4:5, Z-Image-Turbo, post IG feed cyber tip), (4) `Victoria-template-thumbnail-tech.json` (1280x720 16:9, Z-Image-Turbo, YT thumbnail ciberseguridad), (5) `Victoria-template-video-i2v.json` (WAN 2.2 I2V + lightx2v 4-steps, foto Victoria → video corto hablando), (6) `Victoria-template-video-scail2.json` (WAN 2.1 SCAIL-2 + SAM3 character replacement, sustitución persona por Victoria en `driving_outdoor_dance.mp4`). Los 4 templates de imagen usan el `zimg-*` base con prompts editados (positivo + negativo) + seed=0 random; los 2 de video usan templates `video_wan*` con `LoadImage`/`LoadVideo` cambiados a `victoria-reference/victoria-profile.jpg` (o `victoria-Posing.jpg` para SCAIL-2). **Videos de referencia** (`Documents/Victoria Armada/videos/`): 13 clips generados con ffmpeg (8s cada uno) — `cyberpunk_grid_loop`, `glitch_tech`, `ken_burns_victoria_profile`, `tech_screens_loop`, `driving_outdoor_dance` (input SCAIL-2) y 8 `victoria-pan-*.mp4` (pan-zoom sobre cada foto de Victoria). Intento de descargar stock video de Pixabay/Pexels/Mixkit CDNs: bloqueados (403/404 cloud protection a wget/curl) — se usaron sintéticos con ffmpeg en su lugar. **Symlinks**: 9 imágenes + 13 videos symlinkados a `ComfyUI/input/victoria-reference/` (broken=0, todos válidos). **Documentación**: AGENTS.md §11 ampliado (subsección "Videos de referencia + Templates Victoria"), `comfyui-ops.md` ampliado (sección equivalente + pipeline de contenido sugerido), `README.md` en `Documents/Victoria Armada/` reescrito (organización + tabla de 6 templates + pipeline 5-pasos + mantenimiento). **Validación**: los 4 templates API format tienen todos los nodos críticos (sampler, clip, save, loader); los 2 templates UI format tienen LoadImage/LoadVideo apuntando a `victoria-reference/`. Persistencia en disco host (`Documents/Victoria Armada/` = 16 MB) sobrevive reboot/crash del sandbox.ғ

- **2026-08-16 04:30 UTC**: **fix SAM3_VideoTrack cuDNN failure on GB10 (sm_121a)** — `Victoria-template-video-scail2.json` fallaba en runtime con `cuDNN Frontend error: No valid execution plans built` en el node `SAM3_VideoTrack`. Causa raíz: `comfy-venv` tenía `torch==2.11.0+cu128`; CUDA 12.8 no trae kernels cuDNN tuned para sm_121a (GB10 es muy nuevo). ComfyUI lo detectaba en boot y **disableaba el backend CUDA de comfy-kitchen** (`comfy/quant_ops.py:41-43`: si `torch.version.cuda < (13,)` → `ck.registry.disable("cuda")` + WARNING "You need pytorch with cu130 or higher"). Sin backend CUDA optimizado, los convs de SAM3 corrían vía vanilla cuDNN sin plan válido para sm_121a → RuntimeError. **Fix aplicado**: upgrade in-place del `comfy-venv` (no Docker) de `cu128` a `cu130` — `pip install --index-url https://download.pytorch.org/whl/cu130 torch==2.11.0 torchvision torchaudio triton` sobre el venv host. Resultado: `torch 2.11.0+cu130`, `torchvision 0.26.0+cu130`, `torchaudio 2.11.0+cu130`, `triton 3.6.0`, `nvidia-cudnn-cu13==9.19.0.56` (cuDNN para CUDA 13). Tras restart de `victoria-comfyui.service`: log confirma `comfy_kitchen backend cuda: disabled: False` (49 capabilities) — antes era `disabled: True`. WARNING "cu130 or higher" desaparecido. 5 nodes SAM3 (`SAM3_Detect`, `SAM3_VideoTrack`, `SAM3_TrackPreview`, `SAM3_TrackToMask`, `SAMPreprocessor`) registrados OK. vLLM (Docker, su propio torch) **NO tocado**. Snapshot antes/después en `/tmp/comfy-venv-{before,after}-cu130.txt` para rollback. Downtime ~2 min (restart service). Rollback: `pip uninstall -y torch torchvision torchaudio triton && pip install torch==2.11.0+cu128 torchvision==0.26.0+cu128 torchaudio==2.11.0+cu128 triton==3.6.0 --index-url https://download.pytorch.org/whl/cu128`.

- **2026-08-16 15:30 UTC**: **Fase 1+2+3 completadas — Discord streaming humanizado + active-memory cross-canal + RSS blogwatcher persistente + identidad SOUL.md memoria cross-canal**. (a) **Fase 1 — Discord streaming humanizado**: pool de 18 labels humanas (`Thinking`, `Pensando`, `Dándole vueltas`, `Meditándolo`, `Revisando`, `Reflexionando`, `Working`, `En ello`, `Puliéndolo`, etc.) reemplazan los "progress drafts" por defecto (labels tipo "Molting" + commentary con rutas/paths/innerls del gateway). `toolProgress:false` oculta internals. `active-memory` plugin bundled habilitado con `queryMode:recent`, `promptStyle:balanced`, `timeoutMs:15000`, `allowedChatTypes:["direct","group"]` — bloquea sub-agent memory recall inyectando contexto relevante antes del reply main para sesiones persistentes. `session.identityLinks.alfredo:["discord:693703068461826110","whatsapp:18295468686"]` para cross-channel docking. Todo aplicado vía overlay persistente `/home/victoria/.victoria-custom/openclaw-overrides.json` + `openclaw-customize-apply.sh` (deep-merge idempotente con `_managed` explícito lista rutas gestionadas; drift detection por hash; NO usa `_meta` que rompe el schema estricto de openclaw). Enganchado al ensure-loop `openclaw-bridge-ensure.sh` tras restore del `persist.sh` + plugins npm + rss-install + identidad. **Hot-reload confirmado**: streaming y active-memory cargan sin restart (el gateway watcher del openclaw.json lo aplica en vivo); solo `plugins.allow` requiere restart (se dejó vacío = auto-load). 12 plugins cargados al boot (browser, canvas, device-pair, discord, file-transfer, memory-core, ollama, phone-control, talk-voice, tts-local-cli, whatsapp, **active-memory**). (b) **Fase 3 — RSS/blogwatcher reconstruido desde scratch** (se perdió completo en el rebuild del 2026-08-16 01:50; el subagente `rss-news-service.md` referenciaba `polyskill/blogwatcher` 404 y `polyskill/openclaw.blogwatcher` 404 en GitHub). Investigación找到了 el repo real: `github.com/Hyaxia/blogwatcher` v0.0.3 (Go 1.24, 144★, modernc.org/sqlite pure-Go sin CGO). Releases SOLO linux-amd64 prebuilt (no arm64). Solución: Go 1.26.6 arm64 oficial instalado en `/usr/local/go` (host), `git clone --depth 1 --branch v0.0.3`, `CGO_ENABLED=0 go build -ldflags="-s -w" -o ~/.victoria-custom/bin/blogwatcher ./cmd/blogwatcher` → binario ARM64 estático 13.9MB stripped (file confirma `statically linked`). Skill `@polyskill/openclaw.blogwatcher` v1.0.1 ya estaba en openclaw.json backup (manifest solo 2987 bytes); binario canónico en `/home/victoria/.victoria-custom/bin/blogwatcher` (host), copiado al sandbox por nuevo `openclaw-rss-install.sh ensure` (llamado por el ensure-loop tras `ensure_npm_plugins`). DB SQLite en `/sandbox/.openclaw/blogwatcher/blogwatcher.db` (BLOGWATCHER_DB env var, flag correcto `--feed-url` no `--feed_url`). Policy `rss-feeds` preset custom aplicada vía `nemoclaw sandbox policy add --from-file` (14 hosts con reglas GET/HEAD + binarios autorizados incl `/sandbox/.openclaw/bin/blogwatcher`). persist.sh actualizado para excluir `.openclaw/bin/blogwatcher` (binario reinstalable por rss-install) + incluir `blogwatcher/blogwatcher.db` (DB con datos). 15 feeds añadidos, 6 funcional con scan exitoso (Ars Technica 20 articles, Cointelegraph 30, CoinDesk 25 via Feedburner fallback, Hipertextual 15, TechCrunch 21, Wired 50 = 161 articles tracked). 9 feeds restantes fallan con 403 de CloudflareWAF (anti-bot detecta Go-http-client via JA3 incluso con UA override de Chrome) — pendientes feeds alternativos (FeedBurner proxy, RSS.app mirror). Ejecución via `nsenter -t $G -n -- env BLOGWATCHER_DB=... HTTPS_PROXY=http://10.200.0.1:3128 SSL_CERT_FILE=/etc/openshell-tls/ca-bundle.pem SSL_CERT_DIR=/etc/openshell-tls runuser -u sandbox -- /sandbox/.openclaw/bin/blogwatcher ...` (el proxy L7 del sandbox hace MITM TLS con su propio CA `/etc/openshell-tls/ca-bundle.pem`; SSL_CERT_FILE/DIR necesario para que Go valide el cert pinado del proxy). (c) **Fase 2 — SOUL.md directriz memoria/privacidad cross-canal**: `/home/victoria/SOUL-restore.md` ampliado con subsección "Cross-channel memory and privacy" bajo "Discord, WhatsApp, Web, Voice — Same Victoria": qué compartir entre canales (imágenes personales, nombres de amigos/clientes/familia, temas conversados), qué NO compartir (números, IDs, datos de sistema/clientes/sensibles), cómo responder si le preguntan cómo sabía algo ("tengo buena memoria para lo importante 🌟", no detallar el sistema). Nuevo `ensure_identity_files` en el ensure-loop sincroniza `SOUL/IDENTITY/USER-restore.md` desde el host al `/sandbox/.openclaw/workspace/` si el host es más reciente (respeta timestamps de ediciones live de Victoria, no sobreescribe sus cambios). Persist backup 27M victoria-owned (inicialmente 40M con binario incluido; tras excluir blogwatcher binario bajó a 27M). Validación final: sandbox healthy 2h, gateway estable pid 18587 con 0 respawns, 12 plugins cargados, Discord+WhatsApp conectados, config merged idempotente (18 labels + toolProgress false + active-memory.enabled + identityLinks alfredo), blogwatcher binario 13.9MB + DB 81920 bytes con 15 blogs tracked y 161 articles, SOUL.md 117 líneas con la nueva directriz cross-canal, bridge service activo.

- **2026-08-18 13:20 UTC**: **auto-distribución de noticias a Tech Hub (TH) completada**. Script `discord-broadcast.py` distribuye noticias RSS a dos canales de TH: `#ethical-hackers` (webhook ID 1539323889094496438) y `#penetration-testers` (webhook ID 1539324088282259498). Pipeline: (1) blogwatcher escanea feeds RSS en HOST cada 2h; (2) selecciona 2 articulos de cyber/hacking/crypto; (3) LLM (`Qwen3.6-35B-normal`, thinking OFF) genera opinion humana de max 40 palabras; (4) extrae imagen del feed RSS; (5) envía embed a Discord con titulo + opinion + imagen + URL. Horario: cron cada 4h (07,11,15,19,23), solo distribuye 09:00-23:30 EDT. Webhooks guardados en `~/.discord-webhooks`. Scripts: `/home/victoria/discord-broadcast.sh` (wrapper bash), `/home/victoria/discord-broadcast.py` (logic), `~/.discord-webhooks` (URLs). **Solamente TH** — los otros servidores (La Verganza, EnWebs, GamerParty) son para interaccion directa con el owner, no para distribucion automatica.

## 11. Contenido — generación visual y orquestación (2026-09-28)

### LivePortrait — talking head SOTA (:8180)

| Aspecto | Valor |
|---|---|
| Servicio | `liveportrait.service` (systemd, enabled) |
| Venv | `/home/victoria/liveportrait-venv/` (python3.12, torch cu130) |
| Código | `/home/victoria/LivePortrait/` (clone GitHub KlingAIResearch/LivePortrait) |
| Pesos | `/home/victoria/LivePortrait/pretrained_weights/` (~2GB, HuggingFace) |
| WebUI | `http://victoria.local/liveportrait/` — **UI amigable en español (2026-09-28 20:50)**: 3 pestañas (🎬 Animar / 😊 Retoque facial / 🎞️ Retoque de video), fotos de Victoria como ejemplos de un clic (`ComfyUI/input/victoria-reference/`), opciones avanzadas colapsadas. `app.py` personalizado (original en `app.py.bkup-20260928-ui-original`); pipeline y bindings intactos. **Audio propio (2026-10-07)**: Animar paso 3️⃣ — uploader de nota de voz/audio que se pega sobre el video (doblaje; **el AUDIO manda la duración**: nota más corta → video recortado a la nota, más larga → último frame congelado — fix #8 17:10); lip-sync real = Sonic. **Aclaración 2026-10-14 (fix #9)**: el label del uploader dice explícito DOBLAJE sin lip-sync y apunta al Estudio Podcast; el Estudio Podcast **SÍ acepta audio propio** desde hoy (nota de voz → Sonic directo, sin TTS — ver fila Sonic Tab UI) |
| API | HTTP POST a la WebUI Gradio (`/gradio_api/run/<endpoint>`; archivos vía `/gradio_api/upload` + `{"path":..., "meta":{"_type":"gradio.FileData"}}` — Gradio 6.29 exige `meta` explícito, mecanismo vigente verificado con el upgrade 2026-10-01) o CLI `inference.py` |
| Velocidad | ~78 frames en ~10s en GB10 (vs 4+ min de LTX-2.5) |
| Uso | Dales una foto de Victoria + un video guía → labios sincronizados + expresiones |
| Systemd | `sudo systemctl restart liveportrait` |

**Notas**: Los pesos incluyen modo Humans y Animals (solo Humans probado en GB10).
**Fixes Gradio 6 (2026-09-28)**: el `app.py` original tenía (a) `theme=` en el
constructor de `gr.Blocks()` (Gradio 6 lo movió a `launch()` — el theme no aplicaba)
y (b) `gr.Textbox` como hijo directo de `gr.Tabs()` (ilegal en Gradio 6 → warnings
+ layout roto en la detección de pestaña fuente/guía). El `app.py` custom corrige
ambos: theme en `launch()`, textboxes `tab_selection`/`v_tab_selection` fuera del
contexto `gr.Tabs()`. Cero warnings en el journal.
**UI v2 (2026-09-28 22:30)**: CSS propio (`custom_css` en `launch()`: max-width
1320px, botón primario grande, aire en accordions/tabs/forms — el owner veía
"todo muy pegado"), guardias amigables en español en los 3 wrappers (sin
fuente/guía/foto/video → `gr.Error` en ES en vez del error críptico en inglés),
y **reintento de `launch()` en el mismo proceso** (3 intentos, 5s): el parche del
bug de localhost de Gradio 5.x se perdió con el upgrade a 6.28 y el check crudo
(`blocks.py:3589`, `url_ok` 5×HEAD 3s) tumbó el servicio en crash-loop el
2026-09-28 13:41-14:10 (~100 PIDs, 495 excepciones `api_info` legacy en el
journal). El retry lo reemplaza sin tocar el venv (sobrevive upgrades).
**Fix proxy 22:55**: `root_path="/liveportrait"` en `launch()` (el frontend
construía rutas absolutas `/gradio_api/...` → 102× 404 en ejemplos + 14× 404
en `queue/join` = botón Generar muerto tras nginx; acceso directo a :8180
genera URLs con prefijo — usar siempre `victoria.local/liveportrait/`) y
`client_max_body_size 500M` en los locations `/liveportrait/`, `/comfyui/`,
`/n8n/` de nginx (default 1MB → **413 en TODO upload de video/foto real**;
backup `gateway.conf.bkup-20260928-liveportrait-413`). Tras restart, refrescar
la página: los ejemplos viven en `/tmp/gradio/<hash>/` y el hash cambia.
Requiere PyTorch cu130 (mismo que ComfyUI). El bug de Gradio 5.x (check localhost)
fue parcheado y luego resuelto con upgrade a Gradio 6.28.0.

### Sonic — podcast con voz sincronizada (:18850, servicio `victoria-sonic-server`)

| Aspecto | Valor |
|---|---|
| Servicio | `victoria-sonic-server.service` (systemd, enabled) — daemon `sonic-server.py` (stdlib, single-flight 503 si ocupado, auth sense_auth) |
| Venv | `/home/victoria/sonic-venv/` (python3.12, torch 2.14+cu130 + diffusers 0.29 + transformers 4.43.2, SIN xformers — portable ARM64) |
| Código | `/home/victoria/Sonic/` (clone jixiaozhong/Sonic, CVPR 2025; CLI `demo.py img audio out`) |
| Pesos (~38GB) | `checkpoints/`: `Sonic/` 6.2G (unet/audio2token/audio2bucket), `stable-video-diffusion-img2vid-xt/` 31G (gated, HF_TOKEN), `whisper-tiny/`, `RIFE/flownet.pkl`, `yoloface_v5m.pt` |
| API | `GET /health` + `POST /generate {image_path,audio_path,out_path?,steps?=25,resolution?=512\|640\|768}` — resolución de render: 512 rápido, 640 recomendado (default en el Estudio Podcast, bordes más sólidos), 768 lento + VRAM (2026-09-29) |
| VRAM | ~24GB sostenidos; total con vLLM+voz+LP ≈ 76GB/128GB — NO correr renders ComfyUI grandes a la vez (OOMs 2026-09-27/28) |
| Velocidad | ~100s por segundo de audio (25 steps; 15 steps ≈ 5 min para 5s) |
| Licencia | **Pesos CC-NC-ND (no comercial)** — gratis pero no para uso comercial; aceptado por owner 2026-09-29 |
| Tab UI | 🎙️ Estudio Podcast en LivePortrait (guion EXACTO a duración 15s→35pal/195chars, 30s→70/390, 60s→140/780 + pre-escucha con audio REAL + `gpu_wrapped_execute_podcast`: (guion→TTS **o tu nota de voz directa, 2026-10-14** — uploader 🎧, salta el TTS, guion opcional, subs vía whisper sobre tu audio)→Sonic→whisper→1080×1920+subs+logo + 📚 Biblioteca `biblioteca-podcast.json` con fecha/título/prompt/rutas y Cargar para reutilizar + 🎞️ guía de movimiento opcional como en Animar: híbrido Sonic→LivePortrait región `pose`, labios intactos) |
| Reels | `instagram-reels.py VIDEO "caption" [--publish]` (sin flag = DRY, no publica); gateway `/ig-media/*.mp4` |
| Demo sin Sonic | `victoria-podcast-demo.sh "texto"` (ilusión LivePortrait+guía, labios genéricos) |
| Subagente | `Sonic` (`agents/sonic.md`) |
| Systemd | `sudo systemctl restart victoria-sonic-server` (recarga ~10s caliente) |

### ComfyUI — generación de imágenes (:8188)

| Aspecto | Valor |
|---|---|
| Servicio | `comfyui.service` (systemd, enabled) |
| Venv | `/home/victoria/comfy-venv/` (python3.12, torch cu130, **comfy-aimdo 0.6.0 + comfy-kitchen 0.2.40** — update 2026-10-26 junto a ComfyUI v0.42.0; ⚠️ requirements.txt lista DOS paquetes propios (aimdo+kitchen) — actualizar AMBOS antes de reiniciar o crash-loop `ModuleNotFoundError: comfy_kitchen.int8_decode`; historia: 0.5.2→0.5.5→0.5.6 (v0.39.1)→0.6.0+kitchen (v0.42.0)) |
| Raíz | `/home/victoria/ComfyUI/` |
| WebUI | `http://victoria.local/comfyui/` |
| Custom nodes | ComfyUI-Manager, controlnet_aux, Custom-Scripts, InstantID, IPAdapter_plus, RMBG |
| Vía API | `POST /v1/images` del gateway con template (`z-image-turbo`, `flux-schnell`, `sd15-realistic`) + prompt/seed/size — ver §7 art API; templates API-format en `~/.victoria-custom/comfyui-templates-api/` |
| Systemd | `sudo systemctl restart comfyui` |

### Modelos de imagen instalados (2026-10-03, tras activar FLUX)

| Modelo | Ruta | Tamaño | Uso |
|---|---|---|---|
| FLUX.1-dev/schnell | `models/diffusion_models/` | ~46G | Calidad alta (schnell USABLE vía API desde 2026-10-03: clip_l descargado; dev queda para UI) |
| Z-Image-Turbo | `models/diffusion_models/` | ~12G | Rápido (8 steps) — default de la art API |
| Qwen3-4B | `models/text_encoders/` | ~7.5G | Text encoder para Z-Image |
| t5xxl_fp8 + **clip_l** | `models/text_encoders/` | ~4.9G + 246M | Text encoders para FLUX (clip_l descargado 2026-10-03 de comfyanonymous/flux_text_encoders) |
| SD1.5 Realistic Vision | `models/checkpoints/` | ~8G | Ligero, fotorrealismo clásico |
| SDXL RealVisXL V5 | `models/checkpoints/` | ~6.5G | Detalle medio |
| ControlNet SD1.5 (7) | `models/controlnet/` | ~12G | Canny, Depth, HED, OpenPose, etc. |
| InstantID ControlNet | `models/controlnet/` | ~2.4G | Identidad facial |
| CLIP Vision + IP-Adapter | `models/clip_vision/` | ~3.6G | Consistencia de personaje |
| VAE (FLUX/Z-Image) | `models/vae/` | ~0.3G | ae.safetensors |
| **Total** | | **~109G** | Solo imagen; video eliminado 2026-09-28 |

### n8n — orquestador visual de workflows (:5678)

| Aspecto | Valor |
|---|---|
| Contenedor | `n8n` (Docker ARM64, restart unless-stopped) |
| Puerto | 5678 (WebUI en `http://victoria.local/n8n/`) |
| Datos | `/home/victoria/n8n-data/` |
| Uso | Crear workflows: guion (LLM) → imagen (ComfyUI) → talking head (LivePortrait) → concat → publicar |
| Gestión | `docker restart n8n` · `docker logs n8n` |

### Hunyuan3D-2 — image-to-3D local (:18860, 2026-10-09)

| Aspecto | Valor |
|---|---|
| Servicio | `victoria-hunyuan3d.service` (systemd, enabled, Restart=always) |
| Daemon | `/home/victoria/hunyuan-server.py` (stdlib, single-flight 503, auth sense_auth, turno `hunyuan3d-standalone` en `gpu_arbiter.py`) |
| Venv | `/home/victoria/hunyuan-venv/` (py3.12, torch 2.14+cu130, **transformers 4.57.1 + diffusers 0.32.2 pineados** — 5.x/0.41 rompen el load del DiT) |
| Código/pesos | `/home/victoria/Hunyuan3D-2/` + `custom_rasterizer`/`mesh_processor` compilados ARM64; pesos HF `tencent/Hunyuan3D-2mini` (shape turbo 0.6B) + `tencent/Hunyuan3D-2` (paint-turbo 1.3B), ~10G |
| API | `GET /health` + `POST /generate {image_path\|image_b64, texture?, steps?=5}` → GLB + `GET /file/<n>.glb` |
| ENV crítico | `LD_LIBRARY_PATH=<venv>/.../torch/lib` (sin esto `custom_rasterizer_kernel` da ImportError libc10) |
| Chat | wrapper `art-3d` (gate feature `3d`, base64+descarga) + skill `hunyuan3d` + nginx `/hunyuan3d/` LAN |
| Kalimete | **Recurso de la granja (2026-10-19)**: `POST /generate {"image_b64"}` + `GET /file/<n>.glb` con la llave `kalimete` (cap art → sense elevation) — E2E verificado (GLB 3.5MB/46s descargado en kalimete); receta en su skill `assets-3d` |
| Licencia | Tencent Hunyuan 3D 2.0 Community (comercial hasta 1M MAU, no EU/UK/KR) |
| Límite | mesh ESTÁTICO (no riggea): avatar completo = art-3d → Blender rig → LivePortrait/Sonic |

### Animar-por-chat — LivePortrait headless (:18861, 2026-10-09)

| Aspecto | Valor |
|---|---|
| Servicio | `victoria-lp-animate.service` (systemd, enabled) — thin daemon `lp-animate-server.py` (stdlib, single-flight, sense_auth; ejecuta el mismo CLI, sin duplicar ruta) |
| Wrapper | `lp-animate <foto> [--guia <video>] [--preset N\|lista]` (dual-mode host/sandbox como art-3d; gate feature `animar`) → mp4 h264/yuv420p ~17s |
| Presets | `/home/victoria/.victoria-custom/lp-presets/` (01-saludo 3.1s, 02-habla 7.2s, 03-energía 8.3s) |
| GPU | turno `lp-animate` kind liveportrait (polling ≤30s); ~3G + :8180 si coincide |
| Chat | skill `animar` + gate `animar` (PESADO, ventana owner) + nginx `/animar/` LAN |
| Kalimete | **Recurso de la granja (2026-10-19)**: el daemon :18861 acepta `foto_b64` + `preset`/`guia_b64` → mp4 por `GET /file/<n>.mp4` con la llave `kalimete` (cutscenes del Game Studio); receta en su skill `assets-3d` |


## 12. Armada OSINT Search Engine — people/breach/domain search (2026-08-21)

> **❗ MOVED to kalimete.local (2026-09-11) — ELIMINADO por completo de este host.**
> El Armada OSINT Search Engine se movió a `kalimete.local` (la máquina que se
> encarga de "ethical hacking"). En este DGX Spark (Victoria) **TODO fue eliminado
> físicamente**: `armada-osint-api.service` + cron + location nginx `/osint/` +
> código `/home/victoria/armada-osint/` + venv `/home/victoria/osint-venv/` +
> DB PostgreSQL `armada_osint` + subagente `armada-osint-ops.md` + wrappers
> (`osint-search`, `phoneinfoga`) + skill. La función `ensure_osint` del ensure-loop
> y la allowlist de `victoria-host-admin` fueron limpiadas. **No hay forma de
> re-activarlo aquí** — kalimete es dueño del OSINT y su catálogo HIBP (re-ingestable
> desde haveibeenpwned.com). Esta sección se conserva SOLO como histórico.

Servicio de investigación OSINT de personas, emails, teléfonos y dominios
basado en breaches públicos. Stack 100% Python + PostgreSQL en el host.

### Arquitectura

```
victoria (DGX Spark, ARM64)
├── armada-osint-api.service (uvicorn :8090) → FastAPI search engine
│   ├── PostgreSQL :5432 (DB local «armada_osint»: 9 tablas + 2 vistas)
│   ├── HIBP API v3 (catálogo + breach-per-email) — 1029 breaches ingested
│   ├── Shodan + Hunter.io + Dehashed (premium, opt-in)
│   └── phoneinfoga / phonenumbers Python (validación offline)
├── armada-osint-ingest.service (cron monthly: 1ero de cada mes, 3am)
│   └── pipeline/hibp_ingest.py (sincroniza catálogo HIBP)
├── nginx /osint/ → 127.0.0.1:8090 (HTTPS via victoria.local)
└── sandbox nemoclaw → http://172.18.0.1:8090 (wrapper osint-search)
```

### Componentes

| Componente | Ruta / Puerto | Función |
|---|---|---|
| FastAPI service | systemd `armada-osint-api.service` (enabled, Restart=always, User=victoria, bind `0.0.0.0:8090`) | API REST + panel web + Swagger UI |
| DB PostgreSQL | `armada_osint` (@127.0.0.1:5432, user `armada`) | 9 tablas: emails, breaches, entries, phones, phone_entries, aliases, domains, infra, audit_log |
| Venv Python | `/home/victoria/osint-venv/` (python3.12) | fastapi, uvicorn, asyncpg, httpx, shodan, slowapi, phonenumbers |
| Source clients | `/home/victoria/armada-osint/api/sources.py` | HIBPClient, ShodanClient, HunterIOClient, DehashedClient, PhoneInfogaClient |
| Web panel | `/home/victoria/armada-osint/web/index.html` | UI mínimo con stats + search box (sirve en `/panel` con X-API-Key) |
| Nginx location | `/etc/nginx/sites-available/gateway.conf` `location /osint/` | Reverse proxy HTTPS `victoria.local/osint/` → `127.0.0.1:8090` |
| Sandbox wrapper | `/home/victoria/.victoria-custom/bin/osint-search` (canónico host) → `/sandbox/.openclaw/bin/osint-search` (en sandbox) | Wrapper bash para OpenClaw |
| Skill OpenClaw | `/home/victoria/Documents/Victoria Armada/workspace/skills/osint/SKILL.md` (canónico host) → `/sandbox/.openclaw/workspace/skills/osint/SKILL.md` (en sandbox) | Doc para Victoria |
| Config | `/home/victoria/armada-osint/config/.env` (perm 600, NO commitear) | DB creds, API_KEY, claves externas |
| Subagente | `armada-osint-ops` (`~/.config/opencode/agents/armada-osint-ops.md`) | Operación del servicio |

### Endpoints API (auth `X-API-Key` para `/api/v1/*`)

| Endpoint | Método | Función |
|---|---|---|
| `/health` | GET | Health (sin auth) |
| `/` | GET | Root JSON (sin auth) |
| `/docs` | GET | Swagger UI |
| `/api/v1/search?query=x` | GET | Unified search (auto-detect email/phone/domain/name por pattern) |
| `/api/v1/email?email=x` | GET | Email lookup (local DB + HIBP si key) |
| `/api/v1/phone?phone=+xx` | GET | Phone lookup (local DB + phonenumbers lib) |
| `/api/v1/domain?domain=x` | GET | Domain (local emails + Hunter.io + Shodan) |
| `/api/v1/name?q=juan` | GET | Fuzzy name/username search (pg_trgm index) |
| `/api/v1/breaches` | GET | Lista breach catalog (default 100) |
| `/api/v1/breaches?email=x` | GET | Breaches de un email específico |
| `/api/v1/config-guide` | GET | Guía auto-descriptiva JSON |
| `/panel` | GET | Web panel HTML (X-API-Key) |

Rate limiting: `slowapi` 60 req/min per IP. Audit log en `audit_log` (compliance trail).

### Sandbox wrapper `osint-search`

```
/sandbox/.openclaw/bin/osint-search <command> [query]
```

| Comando | Función |
|---|---|
| `search <q>` / `<q>` | Búsqueda unificada |
| `email <email>` | Lookup de email |
| `phone <+num>` | Lookup de teléfono |
| `domain <dominio>` | Lookup de dominio |
| `name <fragmento>` | Fuzzy search |
| `breaches` / `breaches <email>` | Catálogo / breaches de email |
| `config-guide` | Guía auto-descriptiva |
| `health` | Health check |

La API key está embebida en el wrapper (generada por el admin al configurar).
NO commitear el wrapper a repos públicos.

### Persistencia — Anti-rebuild

- **API + PostgreSQL viven en el HOST** (systemd + apt) → sobreviven a cualquier `docker rm -f` del sandbox.
- **El wrapper `osint-search` y el `SKILL.md`** viven en el sandbox container → el ensure-loop los restaura desde el host en cada rebuild:

```bash
# Logica del ensure-loop (openclaw-bridge-ensure.sh::ensure_osint):
# - Re-copia /home/victoria/.victoria-custom/bin/osint-search → /sandbox/.openclaw/bin/
# - Re-copia /home/victoria/Documents/Victoria Armada/workspace/skills/osint/SKILL.md → /sandbox/.openclaw/workspace/skills/osint/
# - chown sandbox:sandbox, chmod 755
```

### Database schema (PostgreSQL)

| Tabla | Contenido | Compliance |
|---|---|---|
| `emails` | email_hash (SHA256) UNIQUE + sources + username/domain | NO se guarda raw (solo lowercased) |
| `breaches` | name UNIQUE + pwn_count + data_types + verified | Catálogo HIBP (1029 entries 2026-08-21) |
| `entries` | email_hash + breach_name + password_hash + has_password | **NUNCA** password_plain (sólo hash + flag) |
| `phones` | phone_hash (SHA256) + country/carrier/line_type | Catálogo de teléfonos |
| `phone_entries` | phone_hash + breach_name | Apariciones de teléfonos en breaches |
| `aliases` | alias_type/value + linked_email_hash | Correlaciones nick→email→phone |
| `domains` | domain UNIQUE + email_count + risk_score (0-100) | Dom. corporativos |
| `infra` | ip + port + service + org | Shodan cache |
| `audit_log` | api_key_hash + query + source_ip | Compliance trail (GDPR/CCPA/LFPDPPP) |

Vistas: `email_full` (LEFT JOIN emails + entries con breach_count), `phone_full` (análoga).

### API keys externas (config `.env`, NO commitear)

| Variable | Para qué | Costo inicial |
|---|---|---|
| `HIBP_API_KEY` | Búsqueda breach-per-email HIBP v3 | $0 con domain propio |
| `SHODAN_API_KEY` | IP/host scan | Free 100 req/mes |
| `HUNTERIO_API_KEY` | Descubrimiento emails de dominio | $34/mo Starter |
| `DEHASHED_API_KEY` | Búsqueda flexible breaches | 500 free credits |
| `APILAYER_API_KEY` | Validación de teléfono (Numverify) | $15/mo |

### Reglas CRÍTICAS (no tocar)

1. **NUNCA commitear** `config/.env` (contiene DB password + API keys).
2. **NUNCA exponer** `:8090` a Internet sin HTTPS + API key fuerte.
3. **NUNCA guardar** `password_plain` en la DB (compliance GDPR/CCPA/LFPDPPP); solo `password_hash` + `has_password` flag.
4. **AUDIT LOG**: toda consulta queda en `audit_log` (api_key_hash + query + source_ip).
5. **HIBP rate limit**: 1 req/sec para account lookups — no abusar.
6. El wrapper lleva la API key embebida — no subir a repos públicos.
7. `pg_dump` diario del PostgreSQL (TODO: programar).

### Comandos operativos

```bash
# Servicio
sudo systemctl status armada-osint-api.service
sudo systemctl restart armada-osint-api.service
sudo journalctl -u armada-osint-api.service -n 50

# Health API
curl -s http://127.0.0.1:8090/health
# Desde sandbox
docker exec openshell-victoria-armada /sandbox/.openclaw/bin/osint-search health

# Stats DB
PGPASSWORD=$(grep ^DATABASE_URL_SYNC /home/victoria/armada-osint/config/.env | sed 's/.*:armada:\(.*\)@.*/\1/') \
  psql -h 127.0.0.1 -U armada -d armada_osint -c "SELECT count(*) FROM breaches;"
PGPASSWORD=$(...) psql -c "SELECT count(*) FROM audit_log;"

# Ingestión manual de breaches HIBP
/home/victoria/osint-venv/bin/python3 /home/victoria/armada-osint/pipeline/hibp_ingest.py --verbose

# Swagger UI
http://victoria.local/osint/docs  (HTTPS, sin auth)

# Panel web (con API key en header)
curl -s -H "X-API-Key: $OSINT_KEY" http://127.0.0.1:8090/panel

# Config-guide (para integradores)
curl -s -H "X-API-Key: $OSINT_KEY" http://127.0.0.1:8090/api/v1/config-guide
```

### Fases del roadmap

- ✅ **F1 (MVP)**: PostgreSQL + FastAPI :8090 + HIBP catalog + auth + audit + wrappers/skill.
- ⏳ **F2 (Premium)**: API keys de Dehashed/Hunter.io/APILayer.
- ⏳ **F3 (Enrichment)**: Integración con vLLM (Qwen3.6) para categorizar breaches, risk scoring, reportes automáticos.
- ✅ **PhoneInfoga**: binario ARM64 estático v2.9.0 en `/home/victoria/.victoria-custom/bin/phoneinfoga` (24MB). Frontend Vue embebido via `embed.FS`. Scan + serve disponibles.
- ✅ **pg_dump diario**: cron `30 3 * * *` → `armada-osint/scripts/pg_backup.sh`, retención 7 días.
- ⏳ **pg_dump off-site**: destino S3/disco externo por definir.

### Estado

Servicio activo, enabled, `Restart=always`. 1029 breaches ingested. Test e2e OK
desde sandbox vía `172.18.0.1:8090`. Cron monthly programado. Wrapper y skill
re-copiados por ensure-loop tras cada rebuild.

> **WhatsApp pairing pendiente**: el `channels add` consulta `clawhub.ai` que no
> está en policy egress; se hará manualmente vía Web UI del dashboard.
