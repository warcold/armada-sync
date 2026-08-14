# 🗺️ MAPA DE AGENTES — Ecosistema Armada (red local + servicios)

> **Para qué es esto**: mapa maestro del ecosistema local de Alfredo Armada. **kalimete** es el CEREBRO CENTRAL que coordina TODO.
>
> **Regla de oro**: el agente principal (primary) NO ejecuta operaciones él mismo — delega a los subagentes según la tabla. Los subagentes ejecutan, el principal coordina y verifica.

---

## Red local Armada (LAN 10.0.0.0/24)

| Host | IP | SSH | Usuario local | Rol |
|---|---|---|---|---|
| **kalimete** | 10.0.0.106 | puerto 1111 | `warcold` | Máquina de trabajo de Alfredo (esta) |
| **victoria** | 10.0.0.5 | puerto 1666 | `victoria` (sudo, password `vcolador`) | Asistente Victoria — NUEVA victoria (2026-08-13, ex-rootsource: GPU GB10, gateway LLM, Docker) |
| **jonas** | 10.0.0.20 | puerto 1222 | `jonas` | NAS / servidor de respaldo |
| ~~rootsource~~ | ~~10.0.0.5~~ | ~~31337~~ | — | ELIMINADO 2026-08-13: host renombrado a **victoria**. La IP 10.0.0.5 y su GPU/gateway LLM ahora son de victoria. |

- DNS local: mDNS/avahi (`.local`). Resolven `kalimete.local`, `victoria.local` (→ 10.0.0.5), `jonas.local`. `rootsource.local` es alias legacy → victoria.
- La victoria VIEJA (10.0.0.64) ya NO existe como host Ubuntu: esa IP la usa ahora el Windows de Alfredo (cliente RDP `WARCOLD`).
- Firewall por host: UFW — victoria (ex-rootsource) SIN reglas activas (2026-08-12; revisar antes de asumir).
- **Escritorio remoto rootsource (2026-08-12, SOLUCIÓN FINAL)**: `gnome-remote-desktop` en modo **headless del sistema** (`grdctl --system rdp`, servicio `gnome-remote-desktop.service` de sistema, puerto 3389). Credenciales = cuenta `rootsource` (validan contra el sistema). TLS: `/var/lib/gnome-remote-desktop/tls.{crt,key}` (propiedad `gnome-remote-desktop`, chown root rompe el arranque). **NO requiere monitor físico** (rootsource tiene 0 monitores). Cliente: remmina RDP (perfil `~/.local/share/remmina/rootsource-rdp.remmina`, `security=` default/NLA, `cert_ignore=1`), script `~/bin/rootsource-rdp.sh`, ícono de escritorio. x11vnc PURGADO 2026-08-12.

## Cómo funciona todo (visión general)

```
TÚ (Alfredo/warcold)
   │
   ▼
┌──────────────────────────────────────────────────────────────────┐
│ kalimete (PRIMARY) — CEREBRO CENTRAL                             │
│ Red neurológica: conoce TODOS los .md de agentes/subagentes      │
│ de cada servicio/proyecto. Coordina, delega, verifica,           │
│ integra nuevos proyectos, documenta para el reporte diario.      │
│ Antes se llamaba eco-cloudflare (renombrado 2026-08-12).         │
└──────────────────────────────────────────────────────────────────┘
   │  (delegación vía tool task; los subagentes están hidden)
   ├──► eco-accesos         → SSH, llaves, usuarios
   ├──► eco-voice           → Servicio de voz de Victoria
   ├──► eco-cloudflare-dns  → DNS de las 3 zonas
   ├──► eco-cloudflare-security → SSL, WAF, firewall, tokens
   ├──► eco-cloudflare-storage   → KV, D1, Queues
   ├──► eco-cloudflare-tunnels   → Túneles cloudflared
   └──► eco-cloudflare-workers   → Workers/Pages
```

## Estructura final de agentes (2026-08-12)

**El selector TAB muestra SOLO 3**: `kalimete` (principal, por defecto), `plan` y `build` (para proyectos nuevos no relacionados al ecosistema).

