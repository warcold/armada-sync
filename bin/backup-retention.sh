#!/usr/bin/env bash
# backup-retention.sh — Aplica política de retención 3-5 copias (2026-10-29)
# Uso: backup-retention.sh [--dry-run] [--force]

set -euo pipefail

DRY_RUN=false
FORCE=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
    esac
done

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Directorios a EXCLUIR de limpieza automática (son aplicaciones, no backups)
EXCLUDE_DIRS=(
    "/var/www/html/backup/robrowser"
    "/home/warcold/.local"
    "/home/warcold/.cache"
    "/home/victoria/.local"
    "/home/victoria/.cache"
)

# Función para verificar si un directorio está excluido
is_excluded() {
    local dir="$1"
    for excluded in "${EXCLUDE_DIRS[@]}"; do
        [[ "$dir" == "$excluded" ]] && return 0
        [[ "$dir" == "$excluded"/* ]] && return 0
    done
    return 1
}

# Función genérica: mantener N archivos más recientes por patrón
retain_n_latest() {
    local dir="$1"
    local pattern="$2"
    local keep="${3:-3}"
    local dry="$4"

    [[ -d "$dir" ]] || { log "SKIP $dir: no existe"; return 0; }
    is_excluded "$dir" && { log "SKIP $dir: excluido de limpieza"; return 0; }
    cd "$dir" || return 1

    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find . -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | cut -z -d' ' -f2-)

    if [[ ${#files[@]} -le $keep ]]; then
        log "OK $dir/$pattern: ${#files[@]} archivos (≤$keep)"
        return 0
    fi

    local to_delete=("${files[@]:$keep}")
    log "CLEAN $dir/$pattern: ${#to_delete[@]} archivos a eliminar (mantener $keep)"
    for f in "${to_delete[@]}"; do
        if [[ "$dry" == "true" ]]; then
            log "  [DRY] rm $f"
        else
            rm -f "$f" && log "  rm $f"
        fi
    done
}

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== INICIO RETENCIÓN BACKUPS $(date) ==="

# === 1. WordPress .wpress exports (3 copias por sitio) ===
retain_n_latest "/home/warcold/dev/wordpress/websites/micaserogou.com/export" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/warcold/dev/wordpress/websites/magantech.com.do/export" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/victoria/dev/wordpress/websites/micaserogou.com/export" "*.wpress" 3 "$DRY_RUN" 2>/dev/null || true
retain_n_latest "/home/victoria/dev/wordpress/websites/magantech.com.do/export" "*.wpress" 3 "$DRY_RUN" 2>/dev/null || true

# 2. WordPress .wpress en Downloads (3 copias globales)
retain_n_latest "/home/warcold/Downloads" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/victoria/Downloads" "*.wpress" 3 "$DRY_RUN" 2>/dev/null || true

# 3. .zip / .wpress / .tar.gz / .iso en Downloads >30 días (eliminar)
find /home/warcold/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null || true
find /home/victoria/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null || true

# 4. ECCOQUALITA Backups (3 copias por tipo)
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Users Backups" "*.zip" 3 "$DRY_RUN"
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Webs Backups" "*.wpress" 3 "$DRY_RUN"

# 5. /var/www/html/backup (3 copias por subdirectorio, excluyendo robrowser)
for d in /var/www/html/backup/*/; do
    [[ -d "$d" ]] && retain_n_latest "$d" "*" 3 "$DRY_RUN"
done

# 6. Logs >7 días (rotación)
find /home/victoria/logs -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
find /home/warcold/logs -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
find /var/log -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true

# 7. Downloads temporales >30 días
find /home/warcold/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null || true
find /home/victoria/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null || true

# 8. ECCOQUALITA Backups (3 copias por tipo)
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Users Backups" "*.zip" 3 "$DRY_RUN"
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Webs Backups" "*.wpress" 3 "$DRY_RUN"

log "=== RETENCIÓN COMPLETADA $(date) ==="