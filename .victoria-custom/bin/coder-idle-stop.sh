#!/bin/bash
# coder-idle-stop.sh — detiene el vLLM-coder tras 30 min sin uso (2026-11-01)
# Parte del proyecto coder on-demand: el gateway arranca el contenedor al
# primer request (gate con RAM>=20G + sin render) y ESTE script lo descarga
# cuando nadie lo usa, devolviendo ~26G de RAM unificada al host.
# Timer systemd cada 5 min. Stdlib puro: docker + curl + coreutils.

CODER_CONTAINER="nemoclaw-vllm-coder"
LAST_USE_FILE="/home/victoria/.victoria-llm/coder-last-use"
STATE_FILE="/home/victoria/.victoria-llm/coder-state"
IDLE_SECS="${CODER_IDLE_STOP_SECS:-1800}"   # 30 min
LOG="/home/victoria/logs/coder-idle-stop.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# ¿Contenedor existe y corre?
STATE=$(docker inspect -f '{{.State.Running}}' "$CODER_CONTAINER" 2>/dev/null)
if [ "$STATE" != "true" ]; then
    # Asegurar estado coherente para la válvula del gateway
    [ -f "$STATE_FILE" ] && grep -q stopped "$STATE_FILE" 2>/dev/null || echo "stopped" > "$STATE_FILE" 2>/dev/null
    exit 0
fi

# ¿Motor con requests en vuelo? (informativo; ver regla de grace abajo)
RUNNING=$(curl -s -m 3 http://127.0.0.1:8001/metrics 2>/dev/null | grep '^vllm:num_requests_running' | grep -oE '[0-9.]+$' | head -1)
RUNNING_INT="${RUNNING%.*}"; [ -z "$RUNNING_INT" ] && RUNNING_INT=0

# ¿Último uso? Fallback: StartedAt del contenedor
NOW=$(date +%s)
if [ -f "$LAST_USE_FILE" ]; then
    LAST=$(cat "$LAST_USE_FILE" 2>/dev/null || echo 0)
else
    LAST=0
fi
if [ "$LAST" -le 0 ]; then
    STARTED=$(docker inspect -f '{{.State.StartedAt}}' "$CODER_CONTAINER" 2>/dev/null)
    LAST=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
fi
AGE=$(( NOW - LAST ))

# Regla de descarga (fix zombis 2026-11-01): el gateway toca last-use en cada
# ADMISION. Una generación legítima tarda <15 min (22K output ~40 tok/s), así
# que: sin requests en vuelo → stop a los 30 min; con requests en vuelo →
# stop a los 45 min (30 idle + 15 de margen de generación). Un request que
# sigue "en vuelo" con last-use de 45+ min es un ZOMBI (cliente muerto) y NO
# debe bloquear la descarga para siempre.
if [ "$RUNNING_INT" -gt 0 ]; then
    EFFECTIVE_SECS=$(( IDLE_SECS + 900 ))   # 45 min
else
    EFFECTIVE_SECS="$IDLE_SECS"             # 30 min
fi

if [ "$AGE" -ge "$EFFECTIVE_SECS" ]; then
    log "idle ${AGE}s >= ${EFFECTIVE_SECS}s (running=$RUNNING_INT): docker stop $CODER_CONTAINER"
    docker stop "$CODER_CONTAINER" >/dev/null 2>&1 && log "detenido OK — ~26G devueltos al host"
    echo "stopped" > "$STATE_FILE" 2>/dev/null
else
    log "idle ${AGE}s < ${EFFECTIVE_SECS}s (running=$RUNNING_INT): sigue corriendo"
fi
