# 🗺️ MAPA DE AGENTES — Ecosistema Armada (red local + servicios)

> **Para qué es esto**: mapa maestro del ecosistema local de Alfredo Armada. **kalimete** es el CEREBRO CENTRAL que coordina TODO.
>
> **Regla de oro**: el agente principal (primary) NO ejecuta operaciones él mismo — delega a los subagentes según la tabla. Los subagentes ejecutan, el principal coordina y verifica.

---

## Red local Armada (LAN 10.0.0.0/24)

| Host | IP | SSH | Usuario local | Rol |
|---|---|---|---|---|
| **kalimete** | 10.0.0.106 | puerto 1111 | `warcold` | Máquina de trabajo de Alfredo (esta) |
| **victoria** | 10.0.0.5 | puerto 1666 | `victoria` (sudo, password `vcolador`) | Asistente Victoria: GPU GB10, vLLM :8000, gateway LLM :8010, Docker, RDP headless :3389, túnel cloudflared |
| **jonas** | 10.0.0.20 | puerto 1222 | `jonas` | NAS / servidor de respaldo |

- DNS local: mDNS/avahi (`.local`). Resolven `kalimete.local`, `victoria.local` (→ 10.0.0.5), `jonas.local`.
- La IP 10.0.0.64 es del Windows de Alfredo (cliente RDP `WARCOLD`).
- Firewall por host: UFW — victoria **INACTIVE (confirmado 2026-08-14, sin firewall)**.
- **Escritorio remoto victoria (2026-08-13, SOLUCIÓN FINAL)**: `gnome-remote-desktop` en modo **headless del sistema** (`grdctl --system rdp`, servicio `gnome-remote-desktop.service` de sistema, puerto 3389). Credenciales explícitas: `victoria`/`vcolador` (seteadas con `grdctl --system rdp set-credentials`). TLS: `/var/lib/gnome-remote-desktop/tls.{crt,key}` (self-signed CN=victoria.local, generado 2026-08-13). **NO requiere monitor físico**. Cliente: remmina RDP (perfil `~/.local/share/remmina/victoria-rdp.remmina`, `cert_ignore=1`), script `~/bin/victoria-rdp.sh`. xrdp DESACTIVADO 2026-08-13 (rompía la sesión GNOME).

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
   ├──► eco-cloudflare-dns  → DNS de las 3 zonas
   ├──► eco-cloudflare-security → SSL, WAF, firewall, tokens
   ├──► eco-cloudflare-storage   → KV, D1, Queues
   ├──► eco-cloudflare-tunnels   → Túneles cloudflared
   └──► eco-cloudflare-workers   → Workers/Pages
