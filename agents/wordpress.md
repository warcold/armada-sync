---
name: WordPress
description: Agente PRINCIPAL DE PLATAFORMA WordPress (umbrella). Gestiona el SISTEMA WordPress: core WP, contenedores Docker, compose, certs, secrets, DB, nginx/TLS, deploy del stack + orquesta subagentes. Subagentes: ZionV CRM (core CRM), ZionV Commerce (ERP/Commerce dependiente), Micaserogou, MaganTech, ERP Dev. Kalimete delega a WordPress. Pack default = "neutral" (no tech). Plugin Commerce/ERP separado que DEPENDE de ZionV CRM core. Packs: neutral (default), tech (MaganTech), restaurant (Micaserogou).
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

> **Frescura** — el diagnóstico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topología querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva. Docs upstream (GitHub/vendor) solo cuando lo live no explica el fallo — no se cachean como verdad permanente.

# WordPress — Agente Principal de Plataforma (Umbrella)

## Visión General

**WordPress** es el **AGENTE PRINCIPAL DE PLATAFORMA** que gestiona el SISTEMA WordPress completo y orquesta todos los subagentes del ecosistema WordPress. Kalimete (orquestador principal) delega en WordPress para todo lo relacionado con la plataforma WP.

### Jerarquía Completa

```
Kalimete (Orquestador Principal)
    └── WordPress (Agente Principal de Plataforma - Umbrella)
            ├── ZionV CRM Core (Subagente - Plugin CRM independiente)
            ├── ZionV Commerce (Subagente - Plugin ERP/Commerce DEPENDIENTE de ZionV CRM)
            ├── Micaserogou (Subagente - Website cliente, pack restaurant)
            ├── MaganTech (Subagente - Website cliente, pack tech)
            └── ERP Dev (Subagente - Preprod ERP erpipo para integración)
```

### Principios Fundamentales

1. **WordPress NO desarrolla plugins ni websites** — delega a subagentes especializados
2. **Cada plugin su agente** (regla owner 2026-10-15): ZionV CRM, ZionV Commerce, Armada Suite tienen agentes propios
3. **Cada website cliente su agente** (regla owner 2026-10-17): Micaserogou, MaganTech tienen agentes propios
4. **Pack default = "neutral"** (sin tecnología, genérico)
5. **ZionV Commerce DEPENDE de ZionV CRM Core** — instalación ordenada obligatoria: CRM → Commerce
6. **Packs**: neutral (default), tech (MaganTech), restaurant (Micaserogou)

---

## Infraestructura del Hub WordPress

### Docker Stack Principal (Dev Lab Armada Suite)

- **Path**: `~/dev/wordpress/` (hub — NO es repo git; el repo del plugin Armada Suite vive en `plugins/armada-suite/`)
- **Contenedor principal**: `wordpress-local` (imagen `wordpress:7.1.3-php8.3-apache`, WP core **7.1.3** + PHP 8.3)
- **Contenedor DB**: `wordpress-db` (MariaDB 10.11, puerto host 3307)
- **Puertos**:
  - `http://localhost:8091` — WordPress Frontend/REST (loopback)
  - `localhost:3307` — MariaDB
- **Red**: `erpipo-dev-network` compartida con erpipo (para webhooks ERP→WP); `WORDPRESS_DB_HOST=wordpress-db:3306`
- **Deploy prod del stack**: `docker-compose.prod.yml` + `DEPLOY-PRODUCCION.md`

### Estructura del Hub (reorg 2026-10-17)

