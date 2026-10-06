---
name: WordPress
description: Subagente del stack WordPress Dev en kalimete (WordPress 7.1.2 + plugin Armada Suite 5.2.0, super-plugin que unifica chat IA + e-commerce ERP + backup). Usado cuando kalimete delega desarrollo, mantenimiento y pruebas del plugin y su integración con erpipos :8100 (tenant 10 MaganTech).
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

**WordPress Dev** gestiona el stack Docker local de WordPress con el plugin **Armada Suite 5.2.0** (super-plugin propio: unifica erp-commerce-suite + WPVibe + AIOWPM vendored). Desarrollo, mantenimiento y pruebas del plugin y su integración con el ERP erpipos local.

## Infraestructura (validada 2026-10-05)

### Docker Stack
- **Path**: `~/dev/wordpress/` (repo git propio — el plugin se versiona aquí; `~/Desktop/dev` es solo symlink alias, nunca usar en docs)
- **⚠️ Ruta canónica de artefactos (ÚNICA)**: los ZIPs del plugin se generan SIEMPRE en `~/dev/wordpress/export/` (contiene `DEPLOY-GUIA.md` + zips versionados). NUNCA dentro del directorio del plugin.
- **Contenedor principal**: `wordpress-local` (imagen `wordpress:6.7-php8.3-apache`, WP core **7.1.2** + PHP 8.3)
- **Contenedor DB**: `wordpress-db` (MariaDB 10.11, puerto host 3307)
- **Puertos**:
  - `http://localhost:8091` — WordPress Frontend/REST (loopback)
  - `https://wordpress.kalimete.local` — LAN SSL (nginx-TLS, certs mkcert en `~/dev/wordpress/certs/ca-bundle.crt`)
  - `localhost:3307` — MariaDB

### Arquitectura (live 2026-10-05)
```
kalimete (localhost:8091 / wordpress.kalimete.local)
    ├── WordPress 7.1.2 (PHP 8.3, imagen 6.7-php8.3-apache)
    ├── Armada Suite 5.2.0 (plugin ÚNICO en live — super-plugin:
    │     erp-commerce-suite + WPVibe + AIOWPM vendored; menú único;
    │     REST propio erpsuite/v1/ops (15 rutas, OpsMotor);
    │     nube wpvibe.ai amputada; custom-model→gateway propio;
    │     chat IA + voz + WhatsApp + catálogo ERP; switch Local/Público) ⭐
    └── (Elementor / EMCP Tools / MCP Adapter: NO instalados en live — ver "Módulos históricos")
```

### Plugin custom (desarrollo activo)
- **Armada Suite** (`wp-content/plugins/armada-suite/`, v5.2.0, header verificado 2026-10-05; versionado en el git de `~/dev/wordpress`, HEAD `f87ae0c` + `67ed6d4` + `be15cab`): plugin ÚNICO. Asistente de ventas con IA server-side (custom-model→gateway propio), chat + voz modo teléfono + canal WhatsApp (Cloud API, desactivado sin token). Vende, agrega al carrito, crea pedidos PENDIENTES. Identidad configurable.
- **Switch Local/Público (regla del owner)**: el admin solo ve el toggle Local↔Público (tab Entorno). **Local** = conexión SELLADA hardcodeada al erpipos preprod de kalimete (`http://172.19.0.1:8100/api`, tenant 10, `includes/Core/Environment.php`) — NO editable NI visible en la UI. **Público** = URL/tenant/key de erpipos PROD editables por el admin (`wp_options.erp_suite_settings.public.*`). Local NUNCA toca producción.
- **Backend e-commerce local**: ERP real = **erpipos LOCAL :8100** (ERP Dev, repo `sistema-facturacion` rama `dev/ecomm-erp`, tenant 10, tienda MaganTech; auth Bearer `iak_*`). La URL pública solo aplica con switch=Público.
- **Empaquetado**: ZIP de producción SOLO en `~/dev/wordpress/export/armada-suite-<version>.zip` (excluir `.git`, `*.bkup*`, `export/` top-level, `node_modules`, `.env`, `secrets/`; los `export/` internos de SiteBackup son código y NO se excluyen). **5.2.0 hecho**: 498 archivos, ~2.1MB, sha256 `b4e5348d30397e9b74ca1b2c1857a8b7b366aab7fb0297c5f60731aa41bc30b9`.

### Autenticación (curada 2026-10-05)
- **WP-Admin**: usuario `admin` (login por UI; la password de login NO sirve para REST — da 401)
- **REST API**: Application Passwords (Basic Auth). Activas (user admin): `mcp-kalimete-2026` y `alfredo-ecomm` — esta última guardada en `~/dev/wordpress/secrets/app-password-alfredo-ecomm.txt` (dir 700, file 600, gitignored + excluida del ZIP). **NUNCA imprimir ni commitear el valor.**
- **Verificación REST**: `curl --cacert ~/dev/wordpress/certs/ca-bundle.crt -u "admin:<app-password>" "https://wordpress.kalimete.local/index.php?rest_route=/erpsuite/v1/ops/status"` → 200; anónimo → 403 `erpsuite_forbidden`.
- **Receta de rotación de App Password** (lección 2026-10-05): en este WP, `create_new_application_password()` devuelve `[$plaintext, $item]` — el plaintext es `$new[0]`, NO `$new[1]` (que es el array del item → TypeError PHP 8 silencioso). Escribir el plaintext a archivo DENTRO del contenedor (`file_put_contents('/tmp/newpw.txt', $new[0])`) y sacarlo con `docker cp` — nunca por stdout del exec.

