#!/usr/bin/env python3
"""
enrich-articles.py — Enriquecimiento de contenido para captions informados (2026-10-22)

Problema que resuelve: los broadcasters (discord/whatsapp/instagram) generan el
caption con SOLO el titulo del articulo (la columna `description` de articles
esta vacia en el 100% de los casos — blogwatcher v0.0.4 no la puebla). Un LLM
que comenta un titular sin contenido real INVENTA (afirmaciones, causas,
"expertos dicen") => riesgo de alucinacion y de marca.

Solucion (aditiva, backwards-compatible):
  - Tabla NUEVA `article_extracts` en la MISMA DB (articles/blogs intactos).
  - Por articulo: extracto del contenido REAL (~1500-2500 chars, HTML limpio).
  - Fuente 1: contenido completo del item RSS (content:encoded/description)
    — 1 fetch de feed por blog por corrida, match por URL normalizada.
  - Fuente 2: description nativa del scan (blogwatcher scan --store-descriptions).
  - Fuente 3 (fallback): fetch de la pagina del articulo + extraccion
    readability-lite (mejor bloque <article>/<main>/<body> por densidad).
  - Se guarda la fuente mas larga. Fallback honesto: si todo falla
    (403/paywall/timeout), extract queda '' y fetch_status documenta la razon.

Interfaz para broadcasters (Meta Business):
  SELECT a.title, a.url, e.extract, e.source, e.fetch_status
    FROM articles a JOIN article_extracts e ON e.article_id = a.id
   WHERE a.id = ?;
  - e.extract TEXT: contenido real del articulo, ~1500-2500 chars ('' si fallo).
  - e.source: 'rss' | 'native' | 'page' | '' (vacio = no obtenido).
  - e.fetch_status: 'ok' (>=200 chars, comentar libre) | 'thin' (50-199,
    caption descriptivo sin especular) | 'empty' | 'http:<code>' | 'error:<msg>'
  - Regla de oro: extract='' o status!='ok' → caption generico/descriptivo,
    JAMAS especular ni inventar "expertos dicen".

Uso:
  enrich-articles.py [--limit N] [--db PATH] [--dry-run] [--article ID] [--verbose]
  - Llamado por rss-broadcast.sh tras el scan (no fatal si falla).
  - --dry-run: selecciona y muestra que haria, NO escribe.
  - --article ID: fuerza un articulo especifico (testing).

Salida: log a stdout (rss-broadcast.sh lo tee'a al log). Exit 0 salvo args malos.
"""
import html as htmllib
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# ═══════════════════ CONFIG ═══════════════════

DEFAULT_DB = "/home/victoria/.victoria-custom/blogwatcher/blogwatcher.db"
DEFAULT_LIMIT = 40          # max articulos por corrida (page fetch ~3-5s c/u)
WINDOW_HOURS = 72           # solo articulos descubiertos en esta ventana
RETRY_HOURS = 6              # reintentar fallos despues de este tiempo
MAX_RETRIES = 2              # reintentos maximos por articulo
TARGET_MAX = 2500            # chars objetivo del extracto
TARGET_MIN_RSS = 300         # min chars (rss+native) para NO ir a la pagina
MIN_USEFUL = 200             # >= esto => fetch_status 'ok'; menos => 'thin'
FEED_TIMEOUT = 12
PAGE_TIMEOUT = 15
DEFAULT_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
              "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36")

# ═══════════════════ HELPERS ═══════════════════

def log(msg: str):
    ts = datetime.now().astimezone().strftime("%H:%M:%S ET")
    print(f"[enrich {ts}] {msg}", flush=True)


def norm_url(u: str) -> str:
    """Clave de match feed↔articulo: host lowercase, sin query/fragment/trailing slash."""
    try:
        p = urllib.parse.urlsplit(u.strip())
        return f"{p.scheme.lower()}://{p.netloc.lower()}{p.path.rstrip('/')}"
    except Exception:
        return u.strip().rstrip('/')