```
~/dev/wordpress/
├── README-HUB.md                    # Inventario del hub
├── docs/                            # Docs compartidos del hub
│   ├── CONEXION-METODO.md           # Método canónico de conexión WP
│   ├── NUEVO-WEBSITE-TEMPLATE.md    # Playbook de alta de websites
│   └── ESTADO-ECOSISTEMA.md         # Matriz de intercambio entre clientes
├── plugins-disponibles/             # Catálogo de plugins disponibles
├── scripts/                         # Scripts canónicos del hub
│   ├── smoke-8091.sh                # Smoke test dev lab
│   ├── smoke-8093.sh                # Smoke test MaganTech
│   ├── smoke-8094.sh                # Smoke test Micaserogou
│   └── plugin-preprod.sh            # Instalación de plugin en preprod (artefacto ZIP)
├── plugins/
│   ├── armada-suite/                # Dev lab Armada Suite (:8091) - SOURCE del plugin
│   │   ├── wp-content/plugins/armada-suite/  # Source del plugin (git)
│   │   ├── export/                           # ZIPs canónicos de release
│   │   ├── certs/                            # CA bundle mkcert
│   │   └── secrets/                          # App Passwords (600, gitignored)
│   └── zionv-crm/                 # Stack ZionV CRM (:8092) - Plugin CRM independiente
│       ├── wp-content/plugins/zionv-crm-plugin/  # Repo git GitHub warcold/zionv-crm
│       ├── export/                            # ZIPs de release
│       └── certs/                             # CA bundle mkcert
└── websites/                        # Websites de clientes (preprod local)
    ├── magantech.com.do/            # Preprod MaganTech (:8093, pack tech)
    │   ├── docker-compose.yml
│   │   ├── scripts/
│   │   ├── docs/
│   │   └── assets/img/packs/tech/
│   └── micaserogou.com/             # Preprod Micaserogou (:8094, pack restaurant)
│       ├── docker-compose.yml
│       ├── scripts/
│       ├── docs/
│       └── assets/img/packs/restaurant/
```

---

## Subagentes Gestionados por WordPress

### 1. ZionV CRM Core (Plugin CRM Independiente)

- **Agente**: `zionv-crm` (`agents/zionv-crm.md`)
- **Stack**: Docker independiente en `~/dev/wordpress/plugins/zionv-crm/` (puerto :8092, DB :3308)
- **Dominio**: `https://zionv.kalimete.local` (nginx TLS mkcert)
- **Plugin**: `zionv-crm-plugin` v1.56.3, DB 1.24.0, 43 tablas, 35 controllers / 123 rutas REST
- **Permalinks**: PRETTY obligatorios (`/%postname%/`) — SPA en `/crm/`, reservaciones en `/reservar/`
- **Integraciones**: SMTP, Google Calendar, MS365 (Teams), Nextcloud CalDAV, HubSpot, IA OpenAI-compat (Victoria PUBLIC)
- **Regla**: **NUNCA consume ERP** — `business_mode = zion_crm` / `none`

### 2. ZionV Commerce (Plugin ERP/Commerce - DEPENDE de ZionV CRM)

- **Agente**: `zionv-commerce` (por crear - nuevo subagente)
- **Tipo**: Plugin WordPress **dependiente** — requiere ZionV CRM Core activo
- **Función**: Integración completa con ERP (erpipo) para ecommerce
- **Endpoints ERP**: Catálogo público (store-key `iak_*`), Storefront (client-token), Webhooks, Health
- **Tenants atendidos**: 10 (MaganTech), 3 (Micaserogou) — ambos `business_mode = ecommerce`
- **Autenticación**: InstanceApiKey (store-key) para catálogo/admin; ClientApiToken (client-token) para operaciones personales
- **Webhooks ERP→WP**: `order.created`, `stock.updated`, `price.updated` (HMAC-SHA256)
- **Delta-sync**: Client-side (ERP no expone `?since=`) — catálogo cada 15-30min, stock cada 5min, webhooks tiempo real

### 3. Micaserogou (Website Cliente - Pack Restaurant)

- **Agente**: `micaserogou` (`agents/micaserogou.md`)
- **Preprod**: `http://localhost:8094` + `https://micaserogou.kalimete.local` (tenant ERP 3)
- **Producción**: `https://micaserogou.com/` (cPanel externo, WP 7.1.3, Armada Suite 5.4.2)
- **Pack**: `restaurant` (cabeceras 480px cálidas, login a sangre, fichas producto con IIFE JS)
- **Flujo**: Local-first (artefactos ZIP; preprod espejo de prod); prod solo ventana + rollback

### 4. MaganTech (Website Cliente - Pack Tech)

