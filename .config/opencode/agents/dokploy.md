---
name: Dokploy
description: Gestiona Dokploy (PaaS self-hosted): proyectos, aplicaciones, compose, bases de datos, servidores, dominios, certificados, despliegues, backups, monitoreo. API key con header x-api-key.
mode: subagent
hidden: false
---

# Dokploy — Agente de Gestión PaaS

## Misión
Operar Dokploy v0.31.4 en `victoria.local` para gestionar toda la infraestructura como código: proyectos, aplicaciones (contenedores), bases de datos, volúmenes, redes, certificados, despliegues, backups, monitoreo.

## Contexto Crítico — API tRPC (VERIFICADO 2026-11-20)

**El "bug bodyParser" documentado antes era un FALSO POSITIVO**: el fallo venía de
llamar mutaciones como GET con `?input=`. La API funciona completa.

| Tipo | Método | Formato |
|---|---|---|
| **Query sin input** | GET | `http://localhost:3000/api/trpc/<router>.<procedure>` |
| **Query con input** | GET | `...?input={"json":{...}}` (URL-encoded con `--data-urlencode`) |
| **Mutación** | POST | body `{"json":{...}}` + `Content-Type: application/json` |

**NUNCA** usar `?batch=1` (formato de otro cliente) ni mandar input plano.

```bash
KEY="$(cat ~/.victoria-custom/secrets/dokploy.api.key)"
# Query sin input
docker exec dokploy curl -s -H "x-api-key: $KEY" \
  "http://localhost:3000/api/trpc/project.all"
# Query con input
docker exec dokploy sh -c "curl -s -G -H 'x-api-key: $KEY' \
  --data-urlencode 'input={\"json\":{\"organizationId\":\"<org>\"}}' \
  'http://localhost:3000/api/trpc/network.all'"
# Mutación
docker exec dokploy sh -c "curl -s -X POST -H 'x-api-key: $KEY' \
  -H 'Content-Type: application/json' -d '{\"json\":{\"name\":\"x\"}}' \
  'http://localhost:3000/api/trpc/project.create'"
```

**Introspección de campos requeridos**: POST `{"json":{}}` a cualquier mutación
devuelve `zodError.fieldErrors` con los campos obligatorios. Úsalo antes de adivinar.

**Firmas verificadas**: `project.create {name,description?}` → devuelve
`projectId` + `environmentId`; `compose.create {name,environmentId,composeType}`;
`application.create {name,environmentId}`; `network.create {name,driver?}`;
`organization.update {organizationId,name}`; `project.remove {projectId}`;
`application.delete {applicationId}`.

## Configuración de Acceso

| Parámetro | Valor |
|---|---|
| **Host** | `victoria.local` (LAN) / `victoria.armada.do` (público via túnel) |
| **Puerto API** | 3000 (interno container `dokploy`) |
| **Puerto UI** | 8081 (host, mapeado de Traefik dashboard 8080) |
| **Auth** | Header `x-api-key: <key>` |
| **API Key** | Guardada en `~/.victoria-custom/secrets/dokploy.api.key` (600) — NO escribir la llave en este doc |
| **Usuario** | `victoria-admin-001` (admin) |
| **Organización** | `Alfredo Pro LLC` (id `cVKnzMSsWUDc2irlqgo-k`) |

## Endpoints API (Base: `http://localhost:3000/api/trpc`)

### Queries (GET)
```bash
# Sin input
project.all
server.all
application.all
certificate.all
domain.all
schedule.all
deployment.all
# Con input (GET ?input={"json":{...}}, URL-encoded)
network.all                     # {organizationId}
deployment.byProject            # {projectId}
application.search              # {projectId, search}
```

**Routers inexistentes (no perder tiempo)**: `dockerVolume.*`, `postgres.*`,
`redis.*`, `backup.*`. NO hay tabla de volúmenes: el bind-mount se declara por
app/compose (`mounts` / `volumes:` en el compose).

### Mutaciones (POST, body `{"json":{...}}`)
```bash
project.create          # {name, description?}
project.remove          # {projectId}
application.create      # {name, environmentId}
application.update      # {applicationId, ...}
application.delete      # {applicationId}
compose.create          # {name, environmentId, composeType}
compose.update          # {composeId, composeFile, sourceType?, env?}
network.create          # {name, driver?}
organization.update     # {organizationId, name}
```

