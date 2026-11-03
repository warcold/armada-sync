#!/usr/bin/env bash
# openclaw-persist.sh
# Persistencia de /sandbox/.openclaw del contenedor del sandbox victoria-armada.
#
# El contenedor del sandbox es EFIMERO (sin volumen persistente): un docker rm -f
# resetea TODO /sandbox/.openclaw (config, identidad, plugins, credenciales,
# memoria, voz, blogwatcher). Este script evita esa perdida:
#
#   backup  : copia /sandbox/.openclaw completo al host (rsync over docker cp)
#   restore : restaura desde el backup si openclaw.json es template/ausente
#             (es decir, si el sandbox fue reconstruido desde cero)
#
# Disenado para correr en loop desde el ensure-loop (openclaw-bridge-ensure.sh)
# o como systemd timer. Idempotente y no-interactivo.
set -u

SANDBOX_NAME="victoria-armada"
BACKUP_ROOT="/home/victoria/.nemoclaw/persistent/victoria-armada"
BACKUP_DIR="$BACKUP_ROOT/openclaw-latest"
RESTORE_FLAG="$BACKUP_ROOT/.restore-needed"
MIN_VALID_SIZE=3000    # openclaw.json sano > ~3KB; template fresco ~1-2KB

log() { echo "[openclaw-persist] $(date -Is) $*"; }

cid_of() {
    docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1
}

