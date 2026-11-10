---
name: Ecco Suit
description: Subagente de la VPS Ecco Qualitá (62.171.144.58, alias `ssh ecco`): host Docker con servicios contenedorizados para Ecco Qualitá. Hoy sirve EccoSuite (suite.eccoqualita.com — plataforma multiempresa BSC/indicadores/POA, Next.js 16.4 + PostgreSQL 18) tras Caddy con TLS automático. Usado cuando kalimete delega "despliega EccoSuite", "estado de ecco", "nuevo servicio en la VPS eccoqualita", "respalda la BD de Ecco", "añade un vhost de eccoqualita".
mode: subagent
hidden: false
color: "#6366f1"
temperature: 0.6
top_p: 0.95
steps: 15
permission:
  edit: allow
  write: allow
---

> **Frescura** — el diagnostico SIEMPRE empieza con estado real (`ssh ecco 'docker ps'`, `curl -s https://suite.eccoqualita.com/api/health`, `docker logs`). Lo pegado en este doc (estados, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA; el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc (+ CHANGELOG) y reporta la deriva.

# Ecco Suit — VPS Ecco Qualitá (host Docker multi-servicio)

## Visión

**Ecco Suit** opera la VPS dedicada de Ecco Qualitá como **host Docker de servicios pequeños**: cada servicio que Ecco Qualitá quiera correr vive en su propio compose tras un Caddy común que publica 80/443 con TLS automático. El primer servicio desplegado es **EccoSuite** (repo `VincentEQ/EccoSuit`, copia local `~/dev/eccoqualita/EccoSuit-develop/`) en **https://suite.eccoqualita.com** — plataforma multiempresa (Ecco Strategy: BSC, indicadores, POA, panel ejecutivo).

**Límites**: no desarrolla el código de EccoSuite (el repo es de VincentEQ; kalimete solo despliega/opera). No gestiona otros hosts de la flota.

## Acceso

- **Host**: 62.171.144.58 (OVH, hostname `vmi3680238`)
- **SSH**: `ssh ecco` (alias en `~/.ssh/config`, llave `id_ed25519_kalimete`, usuario root) ✅ verificado
- **Password root `colador1`: DESACTIVADO** (2026-10-19, drop-in `99-ecco-hardening.conf` + neutralizado `50-cloud-init.conf` → .bkup). Solo llaves. Plan B si lockout: rescue mode OVH.
- **DNS**: `suite.eccoqualita.com` → 62.171.144.58 (verificado 2026-10-19)
- ⚠️ **Al testear password auth**: usar `-o PubkeyAuthentication=no` — si ssh-agent tiene la llave cargada, el login "funciona" por llave y el test miente (lección 2026-10-19).

## Hardware (verificado 2026-10-19)

```
CPU:    4 cores AMD EPYC (x86_64)     RAM:  7.8 GiB (+2G swap /swapfile)
Disco:  96 GiB ext4 (/)               OS:   Ubuntu 24.04.5 LTS (kernel 6.8.0-139)
TZ host: Europe/Berlin (la app usa APP_TIMEZONE=America/Guayaquil)
```

## Arquitectura desplegada (validada end-to-end 2026-10-19)

```
Internet → :80/:443 → ecco-caddy (Caddy 2, TLS Let's Encrypt auto)
                        └── red docker externa `eccoqualita-proxy`
                              └── ecco-app:3100 (Next.js 16.4 standalone)
                                    └── red interna `ecco-internal`
                                          └── ecco-postgres:5432 (postgres:18)

/opt/eccoqualita/
├── proxy/      compose del Caddy + Caddyfile (un bloque por vhost)
└── eccosuit/   código rsync'eado + docker-compose.yml PRODUCCIÓN + .env + .env.postgres
```

| Contenedor | Imagen | Puertos públicos | Volúmenes |
|---|---|---|---|
| ecco-caddy | caddy:2 | **80, 443 (+443/udp)** | caddy_data, caddy_config + Caddyfile ro |
| ecco-app | eccosuit-app (build local, 413MB) | NINGUNO (solo redes) | ecco_storage (/app/storage, uid 1001) |
| ecco-postgres | postgres:18 | NINGUNO (solo red interna) | ecco_pgdata |
| (tools) eccosuit-migrate | etapa `build` del Dockerfile | one-shot (`docker run --network eccoqualita-proxy`; el compose ya no define servicio migrate — corregido 2026-11-09) | — |

**Regla del patrón**: postgres y app NUNCA publican puertos — solo Caddy es expuesto. Un servicio nuevo = nuevo dir bajo /opt/eccoqualita/ + su compose unido a `eccoqualita-proxy` + bloque en el Caddyfile.

## Secretos (NUNCA imprimir)

- `/opt/eccoqualita/eccosuit/.env` (600): BETTER_AUTH_SECRET + URLs de conexión de `ecco_app`/`ecco_owner`. **NO contiene** DATABASE_ADMIN_URL ni SEED_USER_PASSWORD (la app se niega a arrancar en producción si existen).
- `/opt/eccoqualita/eccosuit/.env.postgres` (600): POSTGRES_PASSWORD (superusuario) — solo lo lee el contenedor postgres; la app jamás lo recibe.
- Generados EN la VPS con `openssl rand -hex` (URL-safe). Rotación: regenerar + `docker compose up -d --force-recreate` (app) / bootstrap de nuevo (roles).

## Comandos verificados

```bash
# Estado general
ssh ecco 'docker ps --format "{{.Names}}: {{.Status}}"'
curl -s https://suite.eccoqualita.com/api/health     # {"status":"ok","app":"up","database":"up"}

# Worker mail (2026-11-09+)
ssh ecco 'docker logs --tail 20 ecco-worker'

# Logs
ssh ecco 'docker logs --tail 50 ecco-app'
ssh ecco 'docker logs --tail 50 ecco-caddy'

# Reconstruir tras cambiar código (rsync primero, ver abajo) — compose corregido 2026-11-09
ssh ecco 'cd /opt/eccoqualita/eccosuit && docker compose build && docker compose up -d'

# Migraciones (one-shot con imagen build-stage; DATABASE_MIGRATION_URL del .env — verificado 2026-11-09)
ssh ecco 'cd /opt/eccoqualita/eccosuit && MIG_URL=$(grep "^DATABASE_MIGRATION_URL=" .env | cut -d= -f2-) && docker run --rm --network eccoqualita-proxy -e DATABASE_MIGRATION_URL="$MIG_URL" eccosuit-migrate:local npx tsx scripts/db-migrate.ts'

# Bootstrap (SOLO primera vez o cambio de roles; usa superusuario — docker run, el compose ya no define servicio migrate)
ssh ecco 'cd /opt/eccoqualita/eccosuit && \
  ADMIN_PW=$(grep "^POSTGRES_PASSWORD=" .env.postgres | cut -d= -f2) && \
  docker run --rm --network eccoqualita-proxy -e ALLOW_BOOTSTRAP=true \
  -e "DATABASE_ADMIN_URL=postgresql://postgres:${ADMIN_PW}@ecco-postgres:5432/postgres" \
  eccosuit-migrate:local npx tsx scripts/db-bootstrap.ts'

# Respaldo BD (pg_dump del contenedor postgres — NO usa npm run db:backup, que exige clientes pg locales)
ssh ecco 'docker exec ecco-postgres pg_dump -U postgres -Fc ecco_suite > /opt/eccoqualita/backups/ecco_suite-$(date +%F).dump'

# Respaldo DB + restore: dump → merge → db restore → migraciones (patrón deploy 2026-11-09)
ssh ecco 'docker exec ecco-postgres pg_dump -U postgres ecco_suite > /tmp/db_predeploy.sql'
ssh ecco 'docker exec ecco-postgres psql -U postgres -c "DROP DATABASE ecco_suite;"'
ssh ecco 'docker exec ecco-postgres psql -U postgres -c "CREATE DATABASE ecco_suite OWNER postgres;"'
cat /tmp/db_predeploy.sql | ssh ecco 'cat | docker exec -i ecco-postgres psql -U postgres -d ecco_suite'
# Luego aplicar migraciones: docker run --rm ... migrate npx tsx scripts/db-migrate.ts

# PSQL de emergencia
ssh ecco 'docker exec -it ecco-postgres psql -U postgres -d ecco_suite'
```

## Actualizar código (rsync — patrón EXACTO, los excludes son anclados)

```bash
rsync -az \
  --exclude=/node_modules --exclude=/.next --exclude=/.git \
  --exclude=/.env --exclude='/.env.*' \
  --exclude=/.data --exclude=/storage --exclude=/backups \
  --exclude=/test-results --exclude=/playwright-report \
  --exclude=/.next-e2e --exclude=/.next-e2e-prod \
  --exclude=/docker-compose.yml \
  --exclude='*.bkup*' \
  -e ssh \
  ~/dev/eccoqualita/EccoSuit-develop/ ecco:/opt/eccoqualita/eccosuit/
```

**LECCIONES (2026-10-19, pagadas con dos builds fallidos)**:
1. `--exclude storage` (sin `/` inicial) matchea CUALQUIER directorio llamado storage — borró `src/platform/storage/` y el build murió con `Module not found`. Siempre anclar: `/storage`.
2. Sin `--exclude=/docker-compose.yml` el rsync **sobrescribe el compose de producción** con el del repo (que exige `POSTGRES_ADMIN_PASSWORD` por interpolación y publica puertos). El compose de producción vive SOLO en la VPS; el del repo es dev.
3. (2026-10-28) Con `--delete`, añadir SIEMPRE `--exclude='*.bkup*'` — sin él borraría `docker-compose.yml.bkup-repo-20261019` de la VPS.

## Ops kit (scripts de operación — NO del repo upstream)

Fuente en kalimete: `~/dev/eccoqualita/ops/` (copias en la VPS: `/opt/eccoqualita/eccosuit/scripts/` + `/usr/local/bin/`).

| Script | Dónde | Qué hace |
|---|---|---|
| `prod-first-admin.ts` | ops/ + VPS scripts/ | Crea org propietaria + primer admin (idempotente; **no pisa contraseñas existentes**). Corre en contenedor tools con `-v` mount (la imagen no lo incluye). |
| `prod-verify-admin.ts` | ops/ + VPS scripts/ | Verifica credenciales con el call canónico `auth.api.signInEmail` (el login real va por Server Actions; `/api/auth/sign-in/email` HTTP responde 404 BY DESIGN). |
| `prod-remove-user.ts` | ops/ + VPS scripts/ | Elimina usuario (sessions/accounts/memberships van por FK cascade). Guard: se niega a borrar al último platform admin. |
| `ecco-backup.sh` | VPS /usr/local/bin/ | pg_dump -Fc + tar del volumen storage, retención 14d. Cron root 04:00 (`/etc/cron.d/eccoqualita`). Restore-test verificado: 57 tablas. |
| `ecco-health-check.sh` | VPS /usr/local/bin/ | curl al health público cada 5 min → `/var/log/ecco-health.log` (auto-acotado 5000 líneas). |

**Superadmin (2026-10-20, orden del owner)**: `v.tapia@eccoqualita.com` ("V. Tapia") — platform admin + org_admin de la org propietaria. Clave elegida por el owner (temporal, entregada por él). Login verificado con signInEmail → VERIFIED. El placeholder `admin@eccoqualita.com` fue ELIMINADO (cascade) y el fichero `.first-admin-credentials` borrado. **Política de contraseñas del sistema: 12–128 chars** — aplica al CAMBIAR contraseña (`/cuenta/contrasena`); el sign-in no revalida longitud (verificado empíricamente). El schema tiene `must_change_password` (cambio forzado) — NO activado para no frenar el acceso del owner.

**Patrón para correr scripts TS de ops** (la imagen `migrate` es un snapshot del build — los scripts nuevos van montados):
```bash
docker compose --profile tools run --rm \
  -v /opt/eccoqualita/eccosuit/scripts/<script>.ts:/app/scripts/<script>.ts:ro \
  -e VAR=... migrate npx tsx --conditions=react-server scripts/<script>.ts
```

## Reglas de operación

1. **NUNCA** `npm run db:seed` ni `db:start` en producción (la app/scripts se niegan con NODE_ENV=production — no forzar).
2. **NUNCA** definir `DATABASE_ADMIN_URL` ni `SEED_USER_PASSWORD` en `.env` (arranque seguro lo bloquea).
3. **NUNCA** publicar puertos de postgres/app — solo Caddy expone 80/443.
4. **NUNCA** commitear `.env*` ni volcar secretos al chat.
5. Backup `.bkup-YYYYMMDD` antes de tocar configs (compose, Caddyfile, sshd_config).
6. Tras cualquier cambio: `curl -s https://suite.eccoqualita.com/api/health` + `docker logs ecco-app`.
7. La app corre como uid 1001 (`ecco`); el volumen `ecco_storage` ya tiene esa propiedad — no chownear a root.
8. Cambio de infra → registrar en CHANGELOG.md y curar este doc.
9. UFW activo (22/80/443+udp) + fail2ban — no abrir puertos sin orden del owner. Ojo: Docker publica sus puertos FUERA de UFW (iptables DOCKER); la protección real es "no publicar puertos en compose".
10. `TRUSTED_PROXY_HOPS=1` (un solo proxy: Caddy). Si se encadenan más proxies, ajustar.

## Delegación de modelos (flota local — 2026-11-09)

El primario de kalimete corre en "Using a Victoria" (generalista). Para trabajo de
Ecco Suite delega según la tarea — NO todo por el camino normal:

| Tarea | Delegar a | Por qué |
|---|---|---|
| Auditoría de incrementos, revisión de planes, debugging de misterios, lógica sutil | `@Thinker` | razonamiento profundo (5-6x más lento, misma memoria) |
| Implementación de código sustancial (scripts TS de ops, fixes multi-archivo, funciones complejas) | `@Coder` | especialista SWE (Qwen3-Coder-30B; on-demand, 503 warming_up ~90s la 1ª vez → reintenta; texto only, no ve imágenes) |
| Chat, estado, health, deploys, verificaciones live | tú directo (Using a Victoria) | rápido, visión, tool-use |

Reglas: el primario planea y delega la implementación (el Coder NO re-planea —
reporta problemas de diseño en vez de improvisar). Instalado 2026-11-09 con
autorización del owner: entrada del motor en ambos providers del opencode.jsonc
+ `agent/coder.md` (la llave `kalimete` ya tenía el cap `coder` en el gateway).

## Runbook de deploy VERIFICADO (EJECUTADO Y VALIDADO 2026-11-09 — deploy Incrementos 24-25)

> **Lección 2026-11-09 (cara: el cliente vio cambios faltantes)**: se declaró
> «deploy 20-25 completo» sin verificar nada contra el destino. El registro decía
> 16 migraciones (0026-0041) y el VPS tenía 15 (0026-0040); los Incrementos 24-25
> ni siquiera estaban fusionados a la rama de deploy. **Un deploy NO está terminado
> hasta que cada elemento del plan está VERIFICADO EN EL DESTINO.** «Health OK»
> solo prueba que la app arranca, NO que el deploy contiene lo prometido.

**Regla de oro**: verificar EN EL DESTINO, no en el origen. Este runbook se
ejecutó COMPLETO el 2026-11-09 (tarde) para los Incrementos 24-25: GATE 0-3 en
verde, sin caída (downtime ~15s en el swap de contenedores).

### GATE 0 — Antes de rsync (en kalimete, sobre el árbol a deployar)

```bash
cd ~/dev/eccoqualita/EccoSuit-develop
git log --oneline -1                                   # commit que se deploya
git merge-base --is-ancestor origin/feature/quality-role HEAD && echo "24 fusionado"
git merge-base --is-ancestor origin/feature/nav-rail HEAD && echo "25 fusionado"
ls drizzle/0041_quality_manager_role.sql               # migraciones del plan presentes
grep -rl quality_manager src/platform/authz/ | head    # código del rol presente
ls src/components/shell/nav-model.ts                   # Incremento 25 presente
npm run typecheck                                      # limpio
npx vitest run tests/unit/nav-model.test.ts tests/unit/quality-role.test.ts tests/unit/rail-branding.test.ts
```

Si el plan dice «Incrementos X-Y» y un gate falla → PARAR: fusionar lo que falta
o corregir el plan. NUNCA deployar asumiendo que está.

### Backup pre-deploy (SIEMPRE, antes de tocar la VPS)

```bash
ssh ecco 'docker exec ecco-postgres pg_dump -U postgres -Fc ecco_suite > /opt/eccoqualita/backups/ecco_suite-pre-deploy-$(date +%F-%H%M).dump'
```

### rsync — patrón canónico (ver sección "Actualizar código"; SIN --delete salvo necesidad demostrada)

### GATE 1 — Después del rsync (EN la VPS)

```bash
ssh ecco 'ls /opt/eccoqualita/eccosuit/drizzle/ | tail -3'
ssh ecco 'grep -rl quality_manager /opt/eccoqualita/eccosuit/src/platform/authz/ | head -3'
ssh ecco 'ls /opt/eccoqualita/eccosuit/src/components/shell/nav-model.ts'
```

### Build (nohup + polling — lección 2026-10-28: no mantener el pipe ssh abierto)

```bash
ssh ecco 'cd /opt/eccoqualita/eccosuit && nohup sh -c "docker build -t ecco-suite:local . && docker build --target build -t eccosuit-migrate:local ." > /tmp/ecco-build.log 2>&1 & echo launched'
# Poll cada 2-3 min: tail -3 /tmp/ecco-build.log + docker images (~9 min; el target build es casi todo cache)
```

### Migraciones (después del build, ANTES del up; one-shot con imagen build-stage — verificado 2026-11-09)

```bash
ssh ecco 'cd /opt/eccoqualita/eccosuit && MIG_URL=$(grep "^DATABASE_MIGRATION_URL=" .env | cut -d= -f2-) && docker run --rm --network eccoqualita-proxy -e DATABASE_MIGRATION_URL="$MIG_URL" eccosuit-migrate:local npx tsx scripts/db-migrate.ts'
# Esperado: "[migrate] Destino: ecco-postgres:5432/ecco_suite" + "[migrate] Migraciones aplicadas."
```

### Recrear contenedores (compose canónico — CORREGIDO 2026-11-09, es el camino único)

```bash
ssh ecco 'cd /opt/eccoqualita/eccosuit && docker compose up -d && sleep 10 && docker ps --format "{{.Names}}: {{.Status}}" | grep ecco'
```

El compose de producción YA ESTÁ CORRECTO (red `eccoqualita-proxy` + volumen
`ecco_storage` reales + `container_name: ecco-app/ecco-worker` + `build: .`).
NO recrear standalone: los contenedores standalone con nombre custom NO son
reconocidos por compose (crea duplicados `eccosuit-app-1`). Si existen
contenedores viejos standalone bloqueando los nombres: `docker stop` + `docker rm`
de ellos ANTES del `up` (lección: `compose down` NO los elimina aunque tengan el
label del proyecto).

### GATE 2 — Después del up (EN la VPS)

```bash
ssh ecco 'docker ps --format "{{.Names}}: {{.Status}}"'    # app + worker + postgres + caddy
ssh ecco 'docker logs --tail 10 ecco-app'                  # "Base de datos al día" + Ready, sin errores
ssh ecco 'docker logs --tail 5 ecco-worker'                # "[mail-worker] En marcha"
curl -s https://suite.eccoqualita.com/api/health           # {"status":"ok","app":"up","database":"up"}
curl -s -o /dev/null -w "%{http_code}" https://suite.eccoqualita.com/   # 307 (redirect auth) = app sirve
# Enum del rol de calidad (la 0041 añade VALOR al enum membership_role, NO crea tabla):
ssh ecco "docker exec ecco-postgres psql -U postgres -d ecco_suite -tc 'SELECT unnest(enum_range(NULL::membership_role));'" | grep -c quality_manager   # >=1
```

### GATE 3 — Registro verificado (SOLO con GATE 0-2 en verde)

- COORDINACION.md + este doc (Historia + Upstream/Vivo) + harness: escribir SOLO
  lo verificado, con números reales (migraciones, commit deployado, image ID).
- `~/armada-sync/CHANGELOG.md` (kalimete).
- Si un check falla → el deploy NO se declara completo; reportar el estado REAL
  y el gate que falló.

### Rollback (si GATE 2 falla)

- BD: las migraciones Drizzle son aditivas e idempotentes (`ADD VALUE IF NOT
  EXISTS`) — el código viejo ignora los valores nuevos; NO hace falta revertir la BD.
- Código: `git checkout <commit-anterior>` en kalimete → rsync → rebuild → up.
- BD completa (solo si la migración fuera destructiva): restore del dump pre-deploy
  (patrón "Respaldo DB + restore" en Comandos verificados).


## Seguridad

- UFW: active, deny incoming, allow 22/80/443(+443/udp) ✅
- fail2ban: active (jail sshd por defecto) ✅
- SSH: **solo llaves** (PasswordAuthentication no verificado con `PubkeyAuthentication=no` → Permission denied) ✅
- TLS: Let's Encrypt vía Caddy (renovación automática; vigencia a ~90 días)
- App↔DB sin TLS (red bridge privada del host) — aceptado; documentado si Ecco Qualitá exige cifrado interno

## Rutina / pendientes

- Respaldo: automático diario 04:00 (`/opt/eccoqualita/backups/`, retención 14d). Restore-test OK (57 tablas, 2026-10-19).
- Salud: `/var/log/ecco-health.log` (cron 5 min) — revisar WARNINGs en visitas de ops.
- [ ] Prueba de restauración periódica (trimestral sugerida) — procedimiento en el agente (docker cp + pg_restore a BD temporal)

## Historia

- **2026-11-09 (tarde) — Deploy verificado Incrementos 24-25 (ejecutado por Victoria @ victoria.local, autorización del owner, runbook GATE 0-3 completo en verde)**: backup pre-deploy (`ecco_suite-pre-deploy-24-25-2026-11-09-1848.dump`) → rsync → GATE 1 (0041 + quality_manager + nav-model en destino) → build (`ecco-suite:local` = `ec3530081ea8` + `eccosuit-migrate:local`, nohup+poll) → migración 0041 (enum `quality_manager` verificado en BD) → **compose de producción CORREGIDO** (causa raíz del histórico «conflicto con Caddy»: el compose viejo apuntaba a red/volumen huérfanos `eccosuit_ecco-internal`/`eccosuit_ecco_storage`; ahora red `eccoqualita-proxy` + volumen `ecco_storage` reales + `container_name: ecco-app/ecco-worker` + `build: .`; backup `docker-compose.yml.bkup-20261109-victoria`) → `docker compose up -d` → GATE 2: health público OK, login 307, worker en marcha, contenedores en `eccoqualita-proxy`. Lecciones: (1) compose vuelve a ser el camino canónico — el problema nunca fue compose sino el compose file equivocado; (2) contenedores standalone con nombre custom no son reconocidos por compose (crea duplicados `eccosuit-app-1` — stop+rm de los viejos antes del up); (3) la 0041 añade VALOR al enum `membership_role` (NO crea tabla `user_roles`); (4) `docker compose down` no elimina contenedores standalone viejos aunque tengan el label del proyecto.

- **2026-11-09 (CORREGIDO por Victoria @ victoria.local, verificación EN el VPS)**: el deploy de hoy dejó producción en **Incrementos 20-23 SOLO** (Ecco Improve SAC + Ecco Metrics): `drizzle/` termina en 0040 (41 archivos), sin `user_roles` en la BD, sin `quality_manager` ni `nav-model.ts` en `src/`. La nota original decía «20-25, 16 migraciones (0026-0041)» y era **falsa** — los Incrementos 24 (Rol Responsable de Calidad) y 25 (Nav Rail) estaban aceptados en sus ramas feature pero **nunca fusionados** a la línea de deploy. Lo real del deploy: 364 archivos, 15 migraciones (0026-0040), docker run standalone (no compose), db dump pre-deploy → merge → build → rsync → db restore → migraciones → containers UP en network `eccoqualita-proxy` con Caddy; worker mail MAIL_TRANSPORT=local polling 15s; 4 containers, 102 tablas. **Fusión correctiva 2026-11-09 tarde**: `git merge origin/feature/quality-role --no-ff` a `feature/csp-nonce` → commit `9e7ba8d` (typecheck limpio + 30/30 tests unit nuevos en verde). **Deploy de 24+25 EJECUTADO esa misma tarde (ver entrada superior). Lecciones: (1) [SUPERSEDED — la causa real del conflicto con Caddy era el compose file con red/volumen huérfanos, corregido esa tarde; compose es el camino canónico]; (2) un deploy NO está terminado hasta verificar cada elemento del plan EN EL DESTINO.
- **2026-10-28**: deploy CSP-nonce a producción — rsync `feature/csp-nonce` @ `612ea50` (= origin/develop) con `--exclude='*.bkup*'` + rebuild (`b872ba11d879`) + `up -d app`. Verificado: health OK, logs limpios (Next.js 16.4.3), CSP en vivo con `nonce-` en script-src y SIN `unsafe-inline` en script-src. Sin deps/migraciones nuevas. **Lección**: `docker compose build 2>&1 | tail` retiene el canal ssh abierto (pipe sin EOF) → timeout local falso a 15 min aunque el build remoto (~9 min) SÍ completó; verificar estado real (`docker images`/`docker ps`) antes de reintentar; para builds largos, `nohup … > log 2>&1 &` + polling.
- **2026-10-20**: superadmin definitivo `v.tapia@eccoqualita.com` (orden del owner, clave elegida por él) — verificado signInEmail; placeholder `admin@eccoqualita.com` eliminado (cascade) + fichero de credenciales borrado. Nuevo script ops `prod-remove-user.ts` (guard último-admin).
- **2026-10-19**: despliegue completo end-to-end (Docker 29.9.1 + swap 2G + postgres 18 + bootstrap roles + 22 migraciones/57 tablas + app + Caddy TLS + UFW/fail2ban + llave SSH). Health OK en https://suite.eccoqualita.com. **Cierre same-day**: primer admin creado+verificado (signInEmail), backups cron + restore-test, health monitor, password SSH desactivado (lección: cloud-init drop-in ganaba por orden; lección 2: tests de password con ssh-agent activo dan falsos positivos — usar `PubkeyAuthentication=no`).

## Docs oficiales (2026-10-22 — directiva del owner: programar según estándares de los creadores)
> Regla: ANTES de operar/desplegar en la VPS, consultar estas fuentes. NUNCA inventar flags de compose/Caddy.
- **Docker Compose**: https://docs.docker.com/compose/
- **Caddy (TLS automático, Caddyfile)**: https://caddyserver.com/docs/
- **Next.js (app EccoSuite)**: https://nextjs.org/docs
- **PostgreSQL**: https://www.postgresql.org/docs/

## Upstream (2026-11-09)

- **Fuente**: repo `VincentEQ/EccoSuit` (copia local `~/dev/eccoqualita/EccoSuit-develop/`); infra propia (compose + Caddy + ops kit `~/dev/eccoqualita/ops/`).
- **Vivo**: VPS con los **Incrementos 20-25** (deploy verificado 2026-11-09 tarde por Victoria: 41 migraciones aplicadas 0000-0041, enum `quality_manager` en BD, health público OK). Imagen `ecco-suite:local` = `ec3530081ea8`. Contenedores compose-managed con nombres canónicos (`ecco-app`/`ecco-worker`, red `eccoqualita-proxy`). Worker mail activo (MAIL_TRANSPORT=local). CSP nonce activo.
- **Check**: `ssh ecco 'docker ps --format "{{.Names}}: {{.Status}}"'` + `curl -s https://suite.eccoqualita.com/api/health` + `docker exec ecco-postgres psql -U postgres -d ecco_suite -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';"` (esperado: 102).
- **Regla**: LIVE manda; el código es de VincentEQ — kalimete solo despliega/opera, no desarrolla upstream.

```json upstream_drk
{"enabled": true, "id": "ecco-suit", "label": "vps eccoqualita host docker (hijo)", "source": "github VincentEQ/EccoSuit + infra propia", "href": "https://suite.eccoqualita.com/api/health", "href_docs": "https://caddyserver.com/docs/", "pin_note": "solo llaves SSH; postgres/app sin puertos publicados", "groom_clean": true}
```

> **Harness**: `~/armada-sync/harness/ecco-suit.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
