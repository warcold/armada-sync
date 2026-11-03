#!/usr/bin/env bash
# openclaw-rss-install.sh
#
# Instala/repara el servicio blogwatcher (RSS/Atom feed aggregation) en el
# sandbox victoria-armada. Pensado para ser llamado por el ensure-loop
# `openclaw-bridge-ensure.sh` tras openclaw-persist.sh + openclaw-voice-install.sh.
#
# El binario blogwatcher (Go, CGO_ENABLED=0, arm64 static, v0.0.3) es.efímero en
# /sandbox/.openclaw/bin/ y se pierde en stop/start del sandbox. Aquí lo
# respaldamos en el host (~/.victoria-custom/bin/) y lo volvemos a copiar si
# falta (igual que voice-install.sh hace para el stack de voz).
#
# La DB SQLite (/sandbox/.openclaw/blogwatcher/blogwatcher.db) SÍ se respalda
# con openclaw-persist.sh (vive dentro de /sandbox/.openclaw/, sandbox-owned).
#
# El binario Go se construye una sola vez (ver ~linea 1 commit 2026-08-16):
#   git clone --depth 1 --branch v0.0.3 https://github.com/Hyaxia/blogwatcher.git
#   CGO_ENABLED=0 go build -ldflags="-s -w" -o ~/.victoria-custom/bin/blogwatcher ./cmd/blogwatcher
#
# Si en el futuro se quiere actualizar (v0.0.4+), reconstruir y reemplazar
# el binario canónico en el host; el ensure-loop lo propagará.
#
# Uso:
#   openclaw-rss-install.sh ensure   # idempotente (lo llama el ensure-loop)
#   openclaw-rss-install.sh verify   # diagnostica sin tocar
set -u

HOST_BIN="/home/victoria/.victoria-custom/bin/blogwatcher"
SANDBOX_BIN="/sandbox/.openclaw/bin/blogwatcher"
DB_DIR="/sandbox/.openclaw/blogwatcher"
DB_FILE="$DB_DIR/blogwatcher.db"
BLOGWATCHER_DB_ENV="BLOGWATCHER_DB=$DB_FILE"
SANDBOX_PREFIX="victoria-armada"
LOG_PREFIX="[openclaw-rss-install]"

log() { echo "$LOG_PREFIX $(date -Is) $*"; }

resolve_cid() {
    docker ps --filter "name=$SANDBOX_PREFIX" --format '{{.ID}}' | head -1
}

ensure() {
    [ -f "$HOST_BIN" ] || { log "ensure: binario canónico del host ausente ($HOST_BIN); build pendiente"; return 1; }
    local cid
    cid=$(resolve_cid)
    [ -z "$cid" ] && { log "ensure: sandbox no activo; reintento"; return 0; }

    # 1. Verificar si el binario YA está en el sandbox y es ejecutable
    local need_copy=0
    docker exec -u root "$cid" sh -c '[ -x '"$SANDBOX_BIN"' ]' 2>/dev/null || need_copy=1
    if [ "$need_copy" = "1" ]; then
        log "ensure: binario ausente en sandbox; copiando desde host"
        # Asegurar dir bin/ en sandbox
        docker exec -u root "$cid" sh -c 'mkdir -p /sandbox/.openclaw/bin && chown sandbox:sandbox /sandbox/.openclaw/bin && chmod 775 /sandbox/.openclaw/bin' 2>/dev/null
        docker cp "$HOST_BIN" "$cid:$SANDBOX_BIN" 2>/dev/null
        docker exec -u root "$cid" sh -c 'chown sandbox:sandbox '"$SANDBOX_BIN"' && chmod 755 '"$SANDBOX_BIN" 2>/dev/null
        local ok
        ok=$(docker exec -u sandbox "$cid" sh -c '[ -x '"$SANDBOX_BIN"' ] && echo OK' 2>/dev/null)
        [ "$ok" = "OK" ] && log "ensure: binario instalado ($(stat -c %s "$HOST_BIN") bytes)" || log "ensure: ERROR copiando binario"
    elif [ "${DEBUG:-0}" = "1" ]; then
        log "ensure: binario ya presente en sandbox (skip)"
    fi

    # 2. Asegurar dir DB existe + sandbox-owned (persists DB though stops/starts)
    docker exec -u sandbox "$cid" sh -c "mkdir -p $DB_DIR 2>/dev/null" 2>/dev/null

    # 3. Validar que el binario responde (smoke test)
    local ver
    ver=$(docker exec -u sandbox -e "$BLOGWATCHER_DB_ENV" -w /sandbox "$cid" "$SANDBOX_BIN" blogs 2>&1 | head -1)
    case "$ver" in
        "Tracked"*) ;;
        "") log "ensure: binario sin respuesta (posible arquitectura/lib incompatible)" ;;
        *) [ "${DEBUG:-0}" = "1" ] && log "ensure: smoke test OK ($ver)" ;;
    esac

    return 0
}

verify() {
    [ -f "$HOST_BIN" ] || { log "verify: binario canónico AUSENTE en $HOST_BIN"; return 1; }
    local cid
    cid=$(resolve_cid)
    [ -z "$cid" ] && { log "verify: sandbox no activo"; return 0; }
    docker exec -u root "$cid" sh -c 'ls -la '"$SANDBOX_BIN"' 2>/dev/null && file '"$SANDBOX_BIN"' 2>/dev/null' || log "verify: binario ausente en sandbox"
    docker exec -u root "$cid" sh -c 'ls -la '"$DB_DIR"' 2>/dev/null' || log "verify: dir DB ausente"
    echo
    log "verify: blogs tracked en la DB:"
    docker exec -u sandbox -e "$BLOGWATCHER_DB_ENV" -w /sandbox "$cid" "$SANDBOX_BIN" blogs 2>&1 | head -20
}

cmd="${1:-ensure}"
case "$cmd" in
    ensure) ensure ;;
    verify) verify ;;
    *) echo "uso: openclaw-rss-install.sh {ensure|verify}" >&2; exit 2 ;;
esac
