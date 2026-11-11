#!/usr/bin/env bash
# changelog-sync-victoria.sh — Sync bidireccional CHANGELOG.md Victoria ↔ GitHub hub
# Uso: changelog-sync-victoria.sh [push|pull|sync|status]

set -euo pipefail

HUB_REPO="~/armada-sync"  # en kalimete, accesible via SSH
LOCAL_CHANGELOG="/home/victoria/CHANGELOG.md"
REMOTE_CHANGELOG="~/armada-sync/CHANGELOG.md"
SSH_CMD="ssh -i ~/.ssh/id_victoria -p 1111 warcold@kalimete.local"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

push_local() {
    log "Push local → GitHub hub..."
    scp -i ~/.ssh/id_victoria -P 1111 "$LOCAL_CHANGELOG" warcold@kalimete.local:"$REMOTE_CHANGELOG" && \
    $SSH_CMD "cd ~/armada-sync && git add CHANGELOG.md && git commit -m 'changelog: sync from Victoria $(date -u +%Y-%m-%dT%H:%M:%SZ)' && bash ~/armada-sync/sync.sh" && \
    log "Push OK" || log "Push FALLÓ"
}

pull_remote() {
    log "Pull GitHub hub → local..."
    $SSH_CMD "cd ~/armada-sync && git pull origin master" && \
    scp -i ~/.ssh/id_victoria -P 1111 warcold@kalimete.local:"$REMOTE_CHANGELOG" "$LOCAL_CHANGELOG" && \
    log "Pull OK" || log "Pull FALLÓ"
}

sync_both() {
    # FIX 2026-11-11: sync era pull+push y el pull era DESTRUCTIVO (scp remoto
    # -> local pisaba el master con el espejo viejo) — destruyó la entrada del
    # 2026-11-11 (paquete de mejoras) escrita entre corridas del cron */15.
    # Es exactamente el modo de fallo que motivó armada-sync ("pérdida del
    # historial CHANGELOG por overwrite"). El remoto es un ESPEJO puro de
    # Victoria (Kalimete documenta lo suyo en su propio repo, contrato
    # 2026-09-30) → el local es el MASTER y sync = push-only. El pull queda
    # disponible SOLO manual (pull) para restauración explícita.
    log "Sync = push-only (local es master; pull manual destruiría entradas nuevas)"
    push_local
}

status_check() {
    log "Estado local: $(wc -l < "$LOCAL_CHANGELOG") líneas, mtime: $(stat -c %y "$LOCAL_CHANGELOG")"
    $SSH_CMD "wc -l < ~/armada-sync/CHANGELOG.md && stat -c %y ~/armada-sync/CHANGELOG.md" 2>/dev/null | while read line; do log "Remoto: $line"; done
}

case "${1:-sync}" in
    push) push_local ;;
    pull) pull_remote ;;
    sync) sync_both ;;
    status) status_check ;;
    *) echo "Uso: $0 [push|pull|sync|status]"; exit 1 ;;
esac
