# CHANGELOG — Ecosistema Armada

Registro de cambios que afectan infraestructura, agentes, servicios o configuración.
Cada entrada se crea al finalizar una tarea que modifique algo en el ecosistema.

## Formato de entrada

```markdown
## YYYY-MM-DD

### [Hora] - Cambio: descripción corta
- **Tipo**: agente | config | sync | infra | servicio | red | seguridad | otro
- **Modificado**: archivo o componente que cambió
- **Afecta a**: máquina o agente que se ve impactado
- **Causa**: por qué se hizo el cambio (tarea/razón)
- **Estado**: ✅ sincronizado | ⚠️ pendiente | ❌ error
- **Notas**: detalles adicionales, alertas, observaciones
```

---

## 2026-08-13

### [~21:00] - victoria.armada.do → SOLO API LLM (túnel :8010) + panel admin LAN-only + UIs fuera de internet
- **Tipo**: red | seguridad | infra | config
- **Modificado**: túnel victoria-armada (ingress → :8010), llm-gateway.py (middleware admin LAN-only), DNS (verificado), docs (kalimete.md, eco-cloudflare-tunnels.md, eco-accesos.md, SKILL, MAPAs, AGENTS.md), snapshots históricos borrados
- **Afecta a**: kalimete, victoria, repo armada-sync
- **Causa**: usuario pidió (1) borrar los históricos con menciones del host antiguo, (2) victoria.armada.do SOLO para requests al vLLM (vía gateway con llaves + panel admin como el anterior), (3) UIs de ComfyUI y NemoClaw/OpenClaw SOLO en victoria.local (LAN) — no accesibles desde fuera de la casa
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Túnel: ingress `victoria.armada.do` → `http://127.0.0.1:8010` (era :18789). Validado: chat 200 con bearer, 401 sin key, `/models` 200. Panel `/admin` vía dominio → 403.
  - Gateway parcheado (llm-gateway.py, backup .bkup-20260813): rutas `/admin*` bloqueadas si hay header CF-Connecting-IP (viene por túnel) o IP no-LAN → panel = `http://victoria.local:8010/admin` (login ADMIN_PASS). Servicio reiniciado, verificado LAN 200 / túnel 403 / chat 200.
  - Borrados: `~/.config/opencode/agent-backup-2026-08-12/`, `~/armada-sync/agents-retired-2026-08-12/`, `~/.config/opencode/opencode.jsonc.bkup.old`.
  - ⚠️ Pendiente: el updater DDNS de jonas aún puede pisar el CNAME de victoria.armada.do (verificar cuando el SSH a jonas se arregle). ComfyUI :8188 no corre (cuando corra = solo LAN). OpenClaw :18789 solo LAN.
  - Uso: API LLM pública = `https://victoria.armada.do/v1/chat/completions` (bearer = nombre de key); panel = victoria.local:8010/admin; UIs = victoria.local.

### [~20:00] - Migración documental completa: victoria hace el trabajo completo (0 menciones del host antiguo)
- **Tipo**: config | infra | doc | sync
- **Modificado**: ~/.config/opencode (kalimete.md, eco-*.md, MAPA.md, cloudflare-map, skills), armada-sync (AGENTS.md, MAPA.md, configs/, skills/, daily-report/), ~/.zshrc, ~/.config/opencode/daily-report.env, DNS verificado
- **Afecta a**: kalimete, victoria (10.0.0.5), repo armada-sync
- **Causa**: usuario pidió eliminar todo rastro del host antiguo (10.0.0.5, cuyo nombre histórico se retiró) de documentación, agentes, configs y Cloudflare — victoria hace el trabajo completo; no mencionar el nombre viejo ni "ex-..."
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Gateway validado end-to-end: `victoria-llm-gateway` :8010 (systemd ACTIVE) — auth por NOMBRE de key (bearer `demo`), model `nvidia/Qwen3.6-35B-A3B-NVFP4`, `enable_thinking:false` → content directo. `/v1/models` no existe en el gateway (solo `/models` + `/v1/chat/completions`).
  - `~/.zshrc`: variable de la key renombrada → `VICTORIA_API_KEY` (valor = bearer válido `demo`). `daily-report.env` igual.
  - `report.py`: LLMGATE → `http://10.0.0.5:8010/v1/chat/completions`, MODEL → `nvidia/Qwen3.6-35B-A3B-NVFP4`, SERVERS sin el host viejo.
  - DNS verificado: `victoria.armada.do` = CNAME proxied → túnel `victoria-armada` (`d9abe241-…cfargotunnel.com`); el hostname antiguo NO existe en DNS.
  - ⚠️ **OJO DDNS**: el updater de jonas (cron */5) actualizaba `victoria.armada.do` como A (69.143.73.120); desde hoy es CNAME del túnel — si el updater recrea el A lo pisa (verificar en jonas cuando el SSH se arregle).
  - Pendiente: gateway :18789 no escucha → `victoria.armada.do` 503 (esperado); servicios de voz (victoria-voice, nginx 8765) pendientes de migrar; ollama no corre; opencode.jsonc.bkup.old y daily-report.log aún contienen menciones históricas (snapshots/logs, no activos).

