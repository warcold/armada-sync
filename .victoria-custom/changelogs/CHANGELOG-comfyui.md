# CHANGELOG — Contenido visual (ComfyUI :8188 + n8n :5678)

### [2026-10-26 18:40 EDT] [comfyui+n8n] ComfyUI 0.39.1→0.42.0 (114 commits, dep nueva comfy-kitchen) + n8n 2.42.5→2.44.7
- **Tipo**: update (autorización owner "llevemos todo a lo último"; parte del upgrade general 2026-10-26 18:40 del general)
- **Que**: (1) **ComfyUI 0.39.1 → 0.42.0** (git pull 114 commits: frontend 1.57.4, MOSS-Image, Branch node, Flux2 VAE vía kitchen, partner-nodes proxy fix). **Dep nueva OBLIGATORIA `comfy-kitchen==0.2.40`** — el requirements.txt separó kitchen de aimdo; sin ella crash-loop `ModuleNotFoundError: No module named 'comfy_kitchen.int8_decode'` (RestartPolicy revivía cada ~8s). También `comfy-aimdo 0.5.6→0.6.0`. **Lección para el próximo update**: requirements.txt de ComfyUI lista DOS paquetes propios (aimdo + kitchen) — instalar/actualizar AMBOS antes de reiniciar. (2) **n8n 2.42.5 → 2.44.7** (docker pull latest + recreación con config exacta: env N8N_HOST=victoria.local/PORT/PROTOCOL=https/GENERIC_TIMEZONE + volumen /home/victoria/n8n-data + bridge + 5678 + restart unless-stopped).
- **Verificado**: ComfyUI HTTP 200 en ~30s post-fix, 0 errores en el proceso actual (los 34 del journal eran del crash-loop pre-kitchen), API nodos OK (CheckpointLoaderSimple), /system_stats reporta **v0.42.0** · n8n HTTP 200 + versión 2.44.7 + datos preservados.
- **Impacto**: comfy-venv (+comfy-kitchen 0.2.40, aimdo 0.6.0), ComfyUI/ (git), contenedor n8n recreado.
- **Docs**: yes (general 18:40 + AGENTS.md §11 + este).

### [2026-10-26 14:00 EDT] [comfyui] --reserve-vram 8 vía drop-in systemd (default 400MB insuficiente en UMA compartida)
- **Tipo**: fix + infra (autorización owner "procede con todo"; parte del paquete P0 anti-muertes)
- **Que**: drop-in `/etc/systemd/system/comfyui.service.d/reserve-vram.conf` añade `--reserve-vram 8` al ExecStart de comfyui.service. En memoria unificada el default Linux de ComfyUI reserva solo 400MB (diseñado para GPU discreta con RAM aparte) — insuficiente compartiendo 121GB con vLLM 49GB + Hunyuan 10.9GB + Sonic 5.3GB + flota; sin reserva, ComfyUI puede empujar al OS a presión (patrón OOM 09-27/28). Hallazgo de la evaluación estratégica 2026-10-26 (foro NVIDIA 360336: NO usar --highvram en UMA).
- **Verificado**: restart OK, HTTP 200 en :8188, flota completa activa (liveportrait/sonic/gateway/gpu-saver), journal sin errores.
- **Impacto**: comfyui.service (via drop-in, unit original intacto). Costo: algo más de recarga de modelos entre generaciones.
- **Docs**: yes (general 14:00 + este + AGENTS.md §4).

