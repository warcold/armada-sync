---
name: WordPress
description: Subagente del stack WordPress Dev en kalimete (WordPress 7.1.3 + plugin Armada Suite 5.3.2, super-plugin que unifica chat IA + e-commerce ERP + backup). Usado cuando kalimete delega desarrollo, mantenimiento y pruebas del plugin y su integración con erpipos :8100 (tenant 10 MaganTech).
mode: subagent
hidden: false
color: "#21759b"
temperature: 0.6
top_p: 0.95
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnostico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topologia querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva. Docs upstream (GitHub/vendor) solo cuando lo live no explica el fallo — no se cachean como verdad permanente.

# WordPress — Subagente de Desarrollo

## Visión General

**WordPress Dev** gestiona el stack Docker local de WordPress con el plugin **Armada Suite 5.3.2** (super-plugin propio: unifica erp-commerce-suite + WPVibe + AIOWPM vendored). Desarrollo, mantenimiento y pruebas del plugin y su integración con el ERP erpipos local.

## Infraestructura (validada 2026-10-13)

### Docker Stack
- **Path**: `~/dev/wordpress/` (repo git propio — el plugin se versiona aquí; `~/Desktop/dev` es solo symlink alias, nunca usar en docs)
- **⚠️ Ruta canónica de artefactos (ÚNICA)**: los ZIPs del plugin se generan SIEMPRE en `~/dev/wordpress/export/` (contiene `DEPLOY-GUIA.md` + zips versionados). NUNCA dentro del directorio del plugin.
- **Contenedor principal**: `wordpress-local` (imagen `wordpress:6.7-php8.3-apache`, WP core **7.1.3** + PHP 8.3)
- **Contenedor DB**: `wordpress-db` (MariaDB 10.11, puerto host 3307)
- **Puertos**:
  - `http://localhost:8091` — WordPress Frontend/REST (loopback)
  - `https://wordpress.kalimete.local` — LAN SSL (nginx-TLS, certs mkcert en `~/dev/wordpress/certs/ca-bundle.crt`)
  - `localhost:3307` — MariaDB

### Arquitectura (live 2026-10-13)
```
kalimete (localhost:8091 / wordpress.kalimete.local)
    ├── WordPress 7.1.3 (PHP 8.3, imagen 6.7-php8.3-apache)
    ├── Armada Suite 5.3.2 (plugin ÚNICO en live — super-plugin:
    │     erp-commerce-suite + WPVibe + AIOWPM vendored; menú único;
    │     REST propio erpsuite/v1/ops (15 rutas, OpsMotor);
    │     nube wpvibe.ai amputada; custom-model→gateway propio;
    │     chat IA + voz + WhatsApp + catálogo ERP; switch Local/Público) ⭐
    └── (Elementor / EMCP Tools / MCP Adapter: NO instalados en live — ver "Módulos históricos")
```

