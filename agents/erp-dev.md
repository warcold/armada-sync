---
description: Subagente del preprod ERP (erpipo-preprod dockerizado en kalimete). Usado cuando kalimete delega: desarrollo, mantenimiento, migraciones, despliegue del sistema de facturación erpipo. Corre dockerizado en kalimete: https://erp.kalimete.local (mirrors prod/erpipo dev-stack).
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Erp Dev — Preprod ERP (kalimete)

## Visión

Gestión del preprod dockerizado de erpipo en kalimete. Stack mirrors el dev-stack de producción (erpipos.armada.do:1888).

## Acceso

- **URL**: `https://erp.kalimete.local` (nginx TLS local)
- **phpMyAdmin**: `https://erp.kalimete.local/phpmyadmin`
- **Stack Docker**: `~/dev/erpipo-preprod/` (docker-compose.yml)
- **Código**: `~/dev/erpipo-preprod/code/sistema-facturacion/`

## Stack (docker-compose.yml)

| Servicio | Container | Puerto | Imagen |
|---|---|---|---|
| app | erpipo-preprod-app | :8101 (fpm) | erpipo-preprod (build) |
| nginx | erpipo-preprod-nginx | :8100 | nginx:1.25-alpine |
| db | erpipo-preprod-db | :3310 | mysql:8.0 |
| redis | erpipo-preprod-redis | :6390 | redis:7-alpine |
| queue | erpipo-preprod-queue | — | erpipo-preprod |
| scheduler | erpipo-preprod-scheduler | — | erpipo-preprod |
| phpmyadmin | erpipo-preprod-phpmyadmin | :8102 | phpmyadmin:latest |

## Configuración

- **User app**: 1000:1000 (mismo UID que warcold en kalimete)
- **DB**: facturacion_db / factura_dev / devpass123 (user creado al importar dump)
- **.env**: preprod.env (APP_URL=https://erp.kalimete.local, APP_DEBUG=true)
- **SSL**: mkcert (erp.kalimete.local.pem + -key.pem, expira 2028-12-18)

## Servicios

| Servicio | Puerto | Descripción |
|---|---|---|
| **Nginx proxy** | :8100 | Reverse proxy a app docker |
| **MySQL** | :3310 | Base de datos (mirrors prod) |
| **Redis** | :6390 | Cache + queue (mirrors prod) |
| **phpMyAdmin** | :8102 | Admin DB (local) |

## Workers

- **queue**: `php artisan queue:work --tries=3 --timeout=90 --sleep=3` (redis)
- **scheduler**: `php artisan schedule:work`

## Migraciones

- DB: `facturacion_db` con 601 migraciones (batch 145)
- Dump importado: `facturacion_db-20260919.sql` (528MB)
- Stack: Laravel 12.16, PHP 8.3-fpm, MySQL 8.0, Redis 7

## Reglas de operación

1. **NUNCA** modificar el dump original (`db.sql` en `/tmp/`)
2. **BACKUP** de configs antes de modificar (`.bkup-YYYYMMDD`)
3. **Siempre** verificar que el preprod funciona después de cambios (`curl -sk https://erp.kalimete.local/login`)
4. **Actualizar** docker-compose.yml si se agregan servicios o puertos
5. **Documentar** cambios en CHANGELOG.md tras cada modificación

## Comandos útiles

```sh
# Ver estado
cd ~/dev/erpipo-preprod && docker compose ps

# Logs app
docker logs --tail 50 erpipo-preprod-app

# Logs nginx docker
docker logs --tail 50 erpipo-preprod-nginx

# Acceder al container
docker exec -it erpipo-preprod-app bash

# Reiniciar stack
docker compose restart

# Recrear (si se cambió Dockerfile)
docker compose up -d --build

# Limpiar cache de Laravel
docker exec erpipo-preprod-app php artisan cache:clear && \
docker exec erpipo-preprod-app php artisan config:clear && \
docker exec erpipo-preprod-app php artisan view:clear && \
docker exec erpipo-preprod-app php artisan route:clear

# Importar nuevo dump
docker cp new.sql erpipo-preprod-db:/tmp/
docker exec erpipo-preprod-db bash -c "mysql -uroot -ppreprodroot123 facturacion_db < /tmp/new.sql"

# Backup manual
docker exec erpipo-preprod-db bash -c "mysqldump -uroot -ppreprodroot123 facturacion_db" > backup.sql

# Ver migraciones pendientes
docker exec erpipo-preprod-app php artisan migrate:status
```

## Permisos

- **storage/logs/** y **storage/framework/**: 775, owned by warcold:warcold (UID 1000)
- Si se crean archivos con root: root, cambiar ownership: `chown -R 1000:1000 storage/`

## Producción (vps-erpipo)

- Servidor de terceros: 147.93.6.112:1888 (SSH root)
- Hostname: erpipos, Ubuntu 24.04.4 LTS
- Servicios: nginx (80/443/8080, TLS Let's Encrypt), Docker (erpipos-dev), sshd :1888
- Stack prod: MySQL 8.0 nativo + PHP 8.3 nativo + nginx nativo
- Stack dev (ellos): 7 contenedores (app/nginx/queue/scheduler/db/redis/phpmyadmin)
- **Preprod en kalimete**: stack dockerizado igual que dev-stack de ellos, `erp.kalimete.local:8100`