### [2026-10-19 00:45 EDT] [hunyuan3d] Consumo externo VERIFICADO: kalimete genera GLB por HTTP (image_b64) con su llave — pipeline games end-to-end
- **Tipo**: feature/verificación (cero cambios al servicio; autorización owner 2026-10-19)
- **Que**: Hunyuan3D-2 (:18860) queda abierto como recurso de la granja para kalimete (Game Studio): la llave `kalimete` (coder + caps `llm/art/tts/whisper`) pasa `sense_auth` por elevación de la cap `art`. Kalimete NO necesita rutas del FS de Victoria: `POST /generate {"image_b64", "face_count"}` → GLB → `GET /file/<n>.glb`. Skill `assets-3d` creada en kalimete con la receta (face_count 10-20k para assets de juego, 503 busy=single-flight, 429=árbitro GPU).
- **Por qué**: el Game Studio de kalimete marcaba "image→3D Fase 2 pendiente auth owner" — ya estaba desplegado desde 2026-10-09; solo faltaba documentar el acceso externo. Pipeline completo de juegos verificado: concept art (art API) → GLB 3D → Godot (import nativo) → QA visual (VLM).
- **Verificado E2E desde kalimete** (red real, LAN): concept art z-image-turbo (job art-15874939504eb7d3, ~25s, 1.2MB) → Hunyuan3D `image_b64` → `{"ok":true, "seconds_taken":46.4, "verts":284458, "bytes":3635724}` → GLB descargado en kalimete, magic `glTF` OK (3.5MB). VLM describió la imagen en ES vía `/v1/chat/completions` con `image_url`.
- **Docs**: yes (skill assets-3d + game-studio + victoria-server + harness en kalimete; AGENTS.md §Hunyuan3D + victoria.md §granja kalimete aquí; esta entrada + general)

### [2026-10-09 02:20 EDT] [hunyuan3d] NUEVO: Hunyuan3D-2 image-to-3D local (:18860) + Blender + art-3d
- **Tipo**: feature (autorización owner "procede con todo"; grupo 4 Contenido)
- **Que**: Tencent Hunyuan3D-2 image-to-3D LOCAL (foto → GLB con textura, 2 etapas DiT-mini-turbo shape + Paint-turbo): venv `hunyuan-venv` (py3.12, torch 2.14+cu130, transformers **4.57.1** + diffusers **0.32.2** pineados — 5.x/0.41 rompen el load), `custom_rasterizer`+`mesh_processor` compilados ARM64 OK, daemon `hunyuan-server.py` (:18860, single-flight, sense_auth, gpu_arbiter `hunyuan3d-standalone`), unit `victoria-hunyuan3d.service` (enabled, ENV LD_LIBRARY_PATH torch/lib — sin esto libc10 ImportError), nginx `/hunyuan3d/` LAN, wrapper `art-3d` (base64 + descarga GLB + retry 429 solo, espejo sandbox OK), skill `hunyuan3d`, `ensure_hunyuan3d()` en ensure-loop (servicio + wrapper + skill anti-rebuild), Blender 4.0.2 apt + addon oficial + python3-numpy/requests. Licencia Tencent Community (techo 1M MAU, no EU/UK/KR).
- **Por qué**: alternativa local a Meshy (sin cuentas/créditos/límites) para avatares 3D de Victoria. Límite honesto: mesh ESTÁTICO — el avatar animado es art-3d → Blender rig → LivePortrait/Sonic.
- **Impacto**: grupo 4; pesos HF ~10G; puerto 18860; nginx +1 location; ensure-loop +1 función (syntax OK, loop active).
- **Verificado**: shape GLB 720KB + textured 3.5MB/3.8MB/4.1MB E2E (servicio 44.8s, wrapper 52.1s), /health + /file 200, LAN https 200, sandbox `art-3d health` OK, Blender headless importa GLB (27K verts/40K caras/1 mat) + .blend guardado. MCP bridge Blender diferido (siguiente paso).
- **Docs**: yes (comfyui.md §Hunyuan3D-2 + scope, harness servicio añadido, esta entrada + general)

