# Armada Network — Red de Agentes Sincronizados

## Visión General

**Armada** es un sistema de agentes opencode y documentación sincronizada a través de Git.
**Solo kalimete (hub) es máquina activa.** Victoria = servidor GPU/LLM; JONAS = fuera de servicio.

## Topología de Red

| Host | IP | SSH | Usuario | GPU | Rol | Estado |
|------|-----|-----|---------|-----|------|--------|
| **kalimete** | 10.0.0.106 | 1111 | warcold | — | Hub principal, PC de trabajo | ✅ activo |
| **victoria** | 10.0.0.5 | 1666 | warcold | GB10 GPU | Servidor GPU/LLM (vLLM + gateway) | ✅ activo |
| **jonas** | 10.0.0.20 | 1222 | jonas | — | NAS, backups (fuera de servicio) | 🔴 fuera servicio |
| Windows | 10.0.0.64 | RDP 3389 | — | — | Cliente RDP de Alfredo | — |

## Conectividad SSH

| Origen | Destino | Comando | Estado |
|--------|---------|---------|--------|
| kalimete → kalimete | ssh `kalimete` | llave: `id_ed25519_kalimete` | ✅ SSH 1111 |
| kalimete → victoria | `ssh victoria` | llave: `~/.ssh/id_ed25519_kalimete` (warcold) | ✅ SSH 1666, rbash |
| kalimete → jonas | ⚠️ SSH ROTO (2026-08-12+) | llave no autorizada | 🔴 sin acceso |

## Sistema de Sincronización

### Repositorio Central
- **URL**: `ssh://git@github.com/warcold/armada-sync.git`
- **Rama**: `master`
- **Estructura**:
  ```
  armada-sync/
  ├── agents/          # .md de agentes opencode (→ agent/ local por symlink)
  ├── skills/          # directorios por skill (→ skill/ local)
  ├── commands/        # .md de commands opencode (→ command/ local)
  ├── configs/         # mapas e inventarios (→ ~/.config/opencode/*-map/)
  ├── daily-report/    # script del reporte diario (comando /reporte)
  ├── AGENTS.md        # Este archivo
  ├── MAPA.md          # Mapa maestro del ecosistema
  ├── CHANGELOG.md     # Registro permanente de cambios
  └── sync.sh          # Script de sync (hub único)
  ```

### Script sync.sh
Cada máquina ejecuta `sync.sh` cada 5 min vía cron. Arquitectura **Hub Único**:
- **kalimete (HUB)**: pull → collect (local→repo) → push al remoto.
- Collect y deploy son DESTRUCTIVOS: eliminan "agentes zombies" (archivos locales que ya no existen en el repo).

### Automatización
- **kalimete**: cron `*/5 * * * *` sync.sh → push (hub único)
- **victoria**: sin cron de sync, sin opencode, sin repo cloned

## Agentes — Kalimete (hub)

| Agente | Estado | Modos | Visibilidad | Función |
|---|---|---|---|---|
| **kalimete.md** | ✅ | primary | ✅ TAB | CEREBRO CENTRAL: coordina delegación a subagentes |
| **eco-cloudflare-dns.md** | ✅ | subagent, hidden | ❌ TAB | DNS de 3 zonas Cloudflare (armada.do, micaserogou.com, taohemps.com) |
| **eco-cloudflare-security.md** | ✅ | subagent, hidden | ❌ TAB | SSL, WAF, firewall, tokens, certificados |
| **eco-cloudflare-storage.md** | ✅ | subagent, hidden | ❌ TAB | KV, D1, Queues (NO R2 descártado) |
| **eco-cloudflare-tunnels.md** | ✅ | subagent, hidden | ❌ TAB | Túneles cloudflared, ingress, hostnames |
| **eco-cloudflare-workers.md** | ✅ | subagent, hidden | ❌ TAB | Workers/Pages: deploy, rollback, tail, secrets |
| ~~eco-accesos.md~~ | 🔴 | — | ❌ | roto (symlink sin target, eliminado) |
| ~~eco-voice.md~~ | 🔴 | — | ❌ | roto (symlink sin target, servicio ELIMINADO) |
| **plan** | ✅ | built-in | ✅ TAB | Planificar proyectos nuevos |
| **build** | ✅ | built-in | ✅ TAB | Implementar código en proyectos nuevos |