### [23:35] - Red: host 10.0.0.5 renombrado → NUEVA victoria + fix RDP headless
- **Tipo**: red | infra | servicio | config
- **Modificado**: hosts, SSH configs, MAPA.md, kalimete.md, eco-accesos.md, AGENTS.md, perfil remmina, victoria (10.0.0.5): xrdp desactivado, grd RDP habilitado con credenciales + TLS
- **Afecta a**: kalimete, victoria (10.0.0.5), Alfredo (Windows en 10.0.0.64)
- **Causa**: usuario reportó RDP rechazado tras credenciales; validación de logs mostró: (1) el host 10.0.0.5 es la NUEVA victoria (puerto 1666, user victoria), (2) xrdp validaba OK pero GNOME mataba la sesión ("Session manager already running" — sesión local activa), (3) grd tenía RDP disabled y sin credenciales
- **Estado**: ✅ sincronizado
- **Notas**: llave `id_ed25519_kalimete` autorizada en victoria. `grdctl --system rdp set-credentials victoria vcolador` + cert self-signed en /var/lib/gnome-remote-desktop/. xrdp y xrdp-sesman DISABLED. ⚠️ pendiente reactivar el gateway LLM (luego validado: victoria-llm-gateway :8010 ACTIVE). Victoria vieja (10.0.0.64) ya no existe como Ubuntu (IP ahora del Windows de Alfredo).

### [13:30] - Fix: vLLM context overflow (163K → 262K)
- **Tipo**: config | infra
- **Modificado**: opencode.jsonc (baseline-thinking), MAPA.md (regla anti-desborde)
- **Afecta a**: kalimete (config opencode)
- **Causa**: 147,457 input + 16,384 max_tokens = 163,841 > 163,840 vLLM limit → "Type validation failed". El modelo soporta 262K según NVIDIA docs.
- **Estado**: ✅ sincronizado
- **Notas**: baseline-thinking: max_tokens 16384→8192, context 158000→245000. MAPA.md actualizado con contexto real 262K. vLLM contenedor aún en 163K → no urgente (opencode.jsonc tiene margen).

---

## 2026-08-13

### [05:35] - Sync: integración del host 10.0.0.5 (GPU/LLM) al ecosistema (follower)
- **Tipo**: sync | infra | agente
- **Modificado**: armada-sync/AGENTS.md, armada-sync/agents/docs-keeper.md (nuevo), host 10.0.0.5: llave github del follower + ~/.ssh/config, cron, opencode.jsonc (default_agent)
- **Afecta a**: kalimete, victoria, host 10.0.0.5
- **Causa**: el host 10.0.0.5 es el proveedor de modelos (vLLM/gateway) de todo el ecosistema; quedaba fuera del sync de agentes
- **Estado**: ✅ sincronizado
- **Notas**: el host 10.0.0.5 ahora es FOLLOWER (pull+deploy, nunca push). Deploy key `victoria-follower-readonly` (solo lectura) registrada en GitHub vía gh. docs-keeper.md (agente local del host) añadido al repo con model portable (sin model fijo → usa default de cada máquina). Cron `*/5` instalado. default_agent: kalimete añadido al opencode.jsonc del host. md5 de kalimete.md idéntico al repo. jonas queda pendiente (SSH roto).

### [00:15] - Sync: arquitectura hub/follower, collect/deploy destructivos, cron.log gitignore
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh, armada-sync/.gitignore
- **Afecta a**: kalimete, victoria
- **Causa**: race condition entre crons de kalimete y victoria, agentes zombies
- **Estado**: ✅ sincronizado
- **Notas**: kalimete es ahora el único writer (HUB). Victoria solo pull+deploy. collect y deploy son destructivos (eliminan zombies). cron.log ya no se sube al repo.

### [00:30] - Fix: sync.sh nullglob syntax error
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh
- **Afecta a**: kalimete, victoria
- **Causa`: syntax error en línea 45 (redirección no válida en for)
- **Estado**: ✅ sincronizado
- **Notas**: reemplazar `for ... 2>/dev/null` por `shopt -s nullglob` + for limpio. Victoria necesita actualizar sync.sh del remoto.

### [00:35] - Sync: arquitectura hub/follower, collect/deploy destructivos, cron.log gitignore
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh, armada-sync/.gitignore
- **Afecta a**: kalimete, victoria
- **Causa**: race condition entre crons de kalimete y victoria, agentes zombies
- **Estado**: ✅ sincronizado
- **Notas**: kalimete es ahora el único writer (HUB). Victoria solo pull+deploy. collect y deploy son destructivos (eliminan zombies). cron.log ya no se sube al repo.

### [00:36] - Fix: sync.sh nullglob syntax error
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh
- **Afecta a**: kalimete, victoria
- **Causa**: syntax error en línea 45 (redirección no válida en for)
- **Estado**: ✅ sincronizado
- **Notas**: reemplazar `for ... 2>/dev/null` por `shopt -s nullglob` + for limpio. Victoria necesita actualizar sync.sh del remoto.

### [00:40] - Sync: completar AGENTS.md con datos reales
- **Tipo**: infra
- **Modificado**: armada-sync/AGENTS.md
- **Afecta a**: kalimete, victoria
- **Causa**: AGENTS.md tenía campos vacíos (URL, estructura, conectividad)
- **Estado**: ✅ sincronizado
- **Notas**: se completaron URLs, conectividad SSH, estructura del repo, automatización, servicios (OpenShell corregido), reglas de operación con límites de contexto y GLM-5.2.

---

<continuar arriba — los más recientes primero>
