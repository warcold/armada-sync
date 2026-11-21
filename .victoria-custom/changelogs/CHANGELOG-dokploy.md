# CHANGELOG — Dokploy

### [2026-11-20 21:10 EST] [dokploy] Subdominios + dnsmasq + proyecto "Victoria - Apps" + apps hunyuan3d/lp-animate
- **Tipo**: infra + UX + registro
- **Subdominios**: nginx vhosts por servicio (`comfyui|liveportrait|n8n|openclaw|sonic|hunyuan3d|lp-animate.victoria.local`), cert wildcard `*.victoria.local`, dnsmasq en 10.0.0.5:53 (`address=/victoria.local/10.0.0.5`). Path-based `victoria.local/*` preservado como fallback universal.
- **Proyecto**: `victoria-content` renombrado a **"Victoria - Apps"** (apps internas red doméstica, sin llaves cliente).
- **Apps registradas**: `hunyuan3d` (WK-DCbltWikv9kNj5qw9N) y `lp-animate` (0HcY2YwqFCGv551gc7Q7b) creadas en `victoria-skills` con labels `applicationId` en composes.
- **Requisito owner**: router DHCP option 6 → 10.0.0.5 para resolución LAN completa.
- **Verificado**: subdominios UI 200, path-based 200, dnsmasq wildcard, cert SAN.
- **Tipo**: infra + migration
- **Qué**: `vd-comfyui`, `vd-liveportrait`, `vd-sonic` recreados vía compose de Dokploy (labels `com.docker.compose.project`); `vd-hunyuan3d` y `vd-lp-animate` con compose en disco (slugs `compose-hunyuan3d-standalone-v1`/`compose-lp-animate-standalone-v1`, **pendiente registrarlos en UI**). Todos `image: victoria-gpu-base:1.0`, `network_mode: host`, `--gpus all`, bind mounts de venvs/modelos/código.
- **Gateway**: compose `compose-input-1080p-driver-4h9dqt` ahora monta `/home/victoria/llm-gateway.py:/app/llm-gateway.py:ro` (fuente única: cambios host aplican tras restart) + `COMFY_BASE=http://172.17.0.1:8188` (env) + mounts `comfyui-templates-api`, `.victoria-custom/web`, `ComfyUI/output`, `sense_auth.py`.
- **n8n/voice**: `vd-n8n` recreado con healthcheck `wget` (curl ausente) → healthy; `vd-voice` compose command `python3`→`python3-docker`.
- **Verificado**: art E2E PNG 512x512 servido; nginx `/comfyui/ /liveportrait/ /n8n/` 200; 5 GPU + n8n healthy.
- **Pendiente**: registrar hunyuan3d/lp-animate como apps Dokploy; reconciliar `vd-voice`/`vd-video`/`vd-webnav` (creados con docker run, sin labels) vía sus composes.

## [2026-11-20] Creación subagente Dokploy + Harness + Arquitectura 7 proyectos

### Added
- Subagente `Dokploy` en `~/.config/opencode/agents/dokploy.md`
- Harness `dokploy.harness.json` en `~/.victoria-custom/harness/`
- Changelog dedicado `CHANGELOG-dokploy.md`
- Documentación completa: API endpoints, bug bodyParser, workflow obligatorio
- Arquitectura 7 proyectos Dokploy: shared, llm, gateway, openclaw, art, sentidos, infra
- 36 contenedores definidos con healthchecks, volúmenes, redes, GPU arbiter
- Traefik dynamic configs (tls, middlewares, routes) para *.victoria.local
- Variables de entorno (.env.dokploy) ~50 variables
- Scripts de validación API read-only
- Migración en 8 fases documentada

### Bug Conocido (Crítico)
- **Dokploy v0.31.4**: `bodyParser: false` en handler tRPC/Next.js
- **TODAS las mutaciones fallan**: `project.create`, `application.create`, `postgres.create`, etc.
- **Error**: `400 "Invalid input: expected object, received undefined"`
- **Workaround**: UI Web en `http://victoria.local:8081` para escrituras
- **Queries read-only funcionan perfectamente**

