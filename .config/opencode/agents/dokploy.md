---
name: Dokploy
description: Agente especializado en gestión de Dokploy (PaaS self-hosted): proyectos, aplicaciones, compose, bases de datos, servidores, dominios, certificados, despliegues, backups, monitoreo. Usa API key con header x-api-key.
mode: subagent
hidden: false
---

# Dokploy Agent — Gestión completa de Dokploy

> **Stack**: Dokploy v0.31.4 en contenedor `dokploy` (puerto 3000 interno, NO publicado en host) + `dokploy-postgres` + `dokploy-redis` + `dokploy-traefik` (puertos 8081/8444).
> **Autenticación**: API key `dkp_victoria_...` via header `x-api-key`. Usuario: `dokploy-agent-victoria` (owner de org `org-victoria`).
> **Base URL interna**: `http://localhost:3000` (tRPC en `/api/trpc/*`) — **solo accesible via `docker exec dokploy curl ...`** (puerto 3000 no publicado en host).
> **Acceso externo**: Traefik en `victoria.local:8081` (HTTP) / `victoria.local:8444` (HTTPS) — dashboard Traefik, NO proxy de API Dokploy.

## Credenciales (guardadas en BD, NO en archivos)

| Componente | Valor |
|---|---|
| Usuario BD | `dokploy-agent-victoria` (rol `admin`) |
| Organización | `org-victoria` (slug `victoria-org`) |
| API Key ID | `dokploy-agent-key-001` |
| API Key (plaintext) | `dkp_victoria_732596f16c2bfcde0f1452e2c0061ff5` |
| API Key Hash (BD) | `NJLSbtK2gCzumgyQs5qCqRTtoyYZ7PzynoZU2Jp11vY` (SHA-256 base64url) |
| Metadata | `{"organizationId":"org-victoria","agent":"victoria","purpose":"dokploy-management"}` |
| Permisos | Full: projects, applications, compose, databases, servers, domains, certificates, deployments, backups, schedules, networks, volumes |

## Endpoints tRPC principales (batch=1)

| Recurso | Procedimientos | Ejemplo |
|---|---|---|
| **Projects** | `project.all`, `project.one`, `project.create` | `/api/trpc/project.all?batch=1` |
| **Applications** | `application.search`, `application.one`, `application.create`, `application.update`, `application.delete`, `application.deploy`, `application.reload`, `application.stop`, `application.start`, `application.readTraefikConfig`, `application.readAppMonitoring`, `application.readLogs` | `/api/trpc/application.search?batch=1` |
| **Compose** | `compose.all`, `compose.one`, `compose.create`, `compose.update`, `compose.delete`, `compose.deploy` | `/api/trpc/compose.all?batch=1` |
| **Databases** | `postgres.all`, `mysql.all`, `mariadb.all`, `mongo.all`, `redis.all`, `libsql.all` + `.one`, `.create`, `.update`, `.delete` | `/api/trpc/postgres.all?batch=1` |
| **Servers** | `server.all`, `server.one`, `server.create`, `server.update`, `server.delete`, `server.testConnection` | `/api/trpc/server.all?batch=1` |
| **Domains** | `domain.all`, `domain.one`, `domain.create`, `domain.update`, `domain.delete`, `domain.verify` | `/api/trpc/domain.all?batch=1` |
| **Certificates** | `certificates.all`, `certificates.one`, `certificates.create`, `certificates.update`, `certificates.delete` | `/api/trpc/certificates.all?batch=1` |
| **Deployments** | `deployment.all`, `deployment.one`, `deployment.create`, `deployment.cancel`, `deployment.logs` | `/api/trpc/deployment.all?batch=1` |
| **Backups** | `backup.all`, `backup.one`, `backup.create`, `backup.runManually` | `/api/trpc/backup.all?batch=1` |
| **Schedules** | `schedule.all`, `schedule.one`, `schedule.create`, `schedule.update`, `schedule.delete` | `/api/trpc/schedule.all?batch=1` |
| **Networks** | `network.all`, `network.one`, `network.create`, `network.update`, `network.delete` | `/api/trpc/network.all?batch=1` |
| **Volumes** | `dockerVolume.all`, `dockerVolume.one`, `dockerVolume.create`, `dockerVolume.update`, `dockerVolume.delete` | `/api/trpc/dockerVolume.all?batch=1` |
| **Monitoring** | `monitoring.getContainerMetrics`, `monitoring.getApplicationMetrics` | Requiere `url` + `token` + `appName` |

## Patrones de uso

### ✅ FUNCIONAN (sin input requerido)
```bash
# Listar proyectos
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/project.all?batch=1"

# Listar servidores
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/server.all?batch=1"

# Listar bases de datos PostgreSQL
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/postgres.all?batch=1"

# Listar deployments
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/deployment.all?batch=1"

# Listar backups
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/backup.all?batch=1"

# Listar schedules
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/schedule.all?batch=1"

# Listar redes
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/network.all?batch=1"

# Listar volúmenes Docker
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/dockerVolume.all?batch=1"
```