```

> ⚠️ **eco-voice NO está en la lista activa**: el servicio de voz fue **ELIMINADO 2026-08-14** (verificado: no existe victoria-voice, ni nginx voice, ni puertos 8765/8766). El agente eco-voice.md queda como documentación de reconstrucción.

## Estructura final de agentes (2026-08-12, re-verificado 2026-08-14)

**El selector TAB muestra SOLO 3**: `kalimete` (principal, por defecto), `plan` y `build` (para proyectos nuevos no relacionados al ecosistema).

Los subagentes viven como archivos en `~/.config/opencode/agent/` con `hidden: true` — **no aparecen en TAB ni en @-menciones, pero kalimete puede delegarles** con la tool `task` (la ocultación solo afecta la UI, no el registro de agentes).

Todos los agentes comparten la misma base de conocimiento:
- Este mapa → `~/.config/opencode/ecosistema-map/MAPA.md` (mapa maestro + docs de servicios)
- Agentes → `~/.config/opencode/agent/` (`kalimete.md` + subagentes ocultos)
- Cloudflare → skill `~/.config/opencode/skills/cloudflare/SKILL.md` (PLURAL — la carpeta `skill/` singular fue ELIMINADA 2026-08-14) + `~/.config/opencode/cloudflare-map/INVENTARIO.md`
- Agentes retirados (2026-08-12) → **backup BORRADO 2026-08-14**; solo quedan en el historial git de armada-sync
- Sync red → `~/armada-sync/` (repo git; cron cada 5 min; agentes del repo en `agents/`)

## Tabla de agentes

| Agente | Modo | Visible TAB | Responsabilidad | Delegar cuando... |
|---|---|---|---|---|
| **kalimete** | primary | ✅ | CEREBRO CENTRAL: red, accesos, gateway LLM, Cloudflare, documentación, reporte diario. Conoce TODO el sistema neurológico | — (es el principal, por defecto) |
| **plan** | primary (built-in) | ✅ | Planificar proyectos nuevos sin tocar código (edit denegado) | proyectos no-ecosistema |
| **build** | primary (built-in) | ✅ | Implementar código en proyectos nuevos | proyectos no-ecosistema |
| **eco-accesos** | subagent (hidden) | ❌ | Modelo de acceso SSH: usuarios, llaves, auditoría de intentos denegados, revocar/agregar llaves | "quién tiene acceso a X", "revoca la llave de...", "revisa el log de intentos", "crea un usuario ro" |
| **eco-voice** | subagent (hidden) | ❌ | ⚠️ Servicio de voz **ELIMINADO 2026-08-14** — el .md documenta qué existió y cómo reconstruirlo si se pide | SOLO reconstrucción explícita del usuario |
| **eco-cloudflare-dns** | subagent (hidden) | ❌ | DNS de las 3 zonas (armada.do, micaserogou.com, taohemps.com) | "crea un registro", "cambia el A de X", "cómo está el DNS de..." |
| **eco-cloudflare-security** | subagent (hidden) | ❌ | SSL, WAF, firewall, tokens, certificados, bot mgmt | "revisa el SSL", "despliega el WAF", "inventario de tokens" |
| **eco-cloudflare-storage** | subagent (hidden) | ❌ | KV, D1, Queues. R2 NO (descartado) | "crea un KV", "haz una query D1", "revisa las colas" |
| **eco-cloudflare-tunnels** | subagent (hidden) | ❌ | Túneles cloudflared, ingress, estados, conectividad | "estado del túnel", "agrega hostname al túnel", "reinicia el túnel" |
| **eco-cloudflare-workers** | subagent (hidden) | ❌ | Workers/Pages: deploy, versiones, rollback, tail, secrets, CRON | "despliega el worker", "tail al worker", "agrega un secret" |

## Agentes retirados (2026-08-12)

No se cargan en opencode (movidos fuera de `agent/` y del repo armada-sync). Referencia histórica (**el backup `agent-backup-2026-08-12/` fue BORRADO 2026-08-14 — sin copias locales**):

- **eco-cloudflare**: renombrado a **kalimete** (2026-08-12) — ahora es el agente principal único.
- **ecosistema**: absorbido por kalimete como único primario.
- **cloudflare**: absorbido por kalimete (su mapa vive en `cloudflare-map/MAPA.md`).
- **cf-dns / cf-workers / cf-storage / cf-security / cf-tunnels**: renombrados y reasignados como eco-cloudflare-dns, eco-cloudflare-workers, eco-cloudflare-storage, eco-cloudflare-security, eco-cloudflare-tunnels (hidden).
- **kalimete-ro** y **kalimete-ro-agent**: diseñados para correr en VICTORIA leyendo kalimete. En kalimete eran redundantes y rotos.
- **jonas-ro**: diseñado para VICTORIA (llave `id_jonas_ro`, alias `jonas.ro`, scripts HA en victoria). En kalimete no aplica.

## Estado validado — 2026-08-14

### Stack LLM en victoria

- **`nemoclaw-vllm`** (contenedor Docker, `managed-vllm: true`): vLLM directo sirviendo `nvidia/Qwen3.6-35B-A3B-NVFP4` en `:8000`. Es el motor de inferencia. GPU GB10 (~128 GB VRAM; modelo ~20.4 GiB). **Parámetros (ajustados 2026-08-14)**: `--max-model-len 262144 --gpu-memory-utilization 0.5 --max-num-seqs 8 --max-num-batched-tokens 16384 --kv-cache-dtype fp8 --enable-chunked-prefill --async-scheduling --enable-prefix-caching --quantization modelopt --moe-backend marlin --attention-backend flashinfer --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3`. Resultado: **KV cache 3,447,590 tokens (~34.7 GiB) → concurrencia 13.15× para requests de 262K** (antes 0.4/4/8192 → se trancaba con 2-3 requests grandes). ⚠️ NemoClaw lo gestiona (label managed-vllm): si se recrea desde NemoClaw puede volver a parámetros por defecto.
- **`victoria-llm-gateway`** (servicio systemd, v2.0.0): FastAPI en `:8010` (**loopback-only desde 2026-08-14**; GATEWAY_HOST=127.0.0.1) con autenticación **por VALOR de llave** — bearer `vllm-key-<64hex>`, lookup por key_hash; formato `vllm-key-` desde 2026-08-14. **Llaves finales (3, 2026-08-14)**: `alfredo` (Alfredo Armada, admin — la usa opencode de kalimete y el reporte diario via VICTORIA_API_KEY), `victoria` (Victoria Armada/NemoClaw, admin), `juancarlos` (Juan Carlos Jerez, coder). `demo` ELIMINADA. Código `/home/victoria/llm-gateway.py` (metering tokens+costo, precio por llave `$/1k tokens` default 0.02, `budget` → 402, roles admin/coder, rate/min → 429, edición PUT de llaves), template `/home/victoria/admin_template.html`, backups `llm-gateway.py.bkup-v1-20260814` / `.bkup-v2-20260814`. DB `/home/victoria/.victoria-llm/llm-gateway.db` (api_keys + usage_log; migración automática v1→v2). Env: `VLLM_URL`, `GATEWAY_PORT`, `ADMIN_PASS`, `SERVED_MODEL`, `DEFAULT_PRICE_PER_1K`. Rutas: `/v1/chat/completions`, `/v1/completions`, `/v1/usage` (admin=global, coder=propio), `/models` (404 — NO existe, normal), `/admin*` (panel solo LAN). **Acceso LAN**: nginx TLS 443 (cert mkcert victoria.local, expira nov-2028) → 127.0.0.1:8010. URLs: **`https://victoria.local/admin`** (panel), **`https://victoria.local/v1/...`** (API). Túnel `victoria.armada.do` → 8010 (solo API con llaves; /admin 403 vía túnel). Health: `curl http://127.0.0.1:8010/v1/chat/completions` sin bearer → 401 = OK.
- **opencode kalimete**: provider **`alfredopro`** (name "www.alfredo.pro", model "Coding con Victoria") → `https://victoria.local/v1`, apiKey = llave `alfredo` (no más vLLM directo). **opencode victoria**: provider `vllm` directo → `http://127.0.0.1:8000/v1` (sin llaves). Límites ambos: **context 240000 + output 20000 = 260000 ≤ 262144** (antes 262144+32768 → excedía el límite total → 400 "max context length exceeded"). El gateway normaliza cualquier alias de model al id servido (`qwen3.6`, `Qwen3.6-35B-A3B-NVFP4`, etc.).
- **`openshell-my-assistant`** (contenedor Docker, healthy): sandbox NemoClaw/OpenClaw en red `openshell-docker`. ⚠️ **Su gateway :18789 NO responde (verificado 2026-08-14: nvsm-api-gateway inactive, nada escucha)** — la UI de NemoClaw/OpenClaw NO está disponible ni en LAN ni en túnel. Solo LAN si algún día vuelve — NUNCA en el túnel/dominio.
- **`nemoclaw-vllm`** y **`openshell`** se crearon automáticamente por NemoClaw — NO hay docker-compose files manuales.

