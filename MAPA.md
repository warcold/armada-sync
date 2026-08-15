# 🗺️ MAPA DE AGENTES — Ecosistema Armada (red local + servicios)

> **Para qué es esto**: mapa maestro del ecosistema local de Alfredo Armada. **kalimete** es el CEREBRO CENTRAL que coordina TODO.
>
> **Regla de oro**: el agente principal (primary) NO ejecuta operaciones él mismo — delega a los subagentes según la tabla. Los subagentes ejecutan, el principal coordina y verifica.

---

## Red local Armada (LAN 10.0.0.0/24)

| Host | IP | SSH | Usuario local | Rol |
|---|---|---|---|---|
| **kalimete** | 10.0.0.106 | puerto 1111 | `warcold` | Máquina de trabajo de Alfredo (esta) |
| **jonas** | 10.0.0.20 | puerto 1222 | `jonas` | NAS / servidor de respaldo |

- DNS local: mDNS/avahi (`.local`). Resolven `kalimete.local`, `jonas.local`.
- La IP 10.0.0.64 es del Windows de Alfredo (cliente RDP `WARCOLD`).
- No existen máquinas follower — kalimete es el único HUB.

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
| **kalimete** | primary | ✅ | CEREBRO CENTRAL: red, accesos, Cloudflare, documentación, reporte diario. Conoce TODO el sistema neurológico | — (es el principal, por defecto) |
| **plan** | primary (built-in) | ✅ | Planificar proyectos nuevos sin tocar código (edit denegado) | proyectos no-ecosistema |
| **build** | primary (built-in) | ✅ | Implementar código en proyectos nuevos | proyectos no-ecosistema |
| **eco-accesos** | subagent (hidden) | ❌ | Modelo de acceso SSH: usuarios, llaves, auditoría de intentos denegados, revocar/agregar llaves | "quién tiene acceso a X", "revoca la llave de...", "revisa el log de intentos", "crea un usuario ro" |
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
- **kalimete-ro**, **kalimete-ro-agent**, **jonas-ro**: retirados junto con la arquitectura de follower — ya no existen máquinas follower. Solo quedan en historial git.

## Estado validado — 2026-08-14

### kalimete (10.0.0.106)
- **Docker (7)**: tapmap-m1, woodly-woodly-1 (:5173), micaserogou-frontend-1 (⚠️ restarting loop, pendiente), kalimete (nginx :8080), taohemps-frontend-1 (:8076), taohemps-backend-1 (:3001), petsuite-petsuite-1 (:5176/:4003)
- **Systemd propios**: ssh, nginx, docker, containerd, cron, sddm, anydesk, waydroid-container, kalimete-tunnel (active ✓), publish-kalimete-subdomains, dnsmasq
- **Repos**: dev/ops, dev/infra, ~/.axiom, armada-sync
- **Cron**: check-jobs, RSS digest (revisar), armada-sync cada 5 min (**DUPLICADO: 2 líneas idénticas — limpiar**), y entradas históricas (feed-cron, people-migration, opencode-agents con ruta rota `dev/repos/opencode-agents/`)

### jonas (10.0.0.20)
- ⚠️ **SSH DESDE KALIMETE ROTO (2026-08-12, re-verificado 2026-08-14)**: `id_ed25519_kalimete` rechazada (Permission denied). El mapa dice NAS + HA (:8123) + backups (/srv/backups/) + updater DDNS. PENDIENTE: re-autorizar llave con eco-accesos.

### Estado anterior (2026-08-08) — histórico (parcialmente obsoleto)

- **Acceso a kalimete desde máquina remota** (retirado): túnel inverso systemd `kalimete-tunnel` + `ro-shell-kalimete`. Agente `kalimete-ro` retirado junto con la arquitectura de follower.
- **Home Assistant (jonas)**: container en red ha-net (172.18.0.2:8123), proxy nginx `https://homeassistant.jonas.local:4430`. 137 entidades, sin cámaras aún.
- **PATRON PERMISOS opencode**: usar `"*": "deny"` al final — `"*": "ask"` ROMPE los patrones allow en opencode 1.18.15 (bug); sin "*" el default es allow (inseguro).

## Mantenimiento del mapa

- Cada vez que se cree/borre/renombre un agente → actualizar este archivo, `cloudflare-map/MAPA.md` y el repo `armada-sync` (agents/ + AGENTS.md).
- El cron de `~/armada-sync/sync.sh` (cada 5 min) despliega `agents/*.md` → `~/.config/opencode/agent/` — los cambios DEBEN hacerse en ambos lados o el sync los revierte.
- Cada vez que cambie el estado de la cuenta Cloudflare → actualizar `cloudflare-map/INVENTARIO.md` con la fecha de verificación.

## ⚠️ Regla anti-desborde de contexto (actualizado 2026-08-14)

El modelo `nvidia/Qwen3.6-35B-A3B-NVFP4` soporta **máximo 262,144 tokens** (262K). opencode.jsonc (kalimete: provider configurado) usa `limit.context: 240000` / `output: 20000` (total 260000 ≤ 262144, margen ~2K). **NUNCA volcar archivos grandes al chat** (find/grep sobre node_modules, logs completos): usar `head`, `grep -c`, `wc -l` o escribir a /tmp y leer con offset.

## Registro permanente de acciones (2026-08-12)

- Cada tarea de kalimete sobre infraestructura/servicios/proyectos DEBE dejar registro: este MAPA.md (estado) + commit en `~/armada-sync/` (auto cada 5 min vía cron).
- `plan`/`build` NO se registran (proyectos nuevos/pruebas fuera del ecosistema).
- Al cambiar algo en un servicio con agente → actualizar el .md del agente relacionado para que los modelos no adivinen (los subagentes leen su propio .md al delegarles).