### [2026-10-08 17:10 EDT] [comfyui] Deep treatment: medición LIVE completa + limites_vigentes en harness + /free documentado
- **Tipo**: docs + medición (cero cambios de servicio: nada reiniciado, nada instalado, modelos intactos)
- **Que**: (1) `medicion_live` + `limites_vigentes` agregados a `comfyui.harness.json` (cerrando el gap de la entrada 15:05). (2) Derivas del `comfyui.md` curadas contra LIVE: custom nodes 8→**6** (los 3 de video eliminados 09-28; RMBG nuevo; versiones git de los 6), inventario "~202 GB/42 archivos (2026-08-15)"→**108G verificado con du** (~35 archivos), sección "Versión actual" 651ca296→**46493d82** con deps venv reales (aimdo 0.5.6, kitchen 0.2.37, frontend 1.55.14, templates 0.11.78). (3) **Comportamiento del `/free` documentado** (verificado con curl): con body JSON → **200 + body VACÍO (0 bytes) por diseño** (server.py ~1274); SIN body → **500** (JSONDecodeError no manejado). El body vacío ES el éxito → los 2,863 warnings del gpu-saver son falsos positivos del consumidor (`_curl_json` trata stdout vacío como fallo); fix corresponde al agente Gpu, NO a ComfyUI.
- **Medición LIVE**: ComfyUI v0.39.0-29-g46493d82 (banner+git), torch 2.11.0+cu130, Python 3.12.3, cola vacía, VRAM libre 5.2G reportada. Modelos 108G: diffusion 56G / checkpoints 15G / text_encoders 13G / controlnet 12G / resto ~7G; loras+upscale+animatediff VACÍOS. n8n 2.42.5 @ sha256:f6dc0d15, 0 workflows, 200 directo (3ms) + vía nginx (8ms). **E2E art API**: z-image-turbo 512×512 → 202 → done ~16-21s → `art-zimage_00045_.png` 245K → download 200 PNG válido. Nota cosmética: `elapsed_s` del job sigue corriendo tras done (calculado live en cada GET, gateway:2176).
- **Límites verificados en código** (gateway:1946-1948): 2 img + 1 video concurrentes globales, 30 jobs/h por llave (429 art_rate_limited + Retry-After 300), cola llena 429 art_busy (Retry-After 30), árbitro GPU 429 gpu_busy (Retry-After dinámico), nginx client_max_body_size 500M.
- **Verificado**: harness JSON válido (`json.tool`), `opencode agent list` → Comfyui sano, doc-fresh --mark-ok, E2E real con llave admin (no expuesta).
- **Docs**: yes (esta entrada; Victoria escribe la general)

### [2026-10-08 15:05 EDT] [comfyui] Restructuring agente Comfyui (patrón vLLM): docs oficiales + versión STALE curada
- **Tipo**: docs + refactor
- **Que**: §API de `comfyui.md` decía "stack actual: master 651ca296, 2026-10-01" → **v0.39.0 @ 46493d82, verificado 2026-10-08** (deriva STALE del update de hoy 13:15). §Docs oficiales (docs.comfy.org + docs.n8n.io — verificadas vivas) + §Upstream check agregados; idem bloques en `comfyui.harness.json`.
- **Verificado**: JSON válido, doc-fresh Comfyui FRESH.
- **Gap profundo pendiente**: medición LIVE en el harness (inventario modelos ~109G verificado, versiones custom nodes, n8n workflows).

### [2026-10-08 13:15 EDT] [comfyui] ComfyUI v0.39.1 (31 commits: fix Qwen MTP + aimdo 0.5.6) + n8n 2.42.5
- **Tipo**: maintenance
- **Que**: ComfyUI `5c460d81→46493d82` (v0.39.1; destacan: "Fix Qwen3.5 MTP embedding offload #16877", "Comfy Aimdo 0.5.6 + Fix qwen 2.1 rogues in low VRAM #16870", partner nodes Kling/ClarityAI/Vidu). Venv: frontend 1.55.14, workflow-templates 0.11.78, comfy-aimdo 0.5.6, cryptography (nueva dep). n8n `2.41.6→2.42.5`: docker pull + recreate (mismo bind n8n-data, :5678, env N8N_*); migraciones OK; label `victoria.group=contenido` añadido al recrear.
- **Verificado**: comfyui active, `/system_stats` 200, journal limpio (aimdo 0.5.6 cargado), E2E art API z-image-turbo → done ~10s; n8n 200 LAN (`/n8n/`) + directo :5678, DB intacta.
- **Docs**: yes (general + AGENTS.md aimdo)


