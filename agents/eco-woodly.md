---
description: Subagente del proyecto Woodly (woodly.armada.do) — landing + e-commerce apoyado en Alfredo Pro Ecomm. Corre en vps-preprod (Docker) y kalimete (desarrollador).
tools:
  - bash
  - read
  - write
  - edit
  - glob
  - grep
  - webfetch
model: nvidia/moonshotai/kimi-k3
mode: agent
permission:
  edit: allow
  write: allow
  bash: allow
  webfetch: allow
temperature: 0.1
max_steps: 15
hidden: true
---

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