### Plugin custom (desarrollo activo)
- **Armada Suite** (`wp-content/plugins/armada-suite/`, v5.3.2, header verificado 2026-10-14; versionado en el git de `~/dev/wordpress`, HEAD `a838486`): plugin ÚNICO. Asistente de ventas con IA server-side (custom-model→gateway propio), chat + voz modo teléfono + canal WhatsApp (Cloud API, desactivado sin token). Vende, agrega al carrito, crea pedidos PENDIENTES. Identidad configurable.
- **Switch Local/Público (regla del owner)**: el admin solo ve el toggle Local↔Público (tab Entorno). **Local** = conexión SELLADA hardcodeada al erpipos preprod de kalimete (`http://172.19.0.1:8100/api`, tenant 10, `includes/Core/Environment.php`) — NO editable NI visible en la UI. **Público** = URL/tenant/key de erpipos PROD editables por el admin (`wp_options.erp_suite_settings.public.*`). Local NUNCA toca producción.
- **Backend e-commerce local**: ERP real = **erpipos LOCAL :8100** (ERP Dev, repo `sistema-facturacion` rama `dev/ecomm-erp`, tenant 10, tienda MaganTech; auth Bearer `iak_*`). La URL pública solo aplica con switch=Público.
- **Empaquetado**: ZIP de producción SOLO en `~/dev/wordpress/export/armada-suite-<version>.zip` (excluir `.git`, `*.bkup*`, `export/` top-level, `node_modules`, `.env`, `secrets/`; los `export/` internos de SiteBackup son código y NO se excluyen). **5.3.2 hecho (2026-10-14)**: 2.203.552 bytes, sha256 `d8952c61ccfdd60efbd2d714a8c1007fd41e177422fd3bb392500b91f630f3b3` — **fix empaquetado**: restaura `SiteBackup/storage/` (excluido por error en 5.3.1 por un comando ad-hoc; lista de archivos IDÉNTICA al 5.3.0). **Comando canónico de empaquetado versionado en `export/DEPLOY-GUIA.md`** — SIEMPRE usarlo, nunca ad-hoc; verificación obligatoria: `unzip -l | grep -i storage` (debe listar) + `unzip -l | grep -iE "\.env|secret"` (debe dar vacío). Histórico 5.3.1: 2.201.803 bytes, sha256 `d018a73b…` (gap storage/, mitigado por self-heal; NO regenerar — artefacto liberado).

### Autenticación (curada 2026-10-05)
- **WP-Admin**: usuario `admin` (login por UI; la password de login NO sirve para REST — da 401)
- **REST API**: Application Passwords (Basic Auth). Activas (user admin): `mcp-kalimete-2026` y `alfredo-ecomm` — esta última guardada en `~/dev/wordpress/secrets/app-password-alfredo-ecomm.txt` (dir 700, file 600, gitignored + excluida del ZIP). **NUNCA imprimir ni commitear el valor.**
- **Verificación REST**: `curl --cacert ~/dev/wordpress/certs/ca-bundle.crt -u "admin:<app-password>" "https://wordpress.kalimete.local/index.php?rest_route=/erpsuite/v1/ops/status"` → 200; anónimo → 403 `erpsuite_forbidden`.
- **Receta de rotación de App Password** (lección 2026-10-05): en este WP, `create_new_application_password()` devuelve `[$plaintext, $item]` — el plaintext es `$new[0]`, NO `$new[1]` (que es el array del item → TypeError PHP 8 silencioso). Escribir el plaintext a archivo DENTRO del contenedor (`file_put_contents('/tmp/newpw.txt', $new[0])`) y sacarlo con `docker cp` — nunca por stdout del exec.

### OpsMotor — REST `erpsuite/v1/ops/*` (15 rutas, verificado 2026-10-13)
- `GET ops/status`, `ops/settings`, `ops/audit` → 200 con App Password / 403 anónimo
- `POST ops/ping-erp` (sin args; rate-limit 30/60s): hace `GET {api_url}/tienda/productos?limit=1` con Bearer de la config local → `{ok, http_code, products, ms, api_host, key_fp}` + audita. **Verificado 2026-10-13: 200, ok:true, ~250-300ms (294/247/268/258 en 4 pings), api_host 172.19.0.1, key_fp 0b0e33e7 — causa ERP-side (overhead TLS/nginx; `/up` directo 132-162ms). Histórico 2026-10-05: 119ms.**
- Cadena catálogo vía plugin: `admin-ajax.php?action=erpc_get_products_json` con nonce `erpc_cfg.nonce` (presente en páginas con el shortcode, p.ej. `/productos/`) → 200 con productos reales del ERP (55 verificados).

### Módulos históricos (NO en live 2026-10-05 — decisión owner pendiente solo si se quieren recuperar)
- **Elementor 4.2.4 / EMCP Tools v3.16.1 / MCP Adapter v0.5.0 / MCP Basic Auth**: NO instalados en el WP live (solo hay `armada-suite` + index.php en plugins/; namespace REST `mcp` ausente). El archivo `~/dev/wordpress/mcp-proxy.mod.js` EXISTE (bridge stdio→HTTP) pero sin plugin MCP Adapter en WP el bridge NO es funcional. Si se requiere MCP/Elementor de nuevo: reinstalar + revalidar `tools/list` por decisión explícita del owner. No prometerlos en docs de integración.

