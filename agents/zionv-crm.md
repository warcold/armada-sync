---
name: ZionV CRM
description: Subagente para desarrollo y mantenimiento del plugin ZionV CRM (CRM profesional independiente con SPA React/Vite, 34+ REST controllers, pipeline de ventas, Google/MS365/Nextcloud Calendar, HubSpot, IA OpenAI-compat, automatizaciones y formularios). Usado cuando kalimete delega trabajo sobre este plugin separado del stack Armada Suite.
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

**ZionV CRM** gestiona el stack Docker independiente de ZionV CRM (plugin CRM profesional con admin SPA React/Vite, 34+ REST controllers / 123 rutas, pipeline Kanban, reservaciones tipo Calendly, formularios con lógica condicional, automatizaciones con Action Scheduler, SMTP con cola,Talleres, reportes CSV/Excel/PDF, auditoría, papelera y privacidad WP). Stack completamente aislado del WordPress de Armada Suite.

## Infraestructura

### Docker Stack
- **Path**: `~/dev/wordpress/zionv-crm/` (compose + nginx conf + certs + bin; NO es repo git — el git vive dentro del plugin)
- **Contenedor principal**: `zionv-local` (imagen `wordpress:6.7-php8.3-apache`)
- **Contenedor DB**: `zionv-db` (MariaDB 10.11, puerto host 3308)
- **Puertos**:
  - `http://localhost:8092` — WordPress Frontend/REST (loopback; NO canónico — WP_HOME apunta al host TLS, el acceso plano da 301 a `http://localhost/`)
  - `https://zionv.kalimete.local` — LAN SSL (nginx-TLS, mkcert) — **acceso canónico**
  - `localhost:3308` — MariaDB

### Arquitectura (live)
```
kalimete (https://zionv.kalimete.local / localhost:8092)
    ├── WordPress (PHP 8.3, imagen 6.7-php8.3-apache)
    └── ZionV CRM Plugin (version 1.56.3, DB 1.24.0, vendor composer incluido)
```

### Plugin ZionV CRM
- **Path**: `~/dev/wordpress/zionv-crm/wp-content/plugins/zionv-crm-plugin/` (repo git propio → **GitHub privado `warcold/zionv-crm`**, rama main)
- **Version**: 1.56.3 (cod), DB 1.24.0 (24 migraciones auto-ascendentes)
- **Requisitos**: WordPress 6.4+, PHP 8.1+, **permalinks PRETTY obligatorios** (`/%postname%/`) — la SPA vive en `/crm/` y las reservaciones en `/reservar/` vía rewrite rules; desde 1.54.0 el Activator los auto-activa si el sitio no tiene estructura (bug real 2026-10-13, resuelto)
- **Backend PHP (source COMPLETO)**: `src/` (~1.5M) — `Plugin.php` (service locator, 34 controllers), `Core/` (AppShell, Rewrite, Assets por manifest Vite, Settings, Roles/Capabilities, Encryption, Logger, AuditLogger, Privacy, MigrationRunner 24 versiones), `Modules/` (25 módulos), `Queue/` (Action Scheduler), `Rest/` (Account, Me). Sanitización por capa de Service (`sanitize_*` + `$wpdb->prepare()` + whitelist `orderby` + `Pagination::args(max 100)`); `permission_callback` en el 100% de rutas (públicas solo con nonce propio + RateLimiter + tokens hex).
- **Frontend (SOLO compilado, SIN source)**: React + Vite — únicamente `assets/dist/` (admin 874K + public-booking + public-form). No existe `*.tsx/*.ts`, `vite.config.*` ni `package.json` del frontend en ningún disco, ZIP ni historial git (verificado exhaustivo 2026-10-15). Los manifests `.vite/manifest.json` citan `src/booking/main.ts` y `src/form/main.ts` huérfanos; `admin/index.html` conserva fósiles `jo-crm-root`/`JoCrmConfig`/`localhost:8888` (el bundle live ya usa `zion-crm-root`/`ZionCrmConfig`). **Regla: `dist/` es artefacto — nunca editar a mano; todo cambio visual pasa por rebuild del futuro `admin-app/` o por `tools/patch-config-route.sh` (idempotente + `.orig`) como única vía temporal.**
- **Composer deps**: `dompdf/dompdf`, `phpoffice/phpspreadsheet`, `woocommerce/action-scheduler` (vendor/ incluido en git para deploy directo)
- **Integraciones** (todas configurables desde `/crm/configuracion/` —página unificada PHP desde 1.56.0— y diagnóstico en wp-admin → Zion CRM → Estado del sistema):
  - **SMTP** con presets (Gmail, Outlook/365, Zoho, Brevo, SendGrid, cPanel) + correo de prueba
  - **Google Calendar** (OAuth completo)
  - **Microsoft 365** (Azure AD OAuth + Microsoft Graph; desde 1.55.0 los eventos incluyen enlace **Teams** con `isOnlineMeeting`+`teamsForBusiness`, mismo permiso Calendars.ReadWrite)
  - **Nextcloud** (1.55.0: CalDAV RFC 4791 contra `remote.php/dav` con app password cifrada; UID determinista `zion-crm-booking-{id}@{host}`; alternativa self-hosted)
  - **HubSpot** (1.55.0: push CRM-to-CRM por hooks — contactos upsert por email, deals upsert por propiedad única `zioncrm_opportunity_id`; unidireccional, no bloqueante)
  - **Asistente IA OpenAI-compatible** (base_url + api_key cifrada + modelo; **configurado con Victoria PUBLIC `https://victoria.armada.do/v1`** — 212ms verificado; sirve OpenAI, vLLM, Ollama, LiteLLM, Groq; proxy server-side `ai/chat`; acción de automatización `ai_prompt` con variables y nota en timeline)
  - **Selector de calendario** (1.55.0: `calendar_provider` all|google|ms365|nextcloud|none — el admin elige con cuál/cuáles sincronizar)
