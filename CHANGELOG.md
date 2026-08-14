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

## 2026-08-14

### [~14:30] - Auditoría completa de documentación y agentes contra estado real (limpieza)
- **Tipo**: documentación | agente | config | sync
- **Modificado**:
  - `kalimete.md` reescrito: gateway v2 (auth por valor, panel, llaves), provider alfredopro, health 401, max-model-len 262144, skill plural, backup retirados borrado, voz/ComfyUI/18789 fuera
  - `ecosistema-map/MAPA.md` reescrito: UFW inactive, voz ELIMINADA, openshell 18789 muerto, límites 262K, cron duplicado detectado
  - `eco-voice.md` reescrito como doc de reconstrucción (servicio ELIMINADO 2026-08-14)
  - `eco-accesos.md`: IP histórica 192.168.5.74 corregida (kalimete en LAN), jonas roto, UFW inactive, llaves gateway v2
  - `eco-cloudflare-*.md` (5): fechas 2026-08-14, skill plural, WAF taohemps NO desplegado, panel URL
  - `cloudflare-map/INVENTARIO.md`: verificación 2026-08-14, WAF taohemps NO, micaserogou 27 records, taohemps 27 records, registros obsoletos VPS documentados, panel URL
  - `armada-sync/AGENTS.md`: gateway v2, voz eliminada, 18789, límites 262K, skill plural, docs-keeper fuera
  - `armada-sync/sync.sh`: **bug corregido** — deployea a `skills/` plural (antes `skill/` singular que opencode NO lee)
  - `command/mapa.md`: apunta al mapa maestro ecosistema (no al agente retirado cloudflare)
  - ELIMINADO: `~/.config/opencode/skill/` (duplicado singular, idéntico a `skills/`)
- **Afecta a**: kalimete, victoria (follower sync), repo
- **Causa**: auditoría ordenada por el usuario (validar docs/agentes contra servicios reales, limpiar obsoleto)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Verificado en vivo 2026-08-14: victoria 2 contenedores, 4 systemd activos, UFW inactive, 8010 loopback, 443 nginx, 3389 RDP; NADA en 8765/8766/18789/8188 (voz/ComfyUI/OpenClaw gateway muertos); jonas SSH sigue roto; kalimete 7 contenedores, kalimete-tunnel active
  - ⚠️ Pendiente usuario: cron duplicado de sync.sh en kalimete (2 líneas idénticas) + entrada cron RSS apuntando a /home/victoria (no existe en kalimete)
  - ⚠️ Pendiente usuario: token damp-surf-3478-fusion, registros VPS obsoletos (proxy.us-east, telecomm×2, whiteboard.nextcloud), SPF duplicado micaserogou

---

## 2026-08-13

### [~02:30] - demo eliminada; scripts usan la llave de alfredo
- **Tipo**: servicio | config | seguridad
- **Modificado**: DB del gateway (llave `demo` borrada, incl. su usage_log); `~/.zshrc` + `daily-report.env` (VICTORIA_API_KEY = llave de alfredo)
- **Afecta a**: victoria, kalimete
- **Causa**: el usuario preguntó para qué servía demo (solo reporte diario y pruebas); decidió eliminar y usar la de alfredo
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: llaves finales = 3 personales: `alfredo` (admin), `victoria` (admin), `juancarlos` (coder). La llave de demo ya no funciona (401).

### [~02:00] - Formato de llaves: vllm-key-<hex> (rotadas las 4)
- **Tipo**: servicio | seguridad | config
- **Modificado**: `/home/victoria/llm-gateway.py` (create_key genera `vllm-key-<token_hex(32)>`; backup `.bkup-v2b-20260814`); DB: 4 llaves rotadas in-place (key_plaintext+key_hash, historial intacto); `~/.config/opencode/opencode.jsonc` (apiKey alfredo nuevo), `~/.zshrc` + `daily-report.env` (VICTORIA_API_KEY demo nuevo)
- **Afecta a**: victoria, kalimete, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: formato `vict-llm-<nombre>-<salt>` exponía el nombre de la persona; el usuario pidió `vllm-key-*****`
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Nuevo formato: `vllm-key-` + 64 hex (sin nombre). Auth sigue por valor real (key_hash).
  - Las llaves viejas `vict-llm-*` ya NO funcionan (401). Valores rotados sin perder historial de uso.
  - Validado: alfredo 200, demo 200, vict-llm vieja 401, túnel con demo 200, opencode run OK.

