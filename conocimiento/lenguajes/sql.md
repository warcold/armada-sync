# SQL (MySQL/MariaDB/PostgreSQL) — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: contenedores kalimete + victoria sqlite)
> **Docs oficiales**: https://dev.mysql.com/doc/ · https://mariadb.com/kb/en/documentation/ · https://www.postgresql.org/docs/

## Motores en uso

| Motor | Dónde | Versión | Uso |
|---|---|---|---|
| MariaDB 10.11 | kalimete (wordpress-db, zionv-db, magantech-db, micaserogou-db) | 10.11 | WordPress labs + websites clientes |
| MySQL 8.0 | kalimete (erpipo-preprod-db) | 8.0 | ERP preprod (Laravel-style: queue/scheduler/redis) |
| PostgreSQL 17 | kalimete (ror-postgres) | pg17 + **pgvector** | Record of Ragnarok (juego) |
| PostgreSQL | ecco VPS (ecco-postgres) | — | EccoQualita producción |
| SQLite | victoria (gateway, blogwatcher, métricas) | 3.45.1 | ver lenguajes/sqlite.md |

## Patrones que usamos

- **Backups**: `mysqldump`/`pg_dump` antes de migraciones; db-backups/ en erpipo-preprod
- **Acceso loopback-only**: las DBs de kalimete bindean 127.0.0.1:33XX (salvo erpipo 3310 que publica 0.0.0.0 — revisar)
- **pgvector** para embeddings (ror-postgres)

## Gotchas descubiertos (lecciones)

- **Puerto 3310 ocupado por otro proceso** (convención websites 809X/330X ascendente — próximo 8095/3312). — (MAPA kalimete)
- **wordpress-db publica 0.0.0.0:3307** (única expuesta — el resto loopback): riesgo LAN, pendiente cerrar si el owner quiere.
- **App Passwords ≠ password de login** en WordPress REST (autenticación por Application Passwords). — (MAPA kalimete)

## Regla de actualización

Motores en contenedores: upgrade con imagen nueva + dump/restore + E2E del
proyecto. NUNKA upgrade in-place sin backup. Cambios de esquema: migración
versionada en el repo del proyecto.
