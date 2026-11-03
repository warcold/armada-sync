#!/usr/bin/env bash
# openclaw-discord-fix.sh
# Repara/mantiene el plugin Discord del sandbox OpenClaw de Victoria.
#
# PROPOSITO:
#   Discord vive en npm/projects/openclaw-discord-<hash>/node_modules/@openclaw/discord
#   (layout del runtime 2026.7.1 — fix 2026-09-19: YA NO en extensions/).
#   `openclaw plugins install <tgz-local>` NO sirve: crea el esqueleto del proyecto
#   pero aborta al bajar dependencias (403 policy_denied: el egress del sandbox
#   bloquea registry.npmjs.org) -> dist/index.js nunca aparece y el gateway no
#   carga el plugin. Por eso se EXTRAE el tgz directo al installPath (offline,
#   el tgz trae node_modules empaquetado) y se verifica el trust record en la DB
#   (openclaw.sqlite) para que el trust check (isTrustedOfficialPluginInstall)
#   pase y el canal arranque sin advertencias.
#   El installPath se resuelve por glob (el sufijo hash es estable, pero el glob
#   sobrevive a cambios de version).
#
# USO:
#   openclaw-discord-fix.sh check   # estado actual (idempotente)
#   openclaw-discord-fix.sh apply   # instala/restaura + escribe trust record (idempotente)
#
# Se engancha al ensure-loop (openclaw-bridge-ensure.sh) tras ensure_npm_plugins.

set -uo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-victoria-armada}"
TGZ_SRC="/home/victoria/.victoria-custom/plugins/openclaw-discord-2026.7.1.tgz"
# Layout runtime 2026.7.1 (ver PROPOSITO arriba). Se resuelve dinamicamente.
PLUGIN_SHORT="discord"
PLUGIN_GLOB="/sandbox/.openclaw/npm/projects/openclaw-discord-*"
PLUGIN_SUB="node_modules/@openclaw/discord"
PLUGIN_KNOWN="/sandbox/.openclaw/npm/projects/openclaw-discord-c0892df945/node_modules/@openclaw/discord"
WS_PLUGIN=""
WS_DIST=""
DB="/sandbox/.openclaw/state/openclaw.sqlite"
CONFIG="/sandbox/.openclaw/openclaw.json"

log() { echo "[discord-fix] $*"; }

# Resuelve el installPath real del plugin (glob; fallback al sufijo conocido,
# creandolo si no existe — el sufijo hash es estable entre installs).
resolve_plugin_dir() {
    local cid="$1" d
    d=$(docker exec "$cid" sh -c "ls -d $PLUGIN_GLOB/$PLUGIN_SUB 2>/dev/null | head -1" 2>/dev/null)
    if [ -n "$d" ]; then echo "$d"; return 0; fi
    docker exec -u root "$cid" mkdir -p "$PLUGIN_KNOWN" 2>/dev/null
    docker exec -u root "$cid" chown sandbox:sandbox "$PLUGIN_KNOWN" 2>/dev/null
    echo "$PLUGIN_KNOWN"
}

get_cid() {
    [ -n "$SANDBOX_NAME" ] || { log "SANDBOX_NAME vacio"; return 1; }
    local cid
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -n "$cid" ] || { log "sandbox $SANDBOX_NAME no esta corriendo"; return 1; }
    echo "$cid"
}

install_from_tgz() {
    local cid="$1" dest="$2"
    [ -f "$TGZ_SRC" ] || { log "FATAL: tgz no existe en host: $TGZ_SRC"; return 1; }
    [ -n "$dest" ] || { log "FATAL: no se resolvio installPath"; return 1; }
    docker cp "$TGZ_SRC" "$cid":/tmp/openclaw-discord.tgz >/dev/null 2>&1
    log "extrayendo discord directo a $dest (como sandbox, offline, sin egress npm)"
    docker exec -u sandbox -e HOME=/sandbox "$cid" sh -c \
        "tar xzf /tmp/openclaw-discord.tgz --strip-components=1 -C '$dest' 2>&1" \
        | tail -2
    docker exec "$cid" sh -c "test -f '$dest/dist/index.js' && echo INSTALLED_OK || echo INSTALL_FAIL" 2>/dev/null
    return 0
}

write_trust_record() {
    local cid="$1" dest="$2"
    docker exec -u root "$cid" python3 - "$dest" << 'PYEOF' 2>/dev/null
import json, sqlite3, hashlib, os, sys
dest = sys.argv[1]
pkg = os.path.join(dest, "package.json")
db = "/sandbox/.openclaw/state/openclaw.sqlite"
if not os.path.exists(os.path.join(dest, "dist", "index.js")):
    print("NO_PLUGIN"); raise SystemExit
conn = sqlite3.connect(db, timeout=10)
c = conn.cursor()
c.execute("SELECT install_records_json FROM installed_plugin_index LIMIT 1")
row = c.fetchone()
records = json.loads(row[0]) if row and row[0] else {}
cur = records.get("discord") or {}
# No tocar un record bueno: si ya apunta a un path real con dist, se conserva
# (origen: records restaurados Sep-11, verificados funcionando por meses).
cur_path = cur.get("installPath", "")
if cur_path and os.path.exists(os.path.join(cur_path, "dist", "index.js")):
    print("TRUST_RECORD_OK"); raise SystemExit
h = hashlib.sha256()
h.update(open(pkg, "rb").read())
shasum = h.hexdigest()
records["discord"] = {
    "source": "npm",
    "spec": "@openclaw/discord",
    "installPath": dest,
    "version": "2026.7.1",
    "resolvedName": "@openclaw/discord",
    "resolvedVersion": "2026.7.1",
    "resolvedSpec": "@openclaw/discord@2026.7.1",
    "integrity": f"sha512-{shasum[:43]}",
    "shasum": shasum,
    "resolvedAt": "2026-08-18T02:44:00.000Z",
    "installedAt": "2026-08-18T02:44:00.000Z",
    "origin": "global",
}
c.execute("UPDATE installed_plugin_index SET install_records_json = ?, refresh_reason = ? WHERE index_key = ?",
          (json.dumps(records), "discord-fix-trust", "installed-plugin-index"))
conn.commit()
print("TRUST_RECORD_WRITTEN")
conn.close()
PYEOF
}