### [~01:30] - Auth por VALOR real de llave + jsonc limpio (provider alfredopro, host local)
- **Tipo**: servicio | seguridad | config
- **Modificado**: `/home/victoria/llm-gateway.py` (validate_key por key_hash del bearer; backup `.bkup-v2-20260814`), `~/.config/opencode/opencode.jsonc` (solo provider `alfredopro`/name "www.alfredo.pro", model "Coding con Victoria", baseURL `https://victoria.local/v1` local, apiKey = valor real alfredo; quitado provider `vllm` directo), `~/.zshrc` y `~/.config/opencode/daily-report.env` (VICTORIA_API_KEY = valor real demo)
- **Afecta a**: victoria, kalimete, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: el usuario dudó que las llaves fueran su nombre (auth por nombre = el valor largo no servía). Decidió auth por valor real (estándar, como OpenAI)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Bearer = valor completo `vict-llm-<name>-<salt>`; el nombre ya NO autentica (401). Lookup por SHA-256(key_plaintext).
  - Los valores largos dados antes siguen siendo los mismos y AHORA son las credenciales reales (antes decorativos).
  - Validado: valor alfredo 200, "alfredo" 401, valor demo 200 (env daily-report + túnel chat 200), valor juancarlos 200, `opencode run` con provider alfredopro OK (valor real).
  - opencode.jsonc ahora SOLO LAN (victoria.local); para otros equipos usar victoria.armada.do con su CA/valor.

### [~01:00] - opencode.jsonc (kalimete): provider "armada" — gateway como público
- **Tipo**: config
- **Modificado**: `~/.config/opencode/opencode.jsonc` (kalimete) — provider nuevo `armada` (@ai-sdk/openai-compatible, baseURL `https://victoria.armada.do/v1`, apiKey `alfredo`), model `armada/nvidia/Qwen3.6-35B-A3B-NVFP4` (limit 240000/20000). Provider `vllm` directo (:8000) intacto; providers opencode zen intactos (no viven en este archivo).
- **Afecta a**: kalimete
- **Causa**: probar el gateway "como público" desde el opencode local
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: validado con `opencode run --model armada/nvidia/Qwen3.6-35B-A3B-NVFP4` → respuesta OK; streaming SSE passthrough por túnel verificado; metering contabiliza el request (alfredo 2 requests).

### [~00:30] - Llaves finales (3 personas) + límites por defecto relajados
- **Tipo**: servicio | config | seguridad
- **Modificado**: `/home/victoria/llm-gateway.py` (defaults create_key/panel: rate 1000/min, max_tokens 32768), `/home/victoria/admin_template.html` (formulario con defaults amplios); DB: llaves
- **Afecta a**: victoria, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: uso entre amigos + NemoClaw → sin límites duros; 3 llaves personales (admin/admin/coder), borrada la `alfredo` de prueba
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Llaves finales (auth por NOMBRE, Bearer <name>): `alfredo` (Alfredo Armada, admin), `victoria` (Victoria Armada/NemoClaw, admin), `juancarlos` (Juan Carlos Jerez, coder), `demo` (admin, interna del sistema).
  - Parámetros personales: rate 100000/min, max_tokens 262144, budget 0 (ilimitado), sin expiración, precio 0.02 $/1k (solo contabilidad).
  - Validado: roles/scopes en /v1/usage (admin=all, coder=self).

### [~23:59] - Gateway v2: contabilidad (metering, precio por llave, presupuesto, roles, rate real)
- **Tipo**: servicio | seguridad | infra | config
- **Modificado**: `/home/victoria/llm-gateway.py` (v2.0.0; backup `llm-gateway.py.bkup-v1-20260814`), nuevo `/home/victoria/admin_template.html` (SPA panel), DB migrada automáticamente (ALTER TABLE)
- **Afecta a**: victoria, kalimete, Alfredo (panel), consumidores del gateway
- **Causa**: usuario pidió panel profesional con contabilidad: precio por llave, uso general, límites, manejo de llaves y tiers (admin/coder) — mejoras basadas en prácticas de LiteLLM/Portkey/LLM Gateway (budget duro por llave, metering en el gateway, scoping por rol, llave visible una sola vez)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Metering real: cada request guarda model, prompt/completion/total tokens y costo en `usage_log`; acumula totales por llave. Costo = total_tokens/1000 × `price_per_1k_tokens` (default 0.02, env DEFAULT_PRICE_PER_1K; independiente del modelo).
  - Presupuesto: `budget` USD por llave (0=ilimitado) → 402 "budget exceeded" al agotarse. Rate real por minuto (usage_log últ. 60s) → 429. max_tokens de la key se impone por request. Expiración por horas.
  - Roles: `admin` (ve uso global en /v1/usage) / `coder` (solo su propia key). Panel admin = ADMIN_PASS, sigue LAN-only (403 vía túnel).
  - Endpoints nuevos: `GET /v1/usage`, `PUT /admin/keys/{name}` (editar), `GET /admin/keys/{name}/usage`, `GET /admin/usage?key=`.
  - Panel: login, dashboard (6 stats + chart 14 días + top keys por gasto + actividad), API Keys (crear con rol/precio/presupuesto/expiración, tabla con barra de presupuesto, editar/activar/desactivar/borrar, modal de uso con chart), Usage con filtro por llave y costo por request.
  - Llaves finales: `demo` (admin, del sistema — opencode/túnel) y `alfredo` (coder, $0.05/1k, budget $2, creada por Alfredo en el panel). Tests: budget→402 ✓, rate→429 ✓, túnel con metering ✓, /admin 403 vía túnel ✓.
  - ⚠️ Streaming: pasa raw sin medir tokens (cost 0) — documentado; opencode usa el vLLM directo :8000, no el gateway.