def strip_cdata(s: str) -> str:
    return re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", s, flags=re.S)


def clean_html(raw: str) -> str:
    """HTML → texto plano: scripts/styles fuera, tags fuera, entidades, espacios."""
    txt = re.sub(r"<script.*?</script>|<style.*?</style>|<noscript.*?</noscript>",
                 " ", raw, flags=re.S | re.I)
    txt = re.sub(r"<[^>]+>", " ", txt)
    txt = htmllib.unescape(txt)
    return re.sub(r"\s+", " ", txt).strip()


def cut_to_target(text: str, target: int = TARGET_MAX) -> str:
    """Recorta al objetivo en frontera de parrafo/oracion."""
    if len(text) <= target:
        return text
    cut = text[:target]
    # frontera de parrafo
    for sep in ("\n\n", ". ", ".\n", "¿", "? "):
        idx = cut.rfind(sep)
        if idx > target * 0.6:
            return cut[:idx + (2 if sep == ". " else len(sep))].strip()
    return cut.rsplit(" ", 1)[0].strip()


# ═══════════════════ FUENTE 1: RSS ═══════════════════

def fetch_url(url: str, ua: str, timeout: int) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", errors="ignore")


def parse_feed_items(raw: str) -> dict:
    """URL normalizada → mejor texto de contenido del item (RSS item o Atom entry)."""
    out: dict[str, str] = {}
    blocks = re.findall(r"<item[ >].*?</item>|<entry[ >].*?</entry>", raw, re.S)
    for b in blocks:
        # link: RSS <link>texto</link> | Atom <link href="..."/>
        link = ""
        m = re.search(r"<link[^>]*href=[\"']([^\"']+)[\"']", b)
        if m:
            link = m.group(1)
        else:
            m = re.search(r"<link[^>]*>(.*?)</link>", b, re.S)
            if m:
                link = strip_cdata(m.group(1)).strip()
        if not link:
            continue
        # contenido: content:encoded > content > description > summary
        best = ""
        for pat in (r"<content:encoded[^>]*>(.*?)</content:encoded>",
                    r"<content[^>]*>(.*?)</content>",
                    r"<description[^>]*>(.*?)</description>",
                    r"<summary[^>]*>(.*?)</summary>"):
            m = re.search(pat, b, re.S)
            if m:
                cand = clean_html(strip_cdata(m.group(1)))
                if len(cand) > len(best):
                    best = cand
        key = norm_url(link)
        if key not in out or len(best) > len(out[key]):
            out[key] = best
    return out


def load_feed_map(feed_url: str, ua: str) -> tuple[dict, str]:
    """Fetch del feed del blog → {url_norm: texto}. Retorna (map, status)."""
    if not feed_url:
        return {}, "no_feed_url"
    try:
        raw = fetch_url(feed_url, ua, FEED_TIMEOUT)
        return parse_feed_items(raw), "ok"
    except urllib.error.HTTPError as e:
        return {}, f"http:{e.code}"
    except Exception as e:  # noqa: BLE001 — cualquier fallo de red es no-fatal
        return {}, f"error:{type(e).__name__}"


# ═══════════════════ FUENTE 2: PAGINA ═══════════════════

BLOCK_RE = re.compile(
    r"<(script|style|nav|header|footer|aside|form|noscript|svg|iframe|figure)"
    r"[^>]*>.*?</\1>", re.S | re.I)


def _paras_from(html_frag: str) -> list[str]:
    paras = []
    for pm in re.finditer(r"<p[^>]*>(.*?)</p>", html_frag, re.S | re.I):
        t = clean_html(pm.group(1))
        if len(t) > 40:  # descarta captions/boilerplate cortos
            paras.append(t)
    return paras