- **Diagnóstico gateway (2026-08-12, validado)**: en modo stream, un `httpx.ConnectError` NO se captura en `_stream()` (solo captura `TimeoutException`) → el cliente ve el stream cortado = chat "cargando" sin respuesta. Generaciones long-tail con `content: null` (razonamiento qwen3) pueden tardar minutos a ~50 tok/s — normal, no es cuelgue.

- **Sandbox OpenClaw**: corre dentro de un contenedor OpenShell/NemoClaw con `NEMOCLAW_*` env vars. PID mismatch: PID real ≠ PID file (conocido).

- **RDP**: GNOME Remote Desktop headless en `:3389` (grdctl --system rdp, credenciales victoria/vcolador, TLS self-signed). xrdp DESACTIVADO 2026-08-13 (su sesión GNOME moría por "Session manager already running" con la sesión local activa). Conexión desde kalimete: script `~/bin/victoria-rdp.sh` (remmina RDP directo a 10.0.0.5:3389). Desde Windows: usuario `victoria` / clave `vcolador`, aceptar cert self-signed.

## Inventario de servicios por host (verificado 2026-08-14)

### kalimete (10.0.0.106)
- **Docker (7)**: tapmap-m1, woodly-woodly-1 (:5173), micaserogou-frontend-1 (⚠️ restarting loop, pendiente), kalimete (nginx :8080), taohemps-frontend-1 (:8076), taohemps-backend-1 (:3001), petsuite-petsuite-1 (:5176/:4003)
- **Systemd propios**: ssh, nginx, docker, containerd, cron, sddm, anydesk, waydroid-container, kalimete-tunnel (active ✓), publish-kalimete-subdomains, dnsmasq
- **Repos**: dev/ops, dev/infra, ~/.axiom, armada-sync
- **Cron**: check-jobs, RSS digest (entrada apuntando a /home/victoria — revisar, no existe en kalimete), armada-sync cada 5 min (**DUPLICADO: 2 líneas idénticas — limpiar**), y entradas históricas (feed-cron, victoria update-guardian, people-migration, opencode-agents con ruta rota `dev/repos/opencode-agents/`)

