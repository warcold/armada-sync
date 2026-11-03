#!/bin/bash
# openclaw-voice-host.sh
# Stack de voz de Victoria (TTS Qwen3-TTS + STT Whisper) VIVE EN EL HOST.
#
# Contexto: el venv dentro del sandbox se reconstruia sobre Python 3.13 (unico
# disponible en el container Debian 13), pero los motores TTS requieren
# Python <3.13 (coqui-tts) o torch con CUDA (qwen-tts). Por eso el voice-server
# vive en el host, que tiene Python 3.12 y acceso a PyPI. El sandbox consume
# el servicio via 172.18.0.1:18810 (host.docker.internal del netns del gateway).
#
# Motor TTS (2026-10-03, Fase Jarvis-Victoria): Qwen3-TTS-12Hz-0.6B-Base
# (Apache 2.0) con clonación ICL de ~/voices/<voz>-reference.wav (+ .txt
# con el transcript exacto). XTTS ELIMINADO del todo (2026-10-03, orden del
# owner): pesos 2G + coqui-tts + fallback borrados; todas las voces clonan
# por Qwen3 (incluidas daisy/tanja/dionisio/damien del Estudio, con wav+.txt
# propios generados con XTTS antes de borrarlo).
#
# Este script asegura en el HOST:
#   - /home/victoria/voice-venv  (python3.12 + torch cu128 + qwen-tts +
#     whisper + transformers 4.57.3, accelerate, onnxruntime, sox)
#   - modelos Qwen3-TTS + whisper en rutas canónicas (HOST_MODELS)
#   - /home/victoria/voices/  (victoria/usuario-reference.wav + .txt)
#   - /home/victoria/voice-venv/voice-server-host.py
#   - servicio systemd victoria-voice-server.service (enabled, Restart=always)
#
# Y en el SANDBOX (siempre que este levantado):
#   - wrappers victoria-tts/whisper-cli (socket UNIX /tmp/tts-gateway.sock)
#
# Uso: openclaw-voice-host.sh {ensure|install|status|test}
set -u

VH="/home/victoria/voice-venv"
PY312="/usr/bin/python3.12"
HOST_MODELS="/home/victoria/.voice-models"
SERVICE="victoria-voice-server.service"

log() { echo "[openclaw-voice-host] $(date -Is) $*"; }

cid_of() { docker ps -aq -f name=victoria-armada 2>/dev/null | head -1; }

py312_ok() { [ -x "$PY312" ] && "$PY312" -c 'import sys; sys.exit(0 if sys.version_info < (3,13) else 1)' 2>/dev/null; }

venv_ok() {
    # Verifica las rutas CANONICAS (las que usa voice-server-host.py), no los
    # duplicados dentro del venv (que se eliminaron en 2026-08-30 para ahorrar ~2.5GB).
    [ -x "$VH/bin/python" ] \
      && "$VH/bin/python" -c 'import qwen_tts, whisper, torch, transformers' 2>/dev/null \
      && [ -f "$HOST_MODELS/Qwen3-TTS-12Hz-0.6B-Base/model.safetensors" ] \
      && [ -f "/home/victoria/.cache/whisper/small.pt" ] \
      && [ -f "/home/victoria/voices/victoria-reference.wav" ] \
      && [ -f "/home/victoria/voices/victoria-reference.txt" ] \
      && [ -f "$VH/voice-server-host.py" ]
}

ensure_python312() {
    if ! py312_ok; then
        log "python3.12 no disponible en el host; instalando..."
        sudo apt-get install -y -qq python3.12 python3.12-venv python3.12-dev build-essential 2>&1 | tail -2
        py312_ok || { log "ERROR: no se pudo instalar python3.12"; return 1; }
        log "python3.12 instalado"
    fi
}

ensure_venv() {
    if venv_ok; then
        log "venv host ya presente"
        return 0
    fi
    log "creando/completando venv host ($VH)..."
    [ -x "$VH/bin/python" ] || "$PY312" -m venv "$VH"
    "$VH/bin/pip" install -q --index-url https://download.pytorch.org/whl/cu128 torch torchaudio \
        || { log "ERROR torch"; return 1; }
    "$VH/bin/pip" install -q "transformers==4.57.3" openai-whisper torchcodec \
        || { log "ERROR transformers/whisper"; return 1; }
    # Motor principal Qwen3-TTS (2026-10-03): --no-deps para no traer gradio
    # (UI demo de ellos, peso muerto aquí); deps de runtime explícitas.
    "$VH/bin/pip" install -q accelerate onnxruntime sox einops librosa soundfile \
        || { log "ERROR deps qwen-tts"; return 1; }
    "$VH/bin/pip" install -q --no-deps "qwen-tts==0.1.1" \
        || { log "ERROR qwen-tts"; return 1; }
    log "venv host listo"
}

ensure_models() {
    # Solo verifica las rutas CANONICAS (en HOST_MODELS y ~/voices). NO crea
    # duplicados dentro del venv (se eliminaron 2026-08-30, ahorro ~2.5GB).
    # Qwen3-TTS es el ÚNICO motor (XTTS eliminado 2026-10-03).
    [ -f "$HOST_MODELS/Qwen3-TTS-12Hz-0.6B-Base/model.safetensors" ] || { log "ERROR: falta $HOST_MODELS/Qwen3-TTS-12Hz-0.6B-Base/model.safetensors"; return 1; }
    [ -f "/home/victoria/.cache/whisper/small.pt" ] || { log "ERROR: falta whisper small.pt canonico"; return 1; }
    [ -f "/home/victoria/voices/victoria-reference.wav" ] || { log "ERROR: falta victoria-reference.wav canonico"; return 1; }
    [ -f "/home/victoria/voices/victoria-reference.txt" ] || { log "ERROR: falta victoria-reference.txt (transcript exacto para el clon ICL)"; return 1; }
    # Ref española nativa (acento): WARN si falta — el server degrada a la ref
    # inglesa (funciona, pero español con acento). Re-generable por recitación.
    [ -f "/home/victoria/voices/victoria-es-reference.wav" ] || log "WARN: falta victoria-es-reference.wav — español usará la ref inglesa (acento)"
    [ -f "/home/victoria/voices/victoria-es-reference.txt" ] || log "WARN: falta victoria-es-reference.txt"
    log "modelos y voces canonicos OK"
}

ensure_server_script() {
    [ -f "$VH/voice-server-host.py" ] || {
        log "copiando voice-server-host.py..."
        # Si hay sandbox vivo, lo tomamos de ahi; si no, fallback a instalacion manual.
        local cid
        cid=$(cid_of)
        if [ -n "$cid" ]; then
            docker cp "$cid":/sandbox/.openclaw/bin/voice-server.py "$VH/voice-server-host.py" 2>/dev/null
            sed -i 's|/sandbox/.openclaw/voices|/home/victoria/voices|g' "$VH/voice-server-host.py"
        fi
        [ -f "$VH/voice-server-host.py" ] || { log "ERROR: no se pudo obtener voice-server-host.py"; return 1; }
        log "voice-server-host.py listo"
    }
}

ensure_service() {
    if ! systemctl is-enabled "$SERVICE" >/dev/null 2>&1; then
        log "instalando unit systemd $SERVICE..."
        sudo tee /etc/systemd/system/$SERVICE > /dev/null << EOF
[Unit]
Description=Victoria Voice Server (TTS Qwen3-TTS + STT Whisper) on host
After=network.target
Wants=network.target

[Service]
Type=simple
User=victoria
Environment=HOME=$VH
Environment=VOICE_PORT=18810
ExecStart=$VH/bin/python $VH/voice-server-host.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable "$SERVICE" >/dev/null 2>&1
        log "unit instalada"
    fi
    if ! systemctl is-active "$SERVICE" >/dev/null 2>&1; then
        sudo systemctl start "$SERVICE" >/dev/null 2>&1
        log "servicio iniciado"
    else
        log "servicio ya activo"
    fi
}

ensure_sandbox_wrappers() {
    local cid
    cid=$(cid_of)
    [ -z "$cid" ] && { log "sandbox no levantado; wrappers se quedan para el ensure-loop"; return 0; }
    # Los wrappers actuales usan el bridge UNIX socket /tmp/tts-gateway.sock
    # (legacy: apuntaban a http://172.18.0.1:18810; ese sed es no-op hoy).
    # Nombres canónicos: victoria-tts + whisper-cli (xtts-cli eliminado 2026-10-03).
    docker exec "$cid" sh -c \
        'grep -q "172.18.0.1:18810" /sandbox/.openclaw/bin/victoria-tts 2>/dev/null || sed -i "s|http://127.0.0.1:18810|http://172.18.0.1:18810|g" /sandbox/.openclaw/bin/victoria-tts /sandbox/.openclaw/bin/whisper-cli 2>/dev/null; echo ok' \
        >/dev/null 2>&1
    log "wrappers del sandbox verificados (victoria-tts + whisper-cli)"
}

status() {
    echo "venv host python:"
    "$VH/bin/python" -c 'import sys; print("  ", sys.version.split()[0])' 2>/dev/null || echo "  FALTA"
    echo "paquetes:"
    "$VH/bin/python" -c 'import qwen_tts, whisper, torch, transformers; print("   qwen_tts+whisper+torch+transformers OK")' 2>/dev/null || echo "   INCOMPLETO"
    echo "modelos (canonicos):"
    [ -f "$HOST_MODELS/Qwen3-TTS-12Hz-0.6B-Base/model.safetensors" ] && echo "   Qwen3-TTS-0.6B-Base OK (principal)" || echo "   Qwen3-TTS FALTA"
    [ -f "/home/victoria/.cache/whisper/small.pt" ] && echo "   whisper OK" || echo "   whisper FALTA"
    echo "voces (canonicas):"
    ls /home/victoria/voices/ 2>/dev/null | sed 's/^/   /'
    echo "servicio systemd:"
    systemctl is-active "$SERVICE" 2>/dev/null | sed 's/^/   /'
    curl -s -m 5 http://127.0.0.1:18810/health 2>/dev/null && echo ""
}

test_tts_stt() {
    echo "== TTS =="
    curl -s -m 420 -o /tmp/vhs-test.wav -w "HTTP %{http_code}\n" -X POST http://127.0.0.1:18810/tts \
        -H "Content-Type: application/json" \
        -d '{"text":"Hola, soy Victoria Armada, prueba del stack de voz en el host.","voice":"victoria","language":"es"}'
    [ -s /tmp/vhs-test.wav ] && file /tmp/vhs-test.wav
    echo "== STT =="
    curl -s -m 420 -X POST http://127.0.0.1:18810/stt --data-binary @/tmp/vhs-test.wav
    echo ""
    echo "== health =="
    curl -s -m 5 http://127.0.0.1:18810/health; echo ""
}

cmd="${1:-ensure}"
case "$cmd" in
    ensure)
        if systemctl is-active "$SERVICE" >/dev/null 2>&1; then
            log "servicio $SERVICE ya activo; omito"
            exit 0
        fi
        ensure_python312 && ensure_venv && ensure_models && ensure_server_script && ensure_service && ensure_sandbox_wrappers
        rc=$?
        [ $rc -eq 0 ] && log "ensure OK" || log "ensure con errores"
        exit $rc
        ;;
    install)
        touch "$LOCK"
        ensure_python312 && ensure_venv && ensure_models && ensure_server_script && ensure_service && ensure_sandbox_wrappers
        rc=$?
        rm -f "$LOCK"
        exit $rc
        ;;
    status)
        status
        ;;
    test)
        test_tts_stt
        ;;
    *)
        echo "uso: openclaw-voice-host.sh {ensure|install|status|test}" >&2
        exit 2
        ;;
esac