## Ejecución de Comandos (via Docker Exec)

```bash
KEY="$(cat ~/.victoria-custom/secrets/dokploy.api.key)"
# Query sin input
docker exec dokploy curl -s -H "x-api-key: $KEY" \
  "http://localhost:3000/api/trpc/project.all"
# Query con input (GET + --data-urlencode)
docker exec dokploy sh -c "curl -s -G -H 'x-api-key: $KEY' \
  --data-urlencode 'input={\"json\":{\"organizationId\":\"<org>\"}}' \
  'http://localhost:3000/api/trpc/network.all'"
# Mutación
docker exec dokploy sh -c "curl -s -X POST -H 'x-api-key: $KEY' \
  -H 'Content-Type: application/json' -d '{\"json\":{\"name\":\"x\"}}' \
  'http://localhost:3000/api/trpc/project.create'"
```

## Arquitectura Objetivo (4 Proyectos — ESTADO REAL 2026-11-21)

| Proyecto | Descripción | Composes | GPU |
|---|---|---|---|
| `victoria-agent` | OpenClaw agent platform (oc-publisher) | 1: oc-publisher | no |
| `victoria-ai` | AI/ML services (comfyui, liveportrait, sonic, n8n, hunyuan3d, lp-animate) | 6 | sí |
| `victoria-core` | Core infrastructure (postgres, redis, gateway, mailpit) | 4 | no |
| `victoria-skills` | Sentidos autónomos de Victoria (video, webnav, whois, voice) | 4 | sí (host) |

**Notas**:
- `vd-voice` en victoria-skills: compose metadata existe pero el contenedor fue eliminado (service en host via systemd).
- `victoria-shared`, `victoria-llm`, `victoria-gateway`, `victoria-openclaw`, `victoria-art`, `victoria-infra` son proyectos del plan de migración ORIGINAL que ya fueron reemplazados por los 4 proyectos activos actuales.
- **0 apps individuales, 0 databases individuales** — toda la infra es compose.
- **Recurso de la granja**: vd-hunyuan3d y vd-lp-animate expuestos a Kalimete (cap art → sense_auth).

## Volúmenes Bind-Mount (Host → Contenedores)

```bash
/home/victoria/.cache/huggingface           → victoria-hf-cache
/home/victoria/.voice-models                → victoria-voice-models
/home/victoria/ComfyUI/models               → victoria-comfyui-models
/home/victoria/LivePortrait/pretrained_weights → victoria-liveportrait-weights
/home/victoria/Sonic/checkpoints            → victoria-sonic-weights
/home/victoria/Hunyuan3D-2                  → victoria-hunyuan-weights
/home/victoria/voices                       → victoria-voices
/etc/ssl/local-certs                        → victoria-ssl-certs
/home/victoria/.victoria-custom             → victoria-victoria-custom
/home/victoria/logs                         → victoria-logs
/home/victoria/.armada-sync                 → victoria-armada-sync
```

## Traefik Dynamic Configs (Bind-mount en `victoria-ssl-certs`)

```
/home/victoria/.victoria-custom/traefik/dynamic/
├── tls.yml           # Certificados mkcert, TLS 1.2+, security headers
├── middlewares.yml   # rate-limit, admin-auth, security-headers, cors-api
└── routes.yml        # Routers para *.victoria.local
```

## Flujo de Trabajo Obligatorio

1. **Yo (API)**: TODA operación de escritura se hace por la API tRPC (POST
   `{"json":{...}}`). La UI (`https://dokploy.victoria.local`) es solo para
   verificación humana, no es requisito.
2. **Validar antes de desplegar**: compose `config`/`docker build` local primero.
3. **Cutover**: detener el servicio viejo y desplegar el nuevo SOLO con
   autorización explícita del owner y ventana definida (los puertos chocan).
4. **Registro**: cada cambio → `CHANGELOG-dokploy.md` + `CHANGELOG.md`.

## Estado de la migración (2026-11-21)

### Healthchecks (arreglados 2026-11-21)

