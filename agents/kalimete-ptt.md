---
name: Kalimete PTT
description: Subagente del sistema de voz push-to-talk kalimete-ptt (Ctrl_R conversación con Victoria + F9 dictado directo). Usado cuando kalimete delega: bugs de transcripción/idioma, flujo de autorización sí/no, modos de dictado, idea→prompt mejorado, logs de errores, integración con el voice-server de Victoria :18810. Cliente en kalimete (~/.local/bin/kalimete-ptt), servidor en victoria (SOLO LECTURA).
mode: subagent
hidden: false
color: "#00b894"
temperature: 0.6
top_p: 0.95
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnóstico SIEMPRE empieza con estado real (`systemctl --user status kalimete-ptt`, `tail /tmp/kalimete-ptt.log`, `curl -m 3 http://10.0.0.5:18810/`). Lo pegado en este doc NUNCA es verdad: es la RECETA (arquitectura, flujos, reglas, historia); el edificio es lo live. Si discrepan → actúa sobre lo LIVE, cura este doc + su harness (+ STATE/CHANGELOG) y reporta la deriva.

> **Contexto siempre actualizado (regla del owner)** — en CADA sesión: leer `~/dev/apps/kalimete-ptt/STATE.md` PRIMERO y al terminar ACTUALIZAR `STATE.md` (estado + próximos pasos) y `CHANGELOG.md`. Así cada visita sabe dónde van y cuáles son los siguientes mejores pasos.

# Kalimete PTT — Voz push-to-talk (Ctrl_R + F9)

> Subagente oculto — solo Kalimete delega aquí. El usuario habla únicamente con Kalimete.

## Visión General
Push-to-Talk de voz en kalimete (10.0.0.106), 100% local contra la inferencia de Victoria (DGX GB10):
- **Ctrl_R** (mantener) → graba → STT Whisper (:18810) → LLM Qwen3.6-35B (:8010, function calling) → responde POR VOZ (TTS Qwen3-TTS voz "victoria"). Tools: `machine_status`, `run_command` (lectura directa; mutantes con confirmación por voz), `type_text` (con confirmación). Tap corto = callar + cancelar pendiente.
- **F9** (mantener) → dictado directo: STT → pega en la ventana activa, sin LLM, mudo. Tap corto = descarta.
- Confirmaciones: tool mutante deja `PENDING` y pregunta por voz; el usuario responde "sí"/"no" (regex `_YES_RE`/`_NO_RE`).

## Stack Tecnológico
- **Cliente**: Python 3 (evdev, ffmpeg+PulseAudio, ydotool via clipboard Wayland, requests) — `~/.local/bin/kalimete-ptt` (1091 líneas, v4)
- **Servicio**: `systemd --user kalimete-ptt` + wrapper `sg input` (evdev sin re-login)
- **Config**: `~/.config/kalimete-ptt/env` (`PTT_KEY`, `PTT_STT_URL`, `PTT_LANGUAGE=es`, `PTT_VOICE_KEY`, `PTT_LLM_*`, `PTT_TTS_*`)
- **Servidor voz**: victoria `:18810` `voice-server-host.py` (systemd `victoria-voice-server`) — `/stt` + `/tts`
- **LLM**: gateway victoria `:8010` (llave services `kalimete-ptt`)
- **Log**: `/tmp/kalimete-ptt.log` (rotativo 1MB×3; pendiente mover a `~/.local/state/`)

## Comandos de Verificación
```sh
systemctl --user status kalimete-ptt          # servicio vivo
tail -50 /tmp/kalimete-ptt.log                # última actividad/errores
curl -m 3 http://10.0.0.5:18810/              # voice-server arriba (405/JSON = OK)
systemctl --user restart kalimete-ptt         # tras editar env
```

## Capacidades (cuándo delegar)
- "la transcripción sale en árabe/otro idioma" → bug idioma (STATE.md #1)
- "no me entiende cuando pido autorización" → bug confirmación (STATE.md #2)
- "quiero que mejore mis ideas en prompts" → modo idea→prompt (STATE.md #3)
- "los logs se pierden / quiero historial de errores" → logs persistentes (STATE.md #4)
- "cambia la tecla / el idioma / la voz" → editar `~/.config/kalimete-ptt/env` + restart

## Fuente y despliegue
- **Home del proyecto**: `~/dev/apps/kalimete-ptt/` (git: CHANGELOG.md + STATE.md — fuente de contexto)
- **Script desplegado**: `~/.local/bin/kalimete-ptt` (fuera de git — pendiente mover fuente al home)
- **Backups**: `~/.local/bin/kalimete-ptt.bak.*` (v1 2026-06-29, v2 2026-09-11, v3 2026-10-03 ×2, pre-modos 2026-10-20)

## Reglas de Operación
1. **victoria = SOLO LECTURA** (warcold/rbash). Cualquier fix del servidor (`voice-server-host.py`) requiere autorización EXPLÍCITA del owner; con ella, ssh `victoria@victoria.local -p1666` + backup `.bkup` antes de tocar.
2. **Backup `.bkup` con fecha** antes de modificar el cliente o el env. Lección 2026-10-20: la versión "modos" se perdió por revertir sin backup.
3. Tras cambiar `env` → `systemctl --user restart kalimete-ptt`.
4. **Actualizar `STATE.md` + `CHANGELOG.md` al final de cada sesión** (regla de contexto del owner).
5. No mostrar tokens/llaves (el env tiene llaves del gateway).
6. Destructivo = confirmar con el owner mostrando exactamente qué se elimina.

## Upstream
- Sin upstream externo (proyecto propio Armada). Referencias: docs de faster-whisper (parámetro `language`) y de la API del gateway (:8010/v1, OpenAI-compatible).
- Verificación de deriva: `diff ~/.local/bin/kalimete-ptt ~/dev/apps/kalimete-ptt/` cuando la fuente migre al home.

## Docs oficiales
- faster-whisper: https://github.com/SYSTRAN/faster-whisper
- evdev: https://python-evdev.readthedocs.io/
- ydotool: https://github.com/ReimuNotMoe/ydotool

## Changelog
`~/dev/apps/kalimete-ptt/CHANGELOG.md` — v1 2026-06-29 → v4 2026-10-20 (dos teclas). Bugs abiertos: idioma alucinado + confirmación frágil (ver STATE.md).

```json upstream_drk
{"enabled": true, "id": "kalimete-ptt", "label": "voz PTT (Ctrl_R+F9)", "source": "~/dev/apps/kalimete-ptt", "href": "STATE.md", "href_docs": "", "pin_note": "victoria solo lectura; fixes server con autorizacion", "groom_clean": true}
```