Los subagentes viven como archivos en `~/.config/opencode/agent/` con `hidden: true` — **no aparecen en TAB ni en @-menciones, pero kalimete puede delegarles** con la tool `task` (la ocultación solo afecta la UI, no el registro de agentes).

Todos los agentes comparten la misma base de conocimiento:
- Este mapa → `~/.config/opencode/ecosistema-map/MAPA.md` (mapa maestro + docs de servicios)
- Agentes → `~/.config/opencode/agent/` (`kalimete.md` + subagentes ocultos)
- Cloudflare → skill `~/.config/opencode/skill/cloudflare/SKILL.md` + `~/.config/opencode/cloudflare-map/INVENTARIO.md`
- Agentes retirados (2026-08-12) → `~/.config/opencode/agent-backup-2026-08-12/`
- Sync red → `~/armada-sync/` (repo git; cron cada 5 min; agentes del repo en `agents/`)

## Tabla de agentes

| Agente | Modo | Visible TAB | Responsabilidad | Delegar cuando... |
|---|---|---|---|---|
| **kalimete** | primary | ✅ | CEREBRO CENTRAL: red, accesos, gateway LLM, voz, Cloudflare, documentación, reporte diario. Conoce TODO el sistema neurológico | — (es el principal, por defecto) |
| **plan** | primary (built-in) | ✅ | Planificar proyectos nuevos sin tocar código (edit denegado) | proyectos no-ecosistema |
| **build** | primary (built-in) | ✅ | Implementar código en proyectos nuevos | proyectos no-ecosistema |
| **eco-accesos** | subagent (hidden) | ❌ | Modelo de acceso SSH: usuarios, llaves, auditoría de intentos denegados, revocar/agregar llaves. (⚠️ victoria→rootsource SSH ELIMINADO 2026-08-12) | "quién tiene acceso a X", "revoca la llave de...", "revisa el log de intentos", "crea un usuario ro" |
| **eco-voice** | subagent (hidden) | ❌ | Servicio `victoria-voice`: contenedor, nginx TLS 8765, WebSocket, STT/gateway auth, espejado de idioma, troubleshooting | "no anda la voz", "cómo está el servicio de voz", "el micrófono no funciona", "cambia el URL de la UI" |
| **eco-cloudflare-dns** | subagent (hidden) | ❌ | DNS de las 3 zonas (armada.do, micaserogou.com, taohemps.com) | "crea un registro", "cambia el A de X", "cómo está el DNS de..." |
| **eco-cloudflare-security** | subagent (hidden) | ❌ | SSL, WAF, firewall, tokens, certificados, bot mgmt | "revisa el SSL", "despliega el WAF", "inventario de tokens" |
| **eco-cloudflare-storage** | subagent (hidden) | ❌ | KV, D1, Queues. R2 NO (descartado) | "crea un KV", "haz una query D1", "revisa las colas" |
| **eco-cloudflare-tunnels** | subagent (hidden) | ❌ | Túneles cloudflared, ingress, estados, conectividad | "estado del túnel", "agrega hostname al túnel", "reinicia el túnel" |
| **eco-cloudflare-workers** | subagent (hidden) | ❌ | Workers/Pages: deploy, versiones, rollback, tail, secrets, CRON | "despliega el worker", "tail al worker", "agrega un secret" |

## Agentes retirados (2026-08-12) → `agent-backup-2026-08-12/`

No se cargan en opencode (movidos fuera de `agent/` y del repo armada-sync). Referencia histórica:

- **eco-cloudflare**: renombrado a **kalimete** (2026-08-12) — ahora es el agente principal único.
- **ecosistema**: absorbido por kalimete como único primario.
- **cloudflare**: absorbido por kalimete (su mapa vive en `cloudflare-map/MAPA.md`).
- **cf-dns / cf-workers / cf-storage / cf-security / cf-tunnels**: renombrados y reasignados como eco-cloudflare-dns, eco-cloudflare-workers, eco-cloudflare-storage, eco-cloudflare-security, eco-cloudflare-tunnels (hidden).
- **rootsource-ro**: obsoleto — describía el usuario `victoria` en rootsource (ELIMINADO 2026-08-12) y el stack viejo (router :4000, TTS, Whisper, Gemma).
- **kalimete-ro** y **kalimete-ro-agent**: diseñados para correr en VICTORIA leyendo kalimete. En kalimete eran redundantes y rotos.
- **jonas-ro**: diseñado para VICTORIA (llave `id_jonas_ro`, alias `jonas.ro`, scripts HA en victoria). En kalimete no aplica.
- ⚠️ Nota: los agentes `*-ro` de victoria viven en la config de victoria (fuera de kalimete).

