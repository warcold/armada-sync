---
name: wp-templates
description: Sistema visual y de templates para websites de clientes construidos con el plugin Armada Suite (WordPress multi-tenant, un tenant por negocio). Usa SIEMPRE esta skill cuando el trabajo toque un website de cliente del ecosistema (micaserogou.com, magantech.com.do, futuros), el design de sus páginas (home, catálogo, contacto, reservas, sobre nosotros, login, ficha de producto), las cabeceras/banners, la atribución alfredo.pro, el preprod Docker de `~/dev/wordpress/websites/<sitio>/`, o la verificación responsive por CDP. Documenta el estándar de cabeceras de 480px, el patrón de login a sangre, la regla "el pack gana al HTML del sitio", los pitfalls del plugin compartido y el checklist de validación de 21 combinaciones.
---

# Sistema de templates WordPress (Armada Suite) — websites de clientes

Guía canónica del sistema visual de los websites de clientes. Implementada y verificada el **2026-10-22**
en **Micaserogou** (pack `restaurant`) — 21/21 combinaciones responsive OK.

- **Guía detallada (instancia de sitio)**: `~/dev/wordpress/websites/micaserogou.com/docs/GUIA-TEMPLATES-RESTAURANTE.md`
- **Template de alta de website nuevo**: `~/dev/wordpress/docs/NUEVO-WEBSITE-TEMPLATE.md`
- **Changelog del sitio**: `~/dev/wordpress/websites/micaserogou.com/CHANGELOG.md`

---

## 1. Regla de oro — qué se puede tocar

| Zona | ¿Se toca? | Motivo |
|---|---|---|
| `wp-content/plugins/armada-suite/**` | ❌ **NUNCA** | Plugin **compartido entre tenants**. Un cambio ahí rompe MaganTech, Micaserogou y los futuros. Si el fix va en el plugin → **recomendación upstream** al agente `Armada Suite` + fix site-level. |
| `wp-content/uploads/erpc/erp_suite_settings` | ❌ **NUNCA** | Se regenera en cada sync del ERP. |
| `wp-content/uploads/erpc/*.html` | ✅ Sí | HTML propio del sitio (plantillas de página). |
| `wp-content/mu-plugins/*.php` | ✅ Sí | Capa site-level: CSS y comportamiento, sin depender del plugin. |
| `assets/img/packs/<pack>/` | ✅ Sí | Fuente versionada de imágenes → se replica a `uploads/erpc/img/`. |
| `mejoras-<pack>/` | ✅ Sí | Espejo versionado de las plantillas. **Siempre en paralelo** con `uploads/erpc/`. |

---

## 2. Anatomía del render — quién manda

```
[uploads/erpc/<pagina>.html]        ← HTML propio del sitio (cuando la página lo usa)
   ├── erpc-html-filter.php  (prio 1)  reemplaza [erpc_html file="..."]
   └── erpc_remove_wpautop   (prio 8)
[templates/packs/<pack>/partials/<slug>.php]   ← TEMPLATE DEL PACK (plugin)
   ⚠️ Si el pack define el slug, GANA el pack y el HTML del sitio es CÓDIGO MUERTO
[connector.css / connector.js]      ← estilos y JS del plugin
```

**Cómo saber qué está sirviendo cada página** (nunca adivinar):

```bash
curl -sk https://<dominio>/sobre-nosotros/ | grep -c "COMENTARIO-UNICO-DEL-ARCHIVO"  # 0 = lo sirve el pack
grep -rn "COMENTARIO-UNICO" wp-content/plugins/armada-suite/templates/packs/<pack>/partials/<slug>.php
```

**Orden de cascada que rompe overrides**:
1. CSS del mu-plugin (`<head>`) — gana por defecto.
2. `<style>` inline del HTML de la página — **gana al mu-plugin** (aparece después en el documento).
3. `style="..."` en el elemento — gana a todo.

→ Si una página usa HTML propio, el override definitivo va **en ese HTML**, no solo en el mu-plugin.

---

## 3. Estándar de cabeceras (todas iguales)

**480px · `border-radius: 0` · `center/cover` · overlay cálido** en home, catálogo, contacto, reservas y "sobre nosotros".

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
        linear-gradient(135deg, rgba(122,31,31,.88) 0%, rgba(214,69,69,.72) 52%, rgba(122,31,31,.90) 100%),
        url('<banner>') center/cover no-repeat;
}
@media (max-width: 768px) { .erpc-<slug>-hero { padding: 48px 20px; } }
@media (max-width: 480px) { .erpc-<slug>-hero { padding: 36px 20px; } }
```

**Errores a evitar**: `height` en vez de `min-height` · radios distintos por página · overlay azul de tecnología
(`rgba(10,20,40)`) en sitio cálido · repetir `hero-home.webp` en varias secciones (cada sección necesita su banner).

---

## 4. Login a sangre con fondo cálido

`.erpc-auth-page` vive **dentro** de `.erpc-container` (max-width 1240px) → un `background` normal quedaría
encajonado. El fondo va en `::before` con `position:fixed` + `isolation:isolate`:

```css
.erpc-auth-page { position: relative; isolation: isolate; min-height: 100vh; min-height: 100svh; padding: 60px 20px; }
.erpc-auth-page::before {
    content: ""; position: fixed; inset: 0; z-index: -1;
    background-image:
        linear-gradient(180deg, rgba(122,31,31,.84), rgba(45,16,12,.80) 45%, rgba(122,31,31,.88)),
        url('<banner-login>') center/cover no-repeat;
}
@media (min-width: 769px) { .erpc-auth-page::before { background-attachment: fixed; } }  /* fixed en móvil = jitter */
.erpc-auth-card { max-width: 440px; width: 100%; box-sizing: border-box; margin: 0 auto; }
```

**Medido**: card 303px @375 · 440px @768 · 440px @1440.

---

## 5. Ficha de producto — el pitfall más caro

Un `.html` del sitio contiene un **IIFE de JavaScript**. Sin el cierre `})();` el navegador lanza
`SyntaxError: Unexpected end of input` y **la página entera queda muerta** (típicamente en "Cargando producto…"),
**sin error visible en el servidor**. En Micaserogou esto dejó rotas TODAS las fichas de producto.

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

## 6. Atribución alfredo.pro sin dañar el branding

Patrón tomado de PetSuite (`https://pets.armada.do/login`, SPA Vue/Vite): footer con bloque "Un producto de" + logo.

