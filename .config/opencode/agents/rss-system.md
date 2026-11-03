---
name: RSS System
description: RSS/Atom feed aggregation. Monitors blogs via blogwatcher CLI (13 feeds, DB host + copia sandbox), enriches articles with real content extracts (article_extracts) so social broadcasters generate informed captions without hallucination, OPA policies.
mode: subagent
hidden: false
temperature: 0.1
---
> **Frescura**: lo LIVE manda (`systemctl`/`curl`/`docker`/`nvidia-smi`/logs primero); este doc trae receta y topología. Si discrepan: actúa sobre lo live, actualiza doc + changelog y reporta (protocolo en `agents/victoria.md` §Frescura).

# RSS News Service — blogwatcher (RSS/Atom Feed Aggregation)

## 1. Objetivo

Monitorear feeds RSS/Atom de blogs, detectar nuevos artículos automáticamente y
proveer a los broadcasters sociales (Meta Business) los DATOS suficientes para
comentarios informados: título + extracto del contenido real del artículo
(§14) — sin especulación ni alucinación (directiva del owner 2026-10-22).

## 2. Arquitectura

```
[feeds RSS/Atom] → blogwatcher scan (HOST, internet directo, cron 2h)
                     → DB SQLite HOST (primaria) → enrich-articles.py (extractos)
                     → docker cp → copia DB en sandbox (Victoria la ve via skill)
                     → news-central.json (feed central) → broadcasters (Meta Business)
```

| Componente | Detalle |
|---|---|
| Skill npm | `@polyskill/openclaw.blogwatcher` v1.0.1 (manifest solo, 2987 bytes) — `skills.entries.blogwatcher: {enabled: true}` en `openclaw.json` |
| CLI binary | `/sandbox/.openclaw/bin/blogwatcher` (13.9MB, Go ARM64 estático, `CGO_ENABLED=0`, fuente v0.0.4 desde 2026-09-04; `-v` reporta "dev" — build sin version inyectada) |
| Binario canónico (host) | `/home/victoria/.victoria-custom/bin/blogwatcher` — copiado al sandbox por `openclaw-rss-install.sh ensure` (gancho del ensure-loop); backup del binario v0.0.3 en `blogwatcher.v0.0.3.bak` |
| Source repo | `github.com/Hyaxia/blogwatcher` **v0.0.4** (Go 1.24+, 144★, `modernc.org/sqlite` pure-Go sin CGO; rebuild desde `/tmp/opencode/blogwatcher` con `CGO_ENABLED=0 /usr/local/go/bin/go build -ldflags="-s -w"`) |
| **DB SQLite (PRIMARIA, host)** | `/home/victoria/.victoria-custom/blogwatcher/blogwatcher.db` (~5.7MB tras VACUUM, ~7,000 articles, 13 blogs; el scan corre AQUÍ con `BLOGWATCHER_DB`) |
| DB copia (sandbox) | `/sandbox/.openclaw/blogwatcher/blogwatcher.db` — `docker cp` desde la host en cada corrida de `rss-broadcast.sh` (cada 2h); es COPIA, no primaria |
| Enriquecimiento | `~/.victoria-custom/bin/enrich-articles.py` — tabla `article_extracts` (ver §14); corre tras el scan en `rss-broadcast.sh` |
| Policy | `rss-feeds` preset custom (14 hosts, rules GET/HEAD); aplicado vía `nemoclaw sandbox policy add --from-file`; BrowserRouter de `~/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/rss-feeds.yaml` |

## 3. Ejecución

El sandbox usa un proxy L7 que hace MITM de TLS con su propio CA. Para que
blogwatcher (Go) valide el cert, hay que pasar:
- `HTTPS_PROXY=http://10.200.0.1:3128` (proxy L7 interno del sandbox)
- `SSL_CERT_FILE=/etc/openshell-tls/ca-bundle.pem` (CA del proxy)
- `SSL_CERT_DIR=/etc/openshell-tls`
- `BLOGWATCHER_DB=/sandbox/.openclaw/blogwatcher/blogwatcher.db`
- `runuser -u sandbox --` (los permisos del binario son sandbox:sandbox 755)
- `nsenter -t $(pgrep -f openclaw-gateway|head -1) -n --` (acceder al netns del gateway)

Ejemplo completo:

```bash
CID=$(docker ps --filter "name=openshell-victoria-armada" --format '{{.ID}}' | head -1)
docker exec -u root -w /sandbox "$CID" sh -c '
  G=$(pgrep -f openclaw-gateway|head -1)
  nsenter -t $G -n -- env BLOGWATCHER_DB=/sandbox/.openclaw/blogwatcher/blogwatcher.db \
    HTTPS_PROXY=http://10.200.0.1:3128 \
    SSL_CERT_FILE=/etc/openshell-tls/ca-bundle.pem \
    SSL_CERT_DIR=/etc/openshell-tls \
    runuser -u sandbox -- /sandbox/.openclaw/bin/blogwatcher scan'
```

## 4. Comandos del CLI

| Comando | Descripción |
|---|---|
| `blogwatcher add <name> <url> [--feed-url URL] [--user-agent UA] [--scrape-selector CSS]` | Agregar blog a monitorear |
| `blogwatcher remove <name> [-y]` | Remover blog |
| `blogwatcher blogs` | Listar blogs monitoreados |
| `blogwatcher scan [blog_name] [-s] [-w N]` | Escanear blogs para nuevos artículos |
| `blogwatcher articles` | Listar artículos (unread default) |
| `blogwatcher articles --all` | Listar todos (read+unread) |
| `blogwatcher read <id>` | Marcar artículo como leído |
| `blogwatcher read-all` | Marcar todos como leídos |
| `blogwatcher unread <id>` | Marcar como unread |

Flag `--feed-url` (guión, NO `--feed_url`). Flag `--user-agent` permite UA
override por blog (para evadir WAFs anti-bot — limitado; usa header pero Go
sigue con JA3 fingerprint de Go-http-client, así que CloudflareWAF sigue
detectándolo).

## 5. Blogs activos (13 feeds — conteos LIVE 2026-10-26)

| # | Blog | Feed URL (LIVE en DB) | Categoría | Artículos |
|---|---|---|---|---|
| 1 | ArsTechnica | `feeds.arstechnica.com/arstechnica/index` | General Tech (En) | 689 |
| 2 | TechCrunch | `feeds.feedburner.com/TechCrunch` | Startups/Tech (En) | 21 |
| 3 | Wired | `www.wired.com/feed/rss` | Tech Culture (En) | 1,075 |
| 4 | Cointelegraph | `cointelegraph.com/rss` | Blockchain | 1,058 |
| 5 | Hipertextual | `hipertextual.com/feed/` | Tech/Gaming (Es) | 797 |
| 6 | CoinDesk | `feeds.feedburner.com/CoinDesk` | Cryptocurrency | 1,067 |
| 7 | K8s | `kubernetes.io/feed.xml` | DevOps/Cloud (En) | 51 |
| 8 | Hackernoon | `hackernoon.com/feed` | Hacking/Security | 541 |
| 9 | GamerLinux | `www.gamingonlinux.com/article_rss.php` | Gaming/Linux | 173 |
| 10 | Docker | `www.docker.com/feed/` (mudó de blog.docker.com) | Containers/DevOps | 19 |
| 11 | TheRegister | `www.theregister.com/feed` (mudó de headlines.atom) | Security/Enterprise (En) | 303 |
| 12 | Xataka | `www.xataka.com/atom.xml` (301→feedburner.xml; scrape-selector de respaldo) | Tech (Es) | 730 |
| 13 | XatakaMX | `www.xataka.com.mx/atom.xml` (ídem) | Tech Mexico (Es) | 488 |

