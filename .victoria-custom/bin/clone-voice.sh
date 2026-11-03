#!/usr/bin/env bash
# clone-voice.sh — clona la voz de Victoria desde un audiolibro/zip de Librivox.
#
# Pipeline:
#   1. Extrae el zip
#   2. Lista los audios con duracion (para elegir el mejor segmento)
#   3. Genera un reference limpio: recorta, quita ruido (afftdn), normaliza
#      (loudnorm), convierte a 24000Hz mono 16-bit WAV (nativo Qwen3-TTS)
#   4. Lo instala como /home/victoria/voices/victoria-reference.wav (con backup)
#   5. Genera victoria-reference.txt con Whisper (transcript EXACTO — el clon
#      ICL de Qwen3-TTS lo exige; con un transcript que no coincide el modelo
#      se descontrola. REVISAR el .txt a mano antes de darlo por bueno).
#   6. Reinicia el voice-server (el prompt de clonación se construye una vez
#      por proceso) + prueba TTS.
#
# Uso:
#   clone-voice.sh <zip> [--segmento SS:MM] [--duracion N]
#   Ej: clone-voice.sh ~/Downloads/little_eve_edgarton_librivox.zip
#       clone-voice.sh little_eve.zip --segmento 01:30 --duracion 20
#
# La voz clonada se usa en TODO el sistema (voice-server :18810, WhatsApp,
# Discord voice, Web UI) porque el voice-server la lee de
# /home/victoria/voices/victoria-reference.wav (+ .txt) vía voice_clone_prompt.
set -u

VOICES_DIR="/home/victoria/voices"
WORK="/home/victoria/.victoria-custom/voice-clone"
REFERENCE="$VOICES_DIR/victoria-reference.wav"
BACKUP="$VOICES_DIR/victoria-reference.wav.bak-$(date +%Y%m%d-%H%M%S)"
SEGMENTO="00:30"
DURACION="25"

log() { echo "[clone-voice] $(date -Is) $*"; }

if [ $# -lt 1 ]; then
    echo "uso: $0 <zip> [--segmento SS:MM] [--duracion N]"
    exit 1
fi
ZIP="$1"; shift
while [ $# -gt 0 ]; do
    case "$1" in
        --segmento) SEGMENTO="$2"; shift 2;;
        --duracion) DURACION="$2"; shift 2;;
        *) echo "argumento desconocido: $1"; exit 1;;
    esac
done

[ -f "$ZIP" ] || { log "ERROR: no existe $ZIP"; exit 1; }
mkdir -p "$WORK"

log "1/6 Extrayendo $ZIP..."
rm -rf "$WORK/extract"
mkdir -p "$WORK/extract"
unzip -o -q "$ZIP" -d "$WORK/extract" || { log "ERROR: unzip fallo"; exit 1; }

log "2/6 Audios en el zip:"
find "$WORK/extract" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.flac" \) | sort | while read -r f; do
    dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null | cut -d. -f1)
    echo "   [$dur s] $(basename "$f")"
done

log "3/6 Generando reference limpio (segmento $SEGMENTO, $DURACION s)..."
SEG=$(find "$WORK/extract" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.flac" \) | sort | head -1)
[ -n "$SEG" ] || { log "ERROR: no hay audios en el zip"; exit 1; }
log "   fuente: $(basename "$SEG")"

# Pipeline de limpieza con ffmpeg:
#  - ss/t: recorta el segmento
#  - afftdn: reduccion de ruido (denoise)
#  - highpass/lowpass: quita rumble y sibilancia excesiva
#  - loudnorm: normaliza a -16 LUFS (buen nivel para TTS)
#  - ar 24000 / ac 1 / sample_fmt s16: nativo Qwen3-TTS (24kHz)
ffmpeg -y -v error -ss "$SEGMENTO" -t "$DURACION" -i "$SEG" \
    -af "highpass=f=80,lowpass=f=8000,afftdn=nf=-25, loudnorm=I=-16:TP=-1.5:LRA=11" \
    -ar 24000 -ac 1 -sample_fmt s16 "$WORK/reference-raw.wav" \
    || { log "ERROR: ffmpeg fallo"; exit 1; }

# Recortar silencios de los extremos
ffmpeg -y -v error -i "$WORK/reference-raw.wav" \
    -af "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.3, areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.3,areverse" \
    -ar 24000 -ac 1 "$WORK/reference-clean.wav" \
    || { log "ERROR: recorte de silencios fallo"; exit 1; }

log "4/6 Verificando calidad del reference:"
DUR_OUT=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$WORK/reference-clean.wav" 2>/dev/null | cut -d. -f1)
SIZE_OUT=$(stat -c%s "$WORK/reference-clean.wav" 2>/dev/null)
echo "   duracion: ${DUR_OUT}s | tamano: ${SIZE_OUT} bytes"
if [ "${DUR_OUT:-0}" -lt 8 ]; then
    log "ERROR: reference muy corto (<8s). Usa --segmento/--duracion distintos."
    exit 1
fi

log "5/6 Instalando como voz de Victoria (con backup)..."
cp -f "$VOICES_DIR/victoria-reference.wav" "$BACKUP" 2>/dev/null
cp -f "$WORK/reference-clean.wav" "$REFERENCE"
chown victoria:victoria "$REFERENCE" 2>/dev/null
log "   backup del anterior: $BACKUP"
log "   nueva voz: $REFERENCE ($(stat -c%s "$REFERENCE") bytes)"

log "5b/6 Transcript exacto para el clon ICL (OBLIGATORIO)..."
/home/victoria/voice-venv/bin/python3 -c "
import whisper, torch
m = whisper.load_model('/home/victoria/.cache/whisper/small.pt', device='cuda' if torch.cuda.is_available() else 'cpu')
r = m.transcribe('$REFERENCE')
open('$VOICES_DIR/victoria-reference.txt','w').write((r.get('text') or '').strip() + '\n')
print('transcript:', (r.get('text') or '').strip()[:200])
" 2>/dev/null
log "   revisa $VOICES_DIR/victoria-reference.txt — debe decir EXACTAMENTE lo que se oye"

log "6/6 Reiniciando voice-server para recargar la voz..."
sudo systemctl restart victoria-voice-server
sleep 3

log "LISTO. La voz de Victoria ahora es la clonada."
echo ""
echo "Backup del placeholder: $BACKUP"
echo "Para revertir: cp '$BACKUP' '$REFERENCE' && sudo systemctl restart victoria-voice-server"