## Estado validado — 2026-08-12

### ⚠️ CAMBIOS IMPORTANTES EN ROOTSOURCE (2026-08-12)

- **Stack LLM reemplazado**: El router anterior (`baseline-router` :4000) fue reemplazado por:
  - **`nemoclaw-vllm`** (contenedor Docker): vLLM directo sirviendo `nvidia/Qwen3.6-35B-A3B-NVFP4` en `:8000`. Es el motor de inferencia.
  - **`llmgate`** (servicio systemd): FastAPI en `:4010` con autenticación por API keys. Config en `/home/rootsource/llmgate/` con `config.env` (ADMIN_KEY, UPSTREAM_URL, PORT). Código `llmgate.py`, DB `data/router.db` (api_keys + usage, hashes SHA-256).
  - **`openshell` sandbox** (contenedor Docker): gateway NemoClaw corriendo dentro de un sandbox NemoClaw en red `openshell-docker` (172.18.0.2). El gateway escucha en `:18789` dentro del sandbox.
  - **`nemoclaw-vllm`** y **`openshell`** se crearon automáticamente por NemoClaw — NO hay docker-compose files manuales.
  - **`nemoclaw` directory**: no existe en `/home/rootsource/` (se gestiona por el sistema NemoClaw).

- **opencode.jsonc rootsource**: nuevo provider `nvidia` apuntando a `http://127.0.0.1:4010/v1` (llmgate). Modelos: `baseline` (temp 0.6), `baseline-thinking` (temp 0.2, reasoning), `baseline-fast` (temp 0.6, 4096 tokens).

- **Diagnóstico gateway (2026-08-12, validado)**: llmgate responde `/v1/models` y `/v1/chat/completions` en ~0.9s con la ADMIN_KEY de `config.env` (extraer con `grep -oP "sk-[A-Za-z0-9]+"` — los valores van ENTRE COMILLAS). Único error del día: `httpx.ConnectError: All connection attempts failed` a las 11:40 (vLLM caído/restarting; contenedor "Up 11 hours" desde ~12:47). En modo stream, ese error NO se captura en `_stream()` (solo captura `TimeoutException`) → el cliente ve el stream cortado = chat "cargando" sin respuesta. Generaciones long-tail con `content: null` (razonamiento qwen3) pueden tardar minutos a ~50 tok/s — normal, no es cuelgue.

- **Sandbox OpenClaw**: corre dentro de un contenedor OpenShell/NemoClaw con `NEMOCLAW_*` env vars. PID mismatch: PID real ≠ PID file (conocido).

- **XRDP**: ~~corriendo en `:3389`~~ **REEMPLAZADO 2026-08-12 por GNOME Remote Desktop headless** (`grdctl --system rdp` + `gnome-remote-desktop.service`, puerto 3389, sin monitor físico). xrdp y x11vnc eliminados. Conexión desde kalimete: script `~/bin/rootsource-rdp.sh` (remmina RDP directo a 10.0.0.5:3389, sin túnel). Pantalla debe estar desbloqueada en la sesión física; `loginctl enable-linger rootsource` activado para servicios --user.

## Inventario de servicios por host (verificado 2026-08-12)

### kalimete (10.0.0.106)
- **Docker (7)**: tapmap-m1, woodly-woodly-1 (:5173), micaserogou-frontend-1 (⚠️ restarting loop, pendiente), kalimete (nginx :8080), taohemps-frontend-1 (:8076), taohemps-backend-1 (:3001), petsuite-petsuite-1 (:5176/:4003)
- **Systemd propios**: ssh, nginx, docker, containerd, cron, sddm, anydesk, waydroid-container, kalimete-tunnel, publish-kalimete-subdomains, dnsmasq
- **Repos**: dev/ops, dev/infra, ~/.axiom, armada-sync
- **Cron**: feed-cron (3 ventanas diarias), victoria update-guardian, people-migration, armada-sync cada 5 min, opencode-agents cada 30 min (⚠️ entrada rota `dev/repos/opencode-agents/`)

