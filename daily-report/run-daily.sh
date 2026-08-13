#!/bin/bash
# ============================================================
# Reporte diario del ecosistema Armada → Discord Piso 14
# Programa: systemd timer daily-report.timer (19:45)
# ============================================================
set -euo pipefail

DIR="$HOME/armada-sync/daily-report"
LOG="$HOME/.config/opencode/daily-report.log"
ENV_FILE="$HOME/.config/opencode/daily-report.env"

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  python3 "$DIR/report.py" --hours 24
  echo "=== fin ==="
  echo ""
} >> "$LOG" 2>&1