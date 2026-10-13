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
- **Path**: `~/dev/zionv-crm/wp-content/plugins/zionv-crm-plugin/` (repo git propio → **GitHub privado `warcold/zionv-crm`**, rama main)
- **Version**: 1.54.0 (cod), DB 1.23.0 (23 migraciones auto-ascendentes)
- **Requisitos**: WordPress 6.4+, PHP 8.1+, **permalinks PRETTY obligatorios** (`/%postname%/`) — la SPA vive en `/crm/` y las reservaciones en `/reservar/` vía rewrite rules; desde 1.54.0 el Activator los auto-activa si el sitio no tiene estructura (bug real 2026-10-13, resuelto)
- **Frontend**: React + Vite (admin SPA, public-forms, public-bookings) — solo `assets/dist/` compilado (el source React/TSX NO está en el repo)
- **Composer deps**: `dompdf/dompdf`, `phpoffice/phpspreadsheet`, `woocommerce/action-scheduler` (vendor/ incluido en git para deploy directo)
- **Integraciones** (todas configurables desde wp-admin → Zion CRM → Estado del sistema, PHP clásico):
  - **SMTP** con presets (Gmail, Outlook/365, Zoho, Brevo, SendGrid, cPanel) + correo de prueba
  - **Google Calendar** (OAuth completo, existente)
  - **Microsoft 365** (NUEVO 1.54.0: Azure AD OAuth + Microsoft Graph, sync de reservaciones en paralelo a Google)
  - **Asistente IA OpenAI-compatible** (NUEVO 1.54.0: base_url + api_key cifrada + modelo; sirve OpenAI, vLLM — Victoria —, Ollama, LiteLLM, Groq; proxy server-side `ai/chat`; verificado contra Victoria: 29ms, chat real OK)
- **Artefactos**: ZIP de producción en `~/dev/zionv-crm/export/` (1.54.0: 7.3MB, 1917 archivos, sha256 `0fa5769c…`); procedimiento remoto en `DEPLOY-GUIA.md` del repo

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

# Servicios WP (permalinks PRETTY — REST también responde en /wp-json/)
curl -s "http://localhost:8092/wp-json/"          # vía loopback
curl -s "https://zionv.kalimete.local/wp-json/"    # vía TLS

# CRM SPA (sin sesión → 302 a login con redirect de vuelta)
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}" "https://zionv.kalimete.local/crm/dashboard/"

# Docker logs / reinicio / DB shell
docker logs zionv-local -f
docker restart zionv-local zionv-db
docker exec -it zionv-db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" zionv_crm'

# WP-CLI (montado persistente desde bin/wp-cli.phar)
docker exec zionv-local wp plugin list --allow-root
docker exec zionv-local wp option get zion_crm_db_version --allow-root   # 1.21.0
docker exec zionv-local wp option get permalink_structure --allow-root   # /%postname%/

# Git del plugin (repo GitHub privado)
cd ~/dev/zionv-crm/wp-content/plugins/zionv-crm-plugin && git log --oneline -5
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
- **Permalinks PRETTY obligatorios** (`/%postname%/`): la SPA del CRM vive en `/crm/` vía rewrite rules (`Rewrite.php` registra `^crm/?$` y `^crm/(.+)/?$`); el asistente público de reservaciones en `/reservar/{slug}/`. Con permalinks plain esas rutas no existen y el menú admin "Zion CRM" (que es solo un redirect a `dashboard_url()`) manda al home. Verificado 2026-10-13: fix aplicado con `wp option update permalink_structure '/%postname%/'` + `wp rewrite flush`.
- El menú lateral "Zion CRM" de wp-admin NO renderiza nada propio: `AppShell::maybe_redirect_admin_menu_page()` redirige a `/crm/dashboard/` en `admin_init` (no puede hacerlo en el callback de `add_menu_page` porque los headers ya salieron).
- El plugin tiene un SPA React (Vite) para el admin — los assets compilados están en `assets/dist/`
- Vendor con `woocommerce/action-scheduler` para cron jobs internos del plugin
- Google Calendar OAuth requiere credenciales de Google Cloud API (pendiente de configuración)
- **CA dual mkcert en kalimete** (lección 2026-10-13): existen DOS CAs — `~/.local/share/mkcert/rootCA.pem` (warcold, OU=warcold@victoria) y `/root/.local/share/mkcert/rootCA.pem` (root, OU=root@victoria). Los certs generados con `sudo mkcert` los firma el CA de ROOT. El bundle del contenedor (`certs/ca-bundle-full.crt`, 142 certs = 140 Debian + ambos mkcert) debe incluir AMBOS o curl interno falla con "unable to get local issuer certificate".
- **WP-CLI persistente**: `bin/wp-cli.phar` montado read-only en `/usr/local/bin/wp` (sobrevive recreaciones del contenedor; instalarlo con curl dentro del contenedor se pierde al recrear el volumen).
- `extra_hosts: zionv.kalimete.local:host-gateway` en el compose: el contenedor resuelve su propio host TLS (webhooks, OAuth callbacks, curl interno → HTTP 200 verificado).

## Docs oficiales (2026-10-08)
> Regla: ANTES de programar/configurar contra el servicio, consultar estas fuentes. NUNCA inventar hooks/filtros WP ni APIs del plugin.
- **WordPress Developer**: https://developer.wordpress.org/
- **WordPress Documentation**: https://wordpress.org/documentation/
- **Plugin Handbook**: https://developer.wordpress.org/plugins/

## Upstream (2026-10-13)

- **Fuente**: zionv-crm.zip (import inicial) → desarrollo propio continuo. Stack Docker: wordpress:6.7-php8.3-apache + mariadb:10.11. Plugin versionado en **GitHub privado `warcold/zionv-crm`** (rama main; 1.54.0 con módulos Ai + Ms365 + SystemStatusPage + DEPLOY-GUIA).
- **Vivo 2026-10-13 (verificado)**: zionv-local + zionv-db healthy; plugin **1.54.0** activo; migraciones DB **1.23.0** (tabla `ms365_connection` + columna `ms365_event_id` auto-aplicadas); permalinks pretty; login e2e OK (302 → `/crm/dashboard/` → SPA 200); página **Estado del sistema** renderiza con 5 tabs; REST nuevos `settings/ai`, `settings/ms365`, `ms365/status` (401 sin nonce = seguro); **IA e2e contra Victoria vLLM: test 29ms lista modelo Qwen3.6 + chat real responde**; curl interno al host TLS 200 (CA dual).
- **Check**: `docker ps -f name=zionv` + `curl -sI https://zionv.kalimete.local/crm/dashboard/` (302 esperado sin sesión)
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