> Servicios: `comfyui.service` + contenedor `n8n` (HOST/Docker, GPU unificada GB10)
> Subagentes: `Comfyui` (`~/.config/opencode/agents/`)
> Nota: LivePortrait (`CHANGELOG-liveportrait.md`) y Sonic (`CHANGELOG-sonic.md`) tienen changelog propio desde 2026-10-01; grupo/migración/legacy siguen aquí
> Scripts host: `comfyui-monitor.py` (mover/downloader ELIMINADOS 2026-09-28)
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

---

### [2026-10-05 00:30 EDT] [comfyui] Update 651ca296->5c460d81 (v0.38.0) + n8n 2.41.6 — E2E OK 15.3s
- **Tipo**: update (owner: full updated)
- **Que**: git pull 25 commits (assets DB fixes, comfy-kitchen 0.2.37, workflow-templates 0.11.76, partner nodes, --offline flag, pinned-memory off en GPUs integradas). Tracked diff local = 0 (nuestro stuff untracked: backup/checkpoints/workflows/custom_nodes). venv: pip install comfyui-workflow-templates==0.11.76 + comfy-kitchen==0.2.37. n8n: imagen latest recreado con config identica (bridge/5678/unless-stopped/bind n8n-data/env) -> 2.41.6, data intacta, 200.
- **Verificado**: comfyui active + http 200 + system_stats v0.38.0; E2E arte via sandbox->art-bridge->gateway: gatito z-image-turbo 736KB en 15.3s; n8n 200 + version 2.41.6.
- **Docs**: yes (general 00:30)


### [2026-10-01 02:20 EDT] [comfyui] Update 250b2e95→651ca296 (autorizado, verificado, modelos intactos)
- **Tipo**: update (autorización explícita del owner)
- **Que**: `git pull --ff-only` en `~/ComfyUI` (árbol limpio salvo untracked pre-existentes backup/checkpoints/workflows de ago/sep, no tocados) + `restart comfyui`. Sin renders de prueba (GPU compartida con vLLM en producción).
- **Verificado**: HEAD 651ca296 (= upstream), unit active, API `/system_stats` 200 (v0.34.0), `models/` 108G intactos. Sin rollback. Doc `comfyui.md` sin refs de versión → sin cura necesaria; harness Gradio 6.28→6.29.0.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 01:00 EDT] [changelog] Split Sonic + doc validada
- **Tipo**: docs (organización)
- **Que**: las 9 entradas [podcast] 09-29 mudadas a `CHANGELOG-sonic.md` (propio de `Sonic`); refs a `Comfyui.md`; `Sonic.md`/`Comfyui.md` apuntan a su changelog. Este archivo queda con ComfyUI/LivePortrait/n8n + grupo + legacy.
- **Docs**: yes (general + sonic + esta entrada)

