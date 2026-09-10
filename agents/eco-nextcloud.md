---
description: Subagente del proyecto Nextcloud (nextcloud.armada.do). Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue de Nextcloud y whiteboard. Corre en vps-preprod (Docker).
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco Nextcloud — Cloud Nextcloud

## Visión

Gestión del proyecto **Nextcloud** (`nextcloud.armada.do`) y su whiteboard.

## Infraestructura (vps-preprod)

| Contenedor | Descripción |
|---|---|
| `nextcloud-stack-nextcloud-1` | Nextcloud (fpm) |
| `nextcloud-stack-db-1` | Base de datos (mariadb:10.11) |
| `nextcloud-stack-redis-1` | Redis |
| `nextcloud-stack-cron-1` | Cron |
| `nextcloud-stack-caddy-1` | Reverse proxy (caddy:2) |
| `nextcloud-whiteboard-ws` | Whiteboard (WebSocket) |

## DNS

- nextcloud.armada.do → 154.53.35.102 (proxied)
- whiteboard.armada.do → 154.53.35.102 (proxied)
- whiteboard.nextcloud.armada.do → 154.53.35.102 (gris)

## SMTP

- Config OK y verificado (mail_smtpauthtype=LOGIN, envío de prueba 250 por mail.armada.do)

## OIDC / Authentik (SSO)

- App `user_oidc` configurada en Nextcloud con provider `authentik` (id 2).
- Provider OIDC en Authentik: `auth.armada.do/application/o/nextcloud/`.
- **Fix SSRF (Nextcloud 33)**: `allow_local_remote_servers = true` (boolean).
  - Causa: dentro del contenedor Nextcloud, `auth.armada.do` resuelve a `172.18.0.8` (IP interna del contenedor Caddy). Nextcloud 33 bloquea IPs privadas vía `DnsPinMiddleware`.
  - Comando: `docker exec nextcloud-stack-nextcloud-1 php occ config:system:set allow_local_remote_servers --value=true --type=boolean`
- Flujo verificado: `/apps/user_oidc/login/2` → **303** a `auth.armada.do/application/o/authorize/...` (PKCE S256).
- Root `/` → **302** a `/index.php/login` (página de login con botón SSO).
- Listar providers: `docker exec nextcloud-stack-nextcloud-1 php occ user_oidc:providers` (NOTA: no existe `user_oidc:provider:list`).

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **Siempre** verificar estado de los contenedores antes de asumir
3. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio