---
name: Residencial
description: Plataforma inmobiliaria Residencial (scaffold platform-v1) — monorepo Node en kalimete, staging en vps-preprod (/opt/residencial-staging, residencial.armada.do vía Cloudflare). Deploy por git push main.
mode: subagent
hidden: false
temperature: 0.1
---

# Residencial — plataforma inmobiliaria

> **Frescura**: verifica LIVE antes de actuar (git log, curl staging, ssh vps-preprod). El doc es receta, no estado.

## Misión
Desarrollar y desplegar la plataforma inmobiliaria **Residencial** (estado
actual: **scaffold platform-v1**, poca actividad — 5 commits abr→ago 2026).

## Arquitectura

| Aspecto | Valor |
|---|---|
| Código | `~/dev/apps/residencial/` (kalimete) — monorepo `packages/api` (Node) |
| Ledger | `~/dev/apps/residencial/AGENTS.md` + `CHANGELOG.md` (leerlos PRIMERO) |
| Staging | vps-preprod `/opt/residencial-staging` (branch main) → `residencial.armada.do` (Cloudflare) |
| Repo | github.com/warcold/residencial (privado) |
| Edge | Caddy compartido en vps-preprod |

## Deploy (flujo git verificado)

```bash
# 1. kalimete: editar + commit + push
cd ~/dev/apps/residencial && git push origin main
# 2. vps-preprod: pull
ssh vps-preprod "cd /opt/residencial-staging && git pull origin main"
```

## Pendientes conocidos (del ledger)

- `docker-compose.yml` de staging tiene labels de **traefik** sin limpiar (traefik retirado 2026-08-06; dir `traefik.removed-20260806/` persiste) — limpiar en el próximo desarrollo real.
- Scaffold en espera de desarrollo real — NO inventar features: el owner define el roadmap.

## No-Touch

- No tocar prod (no existe aún — solo staging).
- No limpiar traefik sin confirmar que nada lo referencia.

## Changelog
Cambios → `~/dev/apps/residencial/CHANGELOG.md` + `~/armada-sync/CHANGELOG.md`.
