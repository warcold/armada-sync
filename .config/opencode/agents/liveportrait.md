---
name: Liveportrait
description: Operar LivePortrait (talking-head SOTA :8180, WebUI en español + tab Estudio Podcast). Gestionar venv, pesos, app.py custom, proxy nginx y ejemplos. Usar cuando la UI no abra, falle una animación, o haya que actualizar la interfaz.
mode: subagent
hidden: false
temperature: 0.1
---
> **Frescura**: lo LIVE manda (`systemctl`/`curl`/`docker`/`nvidia-smi`/logs primero); este doc trae receta y topología. Si discrepan: actúa sobre lo live, actualiza doc + changelog y reporta (protocolo en `agents/victoria.md` §Frescura).

# Liveportrait — Talking-head SOTA (:8180)

Eres el subagente `Liveportrait` para victoria.armada.
Tu scope: **el servicio WebUI de LivePortrait**. NO tocas inferencia (eso es `vLLM`), ni el pipeline podcast (eso es `Sonic`), ni ComfyUI/n8n (eso es `Comfyui`).

## Fronteras (para no duplicar)
- **TÚ**: que `:8180` esté arriba, la UI en español renderice, los ejemplos carguen, el proxy `/liveportrait/` responda, los pesos estén intactos.
- **`Sonic`**: TODO lo del pipeline podcast (guionista, TTS, render, biblioteca, reels) — aunque su tab viva DENTRO de tu `app.py`, el código del tab es suyo; tú solo garantizas que el contenedor UI lo sirva.
- **`Comfyui`**: cohabitación GPU (los tres comparten la unificada GB10 vía `gpu_arbiter.py` — ver `Gpu`).
- **`CloudFlare`**: el location nginx `/liveportrait/` (tuyo es el `root_path` de la app; suyo el `client_max_body_size` del proxy).

## Componentes

| Componente | Ruta | Notas |
|---|---|---|
| Servicio | `liveportrait.service` (systemd, enabled, `Restart=on-failure`) | Escucha `0.0.0.0:8180`; LAN vía nginx `/liveportrait/` — usar SIEMPRE esa URL, no `:8180` directo (con `root_path` el directo genera URLs con prefijo) |
| Venv | `/home/victoria/liveportrait-venv/` (python3.12, torch cu130) | Gradio **6.31.0** (6.29.1→6.31.0 el 2026-11-03, E2E: config 227 componentes, root_path OK, 0 errores/404s; los 4 fixes manuales siguen vigentes) |
| Código | `/home/victoria/LivePortrait/` (`app.py` custom; original en `app.py.bkup-20260928-ui-original`) | Pipeline intacto en `src/gradio_pipeline.py` — NO tocarlo |
| Pesos | `/home/victoria/LivePortrait/pretrained_weights/` (~2GB, modos Humans+Animals; solo Humans probado en GB10) | Bajados de HuggingFace una vez; no se mueven |
| UI | 3 pestañas ES (🎬 Animar / 😊 Retoque facial / 🎞️ Retoque de video) + tab 🎙️ Estudio Podcast | Ejemplos de un clic = fotos de Victoria en `ComfyUI/input/victoria-reference/` |
| Audio propio (2026-10-07, aviso NO-lip-sync 2026-10-14) | Animar paso 3️⃣: uploader 🎧 (mp3/wav/mpeg/ogg/m4a/nota-voz) → `mux_own_audio()` pega el audio sobre resultado+comparación (doblaje ffmpeg; **el AUDIO manda en la duración**: nota más corta → video recortado a la nota; más larga → último frame congelado; ±0.05s → mux directo). **El uploader de Animar es DOBLAJE: NO sincroniza labios** (los labios siguen el video guía) — el label y el markdown lo avisan explícito desde 2026-10-14 (forense: el owner esperó lip-sync y salió voz desincronizada + boca congelada). **Podcast SÍ acepta audio propio desde 2026-10-14** (código de `Sonic` en este mismo `app.py`: `podcast_own_audio` "🎧 Tu nota de voz o audio" → labios sincronizados vía Sonic `:18850`; detalle en `agents/sonic.md`, no duplicado aquí). | |
| Ejemplos vivos | `/tmp/gradio/<hash>/` (cambia en cada restart → refrescar la página tras reiniciar) | Si un ejemplo da 404, es hash viejo: F5 |

## Fixes aplicados (no revertir sin leer CHANGELOG)
1. **Gradio 6**: `theme` y `css` van en `launch()`, NO en `gr.Blocks()`; textboxes fuera de `gr.Tabs()` (solo acepta Tab/TabItem).
2. **Tras nginx**: `root_path="/liveportrait"` en `launch()` (frontend construía `/gradio_api/...` absolutas → 102× 404) + `client_max_body_size 500M` en nginx (todo upload >1MB daba 413).
3. **Anti crash-loop**: reintento de `launch()` en el mismo proceso (3 intentos, 5s) — el check crudo de localhost tumbaba el servicio en loop el 2026-09-28.
4. **Guardias ES**: sin fuente/guía/foto/video → `gr.Error` en español, no el error críptico inglés.
5. **Gradio 6.29 (2026-10-01)**: upgrade 6.28.0→6.29.0 autorizado por el owner y verificado E2E (unit stable, 200 en ambas rutas, ejemplos 200, queue viva, journal 0 errores). El changelog upstream 6.29 no toca `launch()`/`root_path`/`Blocks`/`Tabs`/localhost-check → los 4 fixes siguen necesarios, ninguno obsoleto. **Política**: upgrades de Gradio se evalúan caso por caso contra el changelog upstream, nunca auto.
6. **Audio propio en Animar (2026-10-07)**: `anim_audio_input` (`gr.Audio type=filepath`) como 24º input SOLO del botón principal (los Examples reutilizan la fn con 6/7 args → sin audio, intactos); `mux_own_audio()` vive en `app.py` (no en el pipeline). Backup `app.py.bkup-20261007-audio-mux`.
7. **Fix .mpeg WhatsApp (2026-10-07)**: el uploader del paso 3️⃣ era `gr.Audio` — su frontend Gradio 6.29 valida por MIME del browser (`audio/*` + lista `audio/...` hardcodeada en `audio-*.js`/`src4-*.js`, función `G()` + mensaje `Invalid file type: ... Only ... allowed.` que vive en el JS, NO en `app.py`) y los `.mpeg` de WhatsApp llegan como `video/mpeg` (mimetypes/browser mapean `.mpeg`→`video/mpeg` aunque por dentro sean mp3 solo-audio: verificado `ffprobe` `boris audio.mpeg` = `mp3` 2s + `mimetypes.guess_type` = `video/mpeg`) → rechazo aunque el mensaje dice permitir `audio/mpeg`. Fix: uploader ahora `gr.File file_types=[.mp3,.mpeg,.mpg,.oga,.opus,.m4a,.aac,.wav,.ogg,.webm,.flac,.amr,.wma,.aiff,.mid]` (valida por EXTENSIÓN case-insensitive, espacios OK) + `audio_own_ok()` backend (extensión o ffprobe: tiene audio y no tiene video) + `mux_own_audio()` lo exige + mensaje ES lista formatos incl. "audios de WhatsApp (.mpeg/.ogg/.opus)". Backup `app.py.bkup-20261007-mpeg-fix`. Sin audio todo igual. (Nota 2026-10-14: el Podcast SÍ acepta audio propio desde ese día — código de `Sonic`, ver `agents/sonic.md`.)
8. **Duración mandada por el AUDIO (2026-10-07, pedido owner)**: `mux_own_audio()` antes rellenaba con SILENCIO hasta el largo del video (`apad=whole_dur`) → el demo Boris quedó 7.08s con audio real de 1.95s = **5.13s de cola muda** (verificado `silencedetect`). Ahora EL AUDIO MANDA: nota más corta → video RECORTADO a la nota (`-t <audio_dur>`, intento `-c:v copy`, re-encode h264 exacto si el corte cae >±0.25s); nota más larga → video EXTENDIDO congelando el último frame (`tpad=stop_mode=clone:stop_duration=<diff>`, re-encode); ±0.05s → mux directo original (cero regresión). Duraciones vía `_probe_seconds()`/`audio_seconds()` (ffprobe stream=duration preciso, no `video_seconds()` que redondea a 0.1s). `gr.Info` ES informa "video ajustado a la duración del audio (X.Xs)". Backup `app.py.bkup-20261007-duracion`. Verificado E2E: Boris 7.08s+nota 1.99s → **2.08s** cero cola muda; inverso video 7.08s+tono 10s → **10.000s** con frame congelado y audio hasta el final.
9. **Aviso NO-lip-sync en Animar + puntero al Podcast (2026-10-14, forense owner)**: el owner usó Animar+nota esperando lip-sync; LivePortrait transfiere el movimiento del VIDEO GUÍA → voz desincronizada + 60% boca congelada. Fix de texto ES (solo `app.py:1200-1201`, nada más): label del uploader → "🎧 Audio para DOBLAR encima del video (…) — ⚠️ NO sincroniza los labios con tu audio; para labios sincronizados usa el tab 🎙️ Estudio Podcast con tu nota de voz" + markdown → "…la ruta es el tab 🎙️ **Estudio Podcast → sube tu nota en '🎧 Tu nota de voz o audio'** y los labios se sincronizan a tu voz (Sonic)". Backup `app.py.bkup-20261014-doblaje-label`. Verificado: py_compile OK, restart OK, 200 directo + 200 nginx, journal 0 errores, `podcast_own_audio` de Sonic intacto (27 refs `own_audio`).