### Estado Actual
- Dokploy instalado (container `dokploy` + `dokploy-postgres` + `dokploy-redis` + `dokploy-traefik`)
- API key creada: `dkp_victoria_732596f16c2bfcde0f1452e2c0061ff5` (admin, org `org-victoria`)
- Traefik viejo en puerto 8081 (dashboard inseguro HTTP)
- **Migración 0%** - Solo plan, ninguna creación en Dokploy aún

### Próximos Pasos
1. Fase 0: Red + 14 volúmenes bind-mount + mkcert + backup
2. Traefik dynamic configs (archivos host)
3. `victoria-shared` en UI → validar API
4. `victoria-infra` (Traefik nuevo, GPU-Saver, Cloudflared, Armada-Sync)
5. `victoria-llm` (vLLM Main + Coder)
6. `victoria-gateway` (API, Admin, Metering)
7. `victoria-openclaw` (13 contenedores)
8. `victoria-art` (7 contenedores)
9. `victoria-skills` (5 contenedores)
10. Cutover DNS + 24h validación + apagado legacy
## [2026-11-20 15:20 EST] API tRPC corregida + Hito 1 (org/proyectos/red) + whois migrado y validado

### Fixed (documentación vs realidad)
- **El "bug bodyParser" era falso positivo**: las mutaciones funcionan con
  `POST /api/trpc/<proc>` + body `{"json":{...}}`. Antes se llamaban como GET
  con `?input=`/`?batch=1` (formato equivocado) → 400 engañoso.
- `dokploy.md` reescrito: método real, quirk de queries con input
  (`GET --data-urlencode input={"json":{...}}`), routers inexistentes
  (`dockerVolume/postgres/redis/backup`), introspección zod, estado de migración.
- API key movida a `~/.victoria-custom/secrets/dokploy.api.key` (600).

### Scaffolding corregido (bugs reales)
- `requirements.gateway.txt`: eliminados `sqlite3`/`json`/`asyncio` (stdlib,
  rompían `pip install`).
- `Dockerfile.gateway`: faltaba `COPY sense_auth.py` (el gateway lo importa).
- `Dockerfile.{whois,video,webnav,host-admin}`: añadido `COPY sense_auth.py`;
  `Dockerfile.whois`: añadido `curl` (healthcheck lo usa).

### Hito 1 (vía API)
- Organización renombrada `Victoria` → **Alfredo Pro LLC** (`cVKnzMSsWUDc2irlqgo-k`).
- Proyectos: `victoria-shared` (MJkv6ZCyW0BoW-C94YyXH), `victoria-gateway`
  (OjGnUEap9EV99lwiiQQ8l), `victoria-skills` (ZYfA2_95l1ekYGEoIi3o1).
- Red `victoria-gpu` registrada (fQYONFCneYgxNiaWwPJlp). `victoria-lan` NO se
  recrea (existe en Docker → usar `external: true`).
- `victoria-llm` descartado como proyecto: vLLM y sandbox siguen gestionados por
  nemoclaw/openshell (regla documentada); Dokploy los consume vía `172.17.0.1:8000`.

### Gateway (preparado, SIN cutover)
- Imagen `victoria-gateway:1.0` construida y validada E2E: respondió
  `DOKPLOY-OK` vía host vLLM (`172.17.0.1:8000`).
- Compose `gateway-stack` (AxWZzfekvSncpJTOQ4oea) guardado en `victoria-gateway`
  con puerto `127.0.0.1:8010` (NO desplegado: choca con el servicio host).

### whois — MIGRADO Y VALIDADO (primer servicio real en Dokploy)
- Imagen `victoria-whois:1.0`; compose `whois` (KPkMeQye3QIfDfAYDxDwL) en
  `victoria-skills`, desplegado vía API (`compose.deploy`).