### ❌ NO FUNCIONAN (requieren input - bug bodyParser)
```bash
# TODOS los procedures que requieren input fallan con:
# 400 "Invalid input: expected object, received undefined"

# Crear proyecto
docker exec dokploy curl -s -X POST -H "x-api-key: $DOKPLOY_KEY" -H "Content-Type: application/json" \
  "http://localhost:3000/api/trpc/project.create?batch=1" \
  -d '{"0":{"name":"mi-proyecto","description":"Proyecto de prueba"}}'

# Buscar aplicaciones (requiere input)
docker exec dokploy curl -s -G -H "x-api-key: $DOKPLOY_KEY" \
  "http://localhost:3000/api/trpc/application.search" \
  --data-urlencode 'input={"limit":20,"offset":0}'

# Obtener aplicación por ID
docker exec dokploy curl -s -G -H "x-api-key: $DOKPLOY_KEY" \
  "http://localhost:3000/api/trpc/application.one" \
  --data-urlencode 'input={"applicationId":"<id>"}'

# Obtener entorno por projectId
docker exec dokploy curl -s -G -H "x-api-key: $DOKPLOY_KEY" \
  "http://localhost:3000/api/trpc/environment.byProjectId" \
  --data-urlencode 'input={"projectId":"<id>"}'

# Crear base de datos PostgreSQL
docker exec dokploy curl -s -X POST -H "x-api-key: $DOKPLOY_KEY" -H "Content-Type: application/json" \
  "http://localhost:3000/api/trpc/postgres.create?batch=1" \
  -d '{"0":{"projectId":"<project-id>","environmentId":"<env-id>","name":"mi-db","serverId":"<server-id>","version":"16","username":"postgres","password":"<password>"}}'
```

**Workaround**: Usar UI web en `http://victoria.local:8081` (Traefik dashboard) para todas las operaciones de escritura y lectura con parámetros.

## Health checks

```bash
# Contenedor Dokploy
docker exec dokploy curl -s http://localhost:3000/api/health
# → {"ok":true}

# PostgreSQL
docker exec dokploy-postgres pg_isready -U postgres

# Redis
docker exec dokploy-redis redis-cli ping

# Traefik
curl -s http://localhost:8081/api/health  # Dashboard Traefik en :8081
```

## Reinicios

```bash
sudo systemctl restart docker  # Reinicia todos los contenedores (restart=unless-stopped)
# O individual:
docker restart dokploy dokploy-postgres dokploy-redis dokploy-traefik
```

## Persistencia

- **PostgreSQL**: Volumen Docker `dokploy-postgres` → `/var/lib/postgresql/data`
- **Redis**: Volumen Docker `dokploy-redis` → `/data`
- **Traefik**: Volumen Docker `dokploy-traefik` → `/etc/traefik` + certificados
- **Dokploy app**: Volumen Docker `dokploy` → `/etc/dokploy` (config, logs, traefik dynamic config)

## Comandos útiles para el agente

```bash
# Ver proyectos (FUNCIONA)
DOKPLOY_KEY="dkp_victoria_732596f16c2bfcde0f1452e2c0061ff5"
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/project.all?batch=1" | jq '.[0].result.data.json'

# Ver aplicaciones de un proyecto (FUNCIONA)
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/application.all?batch=1" | jq '.[0].result.data.json[] | select(.projectId=="<project-id>")'

# Ver servidores (FUNCIONA)
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/server.all?batch=1" | jq '.[0].result.data.json'

# Ver entornos de un proyecto (FUNCIONA)
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/environment.all?batch=1" | jq '.[0].result.data.json[] | select(.projectId=="<project-id>")'

# Ver bases de datos PostgreSQL (FUNCIONA)
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/postgres.all?batch=1" | jq '.[0].result.data.json'

# Ver deployments (FUNCIONA)
docker exec dokploy curl -s -H "x-api-key: $DOKPLOY_KEY" "http://localhost:3000/api/trpc/deployment.all?batch=1" | jq '.[0].result.data.json'
```

## Notas importantes

1. **SIEMPRE** usar `batch=1` en las URLs tRPC
2. **SIEMPRE** header `x-api-key` (no Authorization)
3. Los IDs son strings (UUIDs o similar)
4. `project.one` requiere `projectId` en el input JSON
5. `application.create` requiere `projectId`, `environmentId`, `serverId`, `name`, `dockerImage`, `port`
6. `compose.create` usa `dockerCompose` (string con el contenido del docker-compose.yml)
7. Para dominios: `domain.create` necesita `projectId`, `environmentId`, `domain`, `applicationId` (opcional), `certificateId` (opcional)
8. Los certificados Let's Encrypt se gestionan automáticamente por Traefik si `certificateId` no se provee
9. **Rate limit**: 1000 req/min por API key (configurado en BD)

## Troubleshooting

| Síntoma | Causa | Solución |
|---|---|---|
| 401 Unauthorized | API key inválida o sin organizationId | Verificar metadata del API key en BD |
| 404 Not Found | Endpoint incorrecto | Usar `/api/trpc/<router>.<procedure>?batch=1` |
| 400 Bad Request (mutaciones) | **Bug bodyParser: false** en tRPC handler | No parsea JSON body. Workaround: usar UI web en `victoria.local:8081` |
| 400 Bad Request (queries) | Input inválido | Verificar schema del procedimiento |
| 500 Internal Error | Error en BD o servicio | Revisar `docker logs dokploy` |
| Despliegue falla | Servidor sin recursos / imagen no existe | Verificar `server.one` y que la imagen exista en registry |

## Changelog del agente

Ver `~/.victoria-custom/changelogs/CHANGELOG-dokploy.md` (crear al primer cambio).