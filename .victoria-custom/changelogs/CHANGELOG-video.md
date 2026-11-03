# CHANGELOG — Video Server (:18811)

> Servicio: `victoria-video-server.service` (yt-dlp + ffmpeg + whisper + VLM, HOST)
> Subagente: `OpenClaw` (`~/.config/opencode/agents/openclaw.md`)
> Script host: `victoria-video-server.py`, `video-venv/`
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

### [2026-10-04 17:50 EDT] [video-bridge] endurecido: thread por conexion + timeouts (igual que tts-bridge)
- **Tipo**: fix estructural (mismo bug que tts-bridge: mono-hilo + recv infinito — un cliente atascado bloqueaba todo el analisis de video del sandbox)
- **Que**: `video-bridge.py`: threading + settimeout(60) + close en finally + URLError->502. Proceso viejo (4d, lanzado por el init del container) matado con `kill <pid>` (pkill -f NO opera ahi) y relanzado por ensure_video con codigo nuevo (md5 verificado IGUAL).
- **Verificado**: health via socket /tmp/video-gateway.sock -> ok:true (ytdlp+ffmpeg) tras relanzar.
- **Docs**: yes (general + openclaw.md)
---

### [2026-09-18 19:00] Validación post-recreación sandbox — video sin cambios
- **Tipo**: docs (verificación, sin cambios al servicio)
- **Que**: El video-server NO fue tocado durante la recreación del sandbox. Servicio active con auth (localhost/docker sin llave, LAN con llave gateway admin/services). Bridge `video-bridge.py` + wrappers (`video-dl`, `video-analyze`, `video-analyze-local` con chmod 755) + skill `video` restaurados en el sandbox nuevo por el ensure-loop (socket `/tmp/video-gateway.sock` verificado).
- **Verificado**: `curl 127.0.0.1:18811/health` → ok; socket + wrappers + skill en sandbox OK.
- **Docs**: yes (este changelog)