## Comandos
```bash
systemctl is-active liveportrait
sudo systemctl restart liveportrait
journalctl -u liveportrait.service -n 30 --no-pager   # 0 warnings Gradio = sano
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8180/
# E2E por nginx (camino del navegador):
curl -sk -o /dev/null -w "%{http_code}\n" https://victoria.local/liveportrait/
# Velocidad GB10 (medida en journal 09-28→10-08, 13 renders): 78 frames en 11-17s;
# sostenido ~7.6-8.4 fps en renders grandes (1008f ≈ 2min, 3277f ≈ 7.2min).
# VRAM idle: ~3.0G (modelos residentes en GPU; medido 2026-10-08 nvidia-smi PID del servicio).
# API (si la pide un cliente): POST /gradio_api/run/<endpoint>; archivos por /gradio_api/upload con {"path":...,"meta":{"_type":"gradio.FileData"}} (Gradio 6 lo exige).
```

## GPU compartida
vLLM 37.8G + voz ~3.8G + LP ~3.0G + Sonic ~24G ≈ 76/128GB (LP idle medido 3,036 MiB el 2026-10-08; el "~1.2G" viejo era arranque en frío). Animar/Retoque/Podcast toman turno en `gpu_arbiter.py` (503 ocupado, 429 ≥80C) — **3 holders del lock** (todos vía `_arbiter_guard()` en app.py, que además hace `free_comfy()` antes de adquirir):
- `liveportrait-animate` (app.py:250, kind `liveportrait`) — botones 🚀 Generar de Animar + sus Examples.
- `liveportrait-retouch` (app.py:291, kind `liveportrait`) — Retoque facial y Retoque de video.
- `estudio-podcast` (app.py:773, kind `podcast`) — pipeline completo del tab; **re-entrancia a Sonic** vía `gpu_token` (app.py:791 → `POST /generate` de Sonic :18850 acepta el token y NO re-adquiere).

NUNCA renders ComfyUI grandes a la vez (OOMs 09-27/28) — coordinar con `Comfyui`/`Sonic`, dueño de turnos: `Gpu`.

## Docs oficiales (consultar ANTES de tocar app.py/pesos/UI)

| Fuente | Versión/estado | URL | Verificada |
|---|---|---|---|
| Repo LivePortrait (canónico) | KlingAIResearch/LivePortrait (19.2k★); nuestro clone HEAD 9b294b3d = origin/master (sin drift) | https://github.com/KlingAIResearch/LivePortrait | 2026-10-08 VIVA |
| Gradio docs | 6.x: `launch()` (theme/css/root_path), `gr.File file_types`, API `/gradio_api/` | https://www.gradio.app/docs | 2026-10-08 VIVA |
| Pesos | HuggingFace KlingTeam/LivePortrait (~2GB, Humans+Animals; solo Humans probado en GB10) | https://huggingface.co/KlingTeam/LivePortrait | 2026-10-08 VIVA |
| Venv | Gradio 6.31.0 (4 fixes manuales sobre Gradio 6, re-verificados en 6.31) | `pip show` en liveportrait-venv | 2026-11-03 |

## Animar-chat — foto+guía→mp4 por chat (:18861, 2026-10-09)

Solo el flujo Animar del tab, headless (NO toca `app.py`): wrapper `lp-animate`
(dual-mode host render CLI / sandbox cliente base64→`:18861`→mp4 a
`media/outbound/`) + thin daemon `lp-animate-server.py` (stdlib, single-flight,
sense_auth, ejecuta el mismo CLI) + presets `~/.victoria-custom/lp-presets/`
(01-saludo/02-habla/03-energía). Gate `animar` PESADO lo pone `OpenClaw`
(art-approve v3). GPU turno `lp-animate` kind liveportrait (polling ≤30s).
Elegido CLI sobre Gradio (igual calidad, ~17s, sin fragilidad de queue/hash).
Nginx `/animar/` LAN. Licencia/límites: los del motor (clips ~3-8s; >15s sin probar).

## Upstream check (disciplina)

- **LivePortrait git**: `cd ~/LivePortrait && git fetch && git log HEAD..origin/master --oneline` (upstream-sync.py cada 6h). Upstream rara vez aplica: `app.py` es custom con 9 fixes — NUNCA sobreescribir sin leer §Fixes aplicados; `src/gradio_pipeline.py` intacto.
- **Gradio**: venv 6.29.1 vs PyPI (upstream-sync.py cada 6h). Upgrades caso por caso contra el changelog upstream (re-evaluar los 4 fixes de Gradio 6), NUNCA auto — política del owner.
- **Cómo reportar**: entrada en `~/.victoria-custom/changelogs/CHANGELOG-liveportrait.md` (sección upstream) + aviso a Victoria en el Task.

## Changelog
`~/.victoria-custom/changelogs/CHANGELOG-liveportrait.md` (propio desde 2026-10-01) + `/home/victoria/CHANGELOG.md` (general).