- Barra **separada**, debajo del footer del cliente. El footer del plugin y el copyright del cliente **NO se tocan**.
- SVG con el **markup exacto** extraído del bundle (`assets/index-CsG5EeBR.js` + CSS `assets/index-Cg_BL46I.css`).
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

## 7. Fix de overflow horizontal (todo el sitio)

`.erpc-container` del plugin usa `content-box` + padding lateral → ancho total = `100% + 32px` →
**32px de scroll horizontal en todas las páginas** por debajo de ~1272px.

```css
.erpc-container { box-sizing: border-box; max-width: 1280px; }
```
Render desktop **idéntico** (contenido útil 1240px) y el desborde desaparece.
**Upstream recomendado**: aplicar `box-sizing:border-box` en la regla base del plugin.

---

## 8. Imágenes — generar y desplegar

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

## 9. Verificación — Playwright NO funciona en kalimete

Falla con `Connection.init: Connection closed while reading from the driver`.
Usar **CDP por websocket**: `~/dev/wordpress/websites/micaserogou.com/scripts/shot-cdp.py`
(el chromium CLI exige `--remote-allow-origins=*`).

```bash
python3 scripts/shot-cdp.py <url> <salida.png> [ancho] [alto] --eval "<JS>"
```

### Matriz mínima de aceptación — 7 páginas × {375, 768, 1440} = 21 combinaciones

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

**Criterio de aceptación**: `scroll_h=0` · `heroes=[480]` · `radii=['0px']` · `card_w=440` · `alfredo=1` ·
`broken=0` · `logs=[]` en las 21.

---

## 10. Checklist de trabajo (cualquier negocio)

**Antes**
- [ ] Leer `docs/README.md` + `docs/WP-SIDE-CONFIG-<fecha>.md` del sitio
- [ ] `docker ps` + `curl -sI` al preprod: ¿vivo?
- [ ] Confirmar el **pack** activo y qué páginas sirve el pack vs. el HTML del sitio
- [ ] Backup `.bkup-YYYYMMDD` de cada archivo (sitio **y** espejo `mejoras-<pack>/`)

**Desarrollo**
- [ ] CSS site-level en `wp-content/mu-plugins/` (nunca en el plugin)
- [ ] `php -l` de cada PHP · `node --check` de cada `<script>` de los `.html`
- [ ] Imágenes 1600×914 WebP en `assets/img/packs/<pack>/` **y** `uploads/erpc/img/`

**Validación**
- [ ] `scripts/shot-cdp.py` sobre las 21 combinaciones
- [ ] `docker logs` sin warnings/fatals nuevos
- [ ] `curl` a cada asset nuevo (200 + content-type)

**Cierre**
- [ ] Entrada en el `CHANGELOG.md` del sitio (formato del hub `~/armada-sync/CHANGELOG.md`)
- [ ] Sección/pitfall nuevo en esta skill si se descubrió algo
- [ ] CHANGELOG del hub + `agents/<sitio>.md` + `harness/<sitio>.harness.json`

---

## 11. Pitfalls conocidos (verificados)

| # | Pitfall | Consecuencia / solución |
|---|---|---|
| 1 | Playwright roto en kalimete | Usar `scripts/shot-cdp.py` (CDP websocket) |
| 2 | `.html` sin `})();` en su IIFE | Página MUERTA sin error de servidor → `node --check` siempre |
| 3 | El pack gana al HTML del sitio | El `[erpc_html file=...]` de esa página es código muerto → override por CSS |
| 4 | CSS inline del HTML > mu-plugin | El fix definitivo va en el HTML del sitio |
| 5 | `wp-content/uploads/` es de `www-data` | `cp` falla → usar `docker cp` |
| 6 | `min-height` vs `height` en heroes | `min-height` gana; las reglas `height` del plugin son código muerto |
| 7 | `background-attachment:fixed` en móvil | Jitter al scrollear → solo ≥769px |
| 8 | Constante WP definida en 2 mu-plugins | `PHP Warning: Constant already defined` → guardar con `if (!defined(...))` |
| 9 | `smoke.sh` chequeando un permalink borrado | Falso fallo → apuntar a una página real del sitio |

---

## 12. Datos que NO son bugs

- Ítems del ERP con `stock=0` o `stock=-1` → quedan fuera del catálogo. Es **dato**, se corrige en el ERP.
- "0 productos relacionados" cuando la categoría tiene 1 solo producto → es dato.
- No tocar las imágenes de `erp.kalimete.local/storage/productos/` (vienen del ERP).