**Total**: ~7,000 artículos (2026-10-26; crece ~100-130/día con el scan cada 2h).
Blogs 7-11 llevan `--user-agent` override (Chrome 126 aarch64) en la DB — sin
eso varios dan 403 (JA3 de Go-http-client). Xataka/XatakaMX funcionan hoy por
feed Atom; el `--scrape-selector "h2.abstract-title a"` quedó como respaldo.

**Descartados**:
- LinuxLat (`linuxlatinoamerica.org` muerto, curl 000).
- **DevTo (`dev.to/feed`) REMOVIDO 2026-10-26**: agregado 2026-10-08, publicaba
  ~141 arts/día (firehose de comunidad dev) = 52% de la ingesta y 48% del work
  de enrich, pero DC/WA nunca lo seleccionan (filtran a 6 blogs) y en IG causó
  una regresión de contenido: su flood dominaba el pool `rows[:8]` de
  `pick_article` → IG publicó SOLO DevTo durante 17 días (33 posts desde
  2026-10-09; en septiembre eran 0). Remoción manual por SQL en orden FK
  (extracts→articles→blogs) + VACUUM (9.3→5.7MB) porque `blogwatcher remove`
  nativo falla con FK (bug upstream v0.0.4, ver §11). Backup previo:
  `blogwatcher.db.bkup-20261026-pre-devto`. Para revertir:
  `blogwatcher add DevTo https://dev.to/feed --user-agent "<Chrome UA>"`.
  La policy `rss-feeds` conserva dev.to como host permitido (inerte, sin
  fetcher — no requiere restart del sandbox).

## 6. Plan de distribución por canal Discord (borrador)

| Categoría | Canal Discord | Blogs | Frecuencia |
|---|---|---|---|
| Crypto | `#crypto-news` | CoinDesk, Cointelegraph | Cada 2 horas |
| Security | `#security-news` | The Register, Hackernoon (pendiente feed functional) | Cada 4 horas |
| Gaming | `#gaming-news` | GamerLinux (pendiente), Hipertextual | Cada 6 horas |
| DevOps | `#devops-kubernetes` | K8s, Docker (pendientes) | Una vez al día |
| Startups | `#startups` | TechCrunch | Una vez al día |
| Tech General (En) | `#general` | Ars Technica, Wired | Cada 6 horas |
| Tech (Es) | `#general` | Hipertextual, Xataka/XatakaMX (pendientes) | Cada 6 horas |
| **Todos (resumen)** | `#news-summary` | Todos (1-2 principales) | Una vez al día |

## 8. Broadcasts automáticos a Discord + WhatsApp (producción)

> **CANÓNICO DE DISTRIBUCIÓN**: este §8 es solo resumen de ingesta. La fuente
> de verdad de pipelines, horarios, webhooks, anti-duplicados y formato es el
> subagente `Meta-Business.md`. No duplicar lógica aquí: si cambia un
> horario o un grupo, se edita allá y aquí solo se apunta.
> **Feed central (Plan Victoria 2.0, 2026-09-15)**: `rss-broadcast.sh` (cron
> cada 2h) hace el scan ÚNICO de blogwatcher en el host y escribe
> `/home/victoria/.victoria-custom/state/news-central.json` (artículos
> recientes + timestamp). `discord-broadcast.py`, `whatsapp-broadcast.py` e
> `instagram-broadcast.py` consumen de la DB host
> (`~/.victoria-custom/blogwatcher/blogwatcher.db`) y del feed central en vez
> de escanear por separado. Objetivo: 1 scan → N salidas (sin triple scan
> compitiendo por red/GPU).

El sistema de distribución automática de noticias tiene DOS canales activos,
ambos corren en el **HOST** (no en el sandbox) vía cron. **Solamente Tech Hub
by Alfredo (TH)** — los otros servidores (La Verganza, EnWebs, GamerParty) son
para interacción directa con el owner, nunca distribución automática.

