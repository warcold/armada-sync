#!/usr/bin/env bash
# changelog-sync-kalimete.sh — Sync bidireccional CHANGELOG.md Kalimete ↔ GitHub hub
# Uso: changelog-sync-kalimete.sh [push|pull|sync|status]

set -euo pipefail

LOCAL_CHANGELOG="$HOME/armada-sync/CHANGELOG.md"
REPO_DIR="$HOME/armada-sync"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

push_local() {
    log "Push local → GitHub..."
    cd "$REPO_DIR" && git add CHANGELOG.md && \
    git commit -m "changelog: sync from Kalimete $(date -u +'%Y-%m-%dT%H:%M:%SZ')" && \
    git push origin master && \
    log "Push OK" || log "Push FALLÓ"
}

pull_remote() {
    log "Pull GitHub → local..."
    cd "$REPO_DIR" && git pull origin master && log "Pull OK" || log "Pull FALLÓ"
}

sync_both() {
    log "Sync bidireccional..."
    pull_remote
    push_local
}

status_check() {
    log "Estado local: $(wc -l < "$LOCAL_CHANGELOG") líneas, mtime: $(stat -c %y "$LOCAL_CHANGELOG" 2>/dev/null)"
    log "Git status: $(cd "$REPO_DIR" && git status --short)"
}

case "${1:-sync}" in
    push) push_local ;;
    pull) pull_remote ;;
    sync) sync_both ;;
    status) status_check ;;
    *) echo "Uso: $0 [push|pull|sync|status]"; exit 1 ;;
esac