### [~23:30] - Fix panel admin: login redirigía a /admin/dashboard (JSON) en vez de /admin (HTML)
- **Tipo**: servicio | bugfix
- **Modificado**: `/home/victoria/llm-gateway.py` — doLogin: `location.href = '/admin/dashboard'` → `'/admin'` (patch remoto, sin backup; cambio de 1 línea)
- **Afecta a**: Alfredo (panel https://victoria.local/admin)
- **Causa**: tras loguearse, la SPA mandaba al navegador a un endpoint JSON de la API — se veía "el request crudo" y no la web de administración
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: verificado: GET /admin → HTML con redirect correcto; POST /admin/login → token; GET /admin/keys con token → lista (demo active). El panel completo (crear/activar/desactivar/borrar llaves, usage) ya existía en el template y queda operativo.

### [~23:00] - TLS en victoria.local (nginx 443) — panel y API sin puertos
- **Tipo**: infra | red | seguridad | config
- **Modificado**: victoria (10.0.0.5): nginx instalado + site `gateway.conf` (443 TLS → 127.0.0.1:8010), cert mkcert `victoria.local`/`victoria` (firmado con CA de kalimete, expira 2028-11-14) en `/etc/ssl/local-certs/`, gateway GATEWAY_HOST 0.0.0.0→127.0.0.1 (8010 loopback-only), kalimete: CA copiada a `~/rootCA-kalimete-victoria-local.crt`
- **Afecta a**: kalimete, victoria, Alfredo (Windows 10.0.0.64)
- **Causa**: usuario no podía entrar al panel (ERR_SSL_PROTOCOL_ERROR — navegador forzaba https contra HTTP plano) y pidió trabajar con TLS sin ver puertos
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - URLs finales: panel **`https://victoria.local/admin`** (login `victoria-admin`), API LAN **`https://victoria.local/v1/chat/completions`**, API pública **`https://victoria.armada.do/v1/...`** (túnel → loopback 8010, intacto).
  - Verificado: 443 admin 200 (CA validada), login 200, chat 200; 8010 ya no responde en LAN (refused); túnel 200.
  - Windows de Alfredo: instalar `~/rootCA-kalimete-victoria-local.crt` (en kalimete) en "Entidades de certificación raíz de confianza" para que https://victoria.local no marque error (mDNS/avahi activo resuelve victoria.local).
  - El gateway sigue en 8010 loopback (nginx + cloudflared lo consumen por 127.0.0.1). Middleware admin LAN-only intacto (403 vía túnel).

### [~22:00] - vLLM reconfigured: concurrencia real (13x) + fix límite total del modelo
- **Tipo**: infra | config | servicio
- **Modificado**: contenedor nemoclaw-vllm (recreado: `--gpu-memory-utilization 0.5`, `--max-num-seqs 8`, `--max-num-batched-tokens 16384`), victoria-llm-gateway (patch: normaliza model id → evita 404 por alias), opencode.jsonc kalimete + victoria (context 262144→240000, output 32768→20000)
- **Afecta a**: kalimete, victoria, repo armada-sync
- **Causa**: usuario reportó que el vLLM parecía tener 1 sola secuencia y se trancaba con requests al máximo de tokens. Diagnóstico: (1) util 0.4 → KV ~560K tokens → solo ~2 secuencias de contexto completo; (2) **clientes pedían context 262144 + output 32768 = 294912 > 262144 (límite total del modelo)** → vLLM rechaza con 400 = chat trancado; (3) gateway pasaba el model tal cual → 404 con alias.
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Resultado: KV cache **3,447,590 tokens** (~34.7 GiB), **concurrencia 13.15×** para requests de 262K (antes ~2×). Validado: 6 requests concurrentes → 200 en ~9s; output 30000 OK; chat vía dominio con alias `qwen3.6` → 200.
  - Backup del inspect del contenedor: `/home/victoria/nemoclaw-vllm-inspect-backup.json`. ⚠️ NemoClaw gestiona el contenedor (label managed-vllm) — si lo recrea, puede volver a defaults.
  - Límites clientes: 240000 + 20000 = 260000 ≤ 262144 (holgura ~2K). gateway: SERVED_MODEL env (default nvidia/Qwen3.6-35B-A3B-NVFP4).

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
