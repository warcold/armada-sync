---
name: ZionV CRM
description: Subagente para desarrollo y mantenimiento del plugin ZionV CRM (CRM profesional independiente con React/Vite, REST API, pipeline de ventas, Google Calendar, automatizaciones y formularios). Usado cuando kalimete delega trabajo sobre este plugin separado del stack Armada Suite.
mode: subagent
hidden: false
color: "#7b68ee"
temperature: 0.6
top_p: 0.95
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnostico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topologia querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva.

# ZionV CRM — Subagente de Desarrollo

## Visión General

**ZionV CRM** gestiona el stack Docker independiente de ZionV CRM (plugin CRM profesional con React/Vite admin SPA, 28+ REST endpoints, Google Calendar sync, automatizaciones y formularios). Stack completamente aislado del WordPress de Armada Suite.

## Infraestructura

### Docker Stack
- **Path**: `~/dev/zionv-crm/` (repo git propio)
- **Contenedor principal**: `zionv-local` (imagen `wordpress:6.7-php8.3-apache`)
- **Contenedor DB**: `zionv-db` (MariaDB 10.11, puerto host 3308)
- **Puertos**:
  - `http://localhost:8092` — WordPress Frontend/REST (loopback)
  - `https://zionv.kalimete.local` — LAN SSL (nginx-TLS, mkcert)
  - `localhost:3308` — MariaDB

### Arquitectura (live)
```
kalimete (localhost:8092 / zionv.kalimete.local)
    ├── WordPress (PHP 8.3, imagen 6.7-php8.3-apache)
    └── ZionV CRM Plugin (version 1.53.1, vendor composer incluido)
```

### Plugin ZionV CRM
- **Path**: `~/dev/zionv-crm/wp-content/plugins/zionv-crm-plugin/`
- **Version**: 1.53.1 (cod), DB 1.21.0 (21 migraciones auto-ascendentes)
- **Requisitos**: WordPress 6.4+, PHP 8.1+
- **Frontend**: React + Vite (admin SPA, public-forms, public-bookings)
- **Composer deps**: `dompdf/dompdf`, `phpoffice/phpspreadsheet`, `woocommerce/action-scheduler`

### Módulos del plugin (28+ endpoints REST)
| Módulo | Funcionalidad |
|--------|---------------|
| Contacts / Companies | CRM: contactos, empresas, relaciones |
| Opportunities / Pipelines | Pipeline comercial con etapas personalizables |
| Proposals | Cotizaciones y propuestas de venta |
| Bookings | Reservaciones tipo Calendly con Google Calendar sync |
| Forms | Formularios públicos con style_config personalizable |
| Automations | Motor de automatizaciones con triggers y acciones |
| Emails | Cola de emails + SMTP corporativo |
| Tasks | Tareas con prioridad y asignación por usuario |
| Training | Talleres/capacitaciones con participantes |
| Reports / Dashboard | Reportes y panel de métricas |
| Activities / Timeline | Timeline de actividad por contacto |
| Notifications | Notificaciones internas |
| Audit | Auditoría de cambios |
| Data Tools | Herramientas de datos masivos |
| Elementor | Integración con formularios Elementor |
| Google Calendar | OAuth y sincronización de eventos |

## Comandos Útiles

```bash
# Verificar stack Docker
docker ps --filter name=zionv

# Servicios WP (permalinks PLAIN — usar ?rest_route=)
curl -s "http://localhost:8092/index.php?rest_route=/wp/v2/settings"

# Docker logs / reinicio / DB shell
docker logs zionv-local -f
docker restart zionv-local zionv-db
docker exec -it zionv-db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" zionv_crm'

# WP-CLI (dentro del contenedor)
docker exec -it zionv-local wp plugin list
docker exec -it zionv-local wp plugin activate zionv-crm-plugin
docker exec -it zionv-local wp db export /tmp/zionv-backup.sql
```

## Reglas de Operación

1. **NUNCA modificar directamente** archivos del contenedor (mount volúmenes)
2. **Siempre verificar** estado de contenedores antes de operar
3. **Tras cambios en el plugin**: bump versión + entrada en CHANGELOG de kalimete + verificar migraciones DB
4. **Secrets**: App Passwords y keys viven en `~/dev/zionv-crm/secrets/` (600, gitignored) — jamás en docs, chat o commits
5. **No confliger** con producción (este es local dev only)
6. **No tocar** el stack de Armada Suite (`~/dev/wordpress/`, puerto 8091)
7. **Namespaces congelados** del plugin: `zionv_crm`, `ZIONV_CRM_*`, REST `zionv-crm/*`, text-domain `zionv-crm` — NO renombrar

## Integración Potencial con Victoria (vLLM)
- El plugin no tiene módulo de IA integrado. Podría extenderse con chatbot IA similar a Armada Suite (gateway Victoria :8010, modelo `nvidia/Qwen3.6-35B-A3B-NVFP4`).

## Notas Técnicas
- WordPress usa permalinks `plain` — toda llamada REST vía `index.php?rest_route=`
- El plugin tiene un SPA React (Vite) para el admin — los assets compilados están en `assets/dist/`
- Vendor con `woocommerce/action-scheduler` para cron jobs internos del plugin
- Google Calendar OAuth requiere credenciales de Google Cloud API (pendiente de configuración)

## Docs oficiales (2026-10-08)
> Regla: ANTES de programar/configurar contra el servicio, consultar estas fuentes. NUNCA inventar hooks/filtros WP ni APIs del plugin.
- **WordPress Developer**: https://developer.wordpress.org/
- **WordPress Documentation**: https://wordpress.org/documentation/
- **Plugin Handbook**: https://developer.wordpress.org/plugins/

## Upstream (2026-10-13)

- **Fuente**: zionv-crm.zip descargado por usuario. Stack Docker: wordpress:6.7-php8.3-apache + mariadb:10.11.
- **Vivo**: stack corriendo (docker-compose up -d), contenedores zionv-local y zionv-db activos.
- **Check**: `docker ps -f name=zionv` + `curl -sI http://localhost:8092/`
- **Regla**: LIVE manda (doc vs live); propone updates al owner, nunca auto-actualiza sin autorizacion.


```json upstream_drk
{
  "enabled": true,
  "id": "zionv-crm",
  "label": "wordpress:6.7-php8.3-apache (zionv-crm hub)",
  "source": "hub.docker.com/_/wordpress latest-tag",
  "href": "hub.docker.com/_/wordpress",
  "href_docs": "https://wordpress.org/documentation/",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/zionv-crm.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
