# HTML/CSS/JS — doc viva del ecosistema

> **Verificado**: 2026-10-27 (usado en: landing LAN/pública, admin panel gateway, dashboards, forms de estudio, ragnarok-staging)
> **Docs oficiales**: https://developer.mozilla.org/es/docs/Web (MDN — referencia canónica)

## Dónde vive en el ecosistema

- `~/.victoria-custom/web/landing.html` + `landing-public.html` (CSP estricta)
- `/home/victoria/admin_template.html` (admin panel gateway, responsive móvil)
- `~/dev/ragnarok-staging/` (kalimete — landing juego RoR)
- Forms de estudio (podcast, templates)

## Patrones que usamos

- **CSP `default-src 'none'`** en páginas públicas (landing) — solo lo explícito carga
- **Responsive mobile-first** (drawer hamburguesa ≤860px, touch ≥44px, tablas→cards <640px)
- **Branding unificado** (logo watermark, favicon multi-size, OG tags 1200x630)
- Fetch + JSON para APIs internas (gateway, art API)

## Gotchas descubiertos (lecciones)

- **Con botones JS (onclick sin form), el atributo `required` nunca aplica** — validar en el JS y mostrar el error en el fetch. — (CHANGELOG)
- **Si el frontend usa FormData, los tests DEBEN simular multipart** (`curl -F`), no urlencoded — el Content-Type manda. — (CHANGELOG)
- **Gradio 6 vía API exige `"meta": {"_type": "gradio.FileData"}`** en los FileData — los errores llaman "None" sin pista. — (CHANGELOG-liveportrait)
- **Thumbs con `object-fit:cover` cortan caras** en fotos 9:16 — usar aspect-ratio por tipo de media. — (CHANGELOG-social)
- **Nginx `client_max_body_size 1M` (default) da 413 en TODO upload real** — subir a 500M en locations con uploads. — (CHANGELOG 2026-09-28)

## Regla de actualización

Sin framework (vanilla) en el stack — mantener así salvo decisión del owner.
Cambios de UI: probar en móvil Y desktop + changelog si es servicio.