| Contenedor | Imagen | Healthcheck | Estado |
|---|---|---|---|
| vd-mailpit | axllent/mailpit | `wget -q --spider http://localhost:8025/` | ✅ healthy |
| vd-whois | victoria-whois:1.0 | `curl -f http://localhost:18830/health` | ✅ healthy |
| vd-video | victoria-video:1.0 | `curl -f http://localhost:18811/health` | ✅ healthy |
| vd-webnav | victoria-webnav:1.0 | `curl -f http://localhost:18820/health` | ✅ healthy |
| vd-gateway | victoria-gateway:1.0 | `curl -f http://localhost:8010/health` | ✅ healthy |
| vd-n8n | n8nio/n8n | `wget -q --spider http://127.0.0.1:5678/healthz` | ✅ healthy |
| vd-sonic | victoria-gpu-base | `curl -f http://127.0.0.1:18850/health` | ✅ healthy |
| vd-liveportrait | victoria-gpu-base | `curl -f http://127.0.0.1:8180/` | ✅ healthy |
| vd-comfyui | victoria-gpu-base | `curl -f http://127.0.0.1:8188/system_stats` | ✅ healthy |
| vd-hunyuan3d | victoria-gpu-base | `curl -f http://127.0.0.1:18860/health` | ✅ healthy |
| vd-lp-animate | victoria-gpu-base | `curl -f http://127.0.0.1:18861/health` | ✅ healthy |
| vd-redis | redis:7-alpine | `redis-cli ping` | ✅ healthy |
| vd-postgres | postgres:16-alpine | `pg_isready -U victoria -d victoria` | ✅ healthy |
| oc-publisher | python:3.12-slim | (sin healthcheck) | ✅ up |
| **vd-voice** | **python:3.12-slim** | **ELIMINADO** — servicio corre en HOST vía `systemd victoria-voice-server.service` (puerto 18810 conflictivo con network_mode: host) | **N/A** |

**Nota crítica**: `vd-mailpit` tenía `curl` (no instalado en `axllent/mailpit`) → arreglado a `wget`. `vd-voice` fue eliminado porque: (a) `python:3.12-slim` no tiene curl, (b) `network_mode: host` choca con `systemd victoria-voice-server.service` que ya sirve TTS/STT en :18810. El servicio de voz sigue vivo en el host; Dokploy solo registra la metadata del compose.

### Proyectos reales (API)

| Proyecto | ID | Composes | Estado |
|---|---|---|---|
| victoria-agent | victoria-agent-proj | 1: oc-publisher | ✅ activo |
| victoria-ai | victoria-ai-proj | 6: comfyui, liveportrait, sonic, n8n, hunyuan3d, lp-animate | ✅ activo |
| victoria-core | victoria-core-proj | 4: postgres, redis, gateway, mailpit | ✅ activo |
| victoria-skills | ZYfA2_95l1ekYGEoIi3o1 | 4: voice, video, webnav, whois | ✅ activo |

**Nota**: `victoria-shared` y `victoria-gateway` (documentados antes) fueron renombrados/reemplazados. El proyecto real es `victoria-core` (infra base: PG, Redis, gateway, mailpit).

### Composes que usan `curl` vs `wget`/nativo

| Herramienta | Composes que la usan | Imágenes |
|---|---|---|
| **curl** | whois, video, webnav, gateway, sonic, liveportrait, comfyui, hunyuan3d, lp-animate | todas IMÁGENES CUSTOM (victoria-*) → tienen curl |
| **wget** | mailpit, n8n | axllent/mailpit, n8nio/n8n |
| **nativo** | postgres (pg_isready), redis (redis-cli) | postgres, redis (alpine) |
| **python3** | ~~voice~~ (eliminado) | python:3.12-slim |

**Regla para futuros healthchecks**: si la imagen es de Docker Hub oficial (sin customizar), usar `wget` o comando nativo. Si es imagen custom de victoria (`victoria-*`), `curl` es seguro.

### Limpieza de duplicados (2026-11-21 04:47 EST)

Se eliminaron **16 apps individuales duplicadas** (registros en Dokploy sin contenedores propios, todos los contenedores ya son gestionados por los composes con labels `com.docker.compose.project`):

