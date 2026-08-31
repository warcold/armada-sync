---
description: Subagente del servidor VPS de producción (vps-preprod 154.53.35.102). Usado cuando kalimete delega: gestión de contenedores Docker, servicios, caddy, authentik SSO, proyectos alojados. Cubre auth.armada.do, pets, woodly, ragnarok, scriberr, docuseal, nextcloud, whiteboard, taohemps.
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco VPS — Servidor de Producción (vps-preprod)

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
| **Micaserogou** | micaserogou-frontend-1 | Proyecto Micaserogou |
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