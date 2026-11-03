#!/usr/bin/env bash
# openclaw-whatsapp-fix.sh
# Repara/mantiene el plugin WhatsApp del sandbox OpenClaw de Victoria.
#
# PROPOSITO:
#   WhatsApp vive en npm/projects/openclaw-whatsapp-<hash>/node_modules/@openclaw/whatsapp
#   (layout del runtime 2026.7.1 — fix 2026-09-19: YA NO en extensions/).
#   Para que `openKeyedStore` (state keys) funcione, el plugin debe resolverse como
#   trustedOfficialInstall=true. Ese flag NO se lee de la DB directamente: lo calcula
#   `isTrustedOfficialPluginInstall()` en runtime, que exige:
#     1. candidate.origin === "global" (o "config")
#     2. matchesInstalledPluginRecord() -> el install record debe apuntar a la ruta real
#     3. packageName "whatsapp" con catalog entry oficial @openclaw/whatsapp
#     4. installRecord.source === "npm" y resolvedName/spec/resolvedSpec = "@openclaw/whatsapp"
#
#   `openclaw plugins install <tgz-local>` NO sirve: crea el esqueleto del proyecto
#   pero aborta al bajar dependencias (403 policy_denied: el egress del sandbox
#   bloquea registry.npmjs.org) -> dist/index.js nunca aparece. Por eso se EXTRAE
#   el tgz directo al installPath (offline, trae node_modules empaquetado).
#   El installPath se resuelve por glob (el sufijo hash es estable, pero el glob
#   sobrevive a cambios de version).
#
#   Un install via `openclaw plugins install @openclaw/whatsapp` desde npm FALLA (403
#   policy_denied) por la misma razon. Todo el flujo aqui es offline.
#
# USO:
#   openclaw-whatsapp-fix.sh check   # estado actual (idempotente)
#   openclaw-whatsapp-fix.sh apply   # instala/restaura + escribe trust record (idempotente)
#
# Se engancha al ensure-loop (openclaw-bridge-ensure.sh) tras ensure_npm_plugins.

set -uo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-victoria-armada}"
TGZ_SRC="/home/victoria/.victoria-custom/plugins/openclaw-whatsapp-2026.7.1.tgz"
# Layout runtime 2026.7.1 (ver PROPOSITO arriba). Se resuelve dinamicamente.
PLUGIN_SHORT="whatsapp"
PLUGIN_GLOB="/sandbox/.openclaw/npm/projects/openclaw-whatsapp-*"
PLUGIN_SUB="node_modules/@openclaw/whatsapp"
PLUGIN_KNOWN="/sandbox/.openclaw/npm/projects/openclaw-whatsapp-290d7f7427/node_modules/@openclaw/whatsapp"
WS_PLUGIN=""
WS_DIST=""
DB="/sandbox/.openclaw/state/openclaw.sqlite"
CONFIG="/sandbox/.openclaw/openclaw.json"
# El gateway corre como 'sandbox' (uid 998); todo debe quedar sandbox:owned salvo
# extensions/nemoclaw (root:root) y extensions/ (dir padre 750 sandbox).

log() { echo "[whatsapp-fix] $*"; }

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

# Extrae el plugin desde el tgz local directo al installPath (offline, el tgz
# trae node_modules empaquetado — `plugins install` aborta por 403 npm).
install_from_tgz() {
    local cid="$1" dest="$2"
    [ -f "$TGZ_SRC" ] || { log "FATAL: tgz no existe en host: $TGZ_SRC"; return 1; }
    [ -n "$dest" ] || { log "FATAL: no se resolvio installPath"; return 1; }
    docker cp "$TGZ_SRC" "$cid":/tmp/openclaw-whatsapp.tgz >/dev/null 2>&1
    log "extrayendo whatsapp directo a $dest (como sandbox, offline, sin egress npm)"
    docker exec -u sandbox -e HOME=/sandbox "$cid" sh -c \
        "tar xzf /tmp/openclaw-whatsapp.tgz --strip-components=1 -C '$dest' 2>&1" \
        | tail -2
    docker exec "$cid" sh -c "test -f '$dest/dist/index.js' && echo INSTALLED_OK || echo INSTALL_FAIL" 2>/dev/null
    return 0
}

