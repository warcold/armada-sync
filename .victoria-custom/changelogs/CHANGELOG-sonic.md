# CHANGELOG — Sonic Podcast (:18850 + reels + Estudio Podcast)
### [2026-10-14 12:45 EDT] [sonic] Feature audio propio en Estudio Podcast (nota de voz del owner directo a Sonic)
- **Tipo**: feature — pedido del owner (fix de fondo del PLAN 2026-10-07; forense 2026-10-14: doblaje en Animar deja 60% del video con boca congelada porque LivePortrait transfiere movimiento del GUÍA, no del audio — el lip-sync real audio→labios SOLO lo hace Sonic).
- **Que**: el tab 🎙️ Estudio Podcast (`LivePortrait/app.py`, código del tab = frontera Sonic) acepta **audio propio** opcional: nuevo `gr.File` 🎧 + ayuda (formatos incl. WhatsApp + ETA ~60s/s a 15 steps/512px · ~100s/s a 25 steps/512px · ~180s/s a 640px). `gpu_wrapped_execute_podcast`/`_execute_podcast_locked` reciben `own_audio` (al final, sin romper orden): con audio → se valida con `audio_own_ok()` y se convierte al MISMO formato del wav del TTS (`ffmpeg -ar 22050 -ac 1 pcm_s16le`, verificado ffprobe sobre wav 2026-09-29) en el mismo path — el resto del pipeline (Sonic/whisper/ffmpeg/biblioteca) queda INTACTO. Guards: con audio el guión es OPCIONAL y los caps 1600/AUTO-1100 NO aplican; sin audio ni guión → error actual intacto; título default "Audio propio". Biblioteca: campo nuevo `audio_propio: bool` (con audio: guion "", prompt "", counts 0, sin fallback RSS inventado) y estado final dice "tu voz 🎧". `gpu_wrapped_preview_audio` SIN cambios (pre-escucha solo del guión). Uploader de Animar NO tocado (frontera Liveportrait).
- **Verificado**: `py_compile` OK; `restart liveportrait` active + 200 directo :8180 + 200 proxy `/liveportrait/` + 0 tracebacks en journal. **Mini-test E2E daemon** (GPU 53°C/0% pre-vuelo): ogg del owner → 3s wav 22050 mono → Sonic `steps 15 resolution 512` → `{"ok":true,"seconds_taken":140.9}` (~47s/s, mejor que el ETA ~60s/s) → mp4 512x512 h264+aac ~2.9s. Foto multi-cara: yoloface NO falló (render OK; qué cara eligió se verifica viendo el mp4). GPU post-test 65°C/0%.
- **Docs**: yes (sonic.md §Tab Podcast + sonic.harness.json pipeline/updated 2026-10-14 + esta entrada; general la escribe Victoria). doc-fresh Sonic `--mark-ok` hecho.
### [2026-10-08 16:50 EDT] [sonic] Deep treatment: medición LIVE (VRAM/tiempos/pesos) + limites_vigentes en harness
- **Tipo**: docs + medición (SIN disparar render — journal/du/nvidia-smi/código)
- **Que**: `sonic.harness.json` ahora tiene `medicion_live` + `limites_vigentes`: (1) **Versiones LIVE**: repo c1bd2d13 (= origin/main, 2026-01-08), venv torch 2.14.0+cu130/diffusers 0.29.0/transformers 4.43.2/accelerate 1.15.0, daemon SonicServer/1.0; (2) **Pesos verificados du 2026-10-08**: 38G total SIN deriva vs "~38G" (Sonic/ 6.2G + SVD-XT 31G + whisper-tiny 581M + RIFE 12M + yoloface_v5m.pt 81M) — estructura 1:1 vs README oficial, nada falta; (3) **VRAM**: idle 5,306 MiB por proceso (pid 2422, coincide medición Gpu 16:29 EDT) + delta render +~19G → pico ~24G — el "~24GB sostenidos" del doc era el PICO, no el idle; (4) **Tiempos históricos** (journal liveportrait + biblioteca + changelog 09-29): 512px/25steps ~100-105s por segundo de audio (2 fuentes reales: piloto 4.6s→474s y episodio 20260929-101801 28.3s→~49.7min), 640px ~180s/s (test real 5.5s→972s), 768px ~240s/s estimado, 15steps ~60s/s; carga pipeline 11-28s (típico 15-17s, doc decía ~10s); (5) **Límites del código**: single-flight 503, resolución default daemon 512 (tab Estudio Podcast manda 640 explícito), steps 25, árbitro lock `sonic-standalone`/BLOCK_TEMP 80C→429/WARN 75C/BUSY_UTIL 85%/stale 5h.
- **Fix docstring daemon** (solo comentarios; proceso en vivo NO reiniciado ni tocado): licencia CC-NC-ND → CC BY-NC-SA 4.0, param `resolution` documentado (existía en código, faltaba en docstring) + nota árbitro. `py_compile` OK, servicio sigue active/loaded.
- **Verificado**: harness JSON válido (`json.tool`), `opencode agent list` resuelve Sonic, doc-fresh `--mark-ok`.
- **Docs**: yes (sonic.harness.json, sonic-server.py docstring, esta entrada; general la escribe Victoria).