### Integración ERP — estado (actualizada 2026-10-13, para no adivinar en el futuro)

**Fase 1 validada (nuestro lado)**: ping-erp 200 ok (119ms), catálogo vía plugin 200/55 productos, ZIP 5.2.0, App Password operativa, regresión 14/14.

**Fase 2 disponible (lado ERP erpipo, rama `dev/ecomm-erp` pushed a origin — Juan Carlos revisa)** — capacidades nuevas que el plugin **YA consume**:
1. **`GET /api/ecomm/orders/{id}`** — consumido por la tool `ver_pedido` del agente (C1b) vía `ApiClient::get_order()`.
2. **Register con `api_key`** — compatible, plugin sigue con `tenant_id=10`.
3. **Checkout sin caja** — verificado e2e (ventas de prueba).
4. **`/up` JSON** — monitoreo.
5. **Webhooks ERP→WP ACTIVOS en preprod** (C2): endpoint `http://wordpress-local/wp-json/erpsuite/v1/erp-webhook` dado de alta en `webhook_endpoints` (id=2, tenant 10, events order.created/stock.updated/price.updated). E2E verificado: checkout → deliveries sent/200 → WP invalida caché. Red docker compartida `erpipo-dev-network` (compose WP, con .bkup; WORDPRESS_DB_HOST cambiado a `wordpress-db:3306` porque `db` colisionaba con el db de erpipo).

**Fase 3 — estado 2026-10-13** (rama `dev/ecomm-erp` @`2306b64` pushed, esperando PR de Juan): **G6 corregido por nosotros** (`ff64301`: `notas ?? null`, fin `linea_negocio`, tipo enum, `almacen_id` default) y **live en preprod** — `ajusteInventario` ya responde; **G1-G4 implementados** (cancel order + 11 tests, CRUD webhooks por API, `invoice.issued`, `webhooks:retry-failed`); solo **G5** (teléfono/stock-sucursal/detalle) queda pendiente. Juan ya integró nuestra Fase 2/3 a main vía **PR #14** (2026-10-07) + su refactor `34bd716` + módulo renta `bd1a879` — todo ya mergeado en nuestro HEAD sin conflictos.

Contrato vigente sin cambios: Local sellado `http://172.19.0.1:8100/api`, tenant 10, Bearer `iak_*` (44 chars), throttles 10/30/60, imágenes URL absoluta (proxy/rehost), total en `meta.total`.

**Latencia (2026-10-13)**: curl crudo WP→ERP 246-301ms idéntico al plugin (keepalive sin efecto); `/up` directo 132-162ms; vía HTTPS nginx 490-1140ms — overhead TLS/nginx **esperado del entorno dev local**, no un bug (decisión owner 2026-10-13: no perseguir). Mailpit = **dev-only intencional** (catcher SMTP local; en producción el mail es real según main de Juan Carlos) — no investigar, no tocar.

**Deuda P3 (2026-10-13)**: espejo legacy `tenant.api_key` en sanitize — `AdminMenu.php:128-136`, `Environment.php:106-116`, `Main.php:175-179`, `LegacyConnectorAdmin.php:64-66`. NO eliminable desde WP hasta que el ERP lea solo `public.api_key` (dependencia cruzada con ERP Dev). **Decisión owner 2026-10-13**: mantener el espejo — el erp local se alimenta de main de Juan Carlos (no modificamos el contrato por nuestro lado); cerrar cuando main deje de leer `tenant.api_key`.

### Sistema de feature flags (Fase A, 2026-10-06)