# Escribe el install record que hace que isTrustedOfficialPluginInstall() devuelva true.
# No toca un record bueno: si ya apunta a un path real con dist, se conserva
# (origen: records restaurados Sep-11, verificados funcionando por meses).
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
cur = records.get("whatsapp") or {}
cur_path = cur.get("installPath", "")
if cur_path and os.path.exists(os.path.join(cur_path, "dist", "index.js")):
    print("TRUST_RECORD_OK"); raise SystemExit
h = hashlib.sha256()
h.update(open(pkg, "rb").read())
shasum = h.hexdigest()
records["whatsapp"] = {
    "source": "npm",
    "spec": "@openclaw/whatsapp",
    "installPath": dest,
    "version": "2026.7.1",
    "resolvedName": "@openclaw/whatsapp",
    "resolvedVersion": "2026.7.1",
    "resolvedSpec": "@openclaw/whatsapp@2026.7.1",
    "integrity": f"sha512-{shasum[:43]}",
    "shasum": shasum,
    "resolvedAt": "2026-08-17T02:30:00.000Z",
    "installedAt": "2026-08-17T02:30:00.000Z",
    "origin": "global",
}
c.execute("UPDATE installed_plugin_index SET install_records_json = ?, refresh_reason = ? WHERE index_key = ?",
          (json.dumps(records), "whatsapp-fix-trust", "installed-plugin-index"))
conn.commit()
print("TRUST_RECORD_WRITTEN")
conn.close()
PYEOF
}

# Asegura que openclaw.json tenga el canal + plugins.entries whatsapp habilitados.
ensure_config() {
    local cid="$1"
    docker exec -u sandbox -e HOME=/sandbox "$cid" python3 - << 'PYEOF' 2>/dev/null
import json, os
p = "/sandbox/.openclaw/openclaw.json"
c = json.load(open(p))
dirty = False
ch = c.setdefault("channels", {})
if ch.get("whatsapp", {}).get("enabled") is not True:
    ch["whatsapp"] = {"enabled": True}; dirty = True
# dmPolicy "open" + allowFrom ["*"] (diseno vigente 2026-09-01, restaurado
# 2026-09-15): los DMs llegan al agente; a desconocidos se les responde SOLO
# el invite al hub (identidad USER/SOUL + tools.toolsBySender global les niega
# las 15 tools). NO volver a pairing: rompe el flujo de invitacion.
w = ch.get("whatsapp", {})
if w.get("dmPolicy") != "open":
    w["dmPolicy"] = "open"; dirty = True
if w.get("allowFrom") != ["*"]:
    w["allowFrom"] = ["*"]; dirty = True
if dirty:
    ch["whatsapp"] = w
pl = c.setdefault("plugins", {}).setdefault("entries", {})
if pl.get("whatsapp", {}).get("enabled") is not True:
    pl["whatsapp"] = {"enabled": True}; dirty = True
if dirty:
    json.dump(c, open(p, "w"), indent=2)
    print("CONFIG_UPDATED")
else:
    print("CONFIG_OK")
PYEOF
    # fijar ownership de config a sandbox (el gateway la lee como sandbox)
    docker exec -u root "$cid" chown sandbox:sandbox "$CONFIG" 2>/dev/null
    docker exec -u root "$cid" chmod 660 "$CONFIG" 2>/dev/null
}