### 8.1 Discord (`discord-broadcast.py` / `.sh`)
- **Destino**: solo `#ethical-hackers` de TH (webhook `1539323889094496438`).
  `#penetration-testers` y demás desactivados.
- **Pipeline**: blogwatcher scan → selecciona artículos de cyber/hacking/crypto →
  LLM local (`Qwen3.6-35B-normal`, thinking OFF) genera opinión humana máx 40
  palabras → extrae imagen del feed → envía embed a Discord (título + opinión +
  imagen + URL).
- **Horario**: 3x/semana (mar/jue/dom — ver `crontab -l | grep broadcast`; lo exacto es territorio Meta-Business.md).
- **Webhooks**: `~/.discord-webhooks`.

### 8.2 WhatsApp (`whatsapp-broadcast.py` / `.sh`)
- **Destinos** (3 grupos TH):
  | Grupo | JID | Categoría |
  |---|---|---|
  | Zona Automotriz | `120363408789689253@g.us` | tech en vehículos (EV, OBD, motores…) |
  | Internacionales | `120363408229988464@g.us` | cualquier tech internacional incl. RD (fallback general) |
  | Programadores | `120363406295813450@g.us` | dev/tech/infosec incl. crypto |
- **Pipeline**: blogwatcher scan → clasificación por keywords con word-boundaries
  (automotriz: car|cars|automotive|vehicle|ev|tesla|obd|engine|hypercar|charging…
  programadores: developer|code|software|api|github|linux|python|security|hack|cyber|crypto|bitcoin|blockchain|llm|docker|kubernetes…; internacionales: fallback general) →
  1 artículo random por sala (máx 1 post/sala) → opinión LLM local (máx 40 palabras) →
  imagen del feed RSS descargada al host + `docker cp` al sandbox →
  envío con `openclaw message send --media` en el netns del gateway.
- **Anti-duplicados**: estado JSON `/home/victoria/.victoria-custom/state/whatsapp-sent.json`
  (article IDs).
- **Horario**: 3x/semana (mar/jue/dom — ver `crontab -l | grep broadcast`; lo exacto es territorio Meta-Business.md).
- **Login**: sesión WhatsApp activa con `+12025000357`.

### 8.3 Formato del mensaje (footer normalizado, 2026-08-19)
El footer va en una línea propia con **una línea en blanco de separación** tras
el link de la fuente, y **sin `·` inicial** delante de `www.`:
```
📰 *<Título>*

<Opinión>

🔗 <url fuente>

www.alfredo.pro · <Blog> · <dd/mm hh:mm>
```
Aplicado en `whatsapp-broadcast.py` (mensaje de texto con `\n\n` antes del footer)
y en `discord-broadcast.py` (embed footer). El `blog` y la fecha se generan con
`datetime.now(timezone(timedelta(hours=-4)))` (EDT).

### 8.4 Scripts / rutas / persistencia
- `/home/victoria/whatsapp-broadcast.py` + `.sh` (lógica + wrapper cron)
- `/home/victoria/discord-broadcast.py` + `.sh`
- Logs: `/home/victoria/logs/{whatsapp,discord}-broadcast.log`
- Cron (LIVE 2026-10-22): `rss-broadcast.sh full` cada 2h (`0 */2`); discord/whatsapp 3x/semana; instagram `--auto` cada 20min 9-21. Detalle exacto = Meta-Business.md.
- Todo vive en el **host** (`/home/victoria/`), por lo que **sobrevive reboot,
  power failure y rebuild/restart de contenedores** sin acción extra. El estado
  anti-duplicados (`whatsapp-sent.json`) y los webhooks también están en el host.
- **Media upload WhatsApp (crítico)**: ver subagente `OpenClaw`
  sección 5 (parche `patch_media_upload` + policy egress `*.whatsapp.net` como
  `tls: skip`). Si un broadcast envía sin imagen o falla con "Media upload
  failed", verificar ese parche y la policy.