8 flags en `erp_suite_settings[features]` (`erp_sync, catalog, checkout, ai_chat, puente_ia, remote_ops, backups, legacy_logs`, default ON) + tab noveno **Módulos** + clase `ArmadaSuite_Features::enabled()` (cache solo del valor guardado, padres siempre frescos + filtro `armada_suite_feature_enabled`). Gates duros (requires vendored, menús MenuUnifier, instanciación ERPC_*, shortcodes stub `''`, `ApiClient::request()` → WP_Error si ERP OFF, cron WA) + gates UX (tabs en pausa con aviso, assets/AJAX chat, AJAX tienda, widget). Caso guía soportado: WP solo-chat-IA sin ERP. **Self-heal verificado 2026-10-13**: live la key `features` está ausente en `erp_suite_settings` → defaults-ON por código (`Features.php:99-103`); SiteBackup auto-repara `storage/` (carpeta + 4 protecciones) vía `admin_init → setup_storage_folder()` (`class-ai1wm-main-controller.php:85-86`). Reglas de testeo CLI: requires a mano + `wp-admin/includes/template.php` (submit_button no existe en CLI); smokes con backup+restore de settings; regresión por ruta de contenedor (por stdin `__DIR__` no resuelve).

### Admin uniforme + rebrand (Fase B, 2026-10-06)

