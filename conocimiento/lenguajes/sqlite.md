# SQLite — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `sqlite3 --version` → 3.45.1)
> **Docs oficiales**: https://www.sqlite.org/lang.html + `sqlite3 .help`

## Versiones en uso

- 3.45.1 (sistema) — gateway DB, blogwatcher DB (dentro del sandbox, pure-Go modernc.org/sqlite), métricas WAL del gpu-saver, state JSONs donde aplica

## DBs del ecosistema

| DB | Quién escribe | Acceso |
|---|---|---|
| `~/.victoria-llm/llm-gateway.db` | gateway (vivo) | lectura via sqlite3ro para warcold (bloquea key_plaintext/key_hash y SELECT *) |
| `~/logs/victoria-metrics.db` (WAL) | gpu-saver | caja negra que sobrevive freezes |
| `blogwatcher.db` (sandbox) | blogwatcher Go | respaldada por persist.sh |

## Patrones que usamos

- **WAL mode** en DBs escritas por daemons (metrics) — sobrevive freezes
- **Columnas explícitas SIEMPRE, NUNKA `SELECT *`** en la DB de llaves (key_plaintext/key_hash)
- Backups: `openclaw-persist.sh` (blogwatcher), snapshots armada-sync excluyen DBs vivas

## Gotchas descubiertos (lecciones)

- **Comparar TEXT contra epoch rompe ventanas de tiempo** — usar `datetime('now',?)` (el bug del loop-alert que spameaba horario). — (CHANGELOG 2026-09-17)
- **Esquema de api_keys**: columnas reales son `expires_at` (no `expires`), `budget`, `allowed_models` — verificar con `PRAGMA table_info` antes de query. — (lección 2026-10-27)
- **modernc.org/sqlite (Go puro, sin CGO)**: el blogwatcher lo usa — el binario es estático y no necesita libsqlite del sistema. — (CHANGELOG 2026-08-16)
- **DB viva + backup tar**: el tar puede capturar la DB a mitad de escritura — persist.sh usa `--warning=no-file-changed` y el backup es atómico (extract a temp + mv). — (CHANGELOG 2026-08-16)

## Regla de actualización

sqlite3 del sistema: no tocar. Esquemas nuevos: migración con columnas añadidas
(ALTER TABLE), nunca recrear la DB viva del gateway sin backup previo.