### victoria (10.0.0.5) — NUEVA (2026-08-13, ex-rootsource)
- **Docker (3)**: nemoclav-vllm (vLLM :8000, Qwen3.6-35B-A3B-NVFP4), openshell-my-assistant (sandbox OpenClaw, :18789), ollama (:11434)
- **Systemd propios**: ssh (1666), docker, containerd, cloudflared, llmgate (:4010), gnome-remote-desktop (:3389 RDP headless, ⚠️ RDP disabled 2026-08-13), xrdp (:3389 — ⚠️ ACTIVO pero ROMPE la sesión GNOME: "Session manager already running", revisar), gdm, nginx, dgx-dashboard, nvidia-persistenced, lldpd, smartmontools
- **GPU**: NVIDIA GB10 (~128 GB VRAM, ~47.7 GiB usados por vLLM)
- **Escritorio remoto (2026-08-13, DIAGNÓSTICO)**: xrdp escucha :3389 y valida credenciales OK, pero GNOME mata la sesión porque ya existe sesión local de victoria en `:1` (desde 15:26). `gnome-remote-desktop` está activo pero con RDP **disabled** (`grdctl --system rdp status`). Fix pendiente: habilitar grd RDP headless y/o desactivar xrdp.
- **Acceso SSH desde kalimete**: `ssh victoria.local` (10.0.0.5:1666, user `victoria`, llave `id_ed25519_kalimete` autorizada 2026-08-13) ✅ validado. Password: `vcolador` (sudo OK).
- **Victoria VIEJA (10.0.0.64)**: ya no existe como host Ubuntu — la IP la usa el Windows de Alfredo (cliente RDP `WARCOLD`). Sus servicios (victoria-voice, nginx TLS 8765) están EN ESTE HOST?? → ⚠️ PENDIENTE VERIFICAR migración de contenedores/servicios de la victoria vieja (voice, ollama, nginx).

### jonas (10.0.0.20)
- ⚠️ **SSH DESDE KALIMETE ROTO 2026-08-12**: `id_ed25519_kalimete` rechazada (Permission denied). El mapa dice NAS + HA (:8123) + backups (/srv/backups/). PENDIENTE: re-autorizar llave con eco-accesos.

- **UFW**: sin reglas activas en rootsource ni victoria (ambos sin firewall).

- **Victoria**: nginx roto — certificado `homeassistant.jonas.local.key` sin permisos (Permission denied). Gateway de Victoria expuesto a LAN (18789 en `0.0.0.0`, UFW posiblemente reseteado). opencode usa `http://10.0.0.5:4010/v1` (llmgate directo). openclaw.json apunta a `http://rootsource.local:4010/v1` pero la API key es inválida (401 Unauthorized).

### Estado anterior (2026-08-08) — parcialmente vigente