# Parche de media upload (2026-08-19): Baileys uploadWithNodeHttp pasa el fetchAgent
# (undici ProxyAgent del SDK) como `agent` de https.request -> Node lanza
# ERR_INVALID_ARG_TYPE "options.agent" -> "Media upload failed on all hosts" en <30ms
# sin tocar red. Con fetchAgent=undefined, https.request usa el agente default de Node
# que con NODE_USE_ENV_PROXY=1 hace CONNECT tunnel via el proxy L7 (funciona).
# En entornos sin proxy el fetchAgent ya era undefined -> este parche no cambia nada ahi.
patch_media_upload() {
    local cid="$1"
    docker exec -u root "$cid" sh -c "
        F='$WS_PLUGIN/dist/session-DriaHt7V.js'
        [ -f \"\$F\" ] || { echo '[whatsapp-fix] session-DriaHt7V.js no existe'; exit 0; }
        if grep -q 'PATCHED 2026-08-19' \"\$F\"; then
            : # ya aplicado: silencioso (estado sano no loguea)
        else
            cp \"\$F\" \"\$F.bak-pre-media-patch\" 2>/dev/null
            sed -i 's/const fetchAgent = await resolveEnvFetchDispatcher(sessionLogger, agent);/const fetchAgent = undefined; \/\/ PATCHED 2026-08-19: undici ProxyAgent breaks Baileys uploadWithNodeHttp (ERR_INVALID_ARG_TYPE on https.request agent)/' \"\$F\"
            if grep -q 'PATCHED 2026-08-19' \"\$F\"; then
                echo '[whatsapp-fix] parche media upload aplicado'
            else
                echo '[whatsapp-fix] ERROR: patrón no encontrado en session-DriaHt7V.js'
            fi
        fi
    " 2>/dev/null
}

# Fix de ownership: whatsapp -> sandbox:sandbox (alineado con discord y con
# ensure_ownership_fix del bridge-loop, que impone sandbox en TODO .openclaw
# cada 15s porque el gateway rechaza arrancar con archivos no-sandbox).
# Historial: 2026-08-16 se usó root:root 2775 por el trust check, pero la
# evidencia manda — Discord lleva semanas en sandbox funcionando, y el propio
# loop dejaba whatsapp en sandbox el 99% del tiempo con el canal healthy.
# El trust check lee el install record de la DB, no el owner del FS.
# nemoclaw NO se toca aquí (lo gestiona persist.sh restore + ensure_ownership_fix).
# CHANGED=1 cuando apply modifica algo (para loguear solo cambios reales;
# el ensure-loop corre apply cada 15s y el estado sano debe ser silencioso).
fix_ownership() {
    local cid="$1"
    local cur
    cur=$(docker exec -u root "$cid" sh -c "stat -c '%U:%G' '$WS_PLUGIN' '$WS_PLUGIN/dist/index.js' 2>/dev/null" 2>/dev/null)
    if [ "$cur" = "sandbox:sandbox
sandbox:sandbox" ]; then
        return 0
    fi
    docker exec -u root "$cid" sh -c "
        [ -d '$WS_PLUGIN' ] && chown -R sandbox:sandbox '$WS_PLUGIN'
        [ -d '$WS_PLUGIN' ] && chmod -R u+rwX,go+rX '$WS_PLUGIN'
    " 2>/dev/null
    CHANGED=1
    log "ownership fixeado (whatsapp=sandbox, alineado discord + ensure_ownership_fix)"
}

# Versión del plugin instalado (de su package.json). Vacío si no se puede leer.
# Decide el modo de apply: 2026.7.x = mundo tgz (parche+trust manual);
# cualquier otra (nativa npm >= 2026.9) = records propios, sin trust patch.
plugin_version() {
    local cid="$1"
    docker exec "$cid" sh -c "grep -o '\"version\": *\"[^\"]*\"' '$WS_PLUGIN/package.json' 2>/dev/null | head -1" 2>/dev/null \
        | sed 's/.*: *"//;s/"$//' | tr -d '\r'
}

# Parche media-upload para plugins NATIVOS (>= 2026.9): busca el patrón del bug
# Baileys (fetchAgent undici pasado como agent a https.request) en TODO el dist,
# no solo en session-DriaHt7V.js (hash de build 2026.7.1). Si el patrón no
# existe en ningún archivo = upstream lo arregló (fix nativo confirmado, no-op).
patch_media_upload_native() {
    local cid="$1"
    docker exec -u root "$cid" sh -c "
        for F in '$WS_PLUGIN'/dist/*.js; do
            [ -f \"\$F\" ] || continue
            grep -q 'PATCHED 2026-08-19' \"\$F\" && continue
            if grep -q 'const fetchAgent = await resolveEnvFetchDispatcher(sessionLogger, agent);' \"\$F\"; then
                cp \"\$F\" \"\$F.bak-pre-media-patch\" 2>/dev/null
                sed -i 's/const fetchAgent = await resolveEnvFetchDispatcher(sessionLogger, agent);/const fetchAgent = undefined; \/\/ PATCHED 2026-08-19: undici ProxyAgent breaks Baileys uploadWithNodeHttp (ERR_INVALID_ARG_TYPE)/' \"\$F\"
                grep -q 'PATCHED 2026-08-19' \"\$F\" && echo \"[whatsapp-fix] parche media upload aplicado (native): \$(basename \"\$F\")\"
            fi
        done
    " 2>/dev/null
}

apply() {
    local cid
    cid=$(get_cid) || return 1
    CHANGED=0
    WS_PLUGIN=$(resolve_plugin_dir "$cid")
    WS_DIST="$WS_PLUGIN/dist/index.js"
    local present patch_out trust_out cfg_out pv
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
            # Mundo tgz (histórico): parche media-upload en el archivo de build
            # 2026.7.1 + trust record manual (el tgz no escribe records propios).
            patch_out=$(patch_media_upload "$cid")
            [ -n "$patch_out" ] && { echo "$patch_out"; CHANGED=1; }
            trust_out=$(write_trust_record "$cid" "$WS_PLUGIN")
            case "$trust_out" in *NO_PLUGIN*) log "trust record: plugin ausente tras install (revisar)";; esac
            ;;
        *)
            # NATIVO (npm >= 2026.9, install propio del runtime): records
            # propios = trusted de fábrica — NUNCA sobrescribir con el record
            # 2026.7.1 (corrompería el trust del install nativo). Solo portar
            # el parche media-upload SI el bug sigue presente en el dist nuevo.
            patch_out=$(patch_media_upload_native "$cid")
            [ -n "$patch_out" ] && { echo "$patch_out"; CHANGED=1; }
            ;;
    esac
    cfg_out=$(ensure_config "$cid" 2>/dev/null | tr -d '\r' | tail -1)
    case "$cfg_out" in *CONFIG_UPDATED*) CHANGED=1; log "config whatsapp actualizada";; esac
    [ "$CHANGED" = "1" ] && log "apply completado (con cambios)"
}

check() {
    local cid
    cid=$(get_cid) || return 1
    WS_PLUGIN=$(resolve_plugin_dir "$cid")
    WS_DIST="$WS_PLUGIN/dist/index.js"
    echo "== whatsapp-fix check =="
    echo "installPath: $WS_PLUGIN"
    docker exec "$cid" sh -c "test -f '$WS_DIST' && echo 'plugin dist: PRESENTE' || echo 'plugin dist: AUSENTE'"
    docker exec "$cid" sh -c "grep -q 'PATCHED 2026-08-19' '$WS_PLUGIN/dist/session-DriaHt7V.js' && echo 'media upload patch: APLICADO' || echo 'media upload patch: NO APLICADO'"
    docker exec "$cid" python3 -c "
import json, sqlite3
conn=sqlite3.connect('$DB'); c=conn.cursor()
c.execute('SELECT install_records_json FROM installed_plugin_index LIMIT 1')
row=c.fetchone()
recs=json.loads(row[0]) if row and row[0] else {}
w=recs.get('whatsapp')
print('trust record:', 'OK' if w and w.get('resolvedName')=='@openclaw/whatsapp' else 'FALTA/INCORRECTO')
" 2>/dev/null || echo "trust record: no DB"
    docker exec "$cid" python3 -c "
import json
c=json.load(open('$CONFIG'))
ch=c.get('channels',{}).get('whatsapp',{})
pe=c.get('plugins',{}).get('entries',{}).get('whatsapp',{})
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