def extract_page_text(raw_html: str) -> str:
    """Readability-lite: entre todos los bloques <article>/<main>/<body>,
    el que MAS texto de parrafos tenga (el primer <article> puede ser un widget)."""
    html_txt = BLOCK_RE.sub(" ", raw_html)
    candidates: list[str] = []
    candidates += re.findall(r"<article[^>]*>(.*?)</article>", html_txt, re.S | re.I)
    m = re.search(r"<main[^>]*>(.*?)</main>", html_txt, re.S | re.I)
    if m:
        candidates.append(m.group(1))
    m = re.search(r"<body[^>]*>(.*?)</body>", html_txt, re.S | re.I)
    if m:
        candidates.append(m.group(1))
    best: list[str] = []
    for cand in candidates:
        paras = _paras_from(cand)
        if sum(len(p) for p in paras) > sum(len(p) for p in best):
            best = paras
    if not best:  # ultimo recurso: parrafos de toda la pagina
        best = _paras_from(html_txt)
    return "\n\n".join(best)


def fetch_page(url: str, ua: str) -> tuple[str, str]:
    """Fetch pagina del articulo → (texto, status)."""
    try:
        raw = fetch_url(url, ua, PAGE_TIMEOUT)
    except urllib.error.HTTPError as e:
        return "", f"http:{e.code}"
    except Exception as e:  # noqa: BLE001
        return "", f"error:{type(e).__name__}"
    text = extract_page_text(raw)
    if len(text) < MIN_USEFUL:
        return text, "no_content"
    return text, "ok"


# ═══════════════════ MAIN ═══════════════════

def ensure_table(con: sqlite3.Connection):
    con.execute("""
        CREATE TABLE IF NOT EXISTS article_extracts (
            article_id INTEGER PRIMARY KEY REFERENCES articles(id),
            extract TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL DEFAULT '',
            fetch_status TEXT NOT NULL DEFAULT '',
            retry_count INTEGER NOT NULL DEFAULT 0,
            fetched_at TEXT NOT NULL DEFAULT ''
        )
    """)
    con.commit()


def select_candidates(con: sqlite3.Connection, limit: int, article_id: int | None):
    if article_id is not None:
        return con.execute(
            "SELECT a.id, a.url, b.name, b.feed_url, "
            "COALESCE(b.user_agent, '') FROM articles a "
            "JOIN blogs b ON a.blog_id = b.id WHERE a.id = ?", (article_id,)).fetchall()
    return con.execute(
        """
        SELECT a.id, a.url, b.name, b.feed_url, COALESCE(b.user_agent, '')
          FROM articles a
          JOIN blogs b ON a.blog_id = b.id
          LEFT JOIN article_extracts e ON e.article_id = a.id
         WHERE a.is_read = 0
           AND a.discovered_date > datetime('now', ?)
           AND (e.article_id IS NULL
                OR (e.fetch_status != 'ok'
                    AND e.retry_count < ?
                    AND e.fetched_at < datetime('now', ?)))
         ORDER BY a.discovered_date DESC
         LIMIT ?
        """,
        (f"-{WINDOW_HOURS} hours", MAX_RETRIES, f"-{RETRY_HOURS} hours", limit),
    ).fetchall()


