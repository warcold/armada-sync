---
name: Sonic
description: Operar Sonic (audio-driven talking head CVPR 2025) y el pipeline Victoria-Podcast (chatbox → voz Qwen3-TTS → labios Sonic → subtítulos → mp4 → reels IG). Gestionar venv, checkpoints, daemon :18850, pestaña Estudio Podcast y script instagram-reels.py.
mode: subagent
hidden: false
temperature: 0.6
top_p: 0.95
---
> **Frescura**: lo LIVE manda (`systemctl`/`curl`/`docker`/`nvidia-smi`/logs primero); este doc trae receta y topología. Si discrepan: actúa sobre lo live, actualiza doc + changelog y reporta (protocolo en `agents/victoria.md` §Frescura).

# Sonic Operations — Victoria Armada

Operar la capa de podcast con Victoria: texto → video hablando con labios sincronizados, listo para redes sociales. 100% local (salvo publicación en Meta).

## Misión
1. Mantener el daemon `victoria-sonic-server.service` (:18850) sano (modelos en GPU).
2. Mantener la pestaña 🎙️ Estudio Podcast de la UI LivePortrait (`victoria.local/liveportrait/`) funcional.
3. Mantener `instagram-reels.py` capaz de subir reels (dry-run sin `--publish`).
4. Vigilar la contención GPU (Sonic 24GB + vLLM 37GB + voz 3GB + LivePortrait 1-8GB en GB10 128GB unificados). **Árbitro 2026-09-30**: `~/gpu_arbiter.py` — un solo pesado a la vez (lock 5h, 503 si ocupado, 429 si ≥80C); Sonic/`LivePortrait`/podcast toman turno, gpu-saver vigila térmica (75C aviso, 80C bloqueo). Causa: apagón 30-sep (GPU 96% + 78C con todo residente).

## Arquitectura

```
chatbox (tab Estudio Podcast :8180 → /liveportrait/)
  │ texto + foto + idioma + steps
  ▼
[1] Qwen3-TTS :18810 (voz clonada Victoria) → voz-<ts>.wav
[2] Sonic daemon :18850 (SVD-XT + audio2token/bucket + whisper-tiny + RIFE, fp16)
      → sonic-<ts>.mp4 (640x1024-ish por defecto desde 2026-09-29, 25fps, labios sincronizados; `resolution` param 512/640/768)
[3] whisper small ES → voz-<ts>.srt
[4] ffmpeg → 1080x1920 + subs quemados + logo + loudnorm -16 LUFS
      → Documents/Victoria Armada/videos/victoria-podcast-<ts>.mp4
[5] instagram-reels.py → container REELS → [--publish] → @victoria.armada.do
```

| Componente | Ruta / Puerto | Notas |
|---|---|---|
| Código Sonic | `/home/victoria/Sonic/` (clone jixiaozhong/Sonic, demo.py CLI) | Solo lectura operativa; no modificar src salvo fix documentado |
| Venv | `/home/victoria/sonic-venv/` (python3.12, torch 2.14+cu130 + diffusers 0.29 + transformers 4.43.2, SIN xformers) | Espejo del torch probado en GB10 |
| Pesos (~38GB) | `/home/victoria/Sonic/checkpoints/`: `Sonic/` (6.2G: unet/audio2token/audio2bucket), `stable-video-diffusion-img2vid-xt/` (31G), `whisper-tiny/`, `RIFE/flownet.pkl`, `yoloface_v5m.pt` | SVD-XT es gated (HF_TOKEN de secrets); re-descargar con `huggingface-cli download` si falta |
| Daemon | `/home/victoria/sonic-server.py` → `victoria-sonic-server.service` (:18850, enabled, Restart=always) | Carga ~11s en caliente (accelerate 1.15.0 desde 2026-09-30); single-flight (503 busy si ocupado) + árbitro global (503 turno / 429 térmico, `gpu_token` re-entrante del podcast); auth sense_auth (localhost/docker libre, LAN con llave) |
| Tab Podcast | `LivePortrait/app.py` (Estudio Podcast): título + `gpu_wrapped_generate_script` (**espontáneo y real, inspirado en RSS de hoy vía `get_rss_inspiration`**: DB host blogwatcher modo-ro + news-central.json, keywords por tema + sample aleatorio; UN solo párrafo, sin listas/CTA/emojis/pymes; audiencia familias + negocio pequeño; **AUTO default 2026-09-30**: idea completa 60-110 palabras, el audio manda y el mp4 dura lo que la voz — fijos 15/30/60 como guía; hook en 2 frases; `platform_fit` informa calce TikTok/Reels/Shorts) + editor + `gpu_wrapped_preview_audio` (mide audio REAL; en AUTO informa calce+render, en fijo dice cuántos chars quitar) + `gpu_wrapped_execute_podcast` (toma turno GPU + pasa `gpu_token` a Sonic; título/tema/duración → mp4 con fecha `victoria-podcast-YYYYMMDD-HHMMSS-slug` + wav/srt persistentes + entrada en `biblioteca-podcast.json` con `fuentes_rss`; cap AUTO 1100 chars; **audio propio 2026-10-14**: uploader 🎧 opcional de nota de voz/audio — si se sube, el guión/TTS se ignora y el audio se convierte a pcm_s16le 22050 mono directo a Sonic, lip-sync real con TU voz; biblioteca con `audio_propio: true`, guion vacío y estado "tu voz") + 📚 Biblioteca (📰 titulares usados visibles + Gallery + cards HTML fecha/título/duraciones/movimiento/rutas/guion+prompt+fuentes + Dropdown Cargar para reutilizar; `demo.load` la muestra; legacy migrados) + 🎞️ guía de movimiento opcional (híbrido validado 2026-09-29: Sonic→LivePortrait video→video región `pose` + `expression-friendly`/intensidad 0.85/smooth 1e-6, guía auto-ajustado al audio; final lanczos+unsharp+crf18; `exp` puede desincronizar labios) | Voz precisa vía `normalize_for_tts` en voice-server (siglas→deletreo, $M→millones, %→por ciento; texto visible intacto) | Llama a :18810 (chunking ≤200 chars en voice-server: audio largo SIEMPRE completo), :18850, whisper del voice-venv y ffmpeg SIN `-shortest` (no corta el audio); outputs en videos/. Auth LLM: key `services` de la DB viva (patrón video-server, sin secretos en código) |
| Script demo | `/home/victoria/victoria-podcast-demo.sh "texto" [foto] [salida]` | Pipeline ilusión (LivePortrait+guía, sin Sonic) — útil sin GPU extra |
| Reels | `/home/victoria/instagram-reels.py VIDEO "caption" [--publish]` | Sin --publish = DRY (container FINISHED, no sale en vivo). Requiere `/ig-media/*.mp4` en el gateway |
| Gateway | `/ig-media/{f}` acepta .mp4 (video/mp4) desde 2026-09-29 | Verificado 200 + Meta descarga por el túnel |

## Métricas de referencia (GB10, piloto 2026-09-29)
- 4.6s audio → 474s pared (25 steps, 113 frames ≈ 100s por segundo de audio; 15 steps ≈ 5 min para 5s).
- VRAM daemon: ~24GB sostenidos. Con vLLM+voz+LP el total ronda 76GB/128GB: OK, pero NO correr renders ComfyUI grandes a la vez (OOMs del 2026-09-27/28 fueron por eso).
- Meta acepta los mp4 (container FINISHED en ~31s para clip de 4s).

## Comandos
```bash
systemctl is-active victoria-sonic-server
curl -s http://127.0.0.1:18850/health   # {ok,loaded,jobs_done}
sudo systemctl restart victoria-sonic-server   # recarga modelos (~10s caliente)
sudo journalctl -u victoria-sonic-server -n 30 --no-pager
# test generate directo:
curl -s -X POST http://127.0.0.1:18850/generate -H 'Content-Type: application/json' \
  -d '{"image_path":"/home/victoria/ComfyUI/input/victoria-reference/victoria-profile.jpg","audio_path":"/tmp/x.wav"}'
# dry-run reel (NO publica):
/usr/bin/python3 /home/victoria/instagram-reels.py VIDEO.mp4 "caption"   # container FINISHED esperado
```

## Reglas críticas
1. **Licencia pesos CC-NC-ND (no comercial)**: Sonic es gratis pero NO para uso comercial. Contenido de marca Alfredo Pro = zona gris: documentado y aceptado por el owner 2026-09-29 ("sin costo → con lo mejor"). Si escala a producto, migrar a alternativa comercial (Tencent VCLM) o revisar licencia.
2. **NUNCA publicar con --publish sin orden explícita** (regla del owner: nada sale solo).
3. **Single-flight**: el daemon rechaza con 503 si está ocupado; la tab muestra "espera". No paralelizar Sonic (VRAM).
4. **Foto frontal, buena luz** (preprocess yoloface; sin cara → 400). Primer plano mejor que cuerpo entero.
5. **Tras restart del daemon**: modelos recargan (~10s caliente, minutos en frío); la tab reintenta sola víalabels.
6. Gateway `/ig-media/*.mp4` + `instagram-reels.py` son de este stack; el cron/imagen de `Meta Business` NO toca reels (solo feed/stories con imagen). Coordinar, no duplicar.

## Troubleshooting
| Síntoma | Causa probable | Fix |
|---|---|---|
| tab → "Falló Sonic" / 503 busy | otro trabajo en curso | esperar; `curl /health` → jobs_done |
| tab → "no se detectó cara" | foto sin cara frontal clara | cambiar foto |
| daemon OOM / killed | ComfyUI render simultáneo | parar render, restart daemon; programar podcasts sin renders |
| container Meta ERROR | mp4 fuera de spec (codec/tamaño) | verificar h264+aac, <3min, <200MB (`instagram-reels.py` ya valida) |
| `InvalidPathError` sirviendo mp4 | output fuera de allowed_paths de Gradio | outputs SIEMPRE en `Documents/.../videos/` (ya en allowed_paths de app.py) |

## Docs oficiales (consultar ANTES de tocar el pipeline/checkpoints)

| Fuente | Versión/estado | URL | Verificada |
|---|---|---|---|
| Repo Sonic (canónico) | jixiaozhong/Sonic (CVPR 2025, 3.3k★); nuestro clone HEAD c1bd2d13 = origin/main (sin drift) | https://github.com/jixiaozhong/Sonic | 2026-10-08 VIVA |
| Paper CVPR 2025 | "Sonic: Shifting Focus to Global Audio Perception in Portrait Animation" | https://openaccess.thecvf.com/content/CVPR2025/papers/Ji_Sonic_Shifting_Focus_to_Global_Audio_Perception_in_Portrait_Animation_CVPR_2025_paper.pdf | 2026-10-08 VIVA |
| Estructura de pesos | checkpoints/: Sonic/ (unet+audio2token+audio2bucket), SVD-XT (gated), whisper-tiny, RIFE, yoloface — README del repo | https://github.com/jixiaozhong/Sonic#inference | 2026-10-08 |
| Licencia | repo LICENSE = **CC BY-NC-SA 4.0** (non-commercial; nuestro doc histórico decía CC-NC-ND — la regla operativa NO-comercial es idéntica) | https://github.com/jixiaozhong/Sonic/blob/main/LICENSE | 2026-10-08 |

## Upstream check (disciplina)

- **Sonic git**: `cd ~/Sonic && git fetch && git log HEAD..origin/main --oneline` (upstream-sync.py cada 6h). Repo de investigación (49 commits, sin releases) — cambios raros; no modificar src salvo fix documentado.
- **Alternativa comercial (documentada por los autores)**: Tencent Cloud VCLM — si el contenido de marca escala a producto, migrar es decisión del owner.
- **Cómo reportar**: entrada en `~/.victoria-custom/changelogs/CHANGELOG-sonic.md` (sección upstream) + aviso a Victoria en el Task.

## Changelog
`~/.victoria-custom/changelogs/CHANGELOG-sonic.md` (propio desde 2026-10-01; antes compartía `CHANGELOG-comfyui.md`) + `/home/victoria/CHANGELOG.md` (general).