- **Artefactos**: ZIP de producción en `~/dev/wordpress/zionv-crm/export/` (`zionv-crm-1.56.3.zip`, 7.3M, sha256 `e0b730d8…`, sin secrets ni `.bkup`); procedimiento remoto en `DEPLOY-GUIA.md` del repo (versión actual, 43 tablas, nota del parche, matiz `delete_data_on_uninstall=false` por defecto)

### Módulos del plugin (34+ controllers / 123 rutas REST)
| Módulo | Funcionalidad |
|--------|---------------|
| Contacts / Companies | CRM: contactos, empresas, relaciones, sedes, deduplicación, Lead→Contacto |
| Opportunities / Pipelines | Pipeline Kanban con etapas (Ganada/Perdida/Pospuesta con motivo), RD$/US$ |
| Proposals | Cotizaciones versionadas V1/V2/V3 con estados y adjuntos |
| Bookings | Reservaciones tipo Calendly + holds anti-doble-reserva + sync calendarios |
| Forms | Formularios públicos con lógica condicional, style_config, antispam |
| Automations | Motor triggers/condiciones/acciones + runs (incl. acción `ai_prompt`) |
| Emails | Cola SMTP con reintentos/backoff (Action Scheduler) |
| Tasks | Prioridad/estados, asignación con mail + campana, "Mis tareas" |
| Training | Talleres con cupo, lista de espera auto-promovida, recordatorios |
| Reports / Dashboard | 12 indicadores, gráficas, exportación CSV/Excel/PDF |
| Activities / Timeline | Timeline por contacto |
| Notifications | Campana + sección agrupada por fecha |
| Audit | Historial usuario/acción/fecha/IP paginado |
| DataTools | Export/import CSV validado + backup JSON completo |
| Taxonomy / Users | Taxonomías CRM + endpoints de usuarios |
| Elementor | Bridge con formularios Elementor |
| GoogleCalendar / Ms365 / Nextcloud | OAuth + sync (selector `calendar_provider`) |
| Hubspot | Push upsert contactos/deals |
| Ai | Proxy OpenAI-compat + settings cifradas |
| Settings | `settings/*` (incl. SMTP, calendario, HubSpot, IA) + logs del sistema |

## Comandos Útiles

```bash
# Verificar stack Docker
docker ps --filter name=zionv

# Servicios WP (permalinks PRETTY — REST también responde en /wp-json/)
curl -s "http://localhost:8092/wp-json/"          # vía loopback
curl -s "https://zionv.kalimete.local/wp-json/"    # vía TLS

# CRM SPA (sin sesión → 302 a login con redirect de vuelta)
curl -sk -o /dev/null -w "%{http_code}\n" "https://zionv.kalimete.local/crm/dashboard/"

# Docker logs / reinicio / DB shell
docker logs zionv-local -f
docker restart zionv-local zionv-db
docker exec -it zionv-db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" zionv_crm'

# WP-CLI (montado persistente desde bin/wp-cli.phar)
docker exec zionv-local wp plugin list --allow-root
docker exec zionv-local wp option get zion_crm_db_version --allow-root   # 1.24.0
docker exec zionv-local wp option get permalink_structure --allow-root   # /%postname%/

# Tablas live (43 esperadas) + parche del bundle + versión del plugin
docker exec zionv-db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" zionv_crm -e "SHOW TABLES LIKE \"%zion_crm_%\";"' | wc -l
grep -c "__zionCfgUnified" ~/dev/wordpress/zionv-crm/wp-content/plugins/zionv-crm-plugin/assets/dist/admin/assets/index-*.js

# Git del plugin (repo GitHub privado)
cd ~/dev/wordpress/zionv-crm/wp-content/plugins/zionv-crm-plugin && git log --oneline -5 && git status --short
```