- Contenedor `vd-whois` healthy en `0.0.0.0:18830` (bind 0.0.0.0 para que el
  sandbox llegue por `172.18.0.1`, igual que antes).
- Verificado: `/health` OK, whois `github.com` OK desde host, desde
  `172.18.0.1` y desde el wrapper del sandbox (`/sandbox/.openclaw/bin/whois`).
- `victoria-whois-server.service` **stopped + disabled** (archivo intacto).
  Rollback: `sudo systemctl enable --now victoria-whois-server` + borrar compose.

### Cutover hardening (mismo día)
- `openclaw-bridge-ensure.sh::ensure_whois` ahora detecta el contenedor
  `vd-whois` y NO arranca el unit host (antes lo revivía → `Address already in
  use` en loop). Bridge reiniciado para cargar el guard.
- Estado final: `victoria-whois-server` inactive/disabled, `vd-whois` healthy,
  wrapper del sandbox OK (`cloudflare.com`).
- Rollback completo: borrar/parar compose `whois` + `sudo systemctl enable --now
  victoria-whois-server` (el guard detecta que no hay contenedor y lo deja correr).

## [2026-11-20 20:00 EST] Hito 2: whois/video/webnav validados vía Dokploy (puertos alternos)

### Dockerfiles corregidos (bugs de producción)
- **video**: removed openai-whisper (el server delega al voice-server),
  deno instalado en /usr/local/bin (legible por user), venv yt-dlp solo.
  SIZE: ~46.6 MB vs antes (imagen más limpia).
- **webnav**: playwright install --with-deps chromium (bundled, no /snap);
  CHROMIUM_PATH configurable por env.
- **gateway**: requirements sin stdlib (sqlite3/json/asyncio).

### Victoria-video-server.py: DB auth read-only
- `get_vlm_key()` cambiado de `connect()` (rw) a `connect(uri=True, mode=ro)`
  para funcionar con el mount :ro de la DB. Paridad con sense_auth.py que
  ya usa `?mode=ro`.
- Env vars añadidas para portabilidad: PORT, HOST, VOICE_SERVER_URL,
  LLM_GATEWAY_URL, VIDEO_ROOT, YTDLP_BIN, FFMPEG_BIN, FFPROBE_BIN.

### Validación Dokploy (puertos alternos, sin tocar producción)
- **video** (28811): `vd-video-test` healthy, yt-dlp 2026.07.04 OK, DB read
  via `?mode=ro` → key encontrada, voice-server reachable via 172.17.0.1.
  ComposeId: ndNRCs9vR7vhmLOhlIH95.
- **webnav** (28820): `vd-webnav-test` healthy, playwright chromium OK,
  navigate→example.com → title "Example Domain" multi-idioma.
  ComposeId: SiMlcw5xLyk5nqdOw0nCu.
- **whois** (18830): producción, verified sandbox wrapper, unit host
  stopped+disabled, guard en ensure-loop. ComposeId: KPkMeQye3QIfDfAYDxDwL.

### Gateway: preparado pero NO desplegado
- Imagen victoria-gateway:1.0, compose `gateway-stack` (AxWZzfekvSncpJTOQ4oea),
  port 127.0.0.1:8010, admin_pass env, DB rw mount.
- E2E validado: responde `DOKPLOY-OK` vía host vLLM (172.17.0.1:8000).
- NO se despliega hasta cutover (puerto 8010 ocupado por systemd gateway).
- `autoDeploy` deshabilitado para evitar deploy accidental.

### Decisiones de arquitectura (confirmando no-migración)
- **vLLM/sandbox OpenClaw**: gestionados por nemoclaw/openshell (no Dokploy).
- **host-admin**: necesita docker socket + host control (no Docker).
- **gpu-saver**: necesita systemd + GPU direct (no Docker).

## [2026-11-20 21:00 EST] Cutover GATEWAY completado (producción :8010)

