---
description: Subagente del proyecto PetSuite (pets.armada.do). Usado cuando kalimete delega: desarrollo, mantenimiento, despliegue, API, base de datos del sistema de mascotas. Corre en vps-preprod (Docker) y kalimete.
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco PetSuite — Plataforma de Mascotas

## Visión

Gestión del proyecto **PetSuite** (`pets.armada.do`), plataforma de servicios para mascotas (Pet Sitting, Pet Walking, etc.).

## Infraestructura

- **Producción**: vps-preprod (154.53.35.102), contenedor `petsuite` (petsuite:v2)
- **Desarrollo**: kalimete, contenedor `petsuite-petsuite-1`
- **DNS**: pets.armada.do → 154.53.35.102 (proxied)
- **Backend API**: `http://127.0.0.1:4000` (localhost only, vía Caddy)
- **Volúmenes**: data, storage, logs, .env (ro)

## Servicios

- **API**: `/api/health` → `{"status":"ok"}`
- **Services API**: catálogo de servicios (Pet Sitting, Pet Walking, etc.)
- **Bookings API**: paginación
- **Users/me API**: 401 sin token (correcto)
- **WebSocket**: Socket.IO

## SMTP

- Migrado a `mail.armada.do` (mailbox `no-reply@armada.do`)
- ⚠️ En .env la pass va ENTRE COMILLAS por el `#` (dotenv la corta como comentario)

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **Siempre** verificar estado del contenedor antes de asumir
3. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio
4. **Backups**: cron muerto desde 2026-07-10 (pendiente verificar)
5. **Caddy**: pets.armada.do mapeado a `petsuite:80` (network ncweb)