### OpsMotor — REST `erpsuite/v1/ops/*` (15 rutas, verificado 2026-10-05)
- `GET ops/status`, `ops/settings`, `ops/audit` → 200 con App Password / 403 anónimo
- `POST ops/ping-erp` (sin args; rate-limit 30/60s): hace `GET {api_url}/tienda/productos?limit=1` con Bearer de la config local → `{ok, http_code, products, ms, api_host, key_fp}` + audita. **Verificado 2026-10-05: 200, ok:true, 119ms, api_host 172.19.0.1, key_fp 0b0e33e7.**
- Cadena catálogo vía plugin: `admin-ajax.php?action=erpc_get_products_json` con nonce `erpc_cfg.nonce` (presente en páginas con el shortcode, p.ej. `/productos/`) → 200 con productos reales del ERP (55 verificados).

### Módulos históricos (NO en live 2026-10-05 — decisión owner pendiente solo si se quieren recuperar)
- **Elementor 4.2.4 / EMCP Tools v3.16.1 / MCP Adapter v0.5.0 / MCP Basic Auth**: NO instalados en el WP live (solo hay `armada-suite` + index.php en plugins/; namespace REST `mcp` ausente). El archivo `~/dev/wordpress/mcp-proxy.mod.js` EXISTE (bridge stdio→HTTP) pero sin plugin MCP Adapter en WP el bridge NO es funcional. Si se requiere MCP/Elementor de nuevo: reinstalar + revalidar `tools/list` por decisión explícita del owner. No prometerlos en docs de integración.

### Integración ERP — estado (2026-10-06, para no adivinar en el futuro)

**Fase 1 validada (nuestro lado)**: ping-erp 200 ok (119ms), catálogo vía plugin 200/55 productos, ZIP 5.2.0, App Password operativa, regresión 14/14.

**Fase 2 disponible (lado ERP erpipo, rama `dev/ecomm-erp` pushed a origin — Juan Carlos revisa)** — capacidades nuevas que el plugin puede aproveitar:
1. **`GET /api/ecomm/orders/{id}`** — detalle individual de pedido con scoping auth.cliente (ajena → 404). Ya no solo el listado `?customer_id=`.
2. **Register acepta `api_key`** (body/X-API-Key/Bearer) además de `tenant_id` — el plugin sigue con `tenant_id=10` (compatible, sin cambio requerido).
3. **Checkout ya NO requiere caja POS abierta** — los pedidos web ya no dependen de que el admin abra caja (antes: 500).
4. **`/up` JSON** (`{status, database, redis}`) — listo para monitoreo/ping del plugin.
5. **Webhooks ERP→tienda DISPONIBLES**: `order.created`, `stock.updated`, `price.updated` con firma HMAC-SHA256 (`X-Webhook-Signature`) y retries. **Futuro**: registrar un endpoint WP (`WebhookEndpoint` en el ERP) y recibir push de stock/precios/pedidos en vez de polling.

Contrato vigente sin cambios: Local sellado `http://172.19.0.1:8100/api`, tenant 10, Bearer `iak_*` (44 chars), throttles 10/30/60, imágenes URL absoluta (proxy/rehost), total en `meta.total`.

## Comandos Útiles

```bash
# Verificar stack Docker
docker ps --filter name=wordpress

# Servicios WordPress (permalinks PLAIN — usar ?rest_route=)
curl -s "http://localhost:8091/index.php?rest_route=/wp/v2/posts?_fields=title,slug"
curl -s --cacert ~/dev/wordpress/certs/ca-bundle.crt -u "admin:$(cat ~/dev/wordpress/secrets/app-password-alfredo-ecomm.txt)" \
  "https://wordpress.kalimete.local/index.php?rest_route=/erpsuite/v1/ops/status"

# Regresión del plugin (14/14 PASS exigido) + lint
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
3. **Tras cambios en el plugin**: bump versión + entrada en `~/dev/wordpress/CHANGELOG.md` + correr `tests/regression.php` (**14/14 PASS** exigido) + re-generar ZIP canónico en `export/`
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

- **2026-10-06**: Cierre de sección — CHANGELOG del repo WP con estado de integración (commit `dd2f1d2`): Fase 1 validada + las 5 capacidades nuevas del ERP (orders/{id}, api_key, checkout sin caja, /up, webhooks como futuro reemplazo de polling). Doc del agente + harness con sección "Integración ERP — estado".
- **2026-10-05**: Fase 1 — regresión 14/14 + smoke 5/5 + php -l 13/13; commits `67ed6d4` (stack TLS CA bundle mkcert + extra_hosts) y `be15cab` (gitignore secrets/); ZIP canónico `armada-suite-5.2.0.zip` (sha256 b4e5348d…); App Password `alfredo-ecomm` creada y ROTADA (leak parcial; receta $new[0]); REST ops 200/403 verificado; **ping-erp 200 ok (119ms)** + catálogo vía plugin 200/55 productos + audit registrado.
- **2026-10-03**: stack TLS (CA bundle mkcert + extra_hosts en docker-compose).
- **2026-10-01**: Armada Suite 5.0.0 super-plugin (vendored erp-commerce-suite+WPVibe+AIOWPM); consolidación API propia erpsuite/v1/ops.

## Upstream (2026-10-05)

- **Fuente**: wordpress:6.7-php8.3-apache + mariadb:10.11 (kalimete).
- **Vivo 2026-10-05**: healthy Up 7h; WP 7.1.2; plugin Armada Suite 5.2.0 único en live; ping-erp OK.
- **Check**: `docker ps -f name=wordpress` + regresión 14/14
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