### victoria (10.0.0.5) — validado 2026-08-14
- **Docker (2)**: nemoclaw-vllm (:8000, up), openshell-my-assistant (healthy, sandbox). ⚠️ ollama NO corre. ⚠️ **NO existe contenedor victoria-voice** (voz eliminada). ⚠️ **NO existe ComfyUI** (:8188 nada escucha).
- **Systemd**: ssh (1666), docker, containerd, cloudflared (túnel victoria-armada, healthy 4 conexiones), victoria-llm-gateway (:8010, active), gnome-remote-desktop (:3389 RDP headless, active), gdm, dgx-dashboard, nvidia-persistenced, lldpd, smartmontools. **nvsm-api-gateway: INACTIVE** (gateway de OpenClaw :18789 no responde).
- **xrdp**: DESACTIVADO (stop + disable 2026-08-13) — ya no compite por :3389
- **nginx**: sites-enabled = `default` + `gateway.conf` (TLS 443 → 127.0.0.1:8010, cert mkcert victoria.local). NO existe voice.conf ni homeassistant.jonas.local (cert viejo sin permisos era del stack anterior — ya no aplica)
- **GPU**: NVIDIA GB10 (~128 GB VRAM, ~47.7 GiB usados por vLLM)
- **Arquitectura**: ARM64 — binarios/docker images deben ser arm64
- **Acceso SSH desde kalimete**: `ssh victoria.local` (10.0.0.5:1666, user `victoria`, llave `id_ed25519_kalimete` autorizada 2026-08-13) ✅ validado. Password: `vcolador` (sudo OK).
- **Túnel Cloudflare**: `victoria-armada` (`d9abe241-fcbb-40a6-9202-36d0cfa7a95a`), healthy, 4 conexiones QUIC. Ingress: `victoria.armada.do` → `http://127.0.0.1:8010` (victoria-llm-gateway — SOLO API LLM con llaves); default → 404. cloudflared instalado 2026-08-13 (arm64, token en /etc/cloudflared/token). ⚠️ Panel /admin = SOLO victoria.local (LAN) — vía túnel da 403.
- **Victoria VIEJA (10.0.0.64)**: ya no existe como host Ubuntu — la IP la usa el Windows de Alfredo (cliente RDP `WARCOLD`). Sus servicios de voz (victoria-voice, nginx 8765, ollama) **NO fueron migrados y el servicio de voz fue ELIMINADO 2026-08-14** (verificado: nada escucha en 8765/8766, no existe contenedor ni conf nginx).

