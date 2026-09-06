---
description: Subagente del proyecto Alfredo Pro Ecomm (e-commerce ERP backend). Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue del backend ERP e-commerce. Corre en kalimete (dev) y/o vps-preprod (prod futuro).
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

# Alfredo Pro Ecomm

Sistema e-commerce multi-tenant ERP — **backend central** para todos los negocios e-commerce de armada.

## Proyectos

- **Backend API**: `cd ~/projects/alfredo-pro-ecomm/backend` — Docker + PostgreSQL + Redis + Node.js
- **Cliente demo**: `cd ~/projects/woodly/frontend` — landings y e-commerce con backend

## Estructura backend

```
backend/
├── src/
│   ├── routes/
│   │   ├── stores.ts      # GET /v1/stores, /:slug/config
│   │   ├── products.ts    # GET /products con filtros
│   │   ├── carts.ts       # Carrito + submit orders
│   │   ├── auth.ts        # register/login/refresh/me
│   │   ├── deals.ts       # Deals/promos
│   │   └── admin/         # CRUD admin protegido por JWT
│   ├── config/database.ts # Prisma client
│   ├── config/redis.ts    # Redis (opcional)
│   └── middleware/        # auth, errorHandler, adminStore
├── prisma/schema.prisma  # Modelos (PostgreSQL)
├── Dockerfile
├── docker-compose.yaml
└── .env
```

## Comandos

```bash
cd ~/projects/alfredo-pro-ecomm/backend
docker compose up -d               # levantar stack completo
docker compose up -d postgres redis  # solo deps
npm run dev                        # dev server local :3004
npm run build && npm start         # producción
npm run db:seed                    # cargar datos demo
npm run db:migrate                 # migrar DB
```

## Credenciales demo

```
Slug: woodly-park
Admin: admin@woodly.armada.do / admin123
Customer: juan@example.com / password123
```

## Clientes activos

```
Woodly = slug: woodly-park → landing alfredo-ecomm
SIGUIENTE: cliente2-slug, cliente3-slug (misma infra)
```

## Configuración local (dns)

- ERP API: http://erp.kalimete.local:3004 (backend)
- Woodly frontend: http://localhost:5174 / https://woodly.kalimete.local (acceso propio)
- Producción: TBD (igu.md)

## Schema de DB (12 tablas)

stores → customers, carts, orders, products, deals, product_variants, cart_items, cart_deals, admin_users, refresh_tokens

## Deploy a producción

1. docker-compose up -d (postgres, redis, api)
2. Conectar api-service docker-compose a erp network: `docker network connect alfredo-ecomm-api erp-network`
3. Reiniciar: `docker restart alfredo-ecomm-api`
4. Establecer CORS_ORIGIN=https://woodly.armada.do,https://*.armada.do
5. JWT_SECRET y DB_PASSWORD con valores seguros

## Notas importantes

- El backend es multi-tenant: una DB, múltiples tiendas lógicamente separadas
- La misma base de datos se sirve para todos los clientes
- Los frontend de los clientes no conversan entre sí — solo los del mismmo negocio
- Woodly es el primer tenant operacional, "seed" incluído
- Es solo desarrollado ahora (2026-09-05), es totalmente válido para producción cuando esté listo