### [2026-09-30 09:45 EDT] [contenido] Árbitro GPU (turnos) + guardián térmico + AUTO por audio
- **Tipo**: fix (sostenibilidad) + feature (calidad) — causa del apagón 09:19: LivePortrait 15s llevó GPU a 96% + 78C con Sonic/Comfy/vLLM residentes → freeze + corte duro (journal corrupto, sin logs previos = firma eléctrica, no OOM; swap 55Gi libre lo descarta)
- **Que**: nuevo `~/gpu_arbiter.py` (stdlib, lock `/home/victoria/logs/gpu-heavy.lock` 5h stale, re-entrante podcast→Sonic vía `gpu_token`, `check_ready`: lock ajeno→503, temp≥80C→429, Comfy en cola→503, `free_comfy` pre-vuelo). `sonic-server.py`: respeta turnos + libera Comfy antes + suelta lock en finally. `LivePortrait/app.py`: Animar/Retoque-video/Podcast toman turno; Sonic recibe el token del podcast (no se auto-bloquea). `victoria-gpu-saver.py`: `_thermal_tick` cada 30s (warn 75C + /free, block 80C + /free, limpia locks stales). Unit Sonic: `StartLimit*` movidas a `[Unit]` (estaban ignoradas). `sonic-venv`: instalado `accelerate 1.15.0` (carga 21s→11s, menos RAM).
- **AUTO (mejor práctica redes 2026)**: el AUDIO manda, el video lo sigue (como HeyGen/CapCut/Opus). Nuevo default `AUTO · Lo que dure el guión` (idea completa 60-110 palabras, cap 1100 chars/~85s; >120s pide partir). Guionista AUTO no recorta agresivo + hook en 2 frases. Pre-escucha AUTO informa calce (`platform_fit`: TikTok 7-60s / Reels 15-90s / Shorts 20-65s, sweet spot 25-45s) + tiempo de render. Fijos 15/30/60 siguen. Biblioteca guarda `duracion_objetivo_s=audio real` en AUTO.
- **Verificado**: `py_compile` ×4 OK; mutex cross-process (holder bloquea, libera OK); `check_ready` libre; `gpu_arbiter.status()` `{temp 47C, util 0%, comfy False, lock None}`; saver+sonic+liveportrait+comfy `active`; Sonic `/health` loaded; LP `:8180` 200; pipeline Sonic 11s con accelerate.
- **Docs**: yes (esta entrada + general + subagents Comfyui/Sonic pendientes de sync)

### [2026-09-29 22:00 EDT] [docs] Comfyui saneado + header grupo Contenido
- **Tipo**: docs
- **Que**: `victoria-comfyui.service` → `comfyui.service`; `--listen 0.0.0.0` → `127.0.0.1`; `/studio/` → `/comfyui/`; mover/downloader → procedimientos "a mano"; vLLM 49.4→37.8GB; banner ELIMINADO en Estudio legacy; sección Changelog al inicio. Header de este changelog: ahora cubre los 4 servicios del grupo (ComfyUI+LivePortrait+Sonic+n8n). Detalle en CHANGELOG general misma fecha.
- **Verificado**: `comfyui.service` enabled/active, `:8188` en 127.0.0.1, nginx `/comfyui/` OK.
- **Docs**: yes

### [2026-09-28 19:20] MIGRACIÓN MAYOR: video LTX eliminado + LivePortrait (:8180) + n8n (:5678) + ComfyUI solo-imágenes + roles por herramienta + vLLM 160K
- **Tipo**: infra (migración) + cleanup
- **Que**: ~198GB modelos video borrados (LTX/WAN/SCAIL/AnimateDiff/SAM). LivePortrait SOTA instalado (venv cu130, WebUI :8180, inferencia 10s vs 4min LTX). n8n orquestador (:5678 Docker). ComfyUI full-feature para imágenes (:8188). vLLM 0.22/160K (3.8GB libre). nginx 3 rutas nuevas. Roles: liveportrait/comfyui/xtts/whisper/n8n. Landing nueva.
- **Verificado**: 12/12 servicios OK. E2E LLM OK. 50.5GB RAM disponible.
- **Docs**: yes (CHANGELOG general + docs en progreso)

### [2026-09-28 09:50] 3er freeze (prueba 1088×1920) — revert a config probado (448→896, 3σ) + guard EN VIVO (<8GB → /interrupt) + ancla 900×1600 y copy-concat conservados
- **Tipo**: fix crítico
- **Que**: 1088×1920 con 6σ no cabe con vLLM cargado (RAM 6.1GB → freeze). Revert al config del run 08:15 (6 chunks sin freeze). Guard en vivo MEM_ABORT_GB=8 aborta renders antes de congelar. Ancla 916 regenerada a 900×1600; concat -c copy; crf17+unsharp. Regla: nada de configs de GPU sin el owner mirando.
- **Docs**: yes (CHANGELOG general + Comfyui.md)