- **Acceso Victoria → rootsource**: ~~SOLO LECTURA~~ **ELIMINADO 2026-08-12** (usuario `victoria` borrado de rootsource, `ro-shell` eliminado).
- **Acceso Victoria → kalimete**: SOLO LECTURA vía túnel inverso systemd (`kalimete-tunnel`, 127.0.0.1:1111 en victoria) + `ro-shell-kalimete` (allowlist + git lectura + opencode run restringido). Agente `kalimete-ro` en victoria.
- **Voice UI**: `https://victoria.local:8765` funcionando (nginx TLS → app 127.0.0.1:8766). ⚠️ **2026-08-12**: TTS (XTTS :9001) y STT (whisper :4000) ELIMINADOS de rootsource → voice server sin TTS/STT.
- **Espejado de idioma en voz**: SOLUCIONADO — instrucción explícita con idioma nombrado por turno (`[EN] Answer in English, like the user. …`); validado 8/8 + turnos mixtos (ver eco-voice).
- **Voice → gateway autenticado**: `OPENCLAW_GATEWAY_TOKEN` real en `compose/.env` (antes CHANGE_ME → 401 en todas las llamadas al gateway). **Gateway cerrado a LAN**: ~~`ufw deny 18789/tcp`~~ ⚠️ **2026-08-12**: UFW posiblemente reseteado, verificar y reaplicar.
- **Keys unificadas**: `ROOTSOURCE_API_KEY=sk-7279…` (Victoria Gateway admin) en openclaw.json + compose/.env + ~/.zshrc. ⚠️ **2026-08-12**: la key ya no funciona para llmgate (401 Unauthorized).
- **PENDIENTE (opcional)**: rotar el token del gateway openclaw (está en texto plano en openclaw.json, que está en git).
- **Acceso Victoria → jonas**: SOLO LECTURA con llave `id_jonas_ro` + wrapper `ro-shell-jonas` (allowlist argv, sin docker exec). Alias `jonas.ro` (10.0.0.20:1222).
- **Home Assistant (jonas)**: container en red ha-net (172.18.0.2:8123), proxy nginx `https://homeassistant.jonas.local:4430`. Token long-lived `victoria-ro` (10 años) en `~/.config/ha/ha_token` (victoria) + scripts `ha-api.sh`/`ha-snapshot.sh`. 137 entidades, sin cámaras aún.
- **Agentes de victoria (2026-08-08)**: `kalimete-ro` (ssh kalimete ro + opencode run kalimete-ro-agent), `jonas-ro` (ssh jonas ro + HA), ~~`rootsource-ro`~~ (inútil, victoria no tiene SSH en rootsource). Modelo de agentes: ~~`rootsource/baseline`~~ (provider eliminado). PATRON PERMISOS: usar `"*": "deny"` al final — `"*": "ask"` ROMPE los patrones allow en opencode 1.18.15 (bug); sin "*" el default es allow (inseguro).
- **opencode en kalimete para victoria**: wrapper ro-shell-kalimete permite `opencode run --agent kalimete-ro-agent "..."` (agente custom solo lectura; explora proyectos, agentes, configs; 30-120s). Endurecido: DENY_BINS + curl sin -o/-d + find sin -exec + sed sin -i.

## Mantenimiento del mapa

- Cada vez que se cree/borre/renombre un agente → actualizar este archivo, `cloudflare-map/MAPA.md` y el repo `armada-sync` (agents/ + AGENTS.md).
- El cron de `~/armada-sync/sync.sh` (cada 5 min) despliega `agents/*.md` → `~/.config/opencode/agent/` — los cambios DEBEN hacerse en ambos lados o el sync los revierte.
- Cada vez que cambie el estado de la cuenta Cloudflare → actualizar `cloudflare-map/INVENTARIO.md` con la fecha de verificación.

## ⚠️ Regla anti-desborde de contexto (actualizado 2026-08-13)

El modelo `nvidia/Qwen3.6-35B-A3B-NVFP4` soporta **máximo 262,144 tokens** (262K) según NVIDIA docs. `opencode.jsonc` usa `limit.context: 245000` y `output: 16000` para `baseline-thinking` (margen de seguridad de ~17K). `baseline` usa `context: 158000` / `output: 24000` (conservador). `baseline-fast` usa `context: 158000` / `output: 4000`. El contenedor vLLM aún tiene `--max-model-len 163840` (no 262K) — se actualizará con `nemoclaw onboard` cuando se decida. **NUNCA volcar archivos grandes al chat** (find/grep sobre node_modules, logs completos): usar `head`, `grep -c`, `wc -l` o escribir a /tmp y leer con offset.

## Registro permanente de acciones (2026-08-12)

- Cada tarea de kalimete sobre infraestructura/servicios/proyectos DEBE dejar registro: este MAPA.md (estado) + commit en `~/armada-sync/` (auto cada 5 min vía cron).
- `plan`/`build` NO se registran (proyectos nuevos/pruebas fuera del ecosistema).
- Al cambiar algo en un servicio con agente → actualizar el .md del agente relacionado para que los modelos no adivinen (los subagentes leen su propio .md al delegarles).