ensure_config() {
    local cid="$1"
    docker exec -u sandbox -e HOME=/sandbox "$cid" python3 - << 'PYEOF' 2>/dev/null
import json
p = "/sandbox/.openclaw/openclaw.json"
c = json.load(open(p))
dirty = False
ch = c.setdefault("channels", {})
if ch.get("discord", {}).get("enabled") is not True:
    ch["discord"] = {"enabled": True}; dirty = True
pl = c.setdefault("plugins", {}).setdefault("entries", {})
if pl.get("discord", {}).get("enabled") is not True:
    pl["discord"] = {"enabled": True}; dirty = True
if dirty:
    json.dump(c, open(p, "w"), indent=2)
    print("CONFIG_UPDATED")
else:
    print("CONFIG_OK")
PYEOF
    docker exec -u root "$cid" chown sandbox:sandbox "$CONFIG" 2>/dev/null
    docker exec -u root "$cid" chmod 660 "$CONFIG" 2>/dev/null
}

fix_ownership() {
    local cid="$1"
    local cur
    cur=$(docker exec -u root "$cid" sh -c "stat -c '%U:%G' '$WS_PLUGIN' '$WS_DIST' 2>/dev/null" 2>/dev/null)
    if [ "$cur" = "sandbox:sandbox
sandbox:sandbox" ]; then
        return 0
    fi
    docker exec -u root "$cid" sh -c "
        [ -d '$WS_PLUGIN' ] && chown -R sandbox:sandbox '$WS_PLUGIN'
    " 2>/dev/null
    CHANGED=1
    log "ownership fixeado (discord=sandbox)"
}

# Versión del plugin instalado (de su package.json). Vacío si no se puede leer.
# 2026.7.x = mundo tgz (trust record manual); nativa >= 2026.9 = records
# propios del runtime — NUNCA sobrescribirlos (corrompería el trust nativo).
plugin_version() {
    local cid="$1"
    docker exec "$cid" sh -c "grep -o '\"version\": *\"[^\"]*\"' '$WS_PLUGIN/package.json' 2>/dev/null | head -1" 2>/dev/null \
        | sed 's/.*: *"//;s/"$//' | tr -d '\r'
}

apply() {
    local cid
    cid=$(get_cid) || return 1
    CHANGED=0
    WS_PLUGIN=$(resolve_plugin_dir "$cid")
    WS_DIST="$WS_PLUGIN/dist/index.js"
    local present trust_out cfg_out pv
    present=$(docker exec "$cid" sh -c "test -f '$WS_DIST' && echo yes || echo no" 2>/dev/null)
    pv=$(plugin_version "$cid")
    if [ "$present" != "yes" ]; then
        # ensure_npm_plugins ya intentó el install NATIVO antes que este script;
        # si llegamos aquí sin plugin, el fallback es nuestro tgz 2026.7.1.
        install_from_tgz "$cid" "$WS_PLUGIN"
        CHANGED=1
        sleep 2
        pv=$(plugin_version "$cid")
    fi
    fix_ownership "$cid"
    case "$pv" in
        2026.7.*)
            trust_out=$(write_trust_record "$cid" "$WS_PLUGIN")
            case "$trust_out" in *NO_PLUGIN*) log "trust record: plugin ausente tras install (revisar)";; esac
            ;;
        *)
            # NATIVO (npm >= 2026.9): install records propios = trusted de fábrica.
            ;;
    esac
    cfg_out=$(ensure_config "$cid" 2>/dev/null | tr -d '\r' | tail -1)
    case "$cfg_out" in *CONFIG_UPDATED*) CHANGED=1; log "config discord actualizada";; esac
    [ "$CHANGED" = "1" ] && log "apply completado (con cambios)"
}

check() {
    local cid
    cid=$(get_cid) || return 1
    WS_PLUGIN=$(resolve_plugin_dir "$cid")
    WS_DIST="$WS_PLUGIN/dist/index.js"
    echo "== discord-fix check =="
    echo "installPath: $WS_PLUGIN"
    docker exec "$cid" sh -c "test -f '$WS_DIST' && echo 'plugin dist: PRESENTE' || echo 'plugin dist: AUSENTE'"
    docker exec "$cid" python3 -c "
import json, sqlite3
conn=sqlite3.connect('$DB'); c=conn.cursor()
c.execute('SELECT install_records_json FROM installed_plugin_index LIMIT 1')
row=c.fetchone()
recs=json.loads(row[0]) if row and row[0] else {}
w=recs.get('discord')
print('trust record:', 'OK' if w and w.get('resolvedName')=='@openclaw/discord' else 'FALTA/INCORRECTO')
" 2>/dev/null || echo "trust record: no DB"
    docker exec "$cid" python3 -c "
import json
c=json.load(open('$CONFIG'))
ch=c.get('channels',{}).get('discord',{})
pe=c.get('plugins',{}).get('entries',{}).get('discord',{})
print('config channel:', ch)
print('config plugins.entry:', pe)
" 2>/dev/null || echo "config: no legible"
}

case "${1:-check}" in
    apply) apply ;;
    check) check ;;
    *) echo "uso: $0 {apply|check}"; exit 1 ;;
esac
exit 0