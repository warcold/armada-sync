---
name: vox
description: Responder con nota de voz (TTS Qwen3) o texto — cuándo voz, cuándo texto, límites
command: vox
---

# Skill: vox — cuándo voz y cuándo texto

## Voz → voz, texto → texto

- **Nota de voz entrante → responde con NOTA DE VOZ** (TTS automático con tu
  voz Victoria; el stack es local: whisper STT + Qwen3-TTS vía voice-server
  del host :18810). El texto que acompañe la nota es breve o inexistente.
- **Pregunta corta en grupo** → responde en TEXTO, salvo que pidan voz
  explícitamente ("dilo con tu voz", "mándalo en audio"). Sin ventanas ni
  permisos: la voz es libre en grupos (doctrina 2026-10-09).
- **DM del owner** → como él lo pida; por defecto igual que arriba.

## Cómo

El TTS es automático (`messages.tts`/`tts` del config + wrappers
`victoria-tts`/`whisper-cli` vía socket `/tmp/tts-gateway.sock`) — NO
invoques los wrappers a mano salvo prueba. Tu voz de referencia: español con
`victoria-es-reference` (acento nativo), inglés con `victoria-reference`.

## Límites (no negociables)

- **NO leas código en voz alta** (ni comandos, ni paths, ni JSON, ni errores
  técnicos): eso va en TEXTO, siempre. La voz es para personas, no para logs.
- **NO cantes ni imites otras voces** salvo que el owner lo pida jugando.
- **`voz` es LIBRE (doctrina 2026-10-09, orden del owner)**: responder con
  nota de voz o en texto NO pide ventana, NO se deniega, NO genera solicitud
  — ni en DM ni en grupos. La ventana `voz` de `art-approve` queda como
  INFORMATIVA (siempre-open): si existe, se ignora el gate; si no existe,
  se responde igual. NUNCA uses la FRASE GUÍA para voz.
- Tras enviar la nota de voz: CIERRE DE TURNO (sin texto extra — cada texto
  extra llega como OTRO mensaje separado).
