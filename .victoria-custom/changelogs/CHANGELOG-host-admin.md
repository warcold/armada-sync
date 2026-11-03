# CHANGELOG — Host Admin Bridge (:18840)

> Servicio: `victoria-host-admin.service` (exec allowlist + apt install + servicios, HOST)
> Subagente: `OpenClaw` (`~/.config/opencode/agents/openclaw.md`)
> Script host: `victoria-host-admin.py`, `admin-bridge.py` (sandbox), `sense_auth.py`
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

### [2026-10-19 00:30 EDT] [admin-bridge] ENDURECIDO: solo bridge key + rol admin puro — llaves con caps (kalimete) y rol services fuera
- **Tipo**: security (directiva owner 2026-10-19: "kalimete usa los recursos de victoria, NUNCA opera la máquina")
- **Que**: `check_auth()` de `victoria-host-admin.py` ahora exige bridge key O rol gateway **admin puro**. (1) `sense_auth.sense_role()` ganó parámetro `elevate=True` — con `elevate=False` NO aplica la elevación por caps (multi-tier 2026-10-03); host-admin llama con `elevate=False`. (2) El rol `services` se RETIRA de :18840 (no tiene consumidor legítimo: el sandbox usa la bridge key, el owner usa admin). Antes (2026-09-17): admin/services con elevación → la llave `kalimete` (coder+art) y `kalimete-ptt` (services) podían operar el host desde LAN (exec/apt/service restart) — exactamente lo que el owner prohíbe. Los 5 sentidos generadores (voz/video/whois/nav/hunyuan/lp-animate) SIGUEN con elevación normal (recursos).
- **Por qué**: kalimete monta su Game Studio consumiendo la granja de Victoria por HTTP+key (LLM/arte/TTS/3D/animación); el hueco dejaba a cualquier agente de kalimete reiniciar servicios o instalar paquetes en Victoria por red. "Sin explotar y/o hacer que se reinicie" — cerrado por diseño, no por convención.
- **Impacto**: `sense_auth.py` (backwards-compatible, default elevate=True — los otros sentidos y el gateway no cambian), `victoria-host-admin.py`, restart del servicio (instantáneo, stdlib). Backups `.bkup-20261019-kalimeteguard` de ambos.
- **Verificado**: bridge key /health → 200; sin key → 401; admin key elevate=False → 'admin' (pasa); kalimete elevate=False → None; kalimete elevate=True → 'services' (sentidos OK); **por red real desde kalimete: llave kalimete → 401 en :18840/health**. Servicio active.
- **Docs**: yes (AGENTS.md §auth sentidos + §3, victoria.md §granja kalimete, agents/victoria-server de kalimete actualizado por Victoria con autorización del owner, esta entrada + general)

### [2026-10-04 17:50 EDT] [admin-bridge] endurecido: thread + timeouts + fix mensaje de arranque
- **Tipo**: fix estructural + hygiene (mismo bug que tts-bridge: mono-hilo + recv infinito)
- **Que**: `admin-bridge.py`: threading + settimeout(60) + close en finally + URLError->502. Ademas: el mensaje de arranque decia 'Whois bridge listening' (copy-paste) -> corregido a 'Admin bridge listening'.
- **Verificado**: health via socket /tmp/admin-gateway.sock -> ok:true.
- **Docs**: yes (general + openclaw.md)
---

### [2026-09-18 19:00] Validación post-recreación sandbox — host-admin sin cambios
- **Tipo**: docs (verificación, sin cambios al servicio)
- **Que**: El Host Admin Bridge NO fue tocado durante la recreación del sandbox. Servicio active con bridge key (`~/.victoria-custom/secrets/admin-bridge.key` 600) + llave gateway admin/services + filtro de red + allowlists + audit log. Bridge `admin-bridge.py` + key + wrapper `admin-cli` + skill `admin` restaurados en el sandbox nuevo por el ensure-loop (socket `/tmp/admin-gateway.sock` verificado).
- **Verificado**: `curl 127.0.0.1:18840/health` → 401 sin key (por diseño); socket + key + wrapper + skill en sandbox OK.
- **Docs**: yes (este changelog)
