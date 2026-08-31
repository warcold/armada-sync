---
description: Subagente del proyecto Micaserogou (micaserogou.com). Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue de Micaserogou. Corre en vps-preprod (Docker) y kalimete.
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco Micaserogou — Proyecto Micaserogou

## Visión

Gestión del proyecto **Micaserogou** (`micaserogou.com`).

## Infraestructura

- **Producción**: vps-preprod (154.53.35.102), contenedor `micaserogou-frontend-1`
- **Desarrollo**: kalimete, contenedor `micaserogou-frontend-1`
- **DNS**: micaserogou.com → 154.53.35.102 (proxied)
- **Zona Cloudflare**: id `fdebf4707c11ec49d9a73204457ba19c`

## Zona Cloudflare

- A root → 154.53.35.102 (proxied)
- erpipos.micaserogou.com → 147.93.6.112 (proxied)
- ⚠️ SPF duplicado (uno con mailchannels, otro simple) — no tocar sin confirmación

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NO TOCAR** el SPF duplicado sin confirmación
3. **Siempre** verificar estado del contenedor antes de asumir
4. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio