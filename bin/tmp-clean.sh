#!/usr/bin/env bash
# tmp-clean.sh — Limpieza de ~/tmp respetando KEEP (default: DRY-RUN, solo lista).
#
# Política temporal del ecosistema (2026-09-30):
#   ~/tmp/              → trabajo temporal PROPIO (no /tmp del sistema ni /tmp/opencode de herramientas)
#   <algo>.keep         → flag: este item NO se borra nunca en limpiezas
#   KEEP.list           → un nombre por línea: patrones extra que tampoco se borran
#   Todo lo demás con >N días sin tocar → candidato a borrar.
#
# Uso:
#   tmp-clean.sh                 # DRY-RUN: lista lo que borraría (default seguro)
#   tmp-clean.sh --apply         # borra de verdad lo listado
#   tmp-clean.sh --days 3 --apply  # ventana de 3 días + aplicar
#
# Regla de oro: si un script de ~/tmp se usa >1 vez, PROMOVERLO a la librería
# (`~/.victoria-custom/bin/` en victoria, `~/bin/` en kalimete) con header de uso
# y registrarlo en SCRIPTS.md — nunca re-crear lo mismo dos veces.
set -u
DAYS=7
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --days) DAYS="$2"; shift 2 ;;
    --days=*) DAYS="${1#--days=}"; shift ;;
    *) shift ;;
  esac
done
TMPDIR="$HOME/tmp"
[ -d "$TMPDIR" ] || { echo "No existe $TMPDIR"; exit 0; }
MODE="DRY-RUN"; [ $APPLY = 1 ] && MODE="APLICAR"
echo "== tmp-clean: $TMPDIR, >${DAYS}d, modo $MODE =="
find "$TMPDIR" -mindepth 1 -mtime +"$DAYS" | while read -r f; do
  base=$(basename "$f")
  [ -e "$f.keep" ] && { echo "KEEP(flag): $f"; continue; }
  [ -e "$TMPDIR/$base.keep" ] && { echo "KEEP(flag): $f"; continue; }
  if [ -f "$TMPDIR/KEEP.list" ] && grep -qxF "$base" "$TMPDIR/KEEP.list" 2>/dev/null; then
    echo "KEEP(list): $f"; continue
  fi
  if [ $APPLY = 1 ]; then echo "BORRADO: $f"; rm -rf "$f"; else echo "borraría: $f"; fi
done
echo "== fin (promueve a librería lo que reaparezca: ver SCRIPTS.md) =="