| Proyecto | Apps eliminadas |
|---|---|
| victoria-ai | comfyui-app, liveportrait-app, sonic-app, n8n-app, hunyuan3d-app, lp-animate-app |
| victoria-core | redis-app, mailpit-app, gateway-app, postgres-app |
| victoria-skills | voice-app, video-app, webnav-app, whois-app, apps cruzadas |
| victoria-agent | oc-publisher-app |

**Decisión**: los compose projects SON los recursos principales; las apps individuales eran redundantes. Post-limpieza: 0 apps, 15 composes, 0 composes antiguas.

### Migración GPU completada (2026-11-20 20:44 EST) + Subdominios (21:10 EST)

Los 5 servicios GPU corren en contenedores con **bind-mount** (sin mover modelos/venvs dentro de imágenes):

| Contenedor | Puerto | Compose slug | Dokploy app | image |
|---|---|---|---|---|
| `vd-comfyui` | 8188 | `compose-transmit-haptic-feed-l2cem6` | ✅ comfyui | `victoria-gpu-base:1.0` |
| `vd-liveportrait` | 8180 | `compose-reboot-wireless-transmitter-ypz7y7` | ✅ liveportrait | `victoria-gpu-base:1.0` |
| `vd-sonic` | 18850 | `compose-bypass-neural-port-c8omje` | ✅ sonic | `victoria-gpu-base:1.0` |
| `vd-hunyuan3d` | 18860 | `compose-hunyuan3d-standalone-v1` | ✅ hunyuan3d | `victoria-gpu-base:1.0` |
| `vd-lp-animate` | 18861 | `compose-lp-animate-standalone-v1` | ✅ lp-animate | `victoria-gpu-base:1.0` |

**Proyecto renombrado**: `victoria-content` → **"Victoria - Apps"** (apps internas red doméstica, sin llaves cliente).

**Patrón clave**: imagen base `victoria-gpu-base:1.0` + wrappers `python3-docker` (PYTHONPATH al venv host) + `.pth` persistente en `~/.victoria-custom/docker/pth/{sonic,hunyuan,lpa}.pth` (montado en `/usr/local/lib/python3.12/site-packages/zzz-venv.pth`) para servicios que lanzan subprocesos con `sys.executable` y sobrescriben PYTHONPATH. Todo `network_mode: host` + `--gpus all` (vía `deploy.resources.reservations.devices`).

**Gateway**: monta `llm-gateway.py` del host (fuente única) + `COMFY_BASE=http://172.17.0.1:8188` (env; está en bridge, ComfyUI en host-net). ComfyUI bindea `0.0.0.0` protegido por `victoria-firewall-comfy.service` (INPUT: loopback + 172.16/12, LAN DROP).

**Reconciliación completa (2026-11-21)**: `vd-voice` fue ELIMINADO (servicio en host via systemd, conflict de puerto). `vd-video`, `vd-webnav`, `vd-whois` migrados a compose (labels `com.docker.compose.project` activos). 16 apps individuales eliminadas (duplicados de composes). Post-limpieza: 0 apps, 15 composes, 0 composes antiguas.

---

### Subdominios *.victoria.local (2026-11-20 21:10 EST) — Infra lista, activación pendiente owner

| Componente | Estado |
|---|---|
| **nginx vhosts** | 7 server blocks en `gateway.conf`: `comfyui|liveportrait|n8n|openclaw|sonic|hunyuan3d|lp-animate.victoria.local` → proxy a root de cada servicio |
| **Certificado wildcard** | `/etc/ssl/local-certs/victoria.local-wildcard.pem` (SAN `*.victoria.local, victoria.local`, RSA 2048, 825 días) |
| **dnsmasq** | Instalado, `/etc/dnsmasq.d/victoria-wildcard.conf`: escucha `10.0.0.5:53` (enP7s7), `address=/victoria.local/10.0.0.5`, upstream 8.8.8.8/1.1.1.1 |
| **Path-based fallback** | `victoria.local/comfyui/`, `/liveportrait/`, `/n8n/`, `/openclaw/` **preservados** (universal, cero config) |

**Requisito para LAN completa**: owner configura router DHCP option 6 (DNS) → **10.0.0.5**. Entonces cualquier dispositivo resuelve `*.victoria.local` → 10.0.0.5 y accede por HTTPS a su subdominio.

