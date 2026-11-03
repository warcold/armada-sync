# SCRIPTS.md — Librería reutilizable de Victoria (2026-09-30)

> ANTES de crear un script nuevo, busca aquí. Si existe, EJECÚTALO — no lo re-crees.
> Si creas uno que se usará >1 vez: header de uso + fila en esta tabla + sync lo respalda.
> Viven en `~/.victoria-custom/bin/` (respaldados por armada-sync, menos binarios).

## Bridges sandbox↔host (UNIX socket → daemons :1881x/:1884x)

| Script | Qué hace | Uso |
|---|---|---|
| `tts-bridge.py` | voz TTS/STT vía `:18810` | invocado por wrappers `victoria-tts`/`whisper-cli` |
| `video-bridge.py` | video vía `:18811` | invocado por `video-dl`/`video-analyze` |
| `whois-bridge.py` | whois vía `:18830` | invocado por `whois` |
| `admin-bridge.py` | host-admin vía `:18840` | invocado por `admin-cli` |
| `victoria-tts` / `whisper-cli` | TTS (Qwen3-TTS) / STT desde sandbox | `victoria-tts --text "..."` · `whisper-cli audio.wav` |
| `video-dl` / `video-analyze` / `video-analyze-local` | descargar / analizar YouTube | `video-analyze <url>` |
| `whois` | whois con fallback RDAP | `whois ejemplo.com` |
| `admin-cli` | exec/apt/services auditados del host | `admin-cli ...` (ver skill `admin`) |

## Utilidades

| Script | Qué hace | Uso |
|---|---|---|
| `anomalies` | ver anomalías del gateway (today/last/fails/forensics/storms) | `anomalies today` |
| `clone-voice.sh` | clonar voz (referencia TTS) desde audio | ver `~/.victoria-custom/voice-clone/` |
| `nvapi-rotate.sh` | rotar llaves NVIDIA (`status\|test\|rotate\|auto`) | `nvapi-rotate.sh status` |
| `victoria-video-gen` | generar video (pipeline contenido) | `victoria-video-gen --help` |
| `web-navigate` / `web-scrape` / `web-utils.sh` | navegación y scrapeo vía `:18820` | `web-scrape <url>` |
| `tmp-clean.sh` | limpiar `~/tmp` respetando KEEP (DRY-RUN default) | `tmp-clean.sh` · aplicar: `--apply` |
| `new-project.sh` | andamiaje: dir + `AGENTS.md` + `scripts/` + README | `new-project.sh <nombre>` |
| `blogwatcher` | binario Go RSS (NO respaldado, se reinstala) | `openclaw-rss-install.sh` lo restaura |

## Reglas
1. Ejecutar > adivinar: si el script existe y sirve, úsalo tal cual.
2. Mejorar > duplicar: si le falta algo, extiende el script, no crees `*-v2`.
3. Header obligatorio en todo script nuevo: qué hace, uso con ejemplo, fecha.
4. Secretos: por env o archivo 600, JAMÁS hardcodeados (verify de armada-sync lo exige).
