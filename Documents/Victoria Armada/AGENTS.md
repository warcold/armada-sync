# AGENTS.md — Victoria Armada (contenido)

> Ledger del proyecto de contenido. Vive CON el código. Máximo ~60 líneas.
> Protocolo: `~/.config/opencode/agents/victoria.md` (§Protocolo de Contexto
> por Proyecto) + `~/AGENTS.md` §9.6. Actualizar al terminar cada sesión.

## Qué es
Assets de marca de Victoria: fotos, templates ComfyUI, videos/podcasts,
pipeline de contenido. Para IG/reels/talking-head.

## Mapa
- `photos/` — 5 fotos base Victoria (Posing, Thinking, Working, DeepWorking...)
- `profile/victoria-profile.jpg` — foto canónica (referencia InstantID/IP-Adapter)
- `templates/` — 7 templates ComfyUI (posts IG, reel, thumbnail, hablando 12/15/30s)
- `videos/` — clips sintéticos + podcasts generados + `biblioteca-podcast.json`
- `identity-reference/` — IDENTITY/SOUL/USER maestros (sync con sandbox)
- `PIPELINE-CONTENIDO.md` — pipeline 5 pasos · `README.md` — organización
- `workspace/skills/` — skills del workspace

## Cómo correr / debug
```bash
# Symlinks a ComfyUI (verificar rotos):
ls -la ~/ComfyUI/input/victoria-reference/ | head
# Templates vía UI: http://victoria.local/comfyui/ · Podcast: http://victoria.local/liveportrait/ (tab 🎙️)
# Reels DRY: python3 ~/instagram-reels.py VIDEO "caption"  # sin --publish no publica
```

## Decisiones (con fecha)
- **2026-09-28**: solo imagen en ComfyUI (video LTX eliminado); talking-head = LivePortrait+Sonic.
- **2026-09-29**: Sonic render default 640 (bordes sólidos); pesos CC-NC-ND no comercial.
- **2026-09-30**: ledger creado (protocolo contexto por proyecto); instructions slim no embeben este dir.

## Pendientes
- [ ] Verificar symlinks `ComfyUI/input/victoria-reference/` tras cada reboot
- [ ] NUNCA publicar sin aprobación del owner (regla victoria.md)

## Relación con el stack
- Toca grupo Contenido (ComfyUI :8188, LivePortrait :8180, Sonic :18850, n8n).
- Cambios a servicios → CHANGELOG general + `CHANGELOG-comfyui.md`. Este ledger referencia, no duplica.