## 9. Políticas de red

`rss_feeds` policy v6 (custom preset) — en
`~/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/rss-feeds.yaml`:

- **Hosts permitidos**: feeds.feedburner.com, feeds.arstechnica.com,
  www.theregister.com, kubernetes.io, blog.docker.com, dev.to (inerte desde
  2026-10-26: el feed DevTo fue removido, nada lo fetchea; se deja para no
  forzar restart del sandbox), coindesk.com,
  cointelegraph.com, hipertextual.com, gamerlinux.com (en realidad
  gamingonlinux.com), linuxlatinoamerica.org, www.xataka.com,
  www.xataka.com.mx, www.wired.com, www.techcrunch.com
- **Métodos**: GET, HEAD (paths variables según host)
- **Binarios autorizados**: `/sandbox/.openclaw/bin/blogwatcher`,
  `/usr/bin/curl`, `/usr/bin/python3`, `/usr/local/bin/node`,
  `/home/linuxbrew/.linuxbrew/bin/go`, etc.

Para aplicar (si se cambia el preset):
```bash
nemoclaw sandbox policy add victoria-armada rss-feeds \
  --from-file /home/victoria/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/rss-feeds.yaml --yes
# Reinicia el sandbox para que el proxy L7 recargue la policy
nemoclaw victoria-armada stop && nemoclaw victoria-armada start
```

## 9. Estructura de la DB (schema LIVE 2026-10-22)

```sql
-- Blogs (propietario: binario blogwatcher)
blogs: id, name, url, feed_url, user_agent, scrape_selector, last_scanned

-- Articles (propietario: binario blogwatcher; description se puebla desde
-- el scan con --store-descriptions, 2026-10-22; keywords sin uso)
articles: id, blog_id, title, url, published_date, discovered_date,
          is_read, keywords, description

-- Extractos de contenido (propietario: enrich-articles.py, 2026-10-22)
article_extracts: article_id (PK, FK articles.id), extract, source,
                  fetch_status, retry_count, fetched_at
```

## 10. Integración con OpenClaw

Skill `@polyskill/openclaw.blogwatcher` v1.0.1 habilitado en `openclaw.json`:
```json
{
  "skills": {
    "entries": {
      "blogwatcher": { "enabled": true }
    }
  }
}
```

Skills de blogwatcher exponen tools al agente Victoria para que pueda:
- `blogwatcher_scan`, `blogwatcher_articles`, `blogwatcher_blogs`,
  `blogwatcher_get <id>`, `blogwatcher_read <id>`, `blogwatcher_read-all`,
  `blogwatcher_add`, `blogwatcher_remove`, `blogwatcher_read_mark`

## 11. Troubleshooting

### Error: `Forbidden` al escanear
**Causa 1**: Policy `rss-feeds` no cargada en el proxy L7 del sandbox.
**Fix**: `nemoclaw sandbox policy add victoria-armada rss-feeds --from-file
<preset.yaml> --yes` + restart sandbox.

**Causa 2**: WAF del sitio objetivo (Cloudflare, Akamai) bloquea
Go-http-client via JA3 fingerprint (no solucionable con UA override de
header solo).
**Fix**: Buscar feed alternativo (FeedBurner proxy, RSS.app mirror,
community mirror), o usar scraping HTML (`--scrape-selector` flag).

### Error: `tls: failed to verify certificate: x509: certificate signed by unknown authority`
**Causa**: Go no confía en el cert MITM del proxy L7 del sandbox.
**Fix**: Pasa `SSL_CERT_FILE=/etc/openshell-tls/ca-bundle.pem
SSL_CERT_DIR=/etc/openshell-tls` en el env.

### Error: `DENIED -(0) -> host:443 ... reason:failed to resolve peer binary`
**Causa**: blogwatcher corre fuera del netns del gateway (ejecutado
directamente con `docker exec` en lugar de `nsenter -t $G -n`).
**Fix**: Usar el patrón `nsenter -t $G -n -- env ... runuser -u sandbox --
/sandbox/.openclaw/bin/blogwatcher ...` (ver sección 3 Ejecución).