### jonas (10.0.0.20)
- ⚠️ **SSH DESDE KALIMETE ROTO (2026-08-12, re-verificado 2026-08-14)**: `id_ed25519_kalimete` rechazada (Permission denied). El mapa dice NAS + HA (:8123) + backups (/srv/backups/) + updater DDNS. PENDIENTE: re-autorizar llave con eco-accesos (el updater DDNS de jonas también actualizaba `victoria.armada.do` — hoy es CNAME del túnel; si recrea el A lo pisa).

### Estado anterior (2026-08-08) — histórico (parcialmente obsoleto, se mantiene como referencia)

- **Acceso Victoria → kalimete**: SOLO LECTURA vía túnel inverso systemd (`kalimete-tunnel`, 127.0.0.1:1111 en victoria) + `ro-shell-kalimete` (allowlist + git lectura + opencode run restringido). Agente `kalimete-ro` en victoria.
- **Voice UI**: ~~`https://victoria.local:8765`~~ → **ELIMINADA 2026-08-14** (servicio de voz no existe). TTS/STT eliminados. Espejado de idioma y troubleshooting de eco-voice quedan solo como referencia histórica para reconstrucción.
- **Acceso Victoria → jonas**: SOLO LECTURA con llave `id_jonas_ro` + wrapper `ro-shell-jonas` (allowlist argv, sin docker exec). Alias `jonas.ro` (10.0.0.20:1222).
- **Home Assistant (jonas)**: container en red ha-net (172.18.0.2:8123), proxy nginx `https://homeassistant.jonas.local:4430`. Token long-lived `victoria-ro` (10 años) en `~/.config/ha/ha_token` (victoria) + scripts `ha-api.sh`/`ha-snapshot.sh`. 137 entidades, sin cámaras aún.
- **PATRON PERMISOS opencode**: usar `"*": "deny"` al final — `"*": "ask"` ROMPE los patrones allow en opencode 1.18.15 (bug); sin "*" el default es allow (inseguro).

## Mantenimiento del mapa

- Cada vez que se cree/borre/renombre un agente → actualizar este archivo, `cloudflare-map/MAPA.md` y el repo `armada-sync` (agents/ + AGENTS.md).
- El cron de `~/armada-sync/sync.sh` (cada 5 min) despliega `agents/*.md` → `~/.config/opencode/agent/` — los cambios DEBEN hacerse en ambos lados o el sync los revierte.
- Cada vez que cambie el estado de la cuenta Cloudflare → actualizar `cloudflare-map/INVENTARIO.md` con la fecha de verificación.

## ⚠️ Regla anti-desborde de contexto (actualizado 2026-08-14)

El modelo `nvidia/Qwen3.6-35B-A3B-NVFP4` soporta **máximo 262,144 tokens** (262K) — `--max-model-len 262144` YA está aplicado en el contenedor vLLM. `opencode.jsonc` (kalimete: provider `alfredopro`; victoria: provider `vllm`) usa `limit.context: 240000` / `output: 20000` (total 260000 ≤ 262144, margen ~2K). **NUNCA volcar archivos grandes al chat** (find/grep sobre node_modules, logs completos): usar `head`, `grep -c`, `wc -l` o escribir a /tmp y leer con offset.

## Registro permanente de acciones (2026-08-12)

- Cada tarea de kalimete sobre infraestructura/servicios/proyectos DEBE dejar registro: este MAPA.md (estado) + commit en `~/armada-sync/` (auto cada 5 min vía cron).
- `plan`/`build` NO se registran (proyectos nuevos/pruebas fuera del ecosistema).
- Al cambiar algo en un servicio con agente → actualizar el .md del agente relacionado para que los modelos no adivinen (los subagentes leen su propio .md al delegarles).