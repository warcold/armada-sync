# CHANGELOG — Dokploy Agent

## [2026-11-20] Creación del agente Dokploy + API key + Harness

- **Tipo**: feature
- **Qué**: Agente especializado `Dokploy` creado en `~/.config/opencode/agents/dokploy.md` con harness en `~/.victoria-custom/harness/dokploy.harness.json` y changelog propio.
- **Por qué**: Automatizar gestión de Dokploy (PaaS self-hosted) desde Victoria y subagentes.
- **Impacto**: Nuevo subagente disponible via `@Dokploy` o `Task` con `subagent_type: "Dokploy"`. API key funcional con permisos completos.
- **Verificado**:
  - Usuario `dokploy-agent-victoria` creado en BD (rol admin)
  - Organización `org-victoria` creada + miembro owner
  - API key `dokploy-agent-key-001` creada con hash SHA-256 base64url
  - Metadata incluye `organizationId: org-victoria`
  - Header `x-api-key` autentica correctamente contra tRPC
  - `project.all` retorna `[]` (sin proyectos aún)
- **Docs**: `dokploy.md` (agente), `dokploy.harness.json` (harness), este CHANGELOG

### Detalles técnicos

**Stack Dokploy actual (v0.31.4)**:
- Contenedor `dokploy` (dokploy/dokploy:latest) → puerto 3000 (interno, NO publicado en host)
- Contenedor `dokploy-postgres` (postgres:16-alpine) → puerto 5432
- Contenedor `dokploy-redis` (redis:7-alpine) → puerto 6379
- Contenedor `dokploy-traefik` (traefik:v3.1) → puertos 8081 (HTTP), 8444 (HTTPS)

**Autenticación**:
- Better-auth + plugin `@better-auth/api-key` v1.6.23
- Header requerido: `x-api-key` (NO Authorization)
- Hash: SHA-256 del plaintext → base64url (sin padding)
- Rate limit: 1000 req/min (configurado en BD)

**API tRPC**:
- Base: `http://localhost:3000/api/trpc` (acceso via `docker exec dokploy curl ...`)
- Formato: `/api/trpc/<router>.<procedure>?batch=1`
- Input: JSON en body POST (queries) / query param `input` (GET)
- Output: Array con `{result: {data: {json: ...}}}` o `{error: ...}`

**⚠️ BUG CRÍTICO (2026-11-20)**: `bodyParser: false` en config Next.js del tRPC handler (`createNextApiHandler` con `api: {bodyParser: false, sizeLimit: "1gb"}`) → el body JSON NO se parsea en **CUALQUIER procedure que requiera input** (POST body o GET query param `input`). Error: `400 "Invalid input: expected object, received undefined"`. 

**Estado real de procedures (2026-11-20)**:
- ✅ **FUNCIONAN** (sin input requerido): `project.all`, `server.all`, `postgres.all`, `deployment.all`, `backup.all`, `schedule.all`, `network.all`, `dockerVolume.all`, `mysql.all`, `mariadb.all`, `mongo.all`, `redis.all`, `libsql.all`
- ❌ **NO FUNCIONAN** (requieren input): TODOS los demás procedures (create/update/delete/one/search/byProjectId/etc.) → 400 "Invalid input: expected object, received undefined"

**Routers probados**:
- `project.all` ✅
- `server.all` ✅
- `postgres.all` ✅
- `deployment.all` ✅
- `backup.all` ✅
- `schedule.all` ✅
- `network.all` ✅
- `dockerVolume.all` ✅
- `mysql.all` ✅
- `mariadb.all` ✅
- `mongo.all` ✅
- `redis.all` ✅
- `libsql.all` ✅
- `project.one` ❌ (requiere input)
- `application.search` ❌ (requiere input)
- `application.one` ❌ (requiere input)
- `environment.byProjectId` ❌ (requiere input)
- `postgres.one` ❌ (requiere input)

**Workaround para mutaciones y queries con parámetros**: Usar UI web en `http://victoria.local:8081` (Traefik dashboard) para todas las operaciones de escritura y lectura con parámetros.

**Próximos pasos**:
1. Reportar bug upstream en Dokploy (bodyParser: false impide CUALQUIER procedure con input via API)
2. Configurar servidor (local o remoto) via UI web
3. Desplegar primera aplicación (ej. nginx, whoami) via UI web
4. Configurar dominio + certificado Let's Encrypt via Traefik
5. Documentar workflows comunes en el agente