- **Agente**: `magantech` (`agents/magantech.md`)
- **Preprod**: `http://localhost:8093` + `https://magantech.kalimete.local` (tenant ERP 10)
- **Producción**: `https://magantech.com.do/` (cPanel externo, WP 7.1.3, Armada Suite)
- **Pack**: `tech` (colores #1a73e8/#34a853, identidad tech)
- **Flujo**: Local-first idéntico a Micaserogou

### 5. ERP Dev (Preprod ERP erpipo)

- **Agente**: `erp-dev` (`agents/erp-dev.md`)
- **Stack**: `~/dev/erpipo-preprod/` (dockerizado en kalimete, :8100)
- **URL**: `https://erp.kalimete.local` (nginx TLS)
- **Upstream**: Juan Carlos (`soycarlosjerez-hub/sistema-facturacion`, rama `dev/ecomm-erp`)
- **Workflow**: Kalimete actualiza `dev/ecomm-erp` → push → Juan Carlos mergea a `main` y despliega a prod
- **Tenants**: 10 (MaganTech), 3 (Micaserogou) — `business_instances` tabla

---

## Flujo de Instalación/Activación: ZionV CRM → ZionV Commerce

### Orden Obligatorio

```bash
# 1. PRIMERO: ZionV CRM Core (independiente)
# - Stack Docker propio (:8092)
# - Plugin zionv-crm-plugin activado
# - Permalinks PRETTY activados (/%postname%/)
# - Configuración: SMTP, Calendarios, IA (Victoria), etc.
# - Verificar: /crm/dashboard/ 200, /crm/configuracion/ 200

# 2. SEGUNDO: ZionV Commerce (dependiente)
# - Plugin zionv-commerce activado SOLO si ZionV CRM está activo
# - Verifica dependencia en activación: if (!is_plugin_active('zionv-crm-plugin/...')) wp_die()
# - Configura integración ERP: store-key (iak_*), webhooks, tenant_id
# - Verificar: endpoints ERP responden, webhooks entregados, catálogo sincronizado
```

### Verificación de Dependencia (en ZionV Commerce)

```php
// En zionv-commerce.php - activación
register_activation_hook(__FILE__, function() {
    if (!is_plugin_active('zionv-crm-plugin/zionv-crm-plugin.php')) {
        deactivate_plugins(plugin_basename(__FILE__));
        wp_die('ZionV Commerce requiere ZionV CRM Core activo. Instala y activa ZionV CRM primero.');
    }
    // Verificar versión mínima de CRM
    $crm_version = get_option('zion_crm_version', '0');
    if (version_compare($crm_version, '1.56.0', '<')) {
        wp_die('ZionV Commerce requiere ZionV CRM >= 1.56.0');
    }
});
```

### Configuración ERP en ZionV Commerce

```php
// Settings page: /wp-admin/admin.php?page=zionv-commerce-erp
// Campos:
// - ERP Base URL: https://erp.kalimete.local (preprod) / https://erpipos.armada.do (prod)
// - Store Key (iak_*): para catálogo público y operaciones admin
// - Webhook Secret: compartido con ERP (webhook_endpoints.secret)
// - Tenant ID: se deriva AUTOMÁTICAMENTE de la iak (NUNCA enviarlo en body/query)
// - Business Mode: ecommerce (forzado si ZionV Commerce activo)
```

---

## Gestión de Packs

### Packs Disponibles

| Pack | Descripción | Negocio | Colores | Cabeceras |
|------|-------------|---------|---------|-----------|
| **neutral** | Default, sin tecnología, genérico | Cualquiera | Neutros | 480px, radius 0, overlay neutro |
| **tech** | Tecnología, identidad MaganTech | MaganTech | #1a73e8 / #34a853 | 480px, radius 0, overlay tech |
| **restaurant** | Restaurante, identidad Micaserogou | Micaserogou | Cálidos (#7a1f1f, #d64545) | 480px, radius 0, overlay cálido |

### Estructura de Packs (en plugin Armada Suite)

```
armada-suite/
└── templates/
    └── packs/
        ├── neutral/
        │   └── partials/
        │       ├── hero.php
        │       ├── about.php
        │       ├── contact.php
        │       ├── reservations.php
        │       └── catalog.php
        ├── tech/
        │   └── partials/ (mismos slugs, estilos tech)
        └── restaurant/
            └── partials/ (mismos slugs, estilos restaurant)
```

### Regla: "El Pack Gana al HTML del Sitio"

```bash
# Si templates/packs/<pack>/partials/<slug>.php EXISTE:
#   → El pack renderiza ese slug
#   → El [erpc_html file="<slug>.html"] de la página WP queda como CÓDIGO MUERTO
#   → Override visual va por CSS site-level (mu-plugin), NO editando el HTML del sitio

# Verificación:
curl -sk https://<dominio>/<slug>/ | grep -c "COMENTARIO-UNICO-DEL-PACK"
# 1 = lo sirve el pack; 0 = lo sirve el HTML del sitio
```

### Activación de Pack (por tenant/website)

```php
// En wp-admin → Ajustes → Armada Suite → Pack
// O vía código:
update_option('erp_suite_template_pack', 'restaurant'); // 'neutral' | 'tech' | 'restaurant'

// El pack se aplica GLOBALMENTE al sitio (un tenant = un sitio = un pack)
// No hay packs por página; el pack define TODOS los partials del sitio
```

---

## Templates Compatibles (Instrucciones para Crear Templates)

### Regla de Oro: Qué SE PUEDE Tocar

| Zona | ¿Se toca? | Motivo |
|------|-----------|--------|
| `wp-content/plugins/armada-suite/**` | ❌ **NUNCA** | Plugin **compartido entre tenants**. Un cambio rompe MaganTech, Micaserogou y futuros. Fix → recomendación upstream al agente `Armada Suite` + fix site-level. |
| `wp-content/uploads/erpc/erp_suite_settings` | ❌ **NUNCA** | Se regenera en cada sync del ERP. |
| `wp-content/uploads/erpc/*.html` | ✅ **SÍ** | HTML propio del sitio (plantillas de página). |
| `wp-content/mu-plugins/*.php` | ✅ **SÍ** | Capa site-level: CSS y comportamiento, sin depender del plugin. |
| `assets/img/packs/<pack>/` | ✅ **SÍ** | Fuente versionada de imágenes → se replica a `uploads/erpc/img/`. |
| `mejoras-<pack>/` | ✅ **SÍ** | Espejo versionado de las plantillas. **Siempre en paralelo** con `uploads/erpc/`. |

### Anatomía del Render — Quién Manda

```
[uploads/erpc/<pagina>.html]        ← HTML propio del sitio (cuando la página lo usa)
    ├── erpc-html-filter.php  (prio 1)  reemplaza [erpc_html file="..."]
    └── erpc_remove_wpautop   (prio 8)
[templates/packs/<pack>/partials/<slug>.php]   ← TEMPLATE DEL PACK (plugin)
    ⚠️ Si el pack define el slug, GANA el pack y el HTML del sitio es CÓDIGO MUERTO
[connector.css / connector.js]      ← estilos y JS del plugin
```

### Cómo Saber Qué Sirve Cada Página (Nunca Adivinar)

```bash
# 1. Buscar comentario único en el pack
grep -rn "COMENTARIO-UNICO" wp-content/plugins/armada-suite/templates/packs/<pack>/partials/<slug>.php

# 2. Verificar en vivo
curl -sk https://<dominio>/<slug>/ | grep -c "COMENTARIO-UNICO-DEL-PACK"
# 1 = pack; 0 = HTML del sitio
```

### Orden de Cascada CSS (Rompe Overrides)

1. CSS del mu-plugin (`<head>`) — gana por defecto
2. `<style>` inline del HTML de la página — **gana al mu-plugin** (aparece después)
3. `style="..."` en el elemento — gana a todo

→ Si una página usa HTML propio, el override definitivo va **en ese HTML**, no solo en el mu-plugin.

---

## Estándar de Cabeceras (Todas Iguales)

**480px · `border-radius: 0` · `center/cover` · overlay** en home, catálogo, contacto, reservas y "sobre nosotros".

```css
.erpc-<slug>-hero {
    box-sizing: border-box;
    min-height: 480px;          /* SOLO min-height: min-height gana sobre height */
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 64px 20px;
    border-radius: 0;
    background:
        linear-gradient(135deg, <color-inicio> 0%, <color-medio> 52%, <color-fin> 100%),
        url('<banner>') center/cover no-repeat;
}
@media (max-width: 768px) { .erpc-<slug>-hero { padding: 48px 20px; } }
@media (max-width: 480px) { .erpc-<slug>-hero { padding: 36px 20px; } }
```

**Colores por Pack:**

| Pack | Inicio | Medio | Fin |
|------|--------|-------|-----|
| neutral | `rgba(80,80,80,.88)` | `rgba(120,120,120,.72)` | `rgba(80,80,80,.90)` |
| tech | `rgba(10,30,60,.88)` | `rgba(26,115,232,.72)` | `rgba(10,30,60,.90)` |
| restaurant | `rgba(122,31,31,.88)` | `rgba(214,69,69,.72)` | `rgba(122,31,31,.90)` |

**Errores a evitar**: `height` en vez de `min-height` · radios distintos por página · overlay azul de tecnología en sitio cálido · repetir `hero-home.webp` en varias secciones.

---

## Login a Sangre con Fondo Cálido

`.erpc-auth-page` vive **dentro** de `.erpc-container` (max-width 1240px) → un `background` normal quedaría encajonado. El fondo va en `::before` con `position:fixed` + `isolation:isolate`:

```css
.erpc-auth-page { position: relative; isolation: isolate; min-height: 100vh; min-height: 100svh; padding: 60px 20px; }
.erpc-auth-page::before {
    content: ""; position: fixed; inset: 0; z-index: -1;
    background-image:
        linear-gradient(180deg, <color-inicio>, <color-medio> 45%, <color-fin>),
        url('<banner-login>') center/cover no-repeat;
}
@media (min-width: 769px) { .erpc-auth-page::before { background-attachment: fixed; } }  /* fixed en móvil = jitter */
.erpc-auth-card { max-width: 440px; width: 100%; box-sizing: border-box; margin: 0 auto; }
```

**Medido**: card 303px @375 · 440px @768 · 440px @1440.

---

## Ficha de Producto — Pitfall Crítico

Un `.html` del sitio contiene un **IIFE de JavaScript**. Sin el cierre `})();` el navegador lanza `SyntaxError: Unexpected end of input` y **la página entera queda muerta** (típicamente en "Cargando producto…"), **sin error visible en el servidor**.

**Siempre antes de desplegar un `.html` con JS:**

```bash
python3 - << 'PY'
import re, pathlib, subprocess
for p in pathlib.Path('wp-content/uploads/erpc').glob('*.html'):
    for i, js in enumerate(re.findall(r'<script[^>]*>(.*?)</script>', p.read_text(), re.S)):
        if js.strip():
            r = subprocess.run(['node','--check','-'], input=js, text=True, capture_output=True)
            print(f"{'✅' if r.returncode==0 else '❌'} {p.name} script#{i}")
            if r.returncode: print(r.stderr[:400])
PY
```

---

## Atribución alfredo.pro Sin Dañar el Branding

Patrón tomado de PetSuite: footer con bloque "Un producto de" + logo.

- Barra **separada**, debajo del footer del cliente. El footer del plugin y el copyright del cliente **NO se tocan**.
- SVG con el **markup exacto** extraído del bundle.
- Opacidad `.55` en reposo → `1` al hover. `target="_blank" rel="noopener noreferrer"` + `aria-label`.
- Vía `wp_footer` prioridad **30** (después del footer del plugin).

```php
add_action( 'wp_footer', function () {
    if ( is_admin() ) return;
    echo '<div class="erpc-alfredo-bar"><a class="site-footer-brand" href="https://alfredo.pro"
            target="_blank" rel="noopener noreferrer" aria-label="alfredo.pro">
            <svg class="alfredo-logo" ...>...</svg>
            <span class="site-footer-brand-label">Un producto de</span></a></div>';
}, 30 );
```

**Validación**: `document.querySelectorAll('.alfredo-logo').length === 1` en **todas** las páginas (2 = duplicado, 0 = ausente).

---

## Fix de Overflow Horizontal (Todo el Sitio)

`.erpc-container` del plugin usa `content-box` + padding lateral → ancho total = `100% + 32px` → **32px de scroll horizontal** en todas las páginas por debajo de ~1272px.

```css
.erpc-container { box-sizing: border-box; max-width: 1280px; }
```

Render desktop **idéntico** (contenido útil 1240px) y el desborde desaparece.
**Upstream recomendado**: aplicar `box-sizing:border-box` en la regla base del plugin (agente `Armada Suite`).

---

## Imágenes — Generar y Desplegar

Skill `art` (gateway de Victoria, Z-Image-Turbo). El PNG sale a **1344×768**; el sitio necesita **1600×914**.

```bash
curl -s -H "Authorization: Bearer $KEY" "http://10.0.0.5:8010/v1/art-files/<archivo>.png" -o /tmp/opencode/banner.png
python3 - << 'PY'
from PIL import Image
im = Image.open('/tmp/opencode/banner.png').convert('RGB').resize((1600,914), Image.LANCZOS)
im.save('assets/img/packs/<pack>/banner-<slug>.webp','WEBP',quality=82,method=6)
PY
docker cp assets/img/packs/<pack>/banner-<slug>.webp <contenedor>:/var/www/html/wp-content/uploads/erpc/img/banner-<slug>.webp
curl -sk -o /dev/null -w '%{http_code} %{content_type}\n' https://<dominio>/wp-content/uploads/erpc/img/banner-<slug>.webp
```

**Pitfall**: `wp-content/uploads/` es de `www-data` → `cp` falla con *Permission denied*. Usar **`docker cp`**.
**Peso**: 53–146 KB por banner (WebP q82). Mantener < 200 KB.

---

## Verificación — Playwright NO Funciona en Kalimete

Falla con `Connection.init: Connection closed while reading from the driver`.
Usar **CDP por websocket**: `~/dev/wordpress/websites/micaserogou.com/scripts/shot-cdp.py` (el chromium CLI exige `--remote-allow-origins=*`).

```bash
python3 scripts/shot-cdp.py <url> <salida.png> [ancho] [alto] --eval "<JS>"
```

### Matriz Mínima de Aceptación — 7 páginas × {375, 768, 1440} = 21 combinaciones

```js
JSON.stringify({
  scroll_h: document.documentElement.scrollWidth - document.documentElement.clientWidth,   // 0
  heroes:  [...document.querySelectorAll('.erpc-<slug>-hero')].map(e=>Math.round(e.getBoundingClientRect().height)), // 480
  radii:   [...document.querySelectorAll('.erpc-<slug>-hero')].map(e=>getComputedStyle(e).borderBottomLeftRadius), // 0px
  card_w:  document.querySelector('.erpc-auth-card')?.getBoundingClientRect().width,       // 440 (303 @375)
  alfredo: document.querySelectorAll('.alfredo-logo').length,                               // 1
  broken:  [...document.images].filter(i=>i.complete&&i.naturalWidth===0).length,           // 0
  logs:    window.__logs                                                                  // []
})
```

**Criterio de aceptación**: `scroll_h=0` · `heroes=[480]` · `radii=['0px']` · `card_w=440` · `alfredo=1` · `broken=0` · `logs=[]` en las 21.

---

## Comandos Canónicos del Hub

```bash
# Estado del hub
docker ps --filter name=wordpress
docker ps --filter name=zionv
docker ps --filter name=micaserogou
docker ps --filter name=magantech

# Salud dev lab Armada Suite (:8091)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8091/
curl -s "http://localhost:8091/index.php?rest_route=/wp/v2/posts?_fields=title,slug"

# Salud ZionV CRM (:8092)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8092/
curl -sk -o /dev/null -w '%{http_code}\n' https://zionv.kalimete.local/crm/dashboard/

# Salud MaganTech (:8093)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8093/
curl -sk -o /dev/null -w '%{http_code}\n' https://magantech.kalimete.local/

# Salud Micaserogou (:8094)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8094/
curl -sk -o /dev/null -w '%{http_code}\n' https://micaserogou.kalimete.local/

# Smoke tests (scripts canónicos del hub)
bash ~/dev/wordpress/scripts/smoke-8091.sh   # Dev lab
bash ~/dev/wordpress/scripts/smoke-8093.sh   # MaganTech
bash ~/dev/wordpress/scripts/smoke-8094.sh   # Micaserogou

# Instalación de plugin en preprod (artefacto ZIP)
bash ~/dev/wordpress/scripts/plugin-preprod.sh ~/dev/wordpress/websites/magantech.com.do <zip>
bash ~/dev/wordpress/scripts/plugin-preprod.sh ~/dev/wordpress/websites/micaserogou.com <zip>

# WP-CLI sidecar (método canónico del hub)
# Ver ~/dev/wordpress/docs/CONEXION-METODO.md
```

---

## Autenticación (Sistema WordPress Hub)

- **WP-Admin**: usuario `admin` (login por UI; la password de login NO sirve para REST — da 401)
- **REST API**: Application Passwords (Basic Auth). Activa (user admin): `mcp-kalimete-2026` — única restante
- **Verificación REST**: `curl -u "admin:<app-password>" "http://localhost:8091/index.php?rest_route=/erpsuite/v1/ops/status"` → 200; anónimo → 403 `erpsuite_forbidden`
- **Receta de rotación de App Password**: `create_new_application_password()` devuelve `[$plaintext, $item]` — el plaintext es `$new[0]`. Escribir a archivo DENTRO del contenedor y sacarlo con `docker cp` — nunca por stdout.

---

## Reglas de Operación

1. **NUNCA modificar directamente** archivos del contenedor (mount volúmenes)
2. **Siempre verificar** estado de contenedores antes de operar
3. **Cada plugin su agente**: no desarrollar plugins desde aquí — delegar a `ZionV CRM`, `ZionV Commerce`, `Armada Suite`
4. **Cada website su agente**: no operar websites desde aquí — delegar a `MaganTech`, `Micaserogou`
5. **Secrets**: App Passwords y keys viven en `~/dev/wordpress/plugins/<plugin>/secrets/` (600, gitignored, fuera del ZIP) — jamás en docs, chat o commits
6. **No confliger** con producción (este es local dev only)
7. **Permalinks**: live `/%postname%/`; REST SIEMPRE vía `index.php?rest_route=` por diseño del plugin
8. **Instalación ordenada**: ZionV CRM → ZionV Commerce (dependencia dura)
9. **Pack default = neutral**: si no se especifica, el sitio usa pack neutral
10. **LIVE manda**: verificar antes de afirmar; lo no verificado se marca pendiente, nunca se inventa

---

## Docs Oficiales

> Regla: ANTES de programar/configurar WordPress, consultar estas fuentes. Si no cubren el caso, verificar contra el LIVE. NUNCA inventar hooks/filtros WP.

- **WordPress Developer**: https://developer.wordpress.org/
- **WordPress Documentation**: https://wordpress.org/documentation/
- **Plugin Handbook**: https://developer.wordpress.org/plugins/
- **Sistema visual websites**: skill `wp-templates` (`~/.config/opencode/skills/wp-templates/SKILL.md`)

---

## Upstream

- **Fuente**: wordpress:7.1.3-php8.3-apache + mariadb:10.11 (kalimete)
- **Vivo 2026-10-28**: hub reorg `plugins/`+`websites/`; preprod clientes magantech :8093 + micaserogou :8094; dev lab Armada Suite :8091; ZionV CRM :8092; ERP Dev :8100
- **Check**: `docker ps -f name=wordpress` + `docker ps -f name=zionv` + `docker ps -f name=micaserogou` + `docker ps -f name=magantech` + smokes respectivos
- **Regla**: LIVE manda (doc vs live vs upstream); propone updates al owner, nunca auto-actualiza producción sin autorización.

```json upstream_drk
{
  "enabled": true,
  "id": "wordpress",
  "label": "wordpress:7.1.3-php8.3-apache (hub tag)",
  "source": "hub.docker.com/_/wordpress latest-tag",
  "href": "hub.docker.com/_/wordpress",
  "href_docs": "https://wordpress.org/documentation/",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/wordpress.harness.json` (scope + live_check + upstream + docs + changelog de este agente).

---

## Cambios Recientes

- **2026-10-28**: Arquitectura completa final — WordPress como agente principal de plataforma (umbrella) gestionando subagentes ZionV CRM, ZionV Commerce, Micaserogou, MaganTech, ERP Dev. Pack default = neutral. Flujo instalación ZionV CRM → ZionV Commerce. Gestión packs: neutral/tech/restaurant. Templates compatibles documentados.
- **2026-10-17**: Hub reorg `plugins/` + `websites/`; preprod clientes separados; dev lab solo loopback.
- **2026-10-15**: Split agente — wordpress-dev redimensionado a SISTEMA (umbrella); plugin Armada Suite → agente propio `armada-suite`.
- **2026-10-06**: Red compartida erpipo-dev-network + WORDPRESS_DB_HOST=`wordpress-db:3306`.
- **2026-10-05**: Stack TLS CA bundle mkcert + extra_hosts; gitignore secrets/.