### Error: `mkdir /root/.blogwatcher: permission denied`
**Causa**: HOME del sandbox user es `/root` (no writable) y BLOGWATCHER_DB
no fijado.
**Fix**: Pasar `BLOGWATCHER_DB=/sandbox/.openclaw/blogwatcher/blogwatcher.db`
y crear el dir `mkdir -p /sandbox/.openclaw/blogwatcher` (sandbox-owned,
dentro de `/.openclaw/`).

### Ningún artículo detectado en un feed funcional
**Causa**: Ya se escanearon todos los articles existentes como "new" y están
en la DB; re-scan no los marca de nuevo.
**Fix**: `blogwatcher read-all` para marcar todos como leídos, luego
`blogwatcher scan` para detectar nuevos desde entonces.

### Error: `FOREIGN KEY constraint failed` con `blogwatcher remove`
**Causa**: bug upstream v0.0.4 — `remove` borra la fila de `blogs` sin hacer
cascade-delete de `articles` (FK articles.blog_id → blogs.id) → falla SIEMPRE
que el blog tenga artículos.
**Fix**: remoción manual por SQL en orden FK (con backup previo de la DB):
```sql
BEGIN;
DELETE FROM article_extracts WHERE article_id IN
  (SELECT id FROM articles WHERE blog_id=(SELECT id FROM blogs WHERE name='<X>'));
DELETE FROM articles WHERE blog_id=(SELECT id FROM blogs WHERE name='<X>');
DELETE FROM blogs WHERE name='<X>';
COMMIT;
VACUUM;  -- reclama espacio
```
Verificado E2E 2026-10-26 (remoción DevTo): binario lee 13 blogs OK, scan OK,
enrich OK, `PRAGMA foreign_key_check` limpio. Reportable upstream si sacan
v0.0.5.

## 12. Reconstrucción del CLI (si se actualiza a v0.0.4+)

```bash
# Go 1.26.6 arm64 instalado en /usr/local/go
export PATH="/usr/local/go/bin:$PATH"
rm -rf /tmp/opencode/blogwatcher-src
git clone --depth 1 --branch v0.0.4 https://github.com/Hyaxia/blogwatcher.git /tmp/opencode/blogwatcher-src
cd /tmp/opencode/blogwatcher-src
CGO_ENABLED=0 go build -ldflags="-s -w" -o /home/victoria/.victoria-custom/bin/blogwatcher ./cmd/blogwatcher
# verify
file /home/victoria/.victoria-custom/bin/blogwatcher  # ELF 64-bit ARM aarch64 statically linked
# El ensure-loop lo propagará al sandbox en el próximo ciclo
```

## 13. Referencias

- Skill source: `@polyskill/openclaw.blogwatcher` v1.0.1 (npm registry)
- CLI source: `https://github.com/Hyaxia/blogwatcher` (Go v0.0.4 — compilado local ARM64 estático; upstream = v0.0.4 sin drift)
- Policy preset: `~/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/rss-feeds.yaml`
- Binario canónico (host): `/home/victoria/.victoria-custom/bin/blogwatcher`
- Install script: `/home/victoria/openclaw-rss-install.sh`
- Persist backup: `~/.nemoclaw/persistent/victoria-armada/openclaw-latest/.openclaw/blogwatcher/blogwatcher.db`

> ⚠️ **Data safety: la DB PRIMARIA vive en el HOST** (`~/.victoria-custom/blogwatcher/blogwatcher.db`)
> → sobrevive reboot/power failure/rebuild del sandbox. La copia del sandbox se
> re-crea con `docker cp` en cada corrida de `rss-broadcast.sh` (cada 2h) — si el
> sandbox se reconstruye, la copia vuelve sola en el próximo ciclo. El binario
> canónico también vive en el host (`~/.victoria-custom/bin/blogwatcher`) y el
> ensure-loop lo re-copia. Backup adicional: `openclaw-persist.sh` incluye la DB
> del sandbox en el tar de persistencia.