### Cutover ejecutado
1. `sudo systemctl stop victoria-llm-gateway` (puerto 8010 libre)
2. Compose actualizado: mount completo `/home/victoria/.victoria-llm` (no solo DB), `ADMIN_PASS=victoria-admin`, `VLLM_URL=http://172.17.0.1:8000`, red `dokploy-network` external
3. `compose.deploy` → `vd-gateway` healthy en 36s
4. Verificación: `/health` OK, inferencia con `alfredo-pro-internal` OK, admin panel LAN-only (127.0.0.1 rechazado, correcto)
5. `sudo systemctl disable victoria-llm-gateway` (unit intacto, rollback: `systemctl enable --now victoria-llm-gateway`)

### Rollback probado (simulado)
- Container tiene `restart=unless-stopped` → auto-arranca en reboot
- Unit systemd disabled → no compite por puerto
- Si falla: `systemctl enable --now victoria-llm-gateway` (restaura en <5s)

### Stack actual post-cutover
| Servicio | Gestión | Puerto | Estado |
|---|---|---|---|
| **gateway** | **Dokploy** (vd-gateway) | **:8010** | ✅ healthy |
| **whois** | **Dokploy** (vd-whois) | **:18830** | ✅ healthy |
| video | Dokploy (validación) | :28811 | healthy |
| webnav | Dokploy (validación) | :28820 | healthy |
| vLLM | nemoclay (Docker) | :8000 | healthy |
| sandbox OpenClaw | nemoclay | inference.local | healthy |
| voice | systemd (host) | :18810 | healthy |
| host-admin | systemd (host) | :18840 | healthy |
| gpu-saver | systemd (host) | — | healthy |
| sonic | systemd (host) | :18850 | healthy |
| comfyui | systemd (host) | :8188 | healthy |
| liveportrait | systemd (host) | :8180 | healthy |
| n8n | Docker | :5678 | healthy |
| cloudflared | systemd | 443 | healthy |
| nginx | systemd | 443/80 | healthy |

## [2026-11-20 21:45 EST] Renombrado proyecto: victoria-sentidos → victoria-skills

### Cambio de nomenclatura (decisión owner)
- Proyecto Dokploy renombrado vía API: `victoria-sentidos` → **victoria-skills**
  (projectId `ZYfA2_95l1ekYGEoIi3o1`).