## Reglas de Operación

1. **NUNCA modificar directamente** archivos del contenedor (mount volúmenes)
2. **Siempre verificar** estado de contenedores antes de operar
3. **Tras cambios en el plugin**: bump versión (header + define + readme Stable tag + changelogs) + entrada en CHANGELOG de kalimete + verificar migraciones DB + `php -l` + regenerar ZIP canónico en `export/` (comando de DEPLOY-GUIA.md, verificación: sin secrets ni `.bkup`)
4. **Secrets**: App Passwords y keys viven en `~/dev/wordpress/zionv-crm/secrets/` (600, gitignored) — jamás en docs, chat o commits
5. **No confliger** con producción (este es local dev only)
6. **No tocar** el stack de Armada Suite (`~/dev/wordpress/`, puerto 8091)
7. **Namespaces congelados** del plugin: `ZionCrm\` (PSR-4), constantes `ZIONV_CRM_*`/`ZION_CRM_*`, options `zion_crm_*`, tablas `{prefijo}zion_crm_*` (43 live), REST `zion-crm/v1` (+ `zion-crm/public/v1`), text-domains `zionv-crm`/`zion-crm`, rutas `/crm/` y `/reservar/` — NO renombrar
8. **`assets/dist/*` es artefacto**: nunca editar el bundle a mano ni con regex ad-hoc; la única vía temporal es `bash tools/patch-config-route.sh` (idempotente, deja `.orig`, verifica marker). Todo cambio visual definitivo pasa por el futuro `admin-app/` Vite + rebuild + verificación de manifests.
9. **Docs sincronizadas**: cada bump actualiza README (migraciones/controllers/módulos), DEPLOY-GUIA (versión/tablas/parche/uninstall), bootstrap (comentario de migración) y `readme.txt` + `CHANGELOG.md`.

## Integración con Victoria (vLLM) — LIVE

- **Asistente IA (módulo `Ai`)**: proxy server-side `ai/chat` contra endpoint OpenAI-compat configurado en `/crm/configuracion/` → **Victoria PUBLIC `https://victoria.armada.do/v1` (212ms, modelo `nvidia/Qwen3.6-35B-A3B-NVFP4`)**. Clave cifrada con `Encryption` (sodium), nunca al navegador. Acción de automatización `ai_prompt` con variables `{{contact_*}}` y nota opcional en timeline (skip seguro sin IA).
- **Deuda conocida**: `ai/chat` sin throttle server-side ni cap `max_tokens` (solo `MANAGE_SETTINGS`); aplicar transient por usuario (20/min) + `AuditLogger` antes de exponer a más roles.

## Notas Técnicas

- **Permalinks PRETTY obligatorios** (`/%postname%/`): la SPA del CRM vive en `/crm/` vía rewrite rules (`Rewrite.php` registra `^crm/?$` y `^crm/(.+)/?$`); el asistente público de reservaciones en `/reservar/{slug}/`. Con permalinks plain esas rutas no existen y el menú admin "Zion CRM" (que es solo un redirect a `dashboard_url()`) manda al home. Verificado 2026-10-13: fix aplicado con `wp option update permalink_structure '/%postname%/'` + `wp rewrite flush`.
- El menú lateral "Zion CRM" de wp-admin NO renderiza nada propio: `AppShell::maybe_redirect_admin_menu_page()` redirige a `/crm/dashboard/` en `admin_init` (no puede hacerlo en el callback de `add_menu_page` porque los headers ya salieron).
- **Frontend sin source (verdad 2026-10-15)**: el repo NUNCA tuvo React/TSX (import 1.53.1 ya entró solo con `dist/`; `git log --all -- "*.tsx"` vacío; 0 sourcemaps; manifests huérfanos). Por eso 1.56.0–1.56.1 tuvieron que "escribir sobre el compilado" (parche regex `"/configuracion":()=>…` → `window.__zionCfgUnified` + `location.reload()`). Funciona (marker presente live) pero es frágil ante cada rebuild: **la vía correcta es un nuevo `admin-app/` Vite (React+TS+Router con `basename=ZionCrmConfig.baseUrl`, `build.manifest=true`, `outDir=../assets/dist/admin`, entry `index.html`) que consuma `zion-crm/v1` con cookie+nonce y reimplemente `/configuracion` como ruta React de primera clase**; entonces se retira el branch `config_route_patched` de `AppShell`.
- **Lecciones 1.56.x**: `private` del padre invisible para subclass (null silencioso), `final` bloquea extends, parche de bundle = única vía client-side sin source; sidebar del CRM replicado en PHP (9 secciones, 26 items, SVG del bundle, filtrado por capability, colapso <860px) para que configurar no "saque" del CRM.
- Vendor con `woocommerce/action-scheduler` para cron jobs internos del plugin
- Google/Microsoft OAuth requieren HTTPS + URI exacta (`admin-post.php?action=zion_crm_{google,ms365}_callback`)
- **CA dual mkcert en kalimete** (lección 2026-10-13): existen DOS CAs — `~/.local/share/mkcert/rootCA.pem` (warcold, OU=warcold@victoria) y `/root/.local/share/mkcert/rootCA.pem` (root, OU=root@victoria). Los certs generados con `sudo mkcert` los firma el CA de ROOT. El bundle del contenedor (`certs/ca-bundle-full.crt`, 142 certs = 140 Debian + ambos mkcert) debe incluir AMBOS o curl interno falla con "unable to get local issuer certificate".
- **WP-CLI persistente**: `bin/wp-cli.phar` montado read-only en `/usr/local/bin/wp` (sobrevive recreaciones del contenedor; instalarlo con curl dentro del contenedor se pierde al recrear el volumen).
- `extra_hosts: zionv.kalimete.local:host-gateway` en el compose: el contenedor resuelve su propio host TLS (webhooks, OAuth callbacks, curl interno → HTTP 200 verificado).
- **Deudas backend priorizadas** (auditoría 2026-10-15): exports con `per_page=100000` y backup JSON en memoria → streaming/chunks; `system_logs` sin retención (prune 90d + excluir del backup); `RateLimiter::client_ip()` confía en `X-Forwarded-For` → `REMOTE_ADDR` primero; `MigrationRunner` sin lock (verificar idempotencia seeds 1.11.0/1.16.0); import CSV solo valida extensión; `AppShell` 1256 líneas con guías+CSS inline (extraer a asset versionado); `composer.json` declara phpunit sin `tests/` (crear `tests/php/` mínimo: sanitización, `require_capability`, orden/idempotencia migraciones, cobertura `Uninstaller` vs `SHOW TABLES`).

## Docs oficiales (2026-10-08)
> Regla: ANTES de programar/configurar contra el servicio, consultar estas fuentes. NUNCA inventar hooks/filtros WP ni APIs del plugin.
- **WordPress Developer**: https://developer.wordpress.org/
- **WordPress Documentation**: https://wordpress.org/documentation/
- **Plugin Handbook**: https://developer.wordpress.org/plugins/

## Upstream (2026-10-15)

- **Fuente**: zionv-crm.zip (import inicial) → desarrollo propio continuo. Stack Docker: wordpress:6.7-php8.3-apache + mariadb:10.11. Plugin versionado en **GitHub privado `warcold/zionv-crm`** (rama main; 1.56.3 `5d3efab` con Uninstaller completo + welcome notice → Configuración unificada + docs sin discrepancias).
- **Vivo 2026-10-15 (verificado)**: zionv-local Up 29h healthy + zionv-db Up 34h healthy; plugin **1.56.3** activo (welcome notice → `/crm/configuracion/` verificado); migraciones DB **1.24.0**; 43 tablas `zionv_zion_crm_*`; permalinks pretty; login e2e OK (302 → `/crm/dashboard/` → SPA 200); página **unificada `/crm/configuracion/`** con sidebar PHP + 6 tabs (POST guarda y redirige al CRM); bundle parcheado (marker `__zionCfgUnified` presente + `.orig`); página **Estado del sistema** con 5 tabs (Diagnóstico/Correo/Calendario unificada con selector+Google+MS365+Nextcloud/HubSpot/IA); REST `settings/nextcloud`, `settings/hubspot` (401 sin nonce = seguro); **IA configurada con Victoria PUBLIC `https://victoria.armada.do/v1` (212ms, modelo Qwen3.6)**; **acción `ai_prompt` e2e OK**; curl interno al host TLS 200 (CA dual).
- **Check**: `docker ps -f name=zionv` + `curl -sk -o /dev/null -w "%{http_code}" https://zionv.kalimete.local/crm/dashboard/` (302 esperado sin sesión) + `wp option get zion_crm_db_version` (1.24.0) + `grep -c __zionCfgUnified assets/dist/admin/assets/index-*.js` (1 esperado)
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
