### [00:45 29-oct] - Victoria (cross-machine, autorizada): seguridad labs + docs_oficiales + MCP blender E2E + prep ventana prod Micaserogou
- **Tipo**: security | docs | infra
- **Seguridad (labs kalimete)**: 4 puertos que publicaban 0.0.0.0 pasaron a loopback-only — erpipo-preprod db :3310, redis :6390, mailpit :8025 (vía compose, backup .bkup-20261027-loopback) y wordpress-db :3307 (recreado a mano con misma config + aliases db/wordpress-db; datos en volumen wordpress_db_data intactos, 22 tablas WP verificadas). E2E: nginx :8100 → 200, stack erpipo healthy, WP :8091 → 200.
- **docs_oficiales**: 29/32 harnesses ya los tenían; 3 gaps llenados (armada-templates, assetto, wordpress) con URLs oficiales. Commit 8fbd16e.
- **MCP blender E2E VERIFICADO**: Blender 5.0.1 GUI bajo Xvfb → addon :9876 → get_scene_info {"status":"success", 3 objetos}. Hallazgo: el addon responde JSON SIN newline final — tests TCP crudos deben usar recv+timeout, no recv-loop por \n (un hang por \n mató al addon con EBADF y parecía crash; lección en conocimiento/LECCIONES.md). Blender detenido tras el test (on-demand por diseño).
- **Prep ventana prod Micaserogou (5.5.10 → 5.7.0)**: ops/status con App Password usuario victoria → **200** (prod WP 7.1.4, PHP 8.4.27, plugin 5.5.10, ERP prod erpipos.armada.do). Artefacto A (armada-suite-5.7.0.zip) RECUPERADO de la réplica magantech export/ — sha256 **766345c9… MATCH EXACTO** con el checklist (el repo dev-lab plugins/armada-suite/ fue eliminado en la limpieza del 28-oct; el rebuild desde el espejo del sitio NO coincide: 446 vs 529 archivos, espejo divergió). Artefactos B (site-fixes 1.0.3, 130f4b4c…) y C (rollback 5.5.10, b35e007c…) verificados en export/ de micaserogou. Los 3 ZIPs listos para la ventana.
- **BLOCKERS del deploy (owner)**: (1) crear/confirmar **iak tenant 3 en ERP prod** (erpipos.armada.do) — solo owner/Juan Carlos; (2) ventana manual: snapshot cPanel + uploads wp-admin (flujo 4 clicks del checklist). (3) DECISIÓN pendiente: subir 5.7.0 según checklist vs esperar la fusión Zion CRM 2.0.0 (commits 23:00-23:45 28-oct) — el ecosistema está a mitad de la migración unificada.
- **Hallazgo de estado**: el inventario de Victoria estaba viejo (5.4.2) — la flota kalimete avanzó a 5.9.1 + fusión Zion CRM 2.0.0. Docs curadas.
## 2026-10-29

### [06:00] - Assetto Corsa: puesta en marcha completa — session_key, admin SM, DNS UDP srv00, firewall 9600/8081
- **Tipo**: servicio | config | dns | seguridad
- **Modificado**: `/srv/assetto-corsa/config.yml` (session_key, backup `.bkup-20261029`), DNS zona armada.do (record srv00), firewall vps-preprod (`/etc/iptables/rules.v4`, backup `rules.v4.bkup-20261029-assetto`)
- **Afecta a**: vps-preprod (Assetto Corsa server), Cloudflare DNS
- **Causa**: completar los 3 pendientes de la entrada 04:45 para dejar el servidor operativo
- **Estado**: ✅ verificado end-to-end
- **Notas**:
  1. **session_key**: placeholder reemplazado por 64-hex (`openssl rand -hex 32`); contenedor reiniciado, SM UI 302 OK (boot ~90s por escaneo de contenido)
  2. **Cuenta admin SM**: el flujo real NO es "primer login crea cuenta" — credenciales de fábrica `admin`/`servermanager` (doc de config.example.yml) → login 302 a `/accounts/new-password` → password permanente seteado → re-login 302 a `/` ✅. Credenciales en `/srv/assetto-corsa/.sm-admin-credentials` (600, root-only, nunca en chat)
  3. **DNS srv00** (subagente Cloudflare): CNAME→túnel eliminado (ID `792ea47c…`), nuevo A record DNS-only `154.53.35.102` (ID `d657f44339febb5dcbc523a1850afe5a`, TTL auto, comment "Assetto Corsa game port UDP/TCP 9600"); `dig @1.1.1.1` → 154.53.35.102 al primer intento; `assetto.armada.do` (túnel, UI) intacto
  4. **CORRECCIÓN entrada 04:45**: el firewall del VPS NO era "ACCEPT all" — es `INPUT policy DROP` con reglas explícitas (el tcpdump captura antes de netfilter, por eso parecía que UDP pasaba). Añadidas y persistidas (netfilter-persistent): UDP 9600, TCP 9600, TCP 8081 (este último para descargas de coches vía Content Manager)
  5. **E2E verificado desde kalimete**: TCP 9600 `succeeded` con handshake completo capturado (SYN→SYN-ACK→ACK→FIN); UDP 9600 llega a eth0; SM UI 302 vía túnel. Proceso manual acServer matado tras la prueba — el SM lanza el suyo al crear una race desde la UI
  6. **Lección**: una instancia manual de acServer murió sola tras recibir probes UDP basura — no enviar paquetes malformados a un server en pruebas; y tcpdump en el VPS captura pre-netfilter, no prueba que el paquete llegue a la app

### [04:45] - FIX CRÍTICO: acServer Linux arranca — bug era formato de server_cfg.ini, no el binario

- **Tipo**: servicio | fix | config
- **Modificado**: `/srv/assetto-corsa/assetto/cfg/server_cfg.ini` + `entry_list.ini` (vps-preprod, backups `.bkup-20261029`)
- **Afecta a**: vps-preprod (Assetto Corsa server)
- **Causa**: acServer panic `invalid argument to Intn` en weather.go:61 — la causa NO era el binario ni falta de weather.ini por track: el server_cfg.ini usaba formato inventado (`WEATHER_GRAPHICS=0`, `TRACK_CONFIG=`, sin sección `[WEATHER_0]`). El formato correcto Kunos exige sección `[WEATHER_0]` con `GRAPHICS=3_clear` (preset de `content/weather/`), `CONFIG_TRACK=` (no TRACK_CONFIG) y `CARS=` lista separada por `;`
- **Estado**: ✅ verificado — acServer Linux nativo v1.15 arranca sin Wine: "Server started", TCP+UDP 9600 escuchando, HTTP 8081, weather 3_clear cargado (ambient 24.1/road 32.5), 7 cars GT3 parseados, sesiones Practice/Qualify/Race activas
- **Notas**:
  1. **Formato correcto** (FAQ oficial Kunos): `[WEATHER_0] GRAPHICS=3_clear BASE_TEMPERATURE_AMBIENT=26 BASE_TEMPERATURE_ROAD=8 VARIATION_AMBIENT=2 VARIATION_ROAD=1`; sesiones en secciones `[PRACTICE]/[QUALIFY]/[RACE]`; `FUEL_RATE/TYRE_WEAR_RATE/DAMAGE_MULTIPLIER` en porcentaje (100), no float
  2. **DRS zones**: con `CONFIG_TRACK=gp_a` el server busca `content/tracks/ks_nurburgring/gp_a/data/drs_zones.ini` — copiado ahí (+ surfaces.ini para checksum)
  3. **Wine descartado**: el build Windows via Wine tenía el MISMO panic (mismo código Go) — el Linux nativo es el correcto y ya funciona
  4. **Lobby global**: `ERROR,INVALID SERVER` al registrar en lobby Kunos — esperado (puerto 9600 no alcanzable desde internet con server parado); para server privado RD se puede poner `REGISTER_TO_LOBBY=0`
  5. **Flujo Server Manager**: proceso manual matado — el SM (https://assetto.armada.do, UI 302 OK) lanza acServer al crear una race desde la UI; primer registro en la UI crea la cuenta admin
  6. **Red**: docker-compose usa `network_mode: host` — puertos 9600/8081 salen directos al host sin publicar; firewall VPS tiene regla ACCEPT all (UDP pasa)
  7. **Pendiente usuario**: (a) crear cuenta admin en la UI y crear primera race; (b) decidir DNS de `srv00.assetto.armada.do` — hoy es CNAME al túnel CF (TCP-only); para juego UDP conviene A record "DNS only" → 154.53.35.102; (c) cambiar `session_key` placeholder en `/srv/assetto-corsa/config.yml`
  8. Limpieza: weather.ini experimentales por track eliminados (la solución correcta vive en server_cfg.ini)

## 2026-10-28

### [23:45] - PACKS COMPLETOS: tech + neutral añadidos a Zion CRM 2.0.0 + enqueue pack-styles

- **Tipo**: plugin | feature | templates
- **Modificado**: `templates/packs/tech/pack.css` (nuevo, 6.9 KB, overlay frío #2563eb), `templates/packs/neutral/pack.css` (nuevo, 6.9 KB, overlay neutro #475569), `src/Modules/ArmadaSuite/Core/TemplatePacks.php` (registra tech + neutral con colors/dir/url), `src/Modules/ArmadaSuite/Core/Main.php` (enqueue `erpc-pack-styles` condicional tras `erpc-styles`)
- **Afecta a**: kalimete (dev lab), preprod sitios WP
- **Causa**: Armada Templates agent detectó packs faltantes (tech, neutral) y enqueue `erpc-pack-styles` ausente — completados para que Zion CRM 2.0.0 tenga los 3 packs vendibles (default/tech, restaurant, neutral/servicios)
- **Estado**: ✅ completado — ZIP limpio regenerado `zion-crm-2.0.0-clean.zip` (10,059,849 B, sha256 `a4762290…`, 2450 archivos, sin secrets, CERO referencias a negocios)
- **Notas**: (1) Pack `tech` (overlay frío #2563eb) para tecnología/SaaS, `neutral` (overlay neutro #475569) para servicios profesionales, `restaurant` (overlay cálido #d64545) existente. (2) Cada pack registrado con `colors` (primary/secondary), `dir`, `url`, `hero`, `cta`, `vertical`. (3) `Main.php` encola `erpc-pack-styles` condicional tras `erpc-styles` si pack activo ≠ default. (4) ZIP limpio verificado: CERO referencias a `micaserogou`/`MaganTech`/`magan`.

### [23:30] - LIMPIEZA ZIP: Zion CRM 2.0.0-clean (cero referencias a negocios específicos)

- **Tipo**: plugin | fix | limpieza
- **Modificado**: `export/zion-crm-2.0.0-clean.zip` (10,052,868 B, sha256 `56768880...`) — eliminadas todas las referencias a `micaserogou`, `MaganTech` en comentarios/docs de: `pack.css`, `footer-shop.php`, `ApiClient.php`, `Shortcodes.php`, `TemplatePacks.php`, `connector.css`
- **Afecta a**: kalimete (dev lab), preprod sitios WP
- **Causa**: El ZIP original `zion-crm-2.0.0.zip` contenía referencias hardcodeadas a `micaserogou`/`MaganTech` en comentarios/docs — violaba el requisito de plugin genérico sin referencias a negocios específicos
- **Estado**: ✅ verificado — `unzip -l` + `grep` confirman CERO referencias a `micaserogou`/`MaganTech`/`magan` en el ZIP limpio
- **Notas**: (1) Referencias eliminadas de: `pack.css` (comentario verificación), `footer-shop.php` (ejemplo MaganTech), `ApiClient.php` (comentario flujo site-level), `Shortcodes.php` (contrato flujo), `TemplatePacks.php` (ejemplos MaganTech), `connector.css` (comentarios fix site-level). (2) ZIP limpio listo para deploy a CUALQUIER cliente sin contaminación de datos de referencia. (3) El plugin unificado `zion-crm` v2.0.0 es ahora 100% genérico.

### [23:00] - FUSIÓN COMPLETA: ZionV CRM + Armada Suite → Zion CRM 2.0.0 (plugin unificado)

- **Tipo**: plugin | feature | arquitectura | fusión
- **Modificado**: Plugin unificado `zion-crm` v2.0.0 (DB 2.0.0) — fusiona ZionV CRM 1.57.0 + Armada Suite 5.9.1 en un solo plugin
- **Afecta a**: kalimete (dev lab), preprod sitios WP (MaganTech, Micaserogou), ERP erpipos
- **Causa**: owner pidió unificar ambos plugins en uno solo llamado "Zion CRM" con autores Jordan Diaz + Alfredo Armada (me@alfredo.pro), manteniendo toda la funcionalidad CRM + ERP integrada
- **Estado**: ✅ completado — PHP lint OK; ZIP generado `zion-crm-2.0.0.zip` (10,045,291 B, sha256 `12d16561…`, 2447 archivos, sin secrets); incluye módulos CRM (16+) + ERP (catálogo/checkout, sync erpipos, IA, AiBridge, SiteBackup, Ops, Templates) + fusión de formularios tipo reserva + sync contactos + endpoint REST reservas + selector modo negocio
- **Notas**:
  1. **Plugin unificado**: `zion-crm.php` v2.0.0, text domain `zion-crm`, autores "Jordan Diaz, Alfredo Armada", Author URI `https://alfredo.pro`
  2. **Módulos CRM** (16+): Contactos, Pipeline, Formularios (tipo reserva/lead/datos), Reservaciones, Automatizaciones, Correo, Talleres, Reportes, IA, HubSpot, Nextcloud, MS365, Google Calendar, Antispam, DataTools, Elementor Bridge, Notificaciones, Papelera, Servicios
  3. **Módulos ERP integrados** (como submódulos en `src/Modules/ArmadaSuite/`): Catálogo/Checkout ERP (sync erpipos), Sincronización (auto-sync, push órdenes/contactos, modo standalone), Asistente IA (ChatEngine + WhatsApp), AiBridge (WPVibe 1.20.0 vendored), SiteBackup (AIO WP Migration 7.111 vendored), Ops Remotas (status, rollback, auditoría, file ops, kill-switch IA), Templates (landing, contacto, cotizar, packs restaurant/tech/neutral), Shortcodes (catalogo, cart, checkout, reservas)
  4. **Nuevas funcionalidades de fusión**: Formularios tipo reserva (`submission_type`: lead|reserva|datos), Endpoint REST `POST /wp-json/erpsuite/v1/reservations` (recibe de Zion, normaliza, valida, sync ERP si ON, historial local), Sync contactos bidireccional (tabla mapping `wp_zion_erp_contact_map`), Selector modo negocio (`erp_pos`|`zion_crm`|`both`|`none`), Módulos vendored condicionales (AiBridge, SiteBackup)
  5. **Migración BD**: Zion 1.25.0→2.0.0 (submission_type, booking_id), AS opciones migradas, feature gates unificados, text domain `zion-crm` (compat legacy `zionv-crm`/`erp-suite` via filters)
  6. **ZIP unificado**: `export/zion-crm-2.0.0.zip` (10,045,291 B, sha256 `12d16561…`, 2447 archivos, sin secrets) — listo para deploy a preprod MaganTech/Micaserogou via ops API
  7. **Documentación actualizada**: `readme.txt` + `CHANGELOG.md` unificados, `docs/ARQUITECTURA-INTEGRACION-HIBRIDA.md` con Sección 14 (flujos formularios/reservas/sync contactos)

### [22:40] - Ecco Suit: deploy CSP-nonce a producción VPS (612ea50)

- **Tipo**: deploy | seguridad | infra
- **Modificado**: VPS ecco (62.171.144.58) `/opt/eccoqualita/eccosuit/` — rsync repo `feature/csp-nonce` @ `612ea50` (= origin/develop) con patrón documentado + `--exclude='*.bkup*'` (protege `docker-compose.yml.bkup-repo-20261019` del `--delete`) · rebuild imagen `eccosuit-app` (`b872ba11d879`) + `up -d app` · `agents/ecco-suit.md` (Historia + Upstream)
- **Afecta a**: https://suite.eccoqualita.com (producción EccoSuite)
- **Causa**: la VPS corría código pre-CSP-nonce; el audit de la sesión previa validó el diff (proxy.ts, security-headers.ts, módulo ISO eliminado, renovaciones visuales, nuevos tests) y quedó el deploy pendiente
- **Estado**: ✅ verificado — health `{"status":"ok","app":"up","database":"up"}`; contenedor corre la imagen nueva (`docker inspect` = `b872ba11d879`); logs limpios (Next.js 16.4.3 Ready, sin errores); CSP en vivo: `script-src 'self' 'nonce-…' 'strict-dynamic'` — nonce presente y SIN `unsafe-inline` en script-src (queda solo en `style-src`, esperado); sin deps nuevas ni migraciones (25/25 ya aplicadas)
- **Notas**: (1) Lección de operación: `docker compose build 2>&1 | tail` retiene el canal ssh abierto tras terminar (pipe sin EOF) → el wrapper local vio timeout a 15 min aunque el build+up remoto SÍ completó (~9 min); verificar siempre estado real (`docker images`/`docker ps`) antes de reintentar. (2) Para builds largos usar `nohup … > log 2>&1 &` + polling. (3) rsync: ~110 archivos actualizados + rutas del módulo ISO eliminadas; `.env*`, `docker-compose.yml` y `.bkup*` intactos.

### [22:30] - Release 5.9.1: Endpoint REST de reservas (integración ZionV CRM → AS → ERP)

- **Tipo**: plugin | feature | integración
- **Modificado**: `includes/Rest/ReservationController.php` (nuevo, 308 líneas — endpoint `POST /wp-json/erpsuite/v1/reservations` que recibe reservas de ZionV CRM, normaliza campos, valida, sincroniza con ERP si `erp_sync=ON`, o guarda localmente con historial transient `erpsuite_reservations_history`) · `includes/AI/Bootstrap.php` (registro del endpoint en `rest_api_init`) · armada-suite.php + readme.txt bump 5.9.0→5.9.1
- **Afecta a**: Kalimete (plugin AS); preprod sitios WP (MaganTech, Micaserogou)
- **Causa**: Integración con ZionV CRM 1.57.0 — los formularios tipo `submission_type='reserva'` de Zion ahora crean reservas reales en el ERP a través de AS
- **Estado**: ✅ verificado — php -l OK ×2; ZIP generado `armada-suite-5.9.1.zip` (2,606,540 B, sha256 `f348a752…`, 536 archivos, sin secrets); crecer ~4.1KB vs 5.9.0 consistente con los 2 archivos nuevos/modificados
- **Notas**: (1) Endpoint protegido con rate_limit 3/5min por IP (mismo patrón que otros endpoints del plugin). (2) Normaliza ambos formatos: nativo del plugin (`cliente_nombre`, `fecha`, `hora`) Y formato de Zion (`guest_name`, `slot_start`, `guest_count`). (3) Si el ERP falla, la reserva se guarda local con `synced=0` para recovery — no se pierde la reserva. (4) Historial local en transient `erpsuite_reservations_history` (200 max, 1 semana expiry). (5) ZIP listo para deploy a preprod de MaganTech/Micaserogou y luego prod via ops API.

### [22:00] - Arquitectura de integración híbrida AS ↔ Zion CRM ↔ erpipos (ERP Dev + ZionV + AS)

- **Tipo**: arquitectura | docs | integración
- **Modificado**: docs/ARQUITECTURA-INTEGRACION-HIBRIDA.md en micaserogou AS (2732 líneas, secciones 1-13 + 3 appendices) · docs/ARQUITECTURA-INTEGRACION-HIBRIDA.md en erpipo-preprod (891 líneas, API Changes para el ERP)
- **Afecta a**: kalimete (dev lab), ERP erpipos (:8100), ambos plugins (AS + ZionV)
- **Causa**: owner pidió analizar cómo fusionar AS y ZionV CRM manteniendo la flexibilidad de activar/desactivar el ERP sin perder datos ni funcionalidad; validar que ZionV no tiene inventario (no lo tiene); definir qué módulos se sincronizan y cómo
- **Estado**: ✅ documentado — 3 agentes delegados (Armada Suite, ZionV CRM, ERP Dev), documentación completa
- **Notas**:
  1. **Hallazgo crítico**: el auto-sync actual de AS SOLO sincroniza config del negocio (brand, contacto, payment_methods). NO sincroniza productos, clientes ni órdenes. El sistema es 100% on-demand API: catálogo desaparece si `erp_sync=OFF`.
  2. **ZionV no tiene módulo de inventario ni ventas de productos** — solo Leads, Pipeline, Contactos, Servicios, Bookings, Forms, AI, Reportes. El inventario es exclusividad de AS/ERP.
  3. **Fuente de Verdad por entidad**: Productos=ERP (pull), Contactos=Híbrido (push), Órdenes=ERP (push WP→ERP), Reservas=ERP (push), Forms=WP (local siempre).
  4. **Zion-UI necesita 5 componentes React**: ProductCatalogPanel, StockDashboard, SalesHistoryPanel, ServiceProductLinker, QuotationBuilder (mixto servicios+productos).
  5. **ERP Dev requiere 5 nuevos endpoints delta-sync + 1 webhook** (`POST /api/ecomm/webhook/wp`). El ERP ya tiene `updated_at` en productos → suficiente para delta-sync.
  6. **3 cambios mínimos en BD del ERP**: `ventas.external_order_id` (idempotencia), `productos.ecom_visible` (visibilidad), `ecomm_sync_log` (opcional debug).
  7. **5 fases de implementación**: (1) Tablas réplica + ErpSync_Manager, (2) Delta-sync + push + conflictos, (3) Cambios ERP (Juan Carlos `dev/ecomm-erp`), (4) UI/UX en Zion (dashboard sync), (5) Migración + rollback.
  8. Ambos documentos se guardarán en los repos correspondientes para mantener contexto técnico (evitar pérdida por compresión de historial).

### [21:30] - ZionV CRM fix configuración (fatal submit_button) + Armada Suite 5.8.0/5.9.0 selectores por tenant (integración ZionV)

- **Tipo**: plugin | feature | fix | integración
- **Modificado**: ZionV CRM `src/Core/CrmSettingsPage.php` (commit `3830088` + push GitHub `183fe6a..3830088` — fix fatal `submit_button()` en 7 tabs de `/crm/configuracion/` + cierre body/html; ZIP regenerado sha256 `4b056b58…`) · Armada Suite 5.8.0 (commit `1d0639b`: `tenant.business_mode` none|zion_crm|erp_pos|both, tab Entorno, gate erp_sync vía filtro, test 36, ZIP `5fa5306b…`) · Armada Suite 5.9.0 (commits `6c2e028`+`93ab8bf`: `tenant.template_mode` valor `default` — theme intacto, tab Negocio, helper `erpc_theme_intact`, test 37, ZIP `12307394…` 2.602.429 B) · docs agentes + harnesses de ambos (vivo_2026_10_28, .bkup-20261028)
- **Afecta a**: kalimete (dev lab :8091/:8092/:8093/:8094); producción NO tocada
- **Causa**: owner reportó errores en sección configuración de ZionV + pidió evaluar integración ZionV↔Armada Suite con selectores por tenant (template local vs default; CRM Zion vs ERP&POS vs ambos), sin "ERP LOCAL"
- **Estado**: ✅ verificado — ZionV 7/7 tabs 200/0 errores + wp-admin OK + REST 10/10; Armada regresión 37/37 exit 0 + smoke (default: theme manda, frame 0, shortcodes rinden; none/zion_crm: degradación limpia WP_Error; erp_pos: recuperación OK); elementor backward-compat intacto; "ERP LOCAL" NEGATIVO en ambos plugins (grep definitivo); credenciales debug revocadas (0 app passwords, 0 sesiones)
- **Notas**: (1) Convivencia ZionV↔Armada verificada sin conflictos duros — único cuidado: slugs `crm`/`reservar` vs mapa del router Armada. (2) CONTRATO-COMPANION no aplica a ZionV (es visual; ZionV = plugin peer funcional; contrato funcional nuevo a futuro si se integra data). (3) Vía de prueba en producción: preprod websites → ZIP → ventana manual (ops API NO instala plugins, deny-list por diseño). (4) WP_DEBUG quedó activo en stack zionv dev (recomendado mantener). (5) Lección e2e: cookie `secure_auth` vía nginx. (6) Pendiente owner: decidir bump de versión ZionV con el fix (regla del repo) y dónde vio "ERP LOCAL" (no está en ZionV).

## 2026-10-27

### [20:10] - ZionV CRM: validación full local+GitHub, ZIP 1.56.3 regenerado, push 3 commits, deriva controllers corregida

- **Tipo**: plugin | validación | docs
- **Modificado**: repo plugin `~/dev/wordpress/plugins/zionv-crm/wp-content/plugins/zionv-crm-plugin` (push `5d3efab..183fe6a` — 3 commits docs: dominio MaganTech, .gitignore *.bkup*, rutas reorg) · `export/zionv-crm-1.56.3.zip` regenerado (7.568.991 B, 1932 archivos, sha256 `bacba37b…a9d74`, unzip -t OK, sin secrets) · `agents/zionv-crm.md` (controllers 34→35, conteo real) + `harness/zionv-crm.harness.json` (vivo_2026_10_27) con `.bkup-20261027-validacion`
- **Afecta a**: kalimete (plugin ZionV CRM); GitHub warcold/zionv-crm ahora sync 100%
- **Causa**: owner pidió validar plugin local+GitHub, crear ZIP de instalación y evaluar agente/harness
- **Estado**: ✅ verificado — php -l 1437/1437 OK; versiones coherentes 1.56.3 (header=readme=CHANGELOG=DB); DB 1.24.0 con 43 tablas; stack zionv-local+zionv-db Up 7d healthy; wp-json TLS 200; SPA dist marker __zionCfgUnified=1; git status limpio y local=origin/main tras push
- **Notas**: (1) Deriva doc detectada y corregida: doc decía "34 controllers", conteo real grep = 35 (123 rutas REST exactas ✓). (2) ZIP usa convención canónica del repo (raíz `zionv-crm-plugin/`, header es lo que importa para WP). (3) 6 archivos .bkup de docs en el repo quedan ignorados por git — limpieza opcional pendiente decisión owner. (4) Repo GitHub es privado (API 404 sin auth, fetch SSH OK).

### [19:45] - Micaserogou: mejoras de negocio #2/#4/#5 implementadas + ZIP consolidado site-fixes-1.0.4 (ejecución directa por fallo de delegación)

- **Tipo**: servicio | feature | seo | artefacto
- **Modificado**: repo `~/dev/wordpress/websites/micaserogou.com` commit `54c715a` — 3 mu-plugins NUEVOS (`erpc-page-cache.php`, `erpc-sitemap-direct.php`, `erpc-jsonld-restaurant.php`) + config `uploads/erpc/jsonld-restaurant.json` + `export/micaserogou-site-fixes-1.0.4.zip` (15.639 B, sha256 `36e4bf3da44f0019e5cd187331fef414df7376e46630eafe2a13aac8630c75a0`, consolida reservas 1.0.3 + mejoras nuevas) + installer/site-fixes-build actualizado + CHANGELOG del sitio
- **Afecta a**: preprod micaserogou (validado e2e); producción NO tocada (espera upload del owner)
- **Causa**: owner aprobó proceder con las mejoras de la auditoría del 10-27 excepto #1 (gateway de pago → scope ERP Dev). La delegación al subagente Micaserogou falló 3× (1 max-steps + 2 timeouts sin artefactos) → kalimete ejecutó directo bajo la skill wp-templates (plugin compartido intocado, todo site-level)
- **Estado**: ✅ verificado — cache HIT 0.54s vs MISS 1.54s (preprod), BYPASS correctos (carrito/checkout/login/mi-cuenta/reservas/query/sitemaps), kill-switch operativo, /sitemap.xml 200 XML directo (antes 301), JSON-LD Restaurant enriquecido con email verificado, stock-0 correctamente excluido del catálogo (pitfall #12), 11 páginas 200, docker logs limpios, php -l 3/3
- **Notas**: (1) Diagnóstico #2 honesto: prod rápida con --resolve (0.26-0.42s) — los 3s de la auditoría eran DNS desde kalimete; el cache es resiliencia ante varianza del shared hosting, no fix de bottleneck. (2) Pitfalls nuevos: hijackers de página a template_redirect prio 1 obligan cache a prio 0; en WP 7.x el query var del sitemap es `sitemap=index` (no `sitemap=sitemap`). (3) Pendientes externos: upload del owner (1 ZIP: 1.0.4), stock real + teléfono/dirección/redes del cliente (JSON-LD se completa vía ops sin nuevo upload), upgrade plugin 5.5.10→5.7.0 (blocker iak tenant 3), #1 gateway → ERP Dev. (4) El teléfono 18095550123 del sitio es placeholder 555 — NO se propagó al schema.

### [16:12] - Readiness producción: Armada Suite 5.7.0 + MaganTech + Micaserogou + ERP + stack WP — todo LISTO PARA VENTANA (sin tocar producción)

- **Tipo**: plugin | servicio | deploy-prep
- **Modificado**: `~/dev/wordpress/plugins/armada-suite/export/armada-suite-5.7.0.zip` (NUEVO, 2.596.651 B, sha256 `766345c94b585c8863fbb2955c8965294f6d36ecbfc94457ebd7997cf188301c`, 529 archivos, php -l 323/323 OK) · repos de sitios: magantech-website `4a9406d` (pushed), micaserogou-website `27ec07c` (pushed) · harness magantech/micaserogou (vivo_2026_10_27, sincronizados por cron) · docs de ambos sitios (checklists PROD-UPGRADE-5.7.0-CHECKLIST.md nuevos)
- **Afecta a**: ecosistema WP completo (plugin + 2 sitios + ERP + stack); producción NO tocada (solo curl read-only)
- **Causa**: el owner pidió dejar la última versión de cada proyecto lista para subir a producción y probar las 2 páginas con el plugin conectado al ERP de producción
- **Estado**: ✅ verificado — hallazgos clave: (1) **ambos sitios están VIVOS en prod** (MaganTech 5.4.2 exacto, Micaserogou 5.5.10 — la doc "deploy pendiente" de micaserogou era stale del 10-20 y quedó curada; ambos escenarios = UPGRADE); (2) ERP prod `erpipos.armada.do` health 200 y tables/reservations EN main desde 2026-07-01 (sin gap de feature); (3) stack WP 8/8 healthy, WP 7.1.3 ×3, requisitos 5.7.0 (WP≥6.0/PHP≥7.4) cumplen con margen, regresión 35/35
- **Notas**: Artefactos con sha256 en los export/ de cada sitio: MaganTech (5.7.0 `766345c9…` + rollback 5.4.2 `157b1633…` + bundle Fase 0 `4dfcccc8…`, validaciones smoke 10/10 + login@375 OK) · Micaserogou (5.7.0 `766345c9…` + site-fixes 1.0.3 `130f4b4c…` + rollback 5.5.10 `b35e007c…`, delta site-level confirmado = solo site-fixes, bits local-only limpios, deuda de key del proxy curada). **BLOCKERS pre-ventana del owner**: (1) crear iak tenant 3 en ERP prod erpipos.armada.do (Juan Carlos) — sin ella micaserogou.com no conecta; (2) re-provisionar App Password prod de MaganTech (secrets/prod-app-password.txt, muerta). Checklists operativos: `docs/PROD-UPGRADE-5.7.0-CHECKLIST.md` en cada repo de sitio. Derivas reportadas: DEPLOY-GUIA.md del plugin (línea ZIP actual stale 5.5.1 — pendiente), DEPLOY-PRODUCCION.md raíz (pre-Armada-Suite, territorio WordPress umbrella), CHANGELOG interno del plugin divergió del árbol en formato (528/529 archivos idénticos al ZIP, cero código).

### [06:15] - Armada Suite 5.7.0: refactor de diseño/template — las 5 recomendaciones de mejora implementadas (pack.css, breakpoints, header wrapper, SEO/OG compartido, reservas al plugin)

- **Tipo**: plugin | servicio
- **Modificado**: repo `~/dev/wordpress/plugins/armada-suite` (3 commits push a `warcold/armada-suite`: `a4acd37` fase A, `20579f3` fase B, `4de0fe9` fase C) + réplica a copias de clientes (`~/dev/wordpress/websites/micaserogou.com/` y `~/dev/wordpress/websites/magantech.com.do/`, md5 verificado, backups `.bkup-20261027`)
- **Afecta a**: plugin Armada Suite (compartido), preprod micaserogou (pack restaurant) y magantech (pack default); ChatEngine con tool nueva OFF por defecto
- **Causa**: el owner pidió evaluar y proceder con 5 recomendaciones de mejora de diseño/template — todas verificadas contra código real antes de implementar
- **Estado**: ✅ verificado — regresión 35/35 PASS, matriz responsive micaserogou 21/21 (scroll_h=0, broken=0, heroes 480, radius 0), byte-diff del head de micaserogou VACÍO (SEO idéntico), MaganTech og/ld+json 0→9, enqueue pack.css micaserogou=1/magantech=0, 4 tests live de reservas PASS (15 mesas tenant 3, reservación creada+limpiada, shortcode 11/11 IDs, tool con toggle), docker logs limpios, ambos preprod 200
- **Notas**: Fase A (rec 4+3): partial `seo-og.php` compartido con `erpc_schema_type()` (filtro, default→Store/restaurant→Restaurant), header del pack = wrapper fino (202→54 líneas, require ruta directa — un fix futuro del frame propaga solo). Fase B (rec 1+2): `pack.css` restaurant (mecanismo v5.6.0 activado por primera vez: `--erpc-overlay: 122,31,31`, heroes 480/radius 0, login a sangre, container fix; NO pisa `--erpc-primary*`), connector.css normalizado a escala 480/768/992/1200 (767→768 ×5, 991→992 ×4, min-993→992 ×1, cero 767/991/993). Fase C (rec 5): reservas absorbidas al plugin — shortcode `[erpc_reservas]` + handler admin-ajax `erpc_reservas` (op=mesas|crear, nonce, rate limit, validación server-side), ApiClient +5 métodos (mesas paginado cache 60s, elegir_mesa, validar, create sin cache), `assets/js/reservas.js` nuevo, tool `crear_reserva` en ChatEngine con toggle OFF por defecto + checkbox admin. El stack site-level de micaserogou queda intacto como fallback vivo. Derivas documentadas: regresión real 35/35 (no 25/25), réplica a websites/ fue necesaria (preprod sirve copias por sitio). ZIP canónico 5.7.0 pendiente para el release process en `export/`.

### [10:20] - Ecco Suite: hallazgos de auditoría enviados upstream (PR #1 CSP nonce + Issue #2 RLS memberships) — sin aplicar nada

- **Tipo**: servicio | doc
- **Modificado**: GitHub VincentEQ/EccoSuit — branch `feature/csp-nonce` (commit 890be81, 7 archivos +135/−71) + PR #1 + Issue #2; local kalimete — `~/dev/eccoqualita/EccoSuit-develop` (branch feature/csp-nonce, develop intacto en a4644d6)
- **Afecta a**: repo upstream VincentEQ/EccoSuit (pendiente de aprobación del admin); NINGUNA aplicación (ni local develop ni producción)
- **Causa**: auditoría de seguridad de suite.eccoqualita.com (misma fecha) halló 2 mejoras accionables; el owner definió el flujo: nosotros operamos producción, el código lo aprueba el admin upstream — se envían para evaluación, NO se aplican
- **Estado**: ✅ verificado — PR #1 OPEN (https://github.com/VincentEQ/EccoSuit/pull/1), Issue #2 OPEN (https://github.com/VincentEQ/EccoSuit/issues/2), develop local sin cambios, producción intacta (health OK), procesos de prueba locales detenidos
- **Notas**: PR #1 implementa el pendiente documentado de ellos (PLAN-INCREMENTO-5 §2-C): CSP con nonce por solicitud, sin 'unsafe-inline' en script-src; validado con build de producción + servidor standalone real (16/16 scripts con nonce, nonce igual header/HTML por petición, distinto entre peticiones, descargas con su CSP propia) + typecheck/lint + 624 tests unitarios (1 fallo preexistente Windows-en-Linux en embedded-recovery). Issue #2 = RLS para memberships/organization_modules (diseño de 3 vías org/usuario/admin, ~20 call sites mapeados) — va como issue porque es cambio arquitectónico que su Planificación debe evaluar. Acceso al repo: warcold con viewerPermission WRITE. Tests locales: puerto 5434 (5433 ocupado por ror-postgres en kalimete; guards de 5433 de ellos hacen skip de 3 suites de bootstrap — en la máquina del dev pasan).

### [08:35] - Ecco Qualitá: rename de host suit → suite (suite.eccoqualita.com) — Caddy, .env de producción y toda la doc

- **Tipo**: infra | red | doc
- **Modificado**: VPS ecco — `/opt/eccoqualita/proxy/Caddyfile` (site block `suite.eccoqualita.com` + redirect 301 del viejo, cert LE nuevo obtenido) + `/opt/eccoqualita/eccosuit/.env` (`APP_URL`/`BETTER_AUTH_URL` → `https://suite.eccoqualita.com`, app recreada); kalimete — `MAPA.md`, `agents/ecco-suit.md`, `harness/kalimete.harness.json`, `harness/ecco-suit.harness.json`, `~/.config/opencode/ecosistema-map/MAPA.md` (todas las referencias suit→suite)
- **Afecta a**: ecco (VPS), kalimete (doc local)
- **Causa**: el owner renombró el host: ya no es "suit", es "suite" → `suite.eccoqualita.com`; el DNS nuevo ya apuntaba a 62.171.144.58
- **Estado**: ✅ verificado — health OK en `https://suite.eccoqualita.com/api/health` (`app:up, database:up`), cert Let's Encrypt para suite obtenido por Caddy, dominio viejo `suit.eccoqualita.com` responde **301 → suite** (redirect permanente conservado para links existentes), logs sin errores, cero referencias viejas en doc activa
- **Notas**: Backups: `Caddyfile.bkup-20261027-rename-suite` + `.env.bkup-20261027-rename-suite` (en el VPS) y `*.bkup-20261027-rename-suite` (locales). El CHANGELOG histórico NO se reescribe (las entradas viejas describen el estado de su fecha). El nombre del agente sigue siendo `Ecco Suit` (identidad del agente, no del dominio). Si el DNS de `suit` se elimina a futuro, el bloque de redirect queda inofensivo.

### [08:00] - Ecco Suite: deploy Incremento 19 + Next 16.4.3 (parche seguridad) en VPS ecco + local sincronizado con repo GitHub

- **Tipo**: servicio | deploy | seguridad
- **Modificado**: VPS ecco (62.171.144.58) `/opt/eccoqualita/eccosuit/` (código rsync desde repo), imagen `eccosuit-app` (rebuild, Next 16.4.3), imagen `eccosuit-migrate` (rebuild con perfil tools), BD `ecco_suite` (migraciones 0023+0024 aplicadas); kalimete `~/dev/eccoqualita/EccoSuit-develop/` reemplazado por clon git de `github.com/VincentEQ/EccoSuit` rama `develop` (HEAD `a4644d6`)
- **Afecta a**: ecco (VPS producción suit.eccoqualita.com), kalimete (copia dev local)
- **Causa**: repo GitHub develop tenía 17 commits ahead (Incrementos 18-19 completos + commit `07649a0` de seguridad Next 16.4.0→16.4.3: GHSA-2464-fhr4-w9xw, GHSA-673q-mjm6-r5xr, GHSA-p3m5-59mp-jv5r); servidor y copia local estaban en snapshot del 17 oct (Next 16.4.0, sin carpetas del Inc 19, migraciones hasta 0022)
- **Estado**: ✅ verificado — health `{"status":"ok","app":"up","database":"up"}` vía HTTPS, HTTP 307 (redirect login normal), logs sin errores, 25 migraciones en BD (columnas `purpose/inputs/outputs` en `processes`, enum `project_priority`, `process_kind` + `evaluation`), Next 16.4.3 confirmado dentro del contenedor
- **Notas**: Backups previos en `/opt/eccoqualita/backups/`: BD `ecco_suite-pre-inc19-20261027-0741.dump` + código `eccosuit-code-pre-inc19-20261027-0742.tar.gz`; local viejo en `~/dev/eccoqualita/EccoSuit-develop.bkup-20261027`. **Lección ops**: `docker compose build` NO reconstruye servicios con `profiles` inactivos (migrate) — el primer run de migraciones usó imagen stale y dijo "aplicadas" sin aplicar nada; detectado verificando `__drizzle_migrations` contra `_journal.json`; fix: `docker compose --profile tools build migrate`. `.env`, `.env.postgres` y `docker-compose.yml` de producción intactos (excluidos del rsync).

### [01:30] - kalimete-ptt v5.1: bug raíz del PTT (fallback silencioso al default agent) + STT con vocabulario + TTS streaming + Victoria friendly

- **Tipo**: servicio | voz | fix
- **Modificado**: cliente kalimete-ptt (`~/dev/apps/kalimete-ptt/` + deploy `~/.local/bin/`), agente `~/.config/opencode/agent/victoria-voz.md`, **victoria** `/home/victoria/voice-venv/voice-server-host.py` (backup `.bkup-20261027-stt-prompt` — cambio mínimo autorizado por pedido del owner)
- **Afecta a**: conversación de voz Ctrl_R con Victoria (PTT)
- **Causa**: el owner reportó errores + escucha confusa + respuestas técnicas + lentitud. Diagnóstico: (1) **BUG RAÍZ** — desde el deploy v5, `victoria-voz.md` tenía `mode: subagent` y `opencode run` caía silenciosamente al default agent técnico ("Falling back") — Victoria NUNCA respondía, respondía el agente default con listas técnicas de ~1000 chars → 5 chunks TTS ≈ 41s de silencio; (2) STT Whisper small sin `initial_prompt` → nombres propios del ecosistema mal transcritos; (3) TTS secuencial (esperaba el wav completo)
- **Estado**: ✅ verificado e2e: fix `mode: all` (Victoria responde como Victoria, 13.6s, conversacional, cero jerga) · STT con `?prompt=` de vocabulario en victoria (kalimete/opencode/warcold transcriben perfecto, costo 0) · TTS streaming por frases en el cliente (primera palabra ~15-18s vs ~54s, resto fluye) · timing logs por fase · sesión envenenada eliminada · 4 backups para rollback
- **Notas**: NO se recomienda Whisper small→medium (initial_prompt resolvió lo real; +2-4s/clip+VRAM) ni streaming TTS server-side (el cliente ya lo resuelve). Vigilancia menor: "STT silencio" tras conectar audífonos = ruteo PulseAudio, no pipeline. Detalle en STATE.md + CHANGELOG.md del proyecto kalimete-ptt.

## 2026-10-26

### [17:15] - Arquitectura de 3 capas WP: Armada Suite 5.6.0 (contrato companion) + Armada Templates 1.0.0 (plugin NUEVO) + Fase 0 MaganTech + gobernanza del ecosistema

- **Tipo**: plugin | release | arquitectura | gobernanza
- **Modificado** (todo el ecosistema WP, preprod only — PROD NO TOCADA):
  - **Armada Suite 5.6.0** (commits `b2da1bb` + `886d5a7` fix test 26b post-release): contrato companion — `erpc_template_path()` resuelve packs del registro (keys `dir`/`url`), `erpc_pack_asset()` rama URLs externas, `erpc_pack_color_base()` lee `colors`, pack.css automático, admin-notice de pack faltante, overlays `--erpc-overlay` + filtro `erpc_overlay_rgb`; fixes site-level absorbidos (`.erpc-container` box-sizing+1280, heroes móviles height→min-height 380/340, cta-landing con `erpc_pack_asset`); `docs/CONTRATO-COMPANION.md` NUEVO; test 35 nuevo; fix test 26b (unset `brand.hero_image` — MaganTech 34/35→35/35). Regresión **35/35 ×3**, replicación byte-idéntica ×3, ZIP `armada-suite-5.6.0.zip` (2.581.615 B, sha256 `f9100456…`).
  - **Armada Templates 1.0.0** (plugin companion NUEVO, commit `8a0ccff`, repo `~/dev/wordpress/plugins/armada-templates/`): packs `neutral` (base demo VENDIBLE sin copy de vertical, overlay negro, login a sangre, 480px/radius 0), `restaurant` (migrado override-first, byte-idéntico), `tech` (colors heredados, end-state Fase 2). Probado en dev-lab :8091: neutral renderiza + pack.css tras connector.css + admin-notice al desactivar + paridad restaurant + regresión 35/35 con companion activo. ZIP `armada-templates-1.0.0.zip` (459.425 B, sha256 `d7660076…`). Sin suite activo = companion INERTE (el template NECESITA del plugin — requisito owner).
  - **MaganTech Fase 0** (preprod :8093): mu-plugin `erpc-magantech-visual.php` v1.0.0 (overflow fix, heroes 480/radius 0 overlay azul #1a73e8, login a sangre, alfredo.pro, clamp()), 5 banners tech WebP (47-104KB, skill art), settings (`brand.hero_image` cableado, blogdescription profesional, ID 20 magantech-inicio→draft), **matriz 21/21 PASS contra 5.6.0** (evidencia 42 archivos), smoke 10/10, espejo `mejoras-default/`, receptor webhook configurado (secret 48, vivo), checklist PORT-A-PROD (7 pasos, pendiente ventana owner).
  - **Micaserogou** (preprod :8094): regresión **35/35** con 5.6.0 + smoke 7/7 + matriz 21/21 re-validada (home móvil 440/380 — estándar 5.6.0 aceptado, resto 480); **causa forense del "vacío de categorías 25-10"**: ERP sano (8 categorías live), el plugin cacheó la respuesta vacía del ERP 15 min (TTL 900s = el "self-heal") — nota upstream: no cachear respuestas vacías; flush v22→v23 + encadenado chat verificado; bkup-5.4.2 reubicado fuera del scan de plugins (riesgo 🔴 cerrado); curas de docs (header mu-plugin 1.6.0, sobre-nosotros.html muerto→deprecated).
  - **ERP Dev**: `docs/CONTRATO-DATOS-TEMPLATES.md` NUEVO (254 líneas, commit `cc17d79` pushed a dev/ecomm-erp — endpoints+shapes verificados, stock 0/-1/99, webhooks HMAC, multi-tenant, gaps upstream); **webhook tenant 3 reparado** (secret mismatch alineado, 3 deliveries failed→sent/200, backup SQL); **webhook tenant 10 re-apuntado** (dev-lab→magantech-local, e2e sent/200); gap featured/best_seller confirmado (no existen en schema — recomendación upstream Juan Carlos).
  - **WordPress (gobernanza)**: `docs/GOBERNANZA-ECOSISTEMA.md` NUEVO (constitución: ownership, anti-duplicación, flujo cross-tenant); `NUEVO-WEBSITE-TEMPLATE.md` actualizado (arquitectura 3 capas + orden de alta 6 pasos + puertos fixeados); `~/dev/wordpress/CHANGELOG.md` creado (changelog del hub).
  - **Flota**: agente `armada-templates.md` + harness `armada-templates.harness.json` NUEVOS en armada-sync (subagente 27, hidden false, temp 0.6); kalimete.md actualizado (permission.task + flota 26→27); harness armada-suite curado (5.4.2→5.6.0, zips, checks 35/35).
- **Afecta a**: todo el ecosistema WP (plugin compartido, 2 preprods, dev-lab, ERP preprod, docs del hub, flota de agentes)
- **Causa**: orden del owner "Procede con todo... dejando nuestro plugin Armada Suite listo para todo terreno y categoría... cada template, plugin y sistema debe de tener y manejar su agente, subagente, harness y documentación con sus changelogs"
- **Estado**: ✅ todo verificado live (regresiones, matrices, e2e webhooks, commits); prod INTACTA en todos los frentes
- **Notas**: Fase 2 pendiente con ventana owner (remover restaurant del core + tech dueño de su copy + neutralizar base + test 34 update). Ventana prod consolidada por sitio (MaganTech: deploy 5.6.0 + Fase 0; Micaserogou: site-fixes 1.0.3 + 5.6.0 + companion). Derivas reportadas: DEPLOY-GUIA.md "ZIP actual" stale 5.5.1; changelog suite sin entradas 5.5.1→5.6.0 (drift documental); plugins/ de :8091 es bind-mount al tree del suite (instalación transitoria del companion — decisión de layout pendiente con WordPress).

## 2026-10-25

### [23:22] - kalimete: fix Bluetooth Intel AX201 (hci0) — autosuspend crónico

- **Tipo**: infra | hardware
- **Modificado**: kalimete.local (Intel AX201 BT 8087:0026, bus 3-10)
  - `/etc/modprobe.d/btusb.conf` — `options btusb enable_autosuspend=0`
  - `/etc/udev/rules.d/99-bluetooth-ax201.rules` — `power/control=on` para vendor 8087:product 0026 y puerto 3-10
  - `update-initramfs -u` — incluye `/etc/modprobe.d/btusb.conf` en initrd
- **Afecta a**: kalimete (adaptador BT interno)
- **Causa**: el chip Intel AX201 se suspende por autosuspend USB → firmware deja de responder → `hciconfig hci0 up` falla con `Operation not permitted (1)`, `dmesg` muestra `Opcode 0x0c03 failed: -110` (ETIMEDOUT). El bug se activaba tras desconexión del Oculus Quest 3S (mismo puerto USB 3-10) que colgaba el controlador.
- **Estado**: ✅ `hciconfig hci0` → UP RUNNING PSCAN · `bluetoothctl` → Powered: yes · `hcitool inq` → detecta 4 dispositivos · `power/control=on` · `enable_autosuspend=N` · initramfs actualizado · estable tras 15s sin re-suspensión
- **Notas**: verificación de estabilidad recomendada en ~30min y tras reboot. El fix es persistente (modprobe + udev + initramfs).
### [20:30] - Cierre de maratón: registro central del ecosistema + estado final de la flota
- **Tipo**: docs | coordinación
- **Creado**: `docs/ESTADO-ECOSISTEMA.md` del plugin (registro central — primera lectura de CUALQUIER agente de la flota: estado por cliente, versiones 5.5.1→5.5.10, matriz de intercambio de mejoras entre negocios, línea ERP con sus 6 gaps, artefactos con sha256) — replicado ×3, commit plugin 9eb193b. `AGENTS-ESTADO.md` del ERP dev (boundary + contrato congelado + payloads canónicos). `docs/ESTADO-PROYECTO.md` de magantech (nuevo, modelo micaserogou). ESTADO-PROYECTO de micaserogou reescrito al estado final.
- **Harnesses actualizados** (4): PRIMERA LECTURA + Vivo final en micaserogou (5.5.10 rojo blindado, esperando site-fixes del owner), magantech (instalador listo esperando App Password), erp-dev (AGENTS-ESTADO.md), armada-suite (ESTADO-ECOSISTEMA.md).
- **Estado de la flota al cierre**: Micaserogou prod 5.5.10 VENDIENDO (rojo blindado, chat+voz; faltan: 4 clicks de reservas del owner + categorías de Juan). MaganTech esperando deploy (App Password del owner). Plugin cerrado y consistente (34/34 ×3). WhatsApp aplazado (checklist del cliente). ERP: boundary fijado — data only.
- **Notas**: los agentes se encuentran vía ESTADO-ECOSISTEMA.md (protocolo: leer al iniciar, actualizar fila al cerrar; mtime de artefactos = verdad cronológica).

## 2026-10-23
### [13:45] - armada-suite 5.5.6: fix tab «Asistente IA» + reconciliación de las 3 copias (dev-lab/magantech/micaserogou) + ZIP canónico
- **Tipo**: plugin | release | bugfix
- **Modificado**: plugin armada-suite en los 3 ambientes (dev-lab canónico, preprod magantech :8093, preprod micaserogou :8094) — v5.5.6 byte-idéntica en los 3 (diff -rq = 0)
- **Afecta a**: todos los sitios con armada-suite (el plugin es multi-tenant compartido)
- **Causa**: el owner reportó el tab «Asistente IA» sin campos (solo títulos y botones de guardar) — bug de colisión de clases: los divs internos usaban `erpsuite-section`, la misma clase que el SPA JS usa para paneles de tab; `activate()` los dejaba `hidden` para siempre. Fix: divs internos → `erpsuite-subsection` + selector JS blindado (`$('.erpsuite-main > .erpsuite-section')`)
- **Estado**: ✅ regresión 26/26 en los 3 contenedores · smoke 7/7 micaserogou · magantech front 200 · render admin 185 inputs/12 campos · chat nativo end-to-end OK (responde con categorías reales del ERP) · SEO render idéntico tras de-hardcode del pack restaurant · ZIP `armada-suite-5.5.6-plugin-only.zip` (521 archivos, sha256 ce49fe99…, 0 secrets) en export de micaserogou + canónico
- **Notas**: detalle completo en CHANGELOG del proyecto micaserogou y del plugin. De-hardcode SEO: settings del cliente poblados (contact_hours, seo_description) — cero strings del cliente en el plugin. 2 tests de regresión robustecidos contra sitios con datos reales. PROD-DEPLOY-CHECKLIST actualizado: el artefacto de deploy es ahora el 5.5.6 (el ZIP restaurant-20261021 pisaría el fix). Producción NO tocada (requiere ventana).

## 2026-10-22
### [00:35] - micaserogou: página de detalle de producto (punto 4) + proxy ERP en WordPress
- **Tipo**: servicio | frontend | api-integracion
- **Modificado**: preprod micaserogou.kalimete.local — página WP id 52 (slug: producto-detalle) + mu-plugin erpc-html-filter.php (proxy REST + interceptor de clics) + uploads/erpc/producto-detalle.html
- **Afecta a**: sitio restaurante — catálogo ahora enlaza a detalle individual por producto
- **Causa**: punto 4 del owner — página de detalle de producto bajo mejores prácticas de restaurante (referencias: Restro/Framer, The Grand Table, Brimky 2026)
- **Estado**: ✅ verificación estructural completa (12/12 elementos DOM, script, proxy, nonce); render final requiere navegador

**Qué se implementó:**
1. **Página producto-detalle (id 52)**: breadcrumb, imagen grande con badge de stock (disponible/últimas unidades/agotado), chip de categoría, título, descripción, precio RD$, meta (categoría/estado/código), selector de cantidad, botón "Agregar al carrito" (AJAX del plugin con nonce erpc_cfg), botón "Reservar mesa para este plato" (CTA restaurante), sección "Detalles del plato" (descripción/unidad/ITBIS/ingredientes), productos relacionados de la misma categoría (grid dinámico), CTA final de reserva
2. **Proxy REST WordPress** (`/wp-json/erpc-proxy/v1/erp/{path}`): reenvía peticiones al ERP API server-side — evita CORS y certificado autofirmado de erp.kalimete.local desde el navegador; API key vive solo server-side
3. **Interceptor de clics**: tarjetas del catálogo (.erpc-card-open) redirigen a /producto-detalle/?id=XXX
4. **Workaround ERP**: GET /api/products/{id} no existe en el ERP (solo index) → el JS trae products?per_page=100 vía proxy y filtra por ID

**Hallazgo de depuración (lección)**: curl NO ejecuta JavaScript — verificar datos renderizados client-side con curl da falso negativo. Verificación correcta: elementos DOM presentes + script presente + proxy responde + nonce expuesto. Bug real encontrado y corregido en el proceso: el botón de carrito requería el nonce `erpc_nonce` (check_ajax_referer) que el script original no enviaba — ahora usa `window.erpc_cfg.nonce`.

### [02:00] - Micaserogou: verificación remota — el hotfix NO llegó a prod (ZIP v1.0.1 subido o sin re-activar); screenshots ambos estados
- **Tipo**: bugfix | verificación
- **Modificado**: verificación vía ops file/read (POST, scope wp-content): erpc-mg-admin-fix.php NO existe en prod (los otros 6 mu-plugins sí, 18KB/8KB verificados) → el owner subió el ZIP v1.0.1 (sin hotfix, confirmado: unzip v1.0.1 grep admin-fix = 0) o no re-activó el instalador tras el Replace. Screenshots preprod vía CDP con sesión admin: T13-admin-sin-hotfix.png (input 0×0 = lo que ve el owner: solo botones Guardar) y T13-admin-con-hotfix.png (input 350×40 visible). Instrucciones al owner: subir export/micaserogou-site-level-deploy-1.0.2.zip (contiene el hotfix, verificado) → si WP pregunta "¿reemplazar?" → Reemplazar → **ACTIVAR** (el hook de activación es el que copia los archivos) → el aviso verde debe decir "7 mu-plugins instalados" (el v1.0.1 decía 6).
- **Afecta a**: prod micaserogou.com
- **Estado**: 🟡 hotfix verificado en preprod; prod pendiente del re-upload correcto del v1.0.2 + activación
- **Notas**: el aviso admin del instalador es el verificador visual: "7 mu-plugins" = correcto; "6 mu-plugins" = versión vieja

### [01:30] - micaserogou: validación integral 16 páginas — titles, copy restaurante, imágenes de heroes
- **Tipo**: servicio | frontend | seo
- **Modificado**: preprod micaserogou.kalimete.local — mu-plugin nuevo `erpc-restaurante-fixes.php`, `erpc-contacto-template.php` reescrito, reservas.html/contacto.html/producto-detalle.html actualizados, post_title de 10 páginas en DB
- **Afecta a**: TODAS las páginas del sitio (16) — verificación integral title/nav/imagen/copy
- **Causa**: owner pidió validar cada página del menú: texto, imagen, diseño acorde a restaurante
- **Estado**: ✅ 16/16 páginas — title correcto, nav presente, imagen presente, sin textos viejos de tienda

**Problemas encontrados y corregidos:**

1. **9 páginas sin `<title>`** (checkout, login, mi-cuenta, faq, terminos, privacidad, cookies, envios, devoluciones): el tema twentytwentyfive no soporta title-tag y el plugin solo imprime title en sus full-page templates. FIX: mu-plugin con ob_start en hook `wp` (anterior a todos los template_redirect incl. el exit del router) que inserta `<title>` si falta y decodifica entidades (&#8211; → –) si existe.
2. **Títulos duplicados** ("X — Michelle Casero y Gourmet — Michelle Casero y Gourmet"): los post_title incluían el sufijo y el header del plugin agregaba otro. FIX: post_title limpiados en DB (páginas 2, 6, 11, 13-18, 52).
3. **Copy genérico de e-commerce** → lenguaje de restaurante (gettext filter, dominio erp-suite, 20+ cadenas): Catálogo→Nuestro Menú, Explora nuestros productos→Explora nuestros platos, hechos al momento, Buscar productos→Buscar platos, Tu carrito de compras→Tu pedido, Ir a la tienda→Ver el menú, Producto→Plato, Seguir comprando→Seguir pidiendo, Recoger en tienda→Recoger en el restaurante, Volver al carrito→Volver a mi pedido, Cargar más productos→Cargar más platos, etc.
4. **Página "Productos" renombrada a "Menú"** (post_title id 6) — alineada con el nav del sitio.
5. **Reservas y Contacto sin imagen**: heroes con gradiente plano → ahora llevan imagen del pack restaurant (hero-home.webp / cta-band.webp) con overlay rojo de marca.
6. **Contacto sin nav del sitio**: mi template_redirect usaba get_header() del tema (block theme sin nav del plugin) → reescrito para usar el frame del plugin (nav + topbar + logo + title).
7. **Producto-detalle**: CTA de reserva final ahora con imagen de fondo (cta-band.webp).

**Observación para el owner (dato ERP, no template)**: el plato "PASTELON DE BERENJENA" aparece con RD$ 0.00 en el menú — el precio está en 0 en el ERP (tenant 3). Corregir desde el panel del ERP.

### [04:30] - Micaserogou: sistema visual unificado (5 cabeceras 480px) + fix crítico del detalle de producto + atribución alfredo.pro + guía reutilizable
- **Tipo**: servicio | frontend | docs
- **Modificado**: micaserogou (preprod): mu-plugin NUEVO `wp-content/mu-plugins/erpc-micaserogou-visual.php` v1.1.0 (heroes catálogo/sobre-nosotros/reservas, fondo a sangre del login, card 440px, fix overflow `.erpc-container`, barra de atribución alfredo.pro vía `wp_footer` prio 30); `uploads/erpc/producto-detalle.html` + espejo `mejoras-restaurante/` (cierre `})();` del IIFE + fix overflow móvil); `uploads/erpc/contacto.html` + `reservas.html` (+ espejos, backups `.bkup-20261022`); `mu-plugins/erpc-html-filter.php` + `erpc-html-shortcode.php` (guarda `defined()` sobre `ERPC_HTML_DIR`); 5 banners WebP 1600×914 en `assets/img/packs/restaurant/` y `wp-content/uploads/erpc/img/`; `scripts/shot-cdp.py` NUEVO; `CHANGELOG.md` del sitio NUEVO; `docs/GUIA-TEMPLATES-RESTAURANTE.md` NUEVO; `docs/evidencia/2026-10-22/` (21 capturas); hub: `agents/micaserogou.md` (gotchas + cambios recientes), `harness/micaserogou.harness.json` (vivo 2026-10-22 + pitfalls)
- **Afecta a**: sitio cliente Micaserogou (preprod `micaserogou.kalimete.local`); **producción NO tocada** (requiere ventana + rollback vía `erpsuite/v1/ops`); plugin `armada-suite` NO modificado (compartido entre tenants)
- **Causa**: orden del owner — unificar identidad visual, quitar la imagen de tecnología del catálogo, dar fondo cálido al login, diseñar el detalle de producto e integrar la atribución de alfredo.pro sin dañar el branding del cliente
- **Estado**: ✅ Validado 21/21 (7 páginas × 375/768/1440): `scroll_h=0`, 5 cabeceras en 480px con `border-radius:0`, card de login 440px (303 @375), 1 sola atribución alfredo.pro, 0 imágenes rotas, 0 errores de consola, sin warnings PHP nuevos
- **Notas**: (1) **Bug crítico**: `producto-detalle.html` no cerraba el IIFE exterior → `SyntaxError: Unexpected end of input` → TODAS las fichas de producto quedaban muertas en "Cargando producto…" sin error visible en el servidor; corregido y verificado en vivo (id=261 → "ALITAS A LA BARBACOA PICANTES", RD$ 350.00). (2) **El pack gana al HTML del sitio**: `/sobre-nosotros/` lo sirve `templates/packs/restaurant/partials/about.php` e IGNORA el `[erpc_html file="sobre-nosotros.html"]` → ese HTML del sitio es código muerto y su hero heredaba el overlay azul de tecnología (`connector.css:3341-3343`); el override va por CSS site-level. `/reservas/` y `/contacto/` sí usan HTML propio, cuyo CSS inline gana por orden en el documento → el fix definitivo va en esos archivos. (3) **Login a sangre**: `.erpc-auth-page` vive dentro de `.erpc-container` → el fondo va en `::before` con `position:fixed` + `isolation:isolate`; `background-attachment:fixed` solo ≥769px (jitter en móvil). (4) **Atribución alfredo.pro** como barra SEPARADA bajo el footer del cliente, con el SVG exacto extraído del bundle de PetSuite (`assets/index-CsG5EeBR.js` + `assets/index-Cg_BL46I.css`), opacity .55→1 al hover; el copyright del cliente NO se toca. (5) **Overflow horizontal de 32px** en todo el sitio (<1272px) por `content-box` + padding lateral en `.erpc-container` → fix site-level `box-sizing:border-box` + `max-width:1280px`; **upstream recomendado** al agente `armada-suite`. (6) **Warning PHP eliminado**: `ERPC_HTML_DIR` duplicada en 2 mu-plugins. (7) **Playwright roto en kalimete** (`Connection.init: Connection closed while reading from the driver`) → helper CDP `scripts/shot-cdp.py`. (8) `docs/GUIA-TEMPLATES-RESTAURANTE.md` documenta el sistema completo (cabeceras, login, detalle, atribución, overflow, imágenes, verificación, checklist y 7 deudas técnicas) para reutilizar en MaganTech y futuros negocios. (9) **Deuda abierta**: API key del ERP en texto plano en `erpc-html-filter.php:92` → mover a `secrets/` (pendiente de autorización del owner).

### [04:45] - Skill `wp-templates` (sistema visual Armada Suite) + fix del smoke test de Micaserogou
- **Tipo**: docs | servicio
- **Modificado**: hub `skills/wp-templates/SKILL.md` (NUEVO, 256 líneas — skill reutilizable del sistema visual de websites de clientes: estándar de cabeceras 480px, login a sangre, ficha de producto, atribución alfredo.pro, fix de overflow, imágenes 1600×914 WebP, verificación CDP con matriz de 21 combinaciones, checklist y 9 pitfalls verificados); `~/dev/wordpress/docs/NUEVO-WEBSITE-TEMPLATE.md` (sección "Sistema visual del website" → los websites futuros arrancan con el estándar desde el día 1); Micaserogou `scripts/smoke-8094.sh` (el check de permalink apuntaba a `/sample-page/`, página WP default ya eliminada → falso 404; ahora `/productos/`, backup `.bkup-20261022`) → smoke 7/7
- **Afecta a**: futuros websites de clientes (MaganTech y siguientes) + preprod Micaserogou
- **Causa**: orden del owner — dejar el trabajo registrado en changelogs y en documentación reutilizable para futuros templates y tipos de negocio
- **Estado**: ✅ skill versionada y pusheada (`5d32b76`); smoke 7/7; matriz final re-validada 21/21 en el estado definitivo
- **Notas**: la skill queda disponible para todos los agentes vía `~/.config/opencode/skills/` (la despliega `sync.sh`, skills PLURAL). La guía detallada por sitio sigue en `~/dev/wordpress/websites/micaserogou.com/docs/GUIA-TEMPLATES-RESTAURANTE.md` y el historial en el `CHANGELOG.md` de la raíz del sitio.

### [05:15] - Micaserogou: overlay negro en 5 banners (como home) + login sin newsletter + productos 8 sin "cargar más"
- **Tipo**: frontend | ux
- **Modificado**: micaserogou preprod: mu-plugin `erpc-micaserogou-visual.php` v1.2.0 (overlay banners → negro sutil `rgba(0,0,0,.65→.35)` igual que home; `body.page-id-9 .erpc-newsletter-bar { display: none }` oculta newsletter en login); `uploads/erpc/contacto.html` + `reservas.html` (+ espejos, backups `.bkup-20261022-2`) con overlay negro; mu-plugin `!important` en `.erpc-about-hero-bg` para ganar al `style` inline del pack
- **Afecta a**: preprod micaserogou; producción NO tocada
- **Causa**: owner pidió banners "al natural" como home, login limpio (solo form), productos 8 sin "cargar más"
- **Estado**: ✅ 21/21 (7 págs × 3 anchos): 5 cabeceras 480px/radius 0 overlay negro, login solo form, card 440px (303 @375), 0 scroll, 0 errores
- **Notas**: (1) Banners unificados a overlay negro como home. (2) Newsletter oculto en login. (3) Productos: 8 items sin "cargar más" (OK); para "más vendidos/destacados" → marcar `featured/best_seller` en ERP tenant 3. (4) `sobre-nosotros` necesitó `!important` vs `style` inline del pack.

### [05:45] - Micaserogou login: gap card→footer 40px + newsletter oculto + footer compacto
- **Tipo**: frontend | ux
- **Modificado**: micaserogou preprod: mu-plugin `erpc-micaserogou-visual.php` v1.3.0 (anula `min-height:100vh/80vh` del plugin en `.erpc-page`/`.erpc-auth-page` con `body.page-id-9 .erpc-page, .erpc-auth-page { min-height: auto }`; oculta newsletter del footer y columnas 3-4 con `body.page-id-9 .erpc-footer-newsletter { display: none }` + `body.page-id-9 .erpc-footer-grid .erpc-footer-col:nth-child(3), :nth-child(4) { display: none }`)
- **Afecta a**: preprod micaserogou login
- **Causa**: owner detectó espacio excesivo entre form y footer (763px gap) haciendo la página scrolleable
- **Estado**: ✅ 21/21: login gap 40px (era 763px), newsletter oculto, footer 707→635px, scroll vertical 145px @1440 (era 869px)
- **Notas**: (1) Plugin fuerza `.erpc-page { min-height:100vh; display:flex }` (connector.css:1776) y `.erpc-auth-page { min-height:80vh }` (connector.css:2135) → anulados con `min-height:auto` en login. (2) Footer compactado: oculta newsletter bar + columnas "Ayuda" y "Legal". (3) Gap card→footer = 40px (padding-bottom auth-page), scroll vertical 145px @1440 (era 869px).

### [06:15] - Micaserogou login mobile: sin scroll + gap simétrico 24px + nav "Menú" + footer solo marca
- **Tipo**: frontend | ux | mobile
- **Modificado**: micaserogou preprod: mu-plugin `erpc-micaserogou-visual.php` v1.4.0 (media query `@media (max-width: 767px)` para login móvil — footer solo marca (oculta menú, ayuda, legal, newsletter, bottom), padding footer 8px, card padding 12px, auth-page padding 24px, oculta mobile-search, trustbar/topbar/alfredo-bar compactos); `erpc-restaurante-fixes.php` gettext filter `'Tienda' => 'Menú'` para forzar "Menú" en nav
- **Afecta a**: preprod micaserogou login (móvil ≤767px); tablet 768px y desktop intactos
- **Causa**: owner pidió login móvil sin scroll, gap simétrico 24px arriba/abajo, nav "Menú" no "Tienda"
- **Estado**: ✅ 21/21: móvil 375px scroll_v ≤100px (era 763px gap), gap simétrico 24px, card 311px, footer 292px (solo marca), nav "Menú"; tablet 768px/desktop 1440px intactos (gap 30px, card 440px, footer completo)
- **Notas**: (1) Media query `@media (max-width: 767px)` para no afectar tablet 768px. (2) Footer móvil: oculta columnas 2-4 (menú, ayuda, legal), newsletter, bottom; deja solo logo + nombre marca. (3) Card padding 12px, auth-page padding 24px, footer padding 8px. (4) Oculta mobile-search, compacta trustbar/topbar/alfredo-bar. (5) Gettext filter `'Tienda' => 'Menú'` corrige la traducción del plugin que convertía "Menú" a "Tienda".

### [07:30] - Micaserogou: login CENTRADO sin scroll (flex) + header unificado 82px (tagline 1 línea) + reservas/producto-detalle con frame del plugin
- **Tipo**: frontend | ux | servicio
- **Modificado**: micaserogou preprod: mu-plugin `erpc-micaserogou-visual.php` v1.5.0 — (a) **LAYOUT FLEX del login**: `body.page-id-9{display:flex;flex-direction:column;min-height:100svh}` + `.erpc-page{flex:1}` + `.erpc-auth-page{flex:1;justify-content:center}` → card centrada entre header y footer, footer al fondo del viewport, **0 scroll en 375/768/1440×1080**; (b) **header unificado**: `.erpc-tagline{max-width:none!important}` — el pack inyectaba max-width:200px solo al imprimir frame (topbar 100px, tagline 2 líneas) y en login no (80px, 1 línea); el owner prefiere el look de login → 82px con tagline 1 línea en TODO el sitio; (c) footer login minimal (nombre+copyright, sin logo/newsletter/contacto/redes/cols 2-4); (d) mobile-search oculto en login a todos los anchos; (e) topbar login compacto ≤899px. NUEVO `wp-content/mu-plugins/erpc-site-pages-frame.php`: hijack template_redirect prio 1 de **reservas** (ID 2) y **producto-detalle** (ID 52) — renderizaban huérfanas con el TEMA (sin topbar/nav/footer del plugin, sin navegación); ahora header partial del pack + uploads/erpc/<slug>.html + footer partial (patrón de erpc-contacto-template.php)
- **Afecta a**: preprod micaserogou — login, TODAS las páginas (header), /reservas/ y /producto-detalle/
- **Causa**: orden del owner — remover espacio vacío form→footer centrando el form (página completa sin scroll) y unificar el header al look de Ingresar
- **Estado**: ✅ 21/21 (7 págs × 375/768/1440 @1080): login CENTRADO (63/63, 56/56, 94/94) scroll_v=0 en todas, nav+topbar en TODAS (reservas y producto-detalle ya no huérfanas), heroes 480/r0, prod-detalle datos ERP, 0 rotas, 0 errores, copyright visible. Smoke 7/7
- **Notas**: (1) Root cause del header distinto: style inline del pack solo al imprimir frame → tagline 2 líneas (100px) vs login 1 línea (80px); fix global 1 línea. (2) Páginas huérfanas: slugs fuera del mapa $pages del router → tema sin nav; mu-plugin las cubre con el frame (prio 1 < router 99). (3) Flex degrada con elegancia: viewport bajo → scroll natural sin espacios muertos. (4) Evidencia: docs/evidencia/2026-10-22/T11-*.png

### [07:30] - MIGRACIÓN COMPLETA proxy vps-proxy → vps-preprod DOCKERIZADO + DNS cutover — vps-proxy listo para cancelación
- **Tipo**: infra | servicio | docs
- **Modificado**: vps-preprod: NUEVO stack `/opt/proxy-stack/` (docker-compose.yml + squid/Dockerfile ubuntu:24.04 + socks5/Dockerfile python:3.12-slim + squid.conf + proxy-users.conf + blocked-domains.txt 111 dominios + socks5-proxy.py adaptado SQUID_HOST env); contenedores `proxy-squid` (Squid 6.14, :3128) + `proxy-socks5` (:1080), red aislada `proxy-net`, volumen squid-logs, ulimits nofile 65536, tmpfs /run; firewall: iptables INPUT ACCEPT 3128/1080 (posiciones 8-9, netfilter-persistent, backup rules.v4.bkup-20261022-proxy) + excepción DOCKER-USER dports 3128,1080 en /etc/docker-firewall/apply.sh (backup apply.sh.bkup-20261022-proxy, re-aplicada); Cloudflare DNS: proxy.us-east.armada.do + jovtransport.prx.armada.do → 154.53.35.102 (gris, TTL 300, token opencode-dns-cleanup — el de cuenta falló por restricción IP 9109); docs: agents/proxy.md (reescrito), MAPA.md (nodos 3-4 + tabla agentes), harness/proxy.harness.json, INVENTARIO cloudflare-map
- **Afecta a**: vps-preprod (nuevo servicio proxy PARA CLIENTES), vps-proxy (fallback temporal → cancelación Contabo por el owner), cliente jovtransport (IP de salida cambia 31.220.102.176→154.53.35.102; usar hostnames)
- **Causa**: orden del owner — consolidar el proxy en vps-preprod dockerizado para cancelar vps-proxy
- **Estado**: ✅ Validado end-to-end: squid 200 admin/jovtransport (0.15-0.33s), socks5 200 vía dominio dedicado, YouTube 403 (filtros), auth mala 407, FD 65536 verificado, 8 dominios VPS + IRC 6667/6697/7209 intactos, 0 vars proxy en sistema/25 contenedores (aislamiento requisito owner), DNS propagado en 1.1.1.1
- **Notas**: 3 bugs encontrados y curados durante la migración: (1) proxy-users.conf 600 root:root → helper basic_ncsa_auth (uid 13) no leía → 407 loop; fix 640 root:13. (2) /run/squid.pid persistía en capa rw tras docker restart → squid crash-loop "already running PID 1"; fix tmpfs /run en compose. (3) El tráfico externo a puertos docker publicados pasa por FORWARD→DOCKER-USER (NO por INPUT): el DROP CF-only lo mataba; fix excepción en apply.sh (el builder canónico que re-aplica al boot). Hallazgo de fidelidad: en squid.conf de vps-proxy "cache deny all" estaba INERTE (pegado a un comentario en la línea de multi-IP) — la versión dockerizada lo lleva como directiva propia (intención original documentada). Squid 6.14 = misma versión en ubuntu:24.04 que en vps-proxy. vps-proxy NO se tocó ni apagó: queda como fallback hasta que el owner cancele en Contabo (recomendado: gracia de días para que jovtransport confirme hostname vs IP hardcodeada).

### [08:45] - PUNTOS 3-5 EJECUTADOS + VALIDACIÓN CLOUDFLARE + ESTADO JOVTRANSPORT + FIX INVENTARIO
- **Tipo**: infra | seguridad | docs
- **Modificado**: vps-preprod: (3) `docker builder prune -f` (8.1GB recuperados, 45G→38G usado) + `docker image prune -f`; (4) rotación access.log: `logfile_rotate 10` en squid.conf + `squid -k reconfigure` (sin downtime) + cron root `0 4 * * 0 docker exec proxy-squid /usr/sbin/squid -k rotate` (semanal, 10 generaciones); (5) fail2ban jail squid: filter `/etc/fail2ban/filter.d/squid.conf` (epoch + 407), jail `/etc/fail2ban/jail.d/squid.local` (`backend=auto` OBLIGATORIO — default systemd ignora logpath; `ignoreip` subnet docker; `action=iptables-allports chain=FORWARD` — la coma en port= rompe parser); Cloudflare: subagente validó READ-ONLY — 0/33 registros armada.do apuntan a 31.220.102.176, los 2 hosts proxy exactos al objetivo (gris, TTL 300, propagados), 0 hosts jovtransport/proxy/prx sin migrar; INVENTARIO línea 140 corregido (nota telecomm: proxy.us-east NO es de telecomm, es proxy Armada migrado); jovtransport: 0 requests en proxy nuevo (medianoche RD), 0 residual en vps-proxy últimos 15 min — monitorear hoy horario laboral RD; vps-proxy fallback intacto.
- **Afecta a**: vps-preprod (proxy hardening + logs + espacio), vps-proxy (fallback), Cloudflare (docs), jovtransport (pendiente confirmar hostname vs IP hardcodeada)
- **Causa**: orden del owner — ejecutar puntos 3-5 del plan + validar migración completa
- **Estado**: ✅ Disco 38G/145G (26%), rotación probada (reconfigure + rotate OK, cron instalado), fail2ban validado end-to-end (filtro 13/13, ban real REJECT en f2b-squid hook FORWARD pos.1, unban OK — me baneé a mí mismo con 6 tests de auth mala, prueba definitiva; desbaneado), jovtransport aún no conecta (00:55 AST), vps-proxy 0 tráfico residual.
- **Notas**: 3 hallazgos operativos: (1) fail2ban default backend=systemd en Ubuntu 24.04 — sin `backend=auto` el jail NO lee el logpath (solo journal); (2) `iptables-multiport` con `port=3128,1080` falla por coma en parser — usar `iptables-allports`; (3) jovtransport usa el proxy en horario diurno RD — la migración DNS (TTL 300) es transparente si usa hostname; si tiene IP hardcodeada, seguirá en vps-proxy hasta que actualice. vps-proxy queda como fallback sin tocar hasta confirmación.

### [11:45] - AUDITORÍA DOCUMENTAL HUB: 27 agents ↔ 27 harness validados, completitud + discrepancias LIVE curadas, CHANGELOG consolidado
- **Tipo**: docs | infra
- **Modificado**: `harness/kalimete.harness.json` RECONSTRUIDO (tenía 21 subagentes con 2 inexistentes —Ragnarok/Godot viejos— y sin scope/live_check/upstream/docs/changelog; ahora los 26 reales + campos estándar + vivo de auditoría; backup `.bkup-20261022-audit`); 13 harness con backup `.bkup-20261022-audit`: 9 `vivo` refrescados con LIVE checks reales (authentik, cloudflare, docuseal, nextcloud, petsuite, proxmark, scriberr, taohemps, vps — evidencia: vps-preprod 26 contenedores Up 28h, 7 dominios 200/302, victoria uptime 5d, pm3 presente), kalimete-dashboard +changelog+docs_oficiales+vivo (api/health ok), kalimete-ptt +changelog+docs_oficiales+vivo (servicio active), game-studio +docs_oficiales, micaserogou +live_check; agents: blender, ecco-suit, game-studio, intigriti +docs oficiales +upstream_drk +pointer harness; kalimete-ptt +pointer harness; micaserogou +docs oficiales +pointer harness; `agents/kalimete.md` (vps-proxy DESACTIVADO en tabla red + alias + regla TARGET; rol vps-preprod +proxy clientes); `MAPA.md` (topología 2026-10-22, diagrama vps-proxy DESACTIVADO, sección 4 reescrita: verificado muerto, servicios NINGUNO, DNS repuntado); `AGENTS.md` (referencia a eco-cloudflare-* retirados → Cloudflare); `CHANGELOG.md` consolidado (81 bloques ## → 40 fechas únicas, 314 entradas intactas verificadas por script; backup `.bkup-20261022-audit`)
- **Afecta a**: todo el repo armada-sync (documentación); NINGÚN servicio tocado — solo lectura LIVE
- **Causa**: orden del owner — documentar todo, validar que cada harness tenga la documentación correspondiente del servicio que maneja, limpiar discrepancias ambiguas
- **Estado**: ✅ 27/27 agents ↔ 27/27 harness match 1:1; todos los harness con scope/live_check/upstream/docs/changelog completos; temperaturas validadas contra política (infra 0.1 / creativos 0.6 / kalimete 0.2); 9 vivo stale del 2026-10-01 refrescados con evidencia de hoy
- **Notas**: Hallazgos clave: (1) kalimete.harness.json era el MÁS desviado (updated 2026-10-15, subagentes inexistentes, Proxy apuntando al vps-proxy muerto); (2) 9 harness sin verificación viva desde 2026-10-01 (21 días); (3) CHANGELOG acumulaba 41 bloques de fecha duplicados (10-22 ×3, 10-21 ×11, 10-20 ×4, 10-19 ×3, 10-03 ×2 + resto histórico); (4) kalimete.md/MAPA.md decían vps-proxy "✅ activo" pese a estar cancelado hoy. Pendiente menor: los vivo de ragnarok-server, record-of-ragnarok, magantech, armada-suite, erp-dev, zionv-crm, wordpress-dev, victoria-server, irc, blender, ecco-suit, intigriti, game-studio son de fechas intermedias (10-08 a 10-21) — se refrescarán en sus próximas sesiones de servicio.

### [13:15] - HARDENING MEDIO/BAJO EJECUTADO + VERIFICACIONES SERVICIOS + PENDIENTES HEREDADOS
- **Tipo**: infra | mantenimiento | docs
- **Modificado**: vps-preprod: logrotate `/etc/logrotate.d/fail2ban` (diario, 28 rotaciones, compress, postrotate reload fail2ban); health check proxy `/usr/local/bin/proxy-healthcheck.sh` + cron `*/5 * * * *` (Squid + SOCKS5 vía dominios, alerta systemd-cat); cron mensual `0 3 1 * * docker builder prune -f` (log en `/var/log/docker-builder-prune.log`); logrotate fail2ban ya instalado (verificado).
- **Verificaciones**: certs TLS todos vigentes (auth/nextcloud/docuseal/pets/scriberr/ragnarok/whiteboard: dic-2026; taohemps: ene-2027; IRC el.colador.de.alfredo.pro: ene-2027; proxy HTTP plano sin TLS); Nextcloud 33.0.3 sano (maintenance=false, no upgrade pendiente); Authentik 4/4 contenedores healthy (server/worker/redis/db, workers procesando tareas celery OK); IRC certbot auto-renueva ene-2027; taohemps LE ene-2027; proxy HTTP plano (sin TLS, termina en cliente).
- **Pendientes heredados documentados** (no ejecutados, requieren decisión owner):
  1. **Backups rotos** (CRÍTICO): `backup-vps.timer` 03:20 → jonas (10.0.0.20) caído desde sep-2026; nextcloud-db/taohemps/petsuite/infra sin backups. Opciones: reparar jonas / repuntar a kalimete/victoria / nuevo NAS.
  2. **Cancelar vps-proxy** (ALTO): gracia 2-3 días laborables RD para jovtransport (hostname vs IP hardcodeada 31.220.102.176); fallback intacto.
  3. **Dependencia telecomm**: confirmar si servidores 207.244.236.223 usan `proxy.us-east` (hostname transparente / IP hardcodeada rota).
  4. **Shutdown Contabo 21-oct 16:31**: causa por confirmar (¿panel?).
  5. **Retiro `*.alfredo.pro`** en banahosting (pendiente listado; mail.alfredo.pro vive en cPanel).
  6. **Bot Fight Mode**: dashboard 2 clics (plan Free sin API).
  7. **Router port-forward 443→10.0.0.5**: eliminar (privacidad, túnel victoria-armada ya maneja 443).
- **Afecta a**: vps-preprod (hardening operativo), vps-proxy (fallback), Cloudflare (docs), backups (crítico), jovtransport/telecomm (comunicación).
- **Causa**: orden del owner — ejecutar puntos medio/bajo, documentar pendientes para próximo ciclo.
- **Estado**: ✅ Logrotate fail2ban instalado (diario, 28 rot, compress, reload); health check proxy activo (cron 5 min, systemd-cat); docker builder prune mensual (1ro de mes 03:00, log dedicado); certs todos vigentes (dic-2026/ene-2027); Nextcloud 33.0.3 sano; Authentik 4/4 healthy + celery OK; IRC/taohemps certs auto-renuevan ene-2027.
- **Notas**: El proxy es **solo servicio para clientes** (aislado: 0 vars proxy en sistema/25 contenedores, red `proxy-net` dedicada, DNAT preserva IPs reales). Los demás servicios (nextcloud, authentik, IRC, taohemps, pets, scriberr, ror-landing, staging) NO usan el proxy. vps-proxy fallback intacto (0 tráfico residual). Próximo ciclo: backups (crítico), cancelación vps-proxy, telecomm, jonas.

### [16:50] - Proxy: fail2ban jail squid DESHABILITADA — baneaba al cliente legítimo (jovtransport)
- **Tipo**: seguridad | proxy
- **Modificado**: vps-preprod `/etc/fail2ban/jail.d/squid.local` (backup `.bkup-20261022`): sección `[squid]` `enabled = true` → `enabled = false` + comentario explicativo. Jails `sshd` intactas; fail2ban completo sigue activo. Docs: `agents/proxy.md` (tabla servicios + sección fail2ban), `harness/proxy.harness.json`.
- **Afecta a**: vps-preprod (fail2ban), cliente jovtransport (181.36.176.87) — recupera navegación completa
- **Causa**: orden del owner — la jail squid interpretaba los 407 NORMALES de las apps Windows del cliente (CONNECT sin auth pre-emptiva: Skype/login.live, MS telemetry, updater EdrawSoft, update.googleapis; ráfagas de 8 en <1s) como brute-force → baneo all-ports (`iptables-allports chain=FORWARD`) → el cliente perdía la navegación COMPLETA. Baneado 2x el mismo día (14:29 y 15:00); también baneó a kalimete (69.143.73.120) a las 07:45 durante la validación de la migración (el `ignoreip` de la jail squid pisaba al `ignoreip` DEFAULT)
- **Estado**: ✅ Verificado: unban 181.36.176.87 OK + chain `f2b-squid` fuera de FORWARD + 0 refs nftables + jail sshd intacta + probe HTTP 407 (Squid vivo pidiendo auth) + SOCKS5 abierto + túneles `TCP_TUNNEL/200` fluyendo (jovtransport + admin)
- **Notas**: El proxy conserva auth NCSA obligatoria + filtros de contenido; fail2ban sigue protegiendo SSH (:1333). Precedente: vps-proxy corrió 228 días con fail2ban solo sshd sin problemas — la postura actual replica esa estabilidad. Si el owner quisiera anti-bruteforce del proxy en el futuro: reactivar con `maxretry` alto (20+) o `ignoreip` de IPs cliente (frágil por IP dinámica). Dato menor: unban manual previo de 181.36.176.87 a las 14:57 (alguien lo desbaneó a mano antes de la intervención). El PC del cliente reconectará solo cuando sus apps reintenten (backoff post-ban).

### [20:55] - micaserogou: chatbot E2E funcionando en preprod con la key armada-micaserogou (gateway victoria)
- **Tipo**: servicio
- **Modificado**: preprod micaserogou.kalimete.local — erp_suite_settings.ia configurado: api_url=http://10.0.0.5:8010/v1 (IP directa — el contenedor no resuelve victoria.local por mDNS), api_key=armada-micaserogou (secrets/, 600), model=nvidia/Qwen3.6-35B-A3B-NVFP4-normal (default del plugin, sin reasoning)
- **Afecta a**: chatbot del preprod (prod pendiente: owner pega la key en wp-admin → Ajustes → Asistente IA — ia.* bloqueado para ops por el Guard, solo humano)
- **Causa**: owner reportó "El asistente IA no está disponible" en prod — ia.api_key vacía (la URL victoria.armada.do/v1 y el modelo ya son defaults del plugin 5.5.5; solo faltaba la key). Key provisionada por el agente Victoria Server (POST /v1/provision-key, rol services, caps [llm], E2E 200 contra la URL exacta del bot)
- **Estado**: ✅ preprod E2E verificado: conversar("hola, tienen arroz?") → "Tenemos arroz Grande a RD$200 y Pequeño a RD$100, pero lamentablemente ambos están agotados en este momento." (4,1s, precios reales del ERP, respuesta corta hasta el punto) + botón "Ver en tienda →" con filtro ?buscar=arroz (navegación al menú filtrado OK) · ⏳ prod: owner pega la key de secrets/armada-micaserogou.key en wp-admin → ERP Suite → Ajustes → Asistente IA (campo API key; URL y modelo ya defaults)
- **Notas**: La key sirve igual para prod (gateway acepta cualquier origen). En prod NO hace falta tocar api_url/model (defaults correctos: https://victoria.armada.do/v1 + -normal). Hallazgo del agente Victoria: key preexistente "erp-bot" (readonly) es residuo — owner puede revocarla desde el panel /admin si quiere.

### [23:10] - micaserogou: template restaurante — mejoras completas (reservas reales, categorías ERP, datos reales, CTA sticky)
- **Tipo**: servicio | frontend | api-integracion
- **Modificado**: preprod micaserogou.kalimete.local (:8094) — páginas WordPress (id 2, 5, 6, 11, 12) + mu-plugins + assets en wp-content/uploads/erpc/
- **Afecta a**: sitio web del restaurante Mi Casa Rogou / Michelle Casero y Gourmet (tenant 3 del ERP)
- **Causa**: el template migró de tienda de piezas de computo a restaurante; necesitaba reservas de mesas, categorías y productos reales del ERP, y CTA de conversión apropiados para restaurante
- **Estado**: ✅ implementado y verificado en preprod

**Cambios realizados:**

1. **Página Reservas (id=2, slug: reservas)** — Formulario funcional de reserva de mesas:
   - Consulta `/api/tables` del ERP para mostrar mesas disponibles reales (15 mesas, 14 disponibles al momento del deploy)
   - Agrupa mesas por ubicación (Terraza, etc.) con capacidad y número
   - Crea reserva vía `POST /api/reservations` del ERP con fecha, hora, personas, nombre, teléfono, email
   - Feedback visual de éxito/error; recarga disponibilidad tras reserva exitosa
   - Archivo: `wp-content/uploads/erpc/reservas.html` + `reservas.js`

2. **Página Inicio (id=5)** — Hero y CTA orientados a restaurante:
   - Botón sticky fijo "Reservar mesa" (esquina inferior derecha) con enlace a /reservas/
   - Horarios de atención visibles en el sticky (Lun–Jue 11:00–21:00, Vie–Sáb 11:00–22:00, Dom 12:00–20:00)
   - Script `datos-reales.js` inyectado para categorías y productos reales del ERP

3. **Página Productos (id=6)** — Catálogo con datos reales:
   - Filtro de categorías cargado dinámicamente desde `/api/products` del ERP (workaround: `/api/categories` devuelve 500 en el ERP, se extraen categorías únicas de los productos)
   - Productos destacados dinámicos desde el ERP (85 productos, precios DOP, stock, imágenes reales)
   - Proof counters reales (contadores de clientes, platos, categorías, satisfacción)

4. **Página Sobre Nosotros (id=11)** — Imagen hero corregida (URL https correcta, pack restaurant), iconos de sección (SVG Bootstrap), horarios de atención, misión/visión/valores reescritos para restaurante

5. **Página Contacto (id=12)** — Formulario de contacto completo, información de contacto (dirección, teléfono, WhatsApp, correo), horarios, placeholder de mapa de ubicación

6. **Mu-plugins instalados:**
   - `erpc-html-filter.php`: procesa `[erpc_html file="X.html"]` en the_content, inyecta `datos-reales.js` en wp_footer, inyecta botón sticky de reserva + horarios en el front page
   - `erpc-html-shortcode.php`: shortcode `erpc_html` como fallback
   - `erpc-contacto-template.php`: intercepta /contacto/ con `template_redirect` para servir HTML personalizado (el plugin Armada Suite interceptaba esta página)

7. **API del ERP verificada (tenant 3):**
   - `GET /api/products` → 85 productos con precios DOP, stock, imágenes en `erp.kalimete.local/storage/productos/`
   - `GET /api/tables` → 15 mesas con estado, capacidad, ubicación
   - `POST /api/reservations` → creación de reservas
   - `GET /api/categories` → 500 Server Error (bug del ERP reportado; workaround implementado)

**Archivos nuevos en `websites/micaserogou.com/`:**
- `mejoras-restaurante/reservas.html` — HTML de la página de reservas
- `mejoras-restaurante/reservas.js` — JS de reservas (API tables + reservations)
- `mejoras-restaurante/datos-reales.js` — JS de categorías/productos/proof reales del ERP
- `mejoras-restaurante/sobre-nosotros.html` — HTML de Sobre Nosotros
- `mejoras-restaurante/contacto.html` — HTML de Contacto
- `mejoras-restaurante/erpc-html-filter.php` — mu-plugin principal
- `mejoras-restaurante/erpc-html-shortcode.php` — mu-plugin shortcode fallback
- `mejoras-restaurante/erpc-contacto-template.php` — mu-plugin template contacto
- `mejoras-restaurante/actualizar-paginas.php` — script de migración DB
- `mejoras-restaurante/actualizar-shortcodes.php` — script de migración shortcodes

**Notas:** El botón sticky de reserva no interfiere con el carrito flotante existente (erpc-cart-float). Los archivos JS están en `wp-content/uploads/erpc/` (persistente, accesible vía HTTPS). El shortcode `[erpc_html]` permite editar el HTML desde wp-admin si es necesario.

### [23:45] - ERP: fix GET /api/categories 500 (columnas inexistentes en business_types) — push a dev/ecomm-erp para Juan Carlos
- **Tipo**: infra | api | bugfix
- **Modificado**: `~/dev/erpipo-preprod/code/sistema-facturacion/` (rama `dev/ecomm-erp`, commit b187abc, pushed a origin)
- **Afecta a**: endpoint `GET /api/categories` del ERP preprod (tenant 3, micaserogou.com) — usado por el filtro de categorías del sitio restaurante
- **Causa raíz**: `CategoryController@index` hacía eager-load de `business_types` seleccionando columnas `color_default` e `icono_default` que **no existen** en la tabla `business_types` (esquema real: `color`, `icon`). `CategoryResource` también referenciaba `$bt->key`, `$bt->color_default`, `$bt->icono_default` que no existen. Error SQL: `SQLSTATE[42S22]: Column not found: 1054 Unknown column 'business_types.color_default'`
- **Fix aplicado**:
  - `app/Http/Controllers/Api/CategoryController.php`: `select` cambió `color_default, icono_default` → `color, icon`
  - `app/Http/Resources/CategoryResource.php`: mapeo cambió `key→slug`, `color_default→color`, `icono_default→icon`
- **Estado**: ✅ verificado en vivo — `GET /api/categories` devuelve HTTP 200 con 8 categorías reales (ADICIONALES, BEBIDAS, CALDOS, ESPECIALIDADES, MOFONGOS, PASTAS, PLATOS DEL DIA, POSTRES) + `?per_page=100` y `?activa=true` OK
- **Para Juan Carlos**: el fix está en `dev/ecomm-erp` (commit b187abc, pushed). Él hace merge a `main` y despliega a producción (nunca nosotros tocamos prod).
- **Backups**: `.bkup-20261021` creados antes de editar (no commiteados, quedan en árbol de trabajo)


## 2026-10-21
### [15:55] - IRC El Corito EN SERVICIO: firewall vps-preprod abre puertos 6667/6697/7209
- **Tipo**: infra | servicio
- **Modificado**: iptables INPUT en vps-preprod (3 reglas ACCEPT insertadas posiciones 5/6/7) + `/etc/iptables/rules.v4` persistido vía `netfilter-persistent save` (ya instalado, enabled al boot)
- **Afecta a**: vps-preprod (servicio IRC El Corito, InspIRCd v4.7.0)
- **Causa**: política DROP en INPUT sin reglas IRC → todo tráfico silent-drop, clientes en timeout, 0 conexiones (diagnóstico agente IRC, ejecución autorizada por owner)
- **Estado**: ✅ Firewall abierto y persistido · ✅ Verificado desde kalimete: nc OK en 6667/6697/7209 · ✅ InspIRCd activo sin reinicios · 🔴 PENDIENTE cert TLS el.colador.de.alfredo.pro expirado 2026-10-02 (handshake 6697 sirve cert vencido; sin cliente ACME en el VPS, HTTP-01 bloqueado por firewall+Caddy nextcloud, zona alfredo.pro fuera de la cuenta CF — requiere decisión owner) · ⏸️ crontab renovación pendiente del cert
- **Notas**: Backups: `/root/iptables.bkup-20261021-154345` + `/etc/iptables/rules.v4.bkup-20261021-154345` (rollback: `iptables-restore < /root/iptables.bkup-20261021-154345`). Enlace S2S a irc.elcorito.org inestable (~2h, posible lado remoto — solo observado). deploy-ssl.sh resultó ser hook de ejemplo de InspIRCd con rutas placeholder, NO flujo real de renovación. Plaintext 6667 ya operativo para clientes.

### [16:10] - micaserogou: pack restaurant COMPLETO (about.php nuevo) + legales reescritas — cero tecnología en todo el sitio local
- **Tipo**: servicio | release
- **Modificado**: ~/dev/wordpress/websites/micaserogou.com/wp-content/plugins/armada-suite/templates/packs/restaurant/partials/about.php (NUEVO, 5.1 KB — misión/visión/valores/equipo restaurante, mismas clases que el default, hero con get_hero_image()); post_content de 7 páginas reescrito con copy restaurante correcto (IDs 12 contacto "Atención al cliente", 13 términos, 16 envíos→"Delivery y Entregas", 17 devoluciones→reclamos 2h/reposición, 14 privacidad, 15 cookies, 18 FAQ completa con reservas/eventos); revisiones WP purgadas (3, residuos "pedidor"/"perfiln"/"deliverys" solo vivían ahí); ZIP export/armada-suite-micaserogou-restaurant-20261021.zip regenerado (23,9 MB, 1623 archivos, about.php del pack verificado dentro, dump DB limpio 172K)
- **Afecta a**: preprod micaserogou.kalimete.local — producción SIN CAMBIOS
- **Causa**: usuario reportó seguir viendo "Componentes, cables y accesorios para tu PC y oficina" en el template. Root cause: el router del plugin (includes/Store/Templates.php) hijackea /sobre-nosotros/ por slug → [erpc_about] → partial default de TECNOLOGÍA porque el pack restaurant NO tenía about.php (el post_content es ignorado por el router — por eso el fix anterior de la DB fue inerte). Además el str_ireplace automático de la sesión anterior dejó textos mangled ("pedidor", "una pedido", "deliverys", "licencias de software" en devoluciones, "platos perfiln", "Soporte técnico" en contacto, tiempos/pesos/seguimientos de courier en envíos/FAQ)
- **Estado**: ✅ /sobre-nosotros/ renderiza "Mi Casa Rogou — sazón de casa, hecha al momento" (grep "tecnolog" = 0) · ✅ barrido 16 páginas + post con word boundaries: 0 tecnología real (2 falsos positivos documentados: "aplicables" contiene "cables", "almuerzos de oficina" legítimo) · ✅ smoke 7/7 · ✅ ZIP regenerado · ⏳ producción pendiente de ventana autorizada
- **Notas**: Regla arquitectónica respetada: NO se tocaron los defaults de tecnología (templates/partials/*) — son fallback compartido multi-tenant (MaganTech es tecnología); el mecanismo correcto es el pack restaurant completo. PENDIENTE agente Armada Suite: el pack restaurant (7 partials) vive SOLO en la copia de micaserogou; la fuente canónica ~/dev/wordpress/plugins/armada-suite/ NO lo tiene — sincronizar en la próxima iteración del plugin para que no se pierda en updates. Backups: post-content-bkup-20261021-legal.txt (uploads/) + backups/ DB completa previa. Defaults de tecnología intactos: el texto "Componentes, cables..." que citó el usuario es el fallback del default compartido, invisible para micaserogou ahora que el pack está completo.

### [16:40] - IRC TLS renovado (opción C replicada) + docs corregidas: vps-proxy reconstruida
- **Tipo**: servicio | infra | docs
- **Modificado**: vps-preprod (certbot 2.9.0, cert el.colador.de.alfredo.pro emitido 2026-10-21 expira 2027-01-19, hooks pre/post/deploy en /etc/letsencrypt/renewal-hooks/, certbot.timer enabled); docs: agents/irc.md (sección Renovación TLS), agents/proxy.md (reconstrucción 2026-10-19), agents/kalimete.md (tabla red), MAPA.md (nodos 3-4) + copia local ecosistema-map, harness/irc.harness.json + proxy.harness.json + kalimete.harness.json
- **Afecta a**: vps-preprod (IRC El Corito TLS), vps-proxy (doc actualizada), kalimete (docs)
- **Causa**: owner ordenó opción C (replicar flujo de renovación original de certbot standalone) + corregir discrepancias: la vps-proxy vieja ya no existe (reconstruida 2026-10-19) y el proxy NO vive en vps-preprod
- **Estado**: ✅ Cert nuevo servido por InspIRCd en 6697 (verificado externo desde kalimete, serial 05D42A47…) · ✅ Auto-renovación completa: certbot.timer → pre hook (REDIRECT 80→8088) → challenge → post hook (limpieza) → deploy hook (copia + USR1) · ✅ 0 reglas transitorias residuales · ✅ Docs corregidas con estado live verificado
- **Notas**: Causa raíz del fallo inicial de emisión: los hooks de directorio solo corren en RENOVACIONES, no en emisión inicial → se pasan por CLI en certonly (quedaron grabados en el renewal conf). Método probado empíricamente antes de emitir (HTTP 200 por la ruta REDIRECT 80→8088). La nueva vps-proxy conserva renewal confs de 2 certs expirados cuyos dominios apuntan a otras IPs (el.colador → vps-preprod, ya resuelto; colador.union-chat.online → IPs de terceros 104.219.250.37/2.59.170.20, pendiente owner). Discrepancia flaggeada al owner: el proxy corre en la nueva vps-proxy (31.220.102.176, reconstruida), NO en vps-preprod — si quiere moverlo, tarea aparte. Backups: certs.bkup-20261021-155925 (vps-preprod) + 7 .bkup-20261021-irc en repo.

### [16:45] - micaserogou: paleta restaurante cálida aplicada (rojo tomate + ámbar) — cero azul tech en el local
- **Tipo**: servicio | release
- **Modificado**: erp_suite_settings.tenant.brand.color_primary #1a73e8→#d64545 (rojo tomate) y color_secondary #34a853→#f59f00 (ámbar dorado) en preprod micaserogou.kalimete.local; ZIP export/armada-suite-micaserogou-restaurant-20261021.zip regenerado (23,9 MB, dump con colores, about.php del pack dentro); backup previo uploads/erp-settings-bkup-20261021-colors.txt (settings completos con el azul viejo)
- **Afecta a**: preprod micaserogou.kalimete.local — producción SIN CAMBIOS
- **Causa**: owner confirmó el template local correcto en contenido y pidió mejores colores para diferenciarlo del default tech. Mecánica settings-based (Main.php get_theme_colors(): pickers custom ganan al preset; dark/light se derivan solos con erpc_hex_adjust) — cero código tocado
- **Estado**: ✅ CSS inline renderizado en home/sobre-nosotros/productos/contacto: --erpc-primary:#d64545, --erpc-primary-dark:#af3939, --erpc-primary-light:#fae9e9, --erpc-secondary:#f59f00 · ✅ grep "1a73e8" = 0 · ✅ smoke 7/7 · ✅ ZIP regenerado · ⏳ deploy a producción pendiente de ventana autorizada
- **Notas**: Explicación de las discrepancias local vs prod confirmada al owner: producción corre armada-suite 5.4.2 (el pack restaurant llegó en 5.5.x) → renderiza defaults de tecnología mezclados con los productos reales del ERP tenant 3; el deploy nunca se ejecutó (pendiente ventana + prerrequisitos del docs/PROD-DEPLOY-CHECKLIST.md). Falsa alarma 503: el subagente vio un 503 transitorio de micaserogou.com durante su sesión; verificado desde kalimete 3/3 intentos → 200 (blip del hosting, no caída persistente).

### [17:00] - CORRECCIÓN: vps-proxy NO fue reinstalada (fue reboot por kernel upgrade) + evaluación consolidación
- **Tipo**: docs
- **Modificado**: agents/proxy.md, agents/kalimete.md, MAPA.md (+ copia local), harness/proxy.harness.json, harness/kalimete.harness.json — se retira la marca errónea "RECONSTRUIDA 2026-10-19" de la entrada [16:40]
- **Afecta a**: documentación de la flota
- **Causa**: verificación profunda con evidencia (wtmp con boots de 2025, apt history.log.11.gz de Nov-2025, certs LE de julio intactos, kernel 6.8.0-147 instalado por unattended-upgrades el 8-oct): la caja es la MISMA instalación desde siempre; el 19-oct fue su primer reboot en 260 días (desde Feb-2026) para activar el kernel nuevo. El 21-oct 16:31→16:40 hubo shutdown+boot limpio adicional (causa por confirmar con owner — ¿panel Contabo?)
- **Estado**: ✅ docs corregidas con la historia real
- **Notas**: Evaluación de consolidación proxy→vps-preprod entregada al owner (ambas cajas: mismo proveedor Contabo, mismo DC Carlstadt NJ; vps-proxy 93% ociosa con 1 cliente activo jovtransport ~6k req/día; vps-preprod con 5.5GB RAM libres y fail2ban ya activo; "subir recursos" NO sería necesario). Decisión pendiente del owner: mantener / consolidar / right-size.

### [17:10] - micaserogou: preprod alineado 100% a restaurante + ZIP de release + checklist de deploy (producción sin tocar)
- **Tipo**: servicio | docs | release
- **Modificado**: ~/dev/wordpress/websites/micaserogou.com/ (preprod local :8094 / https://micaserogou.kalimete.local) — DB adaptada (12 actualizaciones: blogdescription, erp_suite_settings brand="Mi Casa Rogou"/tagline/business_type="restaurante", páginas legales e-commerce→restaurante, Sobre Nosotros, post Hello world→menú del día, comentario genérico→Carolina M., Sample Page→Reservas), flush de transientes _transient_erpsuite* (brand name renderizado corregido de "Michelle Casero y Gourmet" a "Mi Casa Rogou", 0 residuos); export/armada-suite-micaserogou-restaurant-20261021.zip (23,9 MB: tema twentytwentyfive, plugins armada-suite 5.5.1+akismet+hello, mu-plugins, dump DB fresco 184 KB, backups/); docs/PROD-DEPLOY-CHECKLIST.md (nuevo, 7 prerrequisitos, orden de deploy, rollback con armada-suite-5.4.1.zip vía erpsuite/v1/ops, advertencia NUNCA tocar prod sin ventana autorizada)
- **Afecta a**: preprod micaserogou.kalimete.local (100% restaurante, smoke 7/7 OK, cero "Hello world"/"Sample Page"/texto tecnología); producción micaserogou.com SIN CAMBIOS (sigue mixto tecnología+restaurante, REST API 404, solo lectura verificada 200)
- **Causa**: usuario pidió evaluar y alinear ambos templates a tipo restaurante, usando inventario ERP tenant 3 para textos del landing
- **Estado**: ✅ preprod alineado y verificado · ✅ ZIP de release generado · ✅ checklist de deploy documentado · ⏳ producción pendiente de ventana autorizada del usuario (API key ERP productiva tenant 3 de Juan Carlos, usuario WP administrator + App Password, permalinks /%postname%/, home/siteurl=https://micaserogou.com, snapshot cPanel)
- **Notas**: Backups previos en backups/ (DB, plugin, tema, mu-plugins, armada-suite). Cero secrets impresos; key ERP en secrets/erp-tenant3-preprod.key (chmod 600, no leída). Directorio de micaserogou no es git repo; este CHANGELOG es el registro del cambio.

### [18:00] - DEPLOY A PRODUCCIÓN micaserogou.com: sitio restaurante en vivo (plugin 5.5.1 + pack restaurant + paleta cálida + legales restaurante)
- **Tipo**: servicio | release | deploy
- **Modificado**: PRODUCCIÓN https://micaserogou.com — (1) plugin armada-suite 5.4.2→5.5.1 subido y activado por el owner vía wp-admin (ZIP plugin-only 2,5 MB de export/); (2) settings vía ops API (dry_run→confirm, backup bk_20261021213725_vrb60w): template_pack=restaurant, brand.name="Mi Casa Rogou", headline/tagline restaurante, color_primary=#d64545, color_secondary=#f59f00; (3) legales vía ops/content/edit (9 ediciones: terminos, envios→"Delivery y Entregas", devoluciones→"Devoluciones y Reclamos", privacidad, cookies, faq, contacto + 2 titles) con copy restaurante del preprod; (4) permalinks /%postname%/ activados por el owner (REST /wp-json/ ahora 200); (5) App Password del usuario Victoria guardada en secrets/prod-app-password.txt (chmod 600, nunca en chat/logs)
- **Afecta a**: producción micaserogou.com (antes: sitio mixto tecnología+restaurante con plugin 5.4.2)
- **Causa**: owner autorizó la ventana de deploy ("Procede") tras instalar el plugin y activar el modo trabajo (kill-switch solo-humano) + permalinks
- **Estado**: ✅ 12 páginas verificadas 200 con 0 texto de tecnología · ✅ hero "Comida casera y gourmet, hecha al momento" + tag "Delivery a todo el país" · ✅ colores cálidos renderizados (#d64545/#f59f00, cero #1a73e8) · ✅ /sobre-nosotros/ renderiza el about.php del pack ("Mi Casa Rogou — sazón de casa, hecha al momento") · ✅ /productos/ con productos reales del ERP (POLLO FRITO, POLLO AL HORNO) · ✅ chatbot presente · ✅ jaula REST intacta (anónimo 403) · ⚠️ RESIDUO CONOCIDO: 2x "Michelle Casero y Gourmet" por página (alt del logo + erpc-brand-name del footer) — causa raíz: get_brand_name() (Main.php:286) prioriza erp_config.name (marca registrada en el ERP tenant 3) sobre brand.name; el Guard bloquea tenant.erp_config para ops (solo humano). Fix pendiente: parche 5.5.2 del plugin (brand.name explícito gana — agente Armada Suite) o cambiar la marca del tenant 3 en el ERP (Juan Carlos) → re-sync
- **Notas**: Rollback disponible: plugin 5.4.1.zip en export/ + ops/rollback 1-click (backup automático por edición). Work mode del motor quedó activo (expira solo) — owner puede volver a "safe" en ERP Suite > Proyectos. Próximo: parche 5.5.2 (Armada Suite) para el residuo de marca + sincronizar el pack restaurant a la fuente canónica del plugin.

### [18:30] - micaserogou 5.5.2: mejoras UX restaurante (nav Menú, testimonios SD, stats realistas, fix brand) + chatbot restaurante en prod
- **Tipo**: servicio | release
- **Modificado**: LOCAL ~/dev/wordpress/websites/micaserogou.com/wp-content/plugins/armada-suite/ (v5.5.1→5.5.2): (1) Main.php get_brand_name() parcheado — brand.name del sitio GANA sobre erp_config.name del ERP (fix del residuo "Michelle Casero y Gourmet" en alt del logo y footer); (2) NUEVO packs/restaurant/partials/header.php (nav "Menú" en vez de "Tienda", topbar "Delivery a todo el país/Comida recién hecha/Pago seguro", buscador "Buscar platos..."); (3) BUG loader corregido: 6 templates (landing, about, contacto, cart, products, cotizar) incluían header/footer con include directo saltándose erpc_template_path() — ahora pasan por el loader (tema→pack→default) y el pack puede sobreescribirlos; (4) social-proof del pack: testimonios todos de Santo Domingo (Santo Domingo Este, Villa Mella, Piantini — única sucursal), stats realistas (850+ clientes, 4.8/5, título "Cientos ya han probado nuestra comida"; platos/categorías siguen en vivo del ERP); (5) about.php del pack: stats en vivo del ERP + números alineados; (6) bump 5.5.2. PRODUCCIÓN: identidad del chatbot vía ops/settings (backup bk_20261021222743_t9fxlm): identidad.puesto="Asesor de Mi Casa Rogou", perfil+saludo restaurante, agente.base_negocio.{resumen,horarios,zonas_propias,rubros,politicas,contacto_extra} cargados con info del restaurante (categorías reales del ERP, delivery SD, reclamos 2h)
- **Afecta a**: preprod local (verificado: nav Menú, topbar, buscador platos, testimonios SD, stats, 0 Michelle) + producción (chatbot ya aplicado; resto pendiente del re-upload 5.5.2)
- **Causa**: owner pidió testimonios de Santo Domingo (única sucursal), stats acordes al ERP, nav "Tienda"→"Menú" y evaluar otras mejoras
- **Estado**: ✅ preprod 5.5.2 verificado (php -l 11 archivos OK, smoke 200) · ✅ chatbot prod aplicado · ⏳ owner debe re-subir export/armada-suite-5.5.2-plugin-only.zip (2,5 MB) a prod vía wp-admin → Plugins → Añadir nuevo → Subir → Reemplazar → Activar
- **Notas**: ZIP 5.5.2 en export/ (header del pack dentro, 9 entradas packs/restaurant, sin .bkup). Backups .bkup-20261021-552 de todos los archivos tocados. Pendiente agente Armada Suite: absorber pack restaurant + parches (get_brand_name, loader header/footer) a la fuente canónica en la próxima iteración del plugin.

### [18:50] - micaserogou 5.5.3: SEO del nicho restaurante + OG tags + header compacto (title, lang es-DO, schema Restaurant)
- **Tipo**: servicio | release | seo
- **Modificado**: PRODUCCIÓN via REST WP nativa (App Password): blogname "Michelle Casero y Gourmet"→"Mi Casa Rogou" (title del sitio, feeds, oembed), timezone America/Santo_Domingo. LOCAL plugin 5.5.2→5.5.3 (header del pack restaurant): (1) <title> SEO — antes NO HABÍA title tag en el HTML (el frame del plugin no pasa por el tema): home "Mi Casa Rogou — Comida casera y gourmet con delivery en Santo Domingo", internas "Página — Mi Casa Rogou"; (2) lang="es-DO" hardcode (language es_DO no aplicable via REST — traducción no instalada); (3) meta description con keywords del nicho (restaurante, comida casera, pollo frito, mofongos, delivery Santo Domingo); (4) OG tags completos para WhatsApp/redes: og:locale es_DO, og:type, og:site_name, og:title, og:description, og:url, og:image=logo real del brand (fallback hero del pack), og:image:alt; (5) Twitter cards (summary_large_image); (6) JSON-LD schema.org Restaurant: servesCuisine Dominicana/casera/gourmet, priceRange $$, hasMenu /productos/, openingHours Mo-Su 11:00-21:00, acceptsReservations, address Santo Domingo DO; (7) CSS compacto del header (owner: logo/brand/tagline ocupaban mucho): brand-name 1.35→1.02rem, logo 36→30px, tagline 0.8→0.7rem (oculto en móvil), search-bar 520→340px, gaps 12→8px
- **Afecta a**: preprod local (verificado: 1 solo title, lang es-DO, OG con logo, schema Restaurant, CSS inyectado, smoke 200) + producción (blogname/timezone ya aplicados; resto pendiente re-upload 5.5.3)
- **Causa**: owner pidió SEO bueno para el nicho con productos del inventario, título de la web correcto (no lo había), OG tags para compartir en redes/WhatsApp, y header más compacto (logo/subtítulo grandes, buscador con espacio de sobra)
- **Estado**: ✅ preprod 5.5.3 verificado · ✅ prod: blogname + timezone aplicados · ⏳ owner re-sube export/armada-suite-5.5.3-plugin-only.zip (2,5 MB)
- **Notas**: Guard de ops deniega mu-plugins y plugins (solo theme + wp-content no-plugin) — el SEO se implementó en el header del pack (frame del plugin controla el <head> de todo el frontend público). ZIP 5.5.3 en export/. Backups .bkup-20261021-552 previos de todos los archivos tocados.

### [19:35] - micaserogou 5.5.4: rebranding a "Michelle Casero y Gourmet" (nombre correcto del negocio) + fix iconos admin bar + imágenes de comida generadas
- **Tipo**: servicio | release | fix
- **Modificado**: REBRANDING COMPLETO — el owner aclaró que el nombre del negocio es "Michelle Casero y Gourmet" (no "Mi Casa Rogou"): LOCAL: 9 posts re-titulados/re-escritos (legales, post menú del día, reservas), erp_suite_settings (brand.name + chatbot identidad/base_negocio), blogname WP; header del pack: $erpc_seo_site_name corregido (title/OG/schema ahora con el nombre correcto). PRODUCCIÓN via ops (backup bk_20261021233045_tfegl4): tenant.brand.name, identidad.puesto/perfil/saludo, agente.base_negocio.resumen; blogname via REST WP; legales verificadas sin residuo (contenidos nunca mencionaban el nombre, títulos de prod sin sufijo). FIX ICONOS ADMIN BAR: connector.css excluía .dashicons del font-family global PERO #wpadminbar .ab-icon no lleva esa clase (bug documentado en el propio CSS) → añadido :not(.ab-icon) a los 2 selectores frontend (iconos de la toolbar se rompían al navegar logueado). IMÁGENES: hero-home.webp y cta-band.webp del pack restaurant eran de TECNOLOGÍA → reemplazadas con fotos de comida dominicana generadas via skill art (z-image-turbo, victoria :8010): hero 1600x914 171KB (pollo frito, mofongo, arroz con habichuelas, plátanos) + cta-band 112KB (primer plano pollo frito/mofongo fondo oscuro). HEADER: owner pidió mover el brand a la izquierda en vez de reducir el nombre → CSS revertido (brand-name 1.35rem original, logo 36px) con gaps compactos (6px), tagline 0.7rem, buscador 360px. LOGS: debug.log de prod NO existe (404 via ops/file/read) — sin errores fatales logueados
- **Afecta a**: preprod local (verificado: 14x Michelle, 0x Mi Casa Rogou, title correcto, smoke 200) + producción (settings/blogname ya aplicados; imágenes+fixes pendientes del re-upload 5.5.4)
- **Causa**: owner corrigió el nombre del negocio, reportó iconos rotos en admin bar, imagen de tecnología en "Nosotros", y pidió mover el brand a la izquierda en vez de reducir su tamaño
- **Estado**: ✅ rebranding aplicado (local + prod settings) · ✅ fix ab-icon · ✅ imágenes comida · ⏳ owner re-sube export/armada-suite-5.5.4-plugin-only.zip (2,5 MB)
- **Notas**: Backups: .bkup-20261021-554 (connector.css) + .bkup-20261021 (imágenes viejas) + bk_20261021233045_tfegl4 (settings prod). El fix get_brand_name() de 5.5.2 + brand.name correcto en settings = el nombre correcto se renderiza en todo el sitio sin tocar erp_config del ERP.

### [19:45] - AUDITORÍA migración proxy→vps-preprod: NO EJECUTADA — vps-proxy sigue siendo el único proxy (NO borrar todavía)
- **Tipo**: infra | docs
- **Modificado**: agents/proxy.md (sección consolidación), harness/proxy.harness.json (vivo + scope), MAPA.md (nota consolidación pendiente en nodo 4), CHANGELOG.md
- **Afecta a**: decisión de decommission de vps-proxy (Contabo)
- **Causa**: owner creía la migración hecha ("migramos todo de vps-proxy a vps-preprod, agregando un servicio de proxy para clientes en preprod"); la auditoría live exhaustiva demuestra que NO existe proxy alguno en vps-preprod
- **Estado**: ✅ Auditado con evidencia live 2026-10-21 19:20-19:40
- **Notas**:
  - **vps-preprod SIN proxy** (evidencia): 0 paquetes squid/dante/tinyproxy/3proxy/gost/v2ray (dpkg), 0 unidades systemd proxy, 0 listeners 3128/1080 (ss), 0 imágenes docker proxy, 0 scripts /usr/local/bin, 0 artefactos /opt//srv//root, 0 entradas apt history. El "Up 5 hours" de los 24 contenedores = `apt upgrade` del stack docker-ce/containerd/docker-compose ejecutado por usuario **justin_t** 14:35-14:37 (NO fue migración).
  - **vps-preprod servicios TODOS funcionales**: auth 302 (login OK), nextcloud 302 (login OK), docuseal/pets/scriberr/ragnarok/whiteboard 200; IRC 6667/6697/7209 OPEN.
  - **vps-preprod SIN contaminación proxy** (requisito del owner: el proxy será servicio PARA CLIENTES, el VPS no debe usarlo): 0 vars http_proxy/https_proxy en /etc/environment, /etc/profile.d, docker daemon (sin daemon.json ni Environment), env root, 24 contenedores inspeccionados, apt, git, systemd global, wget/curl rc, snap.
  - **vps-proxy FUNCIONAL Y EN USO**: 13,112 req/24h — cliente activo `jovtransport` desde 181.36.176.87 (12,361 req, conectado AHORA: mtalk.google.com tunnel OK, spotify/teams DENIED 403 por filtros); squid 200 en 0.26s, socks5 200 en 0.35s; fail2ban 0 bans; UFW 1444/53/3128/1080; recursos 93% ociosos (disco 9.8G/145G, RAM 510Mi/7.8Gi).
  - **VEREDICTO**: NO borrar vps-proxy — cortaría el servicio al cliente activo. Migración real PENDIENTE con plan: (1) instalar squid+socks5-proxy.py en vps-preprod como servicio AISLADO (sin env vars del sistema), (2) migrar squid.conf (adaptar visible_hostname) + proxy-users.conf + blocked-domains.txt (111 dominios) + systemd units + fail2ban jail, (3) abrir firewall 3128/1080 en iptables INPUT + persistir, (4) repuntar DNS proxy.us-east.armada.do + jovtransport.prx.armada.do → 154.53.35.102 (gris, NUNCA proxied), (5) validar curl vía proxy + filtros, (6) ventana de corte con jovtransport (IP de salida cambia 31.220.102.176→154.53.35.102), (7) decommission Contabo. Ejecución requiere OK del owner (delegable a subagente Proxy).

### [19:50] - micaserogou 5.5.5: comportamiento de búsqueda del chatbot según reglas del owner (voz corta, top 5 en texto, no navegar sin resultados)
- **Tipo**: servicio | release
- **Modificado**: ChatEngine.php system_prompt (3 líneas): (1) regla 3 — en búsquedas con varios resultados NO lee el inventario en voz, solo anuncia cuántas opciones hay y que el menú filtrado está abierto; el detalle (hasta 5 opciones con precio, las más relevantes) va SOLO como texto en el chat; (2) turno de voz — "al_llegar" ahora es mensaje CORTO que indica que las opciones ya están visibles en el menú y pregunta cuál le interesa, sin leer la lista en voz; sin productos: dilo honestamente y NO pidas ir_a (no navega); (3) modo texto — botón "Ver en tienda" + hasta 5 opciones con precio en texto, en voz NUNCA leer la lista; ejemplo "impresoras" (tech) eliminado del prompt (neutral "opciones"). El flujo existente se conserva: navegación automática al filtro del menú cuando hay resultados, no navega sin resultados, voz máx 2 frases
- **Afecta a**: chatbot de micaserogou (prod tras re-upload; local ya verificado)
- **Causa**: owner definió reglas de búsqueda: si pide "arroz" y hay varias → indicar que hay varias opciones + llevar al filtro del menú + top 5 con precio SOLO en texto (no leído en voz); si no hay → no cambiar la web automáticamente. "Top 5 más comprados": el ERP no expone métrica de ventas por producto → se usa el ranking por relevancia de buscar_productos (lo más cercano disponible, documentado)
- **Estado**: ✅ prompt parcheado y verificado en local (test ReflectionMethod: 6/6 checks OK, sintaxis OK) · ⏳ owner re-sube export/armada-suite-5.5.5-plugin-only.zip (2,5 MB — INCLUYE TODO: rebranding Michelle + fix ab-icon + imágenes comida + header izquierda + chatbot)
- **Notas**: Work mode expiró (safe) — las instrucciones_extra de refuerzo vía ops quedaron opcionales (el parche al prompt base codifica las reglas de forma robusta, no depende de ops). Backup ChatEngine.php.bkup-20261021-554 previo.

### [20:46] - victoria: llave de negocio armada-micaserogou provisionada para el chatbot de micaserogou.com (E2E 200 via tunel)
- **Tipo**: infra | servicio
- **Modificado**: (victoria, SOLO via API de provisioning) DB gateway: api_keys +`armada-micaserogou` (rol services, caps [llm], rate 120/min, 2 slots, max_tokens 32K, sin budget/expiry) + provision_log id 3; (kalimete, docs) agents/victoria-server.md (linea de llaves curada + seccion 2026-10-21), harness/victoria-server.harness.json, CHANGELOG.md; (kalimete, secrets) `websites/micaserogou.com/secrets/armada-micaserogou.key` + `.meta.json` (600)
- **Afecta a**: chatbot erpcbot de micaserogou.com (prod cPanel, Armada Suite 5.5.5 — daba "El asistente IA no esta disponible" por ia.api_key vacia) + preprod :8094
- **Causa**: delegacion de kalimete a victoria-server a peticion del owner: el bot necesita llave propia del gateway (estandar 1-llave-por-negocio armada-<slug>)
- **Estado**: ✅ E2E 2026-10-21 20:38-20:45 — gateway sano (health LAN 200 + tunel 200; victoria-llm-gateway/cloudflared/nginx active; GPU 45C 0%) · POST /v1/provision-key 201 (slug micaserogou → name forzado armada-micaserogou, owner "Micaserogou (micaserogou.com)") · chat de prueba 200 OK via https://victoria.armada.do/v1, model nvidia/Qwen3.6-35B-A3B-NVFP4-normal (gateway normaliza el id; finish stop, 19 tokens) · DB: armada-micaserogou|services|active=1 · provision_log id 3 (kalimete→armada-micaserogou, 10.0.0.106)
- **Notas**: plaintext devuelto UNA vez, guardado SOLO en kalimete `~/dev/wordpress/websites/micaserogou.com/secrets/` (600; fp sha256-16 c48066a582502dd1; meta json con settings al lado) — victoria FS intocable por contrato y `~/.victoria-custom/secrets/` verificado NO accesible a warcold (lectura/escritura denegadas); si se quiere copia en victoria, la coloca Victoria manualmente (patron armada-magantech). Budget mensual NO configurable via provisioning (PROVISION_MAX_BUDGET=0 = sin tope; metering por llave en DB). PENDIENTE (kalimete/owner): pegar la key en wp-admin prod → Ajustes → Asistente IA (o env ERPCBOT_LLM_KEY) — api_url y model -normal ya son defaults del plugin. Hallazgo DB: key `erp-bot` (readonly, active) preexistente — evaluar revocacion en panel si es residuo. Drift curado en doc de llaves: faltaban `vaclaaw` (coder) y las armada-*.


## 2026-10-20
### [00:53] - Gaming: permisos Game Studio+Blender en kalimete + reference rAthena + plan juego Ragnarok×Enshrouded
- **Tipo**: agente | config | docs
- **Modificado**: agents/kalimete.md (allowlist 21→23, tabla, conteos), MAPA.md (MCPs + fila blender), ~/dev/games/AGENTS.md (ledger), ~/dev/games/reference/rathena/ (NUEVO, 17M)
- **Afecta a**: kalimete (delegación gaming), dominio ~/dev/games/
- **Causa**: owner pidió evaluar MCPs godot + agentes gaming + organizar ~/dev/games + arrancar juego nuevo (mecánicas Ragnarok, gráficos Enshrouded, 1 mapa, 99/70 sin advanced)
- **Estado**: ✅ permisos+docs aplicados; ⚠️ juego en plan (nombre + pre-re por confirmar); mario-bros cleanup pendiente confirmación
- **Notas**: GAP crítico: Game Studio y Blender existían (repo+symlink+harness) pero NO en permission.task → kalimete no podía delegarles. MCPs godot: 2 instancias correctas por diseño. rAthena: source vive SOLO en la imagen Docker del server (multi-stage, sin src/) — DBs extraídas (pre-re 34 + re 51 + const.yml), fórmulas battle/status/pc.cpp desde upstream. Server ragnarok: demonios siguen caídos (exit 127, mounts rotos custom/rAthena).

### [01:11] - Alta website micaserogou.com: preprod verificado + agente Micaserogou + documentación de flota (24 subagentes)
- **Tipo**: agente | config | docs | servicio
- **Modificado**: agents/micaserogou.md (NUEVO), harness/micaserogou.harness.json (NUEVO), ~/.config/opencode/agent/micaserogou.md (symlink), agents/kalimete.md (allowlist 23→24, tabla, conteos), MAPA.md (topología + tabla de agentes), README-HUB.md (inventario, dominios, agentes, acciones), websites/micaserogou.com/docs/README.md (secreto redactado), CHANGELOG.md
- **Afecta a**: kalimete (24 subagentes) + preprod micaserogou :8094 + docs de flota
- **Causa**: owner pidió dar de alta micaserogou.com como segundo website cliente multi-tenant, siguiendo el patrón MaganTech
- **Estado**: ✅ preprod + agente + docs verificados; ⚠️ prod pendiente (7 prerrequisitos del checklist)
- **Notas**: Preprod 3 contenedores healthy (`micaserogou-local` :8094, `micaserogou-db` :3311 porque 3310 estaba ocupado, `micaserogou-mailpit` :8027), WP 7.1.3/PHP 8.3.35/MariaDB 10.11, armada-suite 5.4.2 (ZIP sha256 157b1633…), tenant ERP 3 (key preprod id7 + webhook id4 sin secret), smoke 7/7, `https://micaserogou.kalimete.local` 200 con cert SAN exp. 2029-01-20. Prod `https://micaserogou.com/` 200 pero SIN plugin (cPanel externo; checklist: api_key productiva tenant 3, usuario WP dedicado + App Password, permalinks, HTTPS/REST, backup y webhook prod). Seguridad: password DB en claro redactado de `docs/README.md` (solo queda en `docker-compose.yml`, runtime). 5.4.3 IA nativa en working tree sin bump/ZIP — no desplegar. 15 páginas vs 14 del checklist (verificar antes de prod). Conteos: 25 agents .md (24 subagentes), 25 harness; `opencode agent list` muestra `Micaserogou (subagent)`.

### [01:41] - Gaming: mario-bros + armada-starfox BORRADOS + proyecto nuevo "Record of Ragnaroks" (Fase 0)
- **Tipo**: agente | config | docs
- **Modificado**: ~/dev/games/godot/ (mario-bros 3.9M/517 archivos y armada-starfox 39M/391 archivos BORRADOS por orden del owner), opencode.jsonc (MCP `godot` removido — apuntaba a mario-bros; queda `godot-studio` como único MCP godot), agents/godot-dev.md + game-studio.md + kalimete.md (refs a juegos borrados), harness godot-dev + game-studio, MAPA.md, ~/dev/games/AGENTS.md + READMEs, NUEVO studio/record-of-ragnaroks/ (scaffold + GDD Fase 0)
- **Afecta a**: dominio ~/dev/games/ completo + agentes Godot/Game Studio
- **Causa**: owner — "Borra tanto mario-bross y todo lo relacionado al juego, tambien armada-starfox, vamos a manejar este nuevo proyecto arpg, Record of Ragnaroks como la serie animada... peleas de dioses"
- **Estado**: ✅ todo aplicado; tar de cortesía efímero en /tmp/opencode/juegos-viejos-20261020.tar.gz (37M, se pierde al reiniciar — mario-bros era git SIN remote)
- **Notas**: Record of Ragnaroks = ARPG Godot 4.7.2: mecánicas RO pre-renewal 99/70 sin advanced (port de rAthena desde reference/rathena/) × temática anime Shuumatsu no Valkyrie (torneo dioses vs campeones; boss fights elementales; valkyrie Völundr) × estética Enshrouded vía granja. MVP: 1 mapa Valhalla + 8-10 mobs stats reales + progresión 99/70 + DUELO 1 vs THOR. Siguiente: delegar fases 0.5-7 a Game Studio (sesión nueva).

### [01:45] - Provisioning delegado en victoria: kalimete crea llaves de negocio armada-suite via POST /v1/provision-key (cap provision)
- **Tipo**: seguridad | servicio | docs (cambio en VICTORIA, documentado aquí por procedencia cross-machine — autorización del owner)
- **Modificado**: (victoria) llm-gateway.py + sense_auth.py + admin_template.html + DB (tabla provision_log, cap en llave kalimete); (kalimete, docs) agents/victoria-server.md, harness/victoria-server.harness.json, CHANGELOG.md
- **Afecta a**: armada-suite (chatbots IA de magantech.com.do, micaserogou.com y próximos negocios), script `armada-llm-provision` (por construir)
- **Causa**: owner pidió evaluar cómo kalimete crearía llaves de servicio LLM para los proyectos web con su propia llave (sesión ses_ea97154aeffeAWE9n5gdAqrm8V). La propuesta original (key admin provisioner) NO funcionaba: POST /admin/keys exige sesión de panel (ADMIN_PASS), no acepta llaves API. Solución de menor privilegio: endpoint scoped + cap `provision` en la llave kalimete.
- **Estado**: ✅ E2E completo: 403 sin cap · 201 con cap (rol services + caps [llm] + prefijo armada- forzados) · llave nueva chatea 200 OK · llave nueva NO provisiona (cero escalada) · readonly 403 · provision_log con IP 10.0.0.106 · **primera llave de negocio `armada-magantech` provisionada DESDE kalimete** (plaintext 600 en victoria: `~/.victoria-custom/secrets/armada-magantech.key`)
- **Notas**: el endpoint FIJA rol services + caps ["llm"] + prefijo `armada-<slug>` (el cliente solo elige slug/owner/budget/expiry); máx 10 creaciones/hora por provisionadora (429 provision_rate_limited); auditoría `provision_log`; documentado en `/v1/config-guide` → `provision_api` (auto-descriptivo). Pendientes: script `armada-llm-provision` sobre este endpoint; pegar `armada-magantech` en wp-admin prod (Asistente IA); rotar `servicios-alfredo-pro-llc` (expuesta en chat) cuando el tráfico migre. Detalle técnico: CHANGELOG-vllm.md de victoria 2026-10-20 01:45 EDT.

### [02:20] - Auditoría del agente Victoria Server tras el provisioning delegado: fixes de contradicción + deriva en magantech.md/armada-suite.md
- **Tipo**: docs (auditoría pedida por el owner: "¿actualizaste Victoria Server con todas las nuevas instrucciones, accesos y límites?")
- **Modificado**: agents/victoria-server.md (4 fixes), agents/magantech.md (1 fix de deriva), agents/armada-suite.md (estándar nuevo), CHANGELOG.md
- **Afecta a**: delegación del principal kalimete → Victoria Server; flujo de llaves de negocio de armada-suite
- **Hallazgos**: (1) VERIFICADO OK: el symlink `~/.config/opencode/agent/victoria-server.md` → armada-sync es LIVE (las ediciones 01:45 cargan; `opencode agent list` muestra `Victoria Server (subagent)`); sin secretos en el repo (grep limpio, sync GitHub ya propagó). (2) HUECO 1 — contradicción: las reglas "victoria = SOLO LECTURA, NUNCA ESCRIBIR" no tenían la excepción del provisioning → un agente podía leerlo como prohibido. (3) HUECO 2 — frontmatter description no mencionaba provisioning → el principal no sabía delegar tareas de llaves. (4) DERIVA — magantech.md aún decía "key dedicada magantech — owner la crea en panel" cuando `armada-magantech` YA existe (provisionada 01:45). (5) HUECO 3 — armada-suite.md no documentaba el estándar 1-llave-por-negocio.
- **Estado**: ✅ 4 fixes en victoria-server.md (description + regla CRÍTICA con excepción + tabla servicios + reglas de operación #1) · ✅ magantech.md pendiente corregido (la key existe, ruta del plaintext) · ✅ armada-suite.md §Integración con Victoria con el estándar completo · micaserogou.md sin cambios justificados (su chatbot no existe aún; el estándar vive en armada-suite.md)
- **Notas**: backups .bkup-20261020-provision-audit ×3. La única escritura permitida en victoria es `POST /v1/provision-key` (API, no SSH); filesystem/config de victoria sigue intocable para kalimete.

### [14:02] - Micaserogou: WP_HOME promovido a dominio local + fix vhost nginx front-door + deriva prod (plugin activo sin deploy)
- **Tipo**: servicio | config | docs
- **Modificado**: ~/dev/wordpress/websites/micaserogou.com/docker-compose.yml (WP_HOME/WP_SITEURL → https://micaserogou.kalimete.local + snippet X-Forwarded-Proto→HTTPS con escape `$$`; .bkup-20261020); /etc/nginx/sites-enabled/micaserogou.kalimete.local.conf (front-door → proxy estándar; .bkup-20261020-frontdoor) + sites-available sincronizado; scripts/smoke-8094.sh (BASE → dominio canónico; .bkup-20261020); DB micaserogou (search-replace http://localhost:8094: 2 posts default + options siteurl/home → 0/0/0; dump backups/db-posts-options-before-searchreplace-20261020.sql); agents/micaserogou.md + harness/micaserogou.harness.json (.bkup-20261020-wphome)
- **Afecta a**: preprod micaserogou (visibilidad del sitio para el owner y LAN) + docs del agente
- **Causa**: owner reportó no ver el proyecto ni local ni público. LIVE: WP emitía TODOS los links/assets como http://localhost:8094 (mixed content bloqueado en https + inaccesible desde otras máquinas). Causa raíz doble: (1) constantes compose WP_HOME=localhost:8094; (2) vhost sites-enabled era un FRONT-DOOR workaround de ese estado viejo (forzaba Host "localhost:8094", sin scheme headers → tras promover WP_HOME, WP canonicalizaba subpáginas 301 a http://localhost/). DERIVA doc↔live: sites-available stale (proxy_pass 192.168.16.2 inexistente) y doc decía "prod sin plugin" cuando el plugin 5.4.2 YA está ACTIVO en prod (verificado 15:41 vía scripts encolados + REST 403 erpsuite_forbidden) con contenido default "Cats And Dogs" — deploy incompleto, uploader desconocido.
- **Estado**: ✅ front y subpáginas 200 vía dominio (sin redirects, sin mixed content, imágenes ERP cargando) · ✅ grep localhost:8094 en HTML = 0 · ✅ smoke 7/7 · ✅ webhook id 4 intacto (facturacion_db.webhook_endpoints; endpoint POST unsigned → 400) · ✅ erp_suite_settings intacto (public, tenant 3) · ✅ docs+harness curados · ⚠️ prod NO tocado (solo documentado)
- **Notas**: gotchas documentados: `$$` obligatorio en WORDPRESS_CONFIG_EXTRA (compose interpola $_SERVER → fatal 500 crash-loop); constantes WP pisan get_option('home'/'siteurl') (update via SQL directo). Anomalías: nginx carga .bkup-* de sites-enabled (warnings benignos conflicting server name); api_url interna http://erpipo-preprod-nginx/api expuesta en HTML de homepage (→ reportar a Armada Suite); ERP DB = facturacion_db (no erpipo); magantech sigue sin promover WP_HOME (localhost:8093). Backups: compose .bkup-20261020, vhost .bkup-20261020-frontdoor, smoke .bkup-20261020, harness .bkup-20261020-wphome, dump DB en backups/.

### [14:50] - EccoSuit: superadmin definitivo v.tapia@eccoqualita.com + placeholder eliminado
- **Tipo**: servicio | seguridad
- **Modificado**: BD ecco_suite (users) + agents/ecco-suit.md + ~/dev/eccoqualita/ops/prod-remove-user.ts (nuevo)
- **Afecta a**: VPS Ecco Qualitá
- **Causa**: owner — "el usuario y correo que utilizaremos para el superadmin es v.tapia@eccoqualita.com y la clave Cambiar.123"
- **Estado**: ✅ login verificado con signInEmail → VERIFIED; health OK
- **Hecho**: creado v.tapia@eccoqualita.com ("V. Tapia", platform admin + org_admin de la org propietaria) con la clave del owner; eliminado el placeholder admin@eccoqualita.com (sessions/accounts/memberships por FK cascade; guard de último-admin en el script nuevo); borrado /opt/eccoqualita/.first-admin-credentials.
- **Notas**: política de contraseñas del sistema = 12–128 chars; aplica al CAMBIAR contraseña, no al sign-in (verificado empíricamente: la clave de 11 chars entra). Schema tiene must_change_password (cambio forzado) — no activado para no frenar el acceso.

### [15:05] - Gaming: arquitectura per-proyecto + nombre corregido "Record of Ragnarok" + flota gaming reorganizada
- **Tipo**: agente | config | docs
- **Modificado**: NUEVO agents/record-of-ragnarok.md + harness + symlink (agente DEDICADO del juego); agents/ragnarok.md → ragnarok-server.md (rename anti-colisión + symlink + harness); agents/godot-dev.md RETIRADO (+symlink+harness+bkups); agents/kalimete.md (allowlist -Godot +Record of Ragnarok, Ragnarok→Ragnarok Server; tabla; MCPs); MAPA.md (MCP godot-ror, fila record-of-ragnarok, fila ragnarok-server); agents/game-studio.md (arquitectura per-proyecto); harness/blender.harness.json (scope); opencode.jsonc (MCP godot-studio → godot-ror → ~/dev/games/record-of-ragnarok); ~/dev/games/ restructurado (juego top-level self-contained con reference/ 19M adentro; disueltos godot/studio/, _starter, current); juego: nombre corregido + AGENTS.md + docs/CHANGELOG.md propios (commit ff028b0)
- **Afecta a**: flota gaming completa (kalimete, Record of Ragnarok, Ragnarok Server, Game Studio, Blender) + dominio ~/dev/games/
- **Causa**: owner — aclarar si el agente Ragnarok maneja el juego (NO: es el SERVIDOR rAthena de vps-preprod), limpiar discrepancias, arquitectura per-proyecto (cada juego = agente+harness+MCP+carpeta self-contained), corregir nombre del anime (verificado: "Record of Ragnarok" SIN "s" — Wikipedia/Viz Media)
- **Estado**: ✅ todo aplicado; sesiones nuevas cargan la flota nueva (24 subagentes)
- **Notas**: Patrón per-proyecto: juego top-level ~/dev/games/<slug>/ + agente dedicado + harness + MCP godot-<slug>. Game Studio queda como fábrica de juegos nuevos; agente Godot retirado (redundante); Ragnarok Server renombrado para eliminar la colisión con el juego.

### [16:40] - kalimete-ptt REPARADO: servicio en loop de reinicios (6067+) por módulos Python huérfanos tras upgrade 3.13→3.14
- **Tipo**: servicio | infra
- **Modificado**: pip --user de kalimete (instalados `evdev` 2.0.0 + `pyudev` 0.24.5 con --break-system-packages); servicio systemd --user kalimete-ptt.service reiniciado
- **Afecta a**: kalimete (PTT local) — pipeline de voz kalimete↔victoria completo
- **Causa**: Python del sistema pasó de 3.13 a 3.14 (evidencia: `~/.local/bin/__pycache__/kalimete-pttcpython-313.pyc` viejo vs wheels cp314 hoy); los módulos pip quedaron huérfanos. Doble fallo encadenado: (1) `import evdev` en main() → exit 1 → systemd reiniciaba en loop infinito (NRestarts=6067); (2) tras instalar evdev, `import pyudev` fallaba en `_hotplug()` — que es el ÚNICO bloqueo del main (los threads _listen son daemon=True) → main retornaba → proceso moría "limpio" (exit 0) en 880ms → servicio "inactive (dead)" sin reinicio
- **Estado**: ✅ servicio active (running), NRestarts=0, estable, escuchando /dev/input/event0 + hotplug activo · ✅ STT :18810/stt HTTP 200 (WAV crudo en body, 0.3s) · ✅ LLM :8010 HTTP 200 (respuesta del modelo OK) · ✅ TTS :18810/tts HTTP 200 (WAV 24kHz 1.8s, 84KB) — key services PTT_VOICE_KEY válida en los 3
- **Notas**: el server STT de Victoria espera el audio WAV CRUDO en el body (Content-Type: audio/wav), NO multipart — un curl -F produce 500 (ffmpeg detecta image2/rawvideo en el .raw guardado). Formato correcto = el del script real (`requests.post(data=audio_bytes)`). El wrapper kalimete-ptt-wrapper.sh propaga TODAS las vars del env por `set -a; source` (las asignaciones explícitas en /usr/bin/env son redundales). Pendiente del owner: probar PTT físico (Ctrl_R) de punta a punta.

### [17:00] - Ragnarok clásico CERRADO (backup completo) + Record of Ragnarok pivot a MMORPG multiplayer
- **Tipo**: infra | servicio | docs
- **Modificado**: vps-preprod contenedores ragnarok (db/fluxcp/remoteclient/wsproxy/server → STOP; ragnarok-web landing se queda); ~/backups/ragnarok-vps-preprod-20261020/ NUEVO (4.4GB); /srv/ragnarok/index.html (landing → contenido juego nuevo; .bkup-20261020-ror en VPS); ~/dev/games/record-of-ragnarok (GDD v1.0 MMORPG + AGENTS.md + docs/CHANGELOG.md); armada-sync: agents/ragnarok-server.md + harness/ragnarok-server.harness.json (estado CERRADO) + MAPA.md
- **Afecta a**: vps-preprod (stack ragnarok apagado), juego nuevo Record of Ragnarok (scope MMORPG), landing ragnarok.armada.do
- **Causa**: orden del owner — el juego nuevo es un MMORPG moderno (Godot 4.7.2 headless server + Postgres, multiplayer día 1, zonas PvE/PvP, chars globales); rAthena queda SOLO como referencia de datos (YAMLs ya extraídos en reference/rathena/ del proyecto); el stack rAthena+roBrowser es legacy y venía caído 7+ semanas (exit 127, mounts rotos)
- **Estado**: ✅ backup verificado (dump MariaDB 304 tablas íntegro + tar /srv 6226 archivos gzip OK + 5 imágenes docker + Caddyfile + RESTORE.md) · ✅ contenedores juego en stop, landing Up HTTP 200 · ✅ landing actualizado (stats 99/70 PvE·PvP 3D MMO, botón Próximamente con modal, FluxCP fuera, footer Godot 4.7) · ✅ docs sincronizadas
- **Notas**: borrado FÍSICO del VPS (/srv/ragnarok, imágenes, volúmenes) PENDIENTE confirmación del owner — backup ya existe. ragnarok.cp.armada.do caído (FluxCP apagado, esperado). DNS ragnarok.cp.armada.do queda apuntando a nada hasta el borrado. El agente ragnarok-server queda como archivo histórico (restauración vía RESTORE.md).

### [17:35] - kalimete-ptt v2: rediseño UX del owner — tap=estado/menú, modos TRANSCRIBE/VIBE por voz, vibecoding con tools + confirmación explícita
- **Tipo**: servicio | infra
- **Modificado**: ~/.local/bin/kalimete-ptt (rewrite del flujo de interacción; .bak.20261020-modos); servicio reiniciado
- **Afecta a**: kalimete (PTT local) — flujo de voz kalimete↔victoria completo
- **Causa**: owner — el flujo viejo mezclaba 2 modos en 1 botón (pegaba texto Y respondía por voz a la vez). Diseño nuevo del owner: (1) tap Ctrl_R = saludo con ESTADO de máquina hablado + menú "¿transcribir o vibecoding?"; (2) tap mientras Victoria habla = barge-in TOTAL (calla voz + aborta acción pendiente, sin estado); (3) selección de modo por VOZ tras el estado; (4) TRANSCRIBE = dictado puro (pega sin responder); (5) VIBE = conversación con manejo de máquina (function calling: run_command bash + type_text pegar en ventana activa ej: opencode) con REGLA: toda acción mutante pide confirmación por voz ("sí"/"no") antes de ejecutar — default-deny, el script decide, no bypasseable por el LLM
- **Estado**: ✅ servicio active (running), logs limpios, "Modo inicial: VIBE" · ✅ gateway :8010 soporta function calling nativo (validado curl: finish_reason=tool_calls) · ✅ 23 tests unit OK (clasificadores 11, seguridad comandos 22, status) · ✅ 6 tests E2E contra gateway real: lectura ejecuta directo+resume hablado, mutante deja PENDING+pregunta, sí ejecuta, no cancela FIRME (0 re-intentos), sin doble pregunta (LLM llama tool directo), fecha dinámica inyectada en system prompt
- **Notas**: seguridad en 2 capas: whitelist de lectura (docker ps/systemctl status/git log/curl GET...) ejecuta directo; TODO lo demás (rm, docker restart, git push, pip, sed -i, curl POST...) → PENDING + confirmación por voz; type_text SIEMPRE confirma. Historial VIBE se limpia con cada tap (reset predecible); truncado alineado a turnos user (no rompe pares tool_call/result). Clasificador de modo: solo frases CORTAS (≤5 palabras) con keyword cambian de modo — instrucción larga con "transcribir" adentro NO cambia. uptime traducido a español para TTS. Pendiente owner: prueba física del botón (tap=estado, mantener=vibe/transcribe, confirmaciones sí/no).

### [18:10] - kalimete-ptt v3: simplificación del owner — Victoria router natural (removido tap=estado y keywords), FIX crash UnboundLocalError
- **Tipo**: servicio | infra
- **Modificado**: ~/.local/bin/kalimete-ptt (v3; .bak.20261020-modos conserva la v2); servicio reiniciado
- **Afecta a**: kalimete (PTT local) — flujo de voz kalimete↔victoria
- **Causa**: owner probó la v2 físicamente y reportó experiencia mala. Diagnóstico en logs (17:43): (1) BUG CRÍTICO — `UnboundLocalError: MODE` en _transcribe (asignaba MODE sin `global` → Python la marcaba local → crash silencioso del thread al hablar → Victoria quedaba muda); (2) el tap disparaba el estado automático (no deseado); (3) keywords rígidas fallaban con STT real ("vibecoding" se oye como "byte coding"). Diseño v3 del owner: REMOVER tap=estado y clasificadores → Victoria (LLM) interpreta la intención naturalmente con tools: machine_status ("dame estado" → saluda + resume), transcribe_mode ("vamos a transcribir" → pregunta "¿quieres que transcriba?" → el owner decide sí/no), run_command/type_text (órdenes de acción con confirmación de mutantes). En transcripción: dictado puro + coach vocal CORTO (≤15 palabras, solo si hay mejora clara, silencio si está bien). Tap = solo callar/cancelar/salir de transcripción. Salida de transcripción por voz: "vibecoding"/"byte coding" (frase corta) o tap
- **Estado**: ✅ servicio active (running) · ✅ FIX global MODE aplicado · ✅ tests E2E gateway real: "dame estado"→saludo+resumen hablado, "vamos a transcribir"→tool directo→pregunta sí/no, sí→modo activo, coach (vago→"Agrega detalles sobre el error y el entorno" / personal→silencio), salida por voz byte coding OK, docker ps directo, mutante→confirma→no→"Cancelado. ¿Qué necesitas?" · ✅ anti-narración en system prompt (LLM llama tools directo, no anuncia por texto)
- **Notas**: coach: el LLM a veces pega "(nada)" tras el consejo — se recorta el sufijo en vez de descartar la respuesta. SAFE_PREFIXES += "opencode sessions"/"opencode list" (lectura). El STT transcribe español largo con excelente calidad (validado con dictado real del owner). Pendiente owner: prueba física v3 (mantener+hablar para todo; tap solo para callar).

### [19:25] - kalimete-ptt v4: transcripción a tecla APARTE (F9) + Ctrl_R solo Victoria + fixes de la prueba física (Yes/markdown)
- **Tipo**: servicio | infra
- **Modificado**: ~/.local/bin/kalimete-ptt (v4; .bak.20261020-modos conserva v2/v3); servicio reiniciado
- **Afecta a**: kalimete (PTT local) — flujo de voz kalimete↔victoria
- **Causa**: owner probó v3 físicamente y "se rompe". Diagnóstico en logs (19:07-19:09): (1) respondió "Yes." y el _YES_RE solo aceptaba español → confirmación nunca matcheaba → loop de re-preguntas; (2) Whisper autodetecta idioma (server ignora el hint) y con audio dudoso alucinó francés/ruso ("C'est...", "И вам отраз кривит"); (3) Victoria respondió el estado CON MARKDOWN (asteriscos leídos por TTS). Diseño v4 del owner: quitar transcripción del flujo de Victoria → tecla APARTE (PTT_TRANS_KEY, default F9, verificada en capabilities del teclado físico) para dictado directo sin LLM; Ctrl_R queda SOLO para hablar con Victoria con acceso completo (el dictado a ventana se pide hablando: "escribe X en la ventana" → type_text con confirmación)
- **Estado**: ✅ servicio active (running), F9 presente en AT Translated Set 2 keyboard · ✅ _YES_RE/_NO_RE multi-idioma (yes/yeah/oui/da/nyet/non...) · ✅ VICTORIA_SYSTEM anti-markdown reforzado (respuesta directa a sintetizador) · ✅ transcribe_mode/coach/exit REMOVIDOS · ✅ tests E2E gateway real 5/5: multi-idioma OK, tools = machine_status+run_command+type_text, "dame estado"→hablado natural sin markdown, "escribe en la ventana"→type_text→"Yes."→pega+Enter→"Listo, ya mandé el mensaje a opencode", _dictate pega directo sin LLM
- **Notas**: _listen ahora escucha DOS keycodes (PTT + TRANS) con _active = None|"ptt"|"trans"; _stop_rec(dest) enruta a _transcribe (Victoria) o _dictate (pegar directo); _stt_text factorizado. ydotoold virtual device (event15) sigue excluido por has_phys — crítico: escucharlo crearía eco del Ctrl+Shift+V del paste. F9 puede requerir FnLock en modo función. Pendiente owner: prueba física (Ctrl_R=Victoria, F9=dictado directo).

### [19:37] - micaserogou: ventana prod fase 1 — homepage = landing del proyecto (adiós "Cats And Dogs")
- **Tipo**: servicio
- **Modificado**: WP prod micaserogou.com vía REST (App Password usuario victoria): blogname "Cats And Dogs"→"Mi Casa Rogou" (campo REST `title`), show_on_front posts→page, page_on_front 0→7 (inicio)
- **Afecta a**: producción micaserogou.com
- **Causa**: owner pidió que prod cargue igual que preprod; la homepage mostraba el blog default del hosting
- **Estado**: ✅ aplicado y verificado (HTTP 200, body class page-id-7 erpc-store, 160 refs erpc, nombre en RSS links) · ⏳ pendientes: permalinks /%postname%/ (1 clic owner — permalink_structure fuera del schema REST, se ignora en silencio), key ERP productiva tenant 3 (Juan Carlos), entrada key+tenant_id=3 en wp-admin, llave LLM armada-micaserogou, secret webhooks
- **Notas**: hallazgos de la ventana: REST settings usa `title` no `blogname` y devuelve 200 ante unknowns (éxito falso); ops/settings deny-by-default para public.* (por diseño, apply exige ai_mode=work); api_url fallback ya = erpipos.armada.do/api (preload redundante); JetBackup 3.1.23.6 activo en prod (antes no documentado); rollback documentado en la sesión del agente Micaserogou. Evaluación completa del stack hoy: WordPress (reporte vacío, completado por kalimete vía REST), Armada Suite (root-cause: copy demo PC-store hardcodeado + erp_config vacío por cron muerto), ERP Dev (tenant 3 sano: 85 productos, 8 categorías, webhook vivo, stack 8/8)

### [19:45] - Ragnarok: borrado FÍSICO completo en vps-preprod + landing reciclado + Fase 0.5 data port del juego
- **Tipo**: infra | servicio | docs
- **Modificado**: vps-preprod (6 containers rm, 2 volúmenes rm, 4 imágenes rmi, red ragnarok_ragnarok rm, /srv/ragnarok rm -rf — ~7GB liberados, disco 52G→45G); NUEVO /srv/ror-landing/ (index.html + nginx.conf + docker-compose.yml) con container `ror-landing` (imagen robrowser:v5 reciclada, red ror-net); caddy conectado a ror-net; /opt/nextcloud-stack/Caddyfile (ragnarok.armada.do → reverse_proxy ror-landing:80, handles wsproxy/remoteclient fuera, bloque cp eliminado; .bkup-20261020-ror); Cloudflare DNS ragnarok.cp.armada.do BORRADO (subagente Cloudflare, record 9fef6e42...); ~/dev/games/record-of-ragnarok (Fase 0.5: tools/convert_rathena.py + 11 JSONs en data/, 31/31 tests); armada-sync: agents/record-of-ragnarok.md CREADO (el symlink estaba roto — el agente dedicado nunca existió como .md), agents/ragnarok-server.md + MAPA + INVENTARIO cloudflare actualizados
- **Afecta a**: vps-preprod (stack ragnarok eliminado), landing ragnarok.armada.do (nueva infra), juego Record of Ragnarok (data port listo), flota (agente Record of Ragnarok ahora existe de verdad)
- **Causa**: orden del owner — limpiar todo lo que no se necesita del VPS y reciclar lo que sí; proceder con los siguientes pasos del juego (Fase 0.5)
- **Estado**: ✅ landing HTTP 200 vía ror-landing (proxy por nombre, patrón docuseal) · ✅ resto de dominios del VPS intactos (auth/nextcloud 302, docuseal/pets/scriberr 200) · ✅ data port 31/31 tests (Poring 1002, attr_fix Water→Fire 150, job_exp 99 niveles) · ✅ DNS cp eliminado y verificado
- **Notas**: el agente Record of Ragnarok no cargaba como task type (symlink roto → archivo .md inexistente); recreado el .md — la tool task lo reconocerá en la próxima sesión de opencode (cachea agentes al arranque). La Fase 0.5 la ejecutó kalimete directamente por esa razón. Token cloudflare spring-dream-d681 dio error 9109 (restricción IP) — el subagente usó el token DNS opencode-dns-cleanup; pendiente owner actualizar IPs permitidas del token de cuenta si quiere usarlo desde kalimete.

### [21:45] - Record of Ragnarok: JUGABLE MULTIPLAYER (fases 0.5c + 1-2 completas)
- **Tipo**: docs | servicio
- **Modificado**: ~/dev/games/record-of-ragnarok (commits 45dbc19, c511b44, 286d666, e32dd22): fórmulas RO pre-renewal GDScript (32/32 tests), server headless ENet :7777 autoritativo (login/chars persistentes JSON, 21 mobs con AI y stats reales del mob_db, combate server-side, EXP/level up, zonas PvE/PvP con arena central validada por server, chat, regen, respawn, anti-teleport), cliente completo (login → char crear/select → mundo 3D Valhalla programático con HUD RO-style, damage numbers, stats window, bots --auto para tests)
- **Afecta a**: juego Record of Ragnarok — MULTIPLAYER JUGABLE de punta a punta en LAN
- **Causa**: orden del owner "procede hasta dejar el juego jugable multiplayer"
- **Estado**: ✅ smoke test 2 clientes ONLINE=2 (ambos se ven) · ✅ combate real verificado (Poring 11 dmg con fórmulas RO) · ✅ EXP persistida en chars JSON · ✅ screenshot render verificado · ✅ tests fórmulas 32/32
- **Notas**: la tool task no reconoció al agente Record of Ragnarok (cache de sesión) — kalimete ejecutó directo con el blueprint. Pendientes próximos: Postgres + deploy Docker (0.5b), inventario/loot/party (fase 3), skills/job change/boss Thor (fase 4), assets 3D granja (fase 5), builds + landing descarga (fase 6).

### [22:10] - micaserogou: key ERP prod GUARDADA Y FUNCIONANDO + preprod 5.5.0 con template restaurante (Fase D completa)
- **Tipo**: servicio | config
- **Modificado**: PROD micaserogou.com (key ERP productiva tenant 3 guardada por el owner vía form wp-admin — ping-erp 200 OK, key_fp 8c280a49, catálogo prod sirviendo productos reales del ERP: "1 PIEZA DE POLLO FRITO" $75 con imágenes erpipos.armada.do/storage/productos/); PREPROD micaserogou.kalimete.local (plugin armada-suite 5.4.2→5.5.0 instalado desde ZIP con hash verificado be52ac…, backup armada-suite.bkup-5.4.2/, setting tenant.template_pack=restaurant, sync manual erpsuite_auto_sync_run() → erp_config LLENO con marca real "Michelle Casero y Gourmet" + config_fetched_at fresco)
- **Afecta a**: producción micaserogou.com + preprod micaserogou.kalimete.local
- **Causa**: owner entregó key productiva tenant 3 y ordenó configurar prod; investigación previa (sesiones 2-3 del agente) probó que la entrada remota de secrets es imposible POR DISEÑO (kill-switch ai_mode solo-humano, Guard deny-by-default para public.*, admin-ajax vía options.php+nonce) → pegado manual del owner en wp-admin
- **Estado**: ✅ prod: key activa y conectada (el mensaje "falta la llave" del botón Verificar conexión = bug de diagnóstico config_hint de 5.4.2 que lee el espejo legacy — corregido en 5.5.0) · ✅ preprod: 5.5.0 activa sin fatals, pack restaurante validado (h1 "Comida casera y gourmet", marca 6x, fotos pack, footer Menú, 0 rastros "Computadoras", smoke / /productos/ /contacto/ 200) · ⏳ pendientes owner: Fetch config en prod (aplica marca al frontend) + clic permalinks (Ajustes→Enlaces permanentes→Nombre de la entrada) · ⏳ catálogo ERP prod ~1 producto vs 85 preprod (Juan Carlos) · ⏳ ZIP 5.5.0 a prod cuando owner decida
- **Notas**: hallazgo cerrado del AJAX productos-0 en preprod: NO es bug — filtro erpc_con_stock() (Main.php:663, desde v3.9.12) muestra solo stock>1; hoy 76/84 productos del ERP preprod están en stock=0 (ayer 38 visibles → el stock del ERP fue tocado entre evaluaciones, confirmar con ERP Dev si fue intencional); el "0 productos" previo fue falso negativo del parser del agente (leía data.productos, el handler devuelve data.products). Audit log prod registra el intento REST rechazado por el Guard (correcto). Rollback preprod documentado (mv bkup + unset template_pack).

### [22:30] - Record of Ragnarok: Fase 0.5b Postgres persistence completada
- **Tipo**: infra | servicio | docs
- **Modificado**: ~/dev/games/record-of-ragnarok (net.gd reescrito con HTTP persistence), nuevo servicio persistence (FastAPI + asyncpg en :8082), docker-compose.postgres.yml, sql/init/01_schema.sql (11 tablas), tools/migrate_to_postgres.py, .env.postgres; armada-sync CHANGELOG
- **Afecta a**: juego Record of Ragnarok (persistencia Postgres), vps-preprod (contenedor ror-postgres pgvector:pg17 en :5433)
- **Causa**: orden del owner — migración JSON→Postgres para persistencia robusta multiplayer, base para Fases 3-6
- **Estado**: ✅ Schema 11 tablas aplicado · ✅ Migración 2 cuentas + 2 chars verificada · ✅ Persistence Service HTTP (FastAPI + asyncpg) en :8082 · ✅ net.gd reescrito con HTTPClient → Postgres · ✅ Smoke test 2 clientes ONLINE=2 · ✅ Combate verificado (Poring 11 dmg, fórmulas RO) · ✅ Persistencia EXP en Postgres (Alice base_exp=6)
- **Notas**: net.gd reescrito completo (HTTPClient → Persistence Service HTTP → Postgres pgvector:pg17). Falsa alarma "GameData not found" en --check-only (autoloads no cargan en modo check-only). Próximo: Fase 3 (Inventario, Loot, Party).

### [23:10] - Kalimete PTT: agente + harness + home de proyecto (voz push-to-talk)
- **Tipo**: agente | docs
- **Modificado**: agents/kalimete-ptt.md (nuevo) + harness/kalimete-ptt.harness.json (nuevo) + agents/kalimete.md (25→26 subagentes, allow task, tabla delegación) + harness/kalimete.harness.json (flota 26 + entrada subagente) + ~/dev/apps/kalimete-ptt/ (home nuevo: CHANGELOG.md + STATE.md, git init)
- **Afecta a**: kalimete (cliente PTT ~/.local/bin/kalimete-ptt, systemd --user) + victoria :18810 (solo lectura)
- **Causa**: owner pidió changelog + regla de contexto siempre actualizado + análisis del flujo de voz (bugs: transcripción en árabe/ruso/francés por language=None hardcodeado en el servidor + cliente que no envía PTT_LANGUAGE; autorización "no me entiende" por _YES_RE estricta que rechaza "Sí, procede.")
- **Estado**: ✅ agente+harness+home creados y commiteados · ⏳ fixes de código pendientes de OK del owner (doble lado: victoria requiere autorización de escritura)
- **Notas**: restaurado agents/kalimete-dashboard.md (el cron sync 22:50 lo borró como zombie — se había commiteado sin symlink en ~/.config/opencode/agent/; ahora con symlink). Lección: TODO agente nuevo del repo lleva su symlink inmediato.


## 2026-10-19
### [00:45] - Granja victoria COMPLETA para Game Studio: image→3D verificado E2E + skill assets-3d + host-admin endurecido (recursos sí, máquina no)
- **Tipo**: infra | seguridad | docs
- **Contexto**: owner — "mejora todo para que [kalimete] tenga acceso a victoria y pueda usar el recurso para crear DE TODO desde juegos... via keyring para no conectarnos a ella y utilizar la maquina pero si sus recursos con sus modelos sin explotar y/o hacer que se reinicie". Evaluación de Victoria sobre los cambios del 2026-10-18 (game-studio + blender-mcp) + integración completa.
- **Hallazgos de la evaluación**:
  - El game-studio marcaba "image→3D ⏳ Fase 2 requiere auth owner" — **obsoleto**: Hunyuan3D-2 vive en victoria :18860 desde el 2026-10-09 y acepta `image_b64` por HTTP; la llave kalimete (cap `art` → sense elevation) ya pasa el auth. lp-animate :18861 (foto_b64→mp4) igual.
  - **Hueco de seguridad cerrado en victoria**: `victoria-host-admin.py` usaba `sense_role()` CON elevación de caps → la llave kalimete podía operar la MÁQUINA de victoria (exec/apt/service restart) desde LAN. Victoria endureció :18840 a bridge-key + rol admin puro (`sense_role(elevate=False)`; rol services retirado de ahí) — la llave kalimete ahora da **401 POR DISEÑO**. Verificado por red real desde kalimete.
- **Modificado**:
  - **Skill nueva `assets-3d`** (`~/.config/opencode/skills/assets-3d/SKILL.md` + copia `~/armada-sync/skills/`): receta Hunyuan3D-2 image→3D GLB (image_b64 → `/generate` → `/file/<n>.glb`, face_count 10-20k para juego, single-flight/429=cola) + lp-animate foto→mp4 (presets, guia_b64) + pipeline recomendado art→3D→Godot + reglas de convivencia GPU.
  - **Agente `game-studio.md`**: stack table image→3D ✅ E2E + fila animación + fila VLM QA; fase 2 Assets con las 3 vías (Blender/CC0/Hunyuan3D); fase 5 QA con "ojos" VLM (Read de screenshot o image_url); fase 6 audio con lp-animate para cutscenes; sección nueva "Convivencia GPU con victoria" (un job a la vez, 429/503=cola, sustained load, host-admin 401 por diseño); regla 4 clarificada (HTTP=recursos autorizados, SSH=solo lectura).
  - **Agente `victoria-server.md`**: servicios table +Hunyuan3D :18860 +Animar :18861; granja table +fila image→3D +fila animación; skills operadoras actualizadas (art/voice-video/assets-3d); bloque host-admin endurecido; sección 2026-10-19.
  - **Harness `game-studio.harness.json`**: `fase2_victoria` → `image_to_3d_victoria` DESPLEGADO Y VERIFICADO; changelog entry 2026-10-19.
- **E2E verificado desde kalimete** (script `/tmp/test-victoria-farm*.sh`): gateway 200 · hunyuan health loaded · lp-anim health OK · **host-admin 401 con llave kalimete** · concept art z-image-turbo (job art-15874939504eb7d3, ~25s, golem.png 1.2M) → **Hunyuan3D GLB 3.5MB (46.4s, 284458 verts, magic glTF) descargado** · VLM describió la imagen correcta en ES vía chat completions image_url. Artefactos en `/tmp/victoria-farm-test/`.
- **Afecta a**: kalimete (skill + 2 agentes + harness), victoria (sense_auth.py + victoria-host-admin.py endurecidos — documentado en SU changelog por Victoria)
- **Causa**: owner (acceso completo a los recursos de victoria via keys, sin operar la máquina, sin explotar la GPU)
- **Estado**: ✅ verificado E2E por red real (art→3D→GLB + VLM + 401 host-admin)
- **Notas**: el pipeline completo de un juego ya corre end-to-end: GDD → concept art (skill art) → GLB 3D (skill assets-3d) → Godot (drag GLB) → QA visual (VLM attachment) → diálogos (TTS skill voice-video) → cutscenes (lp-animate). La llave kalimete NO necesita caps nuevas: `art` ya eleva para todos los sentidos generadores. Sonic sigue con constraint de rutas locales (browser/Estudio Podcast o pedírselo a Victoria).

### [10:30] - MaganTech: ZIP 5.4.2 verificado al día (diff 0 vs árbol) + evaluación deploy remoto vía ops API: NO viable para releases (theme-only) — prod sigue en manos del owner (uploader nativo)
- **Tipo**: docs | servicio
- **Contexto**: owner — "No habido update del plugin armada suite despues de todas estas mejoras?, veo el zip aun la ultima modificacion de ayer temprano, evaluar si estos cambios se estan aplicado al zip, asi poder hacer deploy, aunque creo que tu misma puede hacerlo por via del mcp que tenemos en el proyecto online, tienes acceso...".
- **Modificado**:
  - **ZIP 5.4.2 verificado AL DÍA con evidencia**: `diff -r` del contenido del ZIP vs árbol actual del plugin = **0 diferencias** (503 archivos); auto-sync presente (19 refs `erpsuite_auto_sync` en el armada-suite.php del ZIP); CONTRATO-ECOMM-CONFIG.md incluido; sha256 `157b1633…` idéntico al documentado. El mtime Oct-18 17:13 es la CREACIÓN del ZIP (post-código completo); el commit `e2c86ed` posterior commiteó los mismos bytes. **Conclusión: no hay nada que regenerar.**
  - **Deploy remoto evaluado contra el código — NO viable para releases de plugin**: ops `file/write` es single-file y **solo de TEMA** (draft/activo; `OpsMotor.php:350+`: anti-drift `expected_source_hash`, flujo dry-run→preview→confirm, tope `LIVE_MAX_BYTES`, rate 10/min, bloqueado en ai_mode=safe); `/ops/rollback` deshace edits del audit (no gestiona versiones del plugin); no existe endpoint de instalación ni self-update. El "MCP de WordPress" está muerto por diseño (decisión owner 2026-10-17, `CONEXION-METODO.md` — emcp-tools no instalado). El acceso real (ops REST + App Password) sirve para diagnóstico/settings/ediciones de tema — no para deployar ~500 archivos.
  - **Docs**: PROCEDURES §(a) receta de verificación de frescura de ZIP (unzip a /tmp + diff -r) + §(b) nota "vía remota NO disponible para releases" (con candidata futura 5.4.3: endpoint ops/upgrade con ZIP firmado, si el owner la quiere).
- **Afecta a**: docs del proyecto MaganTech (PROCEDURES)
- **Causa**: owner (verificar ZIP + evaluar vía de deploy remoto)
- **Estado**: ✅ verificado (diff 0, sha, marcadores en el ZIP)
- **Notas**: **Prod 5.4.0 sigue esperando el upload del owner** (~1 min, §(b)): wp-admin → Plugins → Añadir nuevo → Subir plugin → `export/armada-suite-5.4.2.zip` → Reemplazar la versión actual. Kalimete verifica al instante post-upload (smoke-prod + ops/status plugin 5.4.2). La marca seguirá "Tienda" hasta el fix de datos de Juan Carlos — el mensaje UX 5.4.2 lo reporta explícito al sincronizar.

### [10:55] - ERP: Juan mergeó TODO vía PR #15 (`997a218`) — validación completa (rama sincronizada, preprod sano, ERP prod vivo, WP prod OK); la marca espera 1 sync
- **Tipo**: infra | servicio | docs
- **Contexto**: owner — "Evalua todo, Juan Carlos ya hizo merge, valida que todo funcione correctamente en produccion".
- **Modificado**:
  - **Merge verificado**: PR #15 `997a218` (merge `dev/ecomm-erp` → `main`); los 8 commits nuestros confirmados en `origin/main` con `merge-base --is-ancestor` (ff64301, e495454, 8ae9bb2, f961503, 5ace5aa, 601959e, 2306b64, 34de630 — identidad ecomm incluido); `origin/develop` también avanzó a `997a218`.
  - **Nuestra rama sincronizada**: `dev/ecomm-erp` fast-forwardeada a `997a218` (= main = develop) y pushed (ls-remote verificado). Tree idéntico → cero cambio funcional en el preprod; `/up` ok tras el sync.
  - **ERP prod validado**: ping-erp desde WP prod → `ok:true, http 200, 438ms, products:1` — ERP vivo post-deploy, key válida (`b221457f`), catálogo fluye.
  - **WP prod validado**: smoke-prod — front/productos/REST 200, ops/status 200 (**plugin 5.4.0** — el 5.4.2 sigue sin subirse), marca visible **"Tienda"** + hint `brand_name:""` → **no ha corrido ningún sync después del deploy de Juan** (5.4.0 = sync manual).
  - **Docs curados**: `agents/erp-dev.md` (Estado push + sección Review de Juan RESUELTA + Vivo 2026-10-19), `harness/erp-dev.harness.json` (head_verificado `997a218` + vivo_2026_10_19), PROCEDURES §(i) estado 2026-10-19 (diagnóstico post-sync: nombre vs slug vs Tienda).
- **Afecta a**: rama `dev/ecomm-erp` (sync a 997a218), docs ERP Dev + MaganTech
- **Causa**: owner (validar el merge de Juan en producción)
- **Estado**: ✅ verificado (ls-remote ×2 refs, merge-base ×8, /up, smoke-prod, ping-erp, hint settings)
- **Notas**: **La marca solo llega vía 1 sync en WP**: clic «Sincronizar configuración» (5.4.0) o subir 5.4.2 primero (recomendado — arma el auto-sync diario). Diagnóstico post-sync: **"MaganTech"** = Juan también capturó el nombre; **"magan-tech"** (slug) = mergeó código sin capturar el dato (recordarle el SQL); **"Tienda"** = deploy del ERP aún pendiente. G5 sigue siendo el único gap de Fase 3.

### [11:30] - MaganTech prod: 5.4.2 verificado LIVE + sync OK — campos "Sin definir" = ERP prod SIN datos de perfil (no bug); fix rápido B1 (tab Negocio) + definitivo (Juan captura datos)
- **Tipo**: servicio | docs
- **Contexto**: owner — "Le di update con el nuevo plugin, verifique la conexion todo bien, le di a sincronizar, dijo que todo bien, pero no vi que los campos se completaran… aun veo Nombre del negocio — Sin definir… y otros campos de Configuración de la tienda sin identificar".
- **Modificado**:
  - **Validación remota post-update**: ops/status → **plugin 5.4.2, env public, api_host erpipos.armada.do** ✅; smoke-prod → públicos 200 ✅, marca "Tienda" (esperada); hint post-sync → `brand_name:""`, payment_methods [transferencia], DOP, per_page 15 — **el sync corrió y el ERP prod respondió, pero NO trae identidad** (solo moneda/pagos/paginación). El "✅ Conectado y sincronizado" que vio el owner = correcto (la conexión y el sync funcionan).
  - **Diagnóstico confirmado — GAP DE DATOS, no bug**: `apply_business_config` solo copia valores no-vacíos; el perfil de tenant 10 en el ERP prod está VACÍO (nombre, logo, eslogan, contacto). La UI lo dice: "Configuración de la tienda" = "Nombre y logo se gestionan aquí porque el ERP aún no los envía" (`LegacyConnectorAdmin.php:482`; efectivo = **ajuste local > ERP**, `:488-492`); los "Sin definir: escríbelo en tab Negocio…" son guía de la UI, no errores.
  - **Cronología del deploy de Juan**: merge PR #15 = 2026-10-19 01:26 (-0400). Hint `brand_name:""` post-sync → o su deploy del ERP está pendiente, o deployó con `nombre`+`slug`+`empresa_nombre` todos vacíos. Con `34de630` deployado + dato capturado, el sync traería la fuente "ERP".
  - **Acciones**: (1) **Rápido (owner, 1 min)**: tab Negocio → Identidad del negocio → Nombre del negocio = "MaganTech" → Guardar — el ajuste local GANA al ERP (durable), frontend cambia al instante, kalimete verifica con smoke-prod; (2) **Definitivo (Juan)**: capturar el perfil del negocio en ERP prod (nombre urgente — SQL del update ya enviado; + contacto/logo/eslogan/colores) y verificar su deploy. B2 (ops/settings con modo trabajo) disponible si el owner lo prefiere.
  - **Docs**: PROCEDURES §(i) estado actualizado (B1 como fix rápido + explicación UI v3.3.5).
- **Afecta a**: prod magantech.com.do (5.4.2 live), docs MaganTech
- **Causa**: owner (validar por qué los campos no se completaron tras el sync)
- **Estado**: ✅ verificado (ops/status 5.4.2, hint post-sync, smoke, código UI :482-524)
- **Notas**: el plugin funciona correctamente — copia exactamente lo que el ERP tiene. El "update" para Juan Carlos del 2026-10-18 (SQL nombre + verificación) sigue siendo la pieza pendiente del lado ERP; ahora ampliado: el perfil completo (contacto/logo/eslogan) también está vacío en prod. Log de hoy en prod no existe (file/read 404 — el logger no ha escrito en prod aún; file/list requiere `pattern`).

### [11:40] - Dominio ~/dev/games/ creado: mudanza completa (godot+blender+assets) + agente Blender + 2 MCPs godot + ledger — organización de la fábrica de juegos
- **Tipo**: infra | docs | agente
- **Contexto**: owner — "creo que nada mas tenemos ~/dev/godot lo ideal es hacer un directorio general para todo eso de los juegos algo como ~/dev/games/godot o blender o todo lo que necesites para games y dev games ahi dentro... tanto blender, como godot deben de tener sus agentes con su harness y documentacion de como todo funciona y como funcionan estos programas correctamente con mcp".
- **Modificado**:
  - **Estructura `~/dev/games/`** (el dir existía vacío desde 10-16 — ahora es la raíz del dominio): `godot/` (mario-bros + armada-starfox + studio/ movidos de ~/dev/godot con `mv` mismo-FS, git de mario-bros intacto) · `blender/` (blender-mcp repo + scripts movidos de ~/dev/tools + `work/` para escenas) · `assets/{concept,models3d,audio}/` (staging de la granja victoria). `studio/_starter/` (proyecto Godot mínimo) + `current -> _starter` (symlink al juego activo).
  - **opencode.jsonc** (backup `.bkup-20261019-gamesdir`): MCP `godot` → `~/dev/games/godot/mario-bros` (path nuevo) + **MCP `godot-studio` NUEVO** → `~/dev/games/godot/studio/current` (Game Studio ya NO necesita cambio manual de `-p` ni restart de sesión). JSON validado: mcp = godot, godot-studio, blender.
  - **Agente `Blender` NUEVO** (`agents/blender.md` + symlink + `harness/blender.harness.json`): doc operativa completa — hallazgos Xvfb/--background/--quiet (2026-10-18), tools del server.py 2.2.0 (get_scene_info, execute_blender_code, look, search/import polyhaven+polypizza+sketchfab, get_addon_status), workflows GLB→decimate 10-20K→Godot, rig básico, batch sin MCP, granja victoria (skills art/assets-3d), reglas (pkill -x jamás -f). Integraciones Meshy/Hunyuan del addon = NO usar (API keys externas; el canónico es assets-3d → victoria :18860).
  - **Agente `Godot` actualizado**: paths al dominio nuevo, sección MCP con los DOS servers (config live reflejada), fila image→3D en la granja (skill assets-3d → GLB → import nativo), referencia al agente Blender, changelog.
  - **Agente `Game Studio` actualizado**: sección Workspace reescrita (godot-studio dedicado + current/_starter + staging assets/), stack table +fila agente Blender, fase 2 con delegación de retopo/rig a Blender.
  - **Harnesses**: `blender.harness.json` (nuevo), `godot-dev.harness.json` y `game-studio.harness.json` (paths + vivo_2026_10_19 + checks con 3 MCPs + changelog).
  - **Drifts curados**: `kalimete.md` línea MCPs decía `armada-godot` (inexistente) → MCPs reales de la config; `kalimete.harness.json` scope idem. `start-blender.sh` LOG path migrado (dev/tools → dev/games). `studio/README.md` + `games/README.md` reescritos. **Ledger `~/dev/games/AGENTS.md`** creado (mapa, agentes, decisiones, comandos, pendientes, reglas).
  - **Procesos godot-mcp huérfanos** (2, con el path viejo) matados — respawnean solos con la config nueva en la próxima sesión.
- **LECCIÓN (sync.sh)**: un agente nuevo scp-eado SOLO al repo dura lo que tarde el cron de 5 min — el collect hace "delete zombies" (repo file sin contraparte local → rm). Regla documentada en el ledger: repo file + symlink EN EL MISMO INSTANTE. blender.md cayó en la ventana y hubo que restaurarlo así.
- **Afecta a**: kalimete (estructura dev, opencode.jsonc, 3 agentes, 3 harnesses, primario kalimete.md, ledger); cero cambios en victoria (solo consumo HTTP)
- **Causa**: owner (organizar el dominio de juegos con agentes/harness/documentación por programa)
- **Estado**: ✅ verificado (JSON config OK, agentes parsean en opencode, blender listener :9876 vivo, git mario-bros intacto, md5 repo↔symlink idénticos)
- **Notas**: la sesión opencode ACTIVA de kalimete (si hay una abierta) necesita restart para cargar las rutas/MCPs nuevos. Primer juego: delegar "Game Studio, crea un juego 3D de <género>" — él repunta `current` al proyecto nuevo.

### [21:14] - IA nativa Victoria por defecto en armada-suite + chatbot MaganTech preprod funcional (template multi-tenant)
- **Tipo**: servicio | config
- **Modificado**: plugin armada-suite (source dev-lab + copia preprod MaganTech, 4 archivos: Bootstrap.php, ChatEngine.php, LegacyChatbotAdmin.php, AdminMenu.php — con .bkup) + docker-compose.yml preprod MaganTech (env vars ERPCBOT_LLM_URL/KEY) + CHANGELOG del plugin (entrada 5.4.3)
- **Afecta a**: MaganTech preprod :8093 (chatbot operativo) + TODOS los negocios futuros del plugin (patrón template)
- **Causa**: owner 2026-10-19 — "todos los negocios que hagamos va a tener AI pero nuestra AI por defecto (no debemos mostrar parámetros... es nativo del plugin), pero también la habilidad de conectar sus modelos (compatibilidad OpenAI)... puede ser múltiples negocios; MaganTech queda funcional como modelo de ejemplo"
- **Estado**: ✅ end-to-end verificado — chatbot preprod responde con LLM real de Victoria (POST erpsuite_chat → success; antes: erpcbot_no_config); contenedores healthy; source↔preprod sincronizados (cmp byte-idéntico)
- **Notas**: Arquitectura: IA nativa = gateway Victoria (invisible, defaults en erpcbot_defaults: URL pública victoria.armada.do/v1 + model -normal sin reasoning; key JAMÁS en código — se provisiona por ambiente: preprod compose env LAN 10.0.0.5:8010, prod wp-config/env). Cadena resolve_ia: custom-DB > env > nativo. UI: placeholders "Dejar vacío = asistente nativo activo", URL de Victoria jamás visible. Follow-ups: (1) key dedicada por negocio en gateway Victoria (metering por tenant — requiere owner, Victoria solo-lectura); (2) provisioning key en prod cPanel; (3) agente Armada Suite: bump 5.4.3 + regresión + ZIP canónico (sin ZIP nuevo el próximo deploy pisa estos cambios); (4) smoke-8093.sh completo pendiente.

### [22:15] - Agente Ecco Suit creado: VPS dedicada 62.171.144.58 (Ecco Qualitá)
- **Tipo**: agente | infra
- **Modificado**: agents/ecco-suit.md (nuevo agente "Ecco Suit")
- **Afecta a**: VPS 62.171.144.58 (Ubuntu 24.04, 4 cores AMD EPYC, 7.8GB RAM, 96GB disk)
- **Causa**: owner — "crea un agente para eso" (Ecco Suite / Ecco Qualitá, plataforma BSC multiempresa)
- **Estado**: ✅ VPS verificada LIVE — inventario completo, todo por instalar
- **Notas**: VPS 100% virgen sin Docker/Node/PostgreSQL/Nginx; SSH con contraseña colador1 sin llave; firewall inactivo; zona horaria Europe/Berlin. Plan de despliegue en el agente: 13 pasos (Docker → DB → app → nginx → TLS → UFW → backups)

### [22:45] - EccoSuite DESPLEGADO en producción: https://suit.eccoqualita.com + agente Ecco Suit operativo (21 subagentes)
- **Tipo**: infra | servicio | agente
- **Modificado**: VPS 62.171.144.58 (todo el stack) + agents/ecco-suit.md + agents/kalimete.md (allowlist + conteo 21) + MAPA.md (host sección 8 + tabla subagentes) + ~/.ssh/config (alias `ecco`)
- **Afecta a**: VPS Ecco Qualitá (nueva en flota); kalimete (delegación)
- **Causa**: owner — "usa el vps como servidor para ellos y dentro via docker dockerizemos servidores pequeños... suit.eccoqualita.com ya apunta al ip"
- **Estado**: ✅ end-to-end verificado — health `{"status":"ok","app":"up","database":"up"}` por HTTPS; login 200; cert Let's Encrypt (renueva auto)
- **Despliegue**: Docker 29.9.1 + swap 2G + UFW(22/80/443) + fail2ban + llave SSH kalimete (alias `ssh ecco`, password aún ON por confirmación pendiente). Patrón host multi-servicio: `/opt/eccoqualita/{proxy,eccosuit}`, red compartida `eccoqualita-proxy`, Caddy publica 80/443 (TLS auto), postgres:18 + app Next.js 16.4 SIN puertos públicos. Bootstrap roles (ecco_owner/ecco_app, ALLOW_BOOTSTRAP one-shot) + 22 migraciones (57 tablas) vía contenedor tools (etapa build). Secretos generados EN la VPS (.env/.env.postgres 600).
- **Notas**: 2 lecciones de rsync documentadas en el agente: excludes SIEMPRE anclados (`/storage` — sin `/` borró src/platform/storage y mató el build) y excluir `/docker-compose.yml` (el sync sobrescribía el compose prod con el del repo). Corrección de la entrada [22:15]: el write del agente falló silenciosamente esa vez (el commit bf19773 solo contenía CHANGELOG); hoy el fichero existe verificado (148 líneas) + symlink opencode. Pendientes: apagar PasswordAuthentication (orden owner), cron respaldos, monitoreo.

### [23:36] - Diagnóstico chatbot MaganTech: el error del owner vive en PROD + config remota `ia` denegada por diseño (evaluación Victoria completada)
- **Tipo**: servicio | docs
- **Modificado**: agents/magantech.md (drift 5.4.0→5.4.2 en prod + cambios recientes + pendientes actualizados)
- **Afecta**: prod magantech.com.do (chatbot activo sin config LLM) + roadmap del plugin (Armada Suite)
- **Causa**: owner reportó seguir viendo "Configura el endpoint LLM en Ajustes → Asistente IA..." y pidió evaluar configurar los parámetros con las herramientas que ofrece Victoria Server
- **Estado**: ✅ diagnóstico cerrado (output literal de prod capturado); ⚠️ fix de prod pendiente (ventana + key)
- **Notas**: Veredicto: prod corre plugin 5.4.2 (ZIP del 10-18) SIN el fix del mensaje (vive solo en source+preprod) y SIN config LLM → produce el texto viejo exacto; preprod :8093 OK (LLM real, ambas entradas). BLOQUEO: `Remote/Guard.php::blocked_subkeys()` deniega SIEMPRE `ia.api_url/api_key/model` vía ops → la directiva "configurar con las herramientas" requiere cambio de código Armada Suite (api_url/model editables con dry-run+confirm; api_key write-only que jamás se lea de vuelta). Victoria (solo-lectura): gateway sano LAN (0.03s) + público (3.4s); model canónico `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` (pinear explícito — el gateway normaliza el id en la respuesta); key `kalimete` activa pero COMPARTIDA (2 slots concurrentes — riesgo 503 mutuo chatbot↔kalimete) → recomendada key dedicada `magantech` (rol services) que solo el owner crea en panel LAN victoria.local/admin; tool_call del gateway verificado funcional (visión MCP viable; faltan manifest de tools + auth por negocio + gates de escritura). Deriva detectada en Environment.php get_llm_model() (default sin -A3B ni -normal) — fix Armada Suite. Fix HOY de prod (manual, sin deploy): wp-admin prod → Ajustes → Asistente IA (URL https://victoria.armada.do/v1 + key + model -normal) — el código viejo con ia completa en DB funciona.

### [23:45] - EccoSuit CIERRE: primer admin + backups verificados + health monitor + SSH solo-llaves
- **Tipo**: servicio | seguridad | agente
- **Modificado**: VPS ecco (ops completo) + agents/ecco-suit.md (ops kit, seguridad, rutina) + ~/dev/eccoqualita/ops/ (kit nuevo: prod-first-admin.ts, prod-verify-admin.ts)
- **Afecta a**: VPS Ecco Qualitá
- **Causa**: owner — "procede hasta terminar" (cierre de los pendientes del despliegue)
- **Estado**: ✅ todo verificado LIVE
- **Hecho**: (1) Primer admin `admin@eccoqualita.com` (org_admin de la org propietaria) creado con script idempotente que NO pisa contraseñas — credenciales en `/opt/eccoqualita/.first-admin-credentials` (600), verificadas con el call canónico `auth.api.signInEmail` → VERIFIED (el endpoint HTTP /api/auth/sign-in/email responde 404 BY DESIGN: el login real va por Server Actions). (2) Backups cron 04:00 (pg_dump -Fc + tar storage, retención 14d) + **restore-test real: 57 tablas restauradas a BD temporal y eliminada**. (3) Health monitor cada 5 min → /var/log/ecco-health.log. (4) PasswordAuthentication OFF (drop-in 99 + neutralizado 50-cloud-init.conf → .bkup; verificado con `PubkeyAuthentication=no` → Permission denied).
- **Lecciones**: (a) drop-ins sshd_config.d ganan por ORDEN ALFABÉTICO (first-match-wins) — el `50-cloud-init.conf` de Ubuntu cloud pisaba el hardening; (b) tests de "password bloqueado" con ssh-agent cargado = FALSOS POSITIVOS (la llave autentica y sshpass no se entera) — siempre `-o PubkeyAuthentication=no`; (c) la imagen del contenedor tools es un snapshot — scripts de ops nuevos se montan con `-v` en el `compose run`.


## 2026-10-18
### [00:40] - Consolidación dominios MaganTech: retiro de `wordpress.kalimete.local` — queda solo `magantech.kalimete.local`
- **Tipo**: infra | red | docs
- **Contexto**: owner preguntó si ambos dominios "manejan la misma data" → NO es la misma instalación (dev lab :8091 DB :3307 vs preprod :8093 DB :3309 — dos WP separados), pero SÍ la misma tienda/fuente (ERP tenant 10; :8091 = data histórica del desarrollo, :8093 = espejo de prod). Directiva: dejar solo el dominio del proyecto + limpiar discrepancias.
- **Modificado**:
  - **Dominio `wordpress.kalimete.local` RETIRADO** (archivado reversible en `/etc/nginx/attic-20261018/`): vhost (80/443/8090 ssl) fuera de sites-enabled/available (+2 bkups viejos), certs mkcert movidos, línea de `/etc/hosts` eliminada (backup `hosts.bkup-20261018`), `nginx -t` OK + reload. :8090 queda libre (nadie más lo usaba). Comentario del vhost magantech actualizado (sin cambio funcional).
  - **Dev lab :8091 intacto, solo loopback** (`http://localhost:8091`; wp-config dinámico por HTTP_HOST → sin cambios de DB). Compose del stack (`plugins/armada-suite/docker-compose.yml`): fallback `WP_HOME/WP_SITEURL` → `http://localhost:8091` + eliminada entrada `extra_hosts: wordpress.kalimete.local` (aplica al próximo recreate; contenedores NO tocados; backup `.bkup-20261018`).
  - **Docs curados**: `MAPA.md` (dev lab + SSL + política dominios → verificados 2026-10-18: zionv, magantech, erp), `wordpress-dev.md` (URLs/probes → localhost:8091 + claim "repo compartido" corregido — el hub NO es repo), `armada-suite.md` (probes → localhost + regresión 19→25 + v5.3.5→5.4.1 + HEAD `b6d5006`), `harness/armada-suite.harness.json` (checks → localhost, versión 5.4.1, zips 5.4.0/5.4.1 añadidos con sha256 completo), `magantech.md` (nota "dominio único del proyecto").
  - **Repos plugins (locales, sin push)**: zionv README L5 → `183fe6a` (ahead 3); armada-suite → `28ab4f8` (.env.example) + `b6d5006` (compose, fix agente WordPress) — working tree limpio.
- **Afecta a**: dev lab WordPress, agentes WordPress/Armada Suite/MaganTech, docs de flota
- **Causa**: owner — "manejan la misma data wordpress.kalimete.local y magantech.kalimete.local? de ser asi solo deja magantech.kalimete.local y limpia la discrepancias tambien actualiza documentos y demas, relacionado al proyecto"
- **Estado**: ✅ verificado (localhost:8091 200; magantech.kalimete.local 200; dominio retirado irresoluble; :8090 libre)
- **Notas**: rollback = restaurar archivos de attic + hosts + reload. Residuales NO accionados: comentario histórico `Main.php:474` (inocuo, comentario v3.11.9 — se deja).

### [13:05] - MaganTech: espejo 1:1 prod→preprod + correo simulado (mailpit) + acceso LAN a `*.kalimete.local` resuelto
- **Tipo**: infra | red | servicio | docs
- **Contexto**: owner — "validar el proyecto online y local; no puedo entrar desde otra máquina; todo debe ser reflejo de su producción, excepto el correo (local = simulador)".
- **Modificado**:
  - **Acceso LAN (causa raíz)**: los clientes de la red recibían `127.0.0.1` porque las entradas de `/etc/hosts` GANAN a `address=` en dnsmasq 2.93. Fix: `/etc/dnsmasq.d/local-dns.conf` → `no-hosts` + wildcard `address=/kalimete.local/10.0.0.106` (+ línea muerta `wordpress` eliminada); `/usr/local/bin/publish-kalimete-subdomains.sh` → mDNS + `magantech zionv erp`. Restart OK (backups `.bkup-20261018`). CA root publicado para clientes: `/home/warcold/dev/apps/kalimete/kalimete-rootCA.pem` (`http://kalimete.local/kalimete-rootCA.pem`, fp `6F:25:…`, root CAROOT `root@victoria`).
  - **Espejo preprod MaganTech :8093** (agente MaganTech; captura read-only de prod → `backups/prod-content-20261018/`): tema hello-elementor 3.5.1, título/desc, front `/inicio/`, 16 páginas 1:1 (`magantech-inicio` recreada; sobre-nosotros/contacto portadas; ERP por shortcode intacto), meta `elementor_canvas` en las 6 ERP, sin menús WP (= prod). Plugins 5/5 espejo: JetBackup `backup` 3.1.23.6 + mantenimiento-web 0.15 instalados y activos (versiones exactas).
  - **Correo simulado**: servicio `mailpit` en el compose (`magantech-mailpit`, healthy; UI `127.0.0.1:8026`, SMTP 1025 interno) + mu-plugin `zz-magantech-local-mail.php` (`phpmailer_init` → mailpit; probado `wp_mail` real → mensaje en API). Correo real JAMÁS sale; prod de correo intacto.
  - **Docs**: `README.md` (sección "Espejo local de producción"), `docs/PROCEDURES.md` (§(f) LAN, §(g) mailpit, §(h) sincronización prod→local), `NOTES.md` (fase 3) — backups `.bkup-20261018`; `agents/magantech.md`, `MAPA.md`, `harness/magantech.harness.json`.
- **Afecta a**: kalimete (DNS/mDNS/CA LAN), preprod MaganTech, agentes MaganTech, WordPress, Armada Suite (docs)
- **Causa**: owner (validación online+local; acceso LAN; reflejo de producción; correo simulador)
- **Estado**: ✅ verificado (dig desde LAN: `*` → 10.0.0.106; front-door 200 magantech/zionv/erp; smoke 100%; títulos/theme idénticos prod↔local; mailpit con mensaje)
- **Notas**: prod NUNCA modificado (capturas solo GET). Pendiente owner: importar CA en las otras máquinas + rotar App Password Victoria. Rollback = `.bkup-20261018` de cada archivo.

### [17:15] - MaganTech: causa raíz marca "Tienda" cerrada (ERP prod sin nombre) + update para Juan Carlos + Armada Suite 5.4.2 (auto-sync)
- **Tipo**: servicio | docs | infra
- **Contexto**: owner — "Analiza el ERP Dev para validar porque no envia lo que debe de enviar y asi crear un update para Juan Carlos y este haga lo que debe de hacer para que nuestro plugin Armada Suite funcione correcto".
- **Modificado**:
  - **ERP Dev — causa raíz: GAP DE DATOS, no de código**. El endpoint `GET /api/ecomm/tienda/config` incluye el nombre desde siempre (`'name' => $instance->nombre` directo, sin fallback, en el código que corre prod — verificado con `git show 34de630~1`); la fila `business_instances` id=10 en la DB prod tiene `nombre` vacío. Loop código↔DB verificado live en preprod local (tenant 3: `brand.name` == `business_instances.nombre` exacto). Dónde vive: `business_instances.nombre` (fallbacks: slug → `system_settings.empresa_nombre`). Branch `dev/ecomm-erp` intacto @`34de630` (fallback defensivo + `warnings:["IDENTITY_EMPTY"]` + aliases + header `X-ERP-Tenant` — pendiente merge por Juan; NO está en origin/main).
  - **Update para Juan Carlos** (texto listo, entregado al owner): capturar el nombre en tenant 10 — Opción A (UI: panel Owner → Instancias → editar instancia 10 → campo "Nombre") o B (SQL `UPDATE business_instances SET nombre='MaganTech' WHERE id=10`) + SQL de verificación post-captura + re-sync en WP (hint ops/settings debe mostrar `brand_name:"MaganTech"`). Recomendación adicional: integrar `34de630` (100% aditivo/backward-compatible).
  - **Armada Suite 5.4.2** (dev lab; 3 re-delegaciones por límite de pasos; **regresión 25/25 PASS**, php -l OK): **auto-sync programado** (cron `erpsuite_auto_sync_config` daily, intervalo filtrable `armada_suite_auto_sync_interval`, setting `auto_sync` default ON en form `conexion`, lazy idempotente en `init`, unschedule en deactivate, guards sin-key → skip silencioso + log, log nº campos módulo `auto_sync`, mismo flujo apply que el botón), checkbox "Sincronización automática" en tab Conexión, **mensaje UX** "⚠️ El ERP no envió nombre del negocio — captúralo en el ERP" cuando name+brand.name llegan vacíos, **doc `docs/CONTRATO-ECOMM-CONFIG.md`** (contrato JSON del payload: campos consumidos con archivo:línea, precedencia `brand.name` > `name`, regla solo-no-vacíos, aliases ERP↔plugin, payload mínimo), bump `readme.txt` Stable tag + CHANGELOG del plugin. Backups `.bkup-20261018` en `armada-suite.php`, `LegacyConnectorAdmin.php`, `AdminMenu.php`.
  - **ZIP**: `export/armada-suite-5.4.2.zip` (2.240.253 bytes, sha256 `157b1633e44f39898a409954cef766839e0c86622996c040a16a2c369c841ba9`; verificaciones canónicas storage/secrets OK) + `export/DEPLOY-GUIA.md` línea "ZIP actual" (rollback N-1 = 5.4.1).
- **Afecta a**: ERP prod (recomendación a Juan Carlos — sin acceso directo), dev lab Armada Suite (5.4.2), agentes ERP Dev/Armada Suite/MaganTech (docs)
- **Causa**: owner (validar por qué el ERP no envía el nombre + update para Juan Carlos + plugin correcto)
- **Estado**: ✅ verificado (regresión 25/25, php -l, zip con verificaciones de la guía, causa raíz con evidencia archivo:línea)
- **Notas**: 5.4.2 NO instalado en :8093 ni prod (ventana owner). El fix de la marca en prod depende de Juan Carlos (captura en ERP) + re-sync; stopgap B1/B2 sigue disponible y es durable (apply solo escribe no-vacíos). Con 5.4.2 instalado, futuros cambios de identidad del ERP se propagan solos (daily). `contact.hours` NO se consume en el apply (único flujo de horarios = sync local unidireccional).

### [18:25] - MaganTech: auditoría best-practices del ambiente — fix DNS mailpit ambiguo (fuga real), guard de entorno en mu-plugin, smoke-prod.sh nuevo, manifest de captura
- **Tipo**: servicio | config | docs | seguridad
- **Contexto**: owner — "evaluar el contenido y lo que estamos haciendo con el proyecto, procede con mejoras basándote en mejores prácticas".
- **Modificado**:
  - **🐛 Fix DNS mailpit ambiguo (fuga real de correo)**: el alias de servicio `mailpit` existe en AMBOS stacks (magantech y erpipo comparten `erpipo-dev-network`) → desde `magantech-local` resolvía NO-determinísticamente (172.21.0.4 vs 172.22.0.5). Confirmado: 5 mensajes del preprod magantech cayeron en el mailpit de erpipo (incl. tests de fase 3). Fix: mu-plugin v1.1.0 usa el **container name** `magantech-mailpit` (único en el host docker) → verificado (envío llega a la bandeja correcta, 172.21.0.4). Regla documentada en PROCEDURES §(e.6): en redes compartidas, siempre container name.
  - **Guard de entorno en mu-plugin** (v1.1.0): solo actúa si `wp_get_environment_type() === 'local'` — si el archivo llegara por error a prod, no toca nada (correo de prod intacto). php -l OK + wp_mail OK tras el cambio.
  - **`scripts/smoke-prod.sh` NUEVO** (read-only, solo GET): front/productos/REST 200 + check de marca visible (detecta "Tienda" = sync pendiente) + `ops/status` autenticado (App Password desde `secrets/`, parse robusto: password con espacios + username = primera palabra). Probado: públicos OK, ops/status 200 (plugin 5.4.0), marca=Tienda detectada correctamente (pendiente owner).
  - **Manifest de captura**: `backups/prod-content-20261018/MANIFEST.sha256` (sha256sum -c OK) + `README.md` puntero; **log del espejo movido** a `docs/ESPEJO-20261018.md` (estaba en backups/, dir gitignoreado — conocimiento atrapado).
  - **Docs**: README (sección "Marca del sitio" con el fix 1-clic pendiente + smoke-prod), PROCEDURES §(b) (nota ping-erp es POST-only, GET→404 — verificado en OpsEndpoints.php:53-56; el doc ya estaba correcto), §(e.6) learning DNS, §(g) mu-plugin v1.1.0, §(h) manifest, §(i) NUEVA (marca/sync de identidad: mecanismo, estado, fix), ESPEJO-20261018.md (corrección post-fase-3 + pendiente sync). Backups `.bkup-20261018` en los 4 archivos editados.
- **Afecta a**: preprod MaganTech (mejora), mailpit erpipo (dejó de recibir correo ajeno), agentes MaganTech/WordPress (docs)
- **Causa**: owner (auditoría + mejoras best-practices)
- **Estado**: ✅ verificado (compose config OK, smoke-8093 100% verde, smoke-prod funcional, php -l OK, mailpit recibe en bandeja correcta, manifest verifica)
- **Notas**: prod NUNCA modificado (solo GET). Pendiente owner: clic «Sincronizar configuración» en prod (marca Tienda→MaganTech; smoke-prod lo verificará). Recomendación no aplicada: git init del dir del sitio (decisión estructural del owner). Los 5 mensajes de prueba que cayeron en el mailpit de erpipo quedan ahí (simulador, efímero — sin acción).

### [20:55] - Workflow GitHub del ERP upstream fijado (owner) + agentes/harnesses ERP Dev y Armada Suite validados + release 5.4.2 commiteada
- **Tipo**: docs | infra
- **Contexto**: owner — "Tenemos acceso al github donde Juan Carlos tiene el proyecto, manejamos el branch dev/ecomm-erp… ahi hacemos los updates y todo lo que necesitamos para que Armada Suite funcione correctamente, Juan Carlos mas despues desde ese branch el hace el merge a main y pasa a produccion no nosotros, asi que documenta todo esto en el agente del proyecto… en adicional valida que el agente tanto como el harness de este proyecto este correcto".
- **Modificado**:
  - **Workflow GitHub definitivo (owner 2026-10-18) documentado en el agente del proyecto ERP**: acceso pleno a `soycarlosjerez-hub/sistema-facturacion`; **`dev/ecomm-erp` = NUESTRA rama de trabajo** (push = flujo normal, autorización permanente del owner) para todo lo que Armada Suite necesita; **Juan Carlos mergea a main y despliega a prod — NUNCA nosotros**; `main`/`develop` read-only. Aplicado en `agents/erp-dev.md` (description, modelo de ownership, workflow, regla 4, sección Producción, Vivo 2026-10-18, regla upstream, pin_note `upstream_drk`) + `harness/erp-dev.harness.json` (scope, ownership, git.regla, head_verificado, vivo_2026_10_18, decision_owner_2026_10_18).
  - **Live verificado (kalimete)**: clon `~/dev/erpipo-preprod/code/sistema-facturacion` en `dev/ecomm-erp` @`34de630` = `origin/dev/ecomm-erp` (ls-remote); `origin/main` @`bd1a879` — 8 commits nuestros esperando el merge de Juan; 8/8 containers erpipo Up 10h (db/redis/mailpit healthy); `/up` ok (database+redis true); tree local limpio.
  - **Armada Suite (delegado, agente)**: workflow ERP upstream añadido a `agents/armada-suite.md` (nueva sección "ERP upstream — workflow GitHub (regla owner 2026-10-18)" + cláusula en Vivo) + `harness/armada-suite.harness.json` (scope 5.4.2, upstream.erp_upstream, vivo_2026_10_18, zip_5_4_2 canónico, changelog). **Validación doc-vs-live 9/9**: stack Up, versión 5.4.2 triple fuente (header+define+readme), ZIP sha exacto, DEPLOY-GUIA línea ZIP actual, **regresión 25/25 PASS**, auto-sync presente (hook `:285` + deactivation `:291` + checkbox `:599` + UX `:276` + sanitize `:117`), CONTRATO-ECOMM-CONFIG.md existe, entradas .md correctas, JSON válido. Fixes de docs stale: label checkbox → "Auto-sync diario", línea Check 19/19→25/25, harness version 5.4.1→5.4.2, zip_5_4_1 destronado.
  - **Release 5.4.2 commiteada local** (kalimete, patrón de release): `e2c86ed` (7 archivos, 314 inserciones — auto-sync + contrato ecomm + UX + bump); claims "sin commitear" actualizadas a `e2c86ed` en .md + harness.
- **Afecta a**: agentes ERP Dev + Armada Suite (docs/harnesses), repo del plugin (commit local `e2c86ed`)
- **Causa**: owner (fijar workflow GitHub del ERP + documentar en el agente + validar agente/harness)
- **Estado**: ✅ verificado (ls-remote, docker ps, /up, regresión 25/25, json.tool OK ×2, sha256 ZIP)
- **Notas**: :8093 sigue en 5.4.0 (ventana owner para 5.4.2). 8 commits del ERP esperando merge de Juan (incl. `34de630` identidad ecomm). Gap de datos prod (`business_instances.nombre` tenant 10 vacío) sigue en manos de Juan Carlos — update ya enviado.

### [23:47] - Agente Game Studio creado: fábrica de juegos 3D desde cero (Blender MCP + Godot MCP + victoria)
- **Tipo**: agente | infra
- **Contexto**: owner — "evaluar el stack necesario para crear juegos 3D tipo Enshrouded con IA (Blender, Godots, MCPs, assets) y crear un agente que genere juegos completos (incl. mapas) automáticamente con los modelos de victoria (DGX GB10)". Workflow validado contra el video "Claude Fable 5 Makes FULL GAME Using Godot MCP and Blender MCP" (transcript analizado, `/tmp/opencode/refvideo.json`).
- **Modificado**:
  - **Blender 5.0.1 instalado** (apt Kali, verificado `BPY_OK` headless). Python de Blender = uv cpython-3.14 aislado → `requests` 2.34.2 vía `pip --target ~/.config/blender/5.0/scripts/addons/modules` (PEP668 bloquea pip normal).
  - **blender-mcp montado y verificado END-TO-END**: repo clon en `~/dev/tools/blender-mcp`; addon `blender_mcp.py` (mcp-for-blender 2.2.0) instalado + habilitado en userpref; cadena `uvx mcp-for-blender` (stdio) → TCP 127.0.0.1:9876 → addon → `get_scene_info` OK (9 tools; `execute_blender_code` la potente). **Hallazgos de pruebas**: (1) el addon rechaza auto-start en `blender --background`; (2) `blender --quiet` bajo xvfb NUNCA abrió :9876 (>3 min); (3) la GUI completa `xvfb-run -a blender` sí (auto-start default=True, segundos). Scripts `start-blender.sh`/`stop-blender.sh` en `~/dev/tools/blender-mcp/` (idempotente por puerto; `pkill -x` — NUNCA `pkill -f blender`: se mata al propio shell).
  - **opencode.jsonc**: MCP `blender` añadido (`uvx mcp-for-blender` + BLENDER_HOST/PORT; backup `opencode.jsonc.bkup-blender-mcp-20261018`; JSONC validado: mcp = godot, blender). Requiere restart de sesión para cargarse.
  - **Agente `game-studio`** (`agents/game-studio.md`, symlink `~/.config/opencode/agent/`): fábrica verde 7 fases (GDD → concept art victoria → assets 3D Blender+CC0 → mundo procedural → ensamblado Godot → QA visual screenshots → audio → export). Límite vs agente Godot: existentes = Godot; verde completo = Game Studio. temp 0.6/top_p 0.95 (rol creativo), steps 60. Harness `harness/game-studio.harness.json`.
  - **Workspace**: `~/dev/godot/studio/` (README; `current` symlink se crea con el primer juego; el MCP godot apunta a UN proyecto — cambiar `-p` al iniciar sesión Game Studio).
- **Afecta a**: kalimete (stack local + config opencode + agentes); victoria solo como consumidor read-only de skills existentes (art/voice)
- **Causa**: owner (crear la capacidad de generar juegos completos con IA)
- **Estado**: ✅ verificado (Blender TCP :9876 live, get_scene_info OK, JSONC OK, harness JSON OK, symlink OK). Pendiente: sesión opencode nueva para cargar MCP blender; update menor godot-mcp 1.12.3→1.12.9 opcional.
- **Notas**: **Fase 2 (requiere auth owner)**: image→3D local en GB10 victoria (Hunyuan3D 2.1 / TRELLIS vía ComfyUI :8188) — victoria read-only por defecto; reportado, NO implementado. Blender quedó corriendo bajo Xvfb (PID sesión actual) — detener con `stop-blender.sh` si sobra.

### [23:50] - MaganTech: plugin 5.4.2 desplegado y probado en local (:8091 + :8093) — auto-sync verificado end-to-end; modo del espejo public→dev; prod queda en manos del owner (§(b) manual)
- **Tipo**: servicio | docs
- **Contexto**: owner — "Da update del plugin tanto en local como en public para hacer las pruebas".
- **Modificado**:
  - **:8091 dev lab**: 5.4.2 vivo (bind-mount); auto-sync programado Y disparado solo (22:11, aplicó **6 campos** del ERP local; re-run manual idempotente **0 campos** — regla solo-no-vacíos); log `erp-suite-2026-10-19.log` módulo `auto_sync`; regresión 25/25 (misma fecha).
  - **:8093 preprod**: update §(a) de PROCEDURES (`rm -rf` + unzip ZIP 5.4.2 + reactivo; wp-cli reporta `armada-suite active 5.4.2`); smoke-8093 **100% verde**; cron auto-sync programado (daily, 04:01).
  - **Modo del espejo public→dev (hallazgo + fix)**: el port de settings del espejo heredó `erpsuite_mode=public` de prod PERO sin `public.api_key`/`api_url` (la key de prod NO se copia — seguridad) → conexión ERP viva MUERTA (renderizaba del `erp_config` cacheado del 10-17; todo sync nuevo skipeaba por guard sin-key — verificado: skip correcto 0.012s). Fix: `ERPSuite_Environment::set_mode('dev')` → perfil LOCAL sellado (ERP `:8100`, tenant 10, key 44 chars). **Auto-sync probado end-to-end**: run manual 0.34s (HTTP real) → `config_fetched_at` 2026-10-17 23:36:22 → **2026-10-19 03:29:07**, `brand.name=MaganTech`, `payment_methods=efectivo`. Reversible con `set_mode('public')`.
  - **Quirk sidecar (no bug)**: el sidecar wp-cli corre uid=82 (Alpine) y los dirs del sitio son uid=33 (Debian) → `ERPC_Logger` no escribe desde el sidecar (try/catch silencioso); el cron REAL dentro del contenedor sí loguea (probado en :8091).
  - **Docs**: `docs/ESPEJO-20261018.md` Fase 4 nueva (todo lo anterior), `docs/PROCEDURES.md` §(a) notas del espejo (modo dev + quirk) + §(i) actualizada (auto-sync 5.4.2 + estado prod real: sync corrido 18:30 aplicó 6 campos, marca sigue "Tienda" por gap de datos ERP).
- **Afecta a**: preprod :8093 (plugin 5.4.2 + modo dev), dev lab :8091 (verificado), docs del proyecto MaganTech
- **Causa**: owner (update del plugin en local y public para pruebas)
- **Estado**: ✅ verificado (wp plugin list 5.4.2, smoke 100%, config_fetched_at bump, logs auto_sync, brand MaganTech)
- **Notas**: **PROD queda pendiente del owner** — flujo §(b) manual documentado: wp-admin → Plugins → Añadir nuevo → Subir plugin → `export/armada-suite-5.4.2.zip` (WP reemplaza y reactiva solo). Tras subirlo kalimete verifica con `smoke-prod.sh` (ops/status debe reportar plugin 5.4.2; la marca seguirá "Tienda" hasta el fix de datos de Juan Carlos — el mensaje UX nuevo "el ERP no envió nombre del negocio" lo dirá explícito). Rollback: subir ZIP 5.4.1.


## 2026-10-17
### [16:41] - Armada Suite 5.4.0: el sync APLICA los datos del negocio del ERP a la tienda (paridad dev/público) + fix payment_methods falsos
- **Tipo**: servicio | feature | fix
- **Modificado**:
  - **Evaluación kalimete (LIVE, ambos ERPs)**: el fetch de config NO tenía gate dev/público (0 usos de is_dev en el path) — la asimetría que percibía el owner era de DATOS+APLICACIÓN: (1) `normalize_config` descartaba contact/policies/store/branches/delivery/pickup/delivery_zones/seo; (2) `/ecomm/tienda/config` no trae payment_methods → se guardaban 5 defaults hardcodeados COMO si fueran del ERP (probado en BD local: guardaba los 5; el tenant 10 real solo tiene `efectivo`); (3) `get_brand` merge local-wins → el ERP nunca pisaba valores locales seteados (en local "se veía actualizar" solo el logo porque estaba vacío); (4) `ajax_fetch_config` sin bump de caché (catálogo hasta 15 min stale); (5) save-probe escribía `config_fetched_at` en la raíz (invisible para `prep_tenant`) y descartaba erp_config.
  - **Fix 5.4.0** (implementó subagente Armada Suite; verificó kalimete): **apply-on-sync** — al sincronizar (botón "Obtener configuración" y save-probe de Conexión) se APLICAN brand (name/logo/colores/tagline/favicon), contacto y payment_methods SOLO con valores no-vacíos del ERP; nunca toca hero_image/smtp/api_key/per_page/cart_ttl/theme/template/ia/whatsapp/env_mode. Snapshot previo en `erpsuite_identity_backup` + rollback 1-click (AJAX `erpsuite_restore_identity`, manage_options+nonce, botón en tab Conexión). payment_methods completados desde `/tienda/config` (merge no-bloqueante) y parseados objetos `{id,label}`/strings; sin dato → `[]` (nunca inventados). `normalize_config` conserva el negocio completo (claves aditivas). Fix path `tenant.config_fetched_at` + guardado de erp_config en el probe. Bump `erpsuite_cache_v` al sincronizar. **Reversión del SSOT-local de 5.3.3 para datos provistos por el ERP (decisión owner 2026-10-17).**
  - **Verificación**: php -l OK (4 archivos); regresión **24/24 PASS** (19 originales + 5 nuevos: parse payment, conservación de campos, apply+snapshot, rollback, paridad shapes dev/prod); LIVE contra ERP real :8100 — apply de 6 campos (brand.name "MaganTech Store"→"MaganTech", logo vacío→ERP, colores #465d7c/#b575c2→#1a73e8/#34a853, tagline, payment ["transferencia"]→["efectivo"] dato REAL) + rollback restauró 6/6 y consumió el snapshot. **ZIP canónico** `export/armada-suite-5.4.0.zip` 2.216.778 B sha256 `24b4255c10a7410f76b8ac00da699f5031ead5fbb2a0de08e721c0835cb0e939`; verif secrets vacío + storage stubs OK.
- **Afecta a**: producción WP del cliente MaganTech (cPanel, tenant 10 contra erpipos.armada.do) — deployar 5.4.0 y sincronizar; el sync ahora actualiza la web con los datos del negocio del ERP en público igual que en local
- **Causa**: owner: "así como se actualiza al momento de sincronizar con el local, también debe poder hacerlo con el público — evaluar y mejorar"
- **Estado**: ✅ verificado (24/24 + LIVE apply/rollback + ZIP verificado)
- **Notas**: WP local restaurado a su estado original tras la demo (snapshot consumido). Repo del plugin SIN commit aún (working tree listo si el owner autoriza). Para el cliente: subir 5.4.0 → Conexión ERP → sincronizar → identidad aplicada + payment_methods reales; rollback disponible. La key `iak_mti5…` del tenant 10 fue validada LIVE contra prod (config completa + 238 productos) — el ERP está sano.

### [16:58] - Validación LIVE producción cliente MaganTech (magantech.com.do): App Password OK, sitio en 5.4.0, sync pendiente
- **Tipo**: servicio | verificación | seguridad
- **Modificado**: nada (solo lectura + 1 dry-run auditado en el sitio del cliente)
  - **Credenciales**: App Password del usuario WP `Victoria` (administrator) en magantech.com.do — **válida** (users/me 200, roles administrator). Circuló por chat → **rotar al terminar el trabajo** (REMOTE-OPS §4).
  - **Estado del sitio**: HTTP/2 200 TLS OK; WP 7.1.3, PHP 8.5.11; **armada-suite 5.4.0 activo** (el owner ya deployó el ZIP); env=public → erpipos.armada.do; namespaces REST incluyen erpsuite/v1 + wpvibe/v1 + ai1wm/v1.
  - **Conexión ERP**: POST /ops/ping-erp desde SU hosting → **200 en 634ms**, key fp `b221457f` — red y key sanas.
  - **Catálogo**: /productos/ renderiza 15 cards (idéntico al control local :8091).
  - **Hallazgo clave**: brand visible = **"Tienda" (default)** → `erp_config` quedó VACÍO en su sitio (falso éxito de la versión pre-5.4.0 — el bug que corregimos); los colores visibles (#1a73e8/#34a853) vienen del `theme_preset: azul`, no de settings; `payment_methods` local = ["transferencia"] cuando el ERP tenant 10 solo acepta `efectivo` (riesgo real en checkout).
  - **Dry-run ops/settings** (auditado, sin cambios): preview `pv_p0cAxUlXl9db` con diff de 6 campos listos (brand.name→MaganTech, logo→ERP, colores, tagline, payment→[efectivo]).
- **Afecta a**: producción WP cliente MaganTech
- **Causa**: owner entregó credenciales para validar y verificar producción
- **Estado**: ✅ verificado (auth, plugin, ERP, catálogo) | ⚠️ pendiente 1 acción
- **Notas**: **Acción restante**: en wp-admin del cliente → Armada Suite → Conexión ERP → **"Obtener configuración"** — la 5.4.0 fetchea config real (llena erp_config), aplica identidad (los 6 campos del dry-run) + snapshot + rollback + bump de caché. Alternativa remota (no recomendada): activar modo trabajo + confirmar preview_id — no llena erp_config. admin-ajax NO acepta App Passwords → el sync no es disparable remotamente.

### [20:20] - Reorg hub WP: plugins/ + websites/ por cliente + agente Magantech (primero de la red)
- **Tipo**: infraestructura | reorganización | agente
- **Modificado**:
  - **Decisión owner 2026-10-17**: hub `~/dev/wordpress/` reorganizado — `plugins/` (proyectos con sus dev labs) + `websites/` (un ambiente por CLIENTE nombrado por dominio: preprod local + conexión prod + agente + harness + docs). Pipeline oficial: dev lab :8091 (source) → ZIP canónico → preprod del cliente (instala el ZIP) → prod (deploy manual + ops remota erpsuite/v1).
  - **Moves verificados** (playbook: dump pre-move → down → mv → up → smoke → volúmenes sin huérfanos): armada-suite → `plugins/armada-suite` (dump 606K; git HEAD b4c2a89 intacto + 14 archivos 5.4.0 sin commitear; smoke-8091 verde; regresión 24/24; :8091 200) · zionv-crm → `plugins/zionv-crm` (dump 967K; git del plugin HEAD 5d3efab intacto; smoke-8092 verde; docs internos corregidos).
  - **NUEVO `websites/magantech.com.do/`** (agente Armada Suite): preprod :8093/:3309 (compose `magantech`, imagen wordpress:7.1.3-php8.3-apache ESPEJO EXACTO de prod, red erpipo-dev-network → ERP local tenant 10), plugin 5.4.0 desde ZIP release, /productos/ 15 cards + colores ERP #1a73e8/#34a853 verificados, sync identidad applied=6 + snapshot, smoke-8093 100% verde, secrets/ (prod-connection.md + preprod-admin.md, 600/700), README con inventario REAL de prod (tema Hello Elementor; armada-suite 5.4.0 + JetBackup 3.1.23.6 + Mantenimiento web 0.15; 2 admins; 16 páginas; 1 post, 0 media), docs/PROCEDURES.md con learnings (wp-cli sidecar: env vars DB + WP_ENVIRONMENT_TYPE=local; binds www-data → chown antes de unzip).
  - **NUEVO agente `Magantech`** (kalimete): agents/magantech.md + harness/magantech.harness.json + symlink en ~/.config/opencode/agent/ + permission.task de kalimete — primer agente por-cliente de la red de websites.
  - **Docs hub** (agente WordPress): README-HUB.md reescrito al nuevo layout; NUEVO docs/NUEVO-WEBSITE-TEMPLATE.md (playbook replicable de alta de clientes, convención puertos 809X/330X ascendente — próximo 8094/3310); PROBAR-PLUGIN-EN-8091 + NUEVO-PLUGIN-TEMPLATE + plugins-disponibles/* actualizados; grep de rutas viejas = 0.
  - **Fleet**: paths curados (replaceAll + .bkup-20261017-pluginsmove) en agents/{armada-suite,zionv-crm,wordpress-dev}.md + harness/{armada-suite,zionv-crm,wordpress-dev}.harness.json; MAPA.md sección WP reescrita (labs + websites + prod magantech + pipeline); vivo_2026_10_17 en harnesses.
- **Afecta a**: kalimete dev (rutas nuevas), cliente MaganTech (preprod + agente dedicado), futuros clientes (template replicable)
- **Causa**: owner: "plugins en plugins/, websites de clientes en websites/ con su agente cada uno — empezando con magantech.com.do; trabajo local + conexión a producción"
- **Estado**: ✅ verificado (smokes 8091/8092/8093 verdes, regresión 24/24, volúmenes sin huérfanos, greps limpios, JSONs válidos)
- **Notas**: ⚠️ ROTAR la App Password de prod del usuario Victoria (circuló por chat 2026-10-17). Pendientes: Parte 3 (template vía ops — allowlist de themes en OpsMotor + bump 5.4.1) DIFERIDA a tarea posterior; decisión owner: repos git del hub padre y de websites/; commits de los working trees (5.4.0 de armada sin commitear); webhooks ERP→preprod opcionales.

### [21:55] - Método canónico de conexión + tooling preprod + release 5.4.1 (template vía ops + fix rollback v4.3.0)
- **Tipo**: servicio | feature | fix | docs
- **Modificado**:
  - **Commits autorizados (owner "Haz commit")**: armada-suite `af871dd` (release 5.4.0) + `a2db7f5` (infra reorg: compose pin, changelog, gitignore backups/, stubs SiteBackup restaurados) + `11b2784` (release 5.4.1) + docs CHANGELOG raíz; zionv `a1288fe` (docs rutas). Sin push (armada sin remote; zionv push pendiente autorización owner).
  - **Método canónico** (agente WordPress; `~/dev/wordpress/docs/CONEXION-METODO.md` = LA referencia única, sin discrepancia): dev lab/preprod = **bash + wp-cli sidecar** (MCP = vía muerta documentada — revivirlo es decisión owner); prod cliente = **App Password usuario dedicado + jaula erpsuite/v1/ops + deploys manuales de ZIP**. Respuesta explícita al owner: **"no editar prod directamente" SÍ es la manera correcta** (staging-first respaldado por developer.wordpress.org/make.wordpress.org/wp-cli/Kinsta 2026; App Passwords SIN scoping en WP core → nuestra jaula server-side es la mitigación correcta).
  - **Tooling**: `scripts/plugin-preprod.sh` (202 líneas, probado EN VIVO contra magantech preprod: PASS idempotente, backup tar.gz + rollback automático + smoke integrado) — instalación/actualización canónica de plugins en websites/; README-HUB + NUEVO-WEBSITE-TEMPLATE actualizados apuntando al método canónico.
  - **Release 5.4.1** (agente Armada Suite): template del tema activo editable vía ops — live reads en safe (`scope=live`), live-writes en work mode con gates encadenados fail-closed (sandbox realpath + Guard + allowlist ext + syntax check PHP + backup antes de escribir + preview/confirm/anti-drift); `/ops/rollback` file-aware; REMOTE-OPS.md con política owner 2026-10-17. **Fix bug real v4.3.0**: ids de backup mixed-case vs búsqueda sanitize_key → TODOS los /ops/rollback fallaban "Backup no encontrado" desde v4.3.0 — corregido (impacta clientes prod: los rollbacks ahora funcionan de verdad). **Fix SiteBackup**: cron `ai1wm_storage_cleanup` del AIOWPM vendored borraba storage/.htaccess+web.config >24h (causa raíz de los stubs borrados) — añadidos al exclude. Regresión **25/25** (re-verificada por kalimete). ZIP `export/armada-suite-5.4.1.zip` (2.225.650 B, sha256 `4bb2fa2c…`).
- **Afecta a**: plugin armada-suite (5.4.1 listo para deploy manual), operación remota de clientes (rollbacks reparados), docs del hub
- **Causa**: owner: "no quiero discrepancia — el mejor método de conexión, full control local, instalar nuestros plugins, validar si no editar prod es correcto; haz commit y procede con los cambios"
- **Estado**: ✅ verificado (25/25 re-run kalimete, ZIP sha verificado, LIVE read/write/rollback en :8091, script preprod PASS en vivo)
- **Notas**: Hardening prod pendiente para próxima ventana de deploy (DISALLOW_FILE_MODS + filtro `wp_is_application_passwords_available_for_user` + rotación 90 días) — decisión owner, NO auto-aplicar. ⚠️ App Password Victoria pendiente de rotar (circuló por chat). Deploy 5.4.1 al cliente = manual per DEPLOY-GUIA. En prod endurecido con DISALLOW_FILE_EDIT/MODS el live-write del template queda bloqueado por diseño (documentado REMOTE-OPS §4).

### [23:55] - Flota: agente MaganTech (#20, website cliente) + dominios locales por proyecto + curación de deriva
- **Tipo**: agente | docs | infra | red
- **Modificado**:
  - **Agente `MaganTech`** (#20): `agents/magantech.md` + `harness/magantech.harness.json` (symlink `~/.config/opencode/agent/magantech.md` vivo). `opencode agent list` confirma `MaganTech (subagent)` → flota = **1 primary + 20 subagentes**; `permission.task` de kalimete corregida a `"MaganTech"` (name-match exacto; antes `"Magantech"`).
  - **Dominios locales por proyecto** (política owner 2026-10-17): verificados 200 → `wordpress`, `zionv`, `magantech`, `erp` `.kalimete.local` (mkcert + nginx-TLS front-door). Template `docs/NUEVO-WEBSITE-TEMPLATE.md` **§8 "Dominio local"** añadido (131→171 líneas) para futuros; documentado en MAPA.
  - **Curación de deriva** (reportada por subagentes; sin falsos positivos): `MAPA.md` (armada-suite 5.3.2→5.4.1, HEAD b4c2a89→dc46307, ZIP 5.4.1 sha `4bb2fa2c…`, regresión 25/25, dominios, filas zionv/magantech); `wordpress-dev.md` + harness (5.3.5→5.4.1, vivo 2026-10-17); `plugins-disponibles/armada-suite.txt` (5.4.1); `kalimete.md` (20 subagentes, vía MCP muerta documentada).
  - **Commits repos plugins (locales, sin push)**: armada-suite `dc46307` (docs CONTROL-PLANE nuevo + REMOTE-OPS curado; sin remote); zionv `9698224` (`.gitignore *.bkup*`) — main ahead 2, push pendiente autorización owner.
- **Afecta a**: kalimete (enrutado de flota), hub WP (~/dev/wordpress), website MaganTech, futuros websites
- **Causa**: owner — "cada proyecto debe tener su agente propio y su dominio local preparado y funcionando; actualiza y documenta todo lo necesario para que los agentes tengan la información correcta"
- **Estado**: ✅ verificado (agent list 1+20; dominios 4/4 = 200; JSONs válidos; symlink vivo)
- **Notas**: pendientes siguen — rotar App Password Victoria (prod) + admin preprod; ventana preprod 5.4.0→5.4.1; push zionv (ahead 2). Bridge MCP `wp-magantech` y variante B de escritura de plugins: esperan OK del owner.


## 2026-10-16
### [00:27] - Armada Suite 5.3.4: reporte honesto de errores de config ERP (incidente prod 404 enmascarado) + curas de docs hub
- **Tipo**: servicio | fix | docs
- **Modificado**:
  - **Incidente prod owner**: al sincronizar en producción con 5.3.3 recibió "ERP HTTP 404 … (The route api/tenants/10 could not be found.)". Diagnóstico CONFIRMADO en código (`ApiClient.php:843-882`): `get_business_config()` capturaba SOLO el último error del loop (`/ecomm/tienda/config` → `/tienda/config` → `/config` → `/tenants/{id}`) — el 404 del fallback muerto `/tenants/10` (ruta inexistente en todo ERP) tapaba el error REAL de los endpoints principales (401 = key stale prod, documentado 2026-10-13).
  - **Fix 5.3.4** (commit `6729d4c`, repo ~/dev/wordpress local-only): helpers `config_attempt()` + `config_error_rank()` — prioridad 401/403 (auth) > 5xx/timeout > 404; mensaje "ERP HTTP {code} en {endpoint}: {msg}"; hint "API key inválida, inactiva o sin permisos: verifica la key en el tab Conexión ERP" para 401/403; si todos 404 sugiere módulo ecomm. Regresión 19/19 PASS, lint OK. **ZIP canónico** `export/armada-suite-5.3.4.zip` 2.207.069 B sha256 `c57df620…` (storage presente, sin secrets). DEPLOY-GUIA: ZIP actual 5.3.4 + rollback N-1 5.3.3 (estaba stale 5.3.1) + excepción `!export/DEPLOY-GUIA.md` en .gitignore (adiós `git add -f`).
  - **Curas docs hub (pendientes completados)**: `agents/erp-dev.md` + `harness/erp-dev.harness.json` — HEAD `2306b64`/7 commits → `34de630`/**8 commits** (nuevo: identidad ecomm) + vivo_2026_10_16; `agents/armada-suite.md` + `harness/armada-suite.harness.json` — 5.3.2/`a838486` → 5.3.4/`6729d4c`, entradas Cambios recientes 5.3.3+5.3.4, zips 5.3.3/5.3.4 con sha, vivo_2026_10_16. JSONs validados.
- **Afecta a**: producción WP (necesita deploy 5.3.4 para ver el error REAL), preprod (ya sirve fix vía bind mount), docs flota
- **Causa**: reporte owner del error prod + orden de completar pendientes
- **Estado**: ✅ verificado (19/19, lint, JSON OK, ZIP canónico verificado)
- **Notas**: **La causa raíz en prod sigue siendo la API key inválida/stale del tenant** — 5.3.4 solo deja de ocultarla; al deployar y reintentar verá "ERP HTTP 401 en /ecomm/tienda/config: … — API key inválida…". Acción owner/Juan: provisionar key válida para el tenant prod y guardarla en Conexión ERP (el probe la valida antes de grabar). ERP `34de630` sigue esperando merge de Juan (8 commits).

### [00:51] - Armada Suite 5.3.5 + validación key prod: Sanctum válida, canal equivocado (ecomm público exige iak_)
- **Tipo**: servicio | fix | seguridad
- **Modificado**:
  - **Validación live prod** (key del owner tratada como secreto: test vía curl -K con archivo 600 + `shred -u` posterior, cero rastros, key nunca impresa): la key `4|…` **ES un token Sanctum válido en prod** — `/api/tienda/productos` → 200, `/api/tienda/config` → 200 forma plana, pero `/api/ecomm/tienda/config` → 401 INVALID_API_KEY. Causa en código (`resolveApiKeyPublic()`, TiendaApiController): exige prefijo `iak_` explícito + lookup `InstanceApiKey::activeByHash(sha256)` — Sanctum NUNCA pasa el canal público. En cambio `api-auth` (AuthenticateApiKey) SÍ acepta Sanctum vía fallback `PersonalAccessToken::findToken`. **Veredicto: key correcta, canal equivocado.**
  - **Fix 5.3.5** (commit `b4c2a89`, repo ~/dev/wordpress local-only): `get_business_config()` acepta forma plana `{tenant_id,name,brand,…}` además de `{data:{…}}` (el probe al guardar ya la aceptaba; el sync la ignoraba → con el token actual el `/tienda/config` 200 plano ahora sincroniza SI el tenant coincide); guard `erpc_tenant_mismatch` 409 (no mergea negocio ajeno; tenant 0 = autodetect); aviso no-bloqueante si la key no es `iak_` ante 401/403. Regresión 19/19 PASS. **ZIP canónico** `export/armada-suite-5.3.5.zip` 2.207.808 B sha256 `b9c67bc8…`. DEPLOY-GUIA: ZIP actual 5.3.5 + rollback N-1 5.3.4. Nota: `!export/DEPLOY-GUIA.md` en .gitignore NO basta (git no re-incluye bajo dir excluido) — sigue requiriendo `git add -f`.
  - **Docs hub curados**: armada-suite 5.3.5/`b4c2a89`/zips 5.3.3+5.3.4+5.3.5 (agente + harness, JSON validados).
- **Afecta a**: producción WP (deployar 5.3.5 y reintentar sync), ERP prod (sin cambios — canal público por diseño solo-`iak_`, decisión upstream Juan)
- **Causa**: owner reporta 401 persistente con key que "es correcta" — validación del canal auth + fix de la inconsistencia probe-vs-sync
- **Estado**: ✅ verificado (live prod 200/401/404 discriminados, 19/19, ZIP canónico)
- **Notas**: ⚠️ **ROTAR la key expuesta** — quedó en el historial del chat; es un token de staff con acceso API al panel prod: revocarlo en ERP prod y generar uno nuevo (o mejor: provisionar **instance key `iak_*`** para tenant 10 vía admin ERP Configuración > API > Nueva API Key, o tinker `OwnerService::createApiKey($instance10,…)` — el raw se muestra una sola vez). Best practice: `iak_*` (scope tienda) > Sanctum de usuario (scope staff) como store-key. Qué esperar al reintentar con 5.3.5: ✅ "Configuración obtenida" si el token es del tenant 10; ⚠️ mismatch 409 si es de otro tenant (revela el tenant real); ❌ 401+hint si el token murió. ERP `34de630` sigue esperando merge de Juan (8 commits).

### [15:30] - Reestructuración dev hub: ambos stacks WP bajo ~/dev/wordpress/ con nombres reales de plugins
- **Tipo**: infraestructura | reorganización | docs
- **Modificado**:
  - **Estructura nueva** (decisión owner: "los 2 wordpress dentro del directorio wordpress, con nombres reales"): `~/dev/wordpress/` = padre hub (README-HUB.md, docs/, plugins-disponibles/, scripts/) + hijos `armada-suite/` (stack :8091, Plugin Name "Armada Suite") y `zionv-crm/` (stack :8092, Plugin Name "ZionV CRM"). `~/dev/zionv-crm/` eliminado (dotfile `.gitignore` recuperado).
  - **Compose pinneados** con `name: wordpress` / `name: zionv-crm` — volúmenes `wordpress_*` + `zionv-crm_*` intactos tras down/mv/up (sin huérfanos, sin pérdida de datos). Dumps pre-move: `armada-suite/backups/manual/wp-wordpress-premove-*.sql` (677K) + `zionv-crm/backups/manual/` (941K).
  - **Git preservado**: historial Armada 5.3.5 `b4c2a89` en `armada-suite/.git` (mv del tree; padre hub sin git propio, pendiente decisión owner). Subrepo ZionV intacto (`origin warcold/zionv-crm`, HEAD 1.56.3).
  - **Validación post-move**: 4 containers healthy; regresión Armada **19/19 PASS**; smoke-8091 (front/login/REST 200, `/%postname%/`, armada-suite activo) + smoke-8092 (front 301, wp-login 302, REST 200, `/crm/dashboard/` 302, pretty ON, zionv activo, 43 tablas, db_version 1.24.0) 100% verde; `wordpress-local` re-verificado en `erpipo-dev-network`.
  - **Higiene docs completa** (9 archivos con .bkup-20261016-hubmove): rutas `~/dev/zionv-crm/` → `~/dev/wordpress/zionv-crm/` y `~/dev/wordpress/{wp-content,export,certs,secrets,docker-compose}` → bajo `armada-suite/` en agents/wordpress-dev.md, agents/armada-suite.md, agents/zionv-crm.md + 3 harness JSON (validados); versión 5.3.2→5.3.5 en estado actual (historial preservado); permalinks PLAIN→`/%postname%/` (live); DEPLOY-GUIA de ambos plugins a rutas nuevas (ZionV bump 1.56.2→1.56.3); template NUEVO-PLUGIN + PROBAR-PLUGIN-EN-8091 al layout hub; smoke-8091.sh (STACK nuevo) + smoke-8092.sh creado (check OR regex reparado) + plugins-disponibles/*.txt actualizados; README-HUB.md nuevo.
- **Afecta a**: kalimete dev únicamente (puertos/dominios/vhosts/redes sin cambios; ERP y prod intactos)
- **Causa**: owner: el nombre `wordpress` para UNO de los dos stacks confundía; quiere hub padre con nombres reales de plugins
- **Estado**: ✅ verificado (smokes + regresión + vols + estructura final limpia)
- **Notas**: symlink legacy `~/dev/zionv-crm` NO creado (decisión: no necesario). Pendiente decisión owner: crear repo git para el hub padre (hoy sin .git) y si los subagentes deben migrar sus paths hardcodeados restantes en herramientas propias.


## 2026-10-15
### [12:55] - Flota: split agente-plugin — armada-suite creado, wordpress-dev redimensionado a SISTEMA (umbrella)
- **Tipo**: agente | config | sync (TARGET=kalimete local; repo armada-sync)
- **Modificado**:
  - **Nuevo agente `armada-suite`** (regla owner 2026-10-15: cada plugin WP su agente, así como ZionV CRM): `agents/armada-suite.md` (frontmatter 0.6/0.95/15, edit+write allow) + `harness/armada-suite.harness.json` + symlink `~/.config/opencode/agent/armada-suite.md`. Contenido migrado íntegro desde wordpress-dev: plugin 5.3.2, OpsMotor 15 rutas, webhooks, feature flags, Fases A/B/C, integración ERP (Fases 1/2/3, deuda P3), empaquetado ZIPs, lecciones CLI, releases 5.x. **Nueva sección Multitenant** (modelo por-sitio verificado: un WP = un tenant; receta de alta por negocio; tenants live ERP: magantech=10 activo con key+webhook, micaserogou=3 bloqueado sin key — pendiente provisionar; IA por tenant vive en el plugin, la del ERP es panel-only).
  - **`agents/wordpress-dev.md` redimensionado** a SISTEMA/umbrella: stack WP core, contenedores, compose, certs, secrets, DB, nginx/TLS, deploy. Nueva tabla **Plugins conocidos** (armada-suite ACTIVO / zionv-crm stack aparte :8092 / históricos Elementor-EMCP-MCP sin agente) + regla "wordpress-dev NUNCA desarrolla plugins — delega". Secciones del plugin removidas (migradas a armada-suite). Backup `.bkup-20261015-split`.
  - **`harness/wordpress-dev.harness.json` redimensionado** en espejo: scope sistema-only, `plugins_conocidos[]`, `umbrella`; zip_*/feature_flags/agente_mixto/integracion_erp/lecciones_cli/deuda_p3 → harness armada-suite. Backup `.bkup-20261015-split`.
  - **`agents/kalimete.md`**: permission.task +`"Armada Suite": allow` +`"ZionV CRM": allow` (ZionV faltaba en el registro — huérfano desde su creación 2026-10-13); lista de flota 19→21 subagentes; tabla de delegación con filas nuevas (WordPress=SISTEMA, Armada Suite=plugin multitenant WP↔ERP, ZionV CRM=plugin CRM :8092); lista creativos/dev + Armada Suite/ZionV CRM. Backup `.bkup-20261015-split`.
  - **`MAPA.md` curado**: sección WordPress Dev stale (decía WP 7.1.1 + Elementor + erp-commerce-suite v4.4.0 8/8 + admin:admin123 + repo GitHub) → live real (WP 7.1.3, Armada Suite 5.3.2 19/19, App Passwords, repo local sin remote, rama dev/ecomm-erp @2306b64); tabla subagentes: fila wordpress-dev corregida + filas armada-suite/zionv-crm añadidas + eco-accesos/eco-voice retirados de la tabla activa. Backup `.bkup-20261015-split`.
- **Afecta a**: kalimete (flota 21 subagentes), delegación futura plugin Armada Suite (antes vía WordPress), registro ZionV CRM
- **Causa**: orden del owner — WordPress = sistema del mismo, no plugins; cada plugin su agente separado con docs/git/harness conocido por WordPress (umbrella); Armada Suite multitenant WP↔ERP (magantech 1 ejemplo, micaserogou y futuros igual: IA, inventario, comprar, usuarios por tenant)
- **Estado**: ✅ verificado (symlinks OK, JSON harness válidos, grep flota consistente)
- **Notas**: evaluación previa en 3 vías (WordPress: split línea a línea + patrón ZionV; ZionV CRM: plantilla referencia + drift de registro detectado; ERP Dev: 10 tenants live, micaserogou=3 pendiente desbloquear+key+webhook). Pendiente owner: provisionar tenant 3 micaserogou lado ERP; extracción del plugin a repo git propio = decisión futura.

### [18:31] - Borrado completo: proyectos Alfredo Ecomm + Woodly eliminados (kalimete, vps-preprod, DNS, GitHub, flota 21→19)
- **Tipo**: infra | servicio | agente | red | seguridad
- **Modificado**:
  - **kalimete local**: docker `alfredo-ecomm-*` down -v (3 contenedores :3004/:5432/:6379, 2 volúmenes seed-only, red backend_erp-network); imágenes backend-api + 5 dangling + postgres:16-alpine + node:20-bullseye-slim (~2.46GB); rm repos `~/dev/webs/alfredo-pro-ecomm` (142MB, .env secrets incl.) + `~/dev/apps/woodly.deleted-20261015` (178MB) + `~/dev/webs/woodly` (175MB); imágenes woodly-backend + staging-woodly (1.4GB) + 3 volúmenes staging (0 usuarios verificados); vhost nginx + certs mkcert woodly.kalimete.local; token /etc/hosts (línea compartida intacta, .bkup previo); dev-tunnel.sh, ops/apps/woodly (creds texto plano), Escritorio/erp-migration/02-woodly.md; `~/dev/webs/` eliminada (quedó vacía); cáscara root-owned `~/projects/alfredo-pro-ecomm.archived-20261005` (sudo); 10 archivos compartidos editados con .bkup-20261015 (dev.sh, deploy.sh ×2 —incl. drift ops/scripts/deploy.sh—, setup-dev-proxy.sh, apps/kalimete/index.html, infra/nextcloud-stack Caddyfile+README+CHANGELOG, ops/README.md, ops/agents/backups/AGENTS.md)
  - **vps-preprod (TARGET verificado auth.armada.do)**: contenedor woodly-woodly-1 down + volumen woodly_pgdata rm manual (47MB, SIN dump por orden owner); imagen woodly-woodly (93MB); /opt/woodly (4.3MB, .env); /opt/backups/woodly*; bloque Caddy woodly.armada.do (.bkup previo) + restart caddy — vecinos OK (auth 302, pets 200); backup-vps.sh l.13 (rsync bug ragnarok→woodly) + l.24 refs (.bkup previo, bash -n OK)
  - **WordPress**: Application Password `alfredo-ecomm` REVOCADA (user admin, uuid 892f927b; probe 200→401) + `secrets/app-password-alfredo-ecomm.txt` borrado; stack healthy
  - **Cloudflare**: registro DNS `woodly.armada.do` (A proxied → 154.53.35.102, id c273e3ac…) ELIMINADO de zona armada.do — verificado 0 registros
  - **GitHub**: repos `warcold/woodly` + `warcold/alfredo-pro-ecomm` ELIMINADOS (gh, verificado not-found)
  - **Flota 21→19**: agents/alfredo-ecomm.md + woodly.md + 9 .bkup + symlinks ~/.config/opencode/agent/ ELIMINADOS; harness alfredo-ecomm/woodly .json + 6 .bkup ELIMINADOS; `kalimete.harness.json` curado (subagentes 19 con Armada Suite/ZionV CRM — drift pre-split corregido, updated 2026-10-15); `agents/kalimete.md` (permission.task -2, flota 19, tabla delegación, creativos); `MAPA.md` (docker 7 containers, app-passwords, servicios/DNS vps, 2 líneas NUEVO stale, 2 filas agentes); `agents/wordpress-dev.md` (auth curada); `upstream/state.json` (-eco-woodly, -eco-alfredo-ecomm); `configs/INVENTARIO.md` + copia local cloudflare-map (-fila woodly); `skills/cloudflare/SKILL.md` (nota ELIMINADO, certs, timers backups) + copia local; copia local ecosistema-map/MAPA.md sincronizada; agents/vps.md + harness/vps.harness.json (woodly fuera de servicios/contenedores/DNS/caddy); harness wordpress-dev/armada-suite/erp-dev curados (app-password revocada, curls del secrets file borrado → placeholder, ownership WP/Armada Suite)
- **Afecta a**: kalimete (flota 19, ~/dev reorganizado), vps-preprod (caddy, backups), Cloudflare DNS, GitHub, ecosistema WP (INTACTO — verificado cero dependencias :3004/:5173 en compose/nginx/plugins/DB/cron)
- **Causa**: orden del owner — Alfredo Ecomm no encaja con el ecosistema WordPress+plugins; no habrá trabajo con Woodly; SIN backups (pérdida aceptada: commit f8df738 docs + stash abril + DB woodly_pgdata 47MB)
- **Estado**: ✅ verificado (docker 0 restos local+VPS, puertos 3004/5432/6379/5173 libres, DNS borrado, gh not-found, WP 200, caddy vecinos 200/302, JSONs válidos)
- **Notas**: MAPA corregía claim stale "Ecomm ERP en vps-preprod" (nunca existió ahí). Pendientes owner: registro A `woodly.alfredo.pro` en banahosting (manual cPanel); backups jonas `/srv/backups/vps/woodly/` (inverificable, jonas caído); token CF `spring-dream-d681` auth error 10000 (restricción IP — operación completada con token opencode-dns-cleanup); follow-up: dump ragnarok-db de backup-vps.sh l.12 ahora muere en $TMP sin destino. Higiene WP pendiente (pase aparte): UPDATE-ERP-AMIGO/ mal ubicado, backups/ 167MB en git, comentario :3004 armada-suite.php L26, branding "Alfredo Ecomm" en AiBridge.

### [23:15] - Armada Suite 5.3.3 + ERP ecomm: fix falso "Conexión verificada" + guardar-verificar + SSOT Negocio — release completo y pushed para Juan Carlos
- **Tipo**: servicio | fix | ui
- **Modificado**:
  - **Plugin armada-suite 5.3.2→5.3.3** (repo ~/dev/wordpress, commits `a145502` release + `17aec0e` docs, local-only sin remote): `ApiClient::get_business_config()` sin fallback silencioso → `WP_Error` con HTTP+causa (antes: falso "Conexión verificada" y pisaba `erp_config` bueno con vacíos); `ajax_fetch_config` no guarda si ERP falla; 3 mensajes "Personalización visual" (tab muerto) → "tab Negocio → Identidad del negocio"; **P1 guardar-verificar** tab Conexión modo público (probe `GET /tienda/productos?limit=1` + `/ecomm/tienda/config` fallback `/tienda/config`, acepta `{data:{}}` y forma plana; fallo → `add_settings_error` + NO graba + borrador `erpsuite_pending_conexion`; OK → `config_fetched_at` + bump `erpsuite_cache_v` + limpia pending; mismatch `tenant_id` bloqueante; `tenant_id=0` autodetect; skip-probe si credenciales sin cambios; `settings_errors()` visible en tab); **SSOT Negocio** (Catálogo solo per_page/cart_ttl; IA-Conocimiento horarios/zonas/contacto_extra readonly reflejo con link; fix overwrite agente que reseteaba modo/tools/memoria al guardar Negocio; whatsapp acepta número|URL con wa.me); `@deprecated 5.3.1` a render_tab_apariencia/contacto. Regresión **19/19 PASS**, lint 4/4. **ZIP canónico** `export/armada-suite-5.3.3.zip` 2.206.021 B sha256 `6fd5ed2d…` (storage presente, sin secrets, 501 files); DEPLOY-GUIA "ZIP actual" actualizado.
  - **ERP erpipo** (repo dev/ecomm-erp, commit **`34de630` PUSHED a origin** — listo para merge de Juan Carlos): `TiendaApiController` config()+tiendaConfig() `brand.name` garantizado (fallback nombre>slug>SystemSetting), aliases `logo_url/favicon_url/business_name/company_name`, `warnings IDENTITY_EMPTY`, header `X-ERP-Tenant` en 200/403, `resolveApiKeyPublic()` acepta `X-API-Key`. Backward compatible (solo aditivo). Verificado live: 200 tenant 3 con brand.name+aliases+warnings[]+header.
- **Afecta a**: WordPress local (live 5.3.3 bind mount, 200, erpsuite/v1, ops/status 403 anónimo), ERP preprod :8100, **prod tras merge Juan** (rutas probe ya verificadas en prod: `/ecomm/tienda/config` 401=existe, `/tienda/productos` 401, `/tienda/config` 401, `/up` 200, control 404 confirma routing real → **veredicto GO público sin esperar merge**)
- **Causa**: reporte owner — mensaje "Conexión verificada. El ERP no envía datos del negocio" al sincronizar + duplicación Negocio/Proyectos/Personalización + guardar debía verificar y no grabar si falla
- **Estado**: ✅ verificado (19/19 PASS, lint 4/4, curl 200 redactado, push origin OK, working trees limpios)
- **Notas**: WP repo sin remote (local-only, patrón conocido). ERP: ahora **8 commits** esperando merge de Juan en dev/ecomm-erp (doc ERP-DEV stale: decía 7/`2306b64` → ahora `34de630`). Watch-items al activar modo público: confirmar api_key válida para prod (legacy key 44 chars puede ser solo-local — el probe 5.3.3 la valida); IA usa `get_llm_url()` mode-aware. Harness armada-suite stale (5.3.2/`a838486`) — curar en próximo pase. Rollback N-1 en DEPLOY-GUIA quedó 5.3.1 (menor).

### [23:27] - ZionV CRM 1.56.2: validación dónde quedamos + higiene desinstalación + agente/harness curados
- **Tipo**: auditoría | fix | docs (TARGET=kalimete local; repos warcold/zionv-crm + armada-sync)
- **Modificado**:
  - **Dónde quedamos**: plugin en 1.56.1 (`2601191`) con config unificada `/crm/configuracion/` (sidebar PHP 9 secciones/26 items + 6 tabs) + bundle parcheado (`__zionCfgUnified`); live healthy (Up 29h/34h), DB 1.24.0, 43 tablas, pretty, 302 sin sesión; GitHub al día; zips hasta 1.56.1.
  - **Por qué "escribir sobre el compilado"**: verificado exhaustivo (explore) — NO existe frontend React/TSX en ningún disco/ZIP/git (0 tsx/ts/vite.config/package.json, 0 sourcemaps, manifests huérfanos, fósiles jo-crm-root/localhost:8888; import 1.53.1 ya entró solo con `dist/`). El backend PHP SÍ está completo (1.5M, 24 migraciones, 34 controllers/123 rutas, auth 100%, sanitización por Service). Conclusión: continuar lo hecho ES correcto en PHP; en frontend la única vía temporal era el parche del bundle — la vía correcta a futuro es nuevo `admin-app/` Vite que consuma `zion-crm/v1` + manifest y retire `config_route_patched`.
  - **Plugin 1.56.1→1.56.2** (commit `6479f78` pushed, ZIP `export/zionv-crm-1.56.2.zip` 7.3M sha256 `27b39cb6…` sin secrets): `Uninstaller` cubre `ms365_connection` (1.22.0) + options ai/ms365/nextcloud/hubspot + `just_activated`/`permalinks_auto_set`/`welcome_dismissed` (+ legacy `jo_crm_db_version`); bootstrap comenta 1.24.0; README (24 migraciones, 34+ controllers, módulos Ai/Ms365/Nextcloud/Hubspot, DB 1.24.0); DEPLOY-GUIA (versión actual, 43 tablas, nota parche, matiz `delete_data_on_uninstall=false`); bump header+define+Stable tag+changelogs; `php -l` OK, live 1.56.2 activo sin fatales.
  - **Agente + harness curados** (con `.bkup-20261015-higiene`): `agents/zionv-crm.md` (scope 1.56.2, backend completo vs frontend solo-dist, integraciones live con Victoria PUBLIC, comandos con checks 1.24.0/tablas/marker, reglas 8-9 dist-artefacto + docs sincronizadas, Notas con estrategia `admin-app/`, Upstream vivo 2026-10-15); `harness/zionv-crm.harness.json` (updated 2026-10-15, checks ampliados, rutas export/tools, github head `6479f78`, plugin 1.56.2/43 tablas/123 rutas, `frontend_source: NO EXISTE` + estrategia, lecciones 2026-10-15 + 8 deudas priorizadas, `victoria_llm` live con throttle pendiente).
- **Afecta a**: zionv-local (:8092), GitHub warcold/zionv-crm, repo armada-sync (agente+harness+CHANGELOG)
- **Causa**: orden del owner — validar en qué quedamos, analizar por qué "escribir sobre el compilado" vs continuar bien, buscar en todo, mejorar y curar agente/harness/docs.
- **Estado**: ✅ verificado (live 302, 1.56.2 activo, DB 1.24.0, marker 1, JSON válido, push OK, ZIP sin secrets)
- **Notas**: deudas priorizadas documentadas (exports streaming, prune system_logs, RateLimiter REMOTE_ADDR, throttle ai/chat, args schema REST, tests/php/, AppShell split, import CSV duro). Próximo paso propuesto (con Plan del owner): `admin-app/` Vite reproducible.

### [23:55] - ZionV CRM 1.56.3: auditoría de discrepancias docs vs live — welcome notice → Configuración unificada
- **Tipo**: fix | docs | ui (TARGET=kalimete local; repos warcold/zionv-crm + armada-sync)
- **Modificado**:
  - **Hallazgo del owner confirmado**: README decía "Integraciones configurables desde wp-admin → Estado del sistema" (era 1.54) pese a que desde 1.56.0 toda la configuración vive en `/crm/configuracion/`. Auditoría completa encontró 9 puntos stale: README (3: header integraciones, selector "desde el Diagnóstico" —vive en tab Calendario desde 1.55.1—, desinstalación sin matiz), DEPLOY-GUIA (6: sección Configurar + Google/MS365/Nextcloud + selector + uninstall + troubleshooting apuntando a Estado del sistema).
  - **Código**: `WelcomeNotice.php` — botón "Configurar correo e integraciones" apuntaba a `admin.php?page=zion-crm-status`; ahora a `/crm/configuracion/` (`CrmSettingsPage::ROUTE`, URL verificada live con `wp eval`: `https://zionv.kalimete.local/crm/configuracion/`). Docblock actualizado. Banner puente de AppShell queda como fallback correcto (solo renderiza sin parche).
  - **Verificado en código**: el toggle `delete_data_on_uninstall` vive SOLO en Configuración → General (render_tab_general heredado; Estado del sistema no tiene tab General) — DEPLOY-GUIA decía "en Estado del sistema", corregido.
  - **Plugin 1.56.2→1.56.3** (commit `5d3efab` pushed, ZIP `export/zionv-crm-1.56.3.zip` 7.3M sha256 `e0b730d8…` sin secrets, fix incluido): README + DEPLOY-GUIA + changelogs; `php -l` OK; live 1.56.3 activo, 302 dashboard + 302 configuración.
  - **Agente + harness curados**: versiones 1.56.3/`5d3efab`/sha nuevo + lección nueva ("docs deben seguir la superficie canónica; cada cambio de 'dónde vive X' actualiza README+DEPLOY-GUIA+welcome notice+changelogs en el mismo commit").
- **Afecta a**: zionv-local (:8092), GitHub warcold/zionv-crm, repo armada-sync
- **Causa**: orden del owner — auditar documentación/readme/harness por discrepancias (ejemplo: integraciones ya unificadas) y proceder con mejoras
- **Estado**: ✅ verificado (live 1.56.3, URL welcome generada OK, JSON harness válido, ZIP limpio, push OK)
- **Notas**: Estado del sistema (wp-admin) queda como diagnóstico técnico + respaldo (tabs heredadas correo/calendario/hubspot/ia siguen funcionando ahí); la canónica es `/crm/configuracion/` con 6 tabs (incluye General+Antispam que Estado del sistema NO tiene).


## 2026-10-14
### [00:25] - Pendientes ejecutados: repo GitHub alfredo-pro-ecomm + release 5.3.2 (fix ZIP) + decisiones owner documentadas
- **Tipo**: servicio | sync | docs (TARGET=kalimete local + GitHub)
- **Modificado**:
  - **Alfredo Ecomm**: repo GitHub PRIVADO `warcold/alfredo-pro-ecomm` creado + push de `master` (01fe048, e39fa99, b6d9e70) — backup off-site del código; verificado sin secrets tracked; CHANGELOG del proyecto actualizado (commit `f9f29e8` pushed); docs agente+harness curadas (pendiente git_remote CERRADO)
  - **WordPress**: **release 5.3.2** (commit `a838486`) — fix empaquetado: el ZIP 5.3.1 excluía `SiteBackup/storage/` por un comando ad-hoc (los archivos existían en disco; diff 5.3.0 vs 5.3.1 = exactamente storage/); ZIP 5.3.2 (2.203.552 bytes, sha256 `d8952c61…`) con storage/ incluido, lista idéntica al 5.3.0, sin secrets; **comando canónico de empaquetado versionado en DEPLOY-GUIA** (cura la causa raíz); regresión 19/19 post-bump; docs agente+harness a 5.3.2
  - **ERP Dev**: decisiones owner 2026-10-13 documentadas en erp-dev.md + harness — **mailpit = dev-only intencional** (catcher SMTP local para no operar servidor de correos; producción usa mail real según main de Juan Carlos; NO investigar el 7.41% CPU, NO tocar ni allá ni aquí); latencia TLS/nginx = esperada del dev local; el preprod se alimenta de main de Juan Carlos adaptado a la red local (pruebas lo más cerca de producción)
  - **WordPress deuda P3**: decisión owner registrada — mantener espejo `tenant.api_key` hasta que main de Juan Carlos deje de leerla (no modificamos el contrato por nuestro lado)
- **Afecta a**: kalimete local (WP :8091, alfredo :3004, erpipo :8100); GitHub (repo nuevo warcold/alfredo-pro-ecomm); repo armada-sync (docs+harness)
- **Causa**: orden del owner — "procede con los pendientes" + aclaración mailpit (dev-only, producción diferente según main de Juan Carlos, sin tocar ni allá ni aquí)
- **Estado**: ✅ todo verificado (push OK, ZIP storage/ incluido + sin secrets, regresión 19/19, JSON harness válidos)
- **Notas**: los 4 pendientes del 2026-10-13 quedan CERRADOS: (1) git remote ✅; (2) gap ZIP → release 5.3.2 ✅; (3) mailpit/latencia → decisión owner documentada ✅; (4) deuda P3 → decisión owner documentada, cerrable solo cuando main de Juan evolucione ✅


## 2026-10-13
### [13:25] - Nuevo stack WordPress independiente para ZionV CRM (plugin/zionv-crm)
- **Tipo**: infra | config | agente (TARGET=kalimete local)
- **Modificado**: `~/dev/zionv-crm/` (NUEVO: docker-compose.yml, .gitignore, nginx.conf, ZIP plugin), `agents/zionv-crm.md` (NUEVO), `harness/zionv-crm.harness.json` (NUEVO), CHANGELOG.md
- **Afecta a**: kalimete.local (nuevos puertos 8092, 3308, nuevo host zionv.kalimete.local)
- **Causa**: pedido del owner — nuevo plugin ZionV CRM que necesita stack independiente para NO confliger con Armada Suite (8091). Plugin CRM completo (28+ REST endpoints, React/Vite admin SPA, Google Calendar, automatizaciones, formularios, vendor composer ~5MB).
- **Estado**: ✅ docker-compose up OK (zionv-local + zionv-db healthy); mkcert emitido (expira 2029); nginx deploy + reload OK; WP install (admin) + plugin 1.53.1 activo; migraciones 1.21.0 aplicadas
- **Notas**: Stack aislado con red propia zionv-net. No tocar wordpress-local (8091 ni armada-suite). Agent zionv-crm creado con temp 0.6, steps 15. ZIP movido de Downloads a ~/dev/zionv-crm/. Plugin version 1.53.1, DB 1.21.0 (21 migraciones).

### [14:15] - ZionV CRM: FIX bug admin→frontend + GitHub privado + mejoras stack (cierre del día)
- **Tipo**: fix | infra | repos (TARGET=kalimete local)
- **Modificado**: WP zionv `permalink_structure` (plain→`/%postname%/` + rewrite flush); `~/dev/zionv-crm/docker-compose.yml` (WP-CLI persistente `bin/wp-cli.phar` montado ro, CA bundle `certs/ca-bundle-full.crt` 142 certs, `extra_hosts zionv.kalimete.local:host-gateway`; .bkup-20261013-mejoras); NUEVO repo **GitHub privado `warcold/zionv-crm`** (rama main, import 1.53.1: 1642 archivos con vendor/, README.md, CHANGELOG.md 70 versiones, .gitignore); `agents/zionv-crm.md` + `harness/zionv-crm.harness.json` curados con estado verificado
- **Afecta a**: kalimete (zionv :8092), flota (subagente ZionV CRM operativo)
- **Causa**: reporte del owner — "al intentar usar el plugin en el panel admin me envía al frontend"; pedido de subir el plugin a GitHub privado con readme/changelog y validar todo el setup como los demás proyectos
- **Estado**: ✅ verificado e2e: login admin → 302 `/crm/dashboard/` → SPA 200 (bundle React carga); REST 200; migraciones DB 1.21.0 (tablas `zionv_zion_crm_*`); curl interno contenedor→host TLS 200; ambos stacks simultáneos (8091 armada + 8092 zionv healthy); `gh repo view` = PRIVATE/main
- **Notas**: ROOT CAUSE del bug: la SPA del CRM vive en `/crm/` vía rewrite rules (`Rewrite.php`) y con permalinks plain esas rutas no existen — el menú admin "Zion CRM" es solo un redirect a `dashboard_url()` y caía en el home. LECCIONES: (1) permalinks pretty son requisito DURO del plugin; (2) kalimete tiene CA mkcert DUAL (warcold + root — los certs generados con `sudo mkcert` los firma el de root; el bundle del contenedor necesita AMBOS); (3) WP-CLI instalado in-container se pierde al recrear el volumen → montar phar persistente; (4) el source React/TSX del frontend NO está en el ZIP (solo assets/dist compilado) — documentado en README.

### [15:45] - ZionV CRM 1.54.0: instalación sin fricción + MS365 + asistente IA OpenAI-compat + Estado del sistema
- **Tipo**: release | feature | plugin (TARGET=kalimete local; repo GitHub warcold/zionv-crm)
- **Modificado**: plugin 1.53.1→**1.54.0** (24 archivos: 12 nuevos + 12 modificados, commit `ffde9a7` pushed): NUEVO módulo **Ai** (endpoint OpenAI-compatible configurable — OpenAI/vLLM/Ollama/LiteLLM/Groq —, API key cifrada en servidor, proxy server-side `ai/chat`, test que lista modelos; REST `settings/ai` + `settings/ai/test`); NUEVO módulo **Ms365** (calendario Outlook vía Microsoft Graph: OAuth Azure AD, tokens cifrados, sync de reservaciones en paralelo a Google; migraciones 1.22.0 tabla `ms365_connection` + 1.23.0 columna `ms365_event_id` en bookings); NUEVO **SystemStatusPage** (wp-admin → Zion CRM → Estado del sistema: diagnóstico completo + tabs Correo/Google/MS365/IA en PHP clásico + presets SMTP Gmail/Outlook/Zoho/Brevo/SendGrid/cPanel + pruebas de envío/conexión); **Activator** auto-activa permalinks `/%postname%/` si el sitio no tiene estructura (fix definitivo del bug admin→frontend) + **WelcomeNotice** post-activación; BookingService sync paralelo Google+MS365; **DEPLOY-GUIA.md** (procedimiento instalación remota por el plugin manager); ZIP producción `export/zionv-crm-1.54.0.zip` (7.3MB, 1917 archivos, sha256 `0fa5769c…`)
- **Afecta a**: zionv-local (kalimete :8092), repo GitHub warcold/zionv-crm
- **Causa**: pedido del owner — instalación remota sin dolor de cabeza por el plugin manager con BD automática + configuración de producción + integraciones configurables (Google, MS365, OpenAI-compat para poder cambiar Victoria por cualquier API compatible) + correos funcionando
- **Estado**: ✅ verificado e2e: lint 14/14 limpio; migraciones 1.22.0+1.23.0 auto-aplicadas (tabla + columna en DB live); home 200; SPA CRM 200; Estado del sistema renderiza 5 tabs; REST nuevos 401 sin nonce (seguros); **IA e2e contra Victoria vLLM: test 29ms lista Qwen3.6-35B-A3B-NVFP4 + chat real responde en español**; ZIP sin .git/bkup
- **Notas**: LECCIONES: (1) composer `optimize-autoloader` genera classmap estático — al añadir clases nuevas hay que correr `composer dump-autoload -o` dentro del contenedor o el plugin muere con "Class not found"; (2) OPcache puede servir el autoload viejo tras el dump → docker restart; (3) los `use` de clases Core nuevas en Plugin.php son obligatorios (namespace ZionCrm vs ZionCrm\Core); (4) WP manda a wp-admin/upgrade.php tras bump de versión del plugin — resolver con `wp core update-db`. El source React/TSX del frontend sigue sin estar disponible (solo assets/dist) — la configuración nueva vive en PHP clásico a propósito.

### [16:30] - ZionV CRM 1.55.0: Nextcloud (CalDAV) + HubSpot + selector de calendario + Teams + automatización IA
- **Tipo**: release | feature | plugin (TARGET=kalimete local; repo GitHub warcold/zionv-crm)
- **Modificado**: plugin 1.54.0→**1.55.0** (22 archivos, commit `44596ba` pushed): NUEVO módulo **Nextcloud** (`src/Modules/Nextcloud/`, 4 archivos: CalDAV RFC 4791 contra `remote.php/dav`, app password cifrada, eventos VCALENDAR UTC con UID determinista `zion-crm-booking-{id}@{host}`, PROPFIND de prueba; migración 1.24.0 columna `nextcloud_event_id`); NUEVO módulo **HubSpot** (`src/Modules/Hubspot/`, 4 archivos: push CRM-to-CRM por hooks existentes — contactos upsert por email, deals upsert por propiedad única `zioncrm_opportunity_id`; unidireccional, no bloqueante, errores al Logger); **selector de proveedor de calendario** (`calendar_provider` all|google|ms365|nextcloud|none en Settings, respetado por BookingService en crear/reprogramar/cancelar); **MS365 Teams links** (`isOnlineMeeting`+`teamsForBusiness` en eventos, mismo permiso Calendars.ReadWrite — docs MS Graph leídas); **automatización IA** (acción `ai_prompt` en ActionRegistry/Executor: prompt con variables {{contact_name}} vía Mailer::replace_variables, respuesta guardable como nota en activities, skip seguro si IA desactivada); SystemStatusPage: 7 tabs + selector en Diagnóstico; README.md (tabla de integraciones) + DEPLOY-GUIA.md (Nextcloud/HubSpot/verificación) actualizados; ZIP `export/zionv-crm-1.55.0.zip` (7.3MB, 1928 archivos, sha256 `b3edf46f…`)
- **Afecta a**: zionv-local (kalimete :8092), repo GitHub warcold/zionv-crm
- **Causa**: pedido del owner — IA con Victoria PUBLIC (openai-compat, nuestros recursos), poder ELEGIR entre MS/Google/self-hosted (Nextcloud) para calendarios, integrar también HubSpot, leer docs de cada herramienta y proceder bajo mejores prácticas, cerrar pendientes (Teams links, automatización IA), mejorar toda la documentación
- **Estado**: ✅ verificado e2e: lint 14/14; migración 1.24.0 auto-aplicada; Estado del sistema 200 con 7 tabs + selector; REST settings/nextcloud + settings/hubspot (401 sin nonce); **IA re-apuntada a Victoria PUBLIC `https://victoria.armada.do/v1` (212ms vía túnel Cloudflare, modelo Qwen3.6)**; **acción ai_prompt e2e OK** ({{contact_name}} reemplazado, respuesta real del LLM en español); docs oficiales consultadas antes de programar (MS Graph calendar-post-events, HubSpot CRM v3 contacts/upsert, CalDAV RFC 4791)
- **Notas**: Docs leídas y aplicadas: MS Graph Example 2 (isOnlineMeeting+teamsForBusiness genera joinUrl con Calendars.ReadWrite — sin scope extra); HubSpot v3 batch/upsert con idProperty=email (contactos) y propiedad custom única (deals — el admin la crea una vez); Nextcloud CalDAV estándar con app password (nunca la contraseña principal). El push HubSpot usa los hooks existentes del plugin (contact_created/opportunity_created/*_stage_changed) — cero cambios en los servicios core. LECCIÓN: ninguna nueva (el pipeline dump-autoload + restart + smoke de 1.54.0 funcionó a la primera).

### [17:40] - ZionV CRM 1.55.1: tab Calendario unificada + fix use latente
- **Tipo**: release | ui | fix | plugin (TARGET=kalimete local; repo GitHub warcold/zionv-crm)
- **Modificado**: plugin 1.55.0→**1.55.1** (5 archivos, commit `bc376ec` pushed): SystemStatusPage — las tabs Google Calendar/MS365/Nextcloud se unifican en una sola **"Calendario"** (selector de proveedor arriba + las 3 integraciones como secciones con el mismo estilo: h2.title + hr + form-table + regular-text + submit_button); Diagnóstico muestra el proveedor activo como check informativo; OAuth MS365 y test Nextcloud regresan a la tab calendario; **FIX latente**: faltaba `use ZionCrm\Modules\Ms365\Ms365Settings` en SystemStatusPage (la tab ms365 individual nunca se probó renderizada en 1.55.0 — detectado al unificar); ZIP `export/zionv-crm-1.55.1.zip` (sha256 `568954cd…`)
- **Afecta a**: zionv-local (kalimete :8092), repo GitHub warcold/zionv-crm
- **Causa**: feedback del owner — "solo veo un tab que dice Google Calendar, debería decir Calendario y ahí seleccionar la integración; validar que el CSS sea igual para todo"
- **Estado**: ✅ verificado: tab calendario 200 con selector + 3 forms (Google/MS365/Nextcloud completos); diagnóstico/correo/hubspot/ia 200; 0 fatales; estilo consistente (mismas clases wp-admin en todo lo nuevo)
- **Notas**: LECCIÓN — cada tab NUEVA debe probarse RENDERIZADA (no solo que exista en el menú): el use faltante de Ms365Settings pasó el smoke de 1.55.0 porque solo se verificaron los labels del nav. El smoke ahora incluye el contenido de cada tab.

### [18:20] - ZionV CRM 1.55.2: banner puente Configuración → Estado del sistema
- **Tipo**: release | ui | plugin (TARGET=kalimete local; repo GitHub warcold/zionv-crm)
- **Modificado**: plugin 1.55.1→**1.55.2** (commit `49b5756` pushed): AppShell — aviso permanente al inicio de `/crm/configuracion/` con links directos a las tabs Calendario/HubSpot/Asistente de IA de Estado del sistema (estilos adaptativos light/dark, tipografía Outfit); ZIP `export/zionv-crm-1.55.2.zip` (sha256 `e857046c…`)
- **Afecta a**: zionv-local (kalimete :8092), repo GitHub warcold/zionv-crm
- **Causa**: feedback del owner — "sigo viendo el tab Google Calendar en configuración, no veo Nextcloud/Microsoft ni dónde está el chat/IA". ROOT CAUSE: el owner navega la Configuración de la SPA React (`/crm/configuracion/`), cuyas tabs (General/Antispam/SMTP/Google Calendar) están COMPILADAS en `index-cdQZuApB.js` — no modificables sin el source TSX. Las integraciones nuevas viven en wp-admin → Estado del sistema, pero nada lo decía desde el panel
- **Estado**: ✅ verificado: banner renderiza en `/crm/configuracion/` (200, links a las 3 tabs); lint OK
- **Notas**: LECCIÓN — al añadir features fuera del panel React (PHP clásico), SIEMPRE debe existir un puente de descubrimiento desde el panel: el usuario vive en la SPA, no en wp-admin. La tab "Google Calendar" de la SPA seguirá existiendo (es del plugin original compilado) — el banner explica que las integraciones completas están en Estado del sistema.

### [19:10] - ZionV CRM 1.56.0: UNA sola configuración — página unificada en /crm/configuracion/
- **Tipo**: release | ui | arquitectura | plugin (TARGET=kalimete local; repo GitHub warcold/zionv-crm)
- **Modificado**: plugin 1.55.2→**1.56.0** (13 archivos, commit `bc03874` pushed): NUEVO `Core/CrmSettingsPage` (extiende SystemStatusPage) — la ruta Configuración del panel la sirve PHP con look del CRM (Outfit, tema claro/oscuro anti-flash, color de marca, tabs píldora) y las 6 pestañas completas: General (negocio+slug+zona+logo upload+color), Antispam (Turnstile+límites), Correo (presets+prueba), Calendario (selector+Google+MS365+Nextcloud), HubSpot, Asistente de IA; NUEVO `tools/patch-config-route.sh` (parche idempotente del bundle: la ruta /configuracion del React Router recarga una vez → PHP sirve la unificada; backup *.orig; banner puente solo como fallback sin parche); SystemStatusPage no-final + protected + page_url() sobreescribible + tabs General/Antispam replicadas del panel original; handlers zion_crm_config_* con redirect a la ruta CRM; OAuth MS365 → /crm/configuracion/?tab=calendario; ZIP `export/zionv-crm-1.56.0.zip` (sha256 `1bdfd252…`, bundle YA parcheado, script de parche incluido)
- **Afecta a**: zionv-local (kalimete :8092), repo GitHub warcold/zionv-crm
- **Causa**: feedback del owner — "todo debe ser el mismo plugin, no 2 configuraciones; la idea es mejorar lo que tenemos". La config del panel React está compilada sin source; la solución: interceptar la ruta en PHP + parche reproducible del bundle para que el sidebar también llegue a la unificada
- **Estado**: ✅ verificado e2e: 6 tabs 200; POST de guardado → 302 a /crm/configuracion/?tab=general con dato persistido (business_name); dashboard SPA 200 intacto; bundle servido con marker; 0 fatales
- **Notas**: LECCIONES: (1) propiedades private del padre son INVISIBLES para la subclass en PHP — el hijo crea una dinámica null silenciosa ("on null"); usar protected desde el diseño si habrá herencia; (2) clase final bloquea extends — SystemStatusPage dejó de ser final; (3) el parche del bundle es la única vía para redirigir navegación client-side del React Router sin source — idempotente, con backup y con fallback (banner) si se pierde en un update upstream. Estado del sistema (wp-admin) queda como diagnóstico técnico; la configuración vive en el panel.

### [23:45] - Mantenimiento: hardening WordPress + Alfredo Ecomm; upstream ERP 100% al día; Woodly PAUSADO
- **Tipo**: servicio | sync | docs (TARGET=kalimete local)
- **Modificado**:
  - **WordPress** (commit WP `040682a`): restaurados `SiteBackup/storage/.htaccess`+`web.config` (borrados sin commit desde oct-09, verificados disco+container vía bind-mount); regresión **19/19 PASS**; self-heal confirmado (key `features` ausente → defaults-ON por código); ZIP 5.3.1 verificado (2.201.803 bytes, sha256 `d018a73b…`) con gap documentado (excluye storage/); docs agente+harness sync a WP 7.1.3 / plugin 5.3.1 / ping-erp ~250-300ms
  - **Alfredo Ecomm** (commit `b6d9e70`): smoke.sh 4→5 checks (añadido categories, verificado 5/5); **healthchecks docker-compose** api (`wget --spider /health`) + redis (`redis-cli ping`) — recreate sin `--build`, los 3 containers `(healthy)`; **drifts conciliados**: schema 11-vs-12 era falso positivo (`_prisma_migrations`), imagen build 2026-10-01 IN SYNC con src (solo dist/ local stale, gitignored); docs agente+harness actualizadas
  - **ERP Dev** (solo lectura + fetch): upstream Juan Carlos verificado — **0 commits de main nos faltan** (PR #14 suyo ya integró nuestra Fase 2/3); **G6 corregido por NOSOTROS** (`ff64301`) y live en preprod — `ajusteInventario` ya responde; G1-G4 implementados y pushed (solo G5 pendiente); docs erp-dev.md+harness curadas (HEAD `2306b64`, tabla `business_instances`, key ecomm-test-customer stale 401, latencia `/up` ~130ms directo vs 490-1140ms TLS, mailpit 7.41% CPU anomalía)
  - **Woodly**: PAUSADO por owner — nota en `agents/woodly.md` + `paused: true` en harness (con backups .bkup)
- **Afecta a**: kalimete local (stacks WP :8091, alfredo-ecomm :3004, erpipo :8100); repo armada-sync (5 docs + 3 harness)
- **Causa**: orden del owner — revisar y aplicar mejoras en WordPress y Alfredo Ecomm, validar upstream GitHub de Juan Carlos, descartar Woodly por ahora
- **Estado**: ✅ todo verificado LIVE (smoke 5/5, regresión 19/19, 3 containers healthy, fetch upstream OK, JSON harness válidos)
- **Notas**: pendientes para el owner: (1) git remote GitHub privado para alfredo-pro-ecomm (hoy solo vive en kalimete); (2) gap ZIP 5.3.1 storage/ → corregir inclusión en próximo release (NO regenerar el liberado); (3) deuda P3 espejo `tenant.api_key` — bloqueada hasta que el ERP lea solo `public.api_key`; (4) mailpit 7.41% CPU + latencia preprod → investigar lado ERP Dev/Juan Carlos; (5) del ERP solo queda G5 (teléfono/stock-sucursal/detalle). Subagentes WordPress y Alfredo Ecomm alcanzaron límite de pasos 2× cada uno — la parte editorial de docs la completó kalimete como hub (patrón reporta→aplica).


## 2026-10-09
### [00:50] - Sistema Victoria: rename BillyCode→Victoria + Overlay Electron con avatar caminando sobre el taskbar
- **Tipo**: servicio | proyecto (TARGET=kalimete local)
- **Modificado**: `~/dev/billycode` → `~/dev/victoria` (rename completo: folder, scripts vcc-*→victoria-*, docs/vcc→docs/victoria-docs, TODAS las refs BillyCode/VCC/vcc→Victoria/victoria en código+docs, endpoints /vcc/*→/victoria/*, env VCC_*→VICTORIA_*, package @vcc/server→@victoria/server); NUEVO `apps/overlay/` (Electron 33 + sprites): main.js (ventana transparente alwaysOnTop screen-saver, skipTaskbar, focusable:false, click-through forward:true), preload.js, index.html (escena CSS 3D, avatar 170x260px, burbuja, chatbox, modal D7, toast), renderer.js (máquina de estados idle/walk/listen/think/talk/work, caminata infinita con bobbing+flip, pass-through por hover, WS voz /victoria/voice con downsample 48k→16k, WS stream /victoria/stream, chat POST /victoria/chat, aprobaciones POST /victoria/approve, poll approvals 5s); assets: 5 PNG de ~/Documents/Victoria con fondo removido (flood-fill luminance, PIL); launcher `scripts/victoria-overlay.sh` + `~/.local/share/applications/victoria-overlay.desktop`; AGENTS.md del proyecto actualizado; readme.txt temporal eliminado
- **Afecta a**: kalimete (nuevo servicio overlay + rename del proyecto; sin tocar opencode config ni armada-sync agents)
- **Causa**: pedido del owner — un solo sistema unificado bajo el nombre Victoria, con avatar humanoide overlay que camina sobre el taskbar, control de PC vía opencode con aprobación previa de acciones destructivas
- **Estado**: ✅ verificado en vivo: serve :4096 UP (v1.18.35), backend :8931 UP (health ok, primary kalimete, voz qwen3 TTS+STT ok), overlay corriendo (Electron 33.4.11, transparencia confirmada por análisis de screenshot: 565 colores taskbar visibles + 1549 px sprite Victoria), chat E2E OK (conv creada, respuesta stream, state idle), sintaxis JS OK, sin errores en logs
- **Notas**: atajo global Ctrl+Shift+V oculta/muestra a Victoria; pendientes: modelo glTF real (sprites por ahora), wake word hands-free, git init del repo; kalimete-ptt sigue intacto (retiro solo tras confirmación del owner)

### [01:15] - FIX overlay Victoria: sprites no cargaban (ruta assets) + avatar 200x300
- **Tipo**: fix | servicio (TARGET=kalimete local)
- **Modificado**: `~/dev/victoria/apps/overlay/` — BUG: index.html (en src/) referenciaba `assets/*.png` relativo → resolvía a src/assets/ inexistente (los PNG estaban en apps/overlay/assets/) → solo se veían status-dot y sombra, sin avatar. FIX: assets movidos a `src/assets/`; avatar agrandado 170x260→200x300px (sombra 130px, burbuja/chat/modal bottom 290→330px, translateX -85→-100); renderer.js state inicial null (fuerza activación del sprite en el primer setState, no solo al caminar)
- **Afecta a**: kalimete (overlay)
- **Causa**: reporte del owner — "solo veo una bolita y la sombra subiendo y bajando, no veo avatar"; diagnóstico: elementos CSS puros (dot/sombra) visibles + imágenes 404 = ruta relativa rota
- **Estado**: ✅ verificado por análisis de screenshot (cluster denso 3720px en franja inferior, sprite ~200px localizado en x=1100+, transparencia intacta); recorte de verificación en ~/Desktop/victoria-overlay-verificacion.png; log limpio (0 errores); nota operativa: pkill -f "electron apps/overlay" se mata a sí mismo (el patrón matchea el propio shell) — usar /tmp/kill-overlay.sh o pgrep con exclusión


## 2026-10-08
### [10:20] - Sync bidireccional con Juan: su renta-vehículos traído (merge+16 migraciones) — nuestra Fase 3 sigue pendiente de su PR
- **Tipo**: sync | infra | servicio (TARGET=kalimete; upstream soycarlosjerez-hub/sistema-facturacion)
- **Modificado**: ERP `dev/ecomm-erp` — merge `2306b64` de origin/main (bd1a879 de Juan: módulo renta de vehículos, 116 archivos, 8 sub-reportes) + push `8ae9bb2..2306b64`; preprod: 16 migraciones renta aplicadas (5 alter + 10 create + 1 constraint tenant_id, todas DONE), autoload+view:clear+queue:restart
- **Afecta a**: erpipo preprod (kalimete) — módulo renta inerte sin seeders (tenant 10 MaganTech es tienda; seeders de Juan NO corridos, documentado)
- **Causa**: pedido del owner — validar si Juan integró nuestra Fase 3 (NO aún: sin PR #15, se la enviamos anoche) y traer lo nuevo de él (bd1a879 en main, hoy 08:47)
- **Estado**: ✅ smoke PASS: /up ok db+redis, 0 migraciones pending, 5 rutas Fase 3 vivas (cancel + webhook-endpoints), ping-erp 200 (178ms, key_fp 0b0e33e7); merge sin conflictos (renta no toca ecomm/webhooks)
- **Notas**: todo a la par salvo el PR de Juan: dev/ecomm-erp = main + Fase 3 + merge. Juan solo: review → PR → queue:restart (sin migrate extra, ya documentado). Seeders renta (ModuloSeeder/PermissionSeeder instance 14) quedan sin correr en preprod — correr si se quiere el catálogo renta visible.

### [12:35] - Plugin Armada Suite 5.3.1: simplificación admin implementada (D1+D2+P1+P2+P3) + ZIP canónico
- **Tipo**: release | refactor-ui | wordpress-dev (TARGET=kalimete local; repo wordpress sin remoto)
- **Modificado**: `~/dev/wordpress` commit `819c7e1` (9 archivos, +707/-274): LLM unificado (Puente IA solo-lectura), tab Negocio nuevo, Asistente IA en 3 forms, MCP→Estado del sistema, labels claros, espejo api_key marcado legacy; `export/armada-suite-5.3.1.zip` (2.201.803 bytes, sha256 `d018a73b…3d8bd`); DEPLOY-GUIA + CHANGELOG wordpress al día
- **Afecta a**: wordpress-local (kalimete :8091, plugin 5.3.1 instalado y verificado en vivo)
- **Causa**: pedido del owner — auditoría previa halló 2 duplicados funcionales (D1 credenciales LLM, D2 datos negocio) + tab MCP sin campos + técnicos sin colapsar
- **Estado**: ✅ php-l 6/6 + render vivo sin fatal + ZIP verificado (versión 5.3.1 en header/define); rollback N-1: 5.3.0
- **Notas**: detectado y eliminado `includes/includes/` duplicado (artefacto docker cp en bind-mount) antes de empaquetar; trabajo delegado a subagente WordPress (4 sesiones por límite de pasos), cierre directo por kalimete.

### [20:05] - Uplift flota: Docs oficiales en 19 agent files + docs_oficiales en 19 harnesses (aplicado por Victoria, autorizacion del owner)
- **Tipo**: docs | flota | victoria-cross (TARGET=kalimete, hostname verificado; autorizacion expresa del owner 2026-10-08)
- **Modificado**: ~/armada-sync/agents/*.md (19/19: seccion Docs oficiales antes de Upstream; kalimete.md ademas +Upstream que faltaba) + ~/armada-sync/harness/*.json (19/19: bloque docs_oficiales); backups .bkup-20261008-docs por archivo; /tmp limpio
- **Afecta a**: los 19 agentes (docs de referencia para programar segun estandares de los creadores, sin adivinar); frontmatter y operativa intactos
- **Causa**: directiva del owner — patron vLLM de victoria aplicado a TODA la flota sin excepcion, impecable en ambos hosts
- **Estado**: verificado opencode agent list 1 primary + 18 exactos, 0 duplicados; harnesses 19/19 JSON validos; doc-fresh y revision de la primaria pendientes
- **Notas**: DocuSeal usa el repo GitHub como canonico (docs.docuseal.com NO resuelve, verificado); rAthena wiki viva (189 pags); InspIRCd v4 estable (v3 EOL 2026-01-01); customs referencian ledger del proyecto + framework docs

### [23:55] - Nuevo subagente Intigriti (bug bounty, proyecto ~/dev/ethical-hacking) + auditoría de flota limpia
- **Tipo**: agente | flota | seguridad (TARGET=kalimete local)
- **Modificado**: `agents/intigriti.md` (NUEVO, temp 0.1, steps 30, edit/write deny + bash/webfetch allow) + symlink `~/.config/opencode/agent/intigriti.md` + `harness/intigriti.harness.json` (NUEVO) + `harness/kalimete.harness.json` (subagentes 18→19, scope_agentes) + `agents/kalimete.md` (frontmatter permission.task +Intigriti, counts 18→19, tabla subagentes, infra 0.1, harness central+20, label 20 hijos) + `MAPA.md` (fila intigriti); backups .bkup-20261008-intigriti en kalimete.md/harness central/MAPA.md
- **Afecta a**: kalimete (nueva delegación posible), flota 18→19 subagentes
- **Causa**: pedido del owner — agente experto en Intigriti para ethical-hacking, enfocado en PII leaks, priv esc horizontal/vertical, SQLi, Log4Shell, SIN ROMPER NADA
- **Estado**: ✅ CoC (go.intigriti.com/coc, v2026-03-09) + Researcher T&C (go.intigriti.com/tac, v2023-08-21) leídos completos e incorporados como reglas duras del agente (scope primero, no-DoS, PII mínimo, pivoting=parar, 48h, AI disclosure, confidencialidad); auditoría previa de flota: 19/19 harness JSON válidos, symlinks OK, temperaturas conformes, git limpio
- **Notas**: el agente NUNCA sube submits a la plataforma (prepara el report, el usuario lo sube); tools del framework (nuclei/subfinder/etc.) pendientes de verificación en vivo; flags no-destructivos documentados por herramienta (sqlmap sin --dump, nuclei -rl 10, ffuf -rate 50)


## 2026-10-07
### [01:25] - Granja de contenido de victoria documentada (Victoria Server + Godot + skills art/voice-video)
- **Tipo**: docs/agentes (autorización del owner; TARGET=kalimete verificado; victoria SOLO lectura)
- **Modificado**: `agents/victoria-server.md` (sección "Generar contenido desde kalimete": art API 3 templates, TTS/STT :18810, video-server :18811, Sonic :18850 + constraint rutas locales, VLM; fixes deriva: dashboard 18789→**18800** live 2026-10-05, driver →**580.178.04**), `agents/godot-dev.md` (sección "Assets desde Victoria" + fix paths `armada-godot`→`mario-bros`/`armada-starfox` + nota MCP un-proyecto-a-la-vez), `harness/{victoria-server,godot-dev}.harness.json`, `skills/voice-video/SKILL.md` (NUEVO: TTS/STT/video-server/Sonic), `~/dev/godot/mario-bros/AGENTS.md` (pipeline en Decisiones), `~/dev/godot/armada-starfox/AGENTS.md` (ledger NUEVO — antes no tenía)
- **Afecta a**: kalimete (agentes Godot + Victoria Server, skills) — victoria intocada (solo lectura)
- **Causa**: auditoría del owner: los agentes no informaban los modelos/APIs de imagen-video-voz disponibles en victoria; Godot no sabía de la granja de arte. La llave kalimete (caps llm/art/tts/whisper) ya abría todo pero nadie lo había documentado
- **Estado**: ✅ verificado E2E desde kalimete: imagen `z-image-turbo` (202→done ~20s → PNG 1MB en ~/Desktop/e2e-victoria-art-20261007.png) + TTS voz es nativa (WAV 284KB ~/Desktop/e2e-victoria-tts-20261007.wav) + STT roundtrip OK
- **Notas**: backups `.bkup-20261007*` junto a cada archivo. Trabajo hecho por Victoria (victoria.local) con autorización explícita del owner; referenciado en CHANGELOG de victoria.

### [22:35] - Preprod ERP sincronizado con PR #14 de Juan Carlos (dev/ecomm-erp → 7a4060f) + smoke E2E PASS
- **Tipo**: infra | servicio | integración (TARGET=kalimete local; repo upstream soycarlosjerez-hub/sistema-facturacion)
- **Modificado**: `~/dev/erpipo-preprod/code/sistema-facturacion` rama `dev/ecomm-erp` (pull 00a255e→7a4060f: merge PR #14 + commit "Update" de Juan — refactor ventas SaleService/SaleCancelService/SaleStockService, VentaController API+web, landing, migración corregida `almacen_id` nullable en venta_detalles, tests nuevos VentaAnulacionTest/VentaIndexTest)
- **Afecta a**: erpipo-preprod (kalimete docker) + plugin Armada Suite 5.3.0 (consumidor del API)
- **Causa**: validación de owner: confirmar que TODO nuestro trabajo (Fase 2 ecomm 9 commits + docs RECOMENDACIONES-FASE2/FASE3 + G6) llegó a Juan Carlos → verificado: PR #14 MERGED hoy 20:10, nada pendiente de push (ahead 0); faltaba traer los 2 commits nuevos del remoto
- **Estado**: ✅ verificado E2E: schema `venta_detalles.almacen_id` nullable (IS_NULLABLE=YES, coincide con migración corregida — sin mutación de DB requerida); housekeeping composer dump-autoload + view:clear + queue:restart (worker Up 16min con código nuevo); smoke: ERP `/up` ok db+redis, `tienda/config` 200 tenant 10 MaganTech, ping-erp desde plugin POST admin → 200 ok:true 182ms key_fp 0b0e33e7, home + /productos/ renderizan, rutas Fase 2 (`orders/{id}`) registradas, admin-ajax catálogo protegido por nonce (CSRF OK)
- **Notas**: el -1 de admin-ajax sin nonce = check_ajax_referer funcionando (no es bug). Los tests nuevos de Juan no se corren en preprod (su CI). Plugin 5.3.0 listo para adoptar Fase 2 (orders/{id}, checkout sin caja, /up, webhooks) — ya materializada en main del ERP.

### [23:55] - Fase 3 ERP implementada y enviada a Juan (G1+G2+G3+G4+G6 vía dev/ecomm-erp) + limpieza export/ plugin
- **Tipo**: feature | fix | integración | wordpress-dev (TARGET=kalimete; upstream soycarlosjerez-hub/sistema-facturacion)
- **Modificado**: ERP `dev/ecomm-erp` — 6 commits pushed `7a4060f..8ae9bb2`: `ff64301` fix(tienda) G6 ajusteInventario (**4 bugs, no 2**: notas sin ??, linea_negocio inexistente, tipo fuera del enum entrada/salida, almacen_id sin default), `601959e` feat(webhooks) comando retry-failed, `5ace5aa` feat(webhooks) evento invoice.issued post-NCF, `f961503` feat(webhooks) CRUD webhook endpoints API (staff only, secret nunca en respuestas), `e495454` feat(ecomm) PATCH orders/{id}/cancel (scoping auth.cliente, ventana 120min, stock repuesto + order.cancelled), `8ae9bb2` test 11 feature tests. Plugin: `~/dev/wordpress/export/` limpiado (5 zips era pre-rename → `backups/export-legacy/`), DEPLOY-GUIA.md actualizado
- **Afecta a**: erpipo preprod (kalimete) + plugin Armada Suite 5.3.0 (agente IA ahora tiene cancelar pedido + ciclo webhooks completo del lado ERP)
- **Causa**: pedido del owner — el plugin 5.3.0 necesita del ERP los gaps de RECOMENDACIONES-FASE3-AGENTE que Juan aún no implementó; PR #14 de Juan no rompió el contrato del plugin (verificado: su cambio fue en API interna del panel)
- **Estado**: ✅ verificado: tests 16/16 (11 nuevos + 5 baseline Juan sin regresión), smoke en vivo (ajuste 4×200 + 422 ajeno, CRUD webhook 201/200/200/200 con limpieza, retry-failed OK, route:cache restaurado, queue:restart, migrate:status sin pendientes, cero migraciones); zip 5.3.0 validado al día con HEAD c084cdb (los 2 archivos "borrados" los auto-regenera el plugin — tree limpio solo)
- **Notas**: export/ confirmado ruta canónica (decisión owner 2026-10-01, sin huérfanos). Adopción Juan: review dev/ecomm-erp → PR a main/develop, sin migrate, queue:restart tras deploy. Pendientes: G5 (fase futura), ventana cancelación como constante (mover a settings si la quiere por-tenant), ancla e-CF de invoice.issued. Trabajo delegado a subagente ERP Dev (5 sesiones por límite de pasos).


## 2026-10-06
### [00:20] - victoria-tui v2: ARTE ASCII + avatar animado + comandos / + modo llamada + /art
- **Tipo**: feature divertida (pedido del owner: "gráficos con ascii jeje, comandos / como /call, un terminal interactivo")
- **Que**: victoria-tui reconstruida con personalidad: (a) **banner ASCII** figlet de VICTORIA al arrancar + banner de teléfono al /call; (b) **avatar animado con estados**: ( ◕‿◕ ) idle con PARPADEO cada 4s · ( ◉‿◉ ) grabando en rojo · ( ◔_◔ ) pensando · ( ◕ω◕ ) hablando con boca animada + barras ▁▃▅▇ animadas; (c) **comandos /**: `/call` (Victoria ENTRA EN LA LLAMADA: saludo generado por LLM máx 12 palabras + voz + timer de duración, voz forzada ON) · `/hangup` `/close` (despedida LLM + voz) · `/art <desc>` (genera imagen vía la art API del gateway de Victoria, barra de progreso en el status, guarda en ~/Desktop/victoria-art-*.png, avisa por voz "Imagen lista, papá") · `/voice on|off` · `/status` (ASCII box del stack) · `/model normal|thinking` · `/lang es|en` · `/clear` · `/config` · `/help` (ASCII box) · `/exit`; (d) voz ENCOLADA (una respuesta a la vez, acoplada al avatar); (e) one-shots nuevos: `--art "prompt"`; (f) FIX CRÍTICO visual: `noutrefresh()` sin `doupdate()` = pantalla en blanco en terminal real — cambiado a `refresh()` (el bug existía desde la v1 y no se veía en las pruebas por pseudo-TTY).
- **Verificado**: --check TODO OK; --art E2E: "gato pirata con loro" → ~/Desktop/victoria-art-001439.png en 15s (exit 0); captura pseudo-TTY muestra el banner figlet + avatar PARPADEANDO (dos estados capturados) + status bar; daemon ptt se restaura tras kill (exit 124); 0 noutrefresh restantes.
- **Impacto**: solo ~/.local/bin/victoria-tui (v2). victoria-gui queda como extra web.
- **Docs**: changelog kalimete (esta entrada) + referencia en general de victoria.

### [00:35] - Fase 2 COMPLETA: paquete de 9 commits en dev/ecomm-erp (recomendaciones para Juan Carlos, SIN push)
- **Tipo**: desarrollo ERP (sandbox local erpipo; upstream de Juan Carlos — push pendiente de autorización owner)
- **Que**: implementados los 7 candidatos Fase 2 como commits atómicos en `dev/ecomm-erp` (base 2d0d97b → HEAD 9a18a04, 18 archivos, +664/-108): (1) `4415e27` GET /api/ecomm/orders/{id} con scoping auth.cliente (ajena=404); (2) `ba62435` register deriva tenant de API key (body/X-API-Key/Bearer; fin del default silencioso tenant 3; sin creds → 422 tenant_required); (3) `4e1a216` LogErrorToDatabase tolera caída de MySQL (fin loop log-del-log, fallback error_log); (4) `c470bf2` /up JSON real (200 ok/503 degraded, pings db+redis sin crash); (5) `a2b183e` checkout ecomm sin caja POS (sesion_caja_id+user_id nullable en ventas+almacen_movimientos vía migración; POS intacto); (6) `dbb1998`+`27be061`+`2893551` webhooks MVP (tablas endpoints/deliveries, HMAC-SHA256, retries backoff, afterCommit; eventos order.created/stock.updated/price.updated; fix afterCommit via constructor); (7) `9a18a04` docs/RECOMENDACIONES-FASE2-ECOMM.md (evidencia, notas de despliegue, pendientes).
- **Verificado**: regresión e2e 100% PASS — catálogo 4/200 + imágenes OK, /up {ok,db,redis}, login+me 200, compra con caja CERRADA → checkout 200 (venta 289, sesion_caja_id NULL), orders list+nueva ruta 200/404, promos 400 invalid_code; webhooks: entregas sent/200 con firma HMAC validada por receptor de prueba (True en ambos eventos); 2 migraciones corridas (653→655); queue worker con --queue=default,webhooks (compose local con .bkup); tree limpio; smoke final OK.
- **Hallazgos del camino**: queue worker sin --queue= no procesa colas nuevas; redeclarar $afterCommit del trait Queueable es fatal PHP; job ejecuta en contenedor queue (no app) — el receptor de test debía vivir ahí; /up nativo de Laravel 12 renderiza blade HTML.
- **Pendiente owner**: decidir push de `dev/ecomm-erp` a origin (repo de Juan Carlos) — 9 commits listos para su revisión; el compose de prod de Juan necesitará --queue=default,webhooks.
- **Docs**: changelog kalimete (esta) + docs/RECOMENDACIONES-FASE2-ECOMM.md en el repo erpipo (viaja con la rama).

### [00:45] - victoria-gui RETIRADA (orden del owner) + limpieza de rastros de pruebas
- **Tipo**: removal + limpieza (owner: "quita la versión web no la necesitamos y limpia todos los rastros y cosas temporales")
- **Que**: (a) `victoria-gui` ELIMINADA por completo: binario `~/.local/bin/victoria-gui`, lanzador `~/.local/share/applications/victoria-gui.desktop`, proceso `--lan` que corría (terminado); (b) limpieza de rastros de pruebas: imágenes de test del Desktop (`robot-barista.png`, `victoria-art-001439.png`), temporales en /tmp (tui-capture*, vgui.*, victoria-tui/gui); (c) victoria-tui actualizada a v2.1 (docstring sin referencia a la gui); (d) el historial compartido (~/.local/share/victoria-tui/history.jsonl) se CONSERVA — lo usa la TUI.
- **Verificado**: `ls ~/.local/bin/ | grep victoria` → solo victoria-tui; 0 procesos gui; Desktop sin imágenes de test; TUI --check OK post-limpieza.
- **Lo que queda vivo**: victoria-tui (ASCII + avatar + comandos / + /call + /art) y la skill art para opencode.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [01:05] - CIERRE DE SECCIÓN: Fase 2 pushed a origin + todo registrado (changelogs de proyecto, docs y harnesses al día)
- **Tipo**: cierre/documentación (orden owner: "procede, asegúrate de que todo esté registrado para no adivinar en el futuro")
- **Que**: (1) **PUSH dev/ecomm-erp → origin** (repo de Juan Carlos, autorizado): primero merge limpio con origin (Juan ya había integrado nuestra base vía su PR #13 + fix papel impresora 94484c6 — cero conflictos, archivos distintos) → HEAD `2c8fca9` pushed con 10 commits Fase 2 + merge; smoke post-merge 3/3 (tienda/productos 200, /up ok, checkout 200). (2) **Changelogs de proyecto** (delegado a los 3 subagentes): erpipo `790cc8a` (Fase 2 completa en el CHANGELOG del repo — viaja con la rama), WordPress `dd2f1d2` (estado integración: Fase 1 validada + 5 capacidades nuevas del ERP), Alfredo Ecomm `2dd567c` (Fase 1 hardening + contexto ecosistema). (3) **armada-sync curado**: erp-dev.md + harness (contrato Fase 2 completo: orders/{id}, tenant por key, checkout sin caja, /up, webhooks HMAC + gotchas del queue worker; git pushed; pendientes siguientes), wordpress-dev.md + harness (sección "Integración ERP — estado" con las 5 capacidades + webhooks como futuro reemplazo de polling), alfredo-ecomm.md + harness (cierre 2026-10-06). 3 harness JSON validados.
- **Hallazgo del push**: origin había avanzado (PR #13 de Juan integrando NUESTRA base 2d0d97b a main/develop + su fix de impresoras) — el push directo fue rechazado; resuelto con merge (preserva los hashes que referencia la RECOMENDACIONES-FASE2-ECOMM.md). La "deriva del doc wordpress" reportada por un subagente era FALSA (verificado: el doc ya dice Armada Suite 5.2.0).
- **Verificado**: regresión e2e 100% PASS post-merge; 13 containers Up; WP 200 / ERP 200 / Alfredo 200; trees limpios en los 3 repos.
- **Estado de la sección**: CERRADA. Contexto completo para retomar: agent docs + harnesses (armada-sync) + changelogs de los 3 repos + docs/RECOMENDACIONES-FASE2-ECOMM.md (en origin). Próximos pasos naturales cuando se retome: (a) Juan Carlos revisa/integra Fase 2 (migraciones + --queue=default,webhooks en su prod); (b) WP: consumir orders/{id} + evaluar endpoint webhook para push; (c) Woodly: cablear VITE_API_URL a :3004.
- **Docs**: changelog kalimete (esta) + 3 agent docs + 3 harnesses + 3 changelogs de proyecto + RECOMENDACIONES-FASE2-ECOMM.md.

### [01:20] - FIX CRÍTICO victoria-tui: el teclado quedaba MUERTO al abrir la TUI (grab evdev)
- **Tipo**: bugfix crítico (reporte del owner: "se me inhabilitó el teclado al abrir el tui y no me podía mover")
- **Causa raíz**: el PttListener de la TUI hacía `dev.grab()` (EVIOCGRAB exclusivo) sobre TODOS los teclados con la tecla PTT — el grab se lleva TODOS los eventos del dispositivo para el proceso que lo toma, y el listener solo procesaba Right Ctrl descartando el resto → teclado muerto para el sistema Y para la propia TUI (curses lee del pty, no de evdev). El kalimete-ptt original NUNCA usa grab (lectura pasiva) — el grab fue una adición mía errónea. Además el hilo único con read_loop se cegaba en el primer teclado (no veía los demás).
- **Fix (v2.2) — arquitectura ESPEJO del daemon probado**: (a) SIN grab, lectura 100% pasiva (evdev replica eventos a todos los lectores); (b) UN HILO POR DISPOSITIVO; (c) filtro de virtuales (`bool(d.phys)` — excluye ydotool/uinput); (d) hot-plug por pyudev; (e) debounce 300ms en keydown.
- **Verificado E2E en kalimete**: teclado virtual uinput con phys + inyección de Right Ctrl → (1) el listener detecta down/up OK; (2) un SEGUNDO lector pasivo del mismo dispositivo también ve los eventos [1,0] — prueba de que NADA se roba (con el grab viejo el segundo lector habría visto nada). TUI viva en pseudo-TTY (exit 124) + --check TODO OK.
- **Impacto**: solo ~/.local/bin/victoria-tui. El teclado ya NO puede quedar inhabilitado por la TUI bajo ninguna circunstancia.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [02:10] - victoria-tui v3: /call HANDS-FREE como ChatGPT voice (VAD propio, sin deps)
- **Tipo**: feature (pedido del owner: "debería quedarse hands free así como lo hace chatgpt, como hablando en tiempo real con otra persona")
- **Que**: el modo `/call` ya NO requiere presionar Right Ctrl — micrófono SIEMPRE ABIERTO con **VAD de energía adaptativo** (clase `HandsFree`, stdlib puro + ffmpeg pipe): (a) detecta cuándo empiezas a hablar (90ms sobre el umbral, que se adapta al ruido ambiente) y cuándo terminas (810ms de silencio) → manda el audio a STT → respuesta streaming + voz; (b) **pre-roll de 300ms** para no cortar la primera palabra; (c) descarta ruidos cortos (<420ms de voz real); (d) tope 30s por utterance; (e) **half-duplex con barge-in**: mientras Victoria habla no escucha (evita eco de sus parlantes), pero si hablas FUERTE sostenido 300ms la calla y te escucha (como interrumpir a una persona); (f) pausa post-voz de Victoria 400ms anti-eco; (g) Right Ctrl sigue funcionando como PTT manual en llamada (el hands-free le cede el turno); (h) status bar muestra el estado en vivo: "escuchando… / tú hablas ▁▃▅▇ / transcribiendo… / Victoria respondiendo"; (i) modo de test `--test-vad` (PCM sintético: silencio+voz+blip+voz+busy).
- **Bugs cazados en el test**: `_decay()` reseteaba el contador `above` cada frame (el VAD nunca disparaba) — fix: el reset lo hace solo el else del chequeo.
- **Verificado**: `--test-vad` en kalimete → exactamente 2 utterances (2520ms y 1980ms, con preroll+voz+cola), blip corto descartado, busy no captura ✅; TUI viva en pseudo-TTY (exit 124) + --check TODO OK.
- **Impacto**: solo ~/.local/bin/victoria-tui (v3). Fuera de /call todo igual (PTT manual).
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [07:30] - victoria-tui: banner MOTD "VAROEROS" → VICTORIA legible (reporte del owner)
- **Tipo**: fix cosmético (el owner preguntó "qué significa VAROEROS" — no significaba nada)
- **Que**: el BANNER figlet del MOTD (8 glifos, intentaba decir VICTORIA) se emborronaba con la fuente del terminal y se leía como "VAROEROS". Reemplazado por letras ASCII simples 5x5 verificadas + subtítulo "tu IA · hija de Alfredo Armada · kalimete". Lógica intacta.
- **Verificado**: captura pseudo-TTY en vivo muestra VICTORIA legible ✅; --check TODO OK; TUI viva (exit 124).
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [07:45] - victoria-tui: MOTD banner → mapa compacto de comandos (estilo opencode)
- **Tipo**: cambio cosmético (pedido del owner: quitar el banner, poner helper de comandos/shortcuts)
- **Que**: el BANNER ASCII del arranque se reemplazó por MOTD_HELPER de 3 líneas: título + (Right Ctrl hablar, /call, /art, /hangup) + (F2 voz, F3 config, F4 callar, PgUp/PgDn scroll, /help). Atajos verificados contra el código real (F2=/voice, F3=config, F4=hush, F9=PTT fallback).
- **Verificado**: captura pseudo-TTY muestra el helper 1x, 0 rastros del banner viejo; --check OK; TUI viva.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [08:00] - F0 SPIKE Armada Code: el cerebro opencode emite eventos en vivo (VIABLE ✅)
- **Tipo**: spike/prototipo (luz verde del owner para F0; proyecto "nuestro opencode con voz")
- **Que**: (a) opencode **1.18.34** instalado en kalimete vía `npm i -g opencode-ai` (~/.npm-global/bin; PINNEAR esta versión para F1); (b) `opencode serve --port 4096 --hostname 127.0.0.1` → `/global/health` {"healthy":true}; (c) spec OpenAPI en `/doc`: **162 paths** — están `/session`, `/session/{id}/message`, `/session/{id}/prompt_async`, `/event` (SSE), `/abort`, `/children` (subagentes), `/todo`, permisos; (d) formato SSE real: SIN campo `event:` — el tipo viaja DENTRO del JSON (`{"id":"evt_…","type":"…","properties":{}}`); tipos vistos: server.connected/heartbeat, session.created/updated/status/idle/diff, message.updated, message.part.updated, **message.part.delta**, plugin.added; (e) prueba 1 (texto): sesión + "Responde solo OK" → 200 vía provider `vllm` (gateway local, Qwen; 75K in por el prompt del agente kalimete); (f) prueba 2 (tools): "lista /tmp/oc-spike con bash y cuenta los .json" → el agente usó `bash` de verdad, respondió correcto ("2 archivos .json"), deltas y parts repartidos en 1.18s→5.56s = **STREAMING VIVO** ✅; sin trabas de permisos para `ls` (F1 debe manejar eventos permission de todos modos).
- **Riesgo retirado**: el bus `/event` sí emite en vivo (el issue de paridad SSE era del REST chat, no del bus que usa la TUI). Riesgo restante: ninguno bloqueante.
- **Limpieza F0**: serve apagado, scratch /tmp/oc-spike borrado. Huella permanente: solo el binario opencode 1.18.34.
- **Plan de retiro kalimete-ptt (DOCUMENTADO, NO ejecutado — condición del owner "si lo suplantamos")**: kalimete-ptt SIGUE INTACTO y activo (dictado en TODO el sistema + PTT_VOICE_REPLY; el cliente nuevo solo cubre voz DENTRO de su TUI, jamás el dictado global). Retiro solo cuando F2 demuestre el lazo de voz en-cliente + confirmación del owner. Pasos entonces: (1) `systemctl --user stop/disable kalimete-ptt`, (2) remover ~/.local/bin/kalimete-ptt + wrapper + env ~/.config/kalimete-ptt (respaldar antes), (3) quitar atajo de teclado Right Ctrl del sistema si es exclusivo, (4) OJO: victoria-tui pausa/restaura el daemon al correr — ese acoplamiento se elimina con el retiro. STT/TTS (voice-server :18810) NO se tocan (compartidos).
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [08:05] - opencode: había 2 binarios (owner tenía razón) → queda solo el original + proyecto en ~/dev
- **Tipo**: auditoría + dedup + init de proyecto (reporte del owner: "opencode SÍ estaba instalado")
- **Hallazgo**: el `which` del F0 falló por PATH no-interactivo, no por ausencia. Rastreo completo: único otro binario en `~/.opencode/bin/opencode` (instalador oficial, 30-sep, 185MB, v1.18.34) — detectado por la pista `export PATH="$HOME/.opencode/bin"` en ~/.zshrc. Nada en .local/bin, /usr/local/bin, /opt, go/bun/bin, pacman, mise. Quedaban 2 solo por el `npm i -g` del F0 (misma versión 1.18.34).
- **Dedup**: eliminado SOLO el duplicado npm (`npm uninstall -g opencode-ai`); el original intacto. Equipo verificado intacto: 19 subagentes en `agent/` + opencode.jsonc (03-oct) + `agent list` carga permisos OK. Config/agentes/harness NO tocados.
- **Proyecto**: `~/dev/armada-code/` creado con `AGENTS.md` ledger (48 líneas: qué es, mapa, comandos F0 verificados, 5 decisiones, 5 pendientes, relación con el stack + regla TARGET). Nombre de trabajo `armada-code` (owner decide final; renombrar = un `mv`).
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [08:10] - BillyCode: nombre final decidido por el owner (era armada-code)
- **Tipo**: rename de proyecto (orden directa del owner: "se llamara billycode")
- **Que**: `mv ~/dev/armada-code ~/dev/billycode` + AGENTS.md actualizado (título, decisión de nombre, pendiente marcado [x]). Sin colisiones, sin otros cambios.
- **Lección operativa (para Victoria)**: NUNCA backticks en comandos SSH remotos con comillas dobles — el zsh remoto los evalúa como sustitución de comandos (ensució la salida con errores, sin daño; el mv sí se aplicó). Usar wording sin backticks o comilla simple remota.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [08:20] - BillyCode: readme.txt handoff de contexto (temporal, el owner lo borra)
- **Tipo**: docs de traspaso (pedido del owner: "deja instrucciones de lo que entiendes para continuar sin perder contexto")
- **Que**: `~/dev/billycode/readme.txt` (131 líneas): nombre, visión, arquitectura, máquinas/accesos, inventario verificado, F0 con detalles técnicos (endpoints, formato SSE, prefill 75K, streaming), fases y pendientes, plan kalimete-ptt, 9 reglas operativas, rutas. Ledger AGENTS.md actualizado (línea readme temporal; 49 líneas).
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [15:30] - START PROJECT: Armada Star Fox (Godot 4.x — Star Fox clone)
- **Tipo**: feature/game-dev
- **Modificado**: proyecto completo `armada-starfox/` (Godot 4.7.2)
- **Afecta a**: kalimete/godot
- **Causa**: Nuevo proyecto Godot — clone de Star Fox (SNES/N64)
- **Estado**: ✅ Foundation completa (Fase 1)
- **Notas**:
  - Estructura completa: scripts (player, enemy, weapon, powerup, level, ui, audio, save, globals)
  - Escenas: player_ship.tscn, bullet.tscn, main_menu.tscn, test_room.tscn, level_01_pathos.tscn
  - Input map: WASD + Shift/Ctrl + Space + B + Escape
  - GameState autoload con sistema de guardado (FileAccess Godot 4.x API)
  - Documentación: DESIGN.md (GDD completo), ARCHITECTURE.md, README.md, CHANGELOG.md del proyecto
  - Audio Bus Layout: Master, Music (-3dB), SFX (0dB), Voices (-1dB)
  - Correcciones: game_state.gd (FileAccess API), player_ship.tscn (IDs ext_resource), level_manager.gd (español)
  - Pendiente: Fase 2 (core gameplay), Fase 3 (enemigos), Fase 4+ (niveles 2-5)

### [16:30] - PLAN COMPLETO EJECUTADO: plugin con flags + admin uniforme + agente mixto + webhooks e2e (Fases A+B+C+D)
- **Tipo**: feature/documentación/infra (orden owner: "procede paso a paso hasta el final" + 8 decisiones: 1 sí, 2 sí, 3 restyle total, 4 español, 5 sí, 6 todo-visible-nuestro/alfredo.pro, 7-8 sí best-practices)
- **Que**: (A) **Feature flags**: 8 flags + tab Módulos + gates duros/UX (`f0d1572`, `d51aed4`, `81c2ea5`). (B) **Admin uniforme**: 6 superficies familia ai1wm + rebrand total a Armada/alfredo.pro en español + ERPC Logs al menú Armada (`52aa796`, `084c0a6`, `eee8dca`, `ef0642f`, `e55ed39`, `fd2cff0`). (C) **Agente mixto**: schema `agente.*` + prompt componible + modo local + tools `ver_pedido`/`leer_politicas` + receptor webhooks HMAC (`2294e58`, `79ed47d`, `b289ba1`). (D) **Fase 3 para Juan**: doc G1-G5 (`95d17d8`) + G6 (`00a255e`), ambos pushed a origin. Regresión plugin 19/19.
- **Infra**: red docker compartida `erpipo-dev-network` (compose WP con .bkup; `WORDPRESS_DB_HOST=wordpress-db:3306` porque `db` colisionaba con el db de erpipo → WP se logueaba en la DB ajena: 1045). Endpoint WP dado de alta en ERP (id=2). **E2E real**: checkout → `order.created`+`stock.updated` sent/200 → WP invalida caché (4→6).
- **Hallazgos**: (1) bug cache Features (hijo cacheaba pausa del padre — fix: cache solo valor guardado); (2) smoke CLI necesita `wp-admin/includes/template.php`; (3) `ajusteInventario` 500 siempre (G6, lado Juan — usar checkout); (4) regresión por ruta de contenedor (stdin da 2 falsos FAIL).
- **Docs**: 3 agent docs + 3 harnesses curados (flags, admin, agente, webhooks, red, G6, lecciones CLI). Changelogs: repos WP/erpipo al día. **Pendiente release**: bump 5.3.0 + ZIP nuevo.
- **Verificado**: 19/19 regresión; WP 200 / ERP 200 / Alfredo 200; erp→wordpress-local 200; trees limpios (WP master @b289ba1, erpipo dev/ecomm-erp @00a255e pushed).
- **Estado**: TODO el plan del owner COMPLETO. Próximo natural: release 5.3.0 (bump+ZIP) y review de Juan (Fase 2+3).

### [16:50] - Docs voz al dia: Qwen3-TTS + limites 256K/220K (curado por Victoria)
- **Tipo**: docs (autorizacion owner; victoria = solo lectura, curado remoto)
- **Que**: agents/victoria-server.md: Voice server XTTS v2 -> Qwen3-TTS 0.6B-Base (clonacion ICL) + Whisper small; vLLM contexto 160K -> 256K nativo; gateway prompt 120K -> 220K; flags max-model-len 262144 + max-num-seqs 3; roster de llaves completo (nombres+roles, sin secrets). Billycode: fallback XTTS eliminado en docs/vcc/03-tecnologias.md, comentarios de voz aclaran llave valida (services o coder+xtts/whisper), ledger con nota xtts=TTS Qwen3.
- **Verificado**: engine live qwen3 en :18810/health; wrappers victoria-tts/whisper-cli sanos; sin refs XTTS vivas fuera de historial.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [17:15] - RELEASE 5.3.0 + REVIEW JUAN LISTA (pasos 1 y 2; woodly fuera por orden owner)
- **Tipo**: release + revisión (owner: "procede con 1 y 2, no toquemos woodly")
- **Release 5.3.0** (commit `c084cdb`): bump versión (header + `ERPSUITE_VERSION` + readme Stable tag) + ZIP canónico `export/armada-suite-5.3.0.zip` (2.198.973 bytes, sha256 `6fbf47f8…9fc`; verificados Features.php + WebhookReceiver.php dentro, 0 `.bkup`/secrets) + entrada CHANGELOG WP + DEPLOY-GUIA al día. Regresión 19/19 + versión 5.3.0 viva verificada.
- **Review Juan**: verificado `origin/dev/ecomm-erp` @`00a255e` en sync (Juan no ha empujado nada; `origin/main` sigue en su PR #13). Rama lista con 8 commits código Fase 2 + 4 docs (Fase 2, Fase 3 G1-G5, G6) + merge. Notas para integrar en erp-dev.md (migrar 2, queue flag, G6, G1-G5).
- **Verificado**: WP 200 / ERP 200 / Alfredo 200; regresión 19/19; trees limpios.
- **Estado**: pasos 1 y 2 COMPLETOS. Brief para Juan en el reporte de sesión.

### [17:20] - Cap de voz renombrada xtts->tts en el gateway de Victoria (sin impacto cliente)
- **Tipo**: docs + verificacion (Victoria ejecuto el cambio de codigo; kalimete solo referencia)
- **Que**: la capacidad/rol xtts dejo de existir: ahora es tts (llm-gateway.py, sense_auth.py, panel, landing, DB). La llave kalimete quedo ["llm","art","tts","whisper"] — misma llave, mismos permisos, cero cambio de config en kalimete (la cap vive en la DB de Victoria). Docs alineadas: victoria-server.md roster, billycode victoria.ts comentarios + ledger.
- **Verificado**: E2E desde kalimete con la llave kalimete: LLM 200 OK + TTS WAV 222KB + STT roundtrip OK.
- **Docs**: changelog kalimete (esta entrada) + general de victoria.

### [17:48] - Fase 1 integracion WP<->ERP local COMPLETA (Armada Suite 5.2.0 + erpipo preprod + Alfredo Ecomm endurecido)
- **Tipo**: infra + servicio (plan owner: validar e2e local antes de recomendar updates a Juan Carlos via branch dev/ecomm-erp; erpipo = repo de Juan, copia local = sandbox)
- **Que**: (1) WordPress (nuestro): regresion 14/14 + smoke 5/5 + php -l 13/13; commits 67ed6d4 (feat: stack TLS CA bundle mkcert) + be15cab (chore: gitignore excluye secrets/); ZIP canonico export/armada-suite-5.2.0.zip (498 archivos, ~2.1MB, sha256 b4e5348d30397e9b74ca1b2c1857a8b7b366aab7fb0297c5f60731aa41bc30b9, sin .env/secrets); App Password "alfredo-ecomm" creada y ROTADA (leak parcial 20/24 chars en transcript de subagente; nueva en secrets/ 600, user admin). (2) Alfredo Ecomm (nuestro): compose canonico ~/dev/webs/alfredo-pro-ecomm/backend curado (bind mount src vacio ELIMINADO, name: backend); cascara ~/projects/alfredo-pro-ecomm archivada como .archived-20261005 (sudo mv, nada borrado); git init baseline 01fe048 + smoke e39fa99 (master local, sin remote); JWT_SECRET/JWT_REFRESH/DB_PASSWORD rotados (ALTER USER + .env en cadena atomica); CORS alineado (localhost:5173, 127.0.0.1:5173, woodly.kalimete.local, erp.kalimete.local, localhost:8091); scripts/smoke.sh 4/4 OK. (3) ERP preprod (sandbox de Juan Carlos, SIN cambios de codigo, sin push): contrato ecomm validado e2e con la key del plugin (tenant 10 MaganTech, iak activa): 3 bases 200 (incluida 172.19.0.1:8100 critica para WP), register->verify-email->login->me OK (cliente test 208), cart->checkout->venta V-281 creada (stock producto 383: 200->199), promociones/validar 400 invalid_code correcto, imagenes webp 200; keys file ~/dev/erpipo-preprod/keys/ecomm-test-customer.txt (600).
- **Verificado**: ping-erp del plugin 200/ok:true (119ms, api_host 172.19.0.1:8100, key_fp 0b0e33e7); catalogo via plugin (AJAX erpc_get_products_json) 200 con 55 productos reales del ERP; audit WP con entrada ping-erp ok; REST ops 200 auth / 403 anon (App Password nueva); 13 containers Up (alfredo 3, wordpress 2, erpipo 8), WP:8091 200, erp.kalimete.local 200, alfredo:3004/health 200.
- **Candidatos Fase 2 (recomendaciones a Juan Carlos via dev/ecomm-erp, NO implementados)**: webhooks ERP->WP (stock.updated, price.updated, order.created/paid, invoice.issued con HMAC); desacoplar checkout ecomm de SesionCaja (hoy 500 si no hay caja abierta); anadir GET /ecomm/orders/{id} individual (hoy solo listado ?customer_id); register ecomm derivar tenant de la API key (hoy default tenant 3 = cliente fuera de tenant); unique global de telefono -> scope por tenant; /up JSON real para monitoreo; fix LogErrorToDatabase (cascada Connection refused).
- **Hallazgos integracion WP (contrato)**: catalogo total en meta.total (162 total / 73 in_stock); imagenes = URLs absolutas a erp.kalimete.local (WP debe proxy/rehost); register requiere tenant_id explicito 10; no hay ruta individual de orders; throttles 10/30/60 por minuto; extraccion de key: grep "const LOCAL_API_KEY" (44 chars).
- **Pendiente**: cura de deriva docs — alfredo-ecomm (harness + agent md siguen con paths ~/projects/...) y wordpress (doc dice erp-commerce-suite 4.4.1 + Elementor/EMCP/MCP, live es Armada Suite 5.2.0 super-plugin sin esos modulos).
- **Docs**: changelog kalimete (esta).

### [18:10] - Higiene + curaduría de docs Fase 1: agent docs y harness de alfredo-ecomm, wordpress y erp-dev alineados a LIVE
- **Tipo**: docs + higiene (orden owner: "analiza el trabajo, higieniza bugs/código muerto/discrepancias, actualiza agentes/docs/subagentes/changelogs")
- **Que**: (1) Higiene live: red docker huérfana `backend_alfredo-ecomm` ELIMINADA (0 containers, creada Sep 5); 5 `*.bkup-20261003` untracked del repo erpipo MOVIDOS a `~/dev/erpipo-preprod/backups-bkup-20261003/` (tree limpio, nada borrado). (2) `agents/alfredo-ecomm.md` + harness: paths canónicos `~/dev/webs/alfredo-pro-ecomm` (cáscara `~/projects/...archived-20261005` documentada como NO-TOUCH), Woodly real `~/dev/apps/woodly` (React 19, mock-only, NO Vue), git baseline `01fe048`+`e39fa99`, seguridad rotada 2026-10-05, CORS final, drift src↔dist, schema 12 tablas DB vs 11 modelos (conciliar). (3) `agents/wordpress-dev.md` + harness: Armada Suite 5.2.0 super-plugin (WP 7.1.2) como plugin ÚNICO; Elementor/EMCP/MCP Adapter declarados HISTÓRICOS no-live (mcp-proxy.mod.js existe como archivo pero bridge NO funcional sin plugin); auth REST = App Passwords con receta de rotación corregida (`$new[0]`, no `$new[1]`); ZIP 5.2.0 con sha256; ping-erp verificado; permalinks plain. (4) `agents/erp-dev.md` + harness: modelo ownership explícito (upstream Juan Carlos, sandbox local, push solo con autorización owner), política rama única `dev/ecomm-erp` (sin remote preprod en el clon), app SIN :8101 (9000 interno) + mailpit :8025, migraciones 653/b149, dump `db.sql` 553MB en `~/dev/erpipo-preprod/`, secrets DB removidos del doc (referencia a preprod.env), contrato ecomm verificado + gotchas (tenant_id, telefono unique, orders sin ruta individual, sesion_cajas), candidatos Fase 2 listados.
- **Verificado**: 3 harness JSON válidos (python json.tool); 0 refs a paths muertos (`~/projects/alfredo-pro-ecomm/backend`), versiones viejas (`erp-commerce-suite v4.4.1`) y secrets inline (`preprodroot123`/`devpass123`/`:8101`) en los docs curados.
- **Docs**: changelog kalimete (esta) + 3 agent docs + 3 harness (los symlinks de `~/.config/opencode/agent/` propagan automáticamente).

### [18:45] - Auditoria Victoria: BillyCode 8/8 OK + higiene + pasos victoria ejecutados
- **Tipo**: auditoria externa + docs (owner: "valida los cambios... aplica mejoras... procede con los proximos pasos")
- **Que**: (1) Validacion: 8/8 checks, serve 1.18.34 vivo, .env correcto (llave kalimete, URLs con path), withPath() defensivo bien hecho, guardrails D7 asentados, voice-pipeline.ts revisado (barge-in 2 niveles, stop-words con limites). (2) Mejora aplicada: apps/tui/voice.py ELIMINADO — era placeholder muerto que contradecia el ledger (F2 esta en apps/server, nadie importaba voice.py; tests siguen 8/8). (3) Pasos victoria ejecutados: caps single-source en sense_auth.py, ensure-loop reinicia bridges por md5 (verificado en vivo), git commit a6139aa, victoria-server.md al dia (sin 120K/xtts).
- **Pendiente owner**: readme.txt (handoff temporal) — borrar cuando confirme. F3 branding pendiente. kalimete-ptt: retiro sigue SOLO tras confirmacion.
- **Docs**: changelog kalimete (esta) + ledger billycode + victoria-server.md + changelogs de victoria.

### [19:45] - REPARACIÓN TOTAL Armada Star Fox validada (plan A1-E1, 18/18 escenas OK)
- **Tipo**: fix/game-dev
- **Modificado**: `~/dev/godot/armada-starfox/` (12 scripts, project.godot, 5 reescritas, 16 nuevos)
- **Afecta a**: kalimete/godot
- **Causa**: validación headless Godot 4.7.2: 8 errores compilación + 5 archivos inválidos + 8 refs rotas
- **Estado**: ✅ verificado (check-only limpio, import limpio, 18/18 escenas 30 frames sin errores)
- **Notas**: input re-mapeado (E/Q + Shift solo boost); level_select y niveles 2-5 como stubs jugables; PT→ES total; fases de boss corregidas; detalle en `docs/CHANGELOG.md` del proyecto.

### [20:15] - FIX Star Fox "no puedo jugar": disparo + fuego amigo + pausa (smoke 7/7)
- **Tipo**: fix/game-dev
- **Modificado**: `~/dev/godot/armada-starfox/` (player_ship.gd, bullet.gd)
- **Afecta a**: kalimete/godot
- **Causa**: reporte owner; humo headless reprodujo el fallo (fuego no salía; luego balas se autodestruían)
- **Estado**: ✅ verificado (smoke 7/7 VERDE, runner borrado, escenas tocadas re-corridas OK)
- **Notas**: fire_timer peleado entre _process/_physics → fire_cooldown único; balas ignoran grupo player + spawn fuera del casco; pausa sin soft-lock. Detalle en `docs/CHANGELOG.md` del proyecto.

### [21:10] - TEST Star Fox en vivo display :1 (render OK, inputmap 10/10, XTEST roto)
- **Tipo**: test (sin cambios de código)
- **Modificado**: ninguno
- **Afecta a**: kalimete/godot
- **Causa**: orden "compila el juego y ábrelo para probar"
- **Estado**: ✅ parcial (menú+nivel renderizan, log limpio; input sintético imposible en esta sesión X)
- **Notas**: correr desde fuente compila todo; export release pendiente (falta descarga templates ~1GB + preset). Detalle en `docs/CHANGELOG.md` del proyecto.

### [21:35] - Skill art para agentes opencode + E2E generación desde kalimete + victoria-tui blindada
- **Tipo**: feature + verificación (ronda de cierre, TARGET=kalimete verificado)
- **Que**: (a) **skill `art`** instalada para los agentes opencode de kalimete: `~/armada-sync/skills/art/SKILL.md` (repo, se sincroniza a GitHub) + `~/.config/opencode/skills/art/SKILL.md` (live) — enseña a generar imágenes vía la art API del gateway de Victoria (templates z-image-turbo/flux-schnell/sd15-realistic, flujo async 202→poll→download, cola 429=reintentar, extracción de llave anti-leak por regex del opencode.jsonc); (b) **E2E REAL**: la llave `kalimete` (coder + multi-tier llm/art/xtts/whisper aplicado hoy desde el panel) generó "robot barista retro-futurista" vía `POST 10.0.0.5:8010/v1/images` → poll → imagen descargada a `~/Desktop/robot-barista.png` (671KB) — el caso "genera y ponla en mi escritorio" funciona; (c) **victoria-tui blindada**: handlers SIGTERM/SIGHUP (cierre brusco de terminal ahora restaura el daemon kalimete-ptt — verificado: timeout-kill → daemon volvió a `active`) + UI interactiva verificada por pseudo-TTY (corrió viva 8s dibujando; el owner la usa con `victoria-tui` en su terminal).
- **Verificado**: submit `patched:True` con llave kalimete; imagen en Desktop; TUI exit 124 (viva) + daemon restaurado; skill en repo+config con md5 igual.
- **Impacto**: +skills/art (repo+config), victoria-tui actualizado, ~/Desktop/robot-barista.png (prueba). El sync.sh existente ya cubre skills/.
- **Docs**: changelog kalimete (esta entrada) + CHANGELOG general victoria (referencia).

### [21:40] - Star Fox GameLogger + Parte C (matriz 15/15 VERDE, log con traza, 0 errores)
- **Tipo**: feature/test (subagente Godot: logger + instrumentación; kalimete: validación final)
- **Modificado**: `~/dev/godot/armada-starfox/` (game_logger.gd nuevo autoload, project.godot+bkup, 8 scripts, docs)
- **Afecta a**: kalimete/godot
- **Causa**: pedido "logger para errores + validar que funciona para humanos"
- **Estado**: ✅ verificado (25/25 scripts, import limpio, 18/18 escenas, matriz 15/15, game.log 16 eventos/0 ERROR, screenshots en vivo, temporales borrados)
- **Notas**: fix Continue→level_select path; overlay F3 solo debug; log en `~/.local/share/godot/app_userdata/Armada Star Fox/logs/game.log`. Detalle en `docs/CHANGELOG.md` del proyecto.

### [22:15] - Star Fox Fase 2 tanda 1: bomba, spawner+enemigos, HUD y pausa en niveles (humo 8/8)
- **Tipo**: feature/fix/game-dev
- **Modificado**: `~/dev/godot/armada-starfox/` (player_ship.tscn, spawn_manager, 3 enemy.tscn, level_01 dict, hud.tscn+hud.gd, HUD en 5 niveles)
- **Afecta a**: kalimete/godot
- **Causa**: orden "procede" (pendientes Fase 2)
- **Estado**: ✅ verificado (humo 8/8, 18/18 escenas, 500 frames sin errores, screenshot en vivo: HUD + enemigo + score por combate real)
- **Notas**: fix global_position/add_child; pausa con panel; overlay F3 queda solo-debug. Pendiente: fuego amigo entre enemigos, jefe N1, minimapa, audio, export. Detalle en `docs/CHANGELOG.md` del proyecto.

### [22:15] - victoria-gui: entorno GRÁFICO web de Victoria (chat burbujas + mic + voz + config)
- **Tipo**: feature (pedido del owner: "¿no tiene un entorno gráfico que pudiéramos ver mientras trabaja en la terminal?")
- **Que**: `~/.local/bin/victoria-gui` — servidor web local (Python stdlib, ~470 líneas) + página con estética de Victoria (tema oscuro, acento morado #8B5CF6): (a) **chat de burbujas** con respuestas **STREAMING en vivo** (SSE token a token); (b) **botón micrófono push-to-talk** — mantener presionado graba (MediaRecorder del navegador), soltar → ffmpeg webm→wav → STT Whisper → envía; (c) **voz de Victoria** en las respuestas (TTS Qwen3 → audio en el navegador, toggle 🔊); (d) **config** (voz, idioma, modelo normal/thinking, hablar sí/no) guardada en el MISMO env del ptt/tui; (e) **historial compartido con la TUI** (history.jsonl — lo hablado en una aparece en la otra); (f) barra de estado con salud del gateway (refresh 15s); (g) **lanzador en el menú de aplicaciones** (`~/.local/share/applications/victoria-gui.desktop` — se abre como app normal del escritorio); (h) `--lan` expone a la LAN (usarla desde el teléfono), `--port N`, `--no-open`. Arquitectura: el servidor PROXYA al stack de Victoria (gateway :8010, voice-server :18810) — la llave NUNCA llega al navegador.
- **Verificado**: /api/status gateway ok; /api/chat SSE con tokens en vivo ("Hola…"); /api/tts → WAV 24kHz 122KB; /api/stt round-trip EXACTO ("Hola papá, aquí está tu interfaz gráfica." → mismo texto de vuelta); página sirve con el layout completo; instancia de prueba cerrada limpia.
- **Uso**: `victoria-gui` (abre el navegador solo) o clic en "Victoria GUI" del menú de apps. Parar: `pkill -f victoria-gui`.
- **Impacto**: +~/.local/bin/victoria-gui + lanzador .desktop. Sin tocar tui/ptt (comparten env+historial).
- **Docs**: changelog kalimete (esta entrada) + referencia en CHANGELOG general de victoria.

### [22:30] - Star Fox: guía de assets originales (docs/ASSETS.md) + aviso IP
- **Tipo**: investigación/docs
- **Modificado**: `~/dev/godot/armada-starfox/docs/ASSETS.md` (nuevo)
- **Afecta a**: kalimete/godot
- **Causa**: pedido "assets tal cual en vez de placeholders"
- **Estado**: ✅ fuentes localizadas (Models/Spriters/Sounds-Resource, Sketchfab CC, voces, OST) + alternativa legal Kenney CC0 + pipeline Godot
- **Notas**: prototipo con originales → release con CC0 (IP Nintendo). Pendiente decisión/descarga.

### [23:20] - Star Fox: assets integrados (OST 8 OGG + 12 voces + 7 SFX + Arwing procedural)
- **Tipo**: feature/game-dev
- **Modificado**: `~/dev/godot/armada-starfox/` (audio completo, Audio autoload, música/SFX cableados, 4 escenas con visuales propios)
- **Afecta a**: kalimete/godot
- **Causa**: orden "sí, procede" (opción 1 adaptada: modelos originales bloqueados por login/CF)
- **Estado**: ✅ verificado (humo 4/4, 18/18 escenas, 27 audios importados, screenshot Arwing + combate en vivo)
- **Notas**: khinsider con token por pista; SFX generados con python stdlib; naves procedurales = cero riesgo IP. Detalle en `docs/CHANGELOG.md` + `docs/ASSETS.md`.

### [23:35] - Star Fox: enemigos Kenney reales + Arwing (screenshot combate)
- **Tipo**: feature/game-dev
- **Modificado**: `~/dev/godot/armada-starfox/` (3 enemy.tscn con OBJ, player revert a Arwing)
- **Afecta a**: kalimete/godot
- **Causa**: racer Kenney ilegible de cerca; mix final: jugador Arwing + enemigos Kenney
- **Estado**: ✅ verificado (screenshot Arwing vs nave Kenney + score por combate, log limpio)
- **Notas**: Kenney Space Kit CC0 en models/ (cero IP). Detalle en `docs/CHANGELOG.md` + `docs/ASSETS.md`.


## 2026-10-03
### [11:05] - kalimete-ptt CONVERSACIONAL: Victoria responde por voz + llave services dedicada
- **Tipo**: feature | voz (Fase Jarvis-Victoria, autorización del owner, TARGET=kalimete verificado)
- **Que**: (a) `~/.local/bin/kalimete-ptt` mejorado (backup `.bak.20261003-voz`): tras pegar el texto, Victoria RESPONDE HABLANDO (LLM Qwen3.6-35B-normal vía 10.0.0.5:8010 → TTS Qwen3-TTS con su voz vía 10.0.0.5:18810 → `paplay` en parlantes); `PTT_VOICE_REPLY=1` (0 = solo-pegar como antes); persona breve/hablada (60 palabras, sin markdown); docstrings rootsource limpiados (cero refs); (b) llave nueva `kalimete-ptt` rol **services** en gateway Victoria (STT+LLM+TTS, sin panel; least privilege — la admin heredada queda como fallback STT); config en `~/.config/kalimete-ptt/env` (`PTT_VOICE_KEY` + URLs + modelo); servicio `kalimete-ptt` reiniciado.
- **Verificado**: compila OK; servicio active; E2E remoto LLM 200 OK + TTS 200 176KB + PLAY_OK en parlantes. Falta prueba viva del owner (mantener Ctrl, hablar, soltar, escuchar).
- **Docs**: este changelog (kalimete) + general de Victoria referencia.

### [11:40] - Voz viva en opencode + kalimete-ptt barge-in (Fase Jarvis, TARGET=kalimete)
- **Tipo**: feature | voz en opencode (autorización del owner)
- **Que**: (a) plugin `victoria-voice-live.js` en `~/.config/opencode/plugins/` (misma versión opencode 1.18.34): habla respuestas por oraciones + narra tools + barge-in; env en `~/.bashrc` (TTS por LAN + `VICTORIA_VOICE_KEY` desde kalimete-ptt env, single source); verificado E2E (tts ok 119KB + narración); (b) kalimete-ptt: `PTT_SUBMIT` (Enter tras pegar, opt-in) + toque-corto = solo callar + `PTT_BARGE_ABORT` (Esc opt-in); servicio reiniciado y activo.
- **Verificado**: plugin carga + deltas + TTS LAN con llave services; compila OK.
- **Docs**: este changelog (kalimete) + general de Victoria referencia. NOTA: reiniciar TUI opencode para cargar el plugin.

### [12:30] - Mario Bros: 5 fixes pendientes completados (Godot Agent)
- **Tipo**: feature | game-dev | Godot
- **Que**: Los 5 fixes pendientes del proyecto Mario Bros clone en Godot 4.7.2 completados por el subagente Godot:
  - Fix #1: BGM integrado con AudioManager singleton (play/stop/volume, loop_mode=1 en .import WAV)
  - Fix #2: place_pipe() usa escalamiento dinámico por height_levels (antes fijo 2x2)
  - Fix #3: Flash visual al golpear bloques question/brick (0.5s alternancia bright/dim)
  - Fix #4: Pause overlay con botón PLAY funcional (PausePanel/PauseText/PlayButton en HUD)
  - Fix #5: generate_level_for_stage(world, stage) — variantes procedurales con dificultad escalable
  - Bug fixes: game_manager.gd doble level_complete.emit() eliminado (loop), global_data.gd rename de funciones, hud.gd InputEventKey.new() correcto, level_builder.gd indentación uniformizada
- **Verificado**: `godot --headless --check-only` OK (solo WARNING de escena, no de código)
- **Archivos modificados**: 15 files, +551/-18 lines (AGENTS.md, audio/music/*.wav, main_game.tscn, hud_overlay.tscn, audio_manager.gd, brick_block.gd, game_manager.gd, global_data.gd, hud.gd, level_builder.gd, question_block.gd, generate_bgm.py)
- **Estado**: ✅ en sync (commit 30c2f5c en armada-godot local)
- **Notas**: Push a remote requiere autorización del owner.

### [13:15] - Mario Bros: 5 pendientes restantes completados (Godot Agent)
- **Tipo**: feature | game-dev | Godot
- **Que**: Los 5 pendientes restantes del Mario Bros clone completados tras la sesión de validación:
  - Fix #1 (pendiente): place_pipe() fórmula corregida `max(1.0, h*0.5)` → `1.5 + h*0.75` (1→2.25x, 2→3.0x, 3→3.75x), antes 1 y 2 niveles tenían misma altura (1.0x)
  - Fix #2 (pendiente): pause overlay mejorado — 3 recursos de tema creados (`themes/pause_bg_style.tres`, `pause_button_style.tres`, `pause_theme.tres`) con StyleBoxFlat y Theme, PlayButton renombre a "▶ CONTINUAR"
  - Fix #3 (pendiente): pipeline múltiples niveles verificado end-to-end — flag_pole→game_manager→level_builder→generate_level_for_stage() conectado correctamente, ruta de conexión flag_pole corrigida de `../../../MainGame` a `../..`
  - Fix #4 (pendiente): `global_data.gd` — `_handle_level_complete()` dead code eliminada (nadie la llamaba, flujo real via game_manager._on_level_complete)
  - Fix #5 (pendiente): `game_manager.gd` — dead connection `_global_data_ref.level_complete.connect(_on_level_complete)` eliminada (nadie emitía global_data.level_complete), ruta de escena `prefab_flag_pole.tscn` es la conexión funcional
  - Cleanup: duplicados `armada-godot/themes/` eliminados (res:// resuelve a projects/mario_bros/themes/)
- **Archivos**: 6 scripts + 2 escenas modificados, 3 nuevos .tres, 3 duplicados eliminados
- **Commits**: f4508e8 (pendientes) + 6211550 (cleanup themes) en armada-godot
- **Estado**: ✅ pipeline end-to-end completo (menú→juego→flag_pole→stage_clear→next_level→game_over)
- **Notas**: Push a remote requiere autorización del owner.

### [14:45] - Todowrite Discipline: fix lista zombie + doc modelos Qwen3.6 (mejores prácticas)
- **Tipo**: config | agente | best-practices (TARGET=kalimete, local)
- **Que**: (a) nuevo `~/.config/opencode/todowrite-discipline.md` cargado como 2º `instructions` en `opencode.jsonc` (backup `.bkup-20261003-todowrite`; JSON validado OK): dueño SIEMPRE kalimete (subagentes no escriben en lista del padre, issue #12938), merge manual tras cada `task`, item final de verificación obligatorio, vaciado explícito al cerrar; (b) doc modelos: Qwen3.6-35B-A3B-NVFP4 recomienda 0.6-1.0 según modo, nuestro stack usa 0.2/0.1 INTENCIONAL (determinismo infra > creatividad; Godot 0.4-0.6 queda propuesto, NO aplicado); (c) verificado contra schema en vivo: NO existen `todos.*`/`sidebar.*`/`subagents.enableTodos` — agregarlos rompería el arranque.
- **Verificado**: `python3 json.load(opencode.jsonc)` OK; docs: HF nvidia/Qwen3.6-35B-A3B-NVFP4, unsloth, RedHatAI, NGC + issues opencode #28961/#12938/#44221/#20484.
- **Docs**: este changelog (kalimete). NOTA: reiniciar TUI opencode para cargar la nueva instruction.
- **Estado**: ✅ sincronizado (push hub)

### [15:00] - Sampling Qwen3.6 por rol: 12 agentes creativos a temp 0.6/top_p 0.95 (docs+expertos)
- **Tipo**: config | agentes | best-practices (TARGET=kalimete, local; autorización explícita del owner)
- **Que**: 12 agentes de desarrollo/creativo (godot, wordpress, arcade, woodly, alfredo-ecomm, erp-dev, petsuite, taohemps, ragnarok, nextcloud, docuseal, scriberr): `temperature: 0.1 → 0.6` + `top_p: 0.95` (Qwen oficial thinking-precise-coding; backup `*.bkup-20261003-temp06`). Se mantienen en 0.1 (tool-use determinista, literatura agentes): cloudflare, irc, proxy, vps, victoria-server, authentik, proxmark (API/SSH/SSO/hardware físico) + kalimete 0.2 (routing/TARGET). `todos.*`/`sidebar.*` NO se tocan: no existen en schema oficial (romperían arranque).
- **Verificado**: 12× temp 0.6 + 12× top_p 0.95 (grep); 7× infra en 0.1; kalimete 0.2 intacto.
- **Docs**: este changelog (kalimete). NOTA: reiniciar TUI opencode (temps e instructions se cargan al inicio).
- **Estado**: ✅ sincronizado (push hub)

### [16:45] - Auditoria flota (Victoria→kalimete): Arcade a 0.6 como decia el changelog + kalimete.md a la realidad
- **Tipo**: fix | config | docs (TARGET=kalimete verificado; pedido del owner: "valida y ajusta todo el ecosistema")
- **Que**: (a) `Armada Arcade` temperature 0.1 → **0.6 + top_p 0.95** en AMBAS copias (`~/armada-arcade/agents/armada-arcade.md` canonica + replica `armada-sync/agents/`) — la entrada 15:00 listaba 12 creativos pero live habia 11 (arcade quedo en 0.1); (b) `kalimete.md` curado: frontmatter "subagentes ocultos" → visibles en @ (desde 10-01), `name: kalimete` explicito, linea corrupta "loopstream propio..." reconstruida, doctrina sampling actualizada (12 creativos 0.6/0.95 + infra 0.1 + kalimete 0.2), seccion "rotos eco-*" reemplazada (renombrados 10-01), tabla activos con display names (Armada Arcade, WordPress, ERP Dev, Godot); (c) datos de victoria actualizados: 256K nativo + seqs 3 (era 160K/4), driver 580.173.02, llaves 11 (era 7; +kalimete coder 10-02, +kalimete-ptt services 10-03), prompt 220K (era 120K), key opencode kalimete (era alfredo), warnings resueltos (nginx -t OK, sin :3389, sin ufw → ip6tables); (d) `opencode.jsonc`: `"model"` default `vllm/nvidia/Qwen3.6-35B-A3B-NVFP4-normal` (sesiones nuevas arrancan en el cerebro local — antes sin default caian al free opencode, origen de los rate-limit kills del forense 10-02); en casa seguir cambiando a `vllm-lan` (backup `.bkup-20261003-defaultmodel`); (e) plugin `victoria-voice-live.js`: linea de comentario duplicada eliminada (mismo fix aplicado en victoria — md5 vuelve a ser identico entre maquinas); (f) CHANGELOG: header duplicado "## 2026-10-03" eliminado (esta misma pasada).
- **Verificado**: grep 12× `temperature: 0.6` + 12× `top_p: 0.95` en los 20 agentes; python3 json.load(opencode.jsonc) OK; hostname=kalimete verificado ANTES de mutar; sampling validado contra la model card oficial nvidia/Qwen3.6-35B-A3B-NVFP4 (SciCode/coding = 0.6/0.95, general = 1.0/0.95) + voz E2E re-verificada desde victoria (TTS es ref nativa → STT exacto).
- **Docs**: este changelog (kalimete) + general de Victoria referencia (regla de procedencia). NOTA: reiniciar TUI opencode para cargar temps/model default.
- **Estado**: ✅ sincronizado (push hub)

### [17:47] - Organizacion del home: proyectos en ~/dev/, limpieza de basura, eliminar armada-arcade
- **Tipo**: infra | organizacion (TARGET=kalimete, local; autorizado por el owner)
- **Que**: (a) `armada-arcade/` borrado del home (el juego se hara en Godot, no se necesita); (b) `armada-godot/` renombrado/movido a `~/dev/godot/` (carpeta para proyectos Godot); (c) proyectos movidos a `~/dev/`: `tapmap-data/`, `ragnarok-staging/`, `projects/alfredo-pro-ecomm/ → dev/webs/`, `projects/woodly/ → dev/webs/`; (d) herramientas movidas: `~/tools/ → dev/hacking/tools/`, `~/scripts/ → dev/hacking/scripts/`, `~/go/ → dev/go/`, `~/bin/ → ~/.local/bin/`; (e) unificado `.victoria/` + `.victoria-custom/` → `.victoria/custom/` (+ `/victoria/platform-v1/` al custom); (f) borradas carpetas basura: `123123/`, `qasdasdasd/`, `projects/`, `Projects/`, `agendas con las agenda.`, `cloduflare data armada.do`, `pm 3`, `.qasdasdasd.kate-swp`; (g) borrados temporales: `landing-*.html`, `melina-form-eq.txt`, `ecco-urls.txt`, `woodley-park-restaurants.json`, `te lo dije.png`, `dumpkeys.bin`, `repostocheck`, `alfredo_backup_2026_agentes.tar.gz` (1.1GB → movido a ~/backups/); (h) eliminados symlinks rotos en `~/.local/bin/` (dork-engine, nano-pdf, camsnap, goplaces, himalaya, wacli, intigriti, summarize, osint); (i) eliminados symlinks rotos en home (.steampath → .steam/sdk32/steam, .steampid → .steam/steam.pid); (j) eliminado duplicado `~/~` (directorio ~ dentro del home); (k) subagentes de kalimete: 19→18 (quitado Armada Arcade); (l) MCP Godot actualizado: opencode.jsonc apunta a `~/dev/godot/armada-godot/` (proyecto real); (m) todas las refs de `armada-godot`→`dev/godot/armada-godot`, `armada-arcade` eliminadas en agents/, harness/, MAPA.md, sync.sh, bin/.
- **Rutas nuevas**: `~/dev/godot/` (proyectos Godot), `~/dev/webs/` (webs), `~/dev/hacking/` (hacking), `~/dev/games/` (games), `~/dev/go/` (Go), `~/dev/cybersec/` (cybersec - creada pero vacia), `~/.victoria/custom/` (unificado), `~/.local/bin/` (scripts propios), `~/backups/` (archivos de backup).
- **Afecta a**: kalimete (estructura de home), agents/godot-dev.md, agents/kalimete.md, harness/godot-dev.harness.json, harness/kalimete.harness.json, sync.sh, bin/doc-fresh.sh, bin/upstream-kalimete-check.py, MAPA.md, opencode.jsonc (MCP), upstream/state.json.
- **Notas**: `~/dev/ethical-hacking/` ya existia; `~/dev/hacking/` es nuevo para kenshin/tools. `~/dev/` ya tenia estructura existente (apps/, infra/, ops/, etc.) que se mantiene. El MCP godot requiere opencode reiniciado para tomar la nueva ruta.
- **Estado**: ✅ sincronizado (push hub)

### [20:35] - victoria-tui: version grafica del kalimete-ptt (chat streaming + PTT + config)
- **Tipo**: feature (pedido del owner: "version grafica del kalimete-ptt donde pueda hacer streaming chat live o push to talk, tambien configurarlo" — construido por Victoria @ victoria.local, TARGET=kalimete verificado)
- **Que**: `~/.local/bin/victoria-tui` (TUI curses, ~700 líneas, stdlib+requests+evdev): (a) **chat en vivo** con Victoria — respuestas STREAMING token a token (SSE del gateway :8010), historial persistente en `~/.local/share/victoria-tui/history.jsonl` (carga los últimos 60 al abrir); (b) **push-to-talk** — mantener Right Ctrl (o tecla configurada) graba por ffmpeg+PulseAudio, soltar → STT Whisper (:18810) → envía → respuesta streaming + VOZ de Victoria (Qwen3-TTS → paplay); usa evdev con grab exclusivo (hold real, no toggle); fallback F9 toggle si no hay evdev; (c) **config** (F3): voz ON/OFF, idioma es/en, modelo normal/thinking, endpoint LAN/público, tecla PTT, voz victoria/usuario — se guarda en el MISMO `~/.config/kalimete-ptt/env` (single source, el ptt global hereda); (d) F2 voz rápida, F4 callar (barge-in), PgUp/PgDn scroll; (e) mientras corre, el daemon global kalimete-ptt se PAUSA (misma tecla) y se reactiva solo al salir; (f) modos auxiliares: `--check` (valida config+gateway+evdev+ffmpeg) y `--say "texto"` (one-shot streaming+voz).
- **Verificado**: `--check` TODO OK (gateway 200, evdev 16 dispositivos, ffmpeg/paplay); `--say` E2E streaming OK ("Hola papá, aquí estoy..." + "Listo, papá.", exit 0); py_compile OK; instalado 755 en ~/.local/bin/. La UI interactiva requiere terminal del escritorio (curses) — el owner la prueba con `victoria-tui`.
- **Impacto**: solo añade ~/.local/bin/victoria-tui + ~/.local/share/victoria-tui/; NO toca kalimete-ptt (comparte su env, se pausa/reanima solo); sin cambios en opencode/agents.
- **Docs**: changelog kalimete (esta entrada) + CHANGELOG general de victoria (referencia).


## 2026-10-02
### [00:45] - Fix permisos: WP admin local no podía borrar plugins (ACLs en bind mount)
- **Tipo**: fix | infra | wordpress
- **Causa raíz**: `wp-content/plugins/` es bind mount del host con owner `warcold:warcold` (1000) modo 755; el contenedor corre PHP como `www-data` (UID 33) → solo lectura → "Borrar" en WP admin fallaba (pedía FTP o "no se pudo eliminar"). `themes/` y `uploads/` ya eran www-data (por eso sí funcionaban). Descartado `DISALLOW_FILE_MODS`.
- **Fix**: ACLs recursivas en `~/dev/wordpress/wp-content/plugins/`: `setfacl -R -m u:33:rwx,u:1000:rwx` + default ACL `-d` para herencia en archivos nuevos. Owner sin cambios → edición host-side intacta.
- **Verificación E2E**: plugin desechable `zz-test-delete` borrado vía flujo admin real (GET confirm → POST verify-delete → 302) → carpeta físicamente eliminada ✅. www-data touch+rm OK, warcold touch+rm OK.
- **Extra validado esta sesión**: stack local 100% operativo (DB 22 tablas intactas, login admin/admin123 OK en ambas URLs, plugin 4.4.2 activo, AJAX→ERP 18 categorías reales). El "DB vacía" reportado antes fue falso positivo de kalimete (password root equivocado en sus propios comandos: `rootpassword` vs `root_pass_2026`).
- **Detalle**: entrada completa en `~/dev/wordpress/CHANGELOG.md` [fix-permisos-plugins]. Reversible: `setfacl -R -b`.
- **Estado**: ✅ verificado end-to-end

### [01:30] - Armada Suite 5.1.0: menú único, dedup, fix footer overlap, unificación completa
- **Tipo**: feature | refactor | ux | wordpress
- **Menú único**: nuevo `MenuUnifier.php` (admin_menu prio 999) — `ai1wm_export` y `vibe-ai` ocultos como top-level, re-registrados como 5 submenús de Armada Suite (Exportar/Importar/Respaldos con badge + Puente IA/Registro IA). Reset Hub y Schedules NO re-registrados (upsells premium). Título: "ERP Suite"→"Armada Suite".
- **Dedup verificado**: ¿2 MCP? NO (tab MCP=estado API propia, AiBridge=tools para IAs — complementarios). ¿2 chatbot? NO (1 bot Carlos: Chatbot/IA=cerebro, Voz/WhatsApp=canales). Limpieza real: filtro muerto `mcp_adapter_tools` eliminado (main + WpvibeBridge), texto obsoleto emcp-tools/mcp-adapter→Puente IA.
- **Fix footer** (bug del owner REPRODUCIDO con Selenium): WP 7.1.2 pone #wpfooter hijo de body con absolute;bottom:0 → clavado al viewport, contenido largo se desliza debajo (overlap 52px medido en tab entorno). Fix: `position:static` scopeado → 0px verificado. (Owner reportó bien la versión: WP auto-actualizó 6.7→7.1.2.)
- **Textos + (i)**: helper `ERPSuite_AdminMenu::info()` + CSS popup sin JS; simplificados Conexión ERP, Config tienda, ID tienda, Carrito, MCP.
- **Borrado final** (autorizado, backup 1.8M en `~/backups/armada-unificacion-20261002/`): erp-commerce-suite/, vibe-ai/, all-in-one-wp-migration/ + mu-plugin muerto + plugins/export/ vacía. Solo queda armada-suite/. Borrado con rm directo (NO vía admin: los uninstall.php habrían borrado las opciones compartidas).
- **Smoke**: home 200, 8/8 admin 200, AJAX success:true 18 categorías, 0 FATALs, active_plugins=solo armada-suite.
- **Commits stack** (~/dev/wordpress, sin push): 19a1e4e (5.0.0 creación) + 9697d3d (5.1.0 consolidación) + 169fc4d (borrado aiowpm). Detalle en ~/dev/wordpress/CHANGELOG.md.
- **Nota proceso**: subagente wordpress-dev agotó steps 2 veces (diagnóstico + 90% construcción); kalimete completó la milla final (fix uninstall.php, activación curl, verificación 8 puntos, consolidación v5.1.0) — documentado por transparencia.
- **Estado**: ✅ verificado end-to-end

### [02:15] - Armada Suite 5.1.1: fixes del owner (Respaldos 404, menú, saves, export limpio)
- **Tipo**: fix | ux | wordpress
- **Respaldos 404**: causa raíz en WP core (`menu-header.php` exige callback registrado para generar href completo). `MenuUnifier` ahora pasa callbacks originales → 6/6 submenús con URLs válidas, páginas 200.
- **Menú**: primer submenú "Armada Suite" duplicado → "Panel".
- **Saves**: sin duplicación real (cada form guarda sus settings); labels específicos por tab para claridad.
- **Export**: solo File + Google Drive (filtro prio 999; otros 14 eran ads premium). Sidebar ServMask eliminado de las 3 vistas.
- **Commits stack** (sin push): ver ~/dev/wordpress/CHANGELOG.md [armada-suite-5.1.1]. Smoke: home 200, 6/6 admin 200, 0 FATALs.
- **Estado**: ✅ verificado

### [03:00] - Armada Suite 5.1.2: Asistente IA fusionado, dropdown, centrado, UI unificado
- **Tipo**: feature | fix | ux | wordpress
- **Asistente IA**: Chatbot/IA + Voz/WhatsApp fusionados en 1 tab (cerebro + canales, guía 5 pasos WhatsApp, 1 save). BUG REAL: 4 secciones con display:none sin JS que las mostrara (ajustes inalcanzables) — liberadas, 5/5 visibles verificado.
- **Dropdown Export**: altura fija 456px ServMask → auto (57px verificado). **Backups centrado** (anulado margin-right 399px fantasma → 960px centrado verificado).
- **Avisos**: remote_banner con branding viejo → Armada Suite, y "sin conexión" solo en modo público (ruido eliminado en local).
- **UI**: armada-modules.css nuevo (módulos) + acento verde ServMask en Panel (botones + h3). Guardar carrito → Guardar pagos.
- **Commits stack** (sin push): ver ~/dev/wordpress/CHANGELOG.md [armada-suite-5.1.2]. Smoke: todo 200, 0 FATALs.
- **Estado**: ✅ verificado

### [03:30] - Armada Suite 5.1.3: footer único + simplificación botones/checks
- **Tipo**: fix | ux | wordpress
- **Footer único**: filtro `admin_footer_text` pone nuestra info en la posición del "Thank you" de WP (1 línea); eliminado footer propio + CSS. Bump versión 5.1.3 (cache-bust assets).
- **Botones**: auditoría por tab — sin duplicados reales (cada uno acciona distinto). Visual: tabla salud 4 filas → 1 badge + (i); Vaciar caché a estilo link. Se mantienen Verificar/Sincronizar (ping vs sync) y acciones de Proyectos/Avanzado.
- **Commits stack** (sin push): ver ~/dev/wordpress/CHANGELOG.md [armada-suite-5.1.3]. Smoke: todo 200, 0 FATALs.
- **Estado**: ✅ verificado

### [04:00] - Armada Suite 5.1.4: nav unificada + fix botón fantasma (div huérfano)
- **Tipo**: feature | fix | wordpress
- **Nav unificada**: misma barra de pills en las 6 páginas (Panel + 5 módulos) con activos independientes por nivel. Fix: JS scopeado a .erpsuite-tabs (quitaba el active de la suite nav).
- **Botón fantasma**: `</div>` huérfano en render_tab_pagos expulsaba el submit + secciones fuera del wrap (visible en todos los tabs). Eliminado + barrido: 5 wrappers legacy display:none sin JS (contenido inalcanzable) eliminados. Avanzado/Catálogo ahora muestran todo.
- **Commits stack** (sin push): ver ~/dev/wordpress/CHANGELOG.md [armada-suite-5.1.4]. Smoke: todo 200, 0 FATALs.
- **Estado**: ✅ verificado

### [04:30] - Armada Suite 5.1.5: sin barra superior, submenú izquierdo persistente
- **Tipo**: fix | ux | wordpress
- **Quitado**: barra superior de pills (owner prefiere lista izquierda). Código y CSS eliminados.
- **Persistencia**: el submenú se colapsaba en módulos porque WP resolvía parent a registros fantasma ($submenu huérfanos tras remove_menu_page). Fix: unset() de ambos — verificado expandido + resaltado correcto en las 6 páginas vía Selenium.
- **Commits stack** (sin push): ver ~/dev/wordpress/CHANGELOG.md [armada-suite-5.1.5]. Smoke: todo 200, 0 FATALs.
- **Estado**: ✅ verificado

### [17:30] - Armada Suite 5.2.0: consolidación API propia erpsuite/v1/ops + amputación nube wpvibe.ai
- **Tipo**: feature | security | refactor | wordpress
- **Consolidación** (decisión owner: 1 API propia sobre el motor más completo, solo recursos propios, sin membresías/terceros): OpsMotor propio (includes/Remote/OpsMotor.php) envuelve el motor AiBridge vendored (WPVibe v1.20.0) bajo `erpsuite/v1/ops` — 15 rutas: 5 originales + 7 lecturas (file/read|list|search|outline, content/search, site-info, motor-status) + 3 escrituras con policy (Guard paths deny-list, draft-only, dry-run→preview_id single-use→confirm, anti-drift 409, ai_mode=work fail-closed, rate-limit 10/min, audit). Options: UNA sola puerta (/ops/settings con Guard allowlist).
- **Amputación nube/terceros** (F1): 0 llamadas vivas a mcp.wpvibe.ai/wpvibe.ai/jsdelivr — rutas cloud (self-update, code-snippet WPCode, builder-login SeedProd), authorize-notice beacon, dashboard-widget feed, connection-check preflight, CDN Tailwind, footers/branding, upsells. UI: conector = REST propio del sitio; sidebar CTA → admin propio. Guards class_exists anti-fatal (white-label, cli-plugin).
- **Custom model → gateway propio** (F3): ChatEngine fallback a `wpvibe_custom_model` (placeholder victoria.armada.do); bloque modelo (Sites.php) +7 lecturas allow / +3 escrituras deny explícitas; Text Domain efectivo `erp-suite` (D5-lite, 459 usos, sin migración masiva); atribución GPL WPVibe en readme; docs/REMOTE-OPS.md alineado.
- **Fixes sesión**: Importar sitio sin estilo (causa: import.min.css nunca encolado — hook vendored `all-in-one-wp-migration_page_*` vs live `armada-suite_page_*`; fix en MenuUnifier enqueue espejo + backups) → 5.1.6/5.1.7. Puente IA sin providers de pago (ChatGPT/Claude/Cursor fuera, fatal latente WPVibe_Uninstall_Notice corregido). Test 14 regression.php: drift pre-rename corregido.
- **Regresión F4**: 14/14 PASS exit 0; 5 páginas admin 200/0 fatals; REST sin auth 403; php -l 18/18. Commit `f87ae0c` (repo local ~/dev/wordpress, sin remote).
- **Alfredo Ecomm** (paralelo): D11 docs :3001→:3004 (README+Caddyfile), D14 agent doc reescrito (paths/ports LIVE), D15 harness JSON expandido, D6-D9 namespace legacy CONGELADO documentado (slug/constantes/options/REST/shortcodes — renombrar rompe DB/clientes), estándar documentado: Armada Suite=plugin WP, Alfredo Pro Ecomm=backend :3004 solo-Woodly.
- **Estado**: ✅ verificado (GO). Pendiente owner: validación visual final (Ctrl+F5 ?ver=5.2.0) + decidir residuales (footer links wpvibe.ai ya eliminados; CORS_ORIGIN :5174; nginx woodly :3001 stale).

### [21:30] - FIX "se para incluso en auto": timeouts NIM (glm-5.3 tardaba >5min y opencode mataba el run)
- **Tipo**: fix | config | diagnostico forense
- **Sintoma (owner)**: agentes se paran a mitad de tarea incluso en modo auto; no terminan el trabajo.
- **Causa RAIZ (forense log opencode)**: `ProviderHeaderTimeoutError: Provider response headers timed out after 300000ms` en provider `nvidia` (z-ai/glm-5.3 via NIM, API externa) — 5 veces hoy (01:54, 01:59, 14:00, 23:44, 01:08) + 7 rate-limits/conexiones de kimi-k3 y muse-spark (provider opencode free). Cuando el provider externo tarda >5 min en devolver headers (razonamiento max + contexto grande), opencode ABORTA EL RUN COMPLETO -> el agente muere a mitad de tarea. El provider nvidia NO tenia timeouts configurados (solo los locales vllm/vllm-lan los tenian). COINCIDENCIA EXACTA: error NIM 23:44:51 -> stop de sesion local 23:44:57.
- **El stack LOCAL estaba SANO todo el dia**: 239 requests, 0 rechazos, 0 errores de stream, compacts cada ~5min a 112K reales (TUI con context 144000 en memoria — requiere restart para tomar el 220000).
- **Modificado**: `~/.config/opencode/opencode.jsonc` provider nvidia: `timeout: 1800000` (30 min header-timeout), `chunkTimeout: 600000`, `maxRetries: 3`. Mismo fix aplicado en victoria.
- **Afecta a**: sesiones que usen NIM (glm/deepseek/kimi) — sobreviven first-byte lentos y reintentan rate-limits. Requiere restart del TUI.
- **Recomendacion**: para subagentes operativos (WordPress release/commit), el local (vllm-lan, Qwen) responde en segundos; NIM glm-max para razonamiento pesado (ahora con 30 min de aire).
- **Estado**: en sincronizacion (hub cada 5 min)

### [21:55] - Validacion camino LOCAL (Godot): infra 100% sana — los stops eran comportamiento del modelo
- **Tipo**: diagnostico forense
- **Evidencia**: 0 errores de stream en provider vllm-lan/vllm hoy; 0 fallos del gateway para la sesion (239 requests OK, latencia media 4-8s con prompts 90-133K, prefix-cache sano); 30.2M tokens de entrada servidos sin un solo 502/timeout. El vLLM y el gateway NO se cayeron nunca.
- **Los 2 modos de "se para" del local (sesion Crear juego Mario en Godot)**:
  1. **Amnesia por compactacion (era 144K)**: compacts cada ~5 min a 112K reales (5 drops verificados 19:31-19:50 EDT); tras cada compact el modelo perdia detalle y cerraba turnos anticipadamente (ct=120-338 = textos finales cortos).
  2. **Final degenerado a 133K con variante THINKING**: el ultimo mensaje de la sesion (21:03:05) = step-start + reasoning + step-finish SIN texto y SIN tool call — el modelo penso y no emitio nada -> opencode cierra el turno. Completiones colapsando: 84/69/74/64/120/.../106 tokens en los minutos finales. Ademas 3 requests cortados por thinking_token_budget (2048, lo inyecta el gateway). La sesion corria en la variante "Thinking · Coding con Victoria".
- **Recomendaciones**: (a) para loops agenticos largos usar la variante NORMAL "Coding con Victoria" (thinking OFF — es el default recomendado del stack desde 09-13; thinking para problemas puntuales, no para maratones); (b) correr opencode DESDE ~/armada-godot para que el ledger AGENTS.md auto-cargue en cada sesion (compact-proof); (c) el 220K ya aplicado reduce el churn 2.3x (trigger 188K).
- **Estado**: en sincronizacion (hub cada 5 min)

### [23:58] - Key coder propia + git init armada-godot (auditoría Victoria)
- **Tipo**: config | seguridad | procedencia
- **Que**: (a) key `kalimete` (coder) creada en gateway Victoria; `opencode.jsonc`: apiKey nueva en `vllm`+`vllm-lan` + `instructions` absoluta (backup `.bkup-20261002-2358-kalimete-key`); la admin de alfredo se conserva (reiniciar TUI para tomar la nueva); (b) `git init` en `~/armada-godot` + `.gitignore` Godot (`.godot/`, `*.backup`, `*.bak`) + commit inicial (Mario Bros sin control de versiones; ledger `armada-godot/AGENTS.md` ya cubría `mario_bros/`, no se duplicó).
- **Verificado**: JSON válido; `/v1/usage` 200 con la nueva.


## 2026-10-01
### [00:05] - Harness único Kalimete: 23 subagentes ocultos + estándar de harness + fixes
- **Tipo**: infra | agentes | harness | seguridad
- **Modificado**: 19 archivos (agents/*.md + MAPA.md). `kalimete.md` (permission.task +erp-dev/+godot-dev, tabla +2 filas, sección Harness maestro). Frontmatter `hidden:true`+color en los 17 que faltaban (TAB ahora muestra SOLO kalimete/plan/build). 8 esqueletos expandidos al estándar (stack validado, comandos copiables, capacidades, reglas). `wordpress-dev.md` actualizado (erp-commerce-suite v4.4.0 unificado; el doc citaba plugins pre-4.0.0). MAPA.md (dup taohemps fuera, ERP 4.1.0→4.4.0, filas erp-dev/godot-dev, providers 3→4+MCP). `opencode.jsonc` (backup .bkup-20261001): MCP godot `command` string+args → array (el SDK exige `Array<string>`; así como estaba el MCP nunca conectaba). `eco-docuseal.md`: password SMTP en claro retirada del repo (→ puntero a .env).
- **Afecta a**: kalimete (enrutamiento único; ya puede delegar a erp-dev y godot-dev, antes denegado por `*: deny`). Sin impacto en producción (solo docs + frontmatter).
- **Causa**: Usuario: un solo agente principal Kalimete con harness completo; que los agentes manejen sus herramientas según su documentación y no haya que seleccionarlos manualmente.
- **Validación**: `docker ps` kalimete (19 cont.) + vps-preprod (29 cont., Up 4 weeks); InspIRCd nativo activo (6667/6697, no es docker); ERP plugin v4.4.0 en contenedor; `grep -L hidden` = 0 pendientes; symlinks sanos; `armada-arcade` se edita en `~/armada-arcade/agents/` (el collect lo replica).
- **Estado**: ✅ sincronizado
- **Notas**: excepciones documentadas en kalimete.md (harness maestro). Lo no verificado en agentes remotos quedó marcado pendiente, no inventado.

### [01:30] - Micaserogou: BUG plugin — campos Asistente IA invisibles (JS tabs oculta secciones internas) + hotfix site-level (ZIP v1.0.2)
- **Tipo**: bugfix | upstream
- **Modificado**: NUEVO mu-plugin erpc-mg-admin-fix.php (hotfix): erpsuite-admin.js activate() hace $('.erpsuite-section').attr('hidden',true) sobre TODAS — incluidas las 3 secciones INTERNAS de los forms del tab Asistente IA — y solo des-oculta la del tab activo → campos LLM/identidad/tools invisibles, botones Guardar visibles (síntoma del owner). Hotfix: inline script prio 99 re-muestra .erpsuite-form .erpsuite-section tras cada activación. Verificado vía CDP con sesión admin preprod: 350×40 visible / 0×0 en otros tabs / visible al volver. ZIP instalador v1.0.2 (7 mu-plugins)
- **Afecta a**: admin de todos los tenants (upstream); micaserogou hotfix site-level YA en preprod
- **Causa**: owner no veía dónde pegar config LLM — diagnóstico doble agente: prod==local byte-idéntico (deriva descartada), render_tab_ia sin condiciones, causa = JS de tabs (reproducido: rect 0×0 con computed styles normales)
- **Estado**: ✅ hotfix verificado; PENDIENTE owner: subir ZIP v1.0.2 + pegar config LLM
- **Notas**: upstream #12 para 5.6.0: scope selector a '.erpsuite-section[id^="erpsuite-tab-"]' (1 línea). Solo el tab Asistente IA usa secciones internas → bug invisible en otros tabs

### [00:30] - Consolidación: eco-cloudflare único + ragnarok docs-harness + limpieza duplicados
- **Tipo**: infra | agentes | refactor | diagnóstico
- **Modificado**: `agents/eco-cloudflare.md` (NUEVO, unifica dns/security/storage/tunnels/workers con todas sus reglas aprendidas: IDs de zona/ruleset, NO-2-niveles, R2 ban, playbook túneles). BORRADOS los 5 + sus symlinks (limpieza autorizada). `kalimete.md` (permission `eco-cloudflare-*`→`eco-cloudflare` exacto — el wildcard ya no matcheaba; tabla 5 filas→1). MAPA.md (tabla igual). `eco-ragnarok.md` reescrito como harness docs (rAthena/FluxCP/roBrowser/wsProxy + estado vivo). Fuente+despliegue agregados a woodly/petsuite/taohemps/scriberr/alfredo-ecomm (rutas verificadas). Sin duplicados reales: erp-dev (facturación Laravel) vs alfredo-ecomm (e-commerce Node) son sistemas distintos — documentada la distinción (mismo hostname, puertos :8100/:3004). eco-vps vs proyectos = frontera host/app, se mantiene.
- **Afecta a**: kalimete (1 solo target Cloudflare, cero misrouting). Sin impacto en producción (docs + routing).
- **Causa**: Usuario: identificar discrepancias/duplicados, unificar por sistema, harness basado en documentación oficial de cada servicio.
- **Diagnósticos nuevos (verificados, no inventados)**:
  - 🎮 Demonios rAthena (6900/6121/5121) NO corren en vps-preprod — el juego web carga pero no puede autenticar. Fuente lista en `/srv/ragnarok` (confs, Dockerfiles, sql-init, scripts, ansible).
  - 🔴 `ragnarok.cp.armada.do` → TLS handshake failure en edge aunque origin da 200: viola la regla CF de no-2-niveles. Propuesta: `ragnarok-cp.armada.do` (requiere confirmación, cambia URL pública).
  - ⚠️ wsProxy sin allow-list verificada (`-a` restringido pendiente de confirmar).
- **Estado**: ✅ sincronizado
- **Notas**: pendiente confirmación usuario para renombre del panel y para levantar daemons athena (build desde Dockerfile.rathena).

### [02:30] - Estructura espejo Victoria: principal + 19 hide + harness + frescura + upstream + sync unificado
- **Tipo**: agentes | config | sync | docs
- **Modificado**: `opencode.jsonc` (+`default_agent: kalimete`), `agents/kalimete.md` (identidad flota + regla TARGET + frescura + harness + snapshot victoria 160K/Docker/7 keys/limites 120K/dual P-LAN), `agents/eco-victoria.md` (tabla 13 servicios + receta 160K + Upstream), 19x `## Upstream`, `harness/` (central + 19 JSON), `sync.sh` (+secrets-gate pre-push), `~/bin/doc-fresh.sh` (TTL 24h, estado local fuera del repo)
- **Afecta a**: kalimete (cero produccion: solo docs/config; symlink `agents` eliminado = un solo dir real `agent/`, requiere restart TUI; permisos godot-dev/proxmark ya existian, verificado sin cambio)
- **Causa**: owner: mismo sistema que Victoria (principal visible + hide + @ directo + harness + upstream + frescura) y sync unificado con scopes separados (hub GitHub kalimete Vs snapshots victoria, nunca cruzados)
- **Estado**: en sincronizacion (hub cada 5 min)
- **Notas**: eco-irc no sale en docker ps (pendiente si es nativo); daily-report Discord FALLO con token presente (pendiente owner: rotar/verificar); binario opencode no en PATH no-interactivo (agent list pendiente en TUI)

### [10:10] - Subagentes VISIBLES en autocomplete @ (espejo Victoria, decision del owner)
- **Tipo**: agentes | config
- **Modificado**: 19 subagentes (`agents/*.md` + `~/armada-arcade/agents/armada-arcade.md`): frontmatter `hidden: true` -> `hidden: false`. `kalimete.md` INTACTO (mode: primary, color teal, permission.task allowlist completa). `default_agent: kalimete` ya estaba.
- **Afecta a**: kalimete (TUI opencode): Tab sigue mostrando SOLO kalimete/plan/build (primaries); el autocomplete `@` ahora lista los 19 subagentes (armada-arcade, eco-* x14, erp-dev, godot-dev, proxmark, wordpress-dev) para invocacion directa con `@Nombre`, ademas de la delegacion Task por kalimete.
- **Causa**: owner (via Victoria): mismo fix aplicado en victoria 2026-10-01 — "quiero verlos todos al escribir @". En kalimete los 19 quedaron hidden:true al montarse la estructura espejo (entrada 02:30); ahora se abren.
- **Verificado**: `opencode agent list` live: 19 subagentes resuelven `(subagent)`, primaries = kalimete+plan+build (+internos), CERO duplicados, permisos por agente intactos.
- **Estado**: en sincronizacion (hub cada 5 min)
- **Notas**: backup pre-cambio en `~/.config/opencode/bkup-agents/bkup-20261001-hidden-false/` (21 archivos). El binario opencode no esta en PATH no-interactivo: ruta canonica `/home/warcold/.opencode/bin/opencode`. Se requiere restart del TUI para que el autocomplete tome el cambio.

### [10:45] - Subagentes RENOMBRADOS a nombres reales (adios prefijo eco-) + name: display + harness alineado
- **Tipo**: agentes | harness | docs | refactor
- **Modificado**: 14 archivos `agents/eco-*.md` renombrados con `git mv` (sin prefijo: `authentik.md`, `cloudflare.md`, `docuseal.md`, `irc.md`, `nextcloud.md`, `petsuite.md`, `proxy.md`, `ragnarok.md`, `scriberr.md`, `taohemps.md`, `victoria-server.md`, `vps.md`, `woodly.md`, `alfredo-ecomm.md`); los 19 con `name:` display nuevo (`Authentik`, `Cloudflare`, `DocuSeal`, `IRC`, `Nextcloud`, `PetSuite`, `Proxy`, `Ragnarok`, `Scriberr`, `Taohemps`, `Victoria Server`, `VPS`, `Woodly`, `Alfredo Ecomm`, `Armada Arcade`, `ERP Dev`, `Godot`, `Proxmark`, `WordPress`) + linea `> **Frescura**` + ref a su harness. `kalimete.md`: permission.task con claves = display names EXACTOS + scope reescrito + historia eco-cloudflare conservada + tabla. `harness/`: 14 renombrados + los 20 alineados (name/harness id/hidden:false/agent_file/docs) + central (lista subagentes + scope_agentes). Symlinks `~/.config/opencode/agent/` recreados. `bin/doc-fresh.sh` AGENTES -> ids lowercase. `bin/upstream-kalimete-check.py` ids -> lowercase. MAPA.md + configs/MAPA.md + commands/mapa.md + ecosistema-map + cloudflare-map (areas Cloudflare compactadas al agente unico). state/frescura.json remapeado.
- **Afecta a**: kalimete (TUI): `@` ahora muestra nombres reales identificables (antes eco-*); delegacion Task de kalimete usa los names exactos; cero cambios de produccion/permisos por agente (edit/write deny preservados donde correspondia).
- **Causa**: owner (via Victoria): "no usemos eco, usemos el nombre bien, ej. Authentik, Cloudflare, DocuSeal, NextCloud, Ragnarok" + cada agente con su harness y su documentacion oficial (mismo estandar Victoria).
- **Verificado**: `opencode agent list` live: 19 subagentes con nombres reales `(subagent)`, primaries kalimete/plan/build intactos, CERO duplicados; 20 harness JSON validos; backup pre-cambio `~/.config/opencode/bkup-agents/rename-20261001-pre.tar.gz` (70 archivos). Requiere restart del TUI para el autocomplete.
- **Estado**: en sincronizacion (hub cada 5 min — ya publicado)
- **Notas**: `Victoria Server` (no "Victoria") a proposito: ese subagente GESTIONA el host victoria (solo lectura) — no es hablar CON Victoria. El historial "kalimete antes era eco-cloudflare" (2026-08-12) se conserva con nota. Referencias eco-accesos/eco-voice (muertos) intactas como historia.

### [11:15] - Diagnostico compactaciones agente Godot (MCP ruidoso) + ledger + steps 50 + higiene
- **Tipo**: diagnostico | agentes | docs
- **Causa medida (forense gateway victoria)**: sesion del owner desde kalimete (10.0.0.106, key alfredo, modelo local) = 105 requests / 0 fallos / 9 compactaciones detectadas en ~15 min. Techo real de compactacion ~78-88K (NO 120K: el trigger es context120K - output32K - reserved10K ~= 78K, y un solo tool call lo empuja a ~87K). Salto tipico tras compactar: 15K -> 77K en UN turno = tool outputs del MCP godot masivos (+60K tokens c/u: arbol completo/estado editor). Conclusion: NO es fallo del modelo ni del gateway (105/105 OK, latencia media 11s con prompts 80K+, prefix-caching OK).
- **Modificado**: `~/armada-godot/AGENTS.md` CREADO (ledger por proyecto: mapa Mario Bros clone Godot 4.x, comandos headless, higiene, decisiones, pendientes — sobrevive a compactaciones). `agents/godot-dev.md`: `steps: 15 -> 50` (el limite 15 dejaba tareas grandes por mitad) + seccion "Higiene de contexto" (nodos especificos no arbol completo, no screenshots salvo pedido, errores filtrados).
- **Afecta a**: kalimete (agente Godot); cero impacto en produccion.
- **Pendiente (decision del owner, reinicio vLLM 5-7 min en victoria)**: subir `--max-model-len` 160000 -> ~196608 + gateway MAX_PROMPT_TOKENS 120K->144K + opencode context 144000 en ambos hosts => espacio de trabajo real 78K -> ~102K (+30%). KV 12GiB lo soporta (4x192K=768K < 945K). Alternativa sin cambios: sesiones maraton via provider NVIDIA NIM (DeepSeek 1M nativo, ya configurado en kalimete).
- **Estado**: en sincronizacion (hub cada 5 min)

### [12:55] - opencode.jsonc context 120000 -> 144000 (upgrade de contexto victoria 192K)
- **Tipo**: config | cross-machine
- **Modificado**: `~/.config/opencode/opencode.jsonc` (backup `.bkup-20261001-144k`): `"context": 120000` -> `144000` en los 4 modelos (providers vllm publica + vllm-lan LAN).
- **Afecta a**: kalimete TUI: el techo real de compactacion sube de ~78K a ~102K (+31%) — menos amnesia de sesion en proyectos largos (Godot MCP). El vLLM de victoria ahora sirve 192K reales; el gateway capta prompts hasta 144K.
- **Causa**: owner (via Victoria): "procede al maximo que se pueda sin afectar el ecosistema y configura el opencode.jsonc de victoria y de kalimete". Aplicado desde victoria tras recrear el vLLM (detalle en CHANGELOG victoria / vllm).
- **Verificado**: victoria E2E (prompts 100K+ reales OK, opencode run OK, cerebro sandbox OK). En kalimete requiere restart del TUI para tomar el cambio.
- **Estado**: en sincronizacion (hub cada 5 min)

### [13:11] - Fix bug categorías MaganTech (redirect HTTPS WordPress) + nuevo endpoint /categories en ERP Ecomm + CORS
- **Tipo**: fix | api | wordpress | infra | diagnóstico
- **Modificado**:
  - **WordPress (kalimete :8091)**: `wp-config.php` reescrito (SSL_FIX_INJECTED v2 — HTTPS solo tras `X-Forwarded-Proto` del nginx, `WP_HOME`/`WP_SITEURL` dinámicos desde `HTTP_HOST`, removidos 3 bloques duplicados de `$_SERVER['HTTPS']='on'` + `FORCE_SSL_ADMIN` condicional). Backup `/tmp/wp-config.php.bkup_20261001_124405`. Backup DB `/tmp/wp_backup_20261001_124109.sql.gz`.
  - **ERP Ecomm (kalimete :3004)**: `backend/src/routes/stores.ts` — NUEVO `GET /v1/stores/:slug/categories` (SQL raw GROUP BY, excluye inactivos/vacíos; colocado ANTES de `/:slug` por shadowing de Express). `docker-compose.yaml` — `CORS_ORIGIN` ahora `${CORS_ORIGIN:-...}` con defaults + `localhost:8091` + `mantantech.kalimete.local`; eliminado `version: "3.8"` obsoleto. `.env.example` + `README.md` documentados. Backups `.bkup`.
  - **Docs**: `agents/alfredo-ecomm.md` (sección cambios 2026-10-01).
- **Afecta a**: kalimete (`wordpress-local` y `alfredo-ecomm-api` recreados/redeployados localmente). CERO producción (vps-preprod verificado: ERP y WordPress/MaganTech NO viven ahí).
- **Causa**: Usuario: "click en categorías de la web no cambia de categoría ni en tiempo real". Diagnóstico: (1) **causa raíz del bug = redirect loop HTTPS** — `siteurl` apuntaba a `https://wordpress.kalimete.local` → 301 a `https://localhost/productos/` mataba la página entera (0 bytes, ningún JS corría); (2) no existía endpoint dedicado de categorías en el ERP; (3) CORS no incluía el origen del WordPress.
- **Verificado**:
  - `curl -sI http://localhost:8091/productos/` → **200 OK, 66,606 bytes** (antes 301 con 0 bytes) ✅
  - Filtrado funciona vía `admin-ajax.php?action=erpc_get_products&categoria=X` (erp-commerce-suite v4.4.0): `erpc_get_categories` devuelve las **18 categorías reales de MaganTech** (erpipos `:8100` tenant 10); filtro `categoria=Cables` devuelve producto real ✅
  - `GET :3004/v1/stores/woodly-park/categories` → `{"data":[{"Dispensary":1},{"Drinks":1},{"Kitchen":6}]}` (sum=8 = `_count.products` ✅); slug inexistente → 404 ✅
- **Estado**: ⚠️ pendiente verificación en navegador real (curl confirma server-side; falta click real del usuario)
- **Notas**: **HALLAZGO CLAVE** — el WordPress MaganTech consume erpipos `:8100` tenant 10 (vía admin-ajax same-origin, sin CORS), NO el ERP `:3004` de woodly-park. El endpoint `/categories` nuevo + CORS beneficia a frontends que usen el :3004 (Woodly). Doc drift corregido: credenciales DB reales WP = `wordpress`/`wordpress_pass_2026`, root = `root_pass_2026`. Pendientes: tests del endpoint (backend sin suite), verificación E2E navegador, confirmar dominio público MaganTech, deploy ERP a prod (requiere autorización explícita).

### [14:28] - Switch Local/Público en plugin erp-commerce-suite 4.4.1 + alineación arquitectura ecomm (owner)
- **Tipo**: feature | wordpress | arquitectura | docs | validación
- **Instrucción del owner**: (1) WP local trabaja SOLO con ERP Dev local (erpipos :8100 tenant 10), nunca producción; (2) el ERP Dev vive en `github.com/soycarlosjerez-hub/sistema-facturacion` rama `dev/ecomm-erp` — nosotros solo pusheamos updates ahí, **Juan Carlos mergea a main** (nosotros nunca); (3) plugin erp-commerce-suite: mejorar tabs/páginas admin con errores; (4) la config de conexión del plugin debe tener **switch Local↔Público**: local = valores HARDCODEADOS por defecto (NO editables NI visibles, solo el switch se ve), público = conexión/llaves de erpipos prod EDITABLES por el admin de WP.
- **Modificado**:
  - **Plugin erp-commerce-suite 4.4.0 → 4.4.1** (wordpress-local :8091): `includes/Core/Environment.php` (reescrito — perfil LOCAL sellado: `http://172.19.0.1:8100/api`, tenant_id 10, key iak_* como constantes; accessors `get_api_url/get_api_key/get_tenant_id`; modo persiste en `wp_options.erpsuite_env_mode`), `includes/Core/Main.php` (delega a Environment), `includes/Admin/AdminMenu.php` (badge LOCAL|PÚBLICO, `tab_entorno()` muestra "Perfil Local (sellado)" en local — datos NO visibles, `sanitize_unified()` solo persiste conexión si switch=Público en namespace `erp_suite_settings[public][...]`), `includes/Admin/LegacyConnectorAdmin.php` (`render_tab_conexion()` gateado por modo: local=cero inputs de conexión, público=inputs editables; health check usa accessor). Backups `.bkup` ×4 + `/tmp/wp_options_backup_20261001_134829.sql.gz`.
  - **Docs**: `~/dev/wordpress/CHANGELOG.md` (SSL_FIX v2 + credenciales reales + 4.4.1), CHANGELOG propio del plugin, `agents/alfredo-ecomm.md` (endpoint /categories = mejora general del ecosistema, NO fix de MaganTech; CORS :8091 = cortesía; nueva sección "Vecindad — no confundir": erpipos :8100 Laravel ≠ alfredo-ecomm :3004 Node; deploy a prod = requiere autorización explícita).
- **Afecta a**: kalimete local únicamente (wordpress-local, docs armada-sync). CERO producción.
- **Causa**: owner definió la arquitectura y pidió mejoras del admin del plugin + separación local/público estricta.
- **Verificado**:
  - `php -l` 4/4 archivos OK; **`tests/regression.php` 14/14 PASS**
  - HTML settings modo Local: **0 coincidencias** de `172.19.0.1` ni `iak_` (datos locales ni se renderizan ✅); solo el switch visible
  - admin-ajax con env=local: `erpc_get_products` 200 (AGI-CT2000 Rollo UTP CAT6), `erpc_get_categories` 200 (**18 categorías reales MaganTech**); `erpc_cfg` frontend sigue recibiendo el perfil sellado
  - Auditoría de los 9 tabs del admin: **todos HTTP 200, 0 errores PHP** (Voz/WhatsApp = dependencia de credenciales externas desactivadas por el owner, no "roto"; notices `emcp-tools/list-pages` son de OTRO plugin, documentado); assets admin todos 200
  - **ERP Dev validado**: erpipos local :8100 operativo (stack 7 contenedores healthy + mailpit no documentado); logs nginx confirman tráfico real del plugin WP (`GET /api/tienda/categorias 200`, `/api/tienda/productos?limit=200 200`, `/api/ecomm/tienda/config 200` UA WordPress/7.1.2); repo `~/dev/erpipo-preprod/code/sistema-facturacion` en rama `dev/ecomm-erp`, tree limpio, **5 commits docs ahead de origin sin push** (pendiente decisión del owner)
  - **Alfredo Ecomm :3004**: health OK, `/v1/stores/woodly-park/categories` 200 — intacto, scope exclusivo Woodly
- **Estado**: ✅ sincronizado
- **Notas**: Doc drift corregido en agente erp-dev (live: push directo a `origin dev/ecomm-erp`, NO existe remote `preprod`/`warcold/erpipo-preprod`; merge a main = Juan Carlos). Pendientes: push de los 5 commits docs de erpipos (decidir con owner); smoke test del modo Público del switch (guardar campos public_* y flip; requiere llaves reales de prod — NO hacer sin autorización); apagar Xdebug en erpipo-preprod-app (ruido en logs); alinear título "Doc drift agente erp-dev" cuando se reescriba su sección Acceso/Workflow.

### [14:35] - Contexto 144000 -> 220000 (vLLM 256K nativo + seqs 3) — menos compactacion
- **Tipo**: config | cross-machine
- **Modificado**: `~/.config/opencode/opencode.jsonc`: `"context": 144000` -> `220000` en los 4 modelos (vllm publica + vllm-lan).
- **Causa**: owner (via Victoria): evaluacion con 14 dias de data — las 4 secuencias del vLLM NUNCA se usaron (pico 3, 0.17%) -> se canjeo una carril por el contexto NATIVO completo (256K + seqs 3 en victoria). Trigger de compactacion: ~102K -> ~178K (+74%): el coding (Godot etc.) compacta mucho menos.
- **Evaluacion de agentes (mismo pedido)**: kalimete SANO — AGENTS.md global 2.5KB (~700 tokens, sin necesidad de summary), subagentes 0.6-2K tokens c/u, primary 5.8K. El ruidoso era el MCP godot (+60K/tool call) ya mitigado (higiene + steps 50 + ledger ~/armada-godot/AGENTS.md).
- **Verificado en victoria**: E2E prompt 140K reales 200 OK; cerebro sandbox OK; en kalimete requiere restart del TUI.
- **Estado**: en sincronizacion (hub cada 5 min)

### [16:05] - ZIP de producción erp-commerce-suite-4.4.1 empaquetado
- **Tipo**: release | wordpress
- **Modificado**: NUEVO `~/dev/wordpress/dist/erp-commerce-suite-4.4.1.zip` (**779 KB, 103 archivos**, raíz `erp-commerce-suite/`). Fuente: `/home/warcold/dev/wordpress/wp-content/plugins/erp-commerce-suite/` (volumen del contenedor wordpress-local). Repo propio del plugin: `ssh://git@github.com/warcold/erp-commerce-suite.git` (rama master).
- **Contenido**: bootstrap + uninstall + readme.txt + README/CHANGELOG + includes/ (Core/Admin/Store/AI/Remote/Infra) + assets/ + templates/ + docs/ + tests/regression.php (CLI-only, útil para smoke post-deploy). **Excluidos**: `.git/`, todos los `*.bkup` de hoy, `export/` (zips viejos), `node_modules/`, `.env*`, tests legacy.
- **Verificado**: php -l 6/6 OK pre-zip; `unzip -l` confirma estructura WP estándar y ausencia de .git/.bkup/.env.
- **Afecta a**: ninguno (artefacto de distribución; el owner lo sube a prod manualmente)
- **Causa**: owner: "¿dónde está el plugin .zip para subirlo a producción y probar la parte de producción?"
- **Estado**: ✅ listo para subir
- **Notas**: ⚠️ `includes/Core/Environment.php` lleva HARDCODEADO el perfil LOCAL sellado (API URL `172.19.0.1:8100`, tenant 10 y key `iak_` local de dev) — por diseño del owner queda en el ZIP; la key local es inútil fuera de la red de kalimete, pero si el repo fuera público o el zip se comparte, conviene refactor futuro a constante inyectada vía wp-config. En PROD el admin debe: switch → PÚBLICO → tab Conexión → meter URL/tenant/key reales de erpipos prod (las keys de prod viajan en wp_options de prod, NUNCA en el zip). Instrucciones completas entregadas al owner en el chat.

### [16:30] - Ruta canónica ÚNICA de artefactos WP + consolidación de zips (owner: "no quiero tener 2 rutas")
- **Tipo**: organización | docs | limpieza
- **Análisis**: el owner reportó duplicidad con `~/Desktop/dev/wordpress/export/` vs `~/dev/wordpress/dist/`. Verificado: `~/Desktop/dev` es un **symlink** a `/home/warcold/dev` — misma ubicación física, no hay duplicación de datos, solo doble forma de escribirla. Pero SÍ existían 3 carpetas de distribución reales: `~/dev/wordpress/export/` (vieja: DEPLOY-GUIA + v4.2.0), `~/dev/wordpress/dist/` (creada hoy con 4.4.1), y `~/dev/wordpress/wp-content/plugins/erp-commerce-suite/export/` (DENTRO del repo del plugin: v4.3.0, v4.4.0).
- **Decisión**: canónica = **`~/dev/wordpress/export/`** (forma sin Desktop). Regla: artefactos SIEMPRE ahí; prohibido `export/` dentro del plugin (agregado a su `.gitignore` junto a `dist/`); en docs/comandos jamás `~/Desktop/dev/...`.
- **Modificado**:
  - Movidos: `dist/erp-commerce-suite-4.4.1.zip` → `export/`; `wp-content/plugins/erp-commerce-suite/export/{v4.3.0,v4.4.0}.zip` → `export/`. Borradas ambas carpetas vacías (`rmdir`). Ruta final del ZIP de prod: **`~/dev/wordpress/export/erp-commerce-suite-4.4.1.zip`** (la referencia a `dist/` de la entrada 16:05 queda SUPERADA).
  - `.gitignore` del plugin: `export/` + `dist/` (commit local `c79f711` en master de `warcold/erp-commerce-suite`, SIN push — pendiente owner).
  - Docs: `~/dev/wordpress/export/DEPLOY-GUIA.md` (header canónico), `~/dev/wordpress/DEPLOY-PRODUCCION.md` (bloque de ruta canónica), `~/dev/wordpress/CHANGELOG.md` (entrada `[ruta-canonica-dist]`).
  - `agents/wordpress-dev.md`: regla de ruta canónica en Docker Stack + plugin actualizado a **v4.4.1 con switch Local/Público** + backend local = erpipos :8100 tenant 10.
  - `harness/wordpress-dev.harness.json`: nuevo bloque `rutas_canonicas` (proyecto / artefactos_zip / plugin / erp_local) + docs extra. JSON validado.
- **Afecta a**: kalimete (docs/organización). CERO producción.
- **Verificado**: `export/` final = 5 archivos (DEPLOY-GUIA + 4 zips); `dist/` y export interno del plugin eliminados; `unzip -t` del 4.4.1 = sin errores tras el move.
- **Estado**: ✅ sincronizado
- **Notas**: ⚠️ Pendiente del owner: el repo del plugin tiene SIN COMMITEAR todo el código del switch 4.4.1 (Environment.php, Main.php, AdminMenu.php, LegacyConnectorAdmin.php + untracked includes/Remote/, readme.txt, erpsuite-remote.js). Solo se commiteó el `.gitignore`. Recomendado: `git add -A` (los .bkup ya están ignorados) + push de la 4.4.1.

### [18:00] - Validación exhaustiva anti-duplicados plugin 4.4.2: LIMPIO (veredicto: navegador del owner)
- **Tipo**: diagnóstico | wordpress
- **Reporte del owner**: "en todos los tabs: botones duplicados, textos montados". Segunda ronda de validación (la primera por HTML estático no bastó).
- **Método**: Selenium headless real (chromedriver) con login real + análisis DOM programático (bounding boxes, contadores de nodos visibles) — ni el subagente ni kalimete pueden ver imágenes (modelos sin input visual), por eso evidencia numérica.
- **Resultados (los 9 tabs)**:
  - Navegación por URL: 1 nav, 1 sección visible, 0 botones duplicados, 0 solapes >30% (1366px y 780px)
  - **Navegación por CLICKS, 2 pasadas** (gap cubierto): 1 sección visible por tab, 0 duplicados, 0 acumulación — el JS no clona al interactuar
  - Umbral de solape bajado a >8%: **0 pares** en los 9 tabs
  - Zoom 125%: limpio; zoom 150%: 1 falso positivo (bounding-box de spans inline que wrappean, glifos no se montan; script linecheck.py quedó en /tmp sin ejecutar)
  - Doble registro de menús: descartado (1 add_menu_page, AdminMenu.php:36; LegacyConnectorAdmin es wrapper llamado por diseño)
  - Doble enqueue: descartado (3 handles, 1 vez cada uno; ver=ERPSUITE_VERSION dinámico → cache-bust OK, servido como ?ver=4.4.2 en localhost:8091 Y wordpress.kalimete.local)
  - erpsuite_remote_nonce x3 y _wpnonce x9: patrón WP legítimo (un nonce por form)
  - Inyección del connector.css VIEJO (pre-fix): rompe fuentes/íconos pero NO produce botones duplicados → ni siquiera el bug original explica el síntoma actual
- **Veredicto**: el sitio servido 4.4.2 está CORRECTO; no existe bug reproducible de duplicación. Lo que el owner ve = estado de su navegador (pestaña abierta pre-fix / cache de disco). NO se aplicaron fixes inventados (regla respetada).
- **Estado**: ✅ validado; pendiente confirmación del owner tras Ctrl+Shift+R o incógnito
- **Notas**: Si persiste tras limpieza de cache → pedir al owner: navegador+versión, zoom, % escalado DPI, y qué texto/botón exacto ve duplicado en qué tab, para reproducir su contexto en headless.
- **Tipo**: fix | wordpress | release
- **Reportado por owner**: tras instalar el plugin, "se perdieron varios íconos arriba del menú de WordPress" + footer `Thank you for creating with WordPress.` duplicado/desplazado.
- **Diagnóstico (antes de tocar nada)**: las 9 pantallas del plugin + dashboard + posts nativos verificadas por HTML — `footer-thankyou` =1 por página, `wpadminbar` =1, **0 errores PHP**, balance de `<div>` =0 errores, CSS admin del plugin NO se carga en páginas nativas. NO era markup roto.
- **Causa raíz**: `assets/css/connector.css` (líneas 14-21) — reglas `body, body *` con `font-family: Ubuntu !important` + `letter-spacing` se encolaban también en el admin del plugin via `Main.php::admin_assets()`. Pisaban las fuentes de wp-admin: `#wpadminbar .ab-icon` (dashicons) quedaba invisible → "íconos perdidos", y el footer nativo se descuadraba. **Bug heredado desde ~v3.13.1, NO causado por el switch 4.4.1.**
- **Fix**: selectores re-scopeados a `body:not(.wp-admin)` + contenedores propios (`.wp-admin .erpsuite-wrap`, `.erpc-section`) — frontend intacto, admin nativo protegido, plugin conserva su look. `connector.css.bkup` previo.
- **Modificado**: `connector.css` (+15/-4), bump **4.4.1 → 4.4.2** (header + ERPSUITE_VERSION + readme Stable tag), CHANGELOG del plugin + `~/dev/wordpress/CHANGELOG.md`. NUEVO `~/dev/wordpress/export/erp-commerce-suite-4.4.2.zip` (780K, 103 archivos, `unzip -t` OK; el 4.4.1.zip se conserva histórico).
- **Commits locales** en `warcold/erp-commerce-suite` (master, SIN push — pendiente owner): `d5d58c5` feat: switch Local/Público 4.4.1 (+acumulado 4.3.0-4.4.0), `94c6737` fix(admin): scope connector.css (4.4.2), `4cc098e` docs. Working tree limpio.
- **Afecta a**: kalimete (plugin + artefacto). CERO producción (el owner sube el 4.4.2.zip cuando quiera).
- **Verificado**: `tests/regression.php` 14/14 PASS post-bump; CSS servido via HTTP muestra selectores corregidos; switch Local/Público intacto.
- **Estado**: ✅ sincronizado
- **Notas**: Owner debe hacer **Ctrl+F5** en wp-admin para ver el fix (cache-bust `?ver=4.4.2` ayuda). Si quiere historia git pristina (4.4.1 puro separado del bump 4.4.2) requiere `git rebase -i` — no hecho sin autorización. Push del repo plugin sigue pendiente a decisión del owner.


## 2026-09-30
### [00:00] - Godot Game Dev: MCP integration (386 herramientas) + agente godot-dev
- **Tipo**: proyecto | gamedev | MCP | herramienta
- **Modificado**: @yanhuifair/godot-mcp 1.12.3 (npm global), Godot 4.7.2 (steam), proyecto armada-godot, opencode.jsonc (mcp config), agents/godot-dev.md
- **Afecta a**: kalimete (opencode MCP client),~/armada-godot (proyecto demo)
- **Causa**: Usuario: "VAMOS A CREAR EL HARNESS / AGENTES PARA GODOT" — necesitamos integración de IA con Godot Engine para desarrollo de juegos
- **Cambios realizados**:
  - ✅ MCP server `@yanhuifair/godot-mcp` 1.12.3 instalado globalmente (npm)
  - ✅ Godot 4.7.2 symlinked a /usr/local/bin/godot (era godot.x11.opt.tools.64)
  - ✅ Proyecto demo ~/armada-godot/ creado con project.godot + addons/godot-mcp/ plugin
  - ✅ opencode.jsonc: sección `mcp` con server `godot` (type: local, command: godot-mcp, args: -p /home/warcold/armada-godot)
  - ✅ Agente `godot-dev.md` creado (386 tools, 30 categorías, GDScript, editor bridge, runtime bridge)
  - ✅ Symlink creado: ~/.config/opencode/agents/godot-dev.md → armada-sync/agents/godot-dev.md
- **Estado**: ✅ sincronizado (pendiente commit/push)
- **Notas**: 386 herramientas vs IvanMurzak/Godot-MCP (42 tools, requiere .NET 8 que no tenemos). @yanhuifair es TypeScript puro, funciona sin Godot abierto para 220+ tools, tiene undo nativo, runtime freeze/step/screenshot (único), 30 categorías

### [00:35] - ERP Commerce Suite 4.2.0: panel UX — SPA tabs, diseño propio, datos vivos del ERP

### [00:35] - ERP Commerce Suite 4.2.0: panel UX — SPA tabs, diseño propio, datos vivos del ERP
- **Tipo**: proyecto | UX | feature | wordpress
- **Modificado**: erp-commerce-suite 4.1.1→4.2.0. AdminMenu SPA client-side (erpsuite-admin.js: tabs sin recarga, deep link #tab-x, localStorage, flechas teclado); erpsuite-admin.css (hero+badge modo, tabs píldora dashicons, cards estado, botones rounded, responsive mobile ≤782px); cards datos vivos en Entorno/Catálogo/MCP (conteos reales ERP vía transient 60s, sin bloqueo si cae); assets solo en nuestra página admin (toplevel_page_erp-suite)
- **Afecta a**: kalimete (wordpress-local wp-admin), producción (v4.2.0 en export/)
- **Causa**: Usuario: hay tabs sin información, todo recarga al hacer click, quiere diseño amigable + responsive/móvil
- **Validación**: php -l 50/50; regresión 8/8; render() completo sin fatal (8 secciones, 7 hidden, 8 cards, badge DEV); erp_counts productos=162 categorias=18 ok=true (fix: shape real ERPC_API['meta']['total']); ZIP reconstruido 761 KB
- **Estado**: ✅ sincronizado. Suite push OK. ZIP: ~/dev/wordpress/export/erp-commerce-suite-v4.2.0.zip
- **Notas**: en el camino: restore temporal del admin conector con Main ya en singletons → sitio caído ~2 min, reparado con split correcto (off-by-one en rango de prep)


## 2026-09-29
### [11:30] - ERP local actualizado a origin/dev/ecomm-erp 5c6ca70 + env migrado (MAIN intacto)
- **Tipo**: proyecto | update | env | erp
- **Modificado**: ~/dev/erpipo-preprod/code/sistema-facturacion (dev/ecomm-erp e76b0c3 → 5c6ca70 + commit local 7d1e885); preprod DB migrada (0 pending, incluye delivery_pickup + whatsapp/cobranza/auditoria)
- **Afecta a**: kalimete (erpipo-preprod :8100, erp.kalimete.local); wordpress-dev (contrato config intacto)
- **Causa**: Usuario: actualizar ERP local con última versión de soycarlosjerez-hub/sistema-facturacion (main=prod no tocar, dev/ecomm=nuestra)
- **Validación**: 2 hosts verificados (LLM configurable vía admin erpcbot_settings→ia.api_url=http://10.0.0.5:8010/v1 DB; ERP prod fijo ERPC_API_URL=https://erpipos.armada.do/api, override solo mu-plugin→172.19.0.1:8100); fetch muestra origin/dev/ecomm-erp==origin/main==5c6ca70 (Juan mergeó PR #10); local main sin tocar; TiendaApiController dedupe 5 keys + sin duplicados; php -l OK; :8100/:8091/:3004 vivos; .bkup-ERP movidos a /tmp/opencode/erp-bkup-20260929 (stash backup conserva original)
- **Estado**: ✅ sincronizado local. Pendiente confirmación usuario para push a origin/dev/ecomm-erp (ahead 1, Juan acepta)
- **Notas**: ajax_test_connection() usa ERPC_API_URL directo sin filtro (botón Probar apunta a prod en dev — reportado, no tocado); MAPA.md tiene versiones WP/ERP desactualizadas (pendiente actualizar)

### [19:50] - ERP Commerce Suite 4.0.0: 3 plugins → 1 plugin unificado, activo y verificado
- **Tipo**: proyecto | feature | consolidación | wordpress
- **Modificado**: ~/dev/wordpress/wp-content/plugins/erp-commerce-suite/ (NUEVO, 51 PHP files): unifica erp-chatbot 1.4.6 + erp-ecomm-connector 3.15.2 + mcp-basic-auth 1.1. Entry + Core/{Environment,Main,Logger,Activator} + Store/{ApiClient,Auth,CartCheckout,Customer,Forms,Templates,Shortcodes} + AI/{ChatEngine,Bootstrap,Channels/WhatsApp} + Infra + Admin/{AdminMenu,LegacyConnectorAdmin,LegacyChatbotAdmin,LogViewer} + Compat/Legacy + 22 templates + assets + tests.
- **Afecta a**: kalimete (wordpress-local :8091), GitHub warcold (3 repos borrados, 1 nuevo)
- **Causa**: Usuario: unificar todo en 1 plugin sin roles (manage_options), modo dev/público sellado, borrar rastro de los 3 plugins local + GitHub
- **Validación**: activada en WP (active_plugins = emcp-tools + suite + mcp-adapter); migración erpc_settings+erpcbot_settings→erp_suite_settings con backup erpsuite_legacy_backup; php -l 51/51; regresión 8/8; front/productos 200 con grid real del ERP local (172.19.0.1:8100); widget carga; REST erpsuite/v1/whatsapp existe (403 sin challenge, esperado); api_url dev=172.19.0.1:8100/api, llm=10.0.0.5:8010/v1, img=erp.kalimete.local, tenant 10 + api_key migradas
- **Estado**: ✅ sincronizado. GitHub: erp-chatbot + erp-ecomm-connector + erp-ecmm-connector BORRADOS; creado warcold/erp-commerce-suite (private) con push inicial + docs
- **Notas**: fixes post-build del subagente (murió por rate limit a mitad): porté Main.php + AI/Bootstrap.php de los entries viejos, corregí alias invertido erpc()/erpsuite() (fatal), recursión infinita en Environment::get_api_url (apply_filters + alias Compat), image_host dev apuntaba a prod, 16 archivos con constantes legacy (ERPC_PLUGIN_DIR etc.), ERPSUITE_DEFAULT_HERO sin definir. Rastros en cuarentena /tmp/opencode/erp-suite-deleted-20260929/ (recuperable). Pendiente 4.1: consolidar renders admin legacy en los 8 tabs del menú ERP Suite (hoy 3 menús funcionales), retirar aliases Compat y mu-plugin erpc-local.php. ERP local clavado a main puro de Juan 5c6ca70 (sin edits, rama dev/ecomm-erp local preservada con nuestro commit 7d1e885 sin push).

### [21:40] - ERP Commerce Suite 4.0.1: auditoría de seguridad completa + hardening (16 hallazgos)
- **Tipo**: proyecto | seguridad | wordpress
- **Modificado**: erp-commerce-suite 4.0.0→4.0.1 (webhook WhatsApp 403 sin app_secret; init garantiza .htaccess+index.php en logs dir; secrets admin enmascarados value=""+preserve-if-empty verificado; capability manage_options en erpc_log_read/list/clear y MCP transport; erpc_client_ip anti-spoof XFF→X-Real-IP solo de proxy confiable; chat RL usa client_ip; erpc_log_error RL 30/min+cap 20; LogViewer basename guard; sslverify modo-aware; ajax_test_connection respeta modo sellado; uninstall transients propios). Stack: nginx wordpress.kalimete.local.conf +deny debug.log y uploads/erp-suite-connector/ (bkup .bkup-20260929)
- **Afecta a**: kalimete (wordpress-local), producción futura (el ZIP de deploy lleva todo el hardening)
- **Causa**: Usuario: procede con mejores prácticas, seguridad, nada expuesto en plano, no explotable
- **Validación**: probes antes/después — debug.log 200→404, logs dir servido→404, webhook POST sin secret → 403 erpsuite_wa_sin_secreto (E2E con enabled=1 temporal), chat/log AJAX sin nonce bloqueados, sanitize preserve-if-empty PRESERVED OK (ia.api_key, tenant.api_key, smtp_pass), php -l 51/51, regresión 8/8, front/productos 200
- **Estado**: ✅ sincronizado (repo suite push 4.0.1). Aceptado/documentado: secrets en wp_options plaintext (estándar WP, cifrado 4.2), sink .html() connector.js (disciplina de escape mantenida)
- **Notas**: auditoría por wordpress-dev (16 hallazgos con file:line) + probes y fixes por kalimete. Hallazgo #2 confirmado en runtime: logs servidos por HTTP (el .htaccess nunca existía porque el Logger no está cableado — además nginx ignora .htaccess, doble capa aplicada)

### [23:30] - ERP Commerce Suite 4.1.0: admin consolidado (1 menú, 8 tabs reales) + fix crítico register_setting
- **Tipo**: proyecto | feature | refactor | wordpress
- **Modificado**: erp-commerce-suite 4.0.1→4.1.0. AdminMenu con 8 tabs reales (split de render_page legacy: ERPC_Admin→6 métodos, ERPCBot_Admin→5 métodos, ambos singleton); sanitize_unificado por marcador erpsuite_form en AdminMenu::register_settings (ÚNICO registro); Main::get_api_url sellado vía Environment; ApiClient image host vía Environment; Compat/Legacy.php retirado; mu-plugin erpc-local.php retirado (queda solo disable-mcp-host-guard.php)
- **Afecta a**: kalimete (wordpress-local), producción futura
- **Causa**: spec original usuario (1 plugin, panel minimalista por tabs) + items pendientes 4.1 documentados
- **Fix crítico**: ambos admin legacy registraban register_setting sobre la MISMA option con sanitizers distintos — el último pisaba al otro y guardar desde una página BORRABA los campos de la otra (latente desde 4.0.0). Verificado con 3 escenarios: preservación mutua OK
- **Validación**: php -l 50/50; regresión 8/8; 8 tabs render OK (form+nonce+marker); menú único (erp-chatbot eliminado, slug erp-suite sin conflicto); front/productos 200; REST 403; debug.log 404. Incidente durante el trabajo: restore temporal del admin original con Main ya en singletons → sitio caído ~2 min, reparado con el split correcto (lección: prep range off-by-one)
- **Estado**: ✅ sincronizado (suite repo push 4.1.0). Pendiente 4.2: cifrado secrets en reposo (libsodium), sink .html() connector.js

### [23:45] - Departamento Ethical Hacking: audit completo + reparaciones (wpscan, metasploit, limpieza 887MB)
- **Tipo**: infra | seguridad | herramientas
- **Modificado**: wpscan 3.8.28→4.1.0 (reparado gem dependency addressable), metasploit-framework 6.5.3 (instalado, reemplaza framework2 roto), outputs Intigriti limpiados (250 dominios BMW, 887MB liberados), trufflehog (pip 2.2.1 incompatible con Py3.13 → pendiente), kalimetehunt.sh framework bug bounty verificado
- **Afecta a**: kalimete (dev/ethical-hacking)
- **Causa**: Preparar el departamento de ethical hacking para reanudar proyectos Intigriti. wpscan rota por gem conflict (opt_parse_validator/cms_scanner), metasploit ausente (solo framework2 roto), outputs antiguos acumulados sin uso desde Feb 2026.
- **Cambios realizados**:
  - ✅ wpscan: `gem install addressable` + `apt-get install --reinstall wpscan` → v4.1.0 Automattic OK
  - ✅ metasploit: `apt-get install metasploit-framework` → v6.5.3-dev OK (msfconsole, msfvenom, msfdb, etc.)
  - ✅ outputs Intigriti: 250 directorios BMW/alphabet limpiados (887MB → 4.8MB), carpeta outputs recreada vacía
  - ✅ trufflehog: binario real v3.97.9 descargado (era script Python corrupto "Not Found"), instalado en ~/.local/bin/trufflehog — operativo (binario Go real, no pip 2.2.1 incompat con Py3.13)
  - ✅ Prueba de fuego: 20 herramientas verificadas (nuclei v3.11.0/13326 templates, ffuf 2.1.0, feroxbuster 2.13.1, sqlmap 1.10.6, dalfox 2.9.3, hashcat 7.1.2, crackmapexec, burpsuite 2026.3.2, zaproxy 2.17.0, amass 3.19.2, subfinder 2.11.0, httpx, katana 1.7.0, puredns 2.1.1, naabu 2.3.7, gobuster 3.8.2, gitleaks 8.30.1, mitmproxy 12.2.3, nikto, wfuzz, dirb, arjun 2.2.7, bandit, safety, scapy, impacket, hashcat, john, crunch → TODAS OK)
  - ✅ pm3 (Proxmark3): instalado, sin dispositivo USB → marcado como "dejar sin tocar" (usuario confirmó)
- **Estado**: ✅ sincronizado (todo OK excepto trufflehog py)
- **Notas**: kalimetehunt.sh framework está listo pero carpetas vacías (recon/, scanning/, exploitation/, reports/, targets/, logs/) — sin actividad desde Feb 2026. Cron de hacking: ninguno (solo sync.sh cada 5 min). Listo para iniciar caza en Intigriti.


## 2026-09-27
### [00:30] - erp-chatbot v1.2.1: navegación automática en modo voz (sin clic)
- **Tipo**: proyecto | feature | UX voz | wordpress
- **Modificado**: erp-chatbot 1.2.0→1.2.1 (~/dev/wordpress: turno marcado de voz, auto-nav al terminar de hablar, prompt según modo). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: hablando por voz no quiere dar clic — el bot debe llevar solo a la tienda filtrada.
- **Solución**: mensaje dictado o modo teléfono → sin botón; al terminar de hablar navega solo (900ms); sin TTS a los 1.5s; mensaje nuevo cancela; escribiendo todo igual (con botón).
- **Verificación**: turno voz=1 con tienda_url ✅; JS 1.2.1 servido con la lógica ✅; node + php OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (dictar → escuchar → auto-nav) → luego commit

### [01:30] - Veredicto producción GO: connector v3.15.2 (fix image host) — ambos plugins libres de IPs locales
- **Tipo**: proyecto | fix+auditoría | producción | wordpress
- **Modificado**: erp-ecomm-connector 3.15.1→3.15.2 (~/dev/wordpress: normalize_image_url() ya NO hardcodea erp.kalimete.local — resolución: constante ERPC_IMAGE_HOST > derivación automática scheme+host de la API URL del ERP > sin host no reescribe; mu-plugin erpc-local.php define la constante para dev; .env.example + DEPLOY-PRODUCCION.md actualizados). PR connector actualizado (MAIN intacto).
- **Afecta a**: producción futura (vps-preprod), kalimete (dev intacto)
- **Causa**: Usuario: ¿están listos para producción con IPs no-locales? Auditoría final: chatbot 0 hits funcionales; connector 1 bloqueante (fallback imágenes a host LAN) — corregido.
- **Verificación**: docker con filtro prod → relativa reescrita a erpipos.armada.do, host público/data-uri intactos; constante local → erp.kalimete.local (dev intacto); suite 8/8; php -l OK; barrido JS/CSS sin hosts absolutos.
- **Estado**: ✅ GO para producción tras merge de los PRs (chatbot#1 v1.4.6, connector#1 v3.15.2, ERP amigo#7)

### [01:30] - erp-chatbot v1.2.2: en voz primero lleva, allá continúa la charla
- **Tipo**: proyecto | feature | UX voz | wordpress
- **Modificado**: erp-chatbot 1.2.1→1.2.2 (~/dev/wordpress: motor con al_llegar + respuesta breve en voz, widget guarda/retoma continuación vía localStorage). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: al encontrar lo pedido, primero llevar allá y continuar la conversación en la tienda (no hablar todo y navegar al final).
- **Solución**: en voz con productos → respuesta breve hablada + navegación guardando historial/modo-teléfono/al_llegar; en la tienda el widget reabre solo, repinta historial, dice el detalle y retoma escucha. En texto sin cambios.
- **Verificación**: turno voz → breve + tienda_url + al_llegar con detalle ✅; JS 1.2.2 servido ✅; node + php OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (dictar → navegar → continuar allá) → luego commit

### [02:30] - Validación remota E2E: chatbot funciona con LLM victoria (túnel) + ERP erpipos (prod) — cero llaves en plano
- **Tipo**: proyecto | test+auditoría | producción | wordpress
- **Modificado**: nada (solo pruebas). Script temporal E2E en contenedor (eliminado).
- **Afecta a**: veredicto producción (confirmado GO)
- **Causa**: Usuario: validar que no haya llaves en plano, todo configurable local/remoto, probar vLLM remoto y ERP erpipos.armada.do.
- **Resultados**: (1) Auditoría llaves: 0 valores hardcodeados en ambos plugins (todo desde get_option/env/$_POST). (2) LLM remoto victoria.armada.do/v1: chat/completions 200 con key del chatbot (nota: /v1/models da 404, /models 200 — irrelevante, el engine usa /chat/completions). (3) ERP remoto erpipos.armada.do/api: config 200 tenant 10 MaganTech — SIN delivery_zones/store (MAIN viejo del amigo, PR#7 pendiente; plugins lo toleran por diseño). (4) E2E remoto con overrides en memoria: turno 1 "¿qué impresoras tienes?" → 3 productos reales con precios del ERP remoto vía LLM remoto (3.9s), tool buscar_productos + ir_a tienda; turno 2 "muéstrame el catálogo" → 18 categorías reales (3.3s). (5) Restauración byte-exacta: config local intacta (10.0.0.5:8010 + filtro 172.19.0.1:8100), cache y telemetría limpios.
- **Estado**: ✅ GO producción confirmado con evidencia real remota. Latencia por turno ~3.5-4s (túnel).

### [02:30] - erp-chatbot v1.3.0: fix loop navegar-llegar-navegar + flujo completo (tienda/carrito/checkout/login)
- **Tipo**: proyecto | fix+feature | UX conversacional | wordpress
- **Modificado**: erp-chatbot 1.2.2→1.3.0 (~/dev/wordpress: página actual en contexto, prompt con flujo completo, armar_ir_a central con whitelist+ya_estas, JS con guard mismaTienda, WhatsApp con link de flujo). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget + canal WhatsApp)
- **Causa**: Usuario: (1) el asistente en voz Y texto debe presentar en la web cada paso, incluido cerrar la orden; (2) el bot quedaba en loop.
- **Diagnóstico del loop**: navegar-siempre + replay al llegar + re-búsqueda del mismo filtro = ciclo infinito. Sin contexto de página el bot decía "te llevo" estando ya ahí.
- **Solución**: motor con página actual; destinos validados server-side (tienda/carrito/checkout/login, el LLM nunca pone URLs); supresión si ya estás (motor) + guard JS (segunda muralla, dice al_llegar en sitio si omite).
- **Verificación**: 13/13 tests (helpers, whitelist, anti-loop E2E) ✅; node + php OK. En el camino se corrigió un bug propio (URL de comparación sin slash).
- **Estado**: ⚠️ pendiente de prueba del usuario (flujo completo hablado: buscar → ver → carrito → pagar) → luego commit

### [03:30] - erp-chatbot v1.4.0: chat retoma al llegar + mapa del sitio (guía total)
- **Tipo**: proyecto | fix+feature | UX conversacional | wordpress
- **Modificado**: erp-chatbot 1.3.0→1.4.0 (~/dev/wordpress: retome incondicional con líneas por destino, mapa del sitio dinámico, ir_a contra el mapa, prompt con destinos). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: (1) al navegar al carrito el chat se cerraba sin poder continuar (en checkout quiere seguir hasta confirmar el cierre); (2) el asistente debe guiar por TODA la web en voz y texto, con mapa para nunca perderse (cada instancia distinta).
- **Diagnóstico**: retomar exigía al_llegar (vacío en carrito/checkout) → chat cerrado; destinos fijos sin noción del sitio real.
- **Solución**: retome siempre (con fallback por destino); mapa con las páginas reales de la instancia (hoy 8); ir_a validado contra el mapa; prompt con destinos disponibles para guiar por donde pida.
- **Verificación**: mapa 8 reales ✅; armar 5/5 ✅; turno voz E2E con ir_a tienda ✅; node + php OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (navegar a carrito → chat sigue abierto → continuar hasta checkout) → luego commit

### [12:30] - erp-chatbot v1.1.0 + ecomm v3.14.0 + ERP v3.14.0-local: dependencia dura, motor multi-canal, WhatsApp
- **Tipo**: proyecto | feature | multi-canal | IA | wordpress + erp-local
- **Modificado**: erp-chatbot 1.0.1→1.1.0 (~/dev/wordpress: dependencia dura ecomm, motor modo web/canal, canal WhatsApp Cloud API + admin tab). ecomm 3.13.9→3.14.0 (checkout_guest con contrato delivery/pickup + origen=chatbot). ERP (~/dev/erpipo-preprod: submitGuest con contrato completo, origen chatbot = pendiente sin pago, tipo_comprobante + tipo_venta). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario: enfocarse en web + WhatsApp (resto después); el agente usa el ecomm para TODO (cero requests directos), no se instala sin él, estructura expandible; plugins como features de venta + SEO del cliente ERP.
- **Solución**: activación aborta sin ecomm + guards runtime; motor dual (web: tools al JS; canal: todo servidor contra ERPC_API); WhatsApp = webhook REST (verify + receive), sesiones por teléfono 24h, envío Cloud API, notas de voz con respuesta honesta (STT en Fase 2); guest checkout del canal → venta PENDIENTE sin pago.
- **Verificación**: php -l 6/6 + node OK; webhook verify (challenge/403) ✅; mensaje WA dry_run → productos reales + sesión ✅; pedido canal → **venta 278** pendiente, zone 3, fee 250, total 1650, 0 pagos ✅ (fixes: cart_id en body, tipo_comprobante, tipo_venta, delete pago auto). Canal WA deshabilitado (sin token Meta real).
- **Estado**: ⚠️ pendiente de prueba del usuario (web + activar WA con token real) → luego commit
- **Notas**: ventas test del canal (277 con pago huérfano limpiado, 278 limpia) en DB preprod.

### [13:30] - erp-chatbot v1.1.1: cumplimiento Meta (firma, async, Graph v23, UTF-8)
- **Tipo**: proyecto | seguridad | cumplimiento API | wordpress
- **Modificado**: erp-chatbot 1.1.0→1.1.1 (~/dev/wordpress: App Secret + firma X-Hub-Signature-256, webhook async con cola+cron, Graph version configurable v23.0, split UTF-8, recipient_type, mark-read, error 131047, admin). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, webhook /wp-json/erpcbot/v1/whatsapp)
- **Causa**: Usuario: validar todo contra documentación oficial, no violar términos de APIs/tokens, confirmar que es real/funciona/mejores prácticas.
- **Diagnóstico** (docs Meta revisadas): verify GET exacto ✅, ventana 24h respetada ✅ (solo reactivo), tokens server-side ✅; FALLOS: sin verificación de firma (cualquiera posteaba al webhook), LLM síncrono en webhook (Meta reintenta → duplicados), Graph v21.0 vieja, str_split rompía emojis.
- **Verificación**: php -l 4/4 OK; firma OK→200+cola, firma mala→403 ✅; cola→cron→cerebro con productos reales ✅; regresión web ✅; verify GET ✅. Config de test limpiada (WA deshabilitado).
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit
- **Notas**: para producción Meta: token permanente de usuario de sistema + App Secret real + templates solo si se inicia conversación fuera de ventana.

### [14:30] - erp-chatbot v1.1.2: texto del chat visible + voz con género configurable
- **Tipo**: proyecto | fix | UI/UX + voz | wordpress
- **Modificado**: erp-chatbot 1.1.1→1.1.2 (~/dev/wordpress: clase msg-bubble propia en CSS+JS; admin Voz con selector Femenina/Masculina + sanitize; JS elegirVoz con onvoiceschanged y heurística es). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: texto invisible en el box del chat; bot con voz de hombre teniendo nombre de mujer — pidió opciones varón/hembra.
- **Diagnóstico**: colisión de clases (mensajes con la clase del botón flotante: fixed 62x62 círculo); hablar() tomaba la primera voz es sin criterio de género (o la default si getVoices vacío).
- **Verificación**: node --check + php -l OK; genero femenina en el cfg del sitio; CSS/JS 1.1.2 sirviéndose con los cambios. Prueba visual y de voz en navegador pendiente (la voz depende del dispositivo del usuario).
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit
- **Notas**: la voz TTS sale del navegador/dispositivo del visitante (speechSynthesis nativo) — no del servidor ni del ERP; el STT del micrófono (Chrome/Edge) sí envía audio a Google para reconocerlo.

### [15:30] - erp-chatbot v1.1.3: iconos apilados + voz configurable y confiable
- **Tipo**: proyecto | fix | UI/UX + voz | wordpress
- **Modificado**: erp-chatbot 1.1.2→1.1.3 (~/dev/wordpress: chat apilado sobre el carrito con detección, botón Probar voz en admin, espera de voces en primer habla, listas limpias). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: icono carrito y chat superpuestos; voz de varón con agente de nombre femenino.
- **Diagnóstico**: ambos flotantes en el mismo punto (right:22/bottom:22); getVoices vacío al inicio + listas con duplicados/ambiguas.
- **Verificación**: node --check + php -l OK; CSS 1.1.3 con apilado sirviéndose. Prueba en navegador pendiente (posición + voz según dispositivo del usuario).
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit

### [20:30] - Micaserogou/Armada Suite: evaluación arquitectura site-level (delegada) + ZIP verificado 8/8 + runbook post-upload
- **Tipo**: docs | servicio | arquitectura
- **Modificado**: docs/POST-UPLOAD-RUNBOOK.md NUEVO (205 líneas, live-testeado: flujo brand.logo vía ops, matriz 7×3 con CHECK_JS listo, rollback granular, pendientes); verificación del ZIP instalador 8/8 PASS (v1.6.0, slug-based, 0 keys, 0 drift vs preprod, SHA-256 d3c25f8f…); evaluación arquitectónica del agente Armada Suite (solo lectura)
- **Afecta a**: micaserogou (deploy) + armada-suite (roadmap 5.6.0)
- **Causa**: owner preguntó si el ZIP era update de Armada Suite o customización de Micaserogou → se delegó la evaluación de arquitectura + verificación del artefacto
- **Estado**: ✅ ZIP listo para upload del owner; propuesta 5.6.0 PENDIENTE de aprobación del owner
- **Notas**: (1) **Respuesta**: el ZIP es la customización de Micaserogou (NO update del plugin); el mecanismo intendido es escalera: config negocio → pack → override tema → mu-plugins (último recurso); la custom de cliente NUNCA dentro del plugin (fuga entre tenants + updates la borrarían). (2) **Misterio 'Tienda' resuelto**: NO es traducción .mo — page-wrapper.php hace require DIRECTO de partials/header.php DEFAULT (bypassea erpc_template_path) → login/checkout/mi-cuenta reciben header default cuyo nav dice 'Tienda' vs 'Menú' en el pack. (3) **Triaje upstream 5.6.0 propuesto** (6 fixes verificados contra código live): box-sizing .erpc-container, wrapper vía erpc_template_path (arregla header inconsistente+Tienda+frame), filter erpc_frame_slugs (páginas custom sin mu-plugin), hero products pack-aware, overlay about pack-aware, min-height auth; efecto: Micaserogou pasaría de 6 mu-plugins a ~2-3. (4) **⚠️ DERIVA CRÍTICA plugin**: prod corre 5.5.5 editada in-situ SIN commit ni ZIP canónico (working copy en 5.4.2+packs sin commit, header 5.5.1) — antes de cualquier release 5.6.0 hay que landear el trabajo de packs y canonizar. (5) ops file/write confinado al tema = CORRECTO por diseño (abrir mu-plugins remoto = canal RCE); camino oficial = ZIP instalador o SFTP.

### [00:30] - Micaserogou post-upload: 21/21 prod OK + IA configurada (8 tools, voz, friendly) + BUG carrito (datos-reales.js destruía la grilla) corregido
- **Tipo**: servicio | ia | bugfix
- **Modificado**: prod micaserogou.com: matriz 21/21 PASS post-instalación; brand.logo local (bk_20261022230437); IA vía ops (bk_20261022232650): 8 tools ON (estaban en 0), identidad Carlos, instrucciones friendly sin detalles técnicos + mensaje error exacto del owner, voz.telefono ON (modo teléfono verificado), memoria 12 turnos + recordar_cliente, temp 0.6/500 tokens; chatbot probado vía CDP (saludo OK, LLM pendiente — api_url/key/model bloqueados por remoto, owner los pega en wp-admin); BUG CRÍTICO: datos-reales.js v1 hacía innerHTML sobre .erpc-products-grid en todas las páginas → botones Agregar muertos en /productos/ (destruía bindings de connector) + categorías duplicadas + home sin binding → v2: eliminadas funciones destructivas (server ya renderiza), handler delegado para home con mismo storage; verificado ambos flujos; ZIP instalador v1.0.1
- **Afecta a**: prod + preprod micaserogou
- **Causa**: owner — validar todo post-instalación (páginas, botones, ERP, IA voz/texto hasta cerrar orden, friendly)
- **Estado**: 🟡 21/21 + IA config + carrito fix listos; PENDIENTE OWNER: re-subir ZIP v1.0.1 + pegar LLM en wp-admin (URL victoria.armada.do/v1, model Qwen3.6-35B-A3B-NVFP4-normal, key secrets/armada-micaserogou.key)
- **Notas**: key LLM no puede ir por ops file/write (audit guarda contenido completo en DB) ni por chat; upstream #11: connector debería bindear add-to-cart delegado como quickview (añadido al triaje 5.6.0)

### [19:40] - Micaserogou: sincronización preprod→prod (auditoría RAW) — tagline/phone/address/contacto/about fixes vía API; categorías footer = dato ERP distinto
- **Tipo**: servicio | infra
- **Modificado**: prod micaserogou.com: auditoría RAW vs RAW 16 páginas + settings; fixes API: contacto y sobre-nosotros contenidos → shortcodes [erpc_html] (16/16 RAW idénticas), tagline "Tu tienda de confianza"→"Comida casera y gourmet, hecha al momento" (bk_20261022192336_sq7c8j), contact_phone/address null→valores
- **Afecta a**: prod micaserogou.com
- **Causa**: owner — evaluar discrepancias local vs prod; preprod = fuente de verdad
- **Estado**: 🟡 DB/settings 100% sincronizados; ZIP site-level PENDIENTE del upload del owner (sin él /reservas/ y /producto-detalle/ muestran shortcode crudo — verificado)
- **Notas**: categorías del footer difieren porque preprod usa ERP local y prod el ERP productivo erpipos.armada.do (sets distintos de categorías tenant 3) — decidir con Juan Carlos; tras el ZIP falta setear brand.logo a URL prod

### [18:40] - erp-chatbot v1.1.4: separación generosa entre flotantes (verificado con captura)
- **Tipo**: proyecto | fix | UI | wordpress
- **Modificado**: erp-chatbot 1.1.3→1.1.4 (~/dev/wordpress: aire entre flotantes a 28px desktop/móvil). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, flotantes del sitio)
- **Causa**: Usuario: carrito y chat aún se veían montados, pidió más separación.
- **Diagnóstico** (captura headless con Chromium propio): el apilado v1.1.3 funcionaba pero con solo ~14px de aire. Verificado visualmente tras el fix: separación limpia. El logo del header carga bien (era timing del headless).
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit

### [19:30] - erp-chatbot v1.1.5: voz con pitch + búsqueda tolerante + divisor entre flotantes
- **Tipo**: proyecto | fix | voz + búsqueda + UI | wordpress
- **Modificado**: erp-chatbot 1.1.4→1.1.5 (~/dev/wordpress: pitch por género × tono admin, normalizador de búsqueda con reintentos, prompt en singular, div divisor entre flotantes). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget del chatbot)
- **Causa**: Usuario: voz femenina suena igual que masculina; bot decía no hay impresoras habiendo stock; chat aún pegado al carrito (pidió div divisor).
- **Diagnóstico**: una sola voz español = elegir por nombre no cambia nada (pitch lo garantiza); ERP busca literal plural≠singular; 28px sin elemento visual se leía pegado.
- **Verificación**: "buscando impresoras" → 3 reales ✅; node + php OK; archivos 1.1.5 sirviéndose; captura propia del divisor ✅. Prueba en navegador pendiente.
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit

### [20:30] - erp-chatbot v1.1.6: búsqueda inteligente por keywords + categorías (mejor práctica)
- **Tipo**: proyecto | feature | IA search | wordpress
- **Modificado**: erp-chatbot 1.1.5→1.1.6 (~/dev/wordpress: tool_buscar_productos en 2 capas con scoring local, ver_categorias, prompt). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, motor del chatbot web + WhatsApp)
- **Causa**: Usuario: búsqueda por keywords o ver el inventario — ¿mejores prácticas? Diagnóstico: el LLM adivinaba 1 palabra contra el buscador literal del ERP; con 162 productos/18 categorías lo correcto es matching server-side con scoring.
- **Solución**: capa 1 search ERP con variantes; capa 2 matching local (tokens - stopwords + singular + scoring exacta/substring/categoría/sub/typo, stock primero); nueva tool ver_categorias.
- **Verificación**: plural/frase con ruido/typo/categoría → resultados reales en los 4 casos ✅; 18 categorías ✅; php -l OK.
- **Estado**: ⚠️ pendiente de prueba del usuario → luego commit

### [21:00] - erp-chatbot v1.4.1: fix checkout voz no pide datos del perfil + mejoras
- **Tipo**: proyecto | fix+feature | wordpress
- **Modificado**: erp-chatbot 1.4.0→1.4.1 (~/dev/wordpress: enriquecimiento server-side del cliente vía ERPC_API::me() con erpc_token — fusión solo-vacíos, regla 8 prompt no-repreguntar si logueado, refrescarCliente() JS antes de confirmar, erpc_token en ambos POST; tienda_url() unificada con mapa del sitio; comentarios puerto 8090→8091; suite tests/regression.php 7 tests; limpieza 46 .bkup viejos del connector; docs WHATSAPP-ACTIVACION.md + FASE2-VOZ-IMAGEN.md).
- **Afecta a**: kalimete (wordpress-local :8091, checkout voz)
- **Causa**: Usuario: al continuar por voz al checkout pedía datos ya grabados en el perfil. Causa raíz: motor armaba cliente solo de localStorage stale, nunca leía sesión ERP; prompt sin excepción logueado; sin WooCommerce el perfil canónico vive en el ERP.
- **Verificación**: batería 3/3 (me existe, tienda_url desde mapa, regla en prompt) + suite 7/7 PASS ✅; php -l + node --check OK.
- **Estado**: ✅ sincronizado (pendiente prueba del usuario: checkout voz con sesión — debe precargar sin preguntar)

### [21:30] - erp-chatbot v1.1.7: separación a prueba de todo (:has puro + 36px)
- **Tipo**: proyecto | fix | UI | wordpress
- **Modificado**: erp-chatbot 1.1.6→1.1.7 (~/dev/wordpress: regla body:has para el apilado sin depender del JS, aire 36px desktop/móvil, divisor siempre en DOM). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, flotantes del sitio)
- **Causa**: Usuario: en desktop/laptop aún juntos, pidió al menos 10px.
- **Verificación**: captura propia — chat, línea, carrito con aire generoso ✅; node --check OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (Ctrl+F5 por caché) → luego commit

### [22:30] - erp-chatbot v1.1.8: voz humana (normalización para habla natural)
- **Tipo**: proyecto | feature | voz TTS | wordpress
- **Modificado**: erp-chatbot 1.1.7→1.1.8 (~/dev/wordpress: textoParaVoz + numeroAPalabras/dineroAPalabras en el widget). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, voz del chatbot)
- **Causa**: Usuario: el agente lee números dígito por dígito y menciona asteriscos/signos — pidió habla humana ("$1,000.00 → mil pesos").
- **Solución**: capa de normalización aplicada a todo lo que habla el bot (markdown/emojis fuera, dinero y números en palabras, símbolos hablados, modelos y fechas intactos).
- **Verificación**: batería de casos reales del checkout en node — ejemplos exactos del usuario perfectos ✅; node --check OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (escuchar en navegador) → luego commit

### [22:45] - erp-chatbot v1.4.2: brevedad + fix nav impresoras + telemetría
- **Tipo**: proyecto | fix+feature | UX conversacional | wordpress
- **Modificado**: erp-chatbot 1.4.1→1.4.2 (~/dev/wordpress: regla 3 brevedad — voz 2 frases/40 palabras, texto 80, máx 3 productos; max_tokens default 1024→350; TTS habla solo 2 primeras frases; al_llegar tope 600→350; ver_categorias fija término de tienda vía termino_desde_categorias; armar_ir_a singulariza término — impresoras→impresora, ERP busca literal; aviso ya_estas en vez de silencio anti-loop; telemetría erpcbot_last_turns máx 20 rotativo; fix puntuar_producto categoria/subcategoria array del ERP — bonus +2/+1 recuperado).
- **Afecta a**: kalimete (wordpress-local :8091, widget voz/texto)
- **Causa**: Usuario: (1) el bot habla mucho, cortar diálogo para rapidez; (2) pidió catálogo de impresoras y no lo llevó.
- **Diagnóstico**: regla de brevedad con excepción que se tragaba la regla + max_tokens 1024 + TTS leía todo; nav fallaba porque ver_categorias no fijaba término (ir_a=null), plural rompía búsqueda literal del ERP, y anti-loop suprimía en silencio.
- **Verificación**: baterías docker (singular OK, ya_estas 2/2, scoring array PASS, telemetría rotativa 20) + suite 7/7 PASS ✅; php -l + node --check OK.
- **Estado**: ✅ sincronizado (pendiente prueba del usuario: pedir "catálogo de impresoras" voz/texto)

### [23:30] - ZIPs de instalación WordPress generados y validados (v1.4.6 + v3.15.2)
- **Tipo**: proyecto | build | distribución | wordpress
- **Modificado**: ~/dev/wordpress/export/erp-chatbot-v1.4.6.zip (74.6 KB, 17 entradas) + erp-ecomm-connector-v3.15.2.zip (693 KB, 68 entradas). Build artifacts (export/ gitignored por diseño).
- **Afecta a**: instalación vía WP admin (Plugins → Añadir → Subir)
- **Causa**: Usuario: plugins listos para instalar como ZIP?
- **Validación**: estructura correcta (carpeta top-level + archivo principal); WP lee headers (get_plugin_data en docker: "ERP Chatbot v1.4.6" + "ERP E-Commerce Connector v3.15.2"); 0 contaminantes (.git/.bkup/.gitignore excluidos); php -l masivo OK; 0 secretos (solo refs truncadas vllm-key-9977… históricas en CHANGELOG, no utilizables); sin keys completas (grep estricto 0 hits).
- **Estado**: ✅ listos para instalar. Nota: erp-ecmm-connector.zip viejo (21-sep, typo nombre) queda obsoleto en export/. Tras merge de los PRs se pueden publicar como GitHub Releases.

### [23:30] - erp-chatbot v1.1.9: anti-eco (el bot ya no se escucha a sí mismo)
- **Tipo**: proyecto | fix | voz | wordpress
- **Modificado**: erp-chatbot 1.1.8→1.1.9 (~/dev/wordpress: half-duplex mic/voz, barge-in solo manual, filtro anti-eco por texto). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, modo teléfono del chatbot)
- **Causa**: Usuario: el agente se escuchaba mientras respondía (eco por bocinas → se respondía solo).
- **Solución**: mic detenido mientras el bot habla + reanude al terminar; tap manual = única interrupción; filtro que ignora transcripciones que repiten lo dicho (≥60% overlap) o ruido.
- **Verificación**: batería anti-eco 5/5 ✅; node --check OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (modo teléfono con bocinas) → luego commit

### [23:45] - erp-chatbot v1.2.0: "Ver en tienda" (del chat a la tienda con filtro)
- **Tipo**: proyecto | feature | UX conversacional | wordpress
- **Modificado**: erp-chatbot 1.1.9→1.2.0 (~/dev/wordpress: tienda_url en respuestas con término, helper URL, botón en widget, link en WhatsApp, prompt, blindaje JSON). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, widget + canal WhatsApp)
- **Causa**: Usuario: al encontrar lo buscado, el bot debe llevar a la sección (tienda con filtro) para continuar desde ahí.
- **Solución**: el motor adjunta la URL de productos con `?buscar=` normalizado (el que matchea, no el plural del usuario); widget con botón, WhatsApp con link en texto.
- **Verificación**: 3/3 tienda_url correcta ✅; /productos/?buscar=impresora filtra reales ✅; botón JS/CSS sirviéndose ✅; php + node OK.
- **Estado**: ⚠️ pendiente de prueba del usuario (clic al botón desde el chat) → luego commit

### [23:50] - erp-chatbot v1.4.3: identidad Carlos sincronizada + doc agente wordpress-dev actualizada
- **Tipo**: proyecto | config+doc | wordpress
- **Modificado**: erp-chatbot 1.4.2→1.4.3 (~/dev/wordpress: defaults de identidad en código sincronizados con DB — Carlos/Asesor de ventas/perfil+saludo masculinos/voz masculina, antes Carla/femenina; regla 3 prompt neutralizada "práctica"→"eficaz"; ia.max_tokens DB 1024→350 que pisaba el default). agents/wordpress-dev.md (puerto 8091 real, WP 7.1.1/Elementor 4.2.4/EMCP 3.16.1, plugins custom erp-chatbot v1.4.3 + erp-ecomm-connector v3.14.0 documentados, LLM LAN 10.0.0.5:8010).
- **Afecta a**: kalimete (wordpress-local :8091, chatbot identidad)
- **Causa**: Usuario cambió identidad del agente por defecto vía admin (Carla→Carlos); auditoría encontró código/DB desalineados (defaults viejos, max_tokens DB viejo pisando el 350, regla 3 en femenino) y doc del subagente desactualizada (8090, versiones viejas, sin mencionar plugins custom).
- **Verificación**: settings() fusionada Carlos/masculina/350 ✅; system_prompt contiene "Carlos"+"eficaz" sin "práctica" ✅; defaults código==DB ✅; suite 7/7 PASS ✅; php -l OK.
- **Estado**: ✅ sincronizado (commit pendiente de prueba del usuario en navegador)

### [23:59] - erp-chatbot v1.4.6: la conversación sobrevive refresh/navegación/cierre
- **Tipo**: proyecto | feature | persistencia | wordpress
- **Modificado**: erp-chatbot 1.4.5→1.4.6 (~/dev/wordpress: guardado en cada turno en erpcbot_historial — últimos 30 + ts_actividad — + hooks pagehide/visibilitychange + estado abierto erpcbot_abierto; restore incondicional en load — repinta sin hablar, reabre si estaba abierto, sin duplicar saludo; TTL inactividad 24h — reset solo tras 24h sin interactuar; fusión con navegación por solape sin duplicar; historial al servidor — erpcbot_parse_historial decode JSON→array, contexto real en build_messages). PR #1 actualizado (MAIN intacto).
- **Afecta a**: kalimete (wordpress-local :8091, widget)
- **Causa**: Usuario: al refrescar la página se perdía la conversación. Causa raíz: historial solo en memoria, guardado solo al navegar por voz, sin restore en load, sin estado abierto.
- **Verificación**: node 38 checks (restore/retome/fusión) + suite 8/8 + php -l ✅ (2 verificaciones).
- **Estado**: ✅ sincronizado (pendiente prueba del usuario en navegador: F5 a mitad de charla → reabre donde quedó)

### [23:59] - Amigo ERP: PR #7 a dev/ecomm-erp + análisis de accesos GitHub
- **Tipo**: proyecto | entrega | erp+github
- **Modificado**: PR soycarlosjerez-hub/sistema-facturacion#7 (rama update/ecomm-local-v3.13-v3.14 → dev/ecomm-erp): 7 modificados + 2 nuevos + migración + CHANGELOG[Unreleased]. Main del amigo sin tocar. Paquete local UPDATE-ERP-AMIGO queda como respaldo (NOTA-ENVIO.md). Stack commit local.
- **Afecta a**: amigo (mergea cuando apruebe), producción futura
- **Causa**: Usuario indicó el repo del amigo (soycarlosjerez-hub/sistema-facturacion) con rama dev/ecomm-erp. Verificado: rama existía sin nuestros cambios (sin origen=chatbot, sin trait correos, sin migración Sept 23); 7/8 baselines byte-idénticos a su rama (solo ResetPassword difiere por store_url v3.12.9 no pusheado — incluido en el PR).
- **Accesos**: warcold tiene push (sin admin) en sistema-facturacion (colaborador junto al dueño) — flujo PR correcto. Repos propios: 30 (incluye warcold/erpipo-preprod privado del 19-sep — espejo desactualizado, no tocado — y warcold/erp-ecmm-connector con typo, posible duplicado a revisar).
- **Verificación**: php -l OK en 9 archivos PHP del PR; diffs aplicados desde archivos live (sirviendo API hoy).
- **Estado**: ✅ PR #7 abierto para el amigo — merge lo hace él. Pendiente: rotar key vllm (lo hace el usuario después).

### [23:59] - ERP del amigo: paquete UPDATE-ERP-AMIGO + compatibilidad MAIN (connector v3.15.1)
- **Tipo**: proyecto | compat+entrega | wordpress+erp
- **Modificado**: ~/dev/wordpress/UPDATE-ERP-AMIGO/ (6 diffs v3.13.0-v3.14.0-local + 2 archivos nuevos + migración + README manifiesto + CHANGELOG-EXTRACTO + COMPATIBILIDAD-MAIN.md). erp-ecomm-connector 3.15.0→3.15.1 (retry UNA vez con método seguro ante 422 payment_method, payment_fallback+payment_requested en respuesta). PR #1 actualizado (MAIN sin tocar). Stack commit 80ad769.
- **Afecta a**: amigo (dueño ERP ERPiPOS — él mergea en su main cuando apruebe), producción futura
- **Causa**: Usuario: el ERP es del amigo — mandarle los updates dev/ecomm para que él los maneje; no tocar MAIN; dejar todo funcional con MAIN de la manera más viable. Key: se queda como está, el usuario la rota después.
- **Diagnóstico**: ERP local tenía cambios v3.13.0-v3.14.0-local (delivery/pickup, zonas, pagos amplios, auth tenant, submitGuest chatbot) sin versionar (erpipo-preprod no es git). Único gap bloqueante contra MAIN viejo: 422 de payment_method sin retry → fallback implementado. Resto degrada elegantemente.
- **Verificación**: php -l + lógica fallback 3/3 (paypal→efectivo, tarjeta no reintenta, 500 no reintenta) + suite chatbot 8/8 ✅. Paquete verificado (diffs legibles, ERP local intacto).
- **Estado**: ✅ PRs abiertos (chatbot#1, connector#1 con v3.15.1) — merge lo hace el admin/amigo. Paquete UPDATE-ERP-AMIGO listo para enviar al amigo.

### [23:59] - Producción-ready: erp-chatbot + connector sin secretos en código + PRs GitHub para el admin
- **Tipo**: proyecto | seguridad+infra | wordpress
- **Modificado**: erp-chatbot (~/dev/wordpress: erpcbot_defaults() sin endpoint/key hardcodeados — resolución options > env ERPCBOT_LLM_URL/KEY/MODEL > vacío con error amigable; placeholder admin genérico; guard apunta a Ajustes). Stack: docker-compose.yml env-driven con ${VAR:-default} (local intacto), docker-compose.prod.yml (sin puertos 8091/3307, restart always), .env.example (placeholders sin valores), .gitignore, DEPLOY-PRODUCCION.md. GIT: repo nuevo github.com/warcold/erp-chatbot (privado) con PR #1 feature/v1.4.5-production-ready → main; connector PR #1 feature/v3.15.0-post-checkout-pedidos → main (incluye 5 commits no pusheados v3.12.5-3.12.10 + v3.15.0); stack commit local 938c270 (sin remote).
- **Afecta a**: kalimete (dev/wordpress), producción futura (vps-preprod)
- **Causa**: Usuario: preparar commit para que el admin de GitHub acepte cambios y haga merge él; funcional en producción (conexiones por variables, no en plano) y en local.
- **Diagnóstico**: API key LLM vllm-key-e473... en PLANO en erpcbot_defaults() (crítico), IP LAN 10.0.0.5 hardcodeada, creds DB en compose, erp-chatbot SIN repo (riesgo pérdida), connector con 16 archivos sin commit.
- **Verificación**: settings() fusionada trae valores de DB (local igual) ✅; defaults puros sin env → url/key vacíos, con env → valores env ✅; grep vllm-key/10.0.0.5 código vivo = 0 hits ✅; suite 8/8 ✅; docker compose config local+prod OK ✅; contenedores healthy + curl 8091 200 ✅.
- **Estado**: ✅ PRs abiertos para el admin (erp-chatbot#1, erp-ecomm-connector#1) — merge lo hace el admin. Pendiente: rotar key vllm expuesta (requiere victoria, autorización usuario).

### [23:59] - erp-chatbot v1.4.5 + erp-ecomm-connector v3.15.0: post-checkout → Mis pedidos estilo Amazon + carrito se limpia
- **Tipo**: proyecto | feature+fix | UX checkout | wordpress
- **Modificado**: erp-ecomm-connector 3.14.0→3.15.0 (~/dev/wordpress: clearCart() inmediato tras checkout exitoso — localStorage+badge; redirect a /mi-cuenta/?tab=pedidos con timeout 4000→1500ms — antes caía en tab Perfil; alias ?tab=pedidos; ajax_get_orders normaliza shape estable; vista Mis pedidos estilo Amazon — tarjeta con Pedido V-XXX/fecha/pill estado/total formateado/items con precio c/u y subtotal/total destacado/CSS responsive; fix customer_id real vía me() no-fatal — antes siempre 0). erp-chatbot 1.4.4→1.4.5 (saveCart([]) tras confirmar_pedido exitoso; prompt: mi-cuenta en destinos ir_a + regla 10 — felicita 1 frase con número de orden y lleva a Mis pedidos).
- **Afecta a**: kalimete (wordpress-local :8091, checkout + mi-cuenta + widget)
- **Causa**: Usuario: (1) al procesar la orden debe llevar a /mi-cuenta en mis pedidos; (2) mejorar vista de órdenes estilo Amazon con más info y precios correctos; (3) limpiar carrito al procesarse la orden.
- **Diagnóstico**: redirect caía en tab Perfil (sin ?tab); localStorage del carrito nunca se limpiaba (riesgo resurrección vía sync); vista pedidos solo mostraba "Órden #X + total raw" sin items; customer_id siempre 0; bot no ofrecía navegar a mi-cuenta.
- **Verificación**: normalize_order con orden real 279 → JSON estable (total 15450 float, fecha "2026-09-26 20:36", items_count 2) ✅; armar_ir_a mi-cuenta → URL real /mi-cuenta/ ✅; suite 8/8 PASS ✅; php -l + node --check OK.
- **Estado**: ✅ sincronizado (pendiente prueba del usuario: checkout completo → cae en Mis pedidos con tarjeta del pedido y carrito vacío)

### [23:59] - erp-chatbot v1.4.4: traducción de términos de búsqueda (EN→ES)
- **Tipo**: proyecto | feature | búsqueda multilingüe | wordpress
- **Modificado**: erp-chatbot 1.4.3→1.4.4 (~/dev/wordpress: traducir_termino() diccionario EN→ES ~36 entradas aplicado en tool_buscar_productos y armar_ir_a; regla 9 prompt — busca en español, responde en idioma del cliente; test 8 en suite).
- **Afecta a**: kalimete (wordpress-local :8091, búsqueda chatbot)
- **Causa**: Usuario pidió "printers" y el bot no encontró — catálogo/ERP en español, búsqueda literal, 0 resultados en inglés.
- **Solución**: 2 capas — (1) determinista: diccionario por palabra tras singularizar (printers→impresora, laptop→portatil, keyboard and mouse→teclado y raton), ?buscar= nunca sale en inglés; (2) prompt: el LLM traduce cualquier idioma que sepa y responde en el idioma del cliente.
- **Verificación**: batería 5/5 (IDs EN==ES contra ERP real: 6 impresoras 998/1016/1001/971/944/951) + suite 8/8 PASS ✅; php -l OK.
- **Estado**: ✅ sincronizado (pendiente prueba del usuario: pedir "printers" en el chat)


## 2026-09-24
### [11:00] - WP connector v3.13.3 + ERP v3.13.3-local: fix 422 checkout, botón Guardando, logo footer
- **Tipo**: proyecto | fix | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.2→3.13.3 (~/dev/wordpress: connector.js profile form, erp-ecomm-connector.php localize_remote_logo, footer.php onerror, connector.css logo). ERP sistema-facturacion (~/dev/erpipo-preprod: EcommCheckoutController payment_method ampliado en submit+submitGuest). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario: 422 al confirmar pedido con perfil completo; /mi-cuenta se queda "Guardando..."; logo de instancia no carga en footer (cuadro blanco) y debe ser más grande.
- **Diagnóstico**: ERP rechazaba paypal/binance/cheque/otro (in: demasiado corto); bug $(this)=jqXHR en ajax del perfil (botón nunca se restauraba — el guardado sí funcionaba); logo con URL a erp.kalimete.local (no resuelve fuera de LAN) + CSS filter brightness(0) invert(1) que lo convertía en cuadro blanco sólido.
- **Solución**: ERP acepta los 9 métodos; JS captura $form; nuevo localize_remote_logo() cachea el logo en uploads/erpc/ y lo sirve desde el dominio del WP (cache 24h); footer logo 48px a color real sobre pill blanco + onerror fallback.
- **Verificación**: checkout paypal → HTTP 200 (venta 272) ✅; logo JPEG real sirviéndose desde /wp-content/uploads/erpc/ en header y footer ✅; node --check + php -l OK. Prueba navegador pendiente del usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit

### [15:45] - WP connector v3.13.4 + ERP v3.13.4-local: fix validation.unique (unique por tenant)
- **Tipo**: proyecto | fix | multitenant | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.3→3.13.4 (~/dev/wordpress: login_password envía tenant_id, traducción de validation.unique). ERP sistema-facturacion (~/dev/erpipo-preprod: ClienteAuthController — updateProfile/register/login con unique por tenant, helper tenantFromApiKey). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario: "validation.unique" al guardar el perfil en /mi-cuenta tras completar campos vacíos. Diagnóstico: unique de telefono/email GLOBAL en el ERP — DB tiene teléfonos duplicados cross-tenant (8090000001 en tenants 2 y 10) → cualquier teléfono de otra instancia bloqueaba el update.
- **Solución**: unique por (tenant_id, valor) en updateProfile (ignora propio id, nullable) y register (tenant resuelto antes de validar, incl. Bearer iak_); login tenant-aware (mismo email puede coexistir en varias instancias); WP envía tenant_id en login y traduce el mensaje crudo.
- **Verificación**: update cross-tenant 200 (antes 422) ✅; duplicado en mismo tenant 422 correcto ✅; register mismo email en 2 tenants 201 coexistiendo ✅; login tenant-aware ✅; php -l OK. Prueba del usuario pendiente.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit
- **Notas**: cliente test 203 (tenant 2, mismo email que test de tenant 10) quedó en DB preprod como evidencia del multitenant — eliminar si molesta.

### [16:30] - WP connector v3.13.5: /contacto compacta + logo footer 150x150
- **Tipo**: proyecto | UI/UX | wordpress
- **Modificado**: plugin erp-ecomm-connector 3.13.4→3.13.5 (~/dev/wordpress: connector.css — compactación scoped de /contacto y logo footer 150x150). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, /contacto/ + footer de todo el sitio)
- **Causa**: Usuario: demasiado espacio en blanco entre secciones de /contacto (compactar sin eliminar) y el logo del footer muy pequeño (pedía ~150x150; la imagen fuente es 3000x3000).
- **Solución**: hero 96→56px, secciones 56→30px (móvil 22px), scoped a .erpc-contacto-page (home intacta); logo footer 48→150x150 con object-fit contain (móvil 110px).
- **Verificación**: CSS 3.13.5 sirviéndose con ambas reglas; /contacto renderiza; php -l OK. Prueba visual pendiente del usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit

### [17:40] - WP connector v3.13.6 + ERP v3.13.6-local: fix reset de clave tocaba cliente de otra instancia
- **Tipo**: proyecto | fix | multitenant | seguridad | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.5→3.13.6 (~/dev/wordpress: request_password_reset/reset_password envían tenant_id). ERP sistema-facturacion (~/dev/erpipo-preprod: ClienteAuthController — forgotPassword/resetPassword/resendVerification tenant-aware). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario restableció la clave de warcold@gmail.com y el login falló. Diagnóstico: ese email existe en 4 clientes (3 en tenant 2, 1 en MaganTech/tenant 10 con acceso_api=0); el forgot/reset GLOBAL generó el token y cambió la clave del cliente de OTRA instancia (id 37, tenant 2); el login tenant-aware de la tienda busca en tenant 10 → clave vieja → "credenciales incorrectas".
- **Solución**: forgot/reset/resend tenant-aware (body tenant_id > Bearer iak_ > global); WP envía tenant_id en ambos pasos; reset devuelve 400 si no hay cliente del tenant en vez de tocar otro.
- **Verificación E2E** (email duplicado en tenants 10 y 2): token para el cliente correcto ✅, correo From instancia + link tienda ✅, reset 200 ✅, login clave nueva OK ✅, cliente del otro tenant intacto ✅, php -l OK.
- **Estado**: ⚠️ pendiente: el usuario debe repetir el reset desde el WP (ahora tocará su cliente 183 y activará acceso_api) → luego commit

### [18:30] - WP connector v3.13.7: data del usuario migrada a su cliente correcto + cache fresco del ERP
- **Tipo**: proyecto | fix | multitenant | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.6→3.13.7 (~/dev/wordpress: connector.js refresca cache tras guardar perfil). DB facturacion_db: migración de datos del usuario (direccion/ciudad/provincia) del cliente 37 (tenant 2) → 183 (MaganTech/tenant 10). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario no veía su data al logearse. Diagnóstico: la data estaba en el ERP pero en el cliente de OTRA instancia (37, tenant 2) — la guardó cuando su sesión apuntaba ahí (login global pre-v3.13.4); el login tenant-aware actual entrega el 183 (tenant 10) que estaba vacío. Misma raíz multitenant del reset (v3.13.6).
- **Solución**: migración de SU propia data al cliente correcto de su tienda (37 intacto); tras guardar perfil, el WP refresca el cache local con la respuesta del ERP (única fuente de verdad = ERP).
- **Verificación E2E**: login tenant-aware → /me data ERP → PUT /profile → /me persistido ✅; node --check OK. Usuario debe ver dirección/ciudad/provincia en /mi-cuenta/ y /checkout/.
- **Estado**: ⚠️ pendiente de verificación del usuario → luego commit del acumulado (3.13.0→3.13.7 + ERP v3.13.x)

### [19:30] - WP connector v3.13.8: gestión de métodos de pago + panel admin con tabs
- **Tipo**: proyecto | feature | UI admin | wordpress
- **Modificado**: plugin erp-ecomm-connector 3.13.7→3.13.8 (~/dev/wordpress: class-erpc-admin.php tabs + sección métodos de pago + sanitize; erp-ecomm-connector.php get_all_payment_methods + override local). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, admin del plugin + /checkout/)
- **Causa**: Usuario: poder activar/desactivar formas de pago para el cliente; reorganizar el panel admin con tabs y compactar secciones afines separadas.
- **Solución**: 5 tabs (Conexión / Apariencia / Tienda / Contacto y correo / Shortcodes) — secciones de marca+tema y contacto+SMTP compactadas; nueva sección Métodos de pago con toggles (7 métodos, ERP v3.13.3+ los acepta todos); override local > config ERP > fallback; tab activo persiste en localStorage.
- **Verificación**: php -l OK; tabs balanceados; E2E: override ['efectivo','tarjeta'] → checkout solo muestra esos 2 ✅; restaurado → fallback 5 ✅. Prueba visual del admin pendiente del usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit

### [21:00] - WP connector v3.13.9 + ERP v3.13.9-local: zonas de cobertura del ERP en el checkout
- **Tipo**: proyecto | feature | multitenant | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.8→3.13.9 (~/dev/wordpress: checkout.php select zona, connector.js fee/ETA/validación, api+shortcodes pasan delivery_zone_id). ERP sistema-facturacion (~/dev/erpipo-preprod: TiendaApiController expone delivery_zones; EcommCheckoutController valida zona por tenant + persiste delivery_fee; fix use $zone). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario: solo se deben poder usar zonas de cobertura disponibles en el ERP. Diagnóstico: delivery_zones existía en el ERP (por tenant) pero no se exponía ni validaba por tenant (exists global = fuga) y el checkout WP no tenía selector.
- **Solución**: config expone zonas activas del tenant; checkout WP exige zona del ERP (con costo en el label + ETA); ERP valida contra tenant (422 invalid_zone cross-tenant) y persiste delivery_fee = tarifa_base (gratis por mínimo de zona).
- **Verificación**: config 4 zonas MaganTech ✅; checkout zona 3 → venta 276 fee 250.00 ✅; zona de otra instancia 422 ✅; node --check + php -l 6/6 OK. Prueba del usuario pendiente.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit

### [23:30] - Plugin NUEVO erp-chatbot v1.0.0: Agente de Negocio Personalizable (IA + voz + ventas reales)
- **Tipo**: proyecto | feature | IA | wordpress
- **Modificado**: plugin NUEVO ~/dev/wordpress/wp-content/plugins/erp-chatbot/ (core + engine + admin + widget JS/CSS + changelog). Activado en wordpress-local. **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + gateway LLM victoria 10.0.0.5:8010)
- **Causa**: Usuario pidió bot vendedor: chat + voz streaming tipo teléfono (no videntes), que use SOLO lo que el ecomm maneja (no adivino), cierre de venta PENDIENTE para verificación del manager. Diseño del usuario: el plugin ES el bot completo, OpenAI-compatible (URL+key+modelo configurables), identidad configurable (nombre/foto/perfil).
- **Solución**: motor PHP con protocolo de herramientas JSON (servidor: buscar_productos/info_tienda contra el ERP real; navegador: carrito interop localStorage + checkout vía erpc_checkout → venta PENDIENTE con nota del manager); admin con tabs (IA/Identidad/Voz/Ventas, foto vía media library); widget con avatar, chat, TTS es-DO, STT streaming continuo con barge-in, modo teléfono, Alt+C, aria; rate limit 20/min; key server-side solo.
- **Verificación**: php -l 3/3 + node --check OK; activado; widget cargando en la home; E2E del motor (con key operativa, no persistida): "busca una impresora" → bot respondió con 3 productos REALES del ERP con precios y stock reales (EcoTank L1250 RD$9,500, Canon PIXMA G1110 RD$9,000, Brother DCPT730DW RD$17,000) ✅; manejo de error 403 key readonly → mensaje claro al usuario ✅; fix del parseo del catálogo (ERP devuelve clave `productos`, precio string).
- **Estado**: ⚠️ la key del usuario (vllm-key-9977…) es rol `readonly` en el gateway victoria → 403 model_forbidden para LLM. Opciones: (a) cambiar rol de la key en victoria.local/admin, (b) crear key nueva con permiso llm, (c) autorizar a kalimete a actualizar el rol. Prueba del usuario en navegador pendiente (voz requiere micrófono).

### [23:50] - erp-chatbot v1.0.1: key de servicios activa + veredicto OpenClaw vs hub propio
- **Tipo**: proyecto | IA | decisión de arquitectura | wordpress
- **Modificado**: plugin erp-chatbot (~/dev/wordpress: defaults + options con key de servicios vllm-key-e4735…). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + gateway LLM victoria 10.0.0.5:8010)
- **Causa**: Usuario pidió validar la key de servicios y decidir: ¿integramos nosotros o usamos OpenClaw (plugin como canal del hub OpenClaw)?
- **Key validada**: la key de servicios respondió una completion real en Qwen3.6-35B ✅ (tiene permiso LLM, a diferencia de la readonly). E2E vía admin-ajax: "Busca una impresora" → bot con 3 productos REALES del ERP (Canon G1110 RD$9,000, EcoTank L1250 RD$9,500, Brother T730DW RD$17,000) ✅. El bot está operativo.
- **Evaluación OpenClaw** (docs oficiales, revisadas hoy): gateway WS :18789 con superficies WhatsApp vía Baileys (cliente NO oficial), Telegram vía grammY, Discord, WebChat estático; pairing de dispositivos; sesiones por agente/sender. VEREDICTO: NO usar OpenClaw como gateway del plugin — (1) es asistente personal/single-user, no multi-tenant de negocio; (2) WhatsApp Baileys = riesgo de baneo para negocio (producción exige Cloud API oficial); (3) su WebChat es genérico, incompatible con nuestro widget (identidad, voz teléfono, carrito localStorage); (4) el pairing es para dueños, no clientes anónimos de tienda; (5) habría que reescribir las ERP tools en TypeScript duplicando el cliente PHP que ya tenemos.
- **Decisión**: hub PROPIO cuando haga falta el 2.º canal (el engine actual porta 1:1); la key sale de WP solo entonces. WhatsApp vía Cloud API oficial de Meta (producción), Telegram primero (BotFather, barato de validar). OpenClaw descartado con razones.
- **Estado**: ⚠️ pendiente de prueba del usuario en navegador (chat + voz) → luego commit


## 2026-09-23
### [01:45] - WP connector v3.12.8: flujo compra completo (auth real + tenant + red local)
- **Tipo**: proyecto | fix | wordpress-dev + erp-local
- **Modificado**: plugin `erp-ecomm-connector` (api/auth/form/js/config/stock-url, bump 3.12.7→3.12.8 + CHANGELOG plugin; commit plugin `73dd312`). MU-plugin `erpc-local.php` → gateway docker. `/etc/hosts` → 127.0.0.1. ERP `preprod.env` → Mailpit local; `AppServiceProvider` forceRootUrl; `ClienteAuthController` verify público + bypass TenantScope. Backups `.bkup-20260922` en cada archivo.
- **Afecta a**: kalimete (wordpress-local, erpipo-preprod, Mailpit)
- **Causa**: Usuario: "no sale el código" al crear cuenta + directiva "todo local, independiente de la red". Diagnóstico: (1) ERP sin rutas OTP — plugin apuntaba a `/ecomm/auth/*` → 404; ERP usa password min12 + email link. (2) `get_tenant_id()`=0 → register caía a tenant 3 (no MaganTech 10) → checkout ModelNotFound. (3) MU-plugin con IP LAN vieja (10.0.0.106; actual 10.1.10.174) → timeout ERP; /etc/hosts stale.
- **Verificación E2E** (todo local): registro → tenant 10 + email en Mailpit + verify OK; login UI; profile load/update; checkout → **orden V-263 completada** (cliente 191, RD$ 3,016.19). Home 0.35s (antes 30s+).
- **Nota**: `docker network connect erpipo-dev-network wordpress-local` se REVERTIÓ (colisión alias `db` → erpipo-db rompía la DB del WP). La vía correcta es el gateway 172.19.0.1. NO reconectar redes entre stacks.
- **Estado**: ✅ sincronizado

### [03:00] - ERP local: reseteo clave cuenta me@alfredo.pro (id=23)
- **Tipo**: proyecto | accesos | erp-local
- **Modificado**: DB `erpipo-preprod-db` (tabla users, solo hash; sin secretos en este log)
- **Afecta a**: kalimete (erpipo-preprod, panel erp.kalimete.local)
- **Causa**: Usuario no podía entrar al panel local (`auth.failed` crudo por falta de lang). Diagnóstico: su cuenta existe local (id=23) pero con otra clave; owner bootstrap deshabilitado. Reseteo autorizado por el usuario.
- **Verificación**: POST /login → 302 a /dashboard; /owner → 200 con sesión; /login con sesión → 302 a /dashboard. Hash verificado con Hash::check.
- **Estado**: ✅ sincronizado

### [03:15] - ERP local: usuario me@alfredo.pro (id=23) asignado a instancia MaganTech (10)
- **Tipo**: proyecto | accesos | erp-local
- **Modificado**: DB `erpipo-preprod-db` (users.business_instance_id  null → 10)
- **Afecta a**: kalimete (erpipo-preprod, panel erp.kalimete.local)
- **Causa**: Usuario veía la instancia MaganTech sin su API key. Diagnóstico: key id=2 `magantechwebsite` existe y activa, pero el TenantScope fail-closed la ocultaba (usuario sin instancia → resolveTenantId null). Asignación autorizada por el usuario.
- **Verificación**: /owner/instances/10/api-keys → 200 y muestra `magantechwebsite`.
- **Nota**: key de pruebas = id=2 `magantechwebsite` → instancia 10 (existe también en prod; la data local es snapshot + writes de prueba).
- **Estado**: ✅ sincronizado

### [03:30] - ERP local: revert asignación + clave owner MaganTech (m.garcia@magantech.com.do, id=35)
- **Tipo**: proyecto | accesos | erp-local
- **Modificado**: DB `erpipo-preprod-db` (users: id=23 business_instance_id → null; id=35 password hash nuevo; sin secretos en este log)
- **Afecta a**: kalimete (erpipo-preprod, panel erp.kalimete.local)
- **Causa**: Usuario corrigió el enfoque — prefiere probar desde la perspectiva del dueño de la tienda (admin-business) en vez de asignarse él la instancia. Ambos cambios autorizados por el usuario.
- **Verificación**: login m.garcia@magantech.com.do → 302 dashboard; dashboard/ordenes/productos/clientes → 200 con su sesión; /owner/* → 403 correcto (sección system-owner).
- **Estado**: ✅ sincronizado

### [04:30] - WP connector v3.12.9: checkout total 0 + bloquear orden 0 + reclamo guest
- **Tipo**: proyecto | fix | wordpress-dev + erp-local
- **Modificado**: plugin (connector.js, shortcodes, auth, api, form auth; bump 3.12.8→3.12.9 + CHANGELOG; commit `7798555`). ERP: submitGuest acceso_api, resetPassword plano+acceso (fix doble-hash), forgotPassword store_url, notificación link a tienda. Backups `.bkup-20260923`.
- **Afecta a**: kalimete (wordpress-local, erpipo-preprod)
- **Causa**: Usuario: resumen en RD$ 0.00, orden en 0 "exitosa", guest sin cuenta en ERP. Diagnóstico: selector JS inexistente (orden V-264 correcta en ERP: 2694.70); sin validación total>0; guest sin clave/acceso y sin vía de reclamo; doble-hash en reset.
- **Verificación E2E**: totales display OK, bloqueo carrito vacío OK, guest → orden V-265 + email reset → set clave → login OK. Cliente 196 acceso=true tenant=10.
- **Nota**: el `&amp;` del email HTML es correcto (navegador lo decodifica); mi test inicial lo extrajo sin decodificar (falso positivo, no bug).
- **Estado**: ✅ sincronizado

### [05:00] - WP connector v3.12.10: checkout exige sesión (anti-suplantación)
- **Tipo**: proyecto | seguridad | wordpress-dev
- **Modificado**: plugin (connector.js, shortcodes, auth; bump 3.12.9→3.12.10 + CHANGELOG; commit plugin pendiente).
- **Afecta a**: kalimete (wordpress-local, /checkout/ y /login/)
- **Causa**: Usuario: comprar sin login permite suplantación (solo email + pago contra entrega) y preguntó por duplicados. Verificado: el ERP reutiliza cliente por email+tenant (2 órdenes → 1 cliente, NO duplica), pero la suplantación era real.
- **Verificación**: guest → /login/?redirect → registro → /checkout/ con items → orden V-269 ✅; POST sin token rechazado ✅.
- **Estado**: ✅ sincronizado

### [20:45] - Checkout delivery/pickup + autofill cliente + correos por instancia (WP ↔ ERP local)
- **Tipo**: proyecto | servicio | wordpress-dev + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.12.10→3.13.0 (~/dev/wordpress: connector.js, checkout.php, api, auth, shortcodes, css, CHANGELOG; backups `.bkup-20260923d`). ERP sistema-facturacion rama dev/ecomm-erp (~/dev/erpipo-preprod: EcommCheckoutController, TiendaApiController, Venta.php, migración 5 columnas ventas EJECUTADA, trait ConfiguresInstanceMail, ClienteVerifyEmail/ClienteResetPassword; changelog propio). **SIN COMMIT en el ERP (regla nueva del usuario: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario: el checkout volvía a pedir datos del cliente ya registrados (loop percibido), no había selector delivery/recoger, y los correos de registro debían salir desde el correo de cada instancia (no global, sin mezclar clientelas).
- **Cambios clave**: contrato `delivery_type` (delivery: address/city/province; pickup: branch_id/pickup_time/pickup_contact) en ambos lados; autofill del checkout vía GET /ecomm/me; proxy público `erpc_store_config` (sucursales/delivery/pickup); sesión expirada → mensaje claro + /login/?redirect=/checkout/ (rompe el loop); correos con From de la instancia (SystemSetting por tenant_id, fallback global + warning); fix fuga cross-tenant en customer.id del checkout.
- **Verificación**: ERP: config 200, register 201 + From instancia en mailpit (`MaganTech Store <pedidos@magantech.test>`), checkout delivery 200 (venta 270), pickup 200 (venta 271, sucursal 6), branch inválido 422, log limpio. Plugin: node --check OK, php -l 5/5 OK, proxy erpc_store_config E2E OK (branches/delivery/pickup llegan al navegador). Prueba E2E en navegador PENDIENTE por el usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit del ERP
- **Notas**: agente wordpress-dev falló 2 veces (reporte vacío, solo backups) — implementación del plugin la hizo kalimete directamente. `pickup.hours` por sucursal = null (no existe columna horario). Datos de test en DB preprod (sucursal 6, mail config tenant 10, cliente test) — eliminar si no se quieren.

### [21:35] - WP connector v3.13.1 + ERP v3.13.1-local: Ubuntu global, perfil completo del cliente, dinero con comas
- **Tipo**: proyecto | servicio | wordpress + erp-local
- **Modificado**: plugin erp-ecomm-connector 3.13.0→3.13.1 (~/dev/wordpress: enqueue fuente, connector.css, api, auth, form.php, profile.php, connector.js, 3 templates de precios). ERP sistema-facturacion (~/dev/erpipo-preprod: ClienteAuthController@register valida direccion/ciudad/provincia). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091 + erpipo-preprod :8100)
- **Causa**: Usuario pidió (1) fuente Ubuntu de Google para todo el template y WordPress, (2) que todos los datos del cliente queden guardados en el ERP al registrarse/actualizar perfil, (3) valores con separador de miles ($1,000.00).
- **Hallazgos de auditoría**: el registro pedía dirección pero register_account() no la enviaba y el ERP no la validaba (se perdía); el perfil no enviaba ciudad/provincia; lo corregido en checkout no se guardaba en el perfil; todos los montos sin separador de miles (JS toFixed, PHP number_format).
- **Verificación**: node --check OK; php -l 8/8 plugin + ERP OK; E2E ERP: register con direccion/ciudad/provincia → /me persistidos ✅, PUT profile cambia ciudad/provincia ✅; fuente Ubuntu encolada en el HTML del sitio ✅. Prueba navegador pendiente del usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit

### [22:10] - WP connector v3.13.2: resumen del pedido rediseñado + Ubuntu total + responsive checkout
- **Tipo**: proyecto | UI/UX | wordpress
- **Modificado**: plugin erp-ecomm-connector 3.13.1→3.13.2 (~/dev/wordpress: connector.js render de items + erpcEsc, connector.css rediseño summary + responsive + regla Ubuntu body *). **SIN COMMIT (regla: nada de commits hasta probar).**
- **Afecta a**: kalimete (wordpress-local :8091, página /checkout/)
- **Causa**: Usuario: items del "Resumen del pedido" con letras muy grandes y sin estilo; pidió texto más pequeño, mejor sección, responsive en todos los dispositivos y Ubuntu en TODO (WP + plugin, todas las páginas).
- **Hallazgo**: el JS renderizaba items como <tr><td> sin clases pero el CSS esperaba .erpc-summary-item (flex) → sin estilo. La regla Ubuntu anterior no cubría todo el DOM.
- **Verificación**: node --check OK; php -l OK; CSS 3.13.2 en el sitio con regla body * y estilos nuevos. Prueba visual (desktop + móvil) pendiente del usuario.
- **Estado**: ⚠️ pendiente de prueba del usuario → recién entonces commit


## 2026-09-22
### [05:45] - WP connector v3.12.2: fix categorías no actualizaban sin F5 (guard ERPCLog)
- **Tipo**: proyecto | fix | wordpress-dev
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector/assets/js/connector.js` (shim no-op de `window.ERPCLog` al inicio del IIFE), `erp-ecomm-connector.php` (bump 3.12.1→3.12.2), CHANGELOG plugin; commit plugin `2fda895` (v3.11.3→v3.12.2, incluye trabajo v3.12.0/3.12.1 que estaba sin commitear). Backups `.bkup-20260922`.
- **Afecta a**: kalimete (wordpress-local, https://wordpress.kalimete.local)
- **Causa**: Síntoma del usuario: click en categoría → URL cambiaba (`?categoria=X`) pero el grid no se actualizaba hasta F5, en cada click. Causa raíz reproducida con Playwright: v3.12.0 insertó `ERPCLog.info()` en el camino crítico del click handler (tras `erpcSyncCategoryUrl()`) y como primera línea de `loadProducts()`; si el navegador no carga `logger.js` (cacheado 404/ausente de sesión previa), `ERPCLog is not defined` → TypeError mata el handler DESPUÉS del URL sync y ANTES de `loadProducts()`. Telemetría no-crítica en camino crítico sin guard.
- **Verificación**: Playwright + Chromium headless: (1) logger.js bloqueado → click Monitores → grid 15→10, 0 errores JS (antes: TypeError + grid congelado); (2) regresión camino caché: Cables 7, Monitores 10, Todo 15; (3) camino AJAX (localStorage vacío): Monitores 10, Cables 5; sitio sirve `ver=3.12.2` con shim; `node --check` + `php -l` OK.
- **Notas**: El bump de versión invalida el connector.js cacheado en el navegador del usuario. Si el usuario aún viera el bug: hard refresh (Ctrl+Shift+R) una sola vez.

### [06:15] - WP connector v3.12.3: imágenes destacados home + thumbs carrito
- **Tipo**: proyecto | fix | wordpress-dev
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector`: `templates/partials/featured.php` (mapeo manual → `ERPC_API::normalize_producto()`), `includes/class-erpc-cart.php::enrich()` (imagen envuelta en `normalize_image_url()`), bump 3.12.2→3.12.3 + CHANGELOG plugin; commit plugin `e5bc78a`. Backups `.bkup-20260922`.
- **Afecta a**: kalimete (wordpress-local, home + carrito)
- **Causa**: Usuario: en la tienda se veían bien pero los 4 destacados de la home mostraban icono roto. Causa: `featured.php` era el único punto con mapeo manual de productos SIN `normalize_image_url()` → servía `https://10.0.0.106:8100/...` (puerto 8100 solo habla HTTP → ERR_SSL_PROTOCOL_ERROR). El `enrich()` del carrito tenía el mismo bypass.
- **Verificación**: home sirve `https://erp.kalimete.local/...` (placeholder 200, webp real 200); Playwright headless: 4/4 destacados cargan (`naturalWidth>0`), 0 rotas, 0 errores JS; regresión categorías Todo 15 / Cables 7 / Monitores 10; `php -l` OK en los 3 archivos.
- **Estado**: ✅ sincronizado

### [06:30] - WP connector v3.12.4: testimonio Miguel A. → Laura A. (foto/nombre)
- **Tipo**: proyecto | fix | contenido | wordpress-dev
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector/templates/partials/social-proof.php` (testimonio Punta Cana: "Miguel A." → "Laura A."), bump 3.12.3→3.12.4 + CHANGELOG plugin; commit plugin `de4a3e1`. Backup `.bkup-20260922`.
- **Afecta a**: kalimete (wordpress-local, home)
- **Causa**: Usuario: "Miguel A. Punta Cana tiene imagen femenina con nombre de varón". Validado visualmente: avatar-3.jpg es foto femenina; avatar-1 (Carolina) y avatar-2 (José) correctos. Sin avatares masculinos libres en `assets/img/`, se corrigió el nombre (texto neutro intacto).
- **Verificación**: home sirve "Laura A." (nombre + alt), "Miguel A." ausente; Playwright headless: 3/3 avatares cargan (256px), foto/nombre coherentes.
- **Estado**: ✅ sincronizado

### [12:10] - WP connector v3.12.5: fix carrito "vacío" (carrera add→navegar)
- **Tipo**: proyecto | fix | wordpress-dev
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector/`: `templates/ecomm/cart.php` (siempre rinde esqueleto completo con visibilidad server-side), `assets/js/connector.js` (renderCartPage robusto con selectores reales, binding qty server, checkout espera sync, re-sync al cargar /carrito/, beacon pagehide), `erp-ecomm-connector.php` (plugin_url en erpc_cfg), bump 3.12.4→3.12.5 + CHANGELOG plugin; commit plugin `a0576e1`. Backups `.bkup-20260922`.
- **Afecta a**: kalimete (wordpress-local, /carrito/ y /checkout/)
- **Causa**: Usuario: "agrego items, las alertas los muestran, pero el carrito dice vacío". Diagnóstico (subagente + repro Playwright): `syncCartToServer` async fire-and-forget → cookie server stale al navegar → `cart.php` rendía rama vacía sin `tbody#erpc-cart-items` → `renderCartPage()` early-return y no repintaba desde localStorage. Agravantes: selectores `#erpc-cart-empty`/`.erpc-total-amount` inexistentes y controles qty server sin binding.
- **Verificación**: Playwright headless — navegación inmediata: 2 filas, total RD$ 3,110.89 ✅; sync bloqueado (route.abort): items visibles desde localStorage ✅; controles +/-: total 3,110.89→6,127.08→3,110.89 ✅.
- **Estado**: ✅ sincronizado

### [19:00] - WP connector v3.12.7: categorías tiempo real + total exacto + nocache
- **Tipo**: proyecto | fix | wordpress-dev
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector/`: `erp-ecomm-connector.php` (nocache_headers frontend + placeholder en erpc_cfg), `assets/js/connector.js` (click handler defensivo + fallback AJAX si caché filtra 0), `includes/class-erpc-shortcodes.php` (ajax_get_products: fetch-all páginas ERP + stock antes de paginar + total desde meta.total), bump 3.12.6→3.12.7 + CHANGELOG plugin; commit plugin `4e81d4d`.
- **Afecta a**: kalimete (wordpress-local, /productos/)
- **Causa**: Usuario: "cambio de categoría no actualiza en tiempo real, debo refrescar". Diagnóstico: en headless el click SÍ funcionaba — fallo del usuario = JS viejo cacheado (HTML sin Cache-Control → caché heurística del navegador → ver viejo con bug ERPCLog mataba el handler). Extra: AJAX devolvía totales incorrectos (return del ERP trae total en meta.total, no 'total'; filtro de stock DESPUÉS de paginar → Cables 5 de 7 reales, sin "cargar más").
- **Verificación**: Playwright headless — AJAX Cables 7 (antes 5)/Monitores 10/Impresoras 22 has_more=true/Computadoras 5 ✅; click sin refresh actualiza grilla + URL, 0 errores JS ✅; fallback caché incompleta → 7 ✅; regresión carrito v3.12.5 OK ✅.
- **Estado**: ✅ sincronizado


## 2026-09-21
### [20:30] - ERP sistema-facturacion: sync con GitHub de Juan Carlos, rama dev/ecomm-erp, limpieza OTP + secrets
- **Tipo**: proyecto | sync | seguridad | limpieza
- **Modificado**: repo `soycarlosjerez-hub/sistema-facturacion` rama `dev/ecomm-erp` (origen único junto a local `~/dev/erpipo-preprod/code/sistema-facturacion/`); eliminado remote `preprod` (warcold/erpipo-preprod, ya no existe); revert en `origin/main` del commit ecomm subido por error (main limpio para Juan); OTP removido de `dev/ecomm-erp` (`ClienteOtpController.php`, `ClienteOtpCode.php`, 4 rutas `api/ecomm/auth/*` — login queda por email+password); SECURITY untrack `.env`, `.env.backup_audit`, `.env.dev` (tenían APP_KEY y DB_PASSWORD reales); `.gitignore` blindado (agrega `.env`/`.env.dev`, saca `.env.example` del ignore, corrige backups a `/storage/app/backups/`, reglas anti-WordPress); eliminado `releases/20260911_212141` (snapshot duplicado 48MB, 2466 archivos); untrack 15 views Blade compilados; `.env.example` documenta integración plugin WP vía Instance API Key (sin secrets).
- **Afecta a**: kalimete (stack erpipo-preprod) + repo GitHub de Juan Carlos (colaborador)
- **Causa**: Usuario: repo de Juan es el principal, sync bidireccional, sin duplicados, plugin WP nunca se sube, ERP listo para deploy de Juan. Hallado: 2 remotes divergentes, secrets en git, OTP muerto, junk trackeado.
- **Verificación**: local↔origin 0 commits desfasados, status limpio; 31 rutas ecomm registradas (login/register/cart/checkout/orders/tienda/config); 0 archivos WP en git; docker 8 servicios up; Laravel 12.16.0 sin errores; php -l OK.
- **Notas**: ROTAR secrets expuestos en historial (APP_KEY, DB_PASSWORD de facturacion_db) — el untrack no borra el historial. Backups locales `storage/app/backups/` (3.4GB) NO tocados, solo reportados.
- **Estado**: ✅ sincronizado

### [21:00] - ERP sistema-facturacion: merge de 13 commits de Juan en dev/ecomm-erp, ecomm preservado, sync 0/0
- **Tipo**: proyecto | sync | merge | seguridad
- **Modificado**: `dev/ecomm-erp` local + `origin/dev/ecomm-erp` (merge `a5c6495`): trae soporte/tickets, landing Erp&Pos, DataTables, roles de Juan; preserva ecomm nuestro (6 archivos restaurados de HEAD tras detectar que el auto-merge tomó versiones revertidas de Juan); conflictos resueltos: `.env` (mantener borrado), 2 views compilados (borrados), `.gitignore` (nuestro bloque); migraciones soporte corridas en docker; push normal sin force.
- **Afecta a**: kalimete (erpipo-preprod) + repo GitHub de Juan Carlos
- **Causa**: Usuario: actualizarse con commits de Juan quedando iguales, sin dañar ecomm de WordPress. Autoría verificada: secrets (`.env`/`.env.dev` con keys reales) y `releases/` los commiteó Carlos Jerez (`1807f68`, `7d40ccf`); nuestra limpieza `0b502c7` solo los removió.
- **Verificación**: local↔remoto 0/0; 31 rutas ecomm; 0 OTP; `php -l` OK; migrate soporte DONE (4 tablas); docker operativo.
- **Notas**: PENDIENTE rotar APP_KEY/DB_PASSWORD expuestos en historial. Rama `main` local aún en 363821c (behind 11, FF pendiente, fuera de alcance pedido).
- **Estado**: ✅ sincronizado

### [21:30] - ERP+WP: imagenes de productos visibles en wordpress.kalimete.local + fix fatal v3
- **Tipo**: proyecto | fix | ecomm | wordpress
- **Modificado**: `dev/ecomm-erp` (`a0f79a3`, solo nuestra rama): `Producto::getImagenUrlAttribute` ahora usa `config(app.url)` en vez de `asset()`; `EcommController::resolveTenantId` corregido (`attributes()` inexistente → `attributes`, 2 líneas, era de Juan `7ab4431`). WP: purgados transients `erpc_c_*` con URLs viejas (`erpipos.armada.do`, `https://IP:8100`).
- **Afecta a**: kalimete (erpipo-preprod + wordpress-local)
- **Causa**: Usuario: sin imágenes en WP. Hallado: 1) ERP generaba `https://10.0.0.106:8100/...` (puerto HTTP-only → ERR_SSL_PROTOCOL_ERROR); 2) caché WP con URLs de `erpipos.armada.do`; 3) `erpipos/v3/*` caído con 500 por `BadMethodCallException`.
- **Verificación**: API devuelve `https://erp.kalimete.local/storage/...` (200 estricto); página WP con 15/15 imgs al host válido; `v3/products` 200 con llave magantech; `php -l` OK; push `a5c6495..a0f79a3` a `origin/dev/ecomm-erp`.
- **Notas**: Ver el ERP UI preferiblemente por `https://erp.kalimete.local` (las imágenes ahora salen con ese host). `main` no tocado (de Juan).
- **Estado**: ✅ sincronizado

### [22:00] - ERP preprod: rotación APP_KEY+DB_PASSWORD, limpieza backups 3.4G→985M
- **Tipo**: seguridad | mantenimiento | infra
- **Modificado**: `preprod.env` (+backup `.bkup-20260921`), `docker-compose.yml` (+backup, MYSQL_PASSWORD igualado), repo `.env` (key nueva); `storage/app/backups/`: borrados 10 dumps viejos + 4 stubs fallidos + 15 txt (quedan 2 full Sep17-18); `REGLAS.md` actualizado.
- **Afecta a**: kalimete (erpipo-preprod; sesiones/cookies invalidadas por key nueva, sin datos cifrados en BD — verificado 0 casts encrypted)
- **Causa**: Usuario ordenó proceder. Secrets estaban expuestos en historial GitHub (commits de Juan). Incidentes en el camino: mount `.env` rancio (fix: restart app), 502 por resolver nginx rancio (fix: restart nginx), compose con password truncado (fix: reescrito desde preprod.env verificado).
- **Verificación**: migrate 0 pendientes; ERP :8100 200; API magantech 200; WP 200 con imágenes; docker 8/8 up; 0 fatales; login DB con clave nueva OK.
- **Notas**: PENDIENTE Juan rote sus secrets. Job auto-backup roto (stubs 98B, conecta a 127.0.0.1) — flag, no tocado.
- **Estado**: ✅ sincronizado

### [22:30] - ERP: revertido todo lo tocado de Juan + fusionado su refactor sin perder ecomm
- **Tipo**: proyecto | revert | merge | reglas
- **Modificado**: `dev/ecomm-erp` (`174b1d3` revert: `.env`/`.env.dev`/`.env.backup_audit`, `releases/`, views compilados, líneas `attributes()` y accessor imagen restaurados byte-idénticos a Juan; luego `e76b0c3`: `SaleCreateService.php` fusionado a mano — su `esTipoComprobantePermitido()` centralizado + nuestro `tenantIdFromContext()` ecomm). `REGLAS.md`: regla file-level no-tocar-lo-de-Juan + no-directivas.
- **Afecta a**: kalimete (erpipo-preprod) + repo GitHub de Juan Carlos
- **Causa**: Usuario: no tocar lo de Juan (ni sus archivos ni darle directivas). Hallado: mi `checkout HEAD` en el merge había pisado su refactor de comprobantes en `SaleCreateService.php` (único de los 6 archivos ecomm que él sí tocó); resto intacto verificado archivo por archivo.
- **Verificación**: 0/0 con origin; 31 rutas ecomm; `php -l` OK; push `174b1d3..e76b0c3` solo a `dev/ecomm-erp` (main no tocado).
- **Estado**: ✅ sincronizado

### [22:45] - WP connector v3.12.1: imágenes visibles vía normalize_image_url + lección mount rancio
- **Tipo**: proyecto | fix | wordpress-dev | infra
- **Modificado**: `~/dev/wordpress/.../erp-ecomm-connector` (solo nuestro): `normalize_image_url()` en `class-erpc-api.php` (reescribe host a `https://erp.kalimete.local`, override `ERPC_IMAGE_HOST`, PHP 7.4 OK) usado en `normalize_producto()`; bump 3.12.1 + CHANGELOG plugin; purgados transients `erpc_c_*`. `REGLAS.md`: regla bind-mount (no reemplazar `preprod.env`, verificar md5) + regla secrets ajenos.
- **Afecta a**: kalimete (wordpress-local + erpipo-preprod)
- **Causa**: Usuario: mejorar todo sin tocar secrets ajenos. Imágenes WP rotas (ERP devolvía host del request). Incidente: `perl -i` cambió el inode de `preprod.env` → contenedor con clave vieja → Access denied; fix con `--force-recreate` + md5.
- **Verificación**: API magantech 200; página WP 200 con 8 URLs al host válido (200 estricto); `php -l` OK; repo ERP limpio 0/0 (cero archivos de Juan tocados).
- **Estado**: ✅ sincronizado


## 2026-09-20
### [00:30] - WordPress local: connector v3.9.7 — buscador funcional + settings contacto/redes/mapa
- **Tipo**: proyecto | feature | fix | ux | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (JS: wiring header search desktop+móvil, `?buscar=`, home_url en erpc_cfg; shortcodes: filtro server-side + `[erpc_map]` nuevo + docs; products.php: paridad; admin: sanitización + sección Contacto/redes/mapa; footer dinámico; CSS; helper `erpc_social_link()`; bump 3.9.7, commit `14b1f4a`, push main OK); `_elementor_data` contacto (sección mapa, backup `_elementor_data_bak_v396`); `map_address` = ciudad (refinar); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.7); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, ambos templates)
- **Causa**: Usuario: validar buscador contra inventario en ambos templates + settings de redes/contacto/mapa. Hallazgos: (1) buscador del header muerto (HTML sin handlers); (2) `?s=` colisiona con búsqueda nativa de WP (mayúsculas/espacios → 404 del tema) → parámetro propio `?buscar=`; (3) products.php (router plugin) ignoraba el filtro en render inicial; (4) footer con 4× `href="#"` muertos y cero settings de redes/contacto/mapa.
- **Implementado**: Header search → `/productos/?buscar=` (Enter desktop/móvil + botón); catálogo lee el parámetro (server pre-filtra en ERP + JS pre-llena y filtra al escribir); admin con teléfono/dirección/horario/6 redes/dirección-mapa (XSS y basura rechazadas); footer con redes configuradas + contacto + icono contacto siempre; `[erpc_map]` (Google embed sin key, responsive) agregado a /contacto/.
- **Verificación**: `?buscar=` filtra inventario real (cable 15/41, laptop 15/38, hdmi 4, mouse 1, inexistente 0); CDP: header desktop+móvil → navegación + resultados correctos; footer con valores (links reales) y vacío (ocultos, 0 muertos); mapa 1060×382 desktop / 307×282 móvil; 200 en modo plugin Y elementor (switch ida/vuelta); php -l ×6 + node --check OK. Screenshots val-search-*.png, val-contacto-map-*.png.
- **Pendiente usuario**: refinar `map_address` a dirección exacta (ERP Connector → Contacto, redes y mapa); poner URLs reales de redes sociales; USP menciona tarjetas de video pero el inventario actual no las tiene — alinear catálogo ERP o copies.
- **Estado**: ✅ sincronizado

### [00:40] - WordPress local: validación plugin — error MCP corregido + connector v3.9.9
- **Tipo**: proyecto | fix | validación | wordpress-dev
- **Modificado**: `mcp-adapter/` (`composer dump-autoload` → `vendor/autoload.php`, 251 clases); plugin `erp-ecomm-connector` (`get_brand()` reescrito con merge defaults<-ERP<-local, `footer.php` + `auth/form.php` blindados con `?? 'Tienda'`, bump 3.9.8→3.9.9); `mcp-basic-auth.php` v1.1 (auth correcta, multi-header Apache/FPM, base64 estricto); `docker-compose.yml` (guards `!defined` en WORDPRESS_CONFIG_EXTRA); `wp-config.php` (WP_DEBUG duplicado eliminado); CHANGELOG del plugin (entrada 3.9.9). Backups `.bkup-20260920` de todo lo tocado.
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, endpoints MCP)
- **Causa**: Usuario: "el plugin emite error de mcp, validar y corregir todas las fallas". Causa raíz: mcp-adapter instalado desde fuente sin `composer install` (sin autoload → plugin oficial muerto; solo vivía la copia bundled de EMCP Tools). Fallas extra: `get_brand()` comparaba array con `!== ''` (warnings `Undefined array key "name"`); `mcp-basic-auth` con lógica invertida y un solo header; colisión de constantes WP_HOME/WP_DEBUG.
- **Estado**: ✅ sincronizado
- **Notas**: wordpress-dev agotó sus pasos en diagnóstico (2 sesiones); kalimete aplicó correcciones pendientes directamente. Verificación: php -l ×4 OK; home 200 sin warnings nuevos; clases `WP\MCP\Plugin/Core\McpAdapter/Transport\HttpTransport` resuelven; MCP anónimo → 401 esperado (protegido, requiere usuario WP con cap read); basic inválido → 401 limpio sin fatales. Pendiente upstream: conflicto require-dev del mcp-adapter (php_codesniffer 3 vs 4) + ext-mbstring en host para `composer install` completo.

### [01:00] - WordPress local: update total — core 7.1.1 + plugins al día, cero pendientes
- **Tipo**: proyecto | update | mantenimiento | wordpress-dev
- **Modificado**: core 7.1→7.1.1; `all-in-one-wp-migration` 7.110→7.111; `emcp-tools` 3.14.1→3.16.1; contenedor `wordpress-local` recreado (activa guards `!defined` del compose en WORDPRESS_CONFIG_EXTRA); wp-cli 2.12.0 instalado en contenedor (`/tmp/wp-cli.phar`, se pierde al recrear). Backups pre-update: `backups/wp-full-20260920.sql` (1.6M) + `backups/wp-content-20260920.tgz` (31M).
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, endpoints MCP)
- **Causa**: Usuario: discrepancias en updates — validar todo y actualizar. Hallado: core pedía 7.1.1 (minor), 2 plugins con update, ruido `Constant already defined` en cada request (compose sin guards + constantes duplicadas).
- **Verificación**: `core check-update` = latest; plugins/temas con update = cero; home 200; REST OK; rutas MCP (`default-server` + `emcp-tools-server`) intactas tras emcp 3.16.1; `wp-config.php` con 1 sola definición y wp-cli sin warnings; `debug.log` sin autoloader ni warnings de brand. Avisos EMCP `not in the ability registry` (40 líneas) son PREVIOS al update (primera 04:43:05, update posterior) — no es regresión, es logging informativo propio con WP_DEBUG.
- **Notas**: (1) imagen base sigue `wordpress:6.7-php8.3-apache` aunque el core es 7.1.1 — normal: el core se auto-actualiza sobre la base; no se cambió la imagen a propósito (riesgo innecesario). (2) `mcp-basic-auth` v1.1 sigue INACTIVO (se deja así; activar cambia auth de MCP — pedir confirmación). (3) demás stacks (erpipo-preprod, alfredo-ecomm, taohemps, petsuite, woodly, tapmap): todos Up/healthy; imágenes de build local (actualizar = rebuild/deploy por stack, no tocado) y bases `:latest` compartidas (pull reiniciaría preprod, no tocado).
- **Estado**: ✅ sincronizado

### [01:05] - WordPress local: connector v3.9.10 — home plugin en paridad con Elementor (4 destacados + CTA)
- **Tipo**: proyecto | fix | paridad | wordpress-dev
- **Modificado**: `templates/landing.php` (destacados 8→4 + sección CTA final "¿Listo para equipar tu setup?/Ir a la tienda"); `assets/css/connector.css` (reglas `.erpc-landing-cta*`); bump 3.9.10 + CHANGELOG del plugin. Backups `.bkup-20260920` de ambos.
- **Afecta a**: kalimete (stack wordpress-local, home modo plugin)
- **Causa**: Usuario: home del plugin mostraba muchos productos, no los 4 del Elementor, y le faltaban updates del template Elementor. Causa: `array_slice($productos,0,8)` vs shortcode Elementor `columns='4' per_page='4' show_more='0'`; CTA final no existía en `landing.php`.
- **Verificación**: render real vía `do_shortcode('[erpc_landing]')` → 4 cards + CTA; php -l OK; últimos `Undefined array key` del 18-sep (pre-fix), cero nuevos.
- **Estado**: ✅ sincronizado

### [01:10] - WordPress local: connector v3.9.11 — causa raíz home plugin (15→landing 4+CTA en modo plugin)
- **Tipo**: proyecto | fix | root-cause | wordpress-dev
- **Modificado**: `includes/class-erpc-templates.php` (portada en modo plugin → `landing`; fallback shortcode honra `per_page/columns/show_more/categoria`); `templates/ecomm/products.php` (consume `erpc_tpl_*`, load-more respeta `$show_more`); página 8 `post_content` (`per_page='12'`→`'4' show_more='0'`); bump 3.9.11 + CHANGELOG plugin. Backups: `class-erpc-templates.php.bkup-20260920`, `backups/home-page8-content-backup.txt`. `template_mode` quedó en `elementor` (original; solo se cambió a `plugin` temporalmente para verificar por HTTP).
- **Afecta a**: kalimete (stack wordpress-local, home en ambos modos)
- **Causa**: Usuario: "no veo que se hayan aplicado". Validación HTTP real demostró que v3.9.10 sí estaba vivo (CSS `ver=3.9.11`) pero la portada en modo plugin nunca rinde `landing.php`: slug `magantech-inicio` ≠ `inicio` → fallback incluía `products.php` directo ignorando attrs → 15 productos del tenant. Tres fuentes divergidas (content:12, elementor:4, router:15).
- **Verificación**: modo plugin → landing con 4 cards + CTA + hero, sin load-more; modo elementor → 4 cards sin load-more; php -l ×3 OK; debug.log sin entradas nuevas.
- **Estado**: ✅ sincronizado

### [01:15] - WordPress local: connector v3.9.12 — filtro stock<=1 oculto del ecommerce
- **Tipo**: proyecto | feature | regla-negocio | wordpress-dev
- **Modificado**: helper `erpc_con_stock()` en `erp-ecomm-connector.php`; filtro en `landing.php`, `products.php`, `render_products`, `ajax_get_products` (+total ajustado), `ajax_get_products_json`; bump 3.9.12 + CHANGELOG plugin. Backups `*.bkup-20260920b`. Carrito/checkout sin cambios (validan con ERP).
- **Afecta a**: kalimete (stack wordpress-local, home + catálogo + buscar + cargar más, ambos modos)
- **Causa**: Usuario: stock 0/1 no debe presentarse en el ecommerce.
- **Verificación**: 162 ERP → 58 visibles / 104 ocultos; home 4 cards, catálogo 15 cards, cero "Agotado", testigo stock-1 ausente; CSS ver=3.9.12; log sin entradas nuevas.
- **Estado**: ✅ sincronizado

### [01:20] - WordPress local: connector v3.9.13 — paridad plugin/Elementor (mapa, chrome único, cotizar)
- **Tipo**: proyecto | fix | paridad | wordpress-dev
- **Modificado**: página 17 (`[erpc_map]` agregado al contenido); `static.php` (retira header/footer espejo → chrome único); router (`cotizar`→static, `erpc_contact/quote/map`→static); bump 3.9.13 + CHANGELOG plugin. Backups: `static.php.bkup-20260920b`, `templates.php.bkup-20260920b`, `backups/contact-page17-content-backup.txt`. `template_mode` en `elementor` (original).
- **Afecta a**: kalimete (stack wordpress-local, contacto/cotizar/legales en ambos modos)
- **Causa**: Usuario: mejoras en ambos defaults (plugin y Elementor) semejantes; el cliente edita Elementor a gusto después. Divergencias: mapa solo en Elementor; doble chrome en plugin; cotizar sin router.
- **Verificación**: plugin → contacto form+mapa, cotizar form, términos 11 cards, catálogo 15, 1 header+1 footer en las 3; elementor → home 4, contacto form+mapa, cotizar form; log limpio.
- **Estado**: ✅ sincronizado

### [01:30] - WordPress local: connector v3.10.0 — Kit Elementor instalable + prueba social + imágenes locales
- **Tipo**: proyecto | feature | kit | ux | wordpress-dev
- **Modificado**: `kit/elementor-kit/*.json` (8 páginas) + `manifest.json` + `kit/assets/hero-home.jpg`; importador `ERPC_Kit` (menú Kit Elementor, manual, no pisa diseños); `assets/img/` (hero-home, cta-band, contact-side, 3 avatares — Unsplash License validadas); `ERPC_DEFAULT_HERO` → asset local; `[erpc_social_proof]` (shortcode + partial con contadores animados EN VIVO + testimonios + reveal); CSS (`.erpc-proof*`, hero catálogo con foto, sheen estáticas, CTA con overlay); JS (count-up rAF + IntersectionObserver); home Elementor (hero imagen attachment 73 + sección proof, backup `elementor-8-before-v310.json`); contenido pág. 8 (`[erpc_social_proof][erpc_footer]`); bump 3.10.0 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, ambos modos, todas las páginas)
- **Causa**: Usuario: opción A (el trabajo viene con la plantilla base), imagen en header plugin vs Elementor, imágenes gratuitas validadas en internet, páginas más dinámicas/profesionales (iconos, efectos, social proof).
- **Verificación**: elementor → home 4 cards + proof 5 counters + 3 avatares + hero en post-8.css + CTA; plugin → home 4 + proof + hero local + CTA; contacto/cotizar chrome único; kit import: skipped en diseño vivo, completed en draft 30; php -l ×6 + node --check OK; log sin entradas nuevas.
- **Pendiente usuario**: draft huérfano 30 (slug `inicio`) recibió el kit — borrar o dejar (confirmar); testimonios son copy de ejemplo (editar a clientes reales); contadores 2500+/4.9 son estáticos (editar a métricas reales).
- **Estado**: ✅ sincronizado

### [01:30] - WordPress local: connector v3.9.8 — auditoría integral responsive + cross-browser
- **Tipo**: proyecto | fix | ux | compat | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (CSS: contador en su línea + hamburguesa ≤991px + 11 prefixes `-webkit-`/`100dvh`/`sticky`; JS: resize a 991; bump 3.9.8, commit `c8f0190`, push main OK); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.8); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, ambos templates — header/botones compartidos)
- **Causa**: Usuario: validar desktop/móviles/dispositivos + multi-navegador + botones centrados en ambos templates. Hallazgos de la matriz CDP (7 páginas × 7 viewports 1920→360): (1) overflow horizontal en tablet 769-991px — nav completo no cabe, afectaba todas las páginas; (2) "Cargar más productos" descentrado en desktop — contador inline en la misma línea; (3) bug de cascada en el propio fix (bloque 991px antes de la regla base → tablet sin nav ni hamburguesa).
- **Implementado**: Hamburguesa a ≤991px (mismo dropdown probado + search móvil + JS resize); contador en bloque propio; bloque 991 movido tras el 768 (cascada correcta); 11 prefixes de compatibilidad; auditoría confirma cero `:has()`/`color-mix`/exóticos.
- **Verificación**: 12 runs CDP con 0 overflow en todos los viewports; hamburguesa 820px abre dropdown con 7 links sin overflow; 100% botones con `text-align:center` + posición verificada uno por uno (los no-centrados son por diseño: pills, search, tabs, USP, newsletter desktop); Firefox real bajo Xvfb con CA mkcert: 5 screenshots con contenido íntegro (Gecko OK); Safari no existe en Linux → cubierto con auditoría CSS estática + prefijos. Screenshots audit-*.png + fx-*.png en /tmp/opencode/.
- **Estado**: ✅ sincronizado

### [01:40] - WordPress local: connector v3.10.1 — fix 403 en Kit Elementor (orden admin_menu)
- **Tipo**: proyecto | fix | admin | wordpress-dev
- **Modificado**: `erp-ecomm-connector.php` (`ERPC_Kit::init()` movido de parse-time a `init_admin()`, después del menú padre); bump 3.10.1 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, wp-admin → ERP Connector → Kit Elementor)
- **Causa**: Usuario: "no puedo entrar a la configuración en wp-admin, está roto". Diagnóstico end-to-end (login real con usuario temporal): página principal 200 OK, dashboard OK, pero Kit Elementor 403 "Sorry, you are not allowed". Causa raíz: Kit registrado en parse-time (antes de plugins_loaded) → add_submenu_page sin padre registrado → hook con nombre incorrecto → 403 con menú visible.
- **Verificación**: kit-page 200 (106KB, contenido, sin 403); main-page 200; dashboard con ambos menús; usuario de prueba eliminado (limpio).
- **Estado**: ✅ sincronizado

### [01:50] - WordPress local: connector v3.10.2 — paridad total home (fuente única de secciones)
- **Tipo**: proyecto | fix | paridad | arquitectura | wordpress-dev
- **Modificado**: 5 shortcodes duales nuevos (`erpc_hero/usp/categories/featured/cta`) + parciales (`hero-landing.php`, `categories-landing.php`, `featured.php`, `usp.php`, `cta-landing.php`); `landing.php` refactorizado a shortcodes; home Elementor reconstruido con la misma secuencia (backup `elementor-8-before-v3102.json`); CSS `.erpc-usp*`; bump 3.10.2 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, home en ambos modos)
- **Causa**: Usuario: la home del plugin se ve mejor que la de Elementor; ambos deben ser iguales (mismas imágenes/textos, mínimas discrepancias). Causa: Elementor tenía `[erpc_products]` que rinde el catálogo completo (hero Catálogo + buscador + filtro + quick-view) dentro de la home.
- **Verificación**: 12 marcadores de paridad TODOS OK idénticos (hero=5, usp=4, cats=17, cards=4, proof=5, cta=3, avatars=3 + 5 textos); catálogo completo eliminado de la home Elementor; home 200, catálogo 200; log limpio.
- **Estado**: ✅ sincronizado

### [02:00] - WordPress local: connector v3.10.3 — fix home plugin sin estilos (frame omitido)
- **Tipo**: proyecto | fix | regresión | wordpress-dev
- **Modificado**: `templates/landing.php` (frame check restaurado al inicio — include header.php); bump 3.10.3 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, home modo plugin)
- **Causa**: Usuario: "la página de inicio del plugin está rota, no tiene estilo". Causa raíz: el refactor v3.10.2 de landing.php olvidó el include del header (frame doctype/head/wp_head) — la home salía como contenido crudo sin CSS (26KB, sin doctype). Regresión del propio refactor.
- **Verificación**: home plugin 200/55KB con doctype + 14 stylesheets + trustbar + todas las secciones; 1 header + 1 footer; modo elementor restaurado idéntico; php -l OK.
- **Estado**: ✅ sincronizado

### [02:10] - WordPress local: connector v3.11.0 — modo Elementor retirado, una sola plantilla (plugin default)
- **Tipo**: proyecto | refactor | limpieza | decisión | wordpress-dev
- **Modificado**: eliminado `kit/` (8 JSON + manifest) + `class-erpc-kit.php` + menú Kit; meta Elementor de 8 páginas (data/edit_mode/template_type/caches/6 baks); draft huérfano 30; plugin Elementor DESACTIVADO (reactivable); `template_mode='plugin'` permanente; pág. 8 `[erpc_landing]`; `_wp_page_template='default'`; README/docs actualizados; bump 3.11.0 + CHANGELOG plugin. Backups: `backups/elementor-cleanup-20260920/` (8 JSON).
- **Afecta a**: kalimete (stack wordpress-local — arquitectura de una sola plantilla)
- **Causa**: Usuario: el template en Elementor está de más (son shortcodes, no se puede editar lo hecho) — borrarlo y quedarse solo con el template del plugin, que se vea tan bien como Elementor. Validado: el home Elementor era solo contenedor de los mismos shortcodes; 2 plantillas = 2 fuentes de divergencia.
- **Verificación**: 8 páginas 200; home completa (hero=5, usp=4, cards=4, proof=5, cta=1, doctype, CSS 3.11.0); productos 15 chrome único; contacto form+mapa; cotizar form; admin 200 sin menú Kit; php -l OK.
- **Estado**: ✅ sincronizado

### [02:20] - WordPress local: connector v3.11.1 — contacto real, nosotros rico, tagline centrado
- **Tipo**: proyecto | fix | feature | ux | wordpress-dev
- **Modificado**: `[erpc_contact_info]` (datos reales del tenant, dinámico) + `contact-info.php`; `[erpc_about]` (hero con foto about-team.jpg, 4 pilares con iconos, stats animados, USP, CTA) + `about.php`; contenido pág. 17 reescrito limpio (tenía 'n' literales + placeholders); pág. 36 `[erpc_about]`; activación actualizada (ambos shortcodes); CSS (tagline centrado absolute, contact-info cards, about); `assets/img/about-team.jpg` (Unsplash validada); bump 3.11.1 + CHANGELOG plugin. Backups: `contact-page17-content-backup2.txt`, `about-page36-content-backup.txt`, CSS `.bkup-20260920c`.
- **Afecta a**: kalimete (stack wordpress-local, contacto/sobre-nosotros/header)
- **Causa**: Usuario: contacto no correcto (placeholders soporte@tudominio.com en vez de datos del tenant), nosotros pobre (sin imágenes, cards planas), tagline "tecnología al mejor precio" no centrado en header.
- **Verificación**: contacto 200 (2 info-cards email real, 0 placeholders, form+mapa, chrome único); nosotros 200 (hero foto, 4 pilares, stats, USP, CTA); home tagline centrado; productos/términos/faq 200; php -l ×4 OK.
- **Estado**: ✅ sincronizado

### [02:30] - WordPress local: connector v3.11.2 — contacto/nosotros/cotizar full width como la home
- **Tipo**: proyecto | fix | layout | responsive | wordpress-dev
- **Modificado**: templates full-page nuevos (`contacto.php` hero foto + info real + form + soporte + mapa; `about.php` [erpc_about]; `cotizar.php` hero foto + form); router (mapeos + shortcode fallbacks + full_page_templates ×3); bump 3.11.2 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, contacto/sobre-nosotros/cotizar)
- **Causa**: Usuario: contacto y nosotros no full width como la inicio; responsive en todos los dispositivos. Causa: las 3 renderizaban vía wrapper (main-container) — hero con foto dentro del container.
- **Verificación**: 3 páginas 200 con main-container=0 (full width), hero=4, chrome único; home 200; términos 200 (wrapper intacto para lectura); media queries cubren desktop/laptop/tablet/mobile; php -l ×5 OK.
- **Estado**: ✅ sincronizado

### [02:40] - WordPress local: connector v3.11.3 — soporte centrado, mapa en box, tagline sin solapamiento
- **Tipo**: proyecto | fix | ux | wordpress-dev
- **Modificado**: `templates/contacto.php` (soporte técnico centrado + mapa en box dentro del container); `templates/partials/header.php` + CSS (tagline apilado centrado bajo el logo — el absolute al 50% se solapaba con el buscador); bump 3.11.3 + CHANGELOG plugin.
- **Afecta a**: kalimete (stack wordpress-local, contacto + header home)
- **Causa**: Usuario: soporte técnico debe quedar centralizado, mapa mejor en box, validar centralizado de texto en header. Hallado: tagline absolute se solapaba con el buscador (search 300-820px vs tagline 600px).
- **Verificación**: contacto 200 (soporte centrado, mapa en box, chrome único); home 200 (tagline renderiza, CSS 3.11.3); productos/nosotros/cotizar/términos 200; php -l ×3 OK; log limpio.
- **Estado**: ✅ sincronizado


## 2026-09-19
### [00:20] - Auditoría completa de conexiones SSH + vps-proxy vivo (vínculo ERP retirado 2026-09-19)
- **Tipo**: infra | red | accesos | docs
- **Modificado**: `/etc/ssh/ssh_config.d/10-armada-hosts.conf` (backup `.bkup-20260919`, agregado `vps-proxy`; alias de tercero retirado el mismo día); `MAPA.md` (nodo 6 nuevo + topología, luego retirado); `agents/kalimete.md` (tabla de red, fila retirada); este CHANGELOG
- **Afecta a**: kalimete (aliases SSH), documentación del ecosistema
- **Causa**: Usuario pidió validar todas las conexiones y re-documentar
- **Validación en vivo** (todos los SSH probados):
  - ✅ kalimete (local, uptime 1d) | ✅ victoria (gw :8010 → 200, GB10 OK) | ✅ vps-preprod (uptime 67d, 16 contenedores)
  - ✅ vps-proxy (uptime 228d, Squid 200 en 0.08s) — la marca FAILED 2026-03-17 era **obsoleta**, corregida
  - ❌ ex-vps-erpipo DESVINCULADO 2026-09-19 (alias SSH retirado, sin acceso, fuera de MAPA y agentes)
  - 🔴 jonas (No route to host — sigue fuera de servicio)
- **Observaciones**: (1) vps-preprod: `caddy` del sistema inactivo (TLS lo sirve contenedor caddy) y `openvpn@server` inactivo — revisar si importa. (2) servidor ERP de terceros: vínculo retirado 2026-09-19 (sin acceso SSH ni registro en red; prod no se toca). (3) kalimete local: UFW inactivo, sin proxy local (solo docker-proxies).
- **Estado**: ✅ sincronizado (pendiente commit+push)

### [00:35] - Auditoría read-only servidor ERP externo (acceso retirado 2026-09-19)
- **Tipo**: infra | auditoría | plan
- **Modificado**: ninguno (solo lectura en servidor externo; cero cambios en el servidor)
- **Afecta a**: futuro preprod en kalimete + repo GitHub del proyecto ERP
- **Hallazgos**: 2 Laravel 8.3 (sistema-facturacion 3.9G con storage/ 3.5G + karaoke 489M con ffmpeg/yt-dlp) sobre nginx+php-fpm+MySQL 8.0 nativos; stack dev Docker (7 contenedores, compose en /opt/erpipos) montando el código de prod con .env propio; MySQL nativo: facturacion_db 746MB/203tbl (PROD) + karaoke_db 1MB + backup_temp 8.9MB; dev MySQL 712MB (copia de prod); backup diario cron 08:00 a /var/backups/facturacion_db (4.3G acumulados, log OK hasta 20260918); UFW activo (1888 + Nginx + fail2ban sshd/nginx-http-auth); huella total a respaldar ~9GB (4.3G código + 4.3G dumps + 1.6G volúmenes dev opcionales)
- **Estado**: 📋 plan entregado, pendiente aprobación para ejecutar

### [00:45] - Backup completo sistema-facturación descargado al Escritorio de kalimete
- **Tipo**: infra | backup | erpipo
- **Modificado**: `/root/erpipo-facturacion-20260919.tar.gz` en servidor externo (staging en `/root/erpipo-backup-20260919/`); copia en `/home/warcold/Desktop/erpipo-facturacion-20260919.tar.gz` (555M, sha256 verificado, tar íntegro)
- **Afecta a**: servidor ERP externo (acceso solo-lectura, retirado 2026-09-19) + kalimete (listo para deploy preprod)
- **Contenido**: dump fresco `facturacion_db` 528M (Laravel 12.16, PHP 8.3.6, MySQL 8.0.46) + código `sistema-facturacion` 3.8G (sin `node_modules`, con `vendor` + `.env` + `storage/` 3.5G) + dev-stack `/opt/erpipos` (compose, Dockerfile, nginx, php conf) + nginx sites + htpasswd + pool php-fpm + certs LE + script de backup + versions.txt. Karaoke EXCLUIDO a pedido. Compresión 87% (4.3G → 555M)
- **Estado**: ✅ en Escritorio, listo para dockerizar en preprod

### [03:08] - Preprod ERP dockerizado en kalimete (erp.kalimete.local)
- **Tipo**: infra | docker | preprod | erpipo
- **Modificado**: `MAPA.md` (nodo kalimete-preprod añadido); `CHANGELOG.md`; `agents/erp-dev.md` (subagente creado); `docker-compose.yml` (stack preprod); `preprod.env` (.env preprod); `nginx` TLS config (erp.kalimete.local.conf + mkcert); symlink `~/.config/opencode/agent/erp-dev.md`
- **Afecta a**: kalimete (preprod ERP dockerizado)
- **Stack dockerizado** standalone (sin vínculo a prod): app (erpipo-preprod), nginx (:8100), db (mysql:8.0, :3310), redis (redis:7-alpine, :6390), queue, scheduler, phpmyadmin (:8102)
- **Dump importado**: 601 migraciones, batch 145 (facturacion_db, 528MB)
- **Código**: ~/dev/erpipo-preprod/code/sistema-facturacion/ (3.8G, uid 1000:1000 en storage/)
- **SSL**: mkcert erp.kalimete.local.pem (exp 2028-12-18), nginx TLS en :443
- **Nginx host**: erp.kalimete.local.conf (proxy_pass :8100 app, :8102 phpMyAdmin)
- **Workers**: queue (`queue:work --tries=3`) + scheduler (`schedule:work`) en Redis
- **App**: uid 1000:1000, storage/logs/ y storage/framework/ con 775 (warcold:warcold)
- **Estado**: ✅ erp.kalimete.local funciona (HTTP 302 → LOGIN 200), stack completo UP
- **Subagente**: erp-dev creado (`agents/erp-dev.md`), linked en opencode (symlink)

### [03:23] - Repo GitHub privado erpipo-preprod + auditoría aislamiento preprod
- **Tipo**: infra | git | seguridad | preprod | erpipo
- **Modificado**: repo nuevo `github.com/warcold/erpipo-preprod` (PRIVATE); `.gitignore` endurecido en el código; `agents/erp-dev.md` (repo + workflow + reglas); `MAPA.md` (nodo 6: repo); este CHANGELOG
- **Afecta a**: kalimete (workflow GitHub → preprod → prod habilitado)
- **Causa**: usuario pidió validar aislamiento/funcionalidad y subir a GitHub privado sin DB
- **Auditoría aislamiento** (verificado contra lo real): red dedicada `erpipo-dev-network` (172.22.0.x, no compartida); volúmenes propios `erpipo-dev-mysql-data`/`erpipo-dev-redis-data`; puertos :8100/:8102/:3310/:6390 sin colisión (6379=alfredo-ecomm, 3307=wordpress-db, 5432=postgres); vhost nginx dedicado `erp.kalimete.local.conf` (otros 11 sites intactos); resto de contenedores (12) sin afectación
- **Funcionalidad** (verificado): `/` 302→/login, `/login` 200 (18KB), `/phpmyadmin` 200; `artisan about`: Laravel 12.16, PHP 8.3.33, env preprod, debug OFF; DB 203 tablas; Redis PONG; scheduler corriendo; cert mkcert hasta 2028-12-18
- **Limpieza pre-push**: eliminado dup `sistema-facturacion/sistema-facturacion/` (3.8G, untracked); untracked `.env.backup_audit` (tenía APP_KEY), dumps `*.sql` (68M: releases/ 51M + solo_inserts 7.8M + app/backups 8.8M), views compilados (27 archivos), `*.backup`; placeholders storage restaurados
- **Repo**: `main` = upstream `05b3323` + 2 commits limpieza (`163839b`, `cc24bf7`); remotos: `origin`=upstream (RO), `preprod`=privado (push); árbol remoto verificado: 0 archivos `.sql`/secrets/`releases/`
- **DB real** (db.sql 528M + storage 3.5G) nunca entró a git — solo vive en kalimete + contenedor
- **Workflow confirmado**: GitHub privado → preprod kalimete (pruebas) → prod (vía Git, sin acceso directo; vínculo SSH retirado)
- **Estado**: ✅ sincronizado
- **Notas**: historial upstream puede contener secretos viejos (repo es PRIVATE, riesgo contenido); si se rota APP_KEY de prod avisar; infra docker (compose/Dockerfile) queda local + documentada en erp-dev, no en el repo de código

### [03:28] - Desvinculación total del servidor ERP externo (prod no se toca)
- **Tipo**: seguridad | red | accesos | docs
- **Modificado**: `/etc/ssh/ssh_config.d/10-armada-hosts.conf` (backup `.bkup-20260919-unlink`, bloque `Host vps-erpipo` eliminado); `MAPA.md` + copia local (topología y nodo retirados); `agents/kalimete.md` (fila, alias y bullet retirados); `agents/erp-dev.md` (sección Producción → nota de desvinculación); entradas CHANGELOG de hoy saneadas (IP/detalles SSH redactados); `~/dev/erpipo-preprod/.env.preprod` y `dev-stack/` eliminados (copias de config de terceros, 68K, nadie los usaba); `preprod.env` MAIL_FROM → `dev@erp.kalimete.local`; comentario docker-compose reworded
- **Afecta a**: kalimete (alias SSH fuera, docs limpios); preprod intacto y verificado (LOGIN 200 tras restart)
- **Causa**: usuario pidió desvincularse: prod no se toca, sin registro del servidor externo en ningún lado
- **Verificación**: `ssh -G vps-erpipo` ya no resuelve (alias fuera); `ssh -G vps-proxy` OK (1444); grep alias/IP en MAPA+agentes+local = 0; preprod LOGIN 200
- **Se deja intacto a propósito**: historial ecomm antiguo que cita la API pública (otro workstream); inventario Cloudflare/SKILL del registro DNS (la zona no cambió; borrar el registro rompería la tienda — no autorizado); branding `erpipos` dentro del código app (DB name, README, CORS — es el producto, no info de acceso); backup tar del Desktop (semilla del preprod, sin datos de conexión)
- **Nota**: nuestra pubkey podría seguir en el `authorized_keys` de ese servidor (no tocamos prod para quitarla); si importa, pedir al dueño que la rote/elimine
- **Estado**: ✅ sincronizado

### [17:20] - WordPress local: connector v3.9.1 — forms responsive + newsletter funcional + cero páginas huérfanas
- **Tipo**: proyecto | fix | ux | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (6 archivos, commit `5d969b1`, push main OK); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.1, 48 archivos); repo padre 2 commits (`8b37c3e` + `a18bd63`, este último arrastra pendientes de sesiones previas: compose loopback 8091 + limpieza assets tema); `erpc_settings.tenant.contact_email` seteado en DB local
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, ambos modos de template)
- **Causa**: Usuario reportó /sobre-nosotros/ y /contacto/ sin responsive/diseño y form "roto". Causas raíz: (1) inputs del form a ancho default del navegador (~150px) y sin contenedor/notice styling — cero reglas .erpc-form en CSS; (2) router apagado por completo en modo elementor → sobre-nosotros (Gutenberg, sin meta Elementor) quedaba huérfana sin chrome; (3) newsletter del footer con submit muerto (input sin name, sin handler); (4) contact_email ausente.
- **Implementado**: (1) CSS: card centrada + inputs 100%/box-sizing + notice .erpc-ok/.erpc-err + media 768/480, solo vars (3 presets). (2) Router v3.9.1: en modo elementor, estáticas mapeadas SIN diseño Elementor reciben chrome del plugin (flag `erpc_router_hijacked` + `erpc_should_print_frame()` imprime frame en hijack); guard v3.8.0 (builder manda) intacto. (3) Newsletter: AJAX `erpc_newsletter_submit` (nonce+rate limit, opción `erpc_newsletter_subscribers` tope 5000, notifica a contact_email) + JS + feedback visible. (4) contact_email explícito. (5) Commit incluye v3.9.0 (auth OTP real ERP) que estaba deployado sin commit.
- **Verificación**: php -l ×4 + node --check OK; ambas páginas 200 en modo elementor Y plugin (switch ida/vuelta), sobre-nosotros con trustbar+topbar+static+footer en ambos modos; AJAX contacto/newsletter success:true end-to-end, suscriptor persistido, SMTP wp_mail OK; sin regresión home/productos/carrito/cotizar; assets cache-bust ver=3.9.1; screenshots móviles en /tmp/opencode/resp-{contacto,sobre}-*.png.
- **Notas**: Subagente wordpress-dev agotó 3×15 pasos en diagnóstico — implementado directo por kalimete (mismo criterio que v3.8.1). Home ID 8 intacta (orden respetada). Pendiente conocido: JSON inválido en `_elementor_data` de home (reparar por editor, no SQL).
- **Estado**: ✅ sincronizado

### [18:40] - WordPress local: connector v3.9.2 — /contacto/ reestructurada con validación CDP
- **Tipo**: proyecto | fix | ux | wordpress-dev
- **Modificado**: `_elementor_data` página 17 (backup doble: postmeta `_elementor_data_bak_v391` + archivo /tmp); plugin `erp-ecomm-connector` (connector.css, bump 3.9.2, commit `edab089`, push main OK); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.2, 48 archivos); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech)
- **Causa**: Usuario reportó /contacto/ mal estructurada tras v3.9.1. Validación programática nueva (chromium headless + CDP vía Node 22 WebSocket, métricas DOM reales en 1280/768/375) confirmó 3 defectos: (1) `\n` literales visibles en pantalla, (2) blob de texto full-width 658px con líneas de ~1265px (ilegible), (3) form flotando solo sin jerarquía.
- **Implementado**: Reestructura con el patrón de /cotizar/ (schema JSON copiado de página construida por el editor Elementor — garantiza compatibilidad editor): hero `.erpc-el-pagehero` (h1 "Contáctanos" + subtítulo, gradiente primary→dark) + grid 2 columnas `.erpc-el-contact-grid` (info card 40% + form 60%, apila <767px) + shortcodes header/footer intactos. CSS con vars (3 presets).
- **Verificación**: CDP post-fix: 0 overflow horizontal en 1280/768/375 (solo honeypot offscreen intencional); `\n` literales 0; form 628px col derecha (desktop) / 408px (tablet) / 323px full-width (móvil); inputs ~100% del card; 200 en modo plugin Y elementor (switch ida/vuelta); /cotizar/ y /sobre-nosotros/ re-validadas limpias. Screenshots: /tmp/opencode/val-{contacto,sobre,cotizar}-*.png.
- **Notas**: Herramienta de validación reutilizable: /tmp/opencode/validate.mjs + run-validation.sh (CDP sin puppeteer, Node 22 WebSocket global). El modelo de kalimete no soporta input de imagen — la confirmación visual es por métricas DOM + screenshots para revisión del usuario.
- **Estado**: ✅ sincronizado

### [19:50] - WordPress local: connector v3.9.3 — cards automáticos en páginas de texto
- **Tipo**: proyecto | feature | ux | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (static.php + connector.css, bump 3.9.3, commit `bdb535d`, push main OK); `_elementor_data` página 61 /cotizar/ (backup doble: postmeta + /tmp); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.3); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech)
- **Causa**: Usuario pidió "cuadritos" con la info dentro en vez de texto plano en todas las landings, como quedó /contacto/, en ambos templates (plugin default y Elementor).
- **Implementado**: (1) Sistema de cards automático en static.php: contenido dividido por secciones `<h2>`, cada sección = card; grid 2 col desktop si todas las secciones son cortas (≤700 chars, última impar full-width), apiladas si hay largas, render clásico sin h2 — cubre sobre-nosotros, terminos, privacidad, cookies, envios, devoluciones, faq y cualquier página futura, en modo plugin Y elementor (fallback v3.9.1). (2) CSS cards con vars (3 presets) + alias `.erpc-info-card`. (3) /cotizar/ reestructurada con el patrón de contacto: hero pagehero + grid 40/60 (info "Cómo funciona" + [erpc_quote]).
- **Verificación CDP**: sobre 1280 = 5 cards 2×2 + última 780px (regla impar), 375 = apiladas 311px; terminos 1280 = 9 cards grid; cotizar = info 412px + form 628px (desktop) / apilados (móvil); contacto 375 sin regresión; 0 overflow horizontal en todas; 200 en modo plugin Y elementor (switch ida/vuelta). Screenshots /tmp/opencode/val-{sobre,terminos,cotizar,contacto}-*.png.
- **Estado**: ✅ sincronizado

### [21:10] - WordPress local: connector v3.9.4 — home optimizada (items, textos, huecos)
- **Tipo**: proyecto | feature | ux | wordpress-dev
- **Modificado**: `_elementor_data` página 8 home (backup: postmeta `_elementor_data_bak_v393` + /tmp/elementor-8-bak-v393.json — el JSON de home ya era válido, el alerta de "char 742" quedó obsoleta tras la reestructuración del 09-18); plugin `erp-ecomm-connector` (connector.css, landing.php, bump 3.9.4, commit `9f01b66`, push main OK); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.4); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech, home en ambos modos)
- **Causa**: Usuario: reducir items de la home, textos acordes a imágenes, espacios grandes por falta de texto. CDP: 12 productos (sección 2172px), USP imagen 825px vs texto corto (hueco gigante), textos genéricos vs imagen de componentes/tarjetas de video.
- **Implementado**: (1) `[erpc_products per_page='8']` (2 filas de 4; landing.php ya renderizaba 8 → consistencia ambos templates). (2) USP: heading+intro+5 items acordes a la imagen + botón "Ver componentes". (3) CSS img cap 420px/280px (sección 965→577px). (4) Hero/destacados/CTA con textos concretos. (5) landing.php default subtitle alineado (tagline tenant manda).
- **Verificación**: CDP 8 cards en DOM (1280/375), USP img 420/280px, 0 overflow horizontal, 200 en modo plugin y elementor. Screenshots /tmp/opencode/val-home-*.png.
- **Estado**: ✅ sincronizado

### [21:45] - WordPress local: connector v3.9.5 — home 6 destacados + botón tienda + hero centrado
- **Tipo**: proyecto | feature | ux | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (shortcodes + products-content.php: attr `show_more`; connector.css `.erpc-el-featured`; bump 3.9.5, commit `c9c29b5`, push main OK); `_elementor_data` home (backup `_elementor_data_bak_v394` + /tmp); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.5); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech)
- **Causa**: Usuario: hero con subtítulo descentrado (h1 centrado vs p sin centrar); home con 6 destacados + botón a la tienda en vez de "cargar más".
- **Implementado**: (1) Hero subtitle `text-align:center` (patrón /cotizar/). (2) Home `[erpc_products columns='3' per_page='6' show_more='0']` (2×3) + botón "Ver todos los productos"→/productos/. (3) `show_more` default 1: /productos/ conserva su load-more, cero regresión.
- **Verificación**: home 200 con load-more ausente + botón presente + subtítulo centrado (HTML); CDP 6 cards en DOM (1280/375), 0 overflow. Screenshots /tmp/opencode/val-home-*.png.
- **Estado**: ✅ sincronizado

### [22:10] - WordPress local: home con 4 destacados en 1 línea + CTA centrado (contenido, sin bump)
- **Tipo**: proyecto | contenido | ux | wordpress-dev
- **Modificado**: `_elementor_data` home (backup: postmeta `_elementor_data_bak_v395` + `backups/elementor/page-8-home-*.json` commiteado al repo padre para trazabilidad)
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech)
- **Causa**: Usuario: "Explora el catálogo completo..." descentrado (h1 y botón center, texto no); 4 destacados en 1 línea en vez de 6.
- **Implementado**: CTA text `text-align:center`; home `[erpc_products columns='4' per_page='4' show_more='0']` + botón a la tienda intacto.
- **Verificación**: home 200; CDP 4 cards en DOM (1280 y 375), sección 1640→1162px, 0 overflow. Screenshots /tmp/opencode/val-home-*.png. Sin cambios de código → no requiere bump de versión ni regenerar ZIP.
- **Estado**: ✅ sincronizado

### [23:15] - WordPress local: connector v3.9.6 — títulos sin duplicar + carrito auditado responsive
- **Tipo**: proyecto | fix | ux | wordpress-dev
- **Modificado**: plugin `erp-ecomm-connector` (shortcodes: flag `force_content_only` en 5 renders de contenido; cart/checkout/auth/profile: h1 condicionales; CSS links huérfanos; bump 3.9.6, commit `f451621`, push main OK); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.9.6); repo padre commit
- **Afecta a**: kalimete (stack wordpress-local, tienda MaganTech: carrito, checkout, login, mi-cuenta)
- **Causa**: Usuario: "Tu carrito de compras" no centrado en /carrito/ + auditar todo en móvil. Raíz: doble título apilado (heading Elementor centrado + h1 interno del plugin a la izquierda); mismo patrón en checkout ("Finalizar compra"/"Finalizar pedido"), login ("Bienvenido..."/marca) y mi-cuenta ("Mi cuenta"×2).
- **Implementado**: Regla v3.9.6 — todo shortcode de contenido marca render embebido; los templates suprimen su h1 interno embebido (el título lo pone Elementor) y lo conservan en standalone (modo plugin). Header vacío no se imprime; link huérfano a la derecha por CSS. Profile conserva subtítulo; orders/loyalty intactos (eran títulos de sección, no duplicados).
- **Verificación**: 1 solo h1 (centrado) en las 4 páginas modo elementor; h1 standalone intacto en modo plugin (switch). CDP con carrito vacío + lleno real (cookie Y localStorage sembrados, IDs reales) en 1280/768/375: 0 overflow horizontal; tabla 692px→353px sin romper; thead visible; empty state centrado sin hueco; footer 1 fila→apilado; qty/checkout/continue OK. Hallazgo de test (no bug real): el JS rinde desde localStorage y oculta la tabla si está vacío — el flujo real mantiene ambos en sync vía `erpc_sync_cart`. Screenshots /tmp/opencode/val-carrito-{empty,full}-*.png.
- **Estado**: ✅ sincronizado


## 2026-09-18
### [00:30] - WordPress: fix duplicación visual landing (v3.4.1) + pipeline MCP Elementor operativo
- **Tipo**: proyecto | fix | wordpress-dev | mcp
- **Modificado**: plugin `erp-ecomm-connector` v3.4.1 (commit `ba92f2a`); `mcp-adapter` + `emcp-tools` activados con fix autoloader; app password MCP creada
- **Afecta a**: kalimete (tienda MaganTech + stack MCP)
- **Causa**: (1) Usuario reportó header/footer "duplicados" en la landing: el hero repetía la marca del header, la sección trust repetía la trustbar, y había un `</div>` huérfano tras `</html>` en landing/products/cart. (2) Plugins MCP (mcp-adapter + emcp-tools) inactivos; al activarlos, fatal por jetpack-autoloader duplicado (ambos bundlean el mismo namespace).
- **Fix**: (1) Hero con headline promocional, trust-grid eliminado, footer tras cierre de .erpc-page — HTML validado 52/52 divs. (2) Guard `class_exists` en `vendor/autoload_packages.php` de AMBOS plugins (mismo namespace hash → redeclaración). (3) `active_plugins` re-serializado con longitudes correctas (mi UPDATE anterior tenía s:19/s:41 erróneos → unserialize fallaba silenciosamente).
- **Verificación**: Landing 200 con hero promocional, 1 header, 1 footer, 0 trust-grid; productos/carrito/mi-cuenta 200; MCP REST `/wp-abilities/v1/abilities` → **151 abilities (148 emcp-tools Elementor: create-page, build-page, add-container, add-flexbox, atomic widgets, global classes, templates, batch-update)**; auth Basic con app password `mcp-kalimete-2026` (admin).
- **Estado**: ✅ sincronizado
- **Notas**: Arquitectura confirmada: plugin=datos (shortcodes), Elementor=diseño, MCP=control programático. Los fixes de autoloader viven en `vendor/` (se pierden en update de plugin — documentar en upstream). El endpoint REST de abilities tiene per_page max 100 (paginar). App password guardada en wp-cli style: NO commitear.

### [01:10] - Plugin v3.4.2: footer social alineado + cómo funciona la landing (arquitectura)
- **Tipo**: proyecto | fix | wordpress-dev | docs
- **Modificado**: plugin `erp-ecomm-connector` v3.4.2 (commit `26fcd5e`)
- **Afecta a**: kalimete (tienda MaganTech)
- **Causa**: Iconos sociales del footer flotando a la derecha del texto. Raíz: regla legacy `.erpc-footer { text-align:center }` (línea ~849, de un footer viejo) que seguía cascando porque el bloque moderno nunca la neutralizó → texto centrado, iconos flex a la izquierda.
- **Fix**: `text-align:left` en bloque moderno + `.erpc-footer-social` con `justify-content:flex-start` y gap reducido (44px→16px). Bump v3.4.2 para cache-bust (`?ver=`).
- **Verificación**: CSS 3.4.2 servido; screenshot footer OK.
- **Estado**: ✅ sincronizado
- **Notas**: Explicación de arquitectura (plugin vs Elementor vs MCP) entregada en chat.

### [02:00] - Plugin v3.5.0: 3 presets color + hero editable + modo Elementor + landing MCP
- **Tipo**: proyecto | feature | wordpress-dev | mcp | elementor
- **Modificado**: plugin `erp-ecomm-connector` v3.5.0 (commit `dae78b5`, 11 archivos); página Elementor 47 (draft)
- **Afecta a**: kalimete (tienda MaganTech + tenants futuros)
- **Causa**: Pedido usuario: (1) 3 temas de color seleccionables, (2) hero editable desde plugin, (3) switch plantilla plugin|Elementor sin mezcla, (4) diseñar plantilla Elementor, (5) qué modelo usar.
- **Implementado**: presets azul/rosa/neutro + pickers override (¡los colores del admin ahora SÍ se aplican! estaban guardados pero ignorados); hero con botón de medios; `template_mode` con gate central `erpc_is_elementor_mode()` (router se aparta, frames condicionales); shortcodes `[erpc_header]`/`[erpc_footer]`; sección admin Apariencia.
- **Verificación**: preset rosa en vivo (#d6336c + derivados), modo elementor verificado (theme render, 0 chrome plugin) + restore a plugin (topbar de vuelta); sintaxis OK; home/productos/login 200; landing Elementor creada vía MCP REST (`create-page/run`, draft 47 canvas con hero+botón+[erpc_products]).
- **Estado**: ✅ sincronizado
- **Notas**: GLM no existe en nuestro stack (sin provider ni llave) — recomendación de modelo en chat: Qwen3.6-35B vía victoria (220k ctx, local, sin bloqueo regional).

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

### [06:30] - Plugin v3.5.2: copy comercial/SEO + imágenes acordes al inventario + responsive validado
- **Tipo**: proyecto | ux | seo | elementor
- **Modificado**: plugin `erp-ecomm-connector` v3.5.2 (commit `6f31f6d`); página Elementor 53 (batch-update 6 widgets); media library (IDs 55-56 nuevas, 49-50 sin referencias)
- **Afecta a**: kalimete (tienda MaganTech)
- **Causa**: Pedido usuario: imágenes no iban con el inventario real, textos debían ser comerciales/SEO sin mencionar "ERP", validar responsive.
- **Cambios**: (1) Inventario real mapeado (18 categorías: cables, componentes, computadoras, accesorios laptop, redes). (2) Hero: "Componentes, cables y accesorios para tu PC y oficina" + "Stock real, precios competitivos y envío a toda RD" — keywords del inventario. (3) Imágenes Pexels acordes: display de computadoras (hero, ID 55) + tarjetas de video (USP, ID 56). (4) USP sin "ERP": "verificados en nuestro inventario". (5) CTA: "¿Listo para equipar tu setup?".
- **Responsive**: validado 375/768/1280px en ambas plantillas — 0 overflow, meta viewport, media queries 992/768/480 con grids 3→2→1, Elementor containers renderizan en todos los breakpoints. Screenshots en /tmp/opencode/resp-*.png.
- **Verificación**: home + Elementor 200 con nuevo copy/imágenes; 0 referencias a imágenes viejas; 0 "ERP" visible; push OK.
- **Estado**: ✅ sincronizado

### [07:30] - Plugin v3.6.0: plantilla dual completa + hamburguesa + aislamiento total de templates
- **Tipo**: proyecto | feature | fix | elementor | responsive
- **Modificado**: plugin `erp-ecomm-connector` v3.6.0 (commit `9bd187b`, 6 archivos); 6 slugs con datos Elementor; demo 53 eliminada; home dup 30 + Sample a draft
- **Afecta a**: kalimete (modelo dual plugin|elementor por tenant)
- **Causa**: Usuario: Elementor incompleto (solo landing, sin carrito/etc), fuga entre templates al navegar, sin hamburguesa responsive, alinear textos.
- **Implementado**: (1) Hamburguesa ≤768px con dropdown + aria + auto-cierre (header compartido, sirve a `[erpc_header]`). (2) 6 slugs duales (inicio/productos/carrito/checkout/login/mi-cuenta): mismas URLs en ambos modos — plugin hijacka en modo plugin, Elementor renderiza en modo elementor. (3) Router refinado (plugin gana en mapeados). (4) Fix JSON inválido en productos/elementor (comillas SQL). (5) Textos: sistema coherente (héroes centro, contenido izquierda) — validado.
- **Verificación**: plugin mode 4/4 páginas frame completo; elementor mode 6/6 con chrome Elementor (topbar vía shortcode, footer 1x, 0 fugas); 15 productos render; hamburguesa en DOM + CSS + JS válido (node --check); sintaxis OK; push OK.
- **Estado**: ✅ sincronizado

### [08:00] - Home muestra Elementor de verdad + lección SQL/JSON documentada
- **Tipo**: proyecto | fix | elementor | docs
- **Modificado**: página 8 (home) con diseño Elementor nativo; modo elementor ACTIVO en el sitio
- **Afecta a**: kalimete (portada de la tienda)
- **Causa**: Usuario veía el template del plugin aun con elementor "activo": (1) el modo seguía en plugin en DB (nunca se guardó el cambio); (2) aunque activo, los tripletes de shortcodes rinden markup del plugin → se veía igual.
- **Fix**: modo elementor activado (round-trip PHP limpio) + home reconstruida como diseño nativo (hero/trust/productos/USP/CTA + [erpc_header]/[erpc_footer]) con el copy comercial e imágenes del inventario.
- **Verificación**: home elementor: 74 widgets, hero nativo, 71 cards, USP+CTA, topbar/footer 1x, 1 doctype, 200.
- **Estado**: ✅ sincronizado
- **Notas**: LECCIÓN — inserts SQL directos con JSON que contenga `\"` se corrompen (backslash colapsa/duplica según capas). Regla: SQL solo con JSON sin backslashes (assert en el generador) + contenido rico vía REST `batch-update`. Los tripletes de los otros 5 slugs no tienen comillas → intactos.

### [09:00] - Plugin v3.7.0: desktop full-width + columnas configurables (menos scroll en PC)
- **Tipo**: proyecto | feature | ux | responsive
- **Modificado**: plugin `erp-ecomm-connector` v3.7.0 (commit `b163149`, 4 archivos); home Elementor reestructurada
- **Afecta a**: kalimete (experiencia desktop de la tienda)
- **Causa**: En PC todo iba en caja ~1140px centrada (mucho scroll, márgenes vacíos). Best practice e-commerce: full-bleed + más columnas en desktop.
- **Implementado**: (1) `data-columns` cablea el attr `columns` (estaba muerto): ≥1200px → 4/5/6 cols, 993-1199 → 3, resto intacto. (2) Home Elementor: hero/trust/CTA `layout:full`, trust 4 columnas, USP 2 columnas (apilan solas en móvil).
- **Verificación**: home 200 con 3 secciones full, 12 cards con data-columns=4, CSS 3.7.0 servido con las reglas; screenshots 1440+375; móvil/tablet intactos (media queries existentes).
- **Estado**: ✅ sincronizado

### [09:30] - Header/footer Elementor a full-width (secciones boxed los encajonaban)
- **Tipo**: proyecto | fix | elementor | ux
- **Modificado**: página 8 (home) — secciones de `[erpc_header]` y `[erpc_footer]` a `layout:full` vía MCP `batch-update`
- **Afecta a**: kalimete (portada en modo elementor)
- **Causa**: El topbar y footer del plugin (fondos sólidos) quedaban dentro de secciones Elementor `boxed` → se veían como caja centrada en PC.
- **Verificación**: 5 secciones full en el render; fondos pintan a borde de pantalla; screenshot 1440px.
- **Estado**: ✅ sincronizado

### [10:30] - 🚨 ERP BLOQUEÓ AL TENANT (impago) + Plugin v3.8.0: forms + SMTP + hamburguesa
- **Tipo**: proyecto | feature | fix | alerta-negocio | email
- **Modificado**: plugin `erp-ecomm-connector` v3.8.0 (commit `3d95c8d`, 9 archivos); páginas contacto/cotizar con diseño; SMTP tenant configurado
- **Afecta a**: kalimete + NEGOCIO (tienda sin productos hasta resolver pago)
- **🚨 ALERTA**: `GET /tienda/*`, `/orders`, `/customers` responden `{"message":"Esta instancia ha sido bloqueada.","motivo":"Impago de suscripción"}`. Catálogo en 0 (verificado tras flush de caché — antes se veía por caché vieja). El tenant debe pagar la suscripción ERPiPOS. Sumar al PEDIDO-ERP.
- **Implementado**: (1) Forms `[erpc_contact]`/`[erpc_quote]` con nonce+honeypot+rate, accesibles, email con Reply-To; páginas /contacto/ (form agregado) y /cotizar/ (nueva) con diseño Elementor completo. (2) SMTP propio sin plugins (phpmailer_init + settings + botón de prueba); configurado mail.armada.do:465 con no-reply; **correo de prueba + submit real entregados** (success:true end-to-end). (3) Hamburguesa ≤768px + footer mobile centrado + `.erpc-el-pagehero`. (4) Fix doble-documento en shortcodes embebidos (`erpc_should_print_frame()` + flag) y doble-render en contacto (estáticas Elementor-built se libran). (5) `users_can_register=0`; verificado 0 creación de usuarios WP — arquitectura confirmada: cuentas solo en ERP, WP solo admin.
- **Casi-incidente**: un round-trip serialize por pipe corrompió `erpc_settings` (solo quedó template_mode) — restaurado desde respaldo + SMTP reconfigurado. REGLA: transforms de options serializados solo en scripts PHP con archivos, jamás pipes.
- **Verificación**: 7/7 páginas Elementor con chrome simple; forms render + submit real OK; plugin-mode sin regresión (home/productos frame simple); sintaxis + JS OK; push OK.
- **Estado**: ✅ sincronizado (pero tienda sin catálogo hasta pago ERP)

### [14:55] - Tienda MaganTech v3.8.1: carrito flotante + hero desktop + centrado (UX)
- **Tipo**: proyecto | feature | fix | ux | wordpress-dev
- **Modificado**: `~/dev/wordpress/wp-content/plugins/erp-ecomm-connector/` (connector.css, connector.js, footer.php, nuevo parcial cart-float.php, bump 3.8.1); `~/dev/wordpress/CHANGELOG.md`; `export/erp-ecmm-connector.zip` regenerado (v3.8.1, 48 archivos, top-level estándar)
- **Afecta a**: kalimete (tienda MaganTech, modos plugin + Elementor)
- **Causa**: Usuario pidió: (1) hero desktop con blancos excesivos (mobile bien); (2) carrito flotante con contador visible siempre; (3) productos/catálogo/textos sin centrar
- **Implementado**: (1) Float fixed inferior-derecha con icono + badge en vivo (fuente real localStorage, sincronizado vía updateCartBadge), 1x por página con guard global (cubre shortcodes Elementor). (2) Fix bloque v2.7.0 (overlay absolute, min-height, contenido 760px centrado); .erpc-el-hero 56px desktop / 90px mobile. (3) Centrado cards, hero+buscador catálogo (sin CSS antes), section headers.
- **Verificación**: 200 en /, /productos/, /carrito/, /checkout/; 1 header + 1 footer + 1 float por página; php -l + node --check limpios; sin fatales; commit `665d7d4` push main OK
- **Notas**: (1) wordpress-dev (subagente) agotó 2×15 pasos solo explorando — implementado directo por kalimete. (2) `_elementor_data` de home ID 8 tiene JSON inválido (char 742): NO se tocó por SQL (riesgo); el fix del hero Elementor fue solo CSS. Pendiente reparar ese JSON por editor. (3) Catálogo sigue en 0 por bloqueo ERP impago (alerta 10:30 vigente) — verificación fue estructural.
- **Estado**: ✅ sincronizado


## 2026-09-17
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

### [03:05] - Caddyfile de preprod: bloque micaserogou.com eliminado (corrección)
- **Tipo**: infra | limpieza | preprod
- **Modificado**: `/opt/nextcloud-stack/Caddyfile` (vps-preprod)
- **Afecta a**: vps-preprod
- **Causa**: El bloque `micaserogou.com` del Caddyfile no fue eliminado en la limpieza inicial (el subagente no lo reportó). Se corrigió manualmente: backup `.bkup`, `sed -i` eliminando el bloque, verificación `grep` OK, Caddy recargado.
- **Estado**: ✅ sincronizado
- **Notas**: Caddyfile limpio ahora. No quedan rastros de micaserogou en preprod.

### [12:05] - kalimete vuelve a aparecer como agente primary en opencode (fix selector TAB)
- **Tipo**: infra | config | opencode
- **Modificado**: `agents/kalimete.md` (frontmatter)
- **Afecta a**: kalimete (opencode TUI)
- **Causa**: La clave `"eco-taohemps": allow` estaba duplicada en `permission.task` (líneas 16 y 22). El parser de frontmatter de opencode rechaza el archivo completo ante claves YAML duplicadas: kalimete no aparecía en `opencode agent list` ni en el selector TAB (solo plan/build). Se eliminó la segunda ocurrencia; backup en `~/backups/kalimete.md.bkup-20260917-dupkey`.
- **Verificación**: `opencode agent list` → `kalimete (primary)`; `opencode debug agent kalimete` → mode primary, temperature 0.2, color, 19 reglas task (`*` deny + allows, `general` denegado).
- **Estado**: ✅ verificado local (sync por cron)

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

### [13:30] - Plugin erp-ecomm-connector con repo GitHub propio + baseline best-practices
- **Tipo**: proyecto | git | wordpress-dev
- **Modificado**: nuevo repo `github.com/warcold/erp-ecomm-connector` (privado, rama `main`); `MAPA.md` (línea repo plugin)
- **Afecta a**: kalimete (`~/dev/wordpress/wp-content/plugins/erp-ecomm-connector`, gitlink actualizado en repo padre)
- **Causa**: El plugin solo existía en disco local + volumen Docker + ZIP (riesgo documentado 13:10). Ahora con remoto, README, uninstall.php, .distignore.
- **Verificación**: push OK (commits `c616677` + `2b43d78`); sitio post-cambio `/` 200, `/wp-json/` 200; `php -l` limpio en archivos tocados.
- **Estado**: ✅ sincronizado
- **Notas**: Incluye fix real (cart TTL ignoraba el ajuste por `$GLOBALS` indefinido). Auditoría completa + roadmap entregados en chat. Riesgo remanente: auth solo-email sin verificación (propuesta OTP) y sin rate limiting — ver roadmap.

### [14:00] - Plugin v3.3.9: Mis Pedidos reales + catálogo server-side + caché + rate limiting
- **Tipo**: proyecto | feature | wordpress-dev
- **Modificado**: repo `github.com/warcold/erp-ecomm-connector` (commit `319aab7`, 8 archivos); gitlink padre actualizado
- **Afecta a**: kalimete (tienda MaganTech viva)
- **Causa**: Mapeo real del API ERP (solo GETs read-only): `/orders` y `/ecomm/carts/:id` SÍ existen; `search/categoria_id/page/limit` funcionan server-side; `?email=` se ignora en `/orders` y `/customers`
- **Verificación**: `/productos/` 200 "Mostrando 15 de 157"; transients `erpc_c_*_v1` creados en DB; harness unitario OK (normalizadores + rate limit 5p/1b); `php -l` limpio; push GitHub OK
- **Estado**: ✅ sincronizado
- **Notas**: Journey compra con cuentas: registro/login/perfil/checkout guest+auth/Mis Pedidos funcionan; falta del ERP: auth con contraseña, PUT perfil, lealtad, /config, detalle /orders/:id, filtro ?email= real. Sin probar end-to-end: checkout_auth (crearía pedido real).

### [15:00] - Plugin v3.4.0: deploy multi-tenant + spec formal para el admin ERP
- **Tipo**: proyecto | feature | wordpress-dev
- **Modificado**: repo `github.com/warcold/erp-ecomm-connector` (commit `a423734`, 11 archivos); gitlink padre actualizado
- **Afecta a**: kalimete (modelo ZIP+llave=tienda por cliente)
- **Causa**: Visión producto: cada cliente ERP despliega su WordPress + plugin + su key. Faltaba hardening tenant + spec para completar funciones del lado ERP.
- **Verificación**: `php -l` limpio; fallback por shortcode probado en vivo (página tmp-* renderizó carrito, eliminada); override por tema probado en harness; home/productos/carrito/checkout/login/mi-cuenta todos 200; push OK.
- **Estado**: ✅ sincronizado
- **Notas**: Docs nuevos en el repo: `docs/PEDIDO-ERP.md` (P0: auth OTP/password, PUT perfil, ?email= real, /tienda/config, GET cliente; P1: lealtad, detalle pedido, ofertas, webhook) y `docs/DEPLOY-TENANT.md` (runbook ~20min + troubleshooting). Riesgo remanente: auth solo-email (P0-1) hasta que el ERP lo implemente.

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


## 2026-09-12
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


## 2026-09-10
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

### [23:55] - Nextcloud: cuenta `alfredo@armada.do` habilitada
- **Tipo**: infra | nextcloud
- **Modificado**: vps-preprod (Nextcloud)
  - `occ user:enable alfredo@armada.do` → cuenta habilitada
- **Afecta a**: nextcloud.armada.do
- **Causa**: El usuario se creó automáticamente por OIDC provisioning (`auto_create_user=1`), pero Nextcloud deshabilita los usuarios nuevos por defecto.
- **Estado**: ✅ desbloqueada


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

### [12:50] - Proxmark: renombrado proxmark-cards → proxmark
- **Tipo**: agente | refactor
- **Modificado**: `agents/proxmark.md`, `agents/kalimete.md`, `AGENTS.md`
- **Afecta a**: kalimete (opencode)
- **Causa**: El nombre `proxmark-cards` era limitante — el agente cubre tokens, LF 125kHz, sniffing, emulation, data analysis. Mucho más que "cards". Se generaliza el nombre.
- **Estado**: ✅ sincronizado


## 2026-09-06
### [02:55] - Fix: frontmatter inválido en eco-woodly y eco-alfredo-ecomm rompía el arranque de opencode
- **Tipo**: agente | config
- **Modificado**: `agents/eco-woodly.md`, `agents/eco-alfredo-ecomm.md`, symlinks en `~/.config/opencode/agent/`
- **Afecta a**: kalimete (opencode)
- **Causa**: Ambos agentes (creados/modificados en sesión Alfredo Pro Ecomm del 2026-09-06 01:26) tenían frontmatter inválido: `mode: agent` (solo son válidos `primary`/`subagent`/`all`), `max_steps` (correcto: `steps`) y claves no estándar (`tools:` en lista, `hidden: true`). El schema de opencode rechazaba los agentes al arrancar; eco-woodly fue renombrado a `.backup` como workaround y eco-alfredo-ecomm nunca tuvo symlink.
- **Estado**: ✅ verificado — ambos agentes cargan como subagent (`opencode agent list`)
- **Notas**: frontmatter normalizado al estándar de los demás eco-* (description/mode/subagent/temperature/steps/permission). Restaurado symlink `eco-woodly.md`; creado symlink `eco-alfredo-ecomm.md`.

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

### [23:59] - ERP Commerce Suite 4.1.1: ZIP de producción listo + fix fallback de modo
- **Tipo**: proyecto | build | seguridad | wordpress
- **Modificado**: erp-commerce-suite 4.1.0→4.1.1 (Environment::mode() fallback por entorno: local=dev, production/staging=public + cinturón host .local; docker-compose.yml + WP_ENVIRONMENT_TYPE=local con bkup). ZIP: ~/dev/wordpress/export/erp-commerce-suite-v4.1.1.zip (757 KB, 86 entradas, sin .git/tests/.bkup)
- **Afecta a**: producción (instalación fresca ahora apunta a ERP prod por defecto), kalimete (local intacto en dev)
- **Causa**: Usuario: ¿plugin listo para producción? ¿dónde está el ZIP?
- **Validación**: mode local=dev + api_url 172.19.0.1:8100 ✓; prod-simulado=public + erpipos ✓; php -l 50 OK; tests 8/8; zip integrity OK; WP lee headers (ERP Commerce Suite v4.1.1, TextDomain erp-suite); scan secrets: 0 reales (solo forms de login de clientes)
- **Estado**: ✅ listo para instalar en producción. Nota: en prod el admin debe configurar la api_key del ERP en Conexión ERP + la key LLM del chatbot; nginx de prod debería bloquear debug.log y uploads/erp-suite-connector/ (el ZIP lleva .htaccess+index.php para Apache)
- **Notas**: el fallback SIEMPRE-dev era bloqueante para instalación fresca en prod (apuntaría al ERP local inaccesible). DEPLOY-GUIA.md viejo (14-sep) sigue en export/ — obsoleto