- Actualizada toda la documentación: AGENTS.md, AGENTS-summary.md, agents/*.md,
  harness/dokploy.harness.json, CHANGELOG-dokploy.md, sense_auth.py, RULES.md,
  knowledge files, art-bridge.py, meta-business.md.
- Archivo de referencia: `docker-compose.victoria-sentidos.yml` →
  `docker-compose.victoria-skills.yml`.
- Snapshots armada-sync (latest) actualizados para consistencia.
- Razón: "sentidos" no refleja correctamente la naturaleza de estos servicios
  (son skills/habilidades de Victoria: voice, video, nav, whois, host-admin).

## [2026-11-20 22:30 EST] Granular caps para TODOS los skills (best practice)

### Cambio de arquitectura: base+add-ons extendido a 17 capacidades
- **ALL_CAPABILITIES** (sense_auth.py + gateway): 9 → 17 caps
  - Nuevas: `video`, `nav`, `whois`, `host_admin`, `sonic`, `hunyuan3d`, `animar`
- **SENSE_ELEVATION_CAPS**: ahora incluye los 7 nuevos skills (elevan a 'services')
- **SENSE_ROLES**: 7 → 14 roles (uno por skill + admin/services/art/llm/coder/readonly)
- **ROLE_DEFAULT_MODELS** (gateway): roles actualizados con caps por defecto
  - `services`: ahora incluye TODOS los skills (video, nav, whois, host_admin, sonic, hunyuan3d, animar)
  - `art`: incluye skills creativos (sonic, hunyuan3d, animar) + tts/whisper
  - Roles específicos: `video`, `nav`, `whois`, `host_admin`, `sonic`, `hunyuan3d`, `animar`
- **_CAP_FRIENDLY**: nombres amigables para hints de upgrade 403 uniformes
- **ROLE_DEFAULT_RATE_LIMIT**: límites por rol (host_admin=30/min por ser potente)
- **admin_template.html**: panel admin con 17 checkboxes + 14 roles en select
- **Validación**: sense_auth.elevation funciona para todos los nuevos caps

### Best practice aplicado
- **Principio de menor privilegio**: cada skill tiene su cap granular
- **Consistencia**: todos los skills siguen el mismo patrón (art/liveportrait/comfyui/tts/whisper ya lo tenían)
- **Auditoría**: usage_log registra qué cap usó cada request
- **Panel admin**: checkboxes mandan, rol es solo preset inicial

## [2026-11-20 23:00 EST] victoria-shared: PostgreSQL, Redis, Mailpit desplegados

### Servicios de infraestructura compartida en victoria-shared
- **PostgreSQL 16** (`vd-postgres`): puerto 5432, DB `victoria`, user `victoria`, volume `postgres-data`, healthcheck `pg_isready`. ComposeId: `CalBbgpglUbF5eDa9rxYX`.
- **Redis 7** (`vd-redis`): puerto 6379, volume `redis-data`, healthcheck `redis-cli ping`. ComposeId: `OiI6IbU4EV22P6ylEMOm0`.
- **Mailpit v1.19** (`vd-mailpit`): SMTP 1025, Web UI 8025, healthcheck HTTP 8025. ComposeId: `dT1w84uB4GkN4xiGVG6aN`.

### Notas
- Creados como **composes** (no applications) porque son imágenes Docker simples, no repos git.
- El deploy inicial de postgres quedó en "Created" → `docker start vd-postgres` lo levantó; healthcheck pasa.
- Todos con `restart: unless-stopped` → auto-arrancan en reboot.
- Puertos expuestos en 0.0.0.0 (LAN accesible); auth por red/credenciales.
- Mailpit Web UI en `http://victoria.local:8025` (via nginx si se configura).

## [2026-11-20 23:45 EST] Proyecto victoria-openclaw creado + publisher migrado

### Proyecto Dokploy: victoria-openclaw (vVzKNCyK6HNM4WioKIyGl)
- **Publisher** (`openclaw-publisher`, compose `3f723LMyIW61-on6O52Rj`): ✅ **PRODUCCIÓN**
  - Dashboard OpenClaw en `http://victoria.local:18800`
  - Gestionado por Dokploy (container `oc-publisher`)
  - Ensure-loop actualizado para detectar `oc-publisher` y no crear `openclaw-publisher` duplicado

### Componentes OpenClaw (arquitectura actual)
| Componente | Gestión | Estado |
|---|---|---|
| **Sandbox nemoclaw** | nemoclay/openshell (host) | ✅ Healthy |
| **Gateway OpenClaw** | openshell systemd user | ✅ Healthy |
| **Publisher** | **Dokploy** (`oc-publisher`) | ✅ Healthy |
| **Bridges (voz/video/whois/admin)** | Sandbox (ensure-loop) | ✅ Healthy |
| **Voice server** | Host systemd | ✅ Healthy |
| **Host-admin** | Host systemd | ✅ Healthy |
| **Persistence** | ensure-loop + persist.sh | ✅ Healthy |

### Decisión de arquitectura
- **Sandbox + gateway OpenClaw**: Se mantienen en nemoclay/openshell (orchestrator nativo)
- **Publisher**: Migrado a Dokploy (contenedor simple, bien definido)
- **Bridges + persistence**: Se mantienen en ensure-loop (lógica compleja de rebuild/recovery)
- **Voice + Host-admin**: Servicios de host (GPU, binarios del sistema)

### Bridges monitor (pendiente)
- Compose `bridges` en estado `error` (debugging pendiente)
- Los bridges reales corren en sandbox vía ensure-loop (funcionando)

