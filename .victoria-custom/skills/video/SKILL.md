---
name: video
description: "Analiza videos (URL de YouTube o archivo subido mp4/avi/mov) por petición del usuario: descarga/lee, extrae frames, transcribe el audio y describe el contenido visual."
---

# Análisis de videos (video)

Cuando el usuario pide analizar, resumir o entender un video, distingue DOS casos:

## Caso A — El usuario envía un LINK (URL de YouTube u otra URL de video)

Usa el wrapper `video-analyze` (descarga con yt-dlp EN EL HOST):

```bash
/sandbox/.openclaw/bin/video-analyze <url> [--count N] [--times HH:MM:SS ...] [--lang es|en]
        [--for <scope>] [--owner]
```

## Ventanas por grupo/canal (modo creativo v3 — `video` es PESADO)

Scopes: `wa:<group-jid>` (ej. `wa:120363429817888300@g.us`) |
`dc:<guild-id>` (ej. `dc:1365731253629751406`) |
`dc:<guild>:<channel>` (canal Discord). Ventana 4h max (default 4), cuota 10.
DM siempre SÍ. Incluye transcribir/analizar videos subidos (mismo gate).

- **Miembro sin ventana**: NO ejecutes. Frase guía ("ese modo aún no está
  abierto en este grupo — pídele a Alfredo que lo active 🔓") +
  `art-approve flow <scope> video --requester "<nombre>" --prompt "<url>"`
  (UNA solicitud por scope+feature, 24h, sin re-notificar si ya hay vigente)
  + DM al owner con el payload (comando exacto
  `art-approve approve <scope> video 4` o `sí video 4`). NUNCA mandes al
  miembro al DM.
- **Ventana vigente**: `video-analyze <url> --for <scope>` (SIN `--owner`) +
  aviso al owner por DM por cada uso.
- **Owner** (`senderIsOwner:true`, DM o EN EL GRUPO): ejecuta directo con
  `--owner` (bypass total, sin solicitud) + auto-ventana (el wrapper la abre
  igual que art-gen/art-3d). En el grupo abre hablando: `abro video 2` /
  `modo creativo 2` / `cierro video` / `cierra todo` → `art-approve natural`
  + anuncio con hora de fin.

## Caso B — El usuario envía un ARCHIVO (video adjunto mp4/avi/mov/webm)

El video subido llega como un `MediaPath` (ruta local en el sandbox, ej.
`media://inbound/<uuid>.mp4` o una ruta absoluta). Usa el wrapper
`video-analyze-local` para procesar el archivo directamente (NO es un link):

```bash
/sandbox/.openclaw/bin/video-analyze-local <ruta-del-video.mp4> [--count N] [--lang es|en]
```

También puedes ejecutarlo vía `exec` con el comando:
`/sandbox/.openclaw/bin/video-analyze-local <ruta> --count 6 --lang es`

## Comando (ambos casos)

- Default: 5 frames automáticos repartidos por el video + transcripción en español.
- `--count N`: número de frames (útil para videos largos, usar 8-10).
- `--times`: (solo URL) timestamps específicos para analizar momentos concretos.
- `--lang`: idioma de la transcripción y de las descripciones.

## Salida (JSON)

```json
{
  "title": "Título del video",
  "duration": 634.6,
  "resolution": "640x360",
  "video_path": "/abs/path/video.mp4",
  "frames": ["/abs/path/frame-00.jpg", ...],
  "transcript": "texto de la transcripción...",
  "frame_descriptions": ["descripción VLM del frame 1", ...]
}
```

## Cómo responder

1. **Ejecuta** el wrapper correspondiente (URL o archivo local) con `exec`.
2. **Lee** `title`, `frame_descriptions` y `transcript`.
3. **Resume** en el idioma del usuario:
   - Qué muestra el video (por las descripciones de frames).
   - Qué dice (por la transcripción).
   - Punto clave / conclusión si aplica.
4. Si la transcripción sale vacía o llena de "I I I", el video probablemente no
   tiene diálogo (solo música/sonido) — dilo naturalmente y apóyate en las
   descripciones visuales.

## Notas

- **Link**: la primera llamada descarga el video (puede tardar 1-3 min).
- **Archivo local**: procesa el archivo tal cual (mp4/avi/mov/webm/mkv); si el
  formato no es legible por ffmpeg, dirá el error en el JSON.
- Los videos de link quedan guardados en el host en
  `/home/victoria/.victoria-custom/videos/downloads/`; los subidos en
  `/home/victoria/.victoria-custom/videos/uploads/`.
- Si el wrapper falla con "socket error", avisa que el servicio de video
  no está disponible temporalmente.

## Imágenes

Si el usuario envía una IMAGEN (jpg/png) — no un video — el VLM ya la procesa
nativamente (el modelo acepta `image`). No uses los wrappers de video para
imágenes; simplemente describe lo que ves en la imagen adjunta.