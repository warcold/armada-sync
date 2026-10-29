# ffmpeg — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `ffmpeg -version` → 6.1.1-3ubuntu5+esm15)
> **Docs oficiales**: https://ffmpeg.org/ffmpeg-filters.html (filtros) + `ffmpeg -h filter=<nombre>`

## Versiones en uso

- 6.1.1 (Ubuntu esm) en host victoria — voz (cadena de claridad), video-server, reels, kalimete-ptt (grabación PTT)
- ffmpeg DENTRO del sandbox (instalado por fix propio)

## Cadenas que usamos (recetas probadas)

- **Claridad de voz** (`enhance_clarity` en voice-server): `highpass=70, equalizer=f=3000:t=q:w=1:g=4.5, equalizer=f=5500:t=q:w=1:g=2, acompressor, loudnorm=I=-16` — presencia +3-4dB sin cambiar timbre. — (CHANGELOG-voice 2026-09-27)
- **Limpieza de referencias de voz**: `highpass+lowpass+afftdn+loudnorm -16 LUFS` → 22050Hz mono 16-bit. — (CHANGELOG 2026-08-31)
- **Reels**: h264 yuv420p 1080x1920 + subs + logo watermark
- **PTT grabación**: ffmpeg + PulseAudio (kalimete), evdev para la tecla

## Gotchas descubiertos (lecciones)

- **`wave` de Python no lee todos los WAV de ffmpeg** — medir duración con `ffprobe -v error -show_entries format=duration -of csv=p=0`. — (lección 2026-10-27)
- **ogg→wav 16kHz para Whisper**: el runtime de openclaw lo convierte solo (`resolveCliMediaPath`); en scripts manuales convertir SIEMPRE antes de /stt. — (CHANGELOG-voice 2026-10-05)
- **ffmpeg 6.1 en ARM64**: todos los filtros que usamos existen; si un filtro falta, verificar con `ffmpeg -filters | grep <f>` antes de asumir.

## Regla de actualización

ffmpeg del sistema (esm): actualizar solo con apt upgrade coordinado. Cadenas
nuevas: probar en un archivo de prueba + medir resultado (ffprobe/escucha) +
changelog si queda en producción.