def main() -> int:
    args = sys.argv[1:]
    opts = {"limit": DEFAULT_LIMIT, "db": DEFAULT_DB, "dry": False,
            "article": None, "verbose": False}
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--limit":
            i += 1; opts["limit"] = int(args[i])
        elif a == "--db":
            i += 1; opts["db"] = args[i]
        elif a == "--article":
            i += 1; opts["article"] = int(args[i])
        elif a == "--dry-run":
            opts["dry"] = True
        elif a in ("-v", "--verbose"):
            opts["verbose"] = True
        else:
            print(f"uso: {sys.argv[0]} [--limit N] [--db PATH] [--dry-run] "
                  f"[--article ID] [-v]", file=sys.stderr)
            return 2
        i += 1

    con = sqlite3.connect(opts["db"], timeout=30)
    ensure_table(con)
    rows = select_candidates(con, opts["limit"], opts["article"])
    if not rows:
        log("0 candidatos — nada que enriquecer")
        return 0

    log(f"{len(rows)} candidatos (limit={opts['limit']}, ventana {WINDOW_HOURS}h)"
        + (" [DRY-RUN]" if opts["dry"] else ""))

    feed_cache: dict[str, tuple[dict, str]] = {}  # feed_url → (map, status)
    # descriptions nativas del scan (--store-descriptions), para los candidatos
    ids = [r[0] for r in rows]
    native_descs: dict[int, str] = {}
    if ids:
        placeholders = ",".join("?" * len(ids))
        for aid, desc in con.execute(
                f"SELECT id, COALESCE(description, '') FROM articles WHERE id IN ({placeholders})",
                ids):
            if desc:
                native_descs[aid] = desc
    results = []  # (article_id, extract, source, status, retry_count)
    stats = {"rss": 0, "page": 0, "native": 0, "empty": 0, "fail": 0}
    t0 = time.time()

    for art_id, url, blog, feed_url, ua in rows:
        ua = ua or DEFAULT_UA
        extract, source, status = "", "", ""

        # Fuente 1: contenido completo del item RSS (content:encoded > description)
        rss_text = ""
        if feed_url:
            if feed_url not in feed_cache:
                feed_cache[feed_url] = load_feed_map(feed_url, ua)
            fmap, fstat = feed_cache[feed_url]
            if fstat == "ok":
                rss_text = fmap.get(norm_url(url), "")
            elif opts["verbose"]:
                log(f"  feed {blog}: {fstat}")

        # Fuente 2: description nativa del scan (--store-descriptions)
        native = ""
        if native_descs.get(art_id):
            native = clean_html(native_descs[art_id])

        best, source = (rss_text, "rss") if len(rss_text) >= len(native) else (native, "native")

        # Fuente 3: pagina del articulo (si rss+native insuficientes)
        if len(best) < TARGET_MIN_RSS:
            ptext, pstat = fetch_page(url, ua)
            if len(ptext) > len(best):
                best, source = ptext, "page"
            elif not best and pstat not in ("ok",):
                status = pstat  # documenta el fallo del fetch

        extract = cut_to_target(best) if best else ""
        if not status:
            if len(extract) >= MIN_USEFUL:
                status = "ok"
            elif extract:
                status = "thin"
            else:
                status = "empty"

        if status == "ok":
            stats[source if source in stats else "rss"] += 1
        elif status in ("thin", "empty"):
            stats["empty"] += 1
        else:
            stats["fail"] += 1

        prev = con.execute(
            "SELECT retry_count FROM article_extracts WHERE article_id = ?",
            (art_id,)).fetchone()
        retry = (prev[0] + 1) if prev else 0
        results.append((art_id, extract, source, status, retry))

        if opts["verbose"]:
            mark = "✓" if status == "ok" else "✗"
            log(f"  {mark} [{blog}] {status:12s} src={source or '-':4s} "
                f"len={len(extract):4d} {url[:70]}")

    elapsed = time.time() - t0
    log(f"hecho en {elapsed:.0f}s — rss={stats['rss']} page={stats['page']} "
        f"empty={stats['empty']} fail={stats['fail']}")

    if opts["dry"]:
        log("DRY-RUN: sin escrituras")
        return 0

    # Escritura en UNA transaccion (journal delete: no competir con el scan)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with con:
        con.executemany(
            """INSERT INTO article_extracts
                   (article_id, extract, source, fetch_status, retry_count, fetched_at)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(article_id) DO UPDATE SET
                   extract=excluded.extract, source=excluded.source,
                   fetch_status=excluded.fetch_status,
                   retry_count=excluded.retry_count, fetched_at=excluded.fetched_at""",
            [(aid, ext, src, st, rc, now) for aid, ext, src, st, rc in results],
        )
    log(f"escritos {len(results)} registros en article_extracts")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
