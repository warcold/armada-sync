# Python — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `python3 --version`)
> **Docs oficiales**: https://docs.python.org/3.12/ (la versión que usamos)

## Versiones en uso (NO mezclar)

| Dónde | Versión | Nota |
|---|---|---|
| Sistema (host victoria) | **3.12.3** | gateway, daemons de sentidos, scripts |
| venvs (voice/comfy/liveportrait/sonic/hunyuan/video) | **3.12** | torch cu130/cu128 según servicio |
| Contenedores (sandbox Debian 13) | **3.13** | ⚠️ coqui-tts y deps con `Requires-Python <3.13` NO instalan ahí — por eso la voz vive en el HOST |

## Patrones que usamos

- venvs por servicio (`python3 -m venv`, deps pineadas en cada servicio)
- `sqlite3` stdlib para DBs pequeñas (gateway usa su propio módulo)
- `subprocess` sin shell=True en daemons expuestos (allowlist + args validados)
- `http.server`/`ThreadingHTTPServer` para daemons stdlib sin deps (sonic, hunyuan, lp-animate, whois)

## Gotchas descubiertos (lecciones)

- **3.13 en contenedores rompe paquetes con `Requires-Python <3.13`** — cualquier stack que requiera wheels viejos vive en el host con 3.12. (CHANGELOG 2026-08-17)
- **transformers 4.57.x vs 5.x**: los servicios de contenido pinean 4.57 (5.x rompe loads de DiT/XTTS-época). No subir sin probar. — (CHANGELOG-comfyui)
- **`os.environ["PATH"]` ya existe**: `setdefault(PATH)` no funciona — prependear con `os.environ["PATH"] = nuevo + ":" + viejo`. — (CHANGELOG 2026-08-18)
- **`wave` module no lee todos los WAV de ffmpeg** (headers variantes) — medir duración con `ffprobe -show_entries format=duration`, no con wave. — (lección 2026-10-27)
- **Imports de extensiones compiladas (custom_rasterizer)**: requieren `LD_LIBRARY_PATH=<venv>/lib/python3.12/site-packages/torch/lib` o ImportError libc10. — (AGENTS.md §11)

## Regla de actualización

Antes de subir Python/transformers/torch en cualquier venv: probar en el venv
afectado + E2E del servicio + changelog. Los pins existen por incidentes
documentados, no por capricho.