## 14. Enriquecimiento de contenido — interfaz para Meta Business (2026-10-22)

> **Por qué**: los broadcasters generaban el caption con SOLO el título
> (description estaba vacía en el 100% de los artículos) → el LLM rellenaba
> con invención. Pedido del owner: comentar basándonos en lo que el artículo
> REAL dice (qué dice la gente y los expertos), sin adivinar.

**Pipeline** (dentro de `rss-broadcast.sh`, cada 2h, tras el scan y antes del
sync al sandbox): `scan --store-descriptions` (nativo, puebla
`articles.description` desde el RSS, cap 2500 chars) → `enrich-articles.py`
(completa lo que falta en `article_extracts`).

**Fuentes del extracto** (se guarda la más larga):
1. `rss` — contenido completo del item RSS (content:encoded/description),
   match por URL normalizada, 1 fetch de feed por blog por corrida.
2. `native` — `articles.description` del scan nativo.
3. `page` — fetch de la página del artículo + readability-lite (mejor bloque
   article/main/body por densidad de párrafos).

**Cómo consumirlo** (broadcasters):
```sql
SELECT a.title, a.url, e.extract, e.source, e.fetch_status
  FROM articles a
  LEFT JOIN article_extracts e ON e.article_id = a.id
 WHERE a.id = ?;
```

**Semáforo honesto** (`e.fetch_status`):
| Status | Significado | Regla para el caption |
|---|---|---|
| `ok` | extract >= 200 chars de contenido real | Comentar libre SOBRE el extracto; citar lo que dice el artículo/expertos |
| `thin` | extract 1-199 chars | Caption descriptivo del extracto corto, SIN especular |
| `empty` / `http:4xx` / `error:*` | no se obtuvo contenido | Caption genérico/descriptivo del título, JAMAS inventar causas, cifras o "expertos dicen" |

**Regla de oro**: sin extracto → no se especula. Un caption aburrido pero
honesto vale más que uno brillante pero inventado (riesgo de marca).

**Cobertura**: unread de últimos 72h, más recientes primero, cap 40/corrida
(≈480/día >> ~100-130 nuevos/día = 4x headroom tras remover DevTo; con DevTo
era ~250-400/día y el headroom se comía a 1.2-2x); reintentos de fallos tras
6h (máx 2). Verificado 2026-10-26: solo 1 artículo (Wired) de 72h sin extracto
ok — el enrich va al día.
Poblada desde 2026-10-22 20:29 ET — artículos anteriores a esa fecha NO
tienen extracto (backlog solo hacia adelante: lo que los broadcasters
puedan seleccionar hoy).

**Mantenimiento**: `python3 ~/.victoria-custom/bin/enrich-articles.py
[--limit N] [--dry-run] [--article ID] [-v]`. Nunca toca articles/blogs;
solo INSERT/UPDATE en article_extracts. No fatal: si falla, el pipeline
del scan sigue igual.

## Docs oficiales (fuentes canónicas del blogwatcher)

| Fuente | Versión/estado | URL | Verificada |
|---|---|---|---|
| Repo blogwatcher (canónico) | Hyaxia/blogwatcher — repo chico SIN docs web: README + código son la fuente canónica | https://github.com/Hyaxia/blogwatcher | 2026-10-08 VIVA |
| Nuestro binario | v0.0.4 Go ARM64 estático (CGO_ENABLED=0, compilado local) | ~/.victoria-custom/bin/blogwatcher | 2026-10-08 |
| Flags del CLI | `blogwatcher --help` — fuente de verdad offline de NUESTRA versión | local | 2026-10-08 |

## Upstream check (disciplina)