# Sanity: openclaw.json es valido y tiene config real (channels + plugins)?
# IMPORTANTE (audit 2026-08-16): el template DE FABRICA del rebuild tambien tiene
# channels.discord + plugins.entries.discord (baked en la imagen), asi que ese
# check NO distingue un sandbox recien construido de uno configurado. El marcador
# REAL de que el config fue configurado por Victoria es 'session.identityLinks'
# (lo aplica openclaw-customize-apply.sh; la fabrica nunca lo tiene).
config_is_valid() {
    local cid="$1"
    local json
    json=$(docker exec "$cid" cat /sandbox/.openclaw/openclaw.json 2>/dev/null)
    [ -z "$json" ] && return 1
    local size=${#json}
    [ "$size" -lt "$MIN_VALID_SIZE" ] && return 1
    echo "$json" | python3 -c '
import json, sys
try:
    c = json.load(sys.stdin)
    # 1) Debe existir un canal real configurado + plugins entries
    ch = c.get("channels", {})
    pl = c.get("plugins", {}).get("entries", {})
    has_real = bool(ch.get("discord") or ch.get("whatsapp")) and bool(pl)
    if not has_real:
        sys.exit(1)
    # 2) CRITICO: debe tener el marcador de identidad de Victoria (identityLinks
    #    cross-canal). El template de fabrica tiene channels.discord pero NUNCA
    #    session.identityLinks. Sin este check, un sandbox reconstruido pasaria
    #    la validacion y el restore no se dispararia (perdida silenciosa).
    if not c.get("session", {}).get("identityLinks"):
        sys.exit(1)
    sys.exit(0)
except Exception:
    sys.exit(1)
' 2>/dev/null
}

backup() {
    local cid="$1"
    mkdir -p "$BACKUP_ROOT"
    local tmp="$BACKUP_ROOT/.openclaw-sync-$$"
    # Excluimos pesos pesados reinstalables (npm plugins, venv de voz,
    # hf-cache de modelos y binario blogwatcher Go): se recrean con scripts
    # dedicados (voice-install, rss-install), no con el backup. El resto
    # (.openclaw config+identidad+voces+DB blogwatcher) es pequeño.
    docker exec "$cid" tar czf - --warning=no-file-changed --exclude='npm' --exclude='.voice-venv' \
        --exclude='hf-cache' --exclude='.openclaw/bin/blogwatcher' \
        --exclude='.openclaw/bin/victoria-tts' --exclude='.openclaw/bin/whisper-cli' \
        -C /sandbox .openclaw > "$tmp.tgz" 2>/dev/null || { rm -f "$tmp.tgz"; return 1; }
    # ATOMICO: extraemos a un directorio temporal y lo movemos con 'mv' al
    # destino final. El backup anterior queda intacto hasta que el nuevo esté
    # completo, así un power failure/crash a mitad del backup NUNCA corrompe
    # el respaldo existente (antes: rm -rf BACKUP_DIR + extract = ventana de
    # perdida total si se cortaba la luz entre ambos pasos).
    local newdir="$BACKUP_ROOT/.openclaw-new-$$"
    rm -rf "$newdir"
    mkdir -p "$newdir"
    # --no-same-owner: no preservar owners del contenedor (root/sandbox) en el
    # host; el backup_dir debe quedar propiedad de victoria para que el script
    # pueda sobrescribirlo en el proximo ciclo.
    tar xzf "$tmp.tgz" --no-same-owner -C "$newdir" 2>/dev/null
    rm -f "$tmp.tgz"
    # BLINDAJE IDENTIDAD (audit 2026-08-17): si el sandbox fue reconstruido y el
    # ensure-loop aún no restauró la identidad (ensure_identity_files corre DESPUÉS
    # de persist.sh auto), el workspace del backup podría llevar los .md de fábrica
    # (template vacío "Fill this in…"). Eso propagaría la pérdida de identidad al
    # próximo rebuild. Nunca respaldamos un template: si el workspace tiene los
    # placeholders de fábrica, lo reemplazamos con el maestro del host.
    local ws_new="$newdir/.openclaw/workspace"
    if [ -d "$ws_new" ]; then
        for f in SOUL IDENTITY USER; do
            local master="/home/victoria/${f}-restore.md"
            [ -f "$master" ] || continue
            if grep -qE 'Fill this in|\(pick something you like\)|Learn about the person' "$ws_new/${f}.md" 2>/dev/null; then
                cp "$master" "$ws_new/${f}.md" 2>/dev/null
                log "backup: workspace/${f}.md era template; copiado maestro del host"
            fi
        done
    fi
    # Forzar owners victoria (paranoya: tar --no-same-owner normalmente hace
    # esto pero a veces algun subdir queda con owner del contenedor cuando
    # el script corrió como root via sudo/systemd; chown siempre es seguro).
    chown -R victoria:victoria "$newdir" 2>/dev/null || sudo chown -R victoria:victoria "$newdir" 2>/dev/null
    # swap atómico: eliminar el backup viejo solo cuando el nuevo está completo
    rm -rf "$BACKUP_DIR"
    mv "$newdir" "$BACKUP_DIR"
    log "backup completado ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1))"
    # marca de tiempo del backup
    touch "$BACKUP_ROOT/last-backup"
}

restore() {
    local cid="$1"
    [ -d "$BACKUP_DIR" ] || { log "no hay backup disponible; no restauro"; return 1; }
    # respaldo previo al restore por seguridad
    docker exec "$cid" sh -c 'cp -r /sandbox/.openclaw /sandbox/.openclaw.pre-restore 2>/dev/null'
    # empaquetar en el host y extraer dentro del contenedor
    local tgz="$BACKUP_ROOT/.restore-$$.tgz"
    tar czf "$tgz" -C "$BACKUP_DIR" . 2>/dev/null || { rm -f "$tgz"; return 1; }
    docker cp "$tgz" "$cid":/tmp/.openclaw-restore.tgz >/dev/null 2>&1
    rm -f "$tgz"
    # --no-same-owner: los owners de host (victoria) no aplican dentro del
    # contenedor; el chown de abajo fija los owners reales.
    docker exec "$cid" sh -c 'tar xzf /tmp/.openclaw-restore.tgz --no-same-owner -C /sandbox 2>/dev/null; rm -f /tmp/.openclaw-restore.tgz' || return 1
    # Ownership dentro del sandbox: la config y el estado son del usuario
    # sandbox (998), que es quien corre el gateway. EXCEPCION: extensions/
    # (p.ej. el plugin nemoclaw) debe quedar root:root, que es lo que espera el
    # cargador de plugins; un chown a sandbox lo bloquearia con
    # "suspicious ownership".
    docker exec -u root "$cid" sh -c 'chown -R sandbox:sandbox /sandbox/.openclaw && chown -R root:root /sandbox/.openclaw/extensions && chmod -R a+rX /sandbox/.openclaw/extensions && chmod 750 /sandbox/.openclaw/extensions /sandbox/.openclaw/extensions/nemoclaw 2>/dev/null' 2>/dev/null
    log "restore completado desde $BACKUP_DIR"
}

# --- main ---
cmd="${1:-auto}"
case "$cmd" in
    backup)
        cid=$(cid_of) && [ -n "$cid" ] && backup "$cid" || { log "backup: sandbox no activo"; exit 1; }
        ;;
    restore)
        cid=$(cid_of) && [ -n "$cid" ] && restore "$cid" || { log "restore: sandbox no activo"; exit 1; }
        ;;
    auto)
        cid=$(cid_of)
        [ -z "$cid" ] && { log "auto: sandbox no levantado"; exit 0; }
        if config_is_valid "$cid"; then
            # config sana -> solo respaldar (limitado a 1 vez por hora para no saturar IO)
            if [ ! -f "$BACKUP_ROOT/last-backup" ] || [ "$(find "$BACKUP_ROOT/last-backup" -mmin +60 2>/dev/null)" ]; then
                backup "$cid"
            else
                exit 0
            fi
        else
            # config rota/template -> restaurar
            log "auto: config invalida o template; restaurado desde backup"
            restore "$cid"
            rm -f "$RESTORE_FLAG"
            # INDICADOR para el ensure-loop: tras un restore el gateway debe
            # reiniciarse para cargar channels/plugins (hot reload no aplica a
            # channels.whatsapp -> "config reload requires gateway restart").
            # Escribimos un flag que openclaw-bridge-ensure.sh lee y borra.
            touch "$BACKUP_ROOT/.gateway-restart-needed"
        fi
        ;;
    status)
        cid=$(cid_of)
        if [ -n "$cid" ]; then
            if config_is_valid "$cid"; then
                echo "sandbox: config OK"
            else
                echo "sandbox: config INVALIDA/template -> restore pendiente"
            fi
        else
            echo "sandbox: no activo"
        fi
        if [ -d "$BACKUP_DIR" ]; then
            echo "backup: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) en $BACKUP_DIR"
        else
            echo "backup: NO EXISTE"
        fi
        ;;
    *)
        echo "uso: openclaw-persist.sh {backup|restore|auto|status}" >&2
        exit 2
        ;;
esac