### [2026-09-28 04:20] FORENSE freeze 03:25 — válvula /free rota (gpu-saver llamaba /api/free=404) + anti-freeze entre chunks (free+espera memoria ≥24GB, ram_guard <12GB aborta)
- **Tipo**: fix crítico (estabilidad)
- **Que**: chunk 1 con estado del chunk 0 caliente → RAM 93.1% → gpu-saver dispara /free a URL inexistente → 0 liberado → freeze. Fixes: gpu-saver `POST /free` correcto (unload_models+free_memory, HTTP 200 verificado); generator `comfy_free_and_wait()` entre segmentos + `ram_guard()` antes de cada render (aborta limpio si <12GB); ETAs honestos.
- **Verificado**: forense read-only, py_compile ×3, /free 200 con cola vacía, gpu-saver activo, :8190 200. E2E: owner.
- **Docs**: yes (CHANGELOG general + Comfyui.md)

### [2026-09-28 01:05] FIX deriva de labios del chunked (targeting acumulado: cada segmento cierra en su tiempo de audio global; ±0.16s no acumulativa) + limpieza intermedios + docs sync
- **Tipo**: fix + docs
- **Que**: el v1 sumaba +0.35s por chunk (labios ~1s fuera al final) → frames 8n+1 al ACUMULADO más cercano, cola solo en el último; validado en seco ×6 duraciones; intermedios chunk*/concat* se limpian; Comfyui.md y AGENTS.md §11 actualizados (chunked + single-flight).
- **Verificado**: py_compile + simulación del planner (asserts). E2E: owner.
- **Docs**: yes (CHANGELOG general)

### [2026-09-28 00:40] MODO CHUNKED (refine por segmentos ≤89f, cortes en silencios) + SINGLE-FLIGHT global (botones se bloquean mientras hay trabajo)
- **Tipo**: fix (calidad) + feature (protección)
- **Que**: el long-sin-refine daba video granulado/blando (sin el pase de detalle) → videos >89f ahora van por segmentos ≤89f CORTADOS EN SILENCIOS con pipeline completo (refine, limpio a esa longitud) + concat con audio TTS original; single-flight global: 1 trabajo de cualquier tipo a la vez, botones bloqueados/liberados solos, 429 amable, redirect a Galería. ETAs recalibrados.
- **Verificado**: en seco (chunks ≤89f con TTS real, py_compile, node --check, HTML servido). E2E: owner.
- **Docs**: yes (CHANGELOG general)

### [2026-09-28 00:05] Selector de fotos: thumbs completos (contain 9:16 + badge ✓ elegida) + dedupe por contenido (md5+dhash, 22→7 poses; borrados 4 artefactos " (n).jpg")
- **Tipo**: fix (UX) + limpieza
- **Que**: thumbs antes `84px object-fit:cover` (47% de la foto visible) → ahora `aspect-ratio:9/16;object-fit:contain`; ctxcards igual; análisis por contenido reveló (1..4) = preps re-subidos, reference/ = symlinks, crop/ = dupes, *-916 = crops; reglas de filtro en fotos(); artefactos de upload borrados del disco.
- **Verificado**: picker 7 poses sin dupes (assert), thumbs servidos, img endpoint 200. Sin renders.
- **Docs**: yes (CHANGELOG general)

### [2026-09-27 23:40] Chat COPILOTO — fences tipados (```guion/```prompt/```voz) con botones que llevan a la pestaña correcta + 🎬 recrear video por link (/api/recreate → video-server :18811/analyze → adaptación LLM)
- **Tipo**: feature (chat)
- **Que**: CHAT_SYS v2 tipado + desambiguación + modo plan; renderReply enruta por fence (🎬 Video / 🖼 Imagen / 🎙 Voz); link en el chat → analyze (yt-dlp+whisper, keyless localhost) → guion adaptado al estilo de Victoria; chips plan/recrear/audiobook. Generar sigue siendo clic del owner.
- **Verificado**: requests reales (guion→```guion, portada→```prompt), recreate 400 en URL inválida, node --check ×2, py_compile.
- **Docs**: yes (CHANGELOG general)

