# CHANGELOG — Whois Server (:18830)

> Servicio: `victoria-whois-server.service` (whois(1) 5.5.22 + fallback RDAP, HOST, stdlib)
> Subagente: `OpenClaw` (`~/.config/opencode/agents/openclaw.md`)
> Script host: `whois-server.py`, `sense_auth.py`
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

### [2026-10-04 17:50 EDT] [whois-bridge] endurecido: thread por conexion + timeouts (igual que tts-bridge)
- **Tipo**: fix estructural (mismo bug que tts-bridge: mono-hilo + recv infinito)
- **Que**: `whois-bridge.py`: threading + settimeout(60) + close en finally + URLError->502. Proceso viejo (4d) matado con kill y relanzado por ensure_whois con codigo nuevo.
- **Verificado**: health via socket /tmp/whois-gateway.sock -> ok:true.
- **Docs**: yes (general + openclaw.md)
---

### [2026-09-18 19:00] Validación post-recreación sandbox — whois sin cambios
- **Tipo**: docs (verificación, sin cambios al servicio)
- **Que**: El whois-server NO fue tocado durante la recreación del sandbox. Servicio active con filtro de red + auth (LAN con llave gateway admin/services) + fallback RDAP para TLDs no soportados. Bridge `whois-bridge.py` + wrapper `whois` + skill `domain` restaurados en el sandbox nuevo por el ensure-loop (socket `/tmp/whois-gateway.sock` verificado).
- **Verificado**: `curl 127.0.0.1:18830/health` → ok; socket + wrapper + skill en sandbox OK.
- **Docs**: yes (este changelog)
