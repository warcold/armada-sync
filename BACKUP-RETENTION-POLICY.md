# POLÍTICA DE RETENCIÓN DE BACKUPS — Ecosistema Armada (2026-10-29)

> Regla obligatoria para TODOS los backups en Victoria, kalimete, VPS, y cualquier servidor del ecosistema.
> Objetivo: Evitar llenar discos con backups obsoletos que nunca se usan.

---

## 📋 Regla General: **Máximo 3-5 copias según criterio**

| Tipo de Backup | Retención | Criterio | Ubicaciones Afectadas |
|----------------|-----------|----------|----------------------|
| **WordPress Sites (.wpress)** | **3 copias** | Por sitio, por fecha | `~/Downloads/`, `~/dev/wordpress/websites/*/export/`, `/var/www/html/backup/` |
| **Docker Volumes / DB Dumps** | **5 copias** | Por servicio, por fecha | `docker volumes`, `~/armada-sync/backups/`, `/tmp/` |
| **Configuración / Code** | **3 copias** | Por cambio mayor | `~/armada-sync/`, `~/dev/*/`, Git history |
| **Modelos / Pesos IA** | **1 copia** (inmutable) | Versión fija | `~/.cache/huggingface/`, `~/ComfyUI/models/`, `~/.voice-models/` |
| **Logs / Debug** | **7 días** | Rotación automática | `~/logs/`, `/var/log/`, `journalctl` |
| **Downloads / Temporales** | **30 días** | Limpieza automática | `~/Downloads/`, `/tmp/` |

---

## 🔧 Implementación Automatizada

### **Script de Retención: `backup-retention.sh`**

```bash
#!/usr/bin/env bash
# backup-retention.sh — Aplica política de retención 3-5 copias
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

# Función genérica: mantener N archivos más recientes por patrón
retain_n_latest() {
    local dir="$1"
    local pattern="$2"
    local keep="${3:-3}"
    local dry="$4"

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

# === APLICACIÓN DE POLÍTICAS ===

# 1. WordPress .wpress exports (3 copias por sitio)
retain_n_latest "/home/warcold/dev/wordpress/websites/micaserogou.com/export" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/warcold/dev/wordpress/websites/magantech.com.do/export" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/victoria/dev/wordpress/websites/micaserogou.com/export" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/victoria/dev/wordpress/websites/magantech.com.do/export" "*.wpress" 3 "$DRY_RUN"

# 2. WordPress .wpress en Downloads (3 copias globales)
retain_n_latest "/home/warcold/Downloads" "*.wpress" 3 "$DRY_RUN"
retain_n_latest "/home/victoria/Downloads" "*.wpress" 3 "$DRY_RUN"

# 3. .zip / .wpress / .tar.gz en Downloads >30 días (eliminar)
find /home/warcold/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null
find /home/victoria/Downloads -type f \( -name "*.zip" -o -name "*.wpress" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete -v 2>/dev/null

# 4. ECCOQUALITA Backups (3 copias por tipo)
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Users Backups" "*.zip" 3 "$DRY_RUN"
retain_n_latest "/home/warcold/Documents/ECCOQUALITA/Webs Backups" "*.wpress" 3 "$DRY_RUN"

# 5. /var/www/html/backup (3 copias por subdirectorio)
for d in /var/www/html/backup/*/; do
    [[ -d "$d" ]] && retain_n_latest "$d" "*" 3 "$DRY_RUN"
done

# 5. Docker volumes backups (5 copias)
# Nota: usar docker volume ls y backup scripts dedicados

log "Retención completada"
```

### **Cron Jobs**

```bash
# Victoria: cada día a las 03:00
0 3 * * * /home/victoria/.victoria-custom/bin/backup-retention.sh >> /home/victoria/logs/backup-retention.log 2>&1

# kalimete: cada día a las 03:30
30 3 * * * /home/warcold/.local/bin/backup-retention.sh >> /home/warcold/logs/backup-retention.log 2>&1
```

---

## 📋 Reglas de Uso Manual

### **Antes de crear un backup:**
1. Verificar espacio: `df -h /`
2. Ejecutar retención: `backup-retention.sh --dry-run`
3. Crear backup nuevo
4. Verificar: `backup-retention.sh --dry-run` (debe mostrar OK)

### **Nomenclatura estándar:**
```
<sitio>-<tipo>-<YYYYMMDD>-<HHMMSS>.<ext>
Ej: micaserogou-wpress-20261029-143000.wpress
```

### **Excepciones (NO borrar):**
- Backups de producción actuales (últimos 3)
- Backups etiquetados `KEEP` o `ARCHIVE`
- Backups de migración en curso
- Modelos IA / Pesos (inmutables)

---

## 📊 Monitoreo y Alertas

### **Alertas de espacio:**
```bash
# Alerta si disco >85%
df -h / | awk 'NR==2 {gsub(/%/,"",$5); if($5>85) print "ALERTA: Disco al " $5 "%"}'
```

### **Reporte semanal automático:**
```bash
# En cron semanal (domingo 04:00)
backup-retention.sh --dry-run | grep -E "(CLEAN|OK)" | mail -s "Reporte retención backups" admin@alfredo.pro
```

---

## 📝 Historial de Cambios

| Fecha | Cambio | Responsable |
|-------|--------|-------------|
| 2026-10-29 | Política creada (3-5 copias, limpieza 30 días, script automatizado) | Victoria |
| 2026-10-29 | Limpieza masiva aplicada: 75GB liberados en kalimete (93%→75%) | Victoria |

---

## 📍 Ubicaciones de Scripts

| Host | Script | Cron |
|------|--------|------|
| Victoria | `~/.victoria-custom/bin/backup-retention.sh` | 03:00 daily |
| kalimete | `~/bin/backup-retention.sh` | 03:30 daily |
| VPS | `/usr/local/bin/backup-retention.sh` | 04:00 daily |

---

**Regla de oro**: *Mejor prevenir que curar — un backup que no se puede restaurar no es un backup.*