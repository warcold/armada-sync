#!/bin/bash
# ngc-upgrade-2609.sh v2 — Switch vLLM NGC 26.05.post1 -> 26.09-py3 (vLLM 0.21.0 -> 0.29.0) con AUTO-ROLLBACK
# v2 (2026-10-26 15:05): +compile-cache volume (primer boot 0.29 compila 15-25min — la v1 fallo por ventana
#   de 15min), ventana 35min, dump de docker logs antes de cada rm (forense), progreso del container en el log.
# Autorizado owner 2026-10-26 ("procede con todo... aunque rompa versiones").
# Ejecutar con nohup: sobrevive a la muerte de la sesion de opencode.
set -u
LOG=/tmp/opencode/ngc-switch.log
OLD_DIGEST="nvcr.io/nvidia/vllm@sha256:9204569b17ee4c0eff75194b8e6e458479c8aee18953b5ab9cf359fcdac659e2"
NEW_DIGEST="nvcr.io/nvidia/vllm@sha256:557747337846eecf34486866f3d992383c6f8af869fdb0e365b5093fcaee02c2"
HEALTH_URL="http://127.0.0.1:8000/health"
WAIT_MIN=35
COMPILE_CACHE=/home/victoria/.vllm-compile-cache

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

changelog_note() {
  python3 - "$1" <<'PYEOF'
import sys
result = sys.argv[1]
entry = f"""### [{__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')} EDT] [vllm] NGC switch v2 26.05.post1->26.09-py3 — RESULTADO: {result}
- **Tipo**: infra (script autonomo ngc-upgrade-2609.sh v2 con compile-cache volume + auto-rollback; autorizacion owner)
- **Detalle**: /tmp/opencode/ngc-switch.log — entrada extendida la escribe Victoria al volver."""
with open('/home/victoria/CHANGELOG.md') as f:
    lines = f.read().split('\n')
lines.insert(1, entry)
with open('/home/victoria/CHANGELOG.md', 'w') as f:
    f.write('\n'.join(lines))
PYEOF
}

dump_and_rm() {
  # Forense: guardar logs del container ANTES de rm (leccion v1: el container fallado se borro con sus logs)
  local TS=$(date '+%H%M%S')
  docker logs nemoclaw-vllm > "/tmp/opencode/vllm-container-logs-${TS}.log" 2>&1 || true
  docker stop nemoclaw-vllm >> "$LOG" 2>&1 || true
  docker rm nemoclaw-vllm >> "$LOG" 2>&1 || true
  log "Logs del container guardados: /tmp/opencode/vllm-container-logs-${TS}.log"
}

run_vllm() {
  local IMG="$1"
  mkdir -p "$COMPILE_CACHE"
  docker run -d \
    --name nemoclaw-vllm \
    --restart unless-stopped \
    --gpus all --ipc host --init \
    --security-opt label=disable \
    --label com.nvidia.nemoclaw.managed-vllm=true \
    -p 8000:8000 \
    -v /home/victoria/.cache/huggingface:/root/.cache/huggingface \
    -v "$COMPILE_CACHE":/root/.cache/vllm \
    -e HF_HOME=/root/.cache/huggingface \
    "$IMG" \
    /bin/bash -lc "vllm serve nvidia/Qwen3.6-35B-A3B-NVFP4 \
      --tensor-parallel-size 1 --pipeline-parallel-size 1 --data-parallel-size 1 \
      --port 8000 --trust-remote-code --max-model-len 262144 \
      --gpu-memory-utilization 0.22 --dtype auto --quantization modelopt \
      --kv-cache-memory-bytes 12884901888 \
      --kv-cache-dtype fp8 --attention-backend flashinfer --moe-backend marlin \
      --max-num-seqs 3 --max-num-batched-tokens 8192 \
      --enable-chunked-prefill --async-scheduling --enable-prefix-caching \
      --enable-auto-tool-choice --tool-call-parser qwen3_xml \
      --reasoning-parser qwen3 --load-format fastsafetensors \
      --default-chat-template-kwargs '{\"enable_thinking\": false}' \
      --speculative-config '{\"method\":\"mtp\",\"num_speculative_tokens\":3,\"moe_backend\":\"triton\"}'" >> "$LOG" 2>&1
}

wait_health() {
  local deadline=$((SECONDS + WAIT_MIN*60))
  local last_progress=0
  while [ $SECONDS -lt $deadline ]; do
    if curl -sf -m 5 "$HEALTH_URL" > /dev/null 2>&1; then return 0; fi
    # Progreso: cada 60s, ultima linea del log del container (compile puede tardar 15-25min la 1ra vez)
    if [ $((SECONDS - last_progress)) -ge 60 ]; then
      PROG=$(docker logs nemoclaw-vllm --since 65s 2>&1 | grep -vE '^\s*$' | tail -1 | cut -c1-160)
      log "  ...esperando (${SECONDS}s): ${PROG:-sin log nuevo}"
      last_progress=$SECONDS
    fi
    sleep 15
  done
  return 1
}

log "=== NGC SWITCH v2 INICIO: 26.05.post1 (9204569b) -> 26.09-py3 (55774733) ==="
log "v2: compile-cache volume ${COMPILE_CACHE} + ventana ${WAIT_MIN}min + forense de logs"
log "1. Stop + rm contenedor viejo (inferencia del stack muere aqui — esperado)"
dump_and_rm
log "2. Run contenedor NUEVO (receta canonica + compile-cache mount)"
run_vllm "$NEW_DIGEST"
log "3. Esperando /health (max ${WAIT_MIN}min — primer boot compila torch.compile 15-25min)"
if wait_health; then
  log "HEALTH OK — verificando modelo servido"
  MODELS=$(curl -s -m 10 http://127.0.0.1:8000/v1/models 2>/dev/null | grep -o 'Qwen3.6-35B[^"]*' | head -1)
  log "Modelo servido: ${MODELS:-NO DETECTADO}"
  if [ -n "$MODELS" ]; then
    log "=== SWITCH v2 EXITOSO — vLLM 0.29.0 en 26.09-py3, compile cache persistente activo ==="
    log "POST-SWITCH PENDIENTE (Victoria): contexto+max_tokens (breaking #57035) + CORS + tool-calls E2E"
    changelog_note "EXITOSO v2 — vLLM 0.29.0 (26.09-py3) sirviendo Qwen3.6-35B con compile-cache persistente"
    exit 0
  fi
fi

log "!!! HEALTH FALLA tras ${WAIT_MIN}min — AUTO-ROLLBACK al digest 9204569b (26.05.post1)"
dump_and_rm
log "Run contenedor VIEJO (rollback, ahora tambien con compile-cache mount)"
run_vllm "$OLD_DIGEST"
if wait_health; then
  log "=== ROLLBACK COMPLETO — vLLM de vuelta en 26.05.post1, stack estable ==="
  changelog_note "ROLLBACK v2 — 26.09-py3 no paso health en 35min; stack restaurado en 26.05.post1; forense en /tmp/opencode/vllm-container-logs-*.log"
else
  log "!!! CRITICO: rollback tambien falla — NO TOCAR: docker ps -a + docker logs nemoclaw-vllm + journalctl -u docker"
  changelog_note "CRITICO v2 — ni 26.09 ni rollback pasaron health; ATENCION MANUAL REQUERIDA"
fi
exit 1