- **Agente kalimete** = `~/.config/opencode/agent/kalimete.md` (symlink → armada-sync/agents/)
- **Subagentes** = symlinks → `armada-sync/agents/eco-*` (hidden en opencode TAB)
- **Commands**: mapa, reporte → `~/.config/opencode/command/` (archivos normales, no symlinks)
- **Skill**: cloudflare → `~/.config/opencode/skills/cloudflare/` (PLURAL)

## Victoria — Servidor GPU/LLM
#### ⚠️ Regla: victoria = SOLO LECTURA por defecto; escritura SOLO con autorización explícita del usuario
Acceso SSH con `warcold` (rbash) es SOLO lectura (monitorización). Existe acceso de escritura con `victoria@victoria.local:1666` (clave del usuario, 2026-08-30) que se usa ÚNICAMENTE cuando el usuario lo autoriza explícitamente. NUNCA escribir sin autorización. Siempre hacer backup (.bkup) antes de modificar.

- **Acceso SSH**:
  - Lectura: `warcold`, ssh 1666, llave `~/.ssh/id_ed25519_kalimete` (rbash)
  - Escritura (autorizado): `victoria`, ssh 1666, `sshpass -p '<clave>' ssh -l victoria victoria.local -p1666`
  - opencode en victoria: `/home/victoria/.opencode/bin/opencode` (node vía nvm v22.23.2)
- **Servicio principal**: vLLM `nvidia/Qwen3.6-35B-A3B-NVFP4` (GB10 GPU, max 262144 tokens)
  - Ejecuta como proceso standalone (no Docker) en :8000
  - Gateway LLM en :8010 (API keys, metering, proxy nginx en :443)
  - Túnel Cloudflare: victoria.armada.do → :8010
- **opencode config**: `/home/victoria/.config/opencode/opencode.jsonc` — 3 providers (vllm local :8010 con 2 variantes Qwen3.6, nvidia NIM con key propia, opencode built-in). 109 modelos, sin duplicados (2026-08-30)
- **No tiene repo synced**

## Jonas — NAS/Respaldo (fuera de servicio)

- Sin cron de sync, SSH rota desde kalimete (2026-08-12+)
- Roles: NAS, backups (/srv/backups/), DDNS updater (home.armada.do)
- Sin agentes locales, sin repo

## Servicios Principales

| Servicio | Puerto | Máquina | Estado |
|----------|--------|---------|--------|
| vLLM (Qwen3.6 35B) | :8000 | victoria | ✅ standalone |
| LLM Gateway | :8010 | victoria | ✅ systemd |
| nginx (TLS) | :443, :80 | victoria | ✅ mkcert (⚠️ nginx -t falla por permission key.pem) |
| Cloudflared | tunnel | victoria | ✅ healthy, victoria-armada |
| Home Assistant | 8123 | jonas | ⚠️ jonas fuera de servicio |
| RDP/vnc | :3389 | victoria | ✅ (⚠️ expuesto a 0.0.0.0) |

## Reglas de Operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NUNCA** compartir llaves privadas entre personas
3. **Siempre** verificar estado de servicios antes de asumir
4. **Sync automático** cada 5 minutos vía cron (hub único — solo kalimete push)
5. **Conflictos Git**: no ocurren (un solo writer: kalimete)
6. **Límites de contexto**: modelo Qwen3.6 max **262144** tokens. opencode.jsonc usa `context: 240000` / `output: 32000` (total 272000 — **excede el límite**, ajustar a 22144 max para output). NO usar 262144+32768.
7. **Skill cloudflare**: en el repo vive en `skills/` y se despliega a `~/.config/opencode/skills/` (PLURAL).
8. **Documentación**: siempre validar contra lo real, no asumir. Si algo está roto (symlink, servicio), documentarlo y no adivinar la causa.
9. **AGENTS.md global**: `~/.config/opencode/AGENTS.md` es un **symlink** → `~/armada-sync/AGENTS.md` (se carga automáticamente en todas las sesiones opencode según la doc oficial de Rules). No reemplazarlo por un archivo real — el symlink garantiza que el repo sea la fuente de verdad.
10. **Permisos de agentes** (patrón oficial opencode docs/agents): los subagentes eco-cloudflare-* tienen `edit: deny`, `write: deny`, `temperature: 0.1`, `steps: 15` — solo operan vía API (bash + webfetch), no modifican archivos. kalimete tiene `temperature: 0.2` y `permission.task` restringido a `eco-cloudflare-*` + `explore` (patrón orquestador de la doc: `"*": deny` + allow específicos).
