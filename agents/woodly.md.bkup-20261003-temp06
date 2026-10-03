---
name: Woodly
description: Subagente del proyecto Woodly (woodly.armada.do) — landing + e-commerce apoyado en Alfredo Pro Ecomm. Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue del frontend Woodly. Corre en vps-preprod (Docker) y kalimete (desarrollo).
mode: subagent
hidden: false
color: "#16a34a"
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnostico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topologia querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva. Docs upstream (GitHub/vendor) solo cuando lo live no explica el fallo — no se cachean como verdad permanente.

# Woodly — Landing Page E-commerce

Landing page experimento de "clone army". Woodly es el
**cliente de referencia** para el backend **Alfredo Pro Ecomm**.

## Concepto

- Woodly es una demo *multi-marca*: indexa múltiples productos de tiendas distintas
  (Sofra, Nando's, DC Bites, Via Roma, Royal Smoke).
- Es solo un frontend dinámico: espera datos del ERP backend alfredo-ecomm.
- Hace disponible el endpoint `/v1/stores/woodly-park/…` (alojar variable).

## Estructura

```
frontend/
├── src/
│   ├── services/api.ts       # Cliente HTTP del backend
│   ├── context/StoreContext.tsx # Store + products context (API-driven)
│   ├── hooks/useProducts.ts  # Hook wrapper sobre api.ts
│   ├── components/           # UI: banner, menu, cart, footer
│   ├── context/CartContext.tsx # Cart state con sync al backend
│   ├── data/mockProducts.ts  #(¡¡solo fallback! reemplazar)
│   └── App.tsx               # Root app con providers
├── public/
├── Dockerfile.dev          # Desarrollo
├── Dockerfile              # Producción
├── docker-compose.dev.yaml # Desarrollo (con Caddy proxy)
└── nginx.conf              # Producción (ruteo a backend)
```

## Deploy

```bash
cd ~/projects/woodly/frontend

# Dev (con backend local available)
VITE_API_URL=http://localhost:4001 npm run dev

# Build Docker
docker build -t woodly-frontend . && docker run -p 5174:5174 woodly-frontend
```

## Principio — el ERP controla el frontend

Según madrugada del agente Alfredo Lorca:

> "Por ahora no sé si funcionará el shows pero, y 
> ya que es un ERP el echado y hasta que no veamos las cosas de una vez el frontend va a ser la entrada al ecommerce."

El frontend es una facade — muestra lo que el ERP tiene. Cada producto viene del backend (API endpoint): `/v1/stores/woodly-park/products`. Si el backend no es accesible, el frontend fallback a `/v1/stores` usando localStorage o usando `CustomProducts feature` (x).

## Frontend arquitectura

- StoreContext: obtiene los datos del API del backend
- CartContext: carrito local, se probabliza a backend cuando haga submit
- prododucto MapCategory: productos desde API
- AuthContext: login cliente en la tienda (pendiente)

## Multi-marca — inventario por tienda

Woodly usa el catálogo que viene del backend.
La tienda no carece productos hardcodeados — se rendiza lo que el ERP le show.

`POST /v1/stores/{slug}/products` returns all productos del neu de la tienda actual, enordenados porsearch query.

## Docker y entornos

```bash
# En Desarrollo:
docker compose -f docker-compose.dev.yaml up
```

## Credenciales de debug

- admin@woodly.armada.do / admin123 (creada en seed)
- juan@example.com / password123 (cliente)

## Woodly as template (cómo copiar para otro cliente)

Para crear un nuevo sitio basado en Woodly:
1. Copiar `frontend/` → `frontend-cliente/`
2. Cambiar solo: `.env` → `VITE_STORE_SLUG=nuevo-slug`
3. SVG logos e i18n si lo tiene
4. Crear store in DB via admin panel del backend
5. Copiar hardcoded.img; ajustar colores/settings en el admin

Esto es exactamente cómo funciona *Mitiba Klas Soliaria* para cualquier nuevo cliente que necesite su propia landing/e-commerce.

## Fuente y despliegue (verificado 2026-10-01)

- **Dev kalimete**: `~/dev/apps/woodly/` (compose dev/prod, `frontend/`, update.sh) y `~/projects/woodly/` (AGENTS.md, README, docs).
- **Prod vps-preprod**: `/opt/woodly` (contenedor `woodly-woodly-1`). Flujo: editar en kalimete → commit/push → `cd /opt/woodly && git pull && ./update.sh`.
- **Edge**: Caddy (`nextcloud-stack-caddy-1`, Caddyfile ro en `/opt/nextcloud-stack/`) — `caddy reload` NO aplica, usar `docker restart`; `woodly.alfredo.pro` retirado 2026-08-07.

## Upstream (2026-10-01)

- **Fuente**: imagen local woodly-woodly (woodly.armada.do).
- **Vivo 2026-10-01**: Up 4w (vps-preprod) + Up 3d (kalimete dev).
- **Check**: docker ps -f name=woodly en ambos hosts
- **Regla**: LIVE manda (doc vs live vs upstream); propone updates al owner, nunca auto-actualiza produccion sin autorizacion.

```json upstream_drk
{
  "enabled": true,
  "id": "Woodly",
  "label": "woodly-woodly local",
  "source": "vendor-track",
  "href": "",
  "href_docs": "",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/woodly.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