- **blogwatcher**: local v0.0.4 vs https://github.com/Hyaxia/blogwatcher/releases (upstream-sync.py cada 6h). Si sale v0.0.5+: rebuild Go estático (§12) + propagar al sandbox con `openclaw-rss-install.sh`. Verificado a mano 2026-10-26: v0.0.4 sigue siendo latest (no hay v0.0.5+). Bug upstream conocido: `remove` falla con FK si el blog tiene articles (ver §11).
- **Feeds 403-WAF**: los 9 feeds bloqueados fallan del lado servidor (Cloudflare anti-bot vs Go-http-client) — no es upstream nuestro; re-probar con FeedBurner fallback.
- **Cómo reportar**: entrada en `~/.victoria-custom/changelogs/CHANGELOG-rss.md` (sección upstream) + aviso a Victoria en el Task.

## 15. Mapa de recursos y modelo-por-etapa (audit 2026-10-26)

**Pipeline por etapa** (todo el sistema, medido):

| Etapa | Motor | Frecuencia | Costo/día |
|---|---|---|---|
| blogwatcher scan | Go binario, sin LLM | 12×/día (cron 2h) | ~8s por corrida = ~96s/día CPU |
| enrich-articles.py | Python + HTTP fetch, sin LLM | 12×/día (tras scan) | ~6s por corrida; ~100-130 arts/día (1 fetch feed/blog + page-fetch solo si RSS <300 chars) |
| news-central.json | Python | 12×/día | trivial |
| Selección/clasificación | SQL + regex keywords | DC/WA 3x/sem; IG ~2-3 ciclos/día efectivos (cron 20min pero gap-logic exit <1s) | trivial |
| Caption LLM | Qwen3.6-35B-A3B-NVFP4-normal (thinking OFF), temp 0.5, top_p 0.95, max_tokens 100 (DC/WA) / 220 (IG) | 1 req/artículo publicado | ~9 req/día, ~670 prompt tokens avg, ~65 completion; **$0.22/30 días** |
| QA visual VLM | mismo 35B (image_url, imagen ≤1024px), temp 0.1, max_tokens 150 | 1 req/imagen publicada (IG) | incluido arriba |
| Composición imagen | PIL en CPU | por post IG | trivial |
| Publicación | APIs IG/DC/WA | según cron | sin LLM |

**Veredicto modelo-por-etapa**: el 35B-A3B (MoE, 3B activos) es CORRECTO para
todo el pipeline y NO hay segundo modelo residente (decisión owner,
CHANGELOG 2026-10-26 01:45). Números: 275 reqs/30d, 183K prompt + 18K
completion tokens, avg 1.08s, max 4.99s, $0.22/30d — un modelo más chico
ahorraría ≈$0 y perdería calidad de caption/QA. Thinking OFF confirmado en
los 3 broadcasters + QA (sufijo `-normal`). Temp 0.5 captions = balance
correcto post-fix anti-alucinación (era 0.8/0.85 pre-2026-10-22); QA a 0.1
(determinista para JSON). El prefill compartido (system + reglas
anti-alucinación idénticas) aprovecha prefix-caching del vLLM.

**Desperdicio eliminado (2026-10-26)**: DevTo era 52% de la ingesta y 48% del
work de enrich para ~0 valor de broadcast (ver §5). Post-remoción: ingesta
~100-130/día, enrich con 4x headroom, DB 5.7MB.

**No-optimizaciones deliberadas** (auditadas, dejar como están): prompts de
caption ya son lean (~670 tokens con prefix-cache); crons sin overlaps (scan
8s cada 2h, IG --auto exit <1s la mayoría de ciclos); scan+enrich fetchean
el feed 2 veces por corrida (Go y Python son procesos separados — 14 GETs
extra/día ≈ 8MB/día, acoplarlos costaría más de lo que ahorra); DB sin prune
(40MB/año proyectado es trivial para SQLite — re-evaluar si pasa de 100MB).