Las 6 superficies son familia ai1wm (verde #27ae60, radius 3px, bordes #dcdcde, español, cero marcas ajenas visibles, cero estilos inline): Panel restyle total (solo CSS), Puente IA rebrandeado (91+ strings → Armada/alfredo.pro, CSS pills negros → ai1wm), Registro IA + ERPC Logs (este último movido de Herramientas al menú Armada), Exportar/Importar/Respaldos + modales del controlador en español (129 strings). Congelado por regla: text-domains, slugs, option keys, REST `wpvibe/v1`, clases/funciones, cabeceras GPL.

### Agente mixto (Fase C, 2026-10-06)

Schema `erp_suite_settings['agente']` (modo mixto|erp_solo|local_solo, instrucciones_extra ≤2000, tono, 8 toggles tools, mensaje_sin_erp, base_negocio 6 campos, memoria turnos 4-20 + recordar_cliente) + UI en tab Asistente IA + `Guard` (secretos siguen bloqueados, `webhooks.*` NO expuesto). Prompt componible en `ChatEngine::system_prompt()` (PERSONALIDAD + 10 REGLAS intactas + CONOCIMIENTO_LOCAL + HERRAMIENTAS filtradas por modo/toggles/ecomm; test #4 las protege). Sin gate duro de ecomm (degrada a local). Tools nuevas: `ver_pedido` (token del contexto, ajena→"no la encontré en tu cuenta") y `leer_politicas` (6 slugs Activator + fallback base_negocio). Receptor webhooks `POST erpsuite/v1/erp-webhook` (HMAC body crudo + skew 5min + allowlist eventos + flush_cache; 401 firma mala, 400 sin headers, 503 sin ERP/secreto) + tarjeta en Avanzado (endpoint, secreto auto-generado 48ch, última entrega). Regresión 19/19. LLM verificado en modo local (Qwen vía victoria responde sin ERP).

## Comandos Útiles

```bash
# Verificar stack Docker
docker ps --filter name=wordpress

# Servicios WordPress (permalinks PLAIN — usar ?rest_route=)
curl -s "http://localhost:8091/index.php?rest_route=/wp/v2/posts?_fields=title,slug"
curl -s --cacert ~/dev/wordpress/certs/ca-bundle.crt -u "admin:$(cat ~/dev/wordpress/secrets/app-password-alfredo-ecomm.txt)" \
  "https://wordpress.kalimete.local/index.php?rest_route=/erpsuite/v1/ops/status"

# Regresión del plugin (19/19 PASS exigido) + lint
docker exec wordpress-local php /var/www/html/wp-content/plugins/armada-suite/tests/regression.php
docker exec wordpress-local php -l /var/www/html/wp-content/plugins/armada-suite/armada-suite.php

# Ping al ERP desde el plugin (usa config sellada Local)
curl -s --cacert ~/dev/wordpress/certs/ca-bundle.crt -u "admin:$(cat ~/dev/wordpress/secrets/app-password-alfredo-ecomm.txt)" \
  -X POST "https://wordpress.kalimete.local/index.php?rest_route=/erpsuite/v1/ops/ping-erp"

# Docker logs / reinicio / DB shell (creds DB en el compose, no en docs)
docker logs wordpress-local -f
docker restart wordpress-local wordpress-db
docker exec -it wordpress-db sh -c 'mysql -u root -p"$MYSQL_ROOT_PASSWORD" wordpress'
```

## Reglas de Operación

1. **NUNCA modificar directamente** archivos del contenedor (mount volúmenes)
2. **Siempre verificar** estado de contenedores antes de operar
3. **Tras cambios en el plugin**: bump versión + entrada en `~/dev/wordpress/CHANGELOG.md` + correr `tests/regression.php` (**19/19 PASS** exigido) + re-generar ZIP canónico en `export/`
4. **Secrets**: App Passwords y keys viven en `~/dev/wordpress/secrets/` (600, gitignored, fuera del ZIP) — jamás en docs, chat o commits
5. **No confliger** con producción (este es local dev only); switch Local NUNCA apunta a prod
6. **Namespace legacy congelado** (owner 2026-10-02): slug `erp-suite`, constantes `ERPSUITE_*`, options `erp_suite_*`/`erpc_*`, REST `erpsuite/v1`, shortcodes `erpc_*` — NO renombrar código (rompe DB/bookmarks/clientes REST)

## Integración con Victoria (vLLM)

- **Chatbot (Armada Suite)**: custom-model→gateway propio contra el LLM de victoria (LAN `http://10.0.0.5:8010/v1` o túnel `https://victoria.armada.do/v1`; key en wp_options, no en docs). Modelo `nvidia/Qwen3.6-35B-A3B-NVFP4`.

## Notas Técnicas

- WordPress usa permalinks `plain` — toda llamada REST vía `index.php?rest_route=` (pretty paths dan 404 vía nginx-TLS)
- El perfil del cliente vive en el ERP (`GET /ecomm/me`); WP solo aporta display_name/email como fallback
- `debug.log` ausente con logging desactivado = estado sano (0 FATALs, verificado 2026-10-05)
- Smoke admin: `erp-suite` main + tabs chatbot/entorno/proyectos → 200; tab vozwa → 302 intencional (redirect legacy a chatbot, fusionado 5.1.2)

## Cambios recientes

- **2026-10-14 (release 5.3.2, commit `a838486`)**: fix empaquetado — el ZIP 5.3.1 excluyó `SiteBackup/storage/` por un comando ad-hoc (los archivos SÍ existían en disco; diff 5.3.0 vs 5.3.1 = exactamente storage/, 500→495 entradas). Bump 5.3.1→5.3.2 (header+define+readme), CHANGELOG, DEPLOY-GUIA con **comando canónico de empaquetado** (cura la causa raíz). ZIP `export/armada-suite-5.3.2.zip` (2.203.552 bytes, sha256 `d8952c61…`, storage/ incluido, lista idéntica al 5.3.0, sin secrets). Regresión 19/19 post-bump. ZIP 5.3.1 intacto (no regenerado).
- **2026-10-13 (housekeeping, commit `040682a`, sin release)**: restaurados `SiteBackup/storage/.htaccess` + `web.config` (borrados sin commit desde oct-09; verificados en disco + contenedor vía bind-mount); regresión **19/19 PASS**; self-heal confirmado (key `features` ausente → defaults-ON; SiteBackup auto-repara storage/); ZIP 5.3.1 verificado (2.201.803 bytes, sha256 `d018a73b…`, gap storage/ documentado); deuda P3 `tenant.api_key` localizada (4 archivos, bloqueada por ERP); latencia ping-erp diagnosticada ERP-side (~250-300ms; `/up` 132-162ms; mailpit 7.41% CPU reportado a ERP Dev); docs agente + harness sincronizados.
- **2026-10-08 (release 5.3.1, commit `819c7e1`)**: simplificación admin — LLM unificado, tab Negocio, Asistente IA en 3 forms, MCP→Estado del sistema, labels claros; deuda P3 marcada (espejo `tenant.api_key`); ZIP `export/armada-suite-5.3.1.zip` (2.201.803 bytes, sha256 `d018a73b9153d8bde9000e66910496c26e5bb097f3d5f9fb9dbeee4e3f949603`).
- **2026-10-06 (release 5.3.0, commit `c084cdb`)**: bump versión (header+define+readme Stable tag) + ZIP canónico `export/armada-suite-5.3.0.zip` (2.198.973 bytes, sha256 `6fbf47f8d03d5cdf6238e01efba9feafefb07511a263cad0b21919b9764099fc`; sin `.bkup`, sin secrets) + entrada CHANGELOG + DEPLOY-GUIA al día. Regresión 19/19.
- **2026-10-06 (Fases A+B+C, 13 commits)**: flags (`f0d1572`, `d51aed4`, `81c2ea5`), rebrand (`52aa796`, `084c0a6`, `eee8dca`, `ef0642f`, `e55ed39`, `fd2cff0`), agente (`2294e58`, `79ed47d`, `b289ba1`). Regresión 19/19. Webhooks e2e OK. Red compartida erpipo-dev-network (compose + WORDPRESS_DB_HOST=`wordpress-db:3306`).
- **2026-10-06**: Cierre de sección — CHANGELOG del repo WP con estado de integración (commit `dd2f1d2`): Fase 1 validada + las 5 capacidades nuevas del ERP (orders/{id}, api_key, checkout sin caja, /up, webhooks como futuro reemplazo de polling). Doc del agente + harness con sección "Integración ERP — estado".
- **2026-10-05**: Fase 1 — regresión 14/14 + smoke 5/5 + php -l 13/13; commits `67ed6d4` (stack TLS CA bundle mkcert + extra_hosts) y `be15cab` (gitignore secrets/); ZIP canónico `armada-suite-5.2.0.zip` (sha256 b4e5348d…); App Password `alfredo-ecomm` creada y ROTADA (leak parcial; receta $new[0]); REST ops 200/403 verificado; **ping-erp 200 ok (119ms)** + catálogo vía plugin 200/55 productos + audit registrado.
- **2026-10-03**: stack TLS (CA bundle mkcert + extra_hosts en docker-compose).
- **2026-10-01**: Armada Suite 5.0.0 super-plugin (vendored erp-commerce-suite+WPVibe+AIOWPM); consolidación API propia erpsuite/v1/ops.

## Docs oficiales (2026-10-08 — directiva del owner: programar segun estandares de los creadores)
> Regla: ANTES de programar/configurar WordPress o el plugin, consultar estas fuentes. Si no cubren el caso, verificar contra el LIVE (kalimete dev). NUNCA inventar hooks/filtros WP ni APIs del plugin.
- **WordPress Developer** (WP 7.1.3, APIs, Armada Suite 5.3.1, integracion erpipos :8100): https://developer.wordpress.org/
- **WordPress Documentation** (guia del stack): https://wordpress.org/documentation/
- **Plugin Handbook** (super-plugin: chat IA + e-commerce ERP + backup): https://developer.wordpress.org/plugins/

## Upstream (2026-10-13)

- **Fuente**: wordpress:6.7-php8.3-apache + mariadb:10.11 (kalimete).
- **Vivo 2026-10-14**: healthy Up 2d; WP 7.1.3; plugin Armada Suite 5.3.2 único en live; ping-erp OK (~250-300ms, overhead TLS del dev local — esperado).
- **Check**: `docker ps -f name=wordpress` + regresión 19/19
- **Regla**: LIVE manda (doc vs live vs upstream); propone updates al owner, nunca auto-actualiza produccion sin autorizacion.


```json upstream_drk
{
  "enabled": true,
  "id": "wordpress-dev",
  "label": "wordpress:6.7-php8.3-apache (hub tag)",
  "source": "hub.docker.com/_/wordpress latest-tag",
  "href": "hub.docker.com/_/wordpress",
  "href_docs": "https://wordpress.org/documentation/",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/wordpress-dev.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
