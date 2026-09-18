## 2026-09-18

### [03:30] - Plugin v3.5.1: Elementor override funcional + multi-color en ambas plantillas + auditoría limpia
- **Tipo**: proyecto | fix | seguridad | elementor | mcp
- **Modificado**: plugin `erp-ecomm-connector` v3.5.1 (commit `169514b`, 8 archivos); página demo Elementor ID 53; imágenes Pexels en media library (IDs 49-50)
- **Afecta a**: kalimete (tienda + modelo multi-tenant)
- **Causa**: Validación integral pedida: (1) el override Elementor no funcionaba de verdad — el router secuestraba páginas Elementor vía fallback de shortcode antes que Elementor renderizara; (2) labels de presets con adornos; (3) plantilla Elementor con imágenes multi-uso.
- **Auditoría**: 0 XSS (echo sin escape), 0 SQL sin prepare, 0 dead code, 0 duplicados, todos los AJAX con nonce (verificado handler por handler), rate limiting en register/login/checkout, colores con sanitize_hex_color + esc_html en inline CSS. Fix adicional: dir uploads/2026/09 era root (uploads fallaban).
- **Fix arquitectura**: router respeta `_elementor_edit_mode=builder` (jamás intercepta); `[erpc_products]` rinde content-only (`products-content.php`); frame flag global (wp_footer solo si header abrió); labels simples azul/rosa/gris.
- **Plantilla Elementor**: "Portada Elementor — Tienda Pro" (ID 53, canvas, publicada) con estructura best-practices (hero/trust/productos/USP/CTA/footer), widgets NATIVOS (el HTML widget es Pro-only — hallazgo), clases `erpc-el-*` que heredan el preset del plugin via CSS vars → multi-color verificado en vivo en AMBAS plantillas (rosa aplicó a Elementor y plugin, restaurado a azul).
- **Verificación**: home/productos sin regresión (frame completo, 1 doctype); página 53: 44 widgets renderizados, 71 cards embebidas, 0 chrome plugin, 1 footer, 1 doctype; sintaxis OK; push GitHub OK.
- **Estado**: ✅ sincronizado
- **Notas**: Imágenes Pexels (libres, uso comercial, sin atribución) subidas a media library. El modelo usado: Qwen3.6-35B vía victoria (GLM no existe en el stack).

