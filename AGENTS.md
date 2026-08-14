# Armada Network — Red de Agentes Sincronizados

## Visión General

**Armada** es una red de 4 máquinas interconectadas que comparten agentes opencode, skills, commands y documentación a través de un repositorio Git central (`github.com/warcold/armada-sync`, rama `master`).

## Topología de Red

| Host | IP | SSH | Usuario | GPU | Rol |
|------|-----|-----|---------|-----|------|
| **kalimete** | 10.0.0.106 | 1111 | warcold | — | Hub principal, PC de trabajo |
| **victoria** | 10.0.0.5 | 1666 | victoria | GB10 124GB | Asistente Victoria: GPU, LLM (vLLM + gateway), túnel Cloudflare, RDP headless |
| **jonas** | 10.0.0.20 | 1222 | jonas | — | NAS, Home Assistant |
| ~~victoria (vieja)~~ | ~~10.0.0.64~~ | — | — | — | ELIMINADA 2026-08-13: el host Ubuntu ya no existe — esa IP la usa el Windows de Alfredo (cliente RDP) |

## Conectividad SSH

| Origen | Destino | Comando |
|--------|---------|---------|
| kalimete → victoria | `ssh victoria.local` (= `ssh -p 1666 victoria@10.0.0.5`, llave `id_ed25519_kalimete` autorizada 2026-08-13) |
| kalimete → jonas | ⚠️ SSH ROTO (2026-08-12, llave no autorizada) |
| victoria → kalimete | `ssh -p 1111 warcold@10.0.0.106` |

## Sistema de Sincronización

### Repositorio Central
- **URL**: `ssh://git@github.com/warcold/armada-sync.git`
- **Rama**: `master`
- **Estructura**:
  ```
  armada-sync/
  ├── agents/          # .md de agentes opencode (→ agent/ local)
  ├── skills/          # directorios por skill (→ skill/ local)
  ├── commands/        # .md de commands opencode (→ command/ local)
  ├── configs/         # mapas e inventarios (→ ~/.config/opencode/*-map/)
  ├── daily-report/    # script del reporte diario (comando /reporte)
  ├── AGENTS.md        # Este archivo
  ├── MAPA.md          # Mapa maestro del ecosistema
  └── sync.sh          # Script de sync (hub/follower)
  ```

### Script sync.sh
Cada máquina ejecuta `sync.sh` cada 5 minutos vía cron. Arquitectura **Hub/Follower**:
- **kalimete (HUB)**: pull → collect (local→repo) → push al remoto.
- **victoria (FOLLOWER)**: pull → deploy (repo→local). Solo lectura.
- Collect y deploy son DESTRUCTIVOS: eliminan "agentes zombies" (archivos que existen en una máquina pero ya no en la fuente de verdad).

### Automatización
- **kalimete**: cron `*/5 * * * *` → sync.sh → push (hub único)
- **victoria**: cron `*/5 * * * *` → sync.sh → pull+deploy (solo lectura; deploy key `victoria-follower-readonly`, registrada 2026-08-13)
- **jonas**: *(sin cron de sync — acceso SSH roto, pendiente de arreglar)*

## Agentes por Máquina

### kalimete (hub)
- **kalimete** — Agente principal del ecosistema (CEREBRO CENTRAL, por defecto; ex-eco-cloudflare)
- **eco-accesos** — Modelo de acceso SSH (hidden)
- **eco-voice** — Servicio de voz de Victoria (hidden)
- **eco-cloudflare-dns** — DNS de las 3 zonas (hidden)
- **eco-cloudflare-security** — SSL, WAF, firewall, tokens (hidden)
- **eco-cloudflare-storage** — KV, D1, Queues (hidden)
- **eco-cloudflare-tunnels** — Túneles cloudflared (hidden)
- **eco-cloudflare-workers** — Workers/Pages (hidden)
- **plan / build** — Proyectos nuevos no-ecosistema (built-in)
- Retirados 2026-08-12: cloudflare, ecosistema, cf-* (5), eco-cloudflare (→ kalimete), jonas-ro, kalimete-ro, kalimete-ro-agent (ver `agents-retired-2026-08-12/`)
- Skill: **cloudflare** → `skill/cloudflare/SKILL.md`
- Command: **mapa**, **reporte** → `commands/`

### victoria (10.0.0.5)
- 9 agentes sincronizados desde kalimete (via hub/follower sync): kalimete + 7 eco-* + **docs-keeper**
- **docs-keeper** — agente local original (mantiene AGENTS.md de victoria-llm-gateway, ComfyUI, NemoClaw); añadido al repo 2026-08-13 (portable, sin model fijo)
- **Nota**: usa `default_agent: kalimete`, modelos locales vía vLLM (`http://127.0.0.1:8000/v1`, directo, sin key)
- Al ser follower, NO pusha al repo: deploy key `victoria-follower-readonly` (solo lectura)
- ⚠️ opencode.jsonc de victoria debe apuntar al stack nuevo — la victoria vieja (10.0.0.64) ya no existe

### jonas
- *(Sin agentes locales — sin cron de sync, SSH roto desde kalimete)*

## Servicios Principales

| Servicio | Puerto | Máquina | Estado |
|----------|--------|---------|--------|
| vLLM (Qwen3.6-35B-A3B-NVFP4) | 8000 | victoria | ✅ nemoclaw-vllm — util 0.5, 8 seqs, batched 16384 → KV 3.4M tok (13× conc. 262K). Límites cliente 240K+20K (2026-08-14) |
| victoria-llm-gateway | 8010 | victoria | ✅ systemd ACTIVE (auth por NOMBRE de key — `demo`; validado 2026-08-13). Panel /admin = SOLO LAN (victoria.local:8010/admin, 403 vía túnel) |
| OpenShell sandbox | 18789 | victoria | ⚠️ contenedor healthy, escucha :18789 loopback — SOLO victoria.local (NO en túnel, decisión 2026-08-13) |
| ComfyUI | 8188 | victoria | ❌ No corre — cuando corra: SOLO victoria.local (LAN), nunca túnel/dominio |
| Ollama | 11434 | victoria | ❌ No corre (verificado 2026-08-13) |
| Voice UI | 8765 | victoria | ⚠️ PENDIENTE migración (servicios de voz de la victoria vieja: victoria-voice, nginx TLS) |
| Home Assistant | 8123 | jonas | ✅ Container |
| RDP Headless | 3389 | victoria | ✅ gnome-remote-desktop (ARREGLADO 2026-08-13: credenciales victoria/vcolador + TLS self-signed + xrdp desactivado) |
| Túnel cloudflared | — | victoria | ✅ `victoria-armada` (ID d9abe241-…), 4 conexiones, ingress victoria.armada.do → :8010 (SÓLO API LLM con llaves; panel /admin 403 vía túnel) |

## Reglas de Operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NUNCA** compartir llaves privadas entre personas
3. **Siempre** verificar estado de servicios antes de asumir
4. **Sync automático** cada 5 minutos vía cron (hub/follower — solo kalimete push)
5. **Conflictos Git**: no ocurren (un solo writer: kalimete)
6. **Límites de contexto**: modelo Qwen3.6 max 163840 tokens. Todos los modelos usan `context: 158000` / `output: 24000` (margen 143920)
7. **GLM-5.2**: definido explícitamente con límites seguros (el catálogo opencode declara 1M pero el local max 163840)