### [2026-10-08 15:05 EDT] [sonic] Restructuring agente Sonic (patrón vLLM): docs oficiales + licencia aclarada
- **Tipo**: docs + refactor
- **Que**: §Docs oficiales (github.com/jixiaozhong/Sonic + paper CVPR 2025 — verificadas vivas) + §Upstream check en `sonic.md` y `sonic.harness.json`. **Licencia aclarada**: el doc histórico decía CC-NC-ND; el LICENSE real del repo = **CC BY-NC-SA 4.0** — la regla operativa (NO comercial) es idéntica, queda documentada con la referencia correcta.
- **Verificado**: JSON válido, doc-fresh Sonic FRESH.
- **Gap profundo pendiente**: medición LIVE de VRAM/tiempos por resolución (512/640/768) y steps en el harness.


> Servicios: `victoria-sonic-server.service` (:18850, HOST) + tab 🎙️ Estudio Podcast (LivePortrait :8180) + `instagram-reels.py`
> Subagente: `Sonic` (`~/.config/opencode/agents/sonic.md`)
> Changelog propio desde 2026-10-01 (antes compartía `CHANGELOG-comfyui.md`; las entradas de grupo — árbitro GPU 09-30, migración 09-28 — siguen allá)
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

---

### [2026-10-03 16:50 EDT] [sonic] Agente Sonic curado: voz Qwen3-TTS en desc/pipeline + temperature 0.6 (creativo)
- **Tipo**: docs | config (auditoría cross-machine del día)
- **Que**: (1) `sonic.md` frontmatter description: "voz XTTS" → "voz Qwen3-TTS" (XTTS eliminado 2026-10-03; la description es metadata viva que sale en el picker); (2) pipeline doc: "[1] XTTS :18810" → "[1] Qwen3-TTS :18810"; (3) `temperature: 0.6 + top_p: 0.95` en frontmatter (subagente CREATIVO según la doctrina de sampling por rol 2026-10-03 — escribe guiones de podcast/reels; model card: coding 0.6/0.95); (4) `sonic.harness.json`: pipeline sin "XTTS fallback" (refs Qwen3 propias) + temperature reflejada.
- **Verificado**: grep sin XTTS vivos en sonic.md/harness; opencode agent list resuelve Sonic; JSON válido.
- **Docs**: yes (sonic.md, sonic.harness.json, esta entrada + general).

### [2026-10-01] [changelog] Changelog propio de Sonic (split desde comfyui)
- **Tipo**: docs (organización — pedido del owner)
- **Que**: las 9 entradas [podcast] del 2026-09-29 (00:10→20:15) se mudaron de `CHANGELOG-comfyui.md` a este archivo; refs `sonic-ops.md`→`Sonic.md`. El de comfyui queda con ComfyUI/LivePortrait/n8n + grupo + histórico legacy.
- **Docs**: yes (esta entrada + general)

### [2026-09-29 20:15 EDT] [podcast] Sonic con resolución elegible: 640px default (test real medido)
- **Tipo**: feature (calidad) — pedido del owner ("¿cuánto subir a Sonic?")
- **Que**: `sonic-server.py` acepta `resolution` (512/640/768 whitelist) + UI dropdown en Estudio Podcast (640 default) + tiempos medidos en la UI + `resolucion` en biblioteca/cards. La VRAM viene del KV del vLLM (−8.7GiB, ver CHANGELOG-vllm).
- **Test real 640**: audio 5.5s → 972s wall (**~180s/s audio**), salida **640×1024 h264** verificada, render OK con vLLM 37.9GB co-residente (sin OOM). Tiempos: 15s→45min, 30s→90min (512: 25/50min). 768 = opcional con warning (~240s/s).
- **Docs**: yes (AGENTS §11 API Sonic, Sonic.md, general)

### [2026-09-29 12:45] [podcast] Bordes sólidos: intensidad 0.85 + suavizado + lanczos/unsharp/crf18 + guía de buen guía
- **Tipo**: fix (calidad) — pedido del owner
- **Que**: híbrido con `expression-friendly` + intensidad 0.85 + smooth 1e-6 (stitching/pasteback/relative ya estaban); final lanczos + unsharp suave + crf 18; tips de guía calmado en UI (base 512: lo brusco ablanda bordes). A/B 17.2s OK.
- **Docs**: yes (general + Sonic.md)

### [2026-09-29 10:00] [podcast] Video guía de movimiento opcional (híbrido Sonic + LivePortrait pose)
- **Tipo**: feature — pedido del owner
- **Que**: campo 🎞️ guía + región (pose default, labios intactos); sin guía = Sonic solo. Guía se ajusta al audio; biblioteca guarda movimiento/guía/región. Validado vivo 16.8s.
- **Docs**: yes (general + Sonic.md + AGENTS.md §11)

### [2026-09-29 09:30] [podcast] Guionista en NOSOTROS (comunidad, no maestra)
- **Tipo**: fix (tono) — pedido del owner
- **Que**: prohibido el TÚ (tú debes, cambia tus…); voz obligatoria en NOSOTROS con ejemplo de tono. Verificado 30pal sin TÚ.
- **Docs**: yes (general)

### [2026-09-29 03:10] [podcast] Guionista real y espontáneo inspirado en los RSS (familia/hogar + negocio pequeño)
- **Tipo**: feature (UX/tono) — pedido del owner
- **Que**: adiós plantilla hook+tip+CTA: UN solo párrafo real inspirado en titulares de hoy (`get_rss_inspiration`: DB host modo-ro + news-central.json, keywords por tema, sample aleatorio por variante). PROHIBIDO listas/CTA/emojis/pymes. UI muestra 📰 fuentes + viajan a la biblioteca (`fuentes_rss`). Temáticas reenfocadas al cuidado del hogar y el negocio.
- **Verificado**: 7 hits seguridad recientes; 2 gen LLM 30-35pal tono humano; liveportrait active, /liveportrait/ 200.
- **Docs**: yes (general + Sonic.md)

### [2026-09-29 02:55] [podcast] Guion exacto a duración + Biblioteca persistente con fecha/cards
- **Tipo**: fix + feature (UX)
- **Que**: guionista calibrado a voz real (13.0 chars/s): 15s→35/195, 30s→70/390, 60s→140/780 + recorte por frase; preview mide audio REAL y dice qué quitar; `execute_podcast` guarda `victoria-podcast-YYYYMMDD-HHMMSS-slug.mp4/.wav/.srt` + entrada en `biblioteca-podcast.json`; Gallery + cards (fecha/título/duraciones/rutas/guion+prompt) + Cargar para reutilizar + demo.load + legacy migrados (3). Video sin `-shortest`.
- **Verificado**: TTS 1000 chars→99.9s, app py_compile OK, liveportrait active, /liveportrait/ 200, biblioteca 3 items.
- **Docs**: yes (Sonic.md + AGENTS.md §11)

### [2026-09-29 02:00] [podcast] Estudio Podcast: guionista + editor + pre-escucha
- **Tipo**: feature (UX)
- **Que**: tab en 3 pasos: guionista LLM (5 temáticas + 15/30/60s + variantes + estimación) → editor + 🔊 pre-audio XTTS → video. Auth: key services de DB viva.
- **Verificado**: guión 3.8s, pre-audio 1.2s, 0 warnings.
- **Docs**: yes (Sonic.md)

### [2026-09-29 01:45] [podcast] Sonic en GB10 + Estudio Podcast en vivo + reels + subagente Sonic
- **Tipo**: feature (fases 1b, 2, 3) + docs
- **Que**: piloto Sonic E2E OK ARM64 (labios palabra por palabra, 100s/seg audio); daemon :18850 enabled (24GB VRAM, single-flight, sense_auth); tab Estudio Podcast E2E 200 (chatbox→mp4 1080×1920; fix allowed_paths); gateway /ig-media/ .mp4 + instagram-reels.py → dry-run Meta FINISHED 31s sin publicar; subagente Sonic + registro completo (tabla/delegación/7/servicios/changelogs) + AGENTS.md §11.
- **Verificado**: todo E2E (ver entrada general).
- **Docs**: yes

### [2026-09-29 00:10] [podcast] Proyecto Victoria-Podcast: Fase 0 completa + Sonic instalándose
- **Tipo**: feature (proyecto multi-fase) + docs
- **Que**: docs Sonic oficiales leídas (sin xformers/flash-attn → portable ARM64; checkpoints LeonJoe13/Sonic + SVD-XT gated + whisper-tiny; licencia CC-NC-ND aprobada por owner). Fase 0a: tab "📱 Guía redes" en UI LivePortrait. Fase 0b: `victoria-podcast-demo.sh` + demo 1080×1920 29.4s verificado. Fase 1a parcial: `~/Sonic` + `sonic-venv` cu130 (CUDA GB10 OK) + pesos 6.3GB + whisper-tiny; SVD-XT descargando en background.
- **Verificado**: TTS ES, demo E2E, venv CUDA.
- **Docs**: yes (todowrite; AGENTS.md §11 al cerrar piloto)