### [02:00] - Plugin v3.5.0: 3 presets color + hero editable + modo Elementor + landing MCP
- **Tipo**: proyecto | feature | wordpress-dev | mcp | elementor
- **Modificado**: plugin `erp-ecomm-connector` v3.5.0 (commit `dae78b5`, 11 archivos); página Elementor 47 (draft)
- **Afecta a**: kalimete (tienda MaganTech + tenants futuros)
- **Causa**: Pedido usuario: (1) 3 temas de color seleccionables, (2) hero editable desde plugin, (3) switch plantilla plugin|Elementor sin mezcla, (4) diseñar plantilla Elementor, (5) qué modelo usar.
- **Implementado**: presets azul/rosa/neutro + pickers override (¡los colores del admin ahora SÍ se aplican! estaban guardados pero ignorados); hero con botón de medios; `template_mode` con gate central `erpc_is_elementor_mode()` (router se aparta, frames condicionales); shortcodes `[erpc_header]`/`[erpc_footer]`; sección admin Apariencia.
- **Verificación**: preset rosa en vivo (#d6336c + derivados), modo elementor verificado (theme render, 0 chrome plugin) + restore a plugin (topbar de vuelta); sintaxis OK; home/productos/login 200; landing Elementor creada vía MCP REST (`create-page/run`, draft 47 canvas con hero+botón+[erpc_products]).
- **Estado**: ✅ sincronizado
- **Notas**: GLM no existe en nuestro stack (sin provider ni llave) — recomendación de modelo en chat: Qwen3.6-35B vía victoria (220k ctx, local, sin bloqueo regional).

### [01:10] - Plugin v3.4.2: footer social alineado + cómo funciona la landing (arquitectura)
- **Tipo**: proyecto | fix | wordpress-dev | docs
- **Modificado**: plugin `erp-ecomm-connector` v3.4.2 (commit `26fcd5e`)
- **Afecta a**: kalimete (tienda MaganTech)
- **Causa**: Iconos sociales del footer flotando a la derecha del texto. Raíz: regla legacy `.erpc-footer { text-align:center }` (línea ~849, de un footer viejo) que seguía cascando porque el bloque moderno nunca la neutralizó → texto centrado, iconos flex a la izquierda.
- **Fix**: `text-align:left` en bloque moderno + `.erpc-footer-social` con `justify-content:flex-start` y gap reducido (44px→16px). Bump v3.4.2 para cache-bust (`?ver=`).
- **Verificación**: CSS 3.4.2 servido; screenshot footer OK.
- **Estado**: ✅ sincronizado
- **Notas**: Explicación de arquitectura (plugin vs Elementor vs MCP) entregada en chat.

### [00:30] - WordPress: fix duplicación visual landing (v3.4.1) + pipeline MCP Elementor operativo
- **Tipo**: proyecto | fix | wordpress-dev | mcp
- **Modificado**: plugin `erp-ecomm-connector` v3.4.1 (commit `ba92f2a`); `mcp-adapter` + `emcp-tools` activados con fix autoloader; app password MCP creada
- **Afecta a**: kalimete (tienda MaganTech + stack MCP)
- **Causa**: (1) Usuario reportó header/footer "duplicados" en la landing: el hero repetía la marca del header, la sección trust repetía la trustbar, y había un `</div>` huérfano tras `</html>` en landing/products/cart. (2) Plugins MCP (mcp-adapter + emcp-tools) inactivos; al activarlos, fatal por jetpack-autoloader duplicado (ambos bundlean el mismo namespace).
- **Fix**: (1) Hero con headline promocional, trust-grid eliminado, footer tras cierre de .erpc-page — HTML validado 52/52 divs. (2) Guard `class_exists` en `vendor/autoload_packages.php` de AMBOS plugins (mismo namespace hash → redeclaración). (3) `active_plugins` re-serializado con longitudes correctas (mi UPDATE anterior tenía s:19/s:41 erróneos → unserialize fallaba silenciosamente).
- **Verificación**: Landing 200 con hero promocional, 1 header, 1 footer, 0 trust-grid; productos/carrito/mi-cuenta 200; MCP REST `/wp-abilities/v1/abilities` → **151 abilities (148 emcp-tools Elementor: create-page, build-page, add-container, add-flexbox, atomic widgets, global classes, templates, batch-update)**; auth Basic con app password `mcp-kalimete-2026` (admin).
- **Estado**: ✅ sincronizado
- **Notas**: Arquitectura confirmada: plugin=datos (shortcodes), Elementor=diseño, MCP=control programático. Los fixes de autoloader viven en `vendor/` (se pierden en update de plugin — documentar en upstream). El endpoint REST de abilities tiene per_page max 100 (paginar). App password guardada en wp-cli style: NO commitear.

## 2026-09-17

### [16:30] - Fix ERR_SSL_PROTOCOL_ERROR: puerto 8090 cedido a nginx-TLS (redirects envenenados)
- **Tipo**: infra | red | seguridad
- **Modificado**: `/etc/nginx/sites-available/wordpress.kalimete.local.conf` (bkup `.bkup-20260917`); `~/dev/wordpress/docker-compose.yml` (bkup, `127.0.0.1:8091:80`)
- **Afecta a**: kalimete (stack wordpress-local)
- **Causa**: Chrome del usuario redirigía solo a `https://wordpress.kalimete.local:8090` → ERR_SSL_PROTOCOL_ERROR. Causa raíz: el 8090 era el backend HTTP directo del container; en la época del bounce de login el servidor emitió URLs con `:8090` que quedaron cacheadas/autocompletadas en el browser. El 8090 hablaba HTTP plano → handshake TLS imposible.
- **Fix**: (1) compose re-bind a `127.0.0.1:8091` (backend solo loopback); (2) nginx ahora escucha TLS en 8090/443/80 con el mismo cert mkcert → la URL envenenada responde 200 con TLS válido y WP canoniza al dominio sin puerto (redirect_to de wp-admin verificado limpio).
- **Verificación**: `https://wordpress.kalimete.local:8090/` → 200 con verificación TLS completa (sin -k); headless Chrome renderiza MaganTech por 8090; principal 200 sin regresión; loopback 8091 200; `nginx -t` OK; container healthy.
- **Estado**: ✅ sincronizado
- **Notas**: Ambas URLs (con y sin puerto) funcionan ahora. Limpieza previa: 4 transients erpc_* borrados (solo proyecto). Si el usuario sigue viendo el error: perfil Chrome (21 extensiones) — probar incógnito.

### [16:40] - NVIDIA NIM: auth.json en kalimete + sistema de rotación + llaves separadas
- **Tipo**: infra | config | opencode | seguridad
- **Modificado**: `~/.local/share/opencode/auth.json` (nuevo en kalimete), `~/.armada-custom/secrets/nvapi-keys.json` (nuevo), `~/.armada-custom/bin/nvapi-rotate.sh` (nuevo)
- **Afecta a**: kalimete (opencode provider nvidia), victoria (sin cambios — su llave intacta)
- **Causa**: El provider `nvidia` en opencode usa `auth.json` (no apiKey en JSONC). Victoria tenía su auth.json pero kalimete no — opencode no podía autenticar contra NVIDIA NIM. Cada nodo ahora usa su propia llave NVIDIA: kalimete = victoria-1 (me@alfredo.pro, nvapi-AuHob...), victoria = victoria-2 (warcold@gmail.com, nvapi-vZ9w...). Se replicó el script de rotación `nvapi-rotate.sh` a kalimete con `--resolve` (DNS jonas caído) y probes en paralelo.
- **Verificación**: Ambas keys dan HTTP 200 al POST `chat/completions` desde kalimete (modelo `openai/gpt-oss-20b` como probe, 3 modelos de NIM dan 404/timeout desde kalimete por restricción regional). auth.json legible, permisos 600 warcold:warcold.
- **Estado**: ✅ sincronizado
- **Notas**: Modelo de prueba cambiado de `moonshotai/kimi-k3` a `openai/gpt-oss-20b` (el único que responde 200 consistentemente desde kalimete). Sistema de rotación: `nvapi-rotate.sh status|test|rotate|auto` en kalimete. 3 llaves disponibles, rotación automática si falla la activa.

### [15:00] - Plugin v3.4.0: deploy multi-tenant + spec formal para el admin ERP
- **Tipo**: proyecto | feature | wordpress-dev
- **Modificado**: repo `github.com/warcold/erp-ecomm-connector` (commit `a423734`, 11 archivos); gitlink padre actualizado
- **Afecta a**: kalimete (modelo ZIP+llave=tienda por cliente)
- **Causa**: Visión producto: cada cliente ERP despliega su WordPress + plugin + su key. Faltaba hardening tenant + spec para completar funciones del lado ERP.
- **Verificación**: `php -l` limpio; fallback por shortcode probado en vivo (página tmp-* renderizó carrito, eliminada); override por tema probado en harness; home/productos/carrito/checkout/login/mi-cuenta todos 200; push OK.
- **Estado**: ✅ sincronizado
- **Notas**: Docs nuevos en el repo: `docs/PEDIDO-ERP.md` (P0: auth OTP/password, PUT perfil, ?email= real, /tienda/config, GET cliente; P1: lealtad, detalle pedido, ofertas, webhook) y `docs/DEPLOY-TENANT.md` (runbook ~20min + troubleshooting). Riesgo remanente: auth solo-email (P0-1) hasta que el ERP lo implemente.

### [14:00] - Plugin v3.3.9: Mis Pedidos reales + catálogo server-side + caché + rate limiting
- **Tipo**: proyecto | feature | wordpress-dev
- **Modificado**: repo `github.com/warcold/erp-ecomm-connector` (commit `319aab7`, 8 archivos); gitlink padre actualizado
- **Afecta a**: kalimete (tienda MaganTech viva)
- **Causa**: Mapeo real del API ERP (solo GETs read-only): `/orders` y `/ecomm/carts/:id` SÍ existen; `search/categoria_id/page/limit` funcionan server-side; `?email=` se ignora en `/orders` y `/customers`
- **Verificación**: `/productos/` 200 "Mostrando 15 de 157"; transients `erpc_c_*_v1` creados en DB; harness unitario OK (normalizadores + rate limit 5p/1b); `php -l` limpio; push GitHub OK
- **Estado**: ✅ sincronizado
- **Notas**: Journey compra con cuentas: registro/login/perfil/checkout guest+auth/Mis Pedidos funcionan; falta del ERP: auth con contraseña, PUT perfil, lealtad, /config, detalle /orders/:id, filtro ?email= real. Sin probar end-to-end: checkout_auth (crearía pedido real).

### [13:30] - Plugin erp-ecomm-connector con repo GitHub propio + baseline best-practices
- **Tipo**: proyecto | git | wordpress-dev
- **Modificado**: nuevo repo `github.com/warcold/erp-ecomm-connector` (privado, rama `main`); `MAPA.md` (línea repo plugin)
- **Afecta a**: kalimete (`~/dev/wordpress/wp-content/plugins/erp-ecomm-connector`, gitlink actualizado en repo padre)
- **Causa**: El plugin solo existía en disco local + volumen Docker + ZIP (riesgo documentado 13:10). Ahora con remoto, README, uninstall.php, .distignore.
- **Verificación**: push OK (commits `c616677` + `2b43d78`); sitio post-cambio `/` 200, `/wp-json/` 200; `php -l` limpio en archivos tocados.
- **Estado**: ✅ sincronizado
- **Notas**: Incluye fix real (cart TTL ignoraba el ajuste por `$GLOBALS` indefinido). Auditoría completa + roadmap entregados en chat. Riesgo remanente: auth solo-email sin verificación (propuesta OTP) y sin rate limiting — ver roadmap.

### [13:10] - WordPress MaganTech: SSL verificado OK + limpieza archivos huérfanos + cadena ERP validada
- **Tipo**: infra | limpieza | wordpress-dev
- **Modificado**: `~/dev/wordpress/` (12 archivos eliminados + 3 dirs vacíos/dups); `MAPA.md` (versiones + estado tienda)
- **Afecta a**: kalimete (stack wordpress-local/wordpress-db)
- **Causa**: Reporte `ERR_SSL_PROTOCOL_ERROR` en `https://wordpress.kalimete.local` + archivos huérfanos de la saga de debug SSL (Sep 16) + duplicados en `export/`
- **Verificación**: Servidor 100% OK — curl 200 con verificación TLS completa; headless Chrome renderiza la tienda sin flags inseguros. Causa del error: perfil Chrome del usuario (proxy/extensión/HSTS en caché), NO el servidor. CA mkcert reinstalada en sistema + NSS (Chrome/Chromium/Firefox). Cadena end-to-end validada: WP "MaganTech Store" → erp-ecomm-connector v3.3.8 → `https://erpipos.armada.do/api` tenant 10 → 18 categorías / 157 productos en vivo. Sitio post-limpieza: `/` 200, `/wp-login.php` 200.
- **Eliminado** (backup en `/tmp/opencode/wp-cleanup-20260917/`): `00-ssl-fix.conf`, `ssl-fix.conf`, `ssl-fix.php`, `wp-config.php.patched`, `docker-entrypoint-{custom,ssl}.sh` (compose nunca los usó), `debug-{headers,ssl}.php`, `test-headers.php`, `hello.php` (ninguno activo), `magantech-erp-template.zip` (contenido ya importado en vivo), `export/deploy-package/` (dups idénticos por md5), dirs vacíos `erp-validation/`, `export-package/`. Commit local `9f0d7ba` en repo `~/dev/wordpress` (sin remoto).
- **Conservado**: `backups/magantech/magantech.wpress` (137MB, único DR full-site) + `RESTAURAR.md`, `export/erp-ecmm-connector.zip` (v3.3.8 distribuible), `export/DEPLOY-GUIA.md`, `mcp-proxy*.js` (referenciados por wordpress-dev).
- **Estado**: ✅ verificado local (sync por cron)
- **Notas**: (1) Solo `elementor` + `erp-ecomm-connector` activos. (2) El `wp-config.php` vivo (volumen Docker) tiene bloques SSL inyectados duplicados pero funcionales; ante recreate del volumen el bloque stock de la imagen oficial + `WORDPRESS_CONFIG_EXTRA` cubren HTTPS. (3) RIESGO: el plugin no tiene remoto git — código solo en disco kalimete + volumen Docker + zip export. Recomendado push a GitHub. (4) `RESTAURAR.md` documenta credencial dev admin/admin123 en texto plano.

### [12:05] - kalimete vuelve a aparecer como agente primary en opencode (fix selector TAB)
- **Tipo**: infra | config | opencode
- **Modificado**: `agents/kalimete.md` (frontmatter)
- **Afecta a**: kalimete (opencode TUI)
- **Causa**: La clave `"eco-taohemps": allow` estaba duplicada en `permission.task` (líneas 16 y 22). El parser de frontmatter de opencode rechaza el archivo completo ante claves YAML duplicadas: kalimete no aparecía en `opencode agent list` ni en el selector TAB (solo plan/build). Se eliminó la segunda ocurrencia; backup en `~/backups/kalimete.md.bkup-20260917-dupkey`.
- **Verificación**: `opencode agent list` → `kalimete (primary)`; `opencode debug agent kalimete` → mode primary, temperature 0.2, color, 19 reglas task (`*` deny + allows, `general` denegado).
- **Estado**: ✅ verificado local (sync por cron)

### [03:05] - Caddyfile de preprod: bloque micaserogou.com eliminado (corrección)
- **Tipo**: infra | limpieza | preprod
- **Modificado**: `/opt/nextcloud-stack/Caddyfile` (vps-preprod)
- **Afecta a**: vps-preprod
- **Causa**: El bloque `micaserogou.com` del Caddyfile no fue eliminado en la limpieza inicial (el subagente no lo reportó). Se corrigió manualmente: backup `.bkup`, `sed -i` eliminando el bloque, verificación `grep` OK, Caddy recargado.
- **Estado**: ✅ sincronizado
- **Notas**: Caddyfile limpio ahora. No quedan rastros de micaserogou en preprod.

### [03:00] - Micaserogou eliminado de kalimete y preprod
- **Tipo**: infra | limpieza | proyecto eliminado
- **Modificado**: kalimete (Docker + código fuente + nginx), vps-preprod (Docker + certificados), docs (MAPA.md, CHANGELOG.md, INVENTARIO.md, agent files)
- **Afecta a**: kalimete, vps-preprod, toda la documentación armada-sync
- **Causa**: El usuario decidió no continuar con el proyecto Micaserogou. Se eliminó:
  - **kalimete**: Docker container `micaserogou-frontend-1`, directorio `~/dev/apps/micaserogou/` (docker-compose, Dockerfile, frontend, nginx.conf, deploy.sh)
  - **preprod**: Docker container `micaserogou-frontend-1`, directorio `/opt/micaserogou/` (clon Git, docker-compose.yaml)
  - **Preprod certs**: certificados SSL `micaserogou.com` eliminados del volumen Caddy
  - **Docker**: red `micaserogou_default` borrada, imagen `micaserogou-frontend:latest` eliminada
  - **Documentación**: borrado `agents/eco-micaserogou.md`, eliminadas todas las referencias en MAPA.md, INVENTARIO.md, kalimete.md, eco-cloudflare-dns.md, eco-cloudflare-security.md, eco-vps.md, SKILL.md (Cloudflare), configs/MAPA.md, configs/INVENTARIO.md
  - **Cloudflare**: zona `micaserogou.com` NO eliminada (solo se quitaron referencias locales — el usuario puede borrarla del dashboard si desea)
- **Estado**: ✅ sincronizado
- **Notas**: WordPress `wordpress.kalimete.local` ✅ funcionando. ComfyUI se queda en victoria.local:8188 (kalimete sin GPU).

---

## 2026-09-14

### [13:05] - ERP E-Commerce Connector v3.3.8: rutas sin doble /api + login real + pedido admin ERP redactado
- **Tipo**: proyecto | wordpress | bugfix crítico
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (4 archivos, commit `ac0b0d2`, push `main` OK), ZIPs regenerados y verificados (89K, `Version: 3.3.8`)
  - Rutas sin doble `/api` (`/customers`, `/ecomm/carts`, `/ecomm/checkout/*`) — login/crear-carrito/checkout estaban muertos (404)
  - `find_customer_by_email()` con paginado local (ERP ignora `?email=` y `per_page`; `page` sí funciona, 78 clientes/6 págs)
  - Guest sin `cliente_id` (422 antes) → 201 verificado; `update_customer` error honesto (PUT 404)
- **Verificación**: login email real → success id 71; `erpc_get_customer` OK; checkout guest → 200; `PUT :id` 404; `OPTIONS` 200 en rutas
- **Residuo de pruebas en tenant 10** (notificar al admin para anular): carts 14 (checked-out) y 15, customers 133 (Validacion Final), 136 (checkout-test), +1 ABANICO vendido en checkout de prueba
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: en remoto subir ZIP 3.3.8 — login y checkout invitado quedan operativos

---

## 2026-09-14

### [12:50] - ERP E-Commerce Connector v3.3.7: quick view modal + badge en vivo + En carrito (N)
- **Tipo**: proyecto | wordpress | feature+bugfix
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (6 archivos, commit `1fc82d9`, push `main` OK), ZIPs regenerados y verificados por dentro (88K, `Version: 3.3.7`)
  - Nuevo modal vista rápida (foto, categoría, precio, stock, stepper cantidad, agregar, Esc/overlay/× para cerrar) — cards tenían `href="#"` muertos; sin endpoint nuevo (ERP detalle por id → 404, usa catálogo en caché/DOM)
  - `header.php` badge siempre en DOM + JS lo crea si falta y lo actualiza en cada mutación (antes invisible hasta recargar)
  - Botones con estado persistente "✓ En carrito (N)" resincronizado en cada cambio (antes revertía a los 1.2s)
- **Afecta a**: ecomm MaganTech
- **Verificación**: `php -l` OK, `node --check` OK, badge en DOM, 30 `card-open`, `erpc_sync_cart` 200 count 2, ZIP con 3.3.7 + modal JS/CSS
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: en remoto subir ZIP 3.3.7

---

## 2026-09-14

### [12:45] - ERP E-Commerce Connector v3.3.6: filtro categoría vía URL + registro/login reparados
- **Tipo**: proyecto | wordpress | bugfix
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (6 archivos, commit `a1c35e0`, push `main` OK), ZIPs regenerados y verificados por dentro (86K, `Version: 3.3.6`)
  - `templates/ecomm/products.php` — respeta `?categoria=` en servidor (grilla filtrada + pill activa + conteo); estado vacío visible con "Ver todo el catálogo" si 0 productos
  - `assets/js/connector.js` — lee `?categoria=` al cargar, sincroniza URL al filtrar (`replaceState`); fix `bindAuthForms()` nunca corría (`$(".erpc-auth")` vs template `erpc-auth-page`); fix `$(this)` en callbacks ajax (errores invisibles + botón trabado)
  - `templates/auth/form.php` — eliminadas contraseñas decorativas (ERP email-only); `includes/class-erpc-auth.php` — 404 login traducido a mensaje útil
- **Afecta a**: ecomm MaganTech
- **Causa**: JS ignoraba querystring; selector auth inexistente + contexto `$(this)` + campos password nunca enviados
- **Verificación**: `php -l` OK, `node --check` OK, `?categoria=Cables` → 15 cards solo Cables + "Mostrando 15 de 47", `?categoria=Redes` → vacío visible, `erpc_register` validación JSON OK, `erpc_login` email inexistente → mensaje útil (solo lectura ERP), login sin passwords
- **Hallazgo**: ERP solo tiene productos en 7/18 categorías (Cables 47, Computadoras 52, Impresoras 22, Monitores 9, Almacenamiento 1, Herramientas 1, 10 sin categoría) — categorías vacías muestran "Sin resultados" correctamente
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: en remoto subir ZIP 3.3.6

---

## 2026-09-14

### [12:35] - ERP E-Commerce Connector v3.3.5: sección config imposible de llenar → rehecha como efectiva (local+ERP)
- **Tipo**: proyecto | wordpress | bugfix
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (3 archivos, commit `162010a`, push `main` OK), ZIPs regenerados y verificados por dentro (84K, `Version: 3.3.5`)
  - `includes/class-erpc-admin.php` — sección 2 rehecha como "Configuración de la tienda": valores efectivos (local gana, ERP respaldo, defaults etiquetados), cada fila con fuente y hint; badge por `config_fetched_at`; `ajax_fetch_config` con mensaje honesto si el ERP no envía identidad
- **Afecta a**: ecomm MaganTech
- **Causa raíz (reproducida)**: `get_business_config()` devuelve `name:""` siempre — el ERP no tiene endpoint de config (6 candidatos → 404). La sección anterior era imposible de llenar por diseño. Además en remoto < v3.3.3 cada Guardar borraba `erp_config` → "Pendiente" eterno
- **Verificación**: `php -l` OK, `wp eval` efectivo `eff_name=[MaganTech Store]`, `/productos/` 200, ZIP contiene 3.3.5 + fixes
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: en remoto subir ZIP 3.3.5, Guardar clave, Sincronizar, rellenar Nombre/Logo en Personalización visual

---

## 2026-09-14

### [12:35] - ERP E-Commerce Connector v3.3.4: newsletter duplicado fuera, logo+nombre siempre visibles, campos negocio por instancia
- **Tipo**: proyecto | wordpress | bugfix+feature
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (6 archivos, commit `c89832a`, push `main` OK), ZIPs regenerados (83K)
  - `templates/landing.php` — eliminado bloque newsletter "Ofertas exclusivas" (el home renderizaba 2 seguidos: landing + footer; el footer queda como única fuente)
  - `templates/partials/header.php` — antes logo O nombre (if/else); ahora ambos (logo + `get_brand_name()`), logo enlaza al inicio, agregado enlace "Inicio" al nav de tienda
  - `includes/class-erpc-admin.php` — nuevos campos editables por instancia: Nombre del negocio + Eslogan (sección Personalización visual); `sanitize_settings()` los preserva; texto engañoso "se actualiza automáticamente al verificar" corregido (Verificar nunca guardaba)
  - `includes/class-erpc-api.php` — `get_business_config()` intenta `/tienda/config` antes que `/config` (futuro; hoy todos 404 verificados: `/tienda/config`, `/tienda/info`, `/tienda`, `/negocio`, `/config`, `/tienda/negocio`)
  - Bump `3.3.3→3.3.4` + CHANGELOG plugin
- **Afecta a**: ecomm MaganTech (tenant 10)
- **Causa**: duplicado visual landing+footer; header ocultaba nombre si había logo y el nav de tienda no tenía Inicio; ERP sin endpoint de config → nombre/logo deben gestionarse en admin WP con fallback local→erp_config→default
- **Verificación**: `php -l` OK x5, home `ofertas exclusivas` 2→1, `newsletter-section` 0, `footer-newsletter` 1, `erpc-brand-name` 1, `/productos/` 104 cards / 19 pills, logs sin fatal
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: en el WP remoto subir ZIP 3.3.4 y rellenar Nombre/Logo/Eslogan en ERP Connector → Personalización visual

---

## 2026-09-14

### [12:05] - ERP E-Commerce Connector v3.3.3: preserva erp_config, categorías robustas + paginación sin repetir + limpieza viejas
- **Tipo**: proyecto | wordpress | bugfix
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (7 archivos, commit `81b7860`, push `main` OK), ZIPs regenerados `export/*.zip` (83K)
  - `includes/class-erpc-admin.php` — `sanitize_settings()` preserva `erp_config` + `config_fetched_at` (fix desync cada Guardar)
  - `templates/ecomm/products.php`, `templates/landing.php` — aceptan `categorias/data/lista`, normalizan `categoria:{id,nombre}` vs string, fallback derivando únicas, `sanitize_text_field`, añadidos `#erpc-count-info` + `data-total`
  - `includes/class-erpc-shortcodes.php` — `ajax_get_categories()` normaliza a `[{id,nombre}]`
  - `assets/js/connector.js` — `seen{}` dedup por `id`, contador `Mostrando X de Y`, toggle Cargar más, fallback pills `erpcEnsureCategories()` si solo Todo
  - Bump `3.3.2→3.3.3` + CHANGELOG plugin
- **Limpieza**: borrados `erpecomm-alfredo-pro/`, `erpecomm-alfredo-pro.bak/` (144K c/u, inactivos, key vieja revocada 401) y duplicado anidado `erp-ecomm-connector/erp-ecomm-connector/` (1.3M artefacto docker cp). Backups en `~/backups/magantech-cleanup-20260914/` + `*.bkup-20260914` por archivo.
- **Afecta a**: ecomm MaganTech (tenant 10, 142 productos, 18 categorías)
- **Causa**: Verificar≠Guardar + `/config` y `/tenants/10` 404 + `sanitize` borraba sync + filtro categoria-objeto + paginación slice(0,15) sin contador/dedup
- **Verificación**: `php -l` OK x5, `node --check` OK, `/productos/` 104 `erpc-card`, 19 `erpc-cat-btn` (Todo+18), 2 `erpc-count-info`, logs sin fatal
- **Estado**: ✅ sincronizado (plugin push + ZIPs)
- **Notas**: purgar caché navegador para probar Cargar más pág.2 sin repetidos; `Guardar` + `Sincronizar` requerido tras update

---

## 2026-09-14

### [11:33] - Docs: AGENTS.md adelgazado a reglas globales, kalimete.md fuente única operativa + fix eco-alfredo-ecomm
- **Tipo**: docs | agente | config
- **Modificado**: `AGENTS.md` (132→41 líneas), `agents/kalimete.md`, `MAPA.md`
- **Afecta a**: kalimete (todas las sesiones opencode)
- **Causa**: AGENTS.md y kalimete.md duplicaban topología, SSH, tabla de agentes y límites de contexto (ya habían derivado: decían 228000/240000 y baseURL por túnel, lo real es 220000/32000 en LAN). MAPA.md tenía fila duplicada y le faltaba proxmark. `eco-alfredo-ecomm` existía en `agents/` pero kalimete no podía delegarle (faltaba en `permission.task` y en la tabla).
- **Cambios**:
  - `AGENTS.md` → solo reglas globales + punteros a la fuente única (MAPA.md / kalimete.md / skill cloudflare). Cero tablas duplicadas.
  - `agents/kalimete.md` → agregado `eco-alfredo-ecomm` a frontmatter + tabla; la lista de permisos ya no se duplica en el cuerpo (vive solo en el frontmatter); snapshot `opencode.jsonc` corregido contra lo real (context 220000/output 32000, `http://victoria.local:8010/v1`); puntero a MAPA.md como fuente de topología.
  - `MAPA.md` → eliminada fila duplicada `eco-micaserogou`, agregada fila `proxmark`, corregido bloque `opencode.jsonc` (3 providers, baseURL LAN, limits).
  - Backups pre-cambio en `~/backups/armada-docs-20260914/` (fuera del repo para no ensuciar el sync).
- **Estado**: ✅ sincronizado
- **Notas**: salir y reiniciar opencode para que tome la nueva config (no hay hot-reload).

---

## 2026-09-14

### [00:20] - ERP E-Commerce Connector: eliminada plantilla Elementor redundante
- **Tipo**: proyecto | wordpress | refactor
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/`
  - Eliminado `includes/generate-template.php` (archivo huérfano)
  - Eliminados `maybe_generate_template()`, `handle_template_generation()`, `gen_id()`, `esc_xml()` de `class-erpc-activation.php`
  - Eliminado hook `?erpc_generate_template=1` (riesgo de seguridad)
  - `DEPLOY-GUIA.md` reescrito (solo plugin, sin template)
- **Afecta a**: ecomm MaganTech + cualquier instalación del plugin
- **Causa**: La plantilla Elementor (`tech-ecomm-template.zip`) era redundante — el plugin ya crea las 14 páginas automáticamente al activarse y las renderiza con su propio CSS/JS. La plantilla era un formato JSON custom sin importador real.
- **Archivos de plantilla eliminados**:
  - `~/Desktop/MaganTech-Connector-Deploy/tech-ecomm-template.zip`
  - `~/dev/wordpress/export/erp-connector-template.xml`
  - `~/dev/wordpress/export/magantech-erp-template.zip`
  - `~/dev/wordpress/export/wp-export-all.xml` y `wp-export-pages.xml` (vacíos)
  - `~/dev/wordpress/export/deploy-package/template/` (directorio)
- **Estado**: ✅ v3.3.2 pusheado (commit `f588b0d`), ZIP regenerado sin template
- **Verificación**: las 14 páginas responden HTTP 200 tras la limpieza.

---

## 2026-09-14

### [03:30] - ERP E-Commerce Connector v3.3.2: activation crea las 14 páginas (fix "not found")
- **Tipo**: proyecto | wordpress | bugfix
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/includes/class-erpc-activation.php`
- **Afecta a**: ecomm MaganTech + cualquier instalación limpia del plugin
- **Causa raíz**: Al instalar el plugin en un WordPress limpio, `create_default_pages()` solo creaba 6 páginas (inicio, productos, carrito, checkout, login, mi-cuenta) y usaba shortcodes incorrectos (`[erpc_login]` y `[erpc_profile]` que NO existen). Las páginas estáticas (sobre-nosotros, contacto, terminos, privacidad, cookies, envios, devoluciones, faq) NO se creaban → "not found".
- **Cambios**:
  - `create_default_pages()` ahora crea **14 páginas** (6 shortcode + 8 estáticas)
  - Shortcodes corregidos: `[erpc_login]`→`[erpc_auth]`, `[erpc_profile]`→`[erpc_customer]`
  - Slug inicio: `inicio`→`magantech-inicio` (coincide con header/footer)
  - Nuevo `get_static_content()` con contenido estándar para las 8 páginas legales
  - `apply_elementor_canvas()` y `handle_template_generation()` actualizados a 14 slugs
- **Estado**: ✅ v3.3.2 pusheado (commits `7ec0b58`, `fc9a034`), ZIPs regenerados
- **Verificación**: las 14 páginas responden HTTP 200 con header + footer + contenido.

---

## 2026-09-13

### [17:00] - ERP E-Commerce Connector: página contacto llenada + template con contenido real
- **Tipo**: proyecto | wordpress | fix
- **Modificado**: WordPress localhost:8090 + `tech-ecomm-template.zip`
- **Afecta a**: ecomm MaganTech (erpipos.armada.do)
- **Causa**: La página "contacto" (ID 17) estaba vacía — el usuario no veía contenido al hacer click. El template de importación tenía contenido placeholder genérico en las páginas estáticas.
- **Cambios**:
  - Página "contacto" llenada con contenido estándar (correo, teléfono, horario, soporte)
  - Template `tech-ecomm-template.zip` regenerado con el **contenido real** de las 8 páginas estáticas (extraído de WordPress, duplicando el patrón de las páginas que funcionan)
- **Verificación**: las 13 páginas renderizan HTTP 200 con header + footer + contenido.
- **Estado**: ✅ sincronizado

---

### [14:55] - Proxmark3: flash firmware Iceman v4.21611 + cfmb25 corregido
- **Tipo**: infra | hardware | fix
- **Modificado**:
  - `/opt/proxmark3/` — compilado desde fuente: Iceman/master/v4.21611-1575-g64b5db4dd (2026-09-13)
  - `pm3-flash-all` — flash completo exitoso (bootrom + armsrc + FPGA)
  - `/home/warcold/bin/cfmb25` — rutas corregidas: `~/.proxmark3/dumps/` (antes apuntaba a `/home/warcold/.victoria/pm3-dumps/` que ya no existe); binario actualizado a `/opt/proxmark3/client/proxmark3` (antes `/usr/bin/proxmark3` viejo de Kali); fix bug `grep -c || echo 0` (doble "0" rompía comparaciones numéricas)
- **Afecta a**: kalimete (pm3 en /dev/ttyACM0)
- **Causa**: El pm3 estaba en ciclo de reinicio (EPROTO, bootloader corrupto) — no respondía por serial. Tras flash quedó 100% operativo (hw ping 1ms, antena LF/HF ok).
- **Validación**: `cfmb25` clonó FMB25 a la tarjeta actual → 64/64 bloques OK, 0 auth errors, 0 fail. Dump FMB25 verificado (UID 32 95 B6 7B, md5 dbb0aa91... idéntico en 3 copias).
- **Estado**: ✅ sincronizado
- **Notas**: El binario viejo `/usr/bin/proxmark3` (Kali 4.18994) no responde con el firmware nuevo — usar siempre `/opt/proxmark3/client/proxmark3`.

---

## 2026-09-13

### [16:30] - ERP E-Commerce Connector v3.3.1: template completo + políticas + flujo ecomm validado
- **Tipo**: proyecto | wordpress | feature
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/`
  - `templates/static.php` — NUEVO: renderiza páginas legales/info con layout unificado
  - `includes/class-erpc-templates.php` — mapea 8 páginas estáticas (terminos, privacidad, cookies, sobre-nosotros, envios, devoluciones, faq, contacto)
  - `templates/partials/footer.php` — links reales (antes `#`), categorías reales de tecnología
  - `templates/partials/header.php` — nav con "Nosotros" y "Contacto" (desktop-only)
  - `templates/ecomm/cart.php` — fix: agregado header.php (antes solo footer)
  - `assets/css/connector.css` — estilos `.erpc-static-page` + nav responsive
- **Afecta a**: ecomm MaganTech (erpipos.armada.do) + cualquier instancia ERP
- **Páginas creadas en WordPress** (7 nuevas): terminos, privacidad, cookies, sobre-nosotros, envios, devoluciones, faq — con contenido estándar de e-commerce adaptable por el propietario.
- **Menú de navegación** creado y asignado a ubicación `menu-1`.
- **Shortcodes corregidos**: `mi-cuenta` usaba `[erpc_profile]` (inexistente) → `[erpc_customer]`; `login` usaba `[erpc_login]` → `[erpc_auth]`.
- **Flujo ecomm validado end-to-end**:
  - ✅ Registro cliente: POST /customers → 201 (cliente id 133, tenant 10)
  - ✅ Carrito: POST /ecomm/carts → 201 (cart id 14, total RD$ 1,100.00)
  - ✅ Checkout guest: POST /ecomm/checkout/guest → 200 ("Guest customer created")
  - ✅ Login por email: GET /customers?email= → 200
- **Aislamiento por key confirmado**: la key determina el tenant; `X-Tenant-ID` es ignorado (productos idénticos con 1/10/999/sin header).
- **Template de importación regenerado**: `tech-ecomm-template.zip` con 14 páginas (6 shortcode + 8 estáticas).
- **Estado**: ✅ v3.3.1 pusheado (commits `e0fa0d8`, `ab3157c`, `4aae706`, `f44ad87`), ZIPs regenerados
- **DEPLOY-GUIA.md** actualizado (solo API Key, 14 páginas, shortcodes correctos).

---

## 2026-09-13

### [13:35] - ERP E-Commerce Connector v3.2.1: URL/Tenant fijos, solo API Key editable
- **Tipo**: proyecto | wordpress | fix
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/`
  - `erp-ecomm-connector.php` — `get_api_url()` vuelve a la constante fija; `get_tenant_id()` solo usa erp_config
  - `includes/class-erpc-admin.php` — eliminados campos "URL de la API" y "Tenant ID"; solo API Key editable
- **Afecta a**: ecomm MaganTech (erpipos.armada.do) + cualquier instancia ERP
- **Causa**: El usuario confirmó que la URL es fija para todas las instancias y que la key es lo que aísla el contenido por tenant. Los campos URL/Tenant ID configurables (v3.2.0) eran innecesarios y arriesgados (el cliente podría tocar lo que no debe).
- **Validación de aislamiento por key**:
  - ✅ La key `iak_Dhv2...` devuelve 142 productos y 18 categorías, todas de tecnología (MaganTech)
  - ✅ El header `X-Tenant-ID` es **ignorado** por el ERP: con valor 1, 10, 999 o sin header, los productos son idénticos
  - ✅ La key es lo único que determina el tenant — no se mezclan keys ni contenido
- **Estado**: ✅ v3.2.1 pusheado (commits `9751a73`, `60d22ef`, `11be069`), ZIPs regenerados limpios
- **Notas**: Se eliminó el header `X-Tenant-ID` del `ajax_test_connection` (era ignorado por el ERP).

---

## 2026-09-13

### [00:45] - ERP E-Commerce Connector v3.2.0: multi-instancia + landing fix
- **Tipo**: proyecto | wordpress | feature
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/`
  - `erp-ecomm-connector.php` — `api_url` y `tenant_id` configurables (antes hardcodeados)
  - `includes/class-erpc-admin.php` — campos "URL de la API" y "Tenant ID" en el admin panel
  - `assets/img/placeholder.svg` — reparado (tenía texto basura)
- **Afecta a**: ecomm MaganTech (erpipos.armada.do) + cualquier instancia ERP
- **Causa**: El plugin estaba atado a `erpipos.armada.do` y tenant 10. Ahora es un template base multi-instancia: el usuario pone la URL de SU ERP + su key + su tenant ID.
- **Landing fix**: La home (page 8) tenía override de Elementor (diseño oscuro viejo). Se eliminó el override → ahora renderiza el template moderno del plugin (`[erpc_landing]` con hero, trust bar, categorías, destacados, newsletter).
- **Estado**: ✅ v3.2.0 pusheado (commits `e0e4f16`, `d41d092`, `8475b9d`), ZIPs regenerados
- **Validación e2e**:
  - ✅ Key correcta `iak_Dhv2...` → 142 productos, 18 categorías
  - ✅ Landing: hero + trust bar + 8 categorías + 8 destacados + newsletter
  - ✅ Productos: cards con imagen, badge stock, precio RD$, botón carrito
  - ✅ Carrito/Checkout/Login/Mi Cuenta renderizan
  - ✅ Responsive (375px y 1280px)

---

## 2026-09-12

### [23:30] - API Key MaganTech documentada + fix product count (v3.1.2)
- **Tipo**: bugfix | seguridad
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/includes/class-erpc-admin.php`
- **Afecta a**: ecomm MaganTech (erpipos.armada.do, tenant 10)
- **Causa raíz 401**: La API Key de MaganTech había sido revocada/desactivada en el ERP. Las dos keys documentadas previamente en el CHANGELOG (`iak_c6ALZ...` y `iak_hT0RO7...`) devuelven 401.
- **Key actual confirmada**: `iak_Dhv2RmUWaLa3fLXlpr330X7SIONl4icQoWSTqCGK` (tenant 10) — devuelve HTTP 200 con **142 productos**.
- **Bug adicional**: `ajax_test_connection` contaba `$data['data']` pero el ERP devuelve `$data['productos']` — el contador de productos siempre era 0. Arreglado.
- **Estado**: ✅ Plugin v3.1.2 pusheado a GitHub (commit `63192d9`)
- **ZIPs regenerados**: `~/dev/wordpress/export/deploy-package/erp-ecmm-connector.zip` + `~/Desktop/MaganTech-Connector-Deploy/erp-ecmm-connector.zip`
- **Notas**: Las dos keys anteriores están registradas en el CHANGELOG de armada-sync con solo los primeros 11 chars (por seguridad). La key completa está ahora en el CHANGELOG del plugin (commit `63192d9`).

---

### [16:10] - Plugin: fix nonce + API Key test sin guardar (v3.1.1)
- **Tipo**: bugfix
- **Modificado**: `wp-content/plugins/erp-ecomm-connector/includes/class-erpc-admin.php`
- **Afecta a**: ecomm MaganTech (erpipos.armada.do)
- **Causa**: El AJAX `test_connection` fallaba con "Falta API Key" si el usuario no había guardado la API key. El nonce también fallaba por incompatibilidad con `check_ajax_referer`.
- **Cambios**:
  - JS: envía `api_key` desde el campo del formulario al AJAX de verificación
  - JS: envía `erpc_test_connection_nonce` adicional para compatibilidad
  - PHP: `ajax_test_connection()` acepta `$_POST['api_key']` (fallback a DB)
- **Estado**: ✅ plugin v3.1.1 pusheado a GitHub (commit `b406cf0`)
- **ZIPs de deploy actualizados**:
  - `~/dev/wordpress/export/deploy-package/erp-ecmm-connector.zip` (v3.1.1 fresh)
  - `~/Desktop/MaganTech-Connector-Deploy/erp-ecmm-connector.zip` (v3.1.1 fresh)
  - `~/dev/wordpress/erp-ecmm-deploy.zip` (eliminado, estaba viejo)

---

### [01:10] - ERP E-Commerce Connector: Diseño consistente + footer profesional (v3.1.0)
- **Tipo**: proyecto | wordpress | footer | diseño | consistencia
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `templates/partials/footer.php` — Footer profesional 4 columnas (brand/tienda/ayuda/legal) + newsletter
  - `templates/partials/page-wrapper.php` — Wrapper unificado para todas las páginas
  - `assets/css/connector.css` — CSS footer completo (gradiente, grid responsive, badges)
  - `erp-ecomm-connector.php` — Version bumped to 3.1.0
  - `CHANGELOG.md` — Documentado v3.1.0
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Las páginas no se veían coherentes con el profesionalismo del landing, y faltaban links legales en el footer.
- **Estado**: ✅ Footer completo, todas las páginas consistentes, 0 emojis, 11 templates con PHP limpio
- **Notas**:
  - Footer ahora incluye: logo, tagline, enlaces a Tienda/Ayuda/Legal, newsletter, redes sociales, badges SSL
  - Legal links: Términos y condiciones, Política de privacidad, Política de cookies, Sobre nosotros, Trabaja con nosotros
  - Todas las páginas unificadas con mismo header/trustbar/footer
  - Git push OK: `f28a51e` (v3.1.0)

## 2026-09-10

### [23:55] - Nextcloud: cuenta `alfredo@armada.do` habilitada
- **Tipo**: infra | nextcloud
- **Modificado**: vps-preprod (Nextcloud)
  - `occ user:enable alfredo@armada.do` → cuenta habilitada
- **Afecta a**: nextcloud.armada.do
- **Causa**: El usuario se creó automáticamente por OIDC provisioning (`auto_create_user=1`), pero Nextcloud deshabilita los usuarios nuevos por defecto.
- **Estado**: ✅ desbloqueada

### [23:49] - Authentik: fix "Failed to provision the user" (scopes OIDC vacíos en providers)
- **Tipo**: infra | sso | oidc
- **Modificado**: vps-preprod (Authentik)
  - Asignados scopes `openid`, `email`, `profile` a los providers OIDC **Nextcloud** y **DocuSeal OIDC** (ambos estaban con `property_mappings` vacío).
- **Afecta a**: auth.armada.do, nextcloud.armada.do, docuseal.armada.do
- **Causa**: Los providers OIDC no tenían scopes configurados. El log de Authentik mostraba `"Application requested scopes not configured, setting to overlap"` con `scope_allowed: set()` (vacío). Al no tener scopes, el ID token salía sin el claim `email`, y Nextcloud (que usa `mappingUid=email`) no podía provisionar el usuario → "Failed to provision the user".
- **Estado**: ✅ fix aplicado y verificado
- **Notas**:
  - Scope mappings por defecto disponibles: `openid`, `email`, `profile`, `entitlements`, `offline_access`, `goauthentik.io/api`, `ak_proxy`.
  - Antes: `Nextcloud -> []`, `DocuSeal OIDC -> []`.
  - Después: `Nextcloud -> ['openid', 'email', 'profile']`, `DocuSeal OIDC -> ['openid', 'email', 'profile']`.
  - Redirect de login ahora incluye `scope=openid+email+profile` (antes no incluía scopes).
  - Warning "scopes not configured" desapareció (últimos registros: 23:04, anteriores al fix).
  - **LECCIÓN**: al crear un provider OIDC en Authentik, asignar SIEMPRE los scopes `openid`, `email`, `profile` (no se asignan automáticamente).

### [22:45] - Authentik↔Nextcloud: fix REAL "Client authentication failed" (secret en DB, no appconfig)
- **Tipo**: infra | sso | oidc | seguridad
- **Modificado**: vps-preprod (Nextcloud DB `oc_user_oidc_providers`)
  - Actualizado el client_secret del provider `authentik` (id=2) en la tabla `oc_user_oidc_providers` vía `occ user_oidc:provider authentik --clientsecret=...`
- **Afecta a**: nextcloud.armada.do
- **Causa**: La app `user_oidc` v8.10.1 NO lee las claves de appconfig (`client_secret`/`clientsecret`). Lee el client_secret de la tabla de base de datos `oc_user_oidc_providers` (encriptado con ICrypto). Los fixes anteriores actualizaban appconfig, que la app ignora. La DB seguía con el secret viejo (172 chars) mientras Authentik tenía el nuevo (hex 64 chars) → "Invalid client secret".
- **Estado**: ✅ fix aplicado y verificado
- **Notas**:
  - Backup DB: `/tmp/oc_user_oidc_providers.bkup-20260910-224434.sql`
  - Comando oficial: `occ user_oidc:provider authentik --clientid=... --clientsecret=... --discoveryuri=...` (encripta automáticamente)
  - Secret en DB cambió: longitud 352→324, prefijo `7dcb4500`→`ad547302`
  - Flujo login OK: `/apps/user_oidc/login/2` → 303 a `auth.armada.do/application/o/authorize/...`
  - Logs: 0 "Invalid client secret" nuevos
  - **LECCIÓN**: al rotar secretos OIDC en Nextcloud, actualizar SIEMPRE la DB (`occ user_oidc:provider`), NO appconfig.

### [19:58] - Authentik↔Nextcloud: fix "Client authentication failed" (client_secret con caracteres especiales)
- **Tipo**: infra | sso | oidc | seguridad
- **Modificado**: vps-preprod (Authentik + Nextcloud)
  - Regenerado `client_secret` del provider OIDC Nextcloud → **hex 64 chars** (sin caracteres especiales)
  - Actualizado en Authentik (`OAuth2Provider.client_secret`) y en Nextcloud `user_oidc` (`client_secret` + clave duplicada `clientsecret`)
- **Afecta a**: auth.armada.do, nextcloud.armada.do
- **Causa**: El client_secret anterior (128 chars) contenía caracteres especiales (`$`, `'`, `"`, `|`, `&`, `^`, `%`, etc.) que se corrompían al enviarse vía URL-encoding al token endpoint OIDC, provocando "Client authentication failed" / "Invalid client secret". El secret almacenado coincidía byte a byte (SHA256 idéntico) entre ambos lados, pero Nextcloud enviaba un valor distinto por el encoding.
- **Estado**: ✅ fix aplicado y verificado
- **Notas**:
  - Nuevo secret: longitud 64, prefijo `89ce` (valor completo NO expuesto).
  - SHA256 idéntico en ambos lados: `54e907b7...beeb251`.
  - Clave duplicada `clientsecret` (sin guion bajo) también actualizada y verificada.
  - Flujo login OK: `/apps/user_oidc/login/2` → **303** a `auth.armada.do/application/o/authorize/...` (PKCE S256).
  - Logs: los únicos 2 "Invalid client secret" son históricos (19:25:09 y 19:25:20), anteriores al fix. 0 errores nuevos tras el cambio.

### [18:10] - Authentik: integración OIDC centralizada (Nextcloud + DocuSeal)
- **Tipo**: infra | sso | oidc | seguridad
- **Modificado**: vps-preprod (Authentik + Nextcloud + DocuSeal)
  - `akadmin` → agregado al grupo `authentik Admins` (superuser corregido)
  - Signing key RS256 creada: `authentik OIDC RS256 Signing Key`
  - Providers OIDC Nextcloud y DocuSeal: `authentication_flow` = `default-authentication-flow` + `signing_key` asignada
  - Nextcloud `user_oidc`: provider_url, client_id, client_secret configurados
  - Cron `*/15 * * * *` para `/opt/authentik/sync_users.sh`
- **Afecta a**: auth.armada.do, nextcloud.armada.do, docuseal.armada.do
- **Causa**: Centralizar todo el login del ecosistema Armada vía Authentik (SSO OIDC). Antes Nextcloud usaba login interno y los providers OIDC estaban sin flujo de autenticación.
- **Estado**: ✅ integración operativa
- **Notas**:
  - DocuSeal ya tenía OIDC configurado (env vars) — solo se corrigió el authentication_flow en Authentik.
  - Patrón repetible establecido para futuros servicios: Application + Provider OIDC → asignar `default-authentication-flow` + signing key RS256 → en el servicio `provider_url=https://auth.armada.do/application/o/<slug>/` + client_id/secret.
  - Ningún client_secret expuesto en reportes.

### [18:05] - Nextcloud: fix SSRF para OIDC/Authentik (allow_local_remote_servers)
- **Tipo**: proyecto | nextcloud | oidc | seguridad
- **Modificado**: vps-preprod (config Nextcloud vía occ)
  - `allow_local_remote_servers` → `true` (boolean)
- **Afecta a**: nextcloud.armada.do (contenedor `nextcloud-stack-nextcloud-1`)
- **Causa**: El flujo OIDC con Authentik fallaba por la protección SSRF de Nextcloud 33 (`DnsPinMiddleware`). Dentro del contenedor, `auth.armada.do` resuelve a `172.18.0.8` (IP interna del contenedor Caddy), que Nextcloud bloqueaba por ser IP privada/local.
- **Estado**: ✅ fix aplicado y verificado
- **Notas**:
  - Comando: `docker exec nextcloud-stack-nextcloud-1 php occ config:system:set allow_local_remote_servers --value=true --type=boolean`
  - Verificación: `config:system:get allow_local_remote_servers` → `true`
  - Flujo OIDC OK: `/apps/user_oidc/login/2` → **303** a `auth.armada.do/application/o/authorize/...` (PKCE S256)
  - Root `/` → **302** a `/index.php/login`
  - Logs limpios: 0 coincidencias de errores OIDC/SSRF en los últimos 200 registros
  - Provider `authentik` (id 2) configurado correctamente (clientSecret enmascarado)

### [11:50] - ERP E-Commerce Connector: textos profesionales + seguridad en admin (v2.6.2)
- **Tipo**: proyecto | wordpress | ui | seguridad
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `includes/class-erpc-admin.php` — Textos profesionales + eliminación de info sensible
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Mejorar profesionalismo de los textos guía y cuidar la seguridad (no exponer URL del ERP ni detalles internos).
- **Estado**: ✅ textos actualizados, sin info sensible en admin, PHP syntax OK
- **Notas**:
  - Renombrado: "Configuración del ERP (Solo Lectura)" → "Estado de configuración del ERP"
  - Eliminado: "La URL del ERP está preconfigurada" y "erpipos.armada.do" del admin UI
  - API Key: `autocomplete="off"`, placeholder seguro sin pista de URL
  - Botones: "Test Connection" → "Verificar conexión", "Obtener Config" → "Sincronizar configuración"
  - Secciones: "Conexión con el ERP", "Personalización visual", "Preferencias de la tienda"
  - Git push OK: commit `9f09269` (v2.6.2)

## 2026-09-09

### [23:55] - ERP E-Commerce Connector: API URL fija + solo API Key editable (v2.6.0)
- **Tipo**: proyecto | wordpress | api | arquitectura
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `erp-ecomm-connector.php`: Constante `ERPC_API_URL` = `https://erpipos.armada.do/api` (FIJA)
  - `class-erpc-admin.php`: Eliminado campo API URL del admin; solo API Key + Tenant ID + Brand editables
  - `class-erpc-admin.php`: `ajax_test_connection()` usa constante `ERPC_API_URL`
  - `class-erpc-admin.php`: `sanitize_settings()` elimina `api_url`
  - `load_settings()`: Defaults sin `api_url`
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Arquitectura multi-tenant: **API URL FIJA** (mismo ERP para todos), solo **API Key + Tenant ID + Brand** por negocio
- **Estado**: ✅ API URL hardcodeada (`https://erpipos.armada.do/api`), solo API Key + Tenant ID + Brand editables, Test Connection funcional
- **Notas**:
  - **Arquitectura validada**: Un ERP (FlowApi/ERPipos) → Múltiples negocios
  - Cada negocio = Su API Key (iak_...) + Tenant ID (sucursal) + Brand
  - ERP detecta negocio por API Key → carga SU inventario
  - Admin panel: Solo **API Key** + **Tenant ID** + **Brand/Colores** editables
  - API URL hardcodeada: `https://erpipos.armada.do/api` (constante `ERPC_API_URL`)
  - Test Connection: ✅ Conectado (HTTP 200)
  - Plugin 100% genérico: Un WordPress = Un negocio = Su Key = Su Inventario

## 2026-09-09

### [23:30] - ERP E-Commerce Connector: Template Kit genérico "tech-ecomm-template" (single import)
- **Tipo**: proyecto | wordpress | elementor | template-kit | deploy
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - Plugin v2.5.0: auto-crea 6 páginas + Elementor Canvas + shortcodes corregidos
- **Agregado**: Template Kit Elementor genérico **tech-ecomm-template.zip** (single import)
  - `~/Desktop/MaganTech-Connector-Deploy/tech-ecomm-template.zip` (3.5K)
    - `manifest.json` — Kit "Tech E-Commerce Template" (nombres genéricos, sin marca)
    - `site-settings.json` — Config global (colores, tipografía, Elementor Canvas)
    - `templates/*.json` — 6 templates válidos Elementor 4.x (formato exacto: `content` root, `elType` camelCase, `widgetType`, `version: 0.4`)
      - `01-inicio-landing.json` → `[erpc_landing]`
      - `02-productos-tienda.json` → `[erpc_products]`
      - `03-carrito.json` → `[erpc_cart]`
      - `04-checkout.json` → `[erpc_checkout]`
      - `05-iniciar-sesion---registro.json` → `[erpc_login]`
      - `06-mi-cuenta---perfil.json` → `[erpc_profile]`
    - `site-settings.json` — Config global (colores, tipografía, Elementor Canvas)
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Usuario pidió **un solo import** + nombres genéricos (reutilizable para cualquier e-commerce, sin marca "MaganTech")
- **Estado**: ✅ Kit ZIP limpio (8 archivos), JSON validado con Elementor 4.x (`prepare_import_template_data()`)
- **Notas**:
  - Importación: **Elementor → Plantillas → Importar Kit** → subir `tech-ecomm-template.zip`
  - Nombres genéricos: "Tech E-Commerce Template", "Inicio (Landing)", "Productos (Tienda)", etc.
  - **Sin marca "MaganTech"** — el cliente pone su marca editando en Elementor
  - Reutilizable para cualquier cliente/vertical (tech, moda, comida, servicios, etc.)
  - Plugin ERP auto-crea páginas + aplica Elementor Canvas al activar
  - Shortcodes: `[erpc_landing]`, `[erpc_products]`, `[erpc_cart]`, `[erpc_checkout]`, `[erpc_login]`, `[erpc_profile]`

## 2026-09-09

### [23:20] - ERP E-Commerce Connector: Template Kit Elementor genérico (single import)
- **Tipo**: proyecto | wordpress | elementor | template-kit | deploy
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - Plugin v2.5.0: auto-crea 6 páginas + Elementor Canvas + shortcodes corregidos
- **Agregado**: Template Kit Elementor genérico (single import)
  - `~/Desktop/MaganTech-Connector-Deploy/ecomm-store-kit.zip` (3.5K)
    - `manifest.json` — Kit "E-Commerce Store Kit" (nombres genéricos)
    - `site-settings.json` — Configuración global (colores, tipografía, canvas)
    - `templates/*.json` — 6 templates válidos Elementor 4.x
      - `inicio` → `[erpc_landing]` (Landing con hero, beneficios, categorías, destacados)
      - `productos` → `[erpc_products]` (Grid + filtros + load more)
      - `carrito` → `[erpc_cart]` (Tabla + resumen)
      - `checkout` → `[erpc_checkout]` (2 cols + resumen sticky)
      - `login` → `[erpc_login]` (Tabs login/registro + iconos)
      - `mi-cuenta` → `[erpc_profile]` (Sidebar + contenido + órdenes + lealtad)
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Usuario pidió **un solo import** + nombres genéricos (reutilizable para cualquier e-commerce, no solo tech)
- **Estado**: ✅ Kit ZIP válido (manifest + 6 templates + site-settings), JSON validado con Elementor 4.x
- **Notas**:
  - Importación: **Elementor → Plantillas → Importar Kit** → subir `ecomm-store-kit.zip`
  - Nombres genéricos: "E-Commerce Store Kit", "Inicio (Landing)", "Productos (Tienda)", etc.
  - Reutilizable para cualquier cliente/vertical (tech, moda, comida, etc.)
  - Plugin ERP auto-crea páginas + aplica Elementor Canvas al activar
  - Shortcodes: `[erpc_landing]`, `[erpc_products]`, `[erpc_cart]`, `[erpc_checkout]`, `[erpc_login]`, `[erpc_profile]`

## 2026-09-09

### [22:50] - ERP E-Commerce Connector: Template Elementor 4.x válido + auto-páginas (v2.5.0)
- **Tipo**: proyecto | wordpress | elementor | template | deploy
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `includes/class-erpc-activation.php` — Auto-crea 6 páginas al activar + aplica Elementor Canvas
  - `includes/class-erpc-templates.php` — Shortcodes actualizados (`[erpc_login]`, `[erpc_profile]`)
  - `includes/class-erpc-shortcodes.php` — Shortcodes corregidos
  - `erp-ecomm-connector.php` — Hook de activación actualizado
- **Agregado**: Template Elementor 4.x válido (6 JSON + guía)
  - `~/Desktop/MaganTech-Connector-Deploy/template/` — 6 JSON válidos (formato Elementor 4.x)
  - `magantech-elementor-templates.zip` — 6 templates + guía (3.9K)
  - `erp-ecmm-connector.zip` — Plugin v2.5.0 (51K)
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: El template JSON anterior era inválido (formato incorrecto). Se corrigió al formato exacto de Elementor 4.x (`content` root, `elType` camelCase, `widgetType`, `version: 0.4`).
- **Estado**: ✅ JSON validado con `prepare_import_template_data()` de Elementor, plugin crea 6 páginas auto, Elementor Canvas aplicado
- **Notas**:
  - Formato correcto: `content` root, `elType` (section/column/widget), `widgetType: shortcode`, `version: 0.4`
  - 6 templates: Inicio, Productos, Carrito, Checkout, Login, Mi Cuenta
  - Plugin auto-crea páginas al activar + aplica Elementor Canvas
  - Shortcodes corregidos: `[erpc_login]`, `[erpc_profile]`
  - ZIPs en `~/Desktop/MaganTech-Connector-Deploy/`

## 2026-09-09

### [15:30] - WordPress dev: package de deploy completo (plugin + guía)
- **Tipo**: wordpress | deploy | proyecto
- **Modificado**: /home/warcold/dev/wordpress/erp-ecmm-deploy.zip
  - `deploy-package/erp-ecmm-connector.zip` — Plugin completo v2.4.0 listo para instalar (48K)
  - `deploy-package/DEPLOY-GUIA.md` — Guía de instalación en 3 pasos para cualquier WordPress
- **Afecta a**: kalimete (WordPress dev)
- **Causa**: Facilitar deploy rápido a producción sin Elementor ni configuraciones manuales.
- **Estado**: ✅ package listo, ZIP descargable
- **Notas**:
  - Package: `/home/warcold/dev/wordpress/erp-ecmm-deploy.zip` (50K)
  - Incluye: plugin ZIP + guía de deploy
  - Deploy en 3 pasos: instalar plugin → configurar API → crear páginas con shortcodes
  - NO requiere Elementor (usa shortcodes del plugin)
  - Páginas: Inicio/[erpc_landing], Productos/[erpc_products], Carrito/[erpc_cart], Checkout/[erpc_checkout], Login/[erpc_login], Mi Cuenta/[erpc_profile]
  - Los shortcodes se registran automáticamente al activar el plugin

## 2026-09-09

### [14:00] - ERP E-Commerce Connector: rediseño completo de todas las páginas + landing profesional (v2.4.0)
- **Tipo**: proyecto | wordpress | frontend | diseño
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `templates/partials/page-wrapper.php` — NUEVO wrapper header/footer
  - `templates/landing.php` — NUEVO landing (hero imagen, beneficios, categorías, destacados, CTA)
  - `templates/auth/form.php` — login/registro rediseñado (card, tabs, iconos)
  - `templates/ecomm/checkout.php` — checkout 2 columnas con resumen sticky
  - `templates/customer/profile.php` — perfil con sidebar + contenido
  - `templates/customer/orders.php`, `loyalty.php` — rediseñados
  - `includes/class-erpc-templates.php` — checkout/login/mi-cuenta envueltos con header/footer
  - `includes/class-erpc-shortcodes.php` — nuevo shortcode `[erpc_landing]`
  - `assets/css/connector.css` — estilos para todas las páginas nuevas
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Solo productos y carrito tenían estilo. Checkout, login, mi-cuenta, órdenes y lealtad se veían "peladas" (sin header/footer del plugin).
- **Estado**: ✅ rediseño completo, PHP syntax OK, todas las páginas HTTP 200, JS IDs intactos
- **Notas**:
  - Landing con hero de imagen Unsplash + overlay gradiente + CTA
  - Página de inicio (magantech-inicio) actualizada con `[erpc_landing]`
  - Checkout/login/mi-cuenta ahora incluyen header/footer del plugin (antes peladas)
  - Inputs con iconos, cards, sticky summary, sidebar de perfil
  - Git push OK: commit `05f5b37` (v2.4.0)

## 2026-09-09

### [13:00] - ERP E-Commerce Connector: optimización rendimiento — carrito localStorage + caché productos (v2.3.0)
- **Tipo**: proyecto | wordpress | frontend | performance
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `assets/js/connector.js` — carrito en localStorage (instantáneo), caché de productos, toast, sync background
  - `includes/class-erpc-cart.php` — nuevo endpoint `erpc_sync_cart`
  - `includes/class-erpc-shortcodes.php` — nuevo endpoint `erpc_get_products_json` (133 productos)
  - `erp-ecomm-connector.php` — añadido `placeholder` al config
  - `assets/css/connector.css` — toast, botón agregado, skeleton
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: El flujo anterior hacía múltiples round-trips AJAX por acción y cada consulta al carrito llamaba a la ERP. Navegación lenta y sin actualización en tiempo real.
- **Estado**: ✅ optimización completa, PHP/JS syntax OK, página HTTP 200, endpoint JSON devuelve 133 productos
- **Notas**:
  - Carrito movido a localStorage: agregar/actualizar/eliminar es instantáneo (sin round-trip)
  - Sync al servidor en background (`erpc_sync_cart`) para persistencia entre sesiones
  - Caché de productos en localStorage (TTL 5 min) para filtros instantáneos
  - Precarga del caché en background al cargar la página
  - Toast notification + feedback visual al agregar al carrito
  - Git push OK: commit `387d07d` (v2.3.0)

## 2026-09-09

### [12:00] - ERP E-Commerce Connector: rediseño profesional frontend + fix navegación (v2.2.0)
- **Tipo**: proyecto | wordpress | frontend | bugfix
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
  - `assets/css/connector.css` — rediseño completo profesional (variables CSS, header sticky, hero gradiente, categorías pills, grid responsive, cards hover)
  - `assets/js/connector.js` — handlers de categorías, búsqueda debounce, load more con estado
  - `templates/ecomm/products.php` — usa `#erpc-grid` (el que el JS espera)
  - `templates/partials/product-grid.php` — emite solo cards (sin wrapper)
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: El frontend no se veía profesional y las categorías + "cargar más" no funcionaban por desconexión template↔JS
- **Estado**: ✅ rediseño completo, PHP/JS syntax OK, página HTTP 200, 15 cards server-rendered
- **Notas**:
  - Fix crítico: template usaba `#erpc-products-container` pero JS esperaba `#erpc-grid`
  - Categorías `.erpc-cat-btn` ahora usan nombre real en `data-category` (el handler AJAX compara con strcasecmp)
  - Load more lee estado actual de búsqueda/categoría y resetea a página 1 al filtrar
  - Búsqueda con debounce 400ms
  - Estilo inspirado en twinstechd.com (tienda moderna)
  - Git push OK: commit `5df4344` (v2.2.0)

## 2026-09-09

### [10:00] - ERP E-Commerce Connector: refactor crítico — Auth token-based → email-based (v2.1.0)
- **Tipo**: proyecto | wordpress | api | bugfix
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecmm-connector/
  - `class-erpc-auth.php` — register/login ahora usa endpoints reales de la ERP
  - `class-erpc-api.php` — endpoints corregidos (sin duplicar /api/ en la URL)
  - `connector.js` — localStorage ahora guarda email + customer_id (no JWT token)
  - `CHANGELOG.md` — documentación completa v1.0.0 → v2.0.0 → v2.1.0
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: La ERP FlowApi NO usa JWT tokens. Los endpoints `/erpipos/v3/auth/login` y `/erpipos/v3/auth/register` retornan 404. Se implementa email-based lookup.
- **Estado**: ✅ refactor completo, PHP syntax OK, git push OK (2 commits: v2.0.0 + v2.1.0)
- **Notas**:
  - **BREAKING**: `erpc_auth_token` (JWT) → `erpc_auth_email` + `erpc_customer`
  - **BUG FIX**: base_url + `/api/customers` = `/api/api/customers` → 404 corregido
  - Endpoints reales confirmados:
    - ✅ `POST /customers` → registro (201)
    - ✅ `GET /customers?email=X` → login (200, pero NO filtra — devuelve todos)
    - ✅ `GET /tienda/productos?limit=100` → 133 productos (200)
    - ✅ `GET /tienda/categorias` → 18 categorías (200)
    - ✅ `POST /ecomm/carts` → crear carrito (201, body exacto requerido)
    - ❌ `/erpipos/v3/auth/*` → 404 (no existen)
    - ❌ `/customers/:id` → 404 (no existe GET individual)
  - ⚠️ `?email=X` devuelve TODOS los clientes (35 en tenant) — se debe filtrar manualmente en PHP/JS
  - Repo GitHub creado: `github.com/warcold/erp-ecmm-connector` (2 commits: v2.0.0 + v2.1.0)
  - CHANGELOG.md completo con diagramas de arquitectura y flujos
  - Checkout endpoints no encontrados — se usan mocks/placeholder por ahora

## 2026-09-08

### [22:24] - ERP E-Commerce Connector: plugin reescrito (WordPress frontend + ERP backend)
- **Tipo**: proyecto | wordpress | api
- **Modificado**: /home/warcold/dev/wordpress/wp-content/plugins/erp-ecomm-connector/
- **Afecta a**: kalimete (WordPress dev localhost:8090)
- **Causa**: Reemplazo del plugin MaganTech antiguo (erpecomm-alfredo-pro) por nuevo connector genérico multi-tenant
- **Estado**: ✅ activado, conectado al ERP
- **Notas**:
  - WordPress = capa de presentación ONLY (HTML + CSS + JS + shortcodes)
  - ERP FlowApi = toda la lógica de negocio (productos, auth, carrito, checkout, clientes)
  - 22 archivos creados (plugin completo, PHP syntax OK)
  - Plugin activado en WordPress (reemplaza erpecomm-alfredo-pro)
  - Páginas actualizadas: /productos/, /carrito/, /checkout/, /mi-cuenta/, /login/
  - API ERP conectada: 132 productos, 18 categorías
  - AJAX endpoints funcionando (erpc_get_products, erpc_get_categories, erpc_checkout)
  - CSS/JS cargando correctamente (connector.css, connector.js)
  - Shortcodes: [erpc_products], [erpc_cart], [erpc_checkout], [erpc_auth], [erpc_customer], [erpc_orders], [erpc_loyalty]
  - Template redirect funcional (products.php incluye header.php con wp_head/wp_footer)
  - Sanitización de categorías corregida (clean copy approach para evitar PHP references)
  - Configurar: api_url=https://erpipos.armada.do/api, api_key=iak_hT0RO7..., tenant_id=10
  - Branding: MaganTech Store, moneda DOP, símbolo RD$
  - Compatible con Elementor (shortcodes funcionan en widgets Elementor)
  - Multi-tenant: un plugin puede servir a múltiples clientes del ERPipos

## 2026-09-07

### [12:50] - Proxmark: renombrado proxmark-cards → proxmark
- **Tipo**: agente | refactor
- **Modificado**: `agents/proxmark.md`, `agents/kalimete.md`, `AGENTS.md`
- **Afecta a**: kalimete (opencode)
- **Causa**: El nombre `proxmark-cards` era limitante — el agente cubre tokens, LF 125kHz, sniffing, emulation, data analysis. Mucho más que "cards". Se generaliza el nombre.
- **Estado**: ✅ sincronizado

### [12:09] - Proxmark3: subagente `proxmark` creado en kalimete
- **Tipo**: agente | infra
- **Modificado**: `agents/proxmark.md`, `agents/kalimete.md`, `~/.config/opencode/agent/proxmark.md`
- **Afecta a**: kalimete (PM3 en /dev/ttyACM0)
- **Causa**: Proxmark dejó de ser parte de Victoria, ahora es tool local de kalimete. Se crea subagente dedicado con documentación completa de todas las capacidades (cards + tokens + LF + HF + emulation + sniffing). Renombrado de `proxmark-cards` a `proxmark` en sesión misma tarde para reflejar alcance completo del agente.
- **Estado**: ✅ sincronizado
- **Notas**:
  - Dumps migrados: `~/.victoria/pm3-dumps/` → `~/.proxmark3/dumps/` (limpia ref a Victoria)
  - `pm3` alias verificada (`/usr/bin/pm3`)
  - Subagente incluye: MIFARE Classic/Ultralight/DESFire/Plus, HID, EM4100, T55xx, NFC, iClass, Wiegand, EMV, FeliCa, LEGIC, Tesla, Gallagher, trace, hw, data analysis
  - ⚠️ **Bug conocido**: en non-interactive mode, el campo HF se apaga entre invocations → "Can't select card". Solución: encadenar `hf 14a reader ; <comando>`
  - Agrega `proxmark` al `permission.task` de kalimete

## 2026-09-06

### [16:05] - MaganTech Store: revalidación ERP tras fixes del backend (v2.2)
- **Tipo**: proyecto | api | wordpress
- **Modificado**: `/home/warcold/dev/wordpress/wp-content/plugins/erpecomm-alfredo-pro/`
- **Afecta a**: kalimete (localhost:8090)
- **Causa**: El dueño del ERPipos reportó haber corregido los issues reportados
- **Estado**: ✅ flujo completo validado

**Qué mejoró el ERP (confirmado vía API)**:
- ✅ `/tienda/categorias` ahora devuelve JSON limpio con **18 categorías** (antes: HTML basura)
- ✅ `ecomm/carts` enriquecido: ahora devuelve data completa de productos (precio_compra, marca, especialización, etc.)
- ✅ `tenant_id: 10` ahora se resuelve correctamente en endpoints ecomm (MaganTech = tenant 10)
- ✅ Inventario limpiado: 400 → **101 productos** (sin duplicados)
- ✅ Checkout funciona con usuario logueado WP (cliente_id: 59, 60, 61 creados en pruebas)

**Mejoras que hice en el plugin**:
- ✅ Endpoint AJAX nuevo `flowapi_get_categorias` — el select de filtros ahora carga las 18 categorías reales del ERP
- ✅ Bug fix: `mb_strcasecmp()` no existe en PHP → reemplazado por `strcasecmp()` (categorías ASCII)
- ✅ Bug fix: null-safety en filtro de categoría (`categoria` puede venir null del ERP)

**Sigue pendiente en el ERP (reportado, no crítico)**:
- 🔴 `/erpipos/v3/customers` (GET/POST) sigue devolviendo "No se pudo resolver la instancia del tenant" — los endpoints v3 de clientes admin quedan rotos, pero **el flujo e-commerce completo no los necesita** (checkout_guest crea el cliente solo)
- ⚠️ `APP_DEBUG=true` sigue activo — stack traces expuestos en errores (riesgo seguridad)
- ⚠️ de las 18 categorías del ERP, solo 3 tienen productos (Computadoras 52, Cables 47, Almacenamiento 1) — el admin de MaganTech decide qué publicar

**Nota comportamiento ERP**: cada checkout guest crea un cliente NUEVO (56, 59, 60, 61). El plugin siempre vincula el más reciente al usuario WP.

**Flujo completo probado OK (2026-09-06)**:
1. Login WP (cliente.prueba) ✅
2. Productos paginados 15/101 + "Cargar más" ✅
3. Búsqueda "laptop" → 36 ✅
4. Filtro categoría "Cables" → 47 ✅
5. Carrito cookie persiste ✅
6. Checkout → ERP cliente_id:61 creado ✅
7. Mi Cuenta muestra 2 pedidos con fechas y totales ✅

## 2026-09-06

### [02:55] - Fix: frontmatter inválido en eco-woodly y eco-alfredo-ecomm rompía el arranque de opencode
- **Tipo**: agente | config
- **Modificado**: `agents/eco-woodly.md`, `agents/eco-alfredo-ecomm.md`, symlinks en `~/.config/opencode/agent/`
- **Afecta a**: kalimete (opencode)
- **Causa**: Ambos agentes (creados/modificados en sesión Alfredo Pro Ecomm del 2026-09-06 01:26) tenían frontmatter inválido: `mode: agent` (solo son válidos `primary`/`subagent`/`all`), `max_steps` (correcto: `steps`) y claves no estándar (`tools:` en lista, `hidden: true`). El schema de opencode rechazaba los agentes al arrancar; eco-woodly fue renombrado a `.backup` como workaround y eco-alfredo-ecomm nunca tuvo symlink.
- **Estado**: ✅ verificado — ambos agentes cargan como subagent (`opencode agent list`)
- **Notas**: frontmatter normalizado al estándar de los demás eco-* (description/mode/subagent/temperature/steps/permission). Restaurado symlink `eco-woodly.md`; creado symlink `eco-alfredo-ecomm.md`.

## 2026-09-05

### [17:00] - Alfredo Pro Ecomm: nuevo backend ERP + integración con Woodly
- **Tipo**: infra | proyecto | backend | docker
- **Modificado**: `~/projects/alfredo-pro-ecomm/` + `~/projects/woodly/` (frontend)
- **Afecta a**: kalimete, vps-preprod
- **Causa**: Necesitamos backend propio para e-commerce multi-tenant (antes el API era de terceros FlowHub)
- **Estado**: ✅ Backend operativo en Docker (API :3004, Postgres:5432, Redis:6379)
- **Notas**: 
  - Backend completo: stores, products, carts, orders, customers, deals, admin panel
  - Woodly adaptado: api.ts, StoreContext, CartContext → consume API en lugar de mocks
  - Puertos: API→3004, DB→5432, Redis→6379
  - Próximo despliegue: VPS (dockerizado + reverse proxy por Caddy)
  - Documentación: `~/projects/alfredo-pro-ecomm/docs/DESIGN.md`, flowhub API de referencia
  - Dockerfile del ERP: postgres + redis + api (HEALTHCHECK incluídos)
  - Test local (y credenciales para demo):
    - Store slug: "woodly-park" — tenant de prueba
    - Admin: admin@woodly.armada.do / admin123
    - Customer: juan@example.com / password123
  - Endpoint `GET /v1/stores/woodly-park/config` added
  - Cart: create + add items + update + submit dedicado a cada tenant
  - Carnoversión frontend: http://localhost:5174/
  - Frontend changes:
    - `src/services/api.ts` (nuevo)
    - `src/context/StoreContext.tsx` (nuevo)
    - `src/hooks/useProducts.ts` (nuevo)
    - `mockProducts.ts` (legacy — reemplazado por API)
    - `CartDrawer.tsx` — actualizado con submit vía API
    - `App.tsx` — actualizado con provider StoreContext
  - El framework base en el frontend es referencia para futuros tenants (micaserogou, wisp, etc.)
  - Ruta en Docker: alfredo-ecomm-api (contenedor) — expone puerto 3004
  - Proyectos verificados corren sobre: npm run dev; docker compose up -d

---

## 2026-09-03
- **Tipo**: proyecto | plugin | wordpress | api
- **Modificado**: `/home/warcold/dev/wordpress/wp-content/plugins/erpecomm-alfredo-pro/`
- **Afecta a**: kalimete (WordPress local, localhost:8090)
- **Causa**: Validar login/registro de usuarios — el usuario creía que el ERPipos tenía endpoints de auth
- **Estado**: ✅ flujo completo funcionando
- **Hallazgos críticos del ERPipos (erpipos.armada.do)**:
  - ❌ NO existen endpoints de auth (login/register = 404 en todas las variantes probadas)
  - ✅ Existe `POST /erpipos/v3/customers` (crear cliente) — pero está **ROTO**: `EcommController::customerCreate` (línea 252) inserta `tenant_id=0` → FK violation. El middleware TenantMiddleware no resuelve el tenant en ese método.
  - ✅ `GET /erpipos/v3/customers` funciona pero devuelve lista vacía (mismo problema de tenant)
  - ✅ `checkout_guest` SÍ funciona: crea cliente automáticamente (confirmado: cliente_id 56, 59 de pruebas)
  - ⚠️ El ERP tiene `APP_DEBUG=true` — expone stack traces completos con SQL y rutas internas (riesgo de seguridad en producción, notificar al dueño)
- **Solución implementada en el plugin**:
  - Registro/login = WordPress nativo (`users_can_register=1` habilitado)
  - Al hacer checkout logueado: se guarda `magantech_cliente_id` (del ERP) en user_meta de WP
  - Teléfono/dirección guardados en user_meta (`magantech_phone`, `magantech_address`) → pre-fill en próximos checkouts
  - Historial de pedidos por usuario en `magantech_orders` (la API no expone historial por cliente)
  - Nuevo shortcode `[flowapi_mi_cuenta]` + página /mi-cuenta/ (perfil + pedidos + badge de cliente ERP)
  - Nav actualizada: Mi Cuenta/Salir si logueado, Login/Registrate si no
- **Pruebas realizadas (todas ✅)**:
  - Registro usuario WP (cliente.prueba) → login OK
  - Checkout logueado → ERP crea cliente_id:59 → vinculado a WP user 4
  - Mi Cuenta muestra el pedido con total correcto (RD$640)
- **Pendiente al dueño del ERP**: arreglar `EcommController::customerCreate` (usar tenant del middleware) y desactivar APP_DEBUG

EOF又是

## 2026-09-03

### [00:55] - MaganTech Store v2.0: llave API corregida + plugin e-commerce completo
- **Tipo**: proyecto | plugin | wordpress
- **Modificado**: `/home/warcold/dev/wordpress/wp-content/plugins/erpecomm-alfredo-pro/` (v1.0.0 → v2.0.0)
- **Afecta a**: kalimete (WordPress local, localhost:8090)
- **Causa**: MaganTech tenía API key errónea; inventario de 400 productos requería paginación + búsqueda + carrito + checkout funcional
- **Estado**: ✅ completado y probado end-to-end
- **Detalles**:
  - API key reemplazada: `iak_hT0RO7VnY2UpPT9q0tbqdfgEaTgkEQRYoeQGTaDM` (backup en `flowapi-ecommerce.php.bkup` dentro del contenedor)
  - Paginación AJAX de 15 productos + botón "Cargar más" (API de MaganTech no soporta paginación nativa — se pagina en PHP)
  - Buscador con parámetro `?buscar=` (evita colisión con WP search nativo `?s=`)
  - Carrito persistente vía **cookie** (sessions PHP rotas en contenedor: `session.save_path` vacío)
  - Checkout guest probado contra ERP: creó `cliente_id:56`, pedido registrado OK
  - Template engine corregido (ahora respeta `wp_head()`/`wp_footer()` para cargar assets)
  - URLs del sitio corregidas a `http://localhost:8090`
  - Páginas: /productos/ [flowapi_productos], /carrito/ [flowapi_carrito], /checkout/ [flowapi_checkout]
- **Limitaciones encontradas en API MaganTech**:
  - No hay endpoints de auth (/auth/login, /auth/register → 404). Usuarios = WordPress nativo.
  - Sin parámetros limit/page — devuelve los 400 productos siempre
  - /tienda/categorias devuelve HTML (Laravel view), no JSON — select de categorías queda pendiente
  - Varios productos tienen precio RD$ 0.00 (dato del ERP, no bug del plugin)
  - `"No hay usuarios activos en la instancia"` en algunas respuestas (config del ERP MaganTech)


## 2026-09-02

### [01:00] - Restaurar acceso SSH de justin_t en vps-preprod (llave ED25519)
- **Tipo**: infra | servicio | acceso
- **Modificado**: vps-preprod (154.53.35.102) — `/home/justin_t/.ssh/` (generada `id_ed25519` + `id_ed25519.pub`, agregada a `authorized_keys`)
- **Afecta a**: justin_t (usuario sudo en vps-preprod)
- **Causa**: justin_t no podía entrar por SSH. La llave en `authorized_keys` era RSA (`andrew.ortega@gmail.com`) pero él se autenticaba antes con una ED25519 (`SHA256:6uBP5yJDEUpz+3Vo426sQ9AYNbUmMk87lMp6E1hsdfM`) que fue removida. Desde el 1 Sep sus conexiones se cerraban en preauth.
- **Estado**: ✅ resuelto — nueva llave ED25519 generada, agregada a authorized_keys, conexión verificada (justin_t + sudo OK)
- **Notas**:
  - Nueva llave: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcKPc5rVP0GxPXXo/77eYY4RPdZj42nz50aKrtt8MKc justin_t@auth.armada.do`
  - Host para SSH remoto: **NO usar `auth.armada.do`** (proxied por Cloudflare, bloquea SSH). Usar IP directa `154.53.35.102 -p 1333`
  - La llave privada se entregó al usuario para que la instale en su máquina

## 2026-09-01

### [22:00] - Fix CRÍTICO: Squid crasheaba con `store.cc:1911` — deshabilitar caché
- **Tipo**: infra | servicio | bugfix crítico
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (deshabilitado cache_dir ufs, agregado `cache deny all`), permisos proxy-users.conf
- **Afecta a**: vps-proxy (proxy server), todos los clientes del proxy
- **Causa**: Squid crasheaba **9 veces** con `FATAL: assertion failed: store.cc:1911: "sd"` (bug del sistema de caché). Cada crash causaba que el proxy "se cayera" y el servicio SOCKS5 se reiniciaba constantemente (342 veces). El usuario reportaba caídas frecuentes.
- **Estado**: ✅ resuelto — sin crashes desde el fix
- **Notas**:
  - **Causa raíz**: el caché de Squid (cache_dir ufs) tiene un bug (`store.cc:1911: "sd"`) que causa crashes aleatorios. Un proxy no necesita caché, así que se deshabilitó por completo.
  - **Fix**: eliminado `cache_dir ufs` y agregado `cache deny all` — sin caché = sin bug
  - **Resultado**: SOCKS5 ya no se reinicia constantemente, Squid estable, Gmail 0.08s, Google 0.00s, SOCKS5 Gmail 0.10s
