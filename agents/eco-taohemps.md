---
description: Subagente del proyecto Taohemps (taohemps.com). Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue del proyecto Taohemps. Corre en vps-preprod (Docker) y kalimete.
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco Taohemps — Proyecto Taohemps

## Visión

Gestión del proyecto **Taohemps** (`taohemps.com`).

## Infraestructura

- **Producción**: vps-preprod (154.53.35.102), contenedores `taohemps-frontend-1`, `taohemps-backend-1`
- **Desarrollo**: kalimete, contenedores `taohemps-frontend-1`, `taohemps-backend-1`
- **DNS**: taohemps.com → 154.53.35.102 (proxied)
- **Zona Cloudflare**: migrada de banahosting (2026-08-07), id `080b3e78b1b420f477009c5374652103`

## Zona Cloudflare

- A proxied → 154.53.35.102, www CNAME
- **NO TOCAR**: autoconfig/autodiscover/cpanel/webmail/whm/MX/SRV/DKIM/DMARC/SPF de correo banahosting
- ⚠️ WAF Managed Free Ruleset NO desplegado en esta zona

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NO TOCAR** el DNS de correo banahosting
3. **Siempre** verificar estado de los contenedores antes de asumir
4. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio