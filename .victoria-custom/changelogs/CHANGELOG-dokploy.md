# CHANGELOG — Dokploy

## [2026-11-20] Creación subagente Dokploy + Harness + Arquitectura 7 proyectos

### Added
- Subagente `Dokploy` en `~/.config/opencode/agents/dokploy.md`
- Harness `dokploy.harness.json` en `~/.victoria-custom/harness/`
- Changelog dedicado `CHANGELOG-dokploy.md`
- Documentación completa: API endpoints, bug bodyParser, workflow obligatorio
- Arquitectura 7 proyectos Dokploy: shared, llm, gateway, openclaw, art, sentidos, infra
- 36 contenedores definidos con healthchecks, volúmenes, redes, GPU arbiter
- Traefik dynamic configs (tls, middlewares, routes) para *.victoria.local
- Variables de entorno (.env.dokploy) ~50 variables
- Scripts de validación API read-only
- Migración en 8 fases documentada

### Bug Conocido (Crítico)
- **Dokploy v0.31.4**: `bodyParser: false` en handler tRPC/Next.js
- **TODAS las mutaciones fallan**: `project.create`, `application.create`, `postgres.create`, etc.
- **Error**: `400 "Invalid input: expected object, received undefined"`
- **Workaround**: UI Web en `http://victoria.local:8081` para escrituras
- **Queries read-only funcionan perfectamente**

### Estado Actual
- Dokploy instalado (container `dokploy` + `dokploy-postgres` + `dokploy-redis` + `dokploy-traefik`)
- API key creada: `dkp_victoria_732596f16c2bfcde0f1452e2c0061ff5` (admin, org `org-victoria`)
- Traefik viejo en puerto 8081 (dashboard inseguro HTTP)
- **Migración 0%** - Solo plan, ninguna creación en Dokploy aún

### Próximos Pasos
1. Fase 0: Red + 14 volúmenes bind-mount + mkcert + backup
2. Traefik dynamic configs (archivos host)
3. `victoria-shared` en UI → validar API
4. `victoria-infra` (Traefik nuevo, GPU-Saver, Cloudflared, Armada-Sync)
5. `victoria-llm` (vLLM Main + Coder)
6. `victoria-gateway` (API, Admin, Metering)
7. `victoria-openclaw` (13 contenedores)
8. `victoria-art` (7 contenedores)
9. `victoria-sentidos` (5 contenedores)
10. Cutover DNS + 24h validación + apagado legacy