### [2026-09-27 23:05] FIX tabs muertos — SyntaxError JS (regresión v5)
- **Tipo**: fix (regresión)
- **Que**: `chatWelcome` con `\n` real dentro de literal JS de comillas simples → SyntaxError → moría todo el `<script>` (tabs/chips/progreso). Fix: `\\n`. Verificado con `node --check` sobre los 2 bloques servidos + funciones presentes.
- **Docs**: yes (CHANGELOG general)

### [2026-09-27 22:40] PROTECCIÓN DE RECURSOS — 1 render pesado a la vez (Estudio FIFO + gate del generator)
- **Tipo**: feature (protección)
- **Que**: (1) Estudio: videos por fila FIFO con worker único + respiración 90s + tope 5; imágenes ≤2; voz ≤2; cancel saca de la fila; posición visible. (2) `wait_gpu_turn()` en victoria-video-generator.py espera turno si ComfyUI está ocupado (cubre CLI/agente). (3) Escalera: gpu-saver + watchdog. Sin pérdida de productividad (la fila sigue aceptando).
- **Verificado**: py_compile ×2 + checks + :8190 200. E2E: owner.
- **Docs**: yes (Comfyui.md + AGENTS.md §11 + CHANGELOG general)

### [2026-09-27 21:15] FIX MALLA DEFINITIVO — refine en tomas largas + lección freeze
- **Tipo**: fix (pipeline) + forense + infra
- **Que**: forense por aislamiento (VLM local como ojos, veredictos sobre crops idénticos): malla presente SOLO cuando el pipeline incluye refine Y la toma es larga (≤89f limpio; 265-289f malla; draft@289f y draft+upscaler@289f SIN refine limpios). FIX: `render_workflow` modo largo >97 frames sin refine (decode plano directo del upscaler, camino de diagF verificado); 3 `victoria-hablando-*` rewireados; `report.json` con `"mode"`. **Freeze 20:27**: renders de diagnóstico back-to-back congelaron el GB10; watchdog hardware rebotó solo y el stack auto-recuperó; lección: nunca renders pesados en cadena (Comfyui.md).
- **Verificado**: cirugía de workflow en seco (largo/corto), py_compile, JSON ×3. E2E: owner.
- **Docs**: yes (Comfyui.md + CHANGELOG general)

### [2026-09-27 21:10] Estudio v5 — chat visual, ideas RSS, progreso vivo, detener
- **Tipo**: feature (UX :8190)
- **Que**: chat con burbujas/bienvenida/chips/tips + contexto visual en mini-cards (reemplaza el select invisible); `POST /api/ideas` (25 titulares del blogwatcher → 5 ideas con bloques ```prompt — solo texto, aplicar es clic del owner); `track_progress` (paso/%/ETA en vivo, barra animada, poll 2.5s); `POST /cancel` (kill process-group + ComfyUI /interrupt, modal de confirmación). Guard de sesión extendido (api/ideas, cancel).
- **Verificado**: py_compile + 13 checks HTML + :8190 200 con UI nueva.
- **Docs**: yes (Comfyui.md §Estudio v5 + CHANGELOG general)

### [2026-09-27 15:30] FIX duplicación en videos (mosaico de caras / malla escamas) — causa en el LTX, no en el acabado
- **Tipo**: fix (parámetros de generación) + prompts + acabado + UI honesta
- **Que**: malla tipo escamas (phishing 11s) y mosaico de mini-caras (proxy's 28s/681f), presente YA en el `_ltx.mp4` crudo. Causa: nodo 25 strength 1.0 (mask 0, aplasta el refinado) + video_cfg 1.0 (default 3.0, negativo sin fuerza). Fix en `ltx25-av-template.json` + 3 `victoria-hablando-*`: strength→**0.5**, video_cfg→**3.0** (audio_cfg 1.0 intacto), negativo/positivo anti-duplicación; generator sin `unsharp` + aviso >721 frames; tutorial/tutorialxl experimentales en el Estudio. Fix MESH previo intacto (tile 1664, compression 33, euler, sigmas). Sin restart de servicios.
- **Verificado**: JSON ×4 OK, render en seco OK, py_compile ×3, ComfyUI 0.34.0 cola idle, Estudio :8190 200. E2E lo hace el owner.
- **Docs**: yes (este + CHANGELOG general + Comfyui.md §Video Generator)

### [2026-09-21 14:10] FASE 1 "Victoria hablando" — 3 workflows validados + prueba 12s OK
- **Tipo**: fix (workflows) + assets (fotos/audio) + validación E2E (sin installs, sin restart)
- **Que**: (1) NADA que instalar: los 26 tipos de nodo de victoria-hablando-* son CORE (LTXV* en `comfy_extras/nodes_lt.py`; ManualSigmas/TrimAudioDuration/ResizeImagesByLongerEdge absorbidos al core). ComfyUI-GGUF/KJNodes/Easy-Use NO se necesitan (UNETLoader+safetensors int8; `easy cleanGpuUsed` no se usa en estos graphs). GGUF y LTX-2.3 NO descargados (regla <2GB respetada: 0 bytes). (2) Fixes Avocado en los 3 JSON: `frame_rate` 24→25, `fps` 24→25, sampler `euler_ancestral`→`euler` (CFG 1.0 ya OK; lengths 337/401/713 ya 8n+1). (3) Fotos: creadas `input/victoria-Posing-916.jpg`, `victoria-916.jpg`, `victoria-Thinking-916.jpg` (720x1280 crop 9:16 de las fotos reales) — los nombres que los workflows ya referenciaban y no existían. (4) Voz: TTS `input/audio/victoria_prueba_12s_16k.wav` (16kHz estéreo, 14.65s, voz clonada Victoria vía :18810). (5) Hallazgo: `LoadImage` RECHAZA symlinks que apuntan fuera de `input/` (`is_within_directory` sobre realpath → "Invalid image file"); `victoria-reference/*.jpg` NO pasan validación — usar copias reales en `input/` (ej. `victoria-profile.jpg` raíz). (6) Ancla voz: `LTXVReferenceAudio` EXISTE en core pero NO se usa por diseño — el graph 2.5 es audio-driven (WAV TTS congelado con mask 0, video sigue al audio; `fit_audio` hace trim/pad solo); la identidad la pone el TTS clonado, y ReferenceAudio es "(ID-LoRA)" (requeriría LoRA de identidad que no tenemos).
- **Verificado**: prueba `victoria-hablando-12s-story` (foto `victoria-profile.jpg`, length runtime 369=8n+1 para 14.65s audio, seed 1201) → `success` primer intento de generación (intento 1 cayó en validación por el symlink, no por el modelo) → `output/victoria-prueba/victoria-prueba-12s_00001_.mp4` (9.9MB, 896x1600, 25fps, 14.76s, H.264+AAC). Loaders validados contra `object_info`: unet int8 21GB, gemma4-12b-proj 15GB, VAEs video+audio, upscaler en `latent_upscale_models/`, CLIP type `ltxv`.
- **Docs**: yes (este changelog + CHANGELOG general)

### [2026-09-18 19:00] Validación post-recreación sandbox — ComfyUI sin cambios
- **Tipo**: docs (verificación, sin cambios al servicio)
- **Que**: ComfyUI NO fue tocado durante la recreación del sandbox. Servicio enabled + active (auto-arranca tras reboot), torch cu130, 42 modelos (~202 GB), 8 custom nodes, templates Victoria intactos. GPU compartida con vLLM sin conflicto (headroom ~52GB).
- **Verificado**: `curl 127.0.0.1:8188/queue` → 200.
- **Docs**: yes (este changelog)
