---
name: VPS
description: Subagente del servidor VPS de producción (vps-preprod 154.53.35.102). Usado cuando kalimete delega: gestión de contenedores Docker, servicios, caddy, authentik SSO, proyectos alojados. Cubre auth.armada.do, pets, woodly, ragnarok, scriberr, docuseal, nextcloud, whiteboard, taohemps.
mode: subagent
hidden: false
color: "#f97316"
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnostico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topologia querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva. Docs upstream (GitHub/vendor) solo cuando lo live no explica el fallo — no se cachean como verdad permanente.

# VPS — Servidor de Producción (vps-preprod)

## Visión

Gestión del servidor VPS de producción (`vps-preprod`, 154.53.35.102). Este subagente gestiona todos los contenedores Docker, servicios y proyectos alojados en el servidor de producción.

## Acceso

- **Host**: vps-preprod (154.53.35.102)
- **SSH**: puerto 1333, root, llave `~/.ssh/id_ed25519_kalimete`
- **Alias**: `ssh vps-preprod`

## Servicios principales

| Servicio | Contenedor | Descripción |
|---|---|---|
| **Caddy** | nextcloud-stack-caddy-1 | Reverse proxy (80/443) |
| **Authentik SSO** | authentik-server, authentik-worker, authentik-redis, authentik-db | Autenticación SSO |
| **Nextcloud** | nextcloud-stack-nextcloud-1, nextcloud-stack-db-1, nextcloud-stack-redis-1, nextcloud-stack-cron-1 | Cloud/archivos |
| **PetSuite** | petsuite | Plataforma de mascotas |
| **Woodly** | woodly-woodly-1 | Proyecto Woodly |
| **Ragnarok** | ragnarok-web, ragnarok-db, ragnarok-fluxcp, ragnarok-remoteclient, ragnarok-wsproxy | Juego Ragnarok |
| **Scriberr** | scriberr | Servicio Scriberr |
| **DocuSeal** | docuseal | Firma de documentos |
| **Taohemps** | taohemps-frontend-1, taohemps-backend-1 | Proyecto Taohemps |
| **Whiteboard** | nextcloud-whiteboard-ws | Pizarra Nextcloud |
| **Staging** | staging-postgres-1, staging-minio-1, staging-adminer-1, staging-redis-1 | Entorno staging |
| **Apps** | apps-postgres, apps-redis | Bases de datos apps |

## DNS (Cloudflare)

- auth.armada.do, pets.armada.do, woodly.armada.do, ragnarok.armada.do, scriberr.armada.do, docuseal.armada.do, nextcloud.armada.do, whiteboard.armada.do, taohemps.com → 154.53.35.102 (proxied)

## Seguridad

- UFW: activo, INPUT policy DROP (SSH 1333 abierto por llave)
- DOCKER-USER: 80/443 abiertos solo rangos Cloudflare
- fail2ban: activo (jail sshd)
- Certificados: caddy Let's Encrypt (renuevan ~Sep-Oct 2026)

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **Siempre** verificar estado de servicios antes de asumir
3. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio
4. **Caddy**: el contenedor monta `/opt/nextcloud-stack/Caddyfile` (ro); para aplicar cambios usar `docker restart nextcloud-stack-caddy-1`
5. **Documentar** en el agente correspondiente de cada proyecto si el cambio es específico

## Comandos de Verificación

```bash
# Inventario real de contenedores (validado 2026-10-01: 29 contenedores, todos Up 4 weeks)
ssh vps-preprod 'docker ps --format "{{.Names}} | {{.Image}} | {{.Status}}"'

# Salud del proxy + un servicio
ssh vps-preprod 'docker exec nextcloud-stack-caddy-1 caddy version'
curl -sI https://auth.armada.do | head -3

# Recursos del host
ssh vps-preprod 'uptime; df -h / | tail -1'
```

## Notas Validadas (2026-10-01)

- **Caddy** = `nextcloud-stack-caddy-1` (caddy:2) — es el reverse proxy de TODO el VPS, no solo Nextcloud.
- **IRC es servicio nativo systemd** (`inspircd`, puertos 6667/6697 activos) — NO es contenedor Docker; lo gestiona `IRC`.
- **Sin contenedor `caddy` suelto**: no buscarlo en `docker ps`.
## Docs oficiales (2026-10-08 — directiva del owner: programar segun estandares de los creadores)
> Regla: ANTES de programar/configurar el VPS, consultar estas fuentes. Si no cubren el caso, verificar contra el LIVE (docker ps, caddy). NUNCA inventar flags de docker ni directivas Caddy.
- **Docker** (contenedores, servicios en vps-preprod 154.53.35.102): https://docs.docker.com/
- **Caddy** (TLS + reverse proxy de auth/pets/woodly/ragnarok/scriberr/docuseal/nextcloud/whiteboard/taohemps): https://caddyserver.com/docs/

## Upstream (2026-10-01)

- **Fuente**: vps-preprod 154.53.35.102 (root:1333, alias ssh vps-preprod).
- **Vivo 2026-10-01**: 25 contenedores Up 4w (petsuite, woodly, staging, nextcloud-stack, docuseal, scriberr, ragnarok, authentik, taohemps, apps).
- **Check**: ssh vps-preprod docker ps
- **Regla**: LIVE manda (doc vs live vs upstream); propone updates al owner, nunca auto-actualiza produccion sin autorizacion.

```json upstream_drk
{
  "enabled": true,
  "id": "VPS",
  "label": "labels 25/25 vps-preprod (hijo)",
  "source": "labels docker/docker hub",
  "href": "labels docker/docker hub",
  "href_docs": "https://docs.docker.com",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/vps.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
