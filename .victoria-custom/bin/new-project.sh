#!/usr/bin/env bash
# new-project.sh — Andamiaje de proyecto eficiente (2026-09-30).
#
# Cada directorio NUEVO de trabajo (no-temporal) nace con guía para agentes:
#   <destino>/<nombre>/AGENTS.md   (ledger desde la plantilla canónica)
#   <destino>/<nombre>/scripts/    (scripts propios reutilizables)
#   <destino>/<nombre>/README.md   (qué es + estructura)
#
# Uso:
#   new-project.sh <nombre> [destino]
#   Ej: new-project.sh mi-bot                  (va a ~/Documents/mi-bot)
#       new-project.sh etl-crypto ~/dev
#
# La plantilla vive en ~/.victoria-custom/templates/AGENTS-project-template.md.
# Al terminar cada sesión: actualizar el AGENTS.md del proyecto (regla global).
# Si el proyecto amerita subagente propio (>1 sesión + delegación frecuente):
# crearlo a mano en ~/.config/opencode/agent(s)/ con name+description+mode.
set -u
NAME="${1:-}"
DEST="${2:-$HOME/Documents}"
[ -z "$NAME" ] && { echo "Uso: new-project.sh <nombre> [destino]"; exit 1; }
PROJ="$DEST/$NAME"
[ -e "$PROJ" ] && { echo "Ya existe: $PROJ (no duplico)"; exit 1; }
TEMPLATE="$HOME/.victoria-custom/templates/AGENTS-project-template.md"
mkdir -p "$PROJ/scripts"
if [ -f "$TEMPLATE" ]; then
  sed "s/<nombre del proyecto>/$NAME/" "$TEMPLATE" > "$PROJ/AGENTS.md"
else
  printf '# AGENTS.md — %s\n\n> Ledger del proyecto. Actualizar al terminar cada sesión.\n\n## Qué es\n<!-- completar -->\n\n## Mapa\n- `scripts/` — scripts propios\n\n## Cómo correr\n<!-- comandos verificados -->\n\n## Decisiones\n\n## Pendientes\n\n## Relación con el stack\n- Ninguna — proyecto aislado.\n' "$NAME" > "$PROJ/AGENTS.md"
fi
cat > "$PROJ/README.md" <<EOF
# $NAME

> Creado con new-project.sh. Guía de agentes: ver AGENTS.md en este dir.

## Estructura
- \`AGENTS.md\` — ledger (mapa, decisiones, pendientes)
- \`scripts/\` — scripts propios reutilizables (con header de uso)
EOF
echo "Proyecto creado: $PROJ (AGENTS.md + scripts/ + README.md)"