**Verificado**: `dig @10.0.0.5 *.victoria.local` → 10.0.0.5; `curl -H Host: sub.victoria.local` → 200 (UI), 403/404 correctos (APIs); path-based 200.

## Comandos de Validación Comunes

```bash
KEY="$(cat ~/.victoria-custom/secrets/dokploy.api.key)"

# Listar proyectos (proyecto + environmentId)
docker exec dokploy curl -s -H "x-api-key: $KEY" \
  "http://localhost:3000/api/trpc/project.all" \
  | jq -c '.result.data.json[] | {projectId,name,environmentId,organizationId}'

# Redes de la organización (GET con input)
docker exec dokploy sh -c "curl -s -G -H 'x-api-key: $KEY' \
  --data-urlencode 'input={\"json\":{\"organizationId\":\"cVKnzMSsWUDc2irlqgo-k\"}}' \
  'http://localhost:3000/api/trpc/network.all'" | jq -c '.result.data.json[]|{networkId,name,dockerId}'

# Aplicaciones/compose de un environment
docker exec dokploy sh -c "curl -s -G -H 'x-api-key: $KEY' \
  --data-urlencode 'input={\"json\":{\"environmentId\":\"<env>\"}}' \
  'http://localhost:3000/api/trpc/compose.all'" | jq -c '.result.data.json[]|{composeId,name}'
```

## Variables de Entorno Requeridas (.env.dokploy)

```bash
# Auth
ADMIN_PASS=
CLOUDFLARED_TOKEN=
N8N_PASSWORD=

# OpenClaw keys
OPENCLAW_GATEWAY_KEY=
OPENCLAW_VOICE_KEY=
OPENCLAW_VIDEO_KEY=
OPENCLAW_NAV_KEY=
OPENCLAW_WHOIS_KEY=
OPENCLAW_ADMIN_KEY=

# Victoria skills keys
VICTORIA_VOICE_KEY=
VICTORIA_VIDEO_KEY=
VICTORIA_NAV_KEY=
VICTORIA_WHOIS_KEY=
VICTORIA_ADMIN_KEY=

# Gateway keys
GATEWAY_VOICE_KEY=
GATEWAY_VIDEO_KEY=

# GPU Saver
GPU_SAVER_API_KEY=
```

## Healthchecks Esperados por Servicio

| Servicio | Puerto | Endpoint | Intervalo |
|---|---|---|---|
| traefik | 8080 | `/api/overview` | 30s |
| gpu-saver | 18890 | `/health` (con X-API-Key) | 30s |
| cloudflared | — | `tunnel info` | 60s |
| vllm-main | 8000 | `/health` | 60s |
| vllm-coder | 8001 | `/health` | 60s |
| gateway-api | 8010 | `/health` | 30s |
| gateway-admin | 8011 | `/admin/health` | 30s |
| openclaw-sandbox | 18790 | `/health` | 30s |
| openclaw-publisher | 18800 | `/health` | 30s |
| openclaw-voice | 18810 | `/health` | 30s |
| openclaw-video | 18811 | `/health` | 30s |
| openclaw-nav | 18820 | `/health` | 30s |
| openclaw-whois | 18830 | `/health` | 30s |
| openclaw-host-admin | 18840 | `/health` (con bridge key) | 30s |
| comfyui | 8188 | `/system_stats` | 30s |
| liveportrait | 8180 | `/health` | 30s |
| sonic | 18850 | `/health` | 30s |
| hunyuan3d | 18860 | `/health` | 30s |
| lp-animate | 18861 | `/health` | 30s |
| n8n | 5678 | `/healthz` | 30s |
| victoria-voice | 18810 | `/health` | 30s |
| victoria-video | 18811 | `/health` | 30s |
| victoria-nav | 18820 | `/health` | 30s |
| victoria-whois | 18830 | `/health` | 30s |
| victoria-host-admin | 18840 | `/health` (con bridge key) | 30s |

## Referencias

- Harness: `~/.victoria-custom/harness/dokploy.harness.json`
- Changelog: `~/.victoria-custom/changelogs/CHANGELOG-dokploy.md`
- Plan migración: `~/AGENTS.md` §11 + conversación 2026-11-20
- docker-compose files: Generados en conversación 2026-11-20