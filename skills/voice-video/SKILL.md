---
name: voice-video
description: Generar VOZ (TTS Qwen3-TTS con la voz de Victoria, es/en nativo), transcribir audio (STT Whisper) y analizar videos de YouTube (frames + transcripción + descripciones) vía los servicios de victoria (10.0.0.5). Usar SIEMPRE que el usuario pida voz, narración, diálogos hablados, transcripción de un audio, o analizar un video/link de YouTube. Para video hablado con labios (Sonic) informar el constraint y ofrecer el tab Estudio Podcast.
---

# Voice-Video — voz, transcripción y análisis de video vía los servicios de Victoria

Los servicios viven en el DGX Spark (victoria.local / 10.0.0.5) y se consumen
por HTTP con la llave `kalimete` (caps `llm/art/tts/whisper` — ya configurada;
el auth de los sentidos la acepta porque sense_auth eleva tts/whisper a
services).

## Endpoint y llave

- **Voz (TTS/STT)**: `http://10.0.0.5:18810`
- **Video server (YouTube)**: `http://10.0.0.5:18811`
- **Llave**: la misma del provider `vllm` en `~/.config/opencode/opencode.jsonc`
  (campo `apiKey`). Extraerla sin mostrarla en el chat:
  ```sh
  KEY=$(python3 -c "import re; s=open('$HOME/.config/opencode/opencode.jsonc').read(); print(re.search(r'\"apiKey\"\s*:\s*\"([^\"]+)\"', s).group(1))")
  ```

## TTS — texto a voz (voz de Victoria)

```sh
curl -s -X POST http://10.0.0.5:18810/tts \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"text":"Hola, esta es mi voz.","voice":"victoria","language":"es"}' \
  -o salida.wav
```

- Salida: **WAV mono 24kHz 16-bit** (Godot lo importa nativo como AudioStreamWAV;
  para otros usos convertir con ffmpeg si hace falta).
- **Voces**: `victoria` (default), `usuario`, `daisy`, `tanja`, `dionisio`, `damien`.
- **Idioma**: `language:"es"` usa la referencia ESPAÑOLA NATIVA de la voz
  (`victoria-es-reference.wav`); `"en"` usa la referencia inglesa. Misma voz,
  acento nativo en cada idioma. Default `es`.
- Textos largos: el server trocea solo; para diálogos de juego conviene UNA
  línea de diálogo por request (facilita el mapeo archivo↔línea).

## STT — transcribir audio

```sh
curl -s -X POST http://10.0.0.5:18810/stt \
  -H "Authorization: Bearer $KEY" \
  --data-binary @audio.wav
# -> {"text": "... transcripción ..."}  (auto-detect language, Whisper small)
```

## Video server — analizar YouTube (material de referencia)

```sh
# Todo-en-uno: descarga + frames + transcripción + descripciones VLM de cada frame
curl -s -X POST http://10.0.0.5:18811/analyze \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"url":"https://youtube.com/watch?v=XXXX","lang":"es"}'

# Solo descargar
curl -s -X POST http://10.0.0.5:18811/download \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"url":"https://youtube.com/watch?v=XXXX"}'

# Frames de un video ya descargado (o subir archivo local con /analyze-upload multipart)
curl -s -X POST http://10.0.0.5:18811/frames \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"video":"<video_path>","count":5,"width":640}'
```

Endpoints: `/download {"url"}` · `/frames {"video","times"?,"count"?,"width"?}` ·
`/transcribe {"video","lang"?}` · `/analyze {"url","frames_times"?,"lang"?}` ·
`/analyze-upload` (multipart, para archivos locales).

## Video hablado con labios (Sonic) — CONSTRAINT

Sonic (`:18850 POST /generate {"image_path","audio_path","out_path"?,"steps"?:25,
"resolution"?:512|640|768}`) usa **rutas LOCALES del FS de victoria** — NO hay
upload HTTP. Desde kalimete hay dos caminos:

1. **Tab 🎙️ Estudio Podcast** en browser: `http://victoria.local/liveportrait/`
   (guion → TTS → video con labios + subtítulos, todo desde la UI).
2. **Pedírselo a Victoria** (chat/WhatsApp): ella corre el job localmente con
   la foto + el WAV que generaste con `/tts`.

## Reglas

1. La GPU es compartida con la inferencia LLM: los servicios de voz/video son
   livianos, pero si algo responde lento, reintentar — no martillar.
2. Guarda los archivos donde el usuario pida (`~/Desktop/`, carpeta del
   proyecto) y dale la ruta absoluta al terminar.
3. Nada de clonar voces de personas reales sin consentimiento.
4. Estado del stack: delegar a `@Victoria Server` (solo lectura).
