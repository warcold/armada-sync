# Armada Network — Red de Agentes Sincronizados

## Visión General

**Armada** es una red de máquinas interconectadas que comparten agentes opencode, skills, commands y documentación a través de un repositorio Git central (`github.com/warcold/armada-sync`, rama `master`).

## Topología de Red

| Host | IP | SSH | Usuario | GPU | Rol |
|------|-----|-----|---------|-----|------|
| **kalimete** | 10.0.0.106 | 1111 | warcold | — | Hub principal, PC de trabajo |
| **jonas** | 10.0.0.20 | 1222 | jonas | — | NAS, Home Assistant |

## Conectividad SSH

| Origen | Destino | Comando |
|--------|---------|---------|
| kalimete → jonas | ⚠️ SSH ROTO (2026-08-12, llave no autorizada) |

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
  └── sync.sh          # Script de sync (hub único)
  ```

### Script sync.sh
Cada máquina ejecuta `sync.sh` cada 5 minutos vía cron. Arquitectura **Hub Único**:
- **kalimete (HUB)**: pull → collect (local→repo) → push al remoto.
- Collect y deploy son DESTRUCTIVOS: eliminan "agentes zombies" (archivos que existen en una máquina pero ya no en la fuente de verdad).

### Automatización
- **kalimete**: cron `*/5 * * * *` → sync.sh → push (hub único)
- **jonas**: *(sin cron de sync — acceso SSH roto, pendiente de arreggar)*

## Agentes por Máquina

### kalimete (hub)
- **kalimete** — Agente principal del ecosistema (CEREBRO CENTRAL, por defecto; ex-eco-cloudflare)
- **eco-accesos** — Modelo de acceso SSH (hidden)
- **eco-cloudflare-dns** — DNS de las 3 zonas (hidden)
- **eco-cloudflare-security** — SSL, WAF, firewall, tokens (hidden)
- **eco-cloudflare-storage** — KV, D1, Queues (hidden)
- **eco-cloudflare-tunnels** — Túneles cloudflared (hidden)
- **eco-cloudflare-workers** — Workers/Pages (hidden)
- **plan / build** — Proyectos nuevos no-ecosistema (built-in)
- Retirados 2026-08-12: cloudflare, ecosistema, cf-* (5), eco-cloudflare (→ kalimete), jonas-ro, kalimete-ro, kalimete-ro-agent — **backup BORRADO 2026-08-14, solo quedan en historial git** (arquitectura de follower retirada, sin máquinas follower)
- Skill: **cloudflare** → `skills/cloudflare/SKILL.md` (en config local: `~/.config/opencode/skills/cloudflare/`)
- Command: **mapa**, **reporte** → `commands/`

### jonas
- *(Sin agentes locales — sin cron de sync, SSH roto desde kalimete)*

## Servicios Principales

| Servicio | Puerto | Máquina | Estado |
|----------|--------|---------|--------|
| Home Assistant | 8123 | jonas | ✅ Container |

## Reglas de Operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NUNCA** compartir llaves privadas entre personas
3. **Siempre** verificar estado de servicios antes de asumir
4. **Sync automático** cada 5 minutos vía cron (hub único — solo kalimete push)
5. **Conflictos Git**: no ocurren (un solo writer: kalimete)
6. **Límites de contexto**: modelo Qwen3.6 max **262144** tokens. Kalimete usan `context: 240000` / `output: 20000` (total 260000, margen ~2K). NO usar 262144+32768 (excede el límite → 400).
7. **Skill cloudflare**: en el repo vive en `skills/` y se despliega a `~/.config/opencode/skills/` (la carpeta `skill/` singular fue ELIMINADA 2026-08-14).
