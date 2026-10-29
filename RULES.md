# RULES.md — Reglas de Negocio y Operativas Consolidadas (2026-10-29)

> Fuente única de verdad para reglas dispersas en AGENTS.md, victoria.md, CHANGELOGs, harnesses, subagentes.
> Pre-aprobado por el owner (2026-10-01): actualizar documentación vs live/upstream sin preguntar.
> **LIVE manda**: si el doc discrepa del estado real -> gana LIVE, se cura el doc + changelog.

---

## 1. ARQUITECTURA Y DELEGACIÓN

### 1.1 Jerarquía de Agentes
- **Victoria** (principal, morada #8B5CF6, `default_agent: Victoria`) = única en Tab, orquesta TODO.
- **10 subagentes Victoria** (visibles en @, `hidden:false`): vLLM, OpenClaw, Comfyui, Sonic, RSS System, Meta Business, Weather, CloudFlare, Liveportrait, Gpu.
- **kalimete** (principal teal, host hermano 10.0.0.106) = 30 subagentes propios, hub GitHub `warcold/armada-sync`.
- **Regla de oro**: kalimete NO ejecuta, solo delega/verifica/responde. Victoria delega a subagentes via Task.

### 1.2 Protocolo de Delegación (OBLIGATORIO)
```bash
# ANTES de delegar con Task:
1. LEER harness del subagente objetivo
2. EJECUTAR live_check del subagente
3. Si live_check -> down: NO delegar, reportar estado + recovery
4. Si up: delegar con Task incluyendo: "lee primero <harness_file> y actualízalo al terminar"
5. POST: verificar que subagente actualizo harness + changelog + doc; Victoria escribe CHANGELOG general
```

### 1.3 Anti-Ejecución-Directa en Primaries
- Victoria y kalimete SOLO delegan (Task) o construyen lo pequeño (Build).
- NUNCA ejecutan directamente lo que un subagente cubre (Plan vs Build).
- Excepción: Build = edición local, debug conocido, health check, respuesta consulta.

---

## 2. GESTIÓN DE CONTEXTO Y DOCUMENTACIÓN

### 2.1 Contexto por Proyecto (Ledger AGENTS.md)
- Cada proyecto/prototipo en `Documents/`, `Desktop/`, repo, `~/.victoria-custom/estudio/` lleva su `AGENTS.md` (ledger).
- Al empezar: leer ledger (mapa, decisiones, pendientes). Si no existe y >1 sesión o >3 archivos -> crearlo desde template.
- Al terminar sesión: actualizar ledger (~60 líneas: qué se hizo, decisiones, pendientes).
- Si tocó stack: ADEMÁS CHANGELOG general + changelog(s) servicio. Ledger referencia, no duplica.
- Subagentes via Task: prompt incluye "lee primero `<proyecto>/AGENTS.md` y actualízalo al terminar".
- NUNCA pegar contexto global en ledger (referenciar por ruta).

### 2.2 Frescura (LIVE manda, protocolo 2026-10-01)
1. **LIVE primero**: diagnóstico SIEMPRE empieza con estado real (systemctl, curl :health, docker ps, nvidia-smi, journalctl, opencode agent list, ss -tlnp).
2. **DOC después**: el doc trae receta (flags, topología, no-touch, historia). Es plano, no edificio.
3. **Si discrepan**: actuar sobre LIVE, curar doc + changelog (servicio + general), reportar deriva.
4. **Docs upstream** (GitHub, foros, vendor): solo via web cuando LIVE no explica fallo. No cachear como verdad permanente.
5. Cada subagente lleva línea `> **Frescura**` arriba: verificar live antes de actuar y curar doc si discrepa.

### 2.3 Harness = Contrato Único de Verdad
- Cada agente/subagente tiene harness JSON con: `vivo_YYYY_MM_DD`, `live_check`, `checks[]`, `upstream.fuente`, `docs`, `docs_oficiales`, `changelog[]`, `no_touch`, `recovery`, `delegacion`.
- El harness ES el contrato. El .md del agente es prompt operativo que REFERENCIA el harness.
- Schema unificado en `~/.victoria-custom/harness/HARNESS_SCHEMA_UNIFICADO.md`.

---

## 3. CHANGELOGS Y TRAZABILIDAD

### 3.1 Regla de Tres Lugares
Cada cambio que toca un servicio/subagente DEBE reflejarse en:
1. Doc del subagente correspondiente (`.md`)
2. Su harness JSON
3. CHANGELOG del servicio + CHANGELOG general (Victoria) / CHANGELOG maestro

### 3.2 Formato Changelog
```markdown
### [YYYY-MM-DD HH:MM EDT] [servicio] descripcion breve
- **Tipo**: fix|feature|refactor|docs|infra|security
- **Que**: Descripcion
- **Por que**: Motivacion (si no obvio)
- **Impacto**: Componentes que tocan
- **Verificado**: Como se validó
- **Docs**: yes/no
```

### 3.3 Changelog Maestro
`~/.victoria-custom/CHANGELOG-MAESTRO.md` = índice cruzado de TODOS los changelogs con referencia a origen.

---

## 4. STACK VICTORIA (DGX SPARK GB10) — REGLAS TÉCNICAS

### 4.1 vLLM + Gateway (SAGRADOS)
- **Digest PINNEADO**: `nvcr.io/nvidia/vllm@sha256:9204569b...` (NUNCA tag movil)
- **Flags inmutables**: `--max-model-len 262144` (256K nativo) + `--max-num-seqs 3` + `--gpu-memory-utilization 0.22` + `--kv-cache-memory-bytes 12884901888` (12GiB) + `--tool-call-parser qwen3_xml` + `--default-chat-template-kwargs {enable_thinking:false}`
- **Contexto opencode**: `context 220000 + output 32000 = 252000 ≤ 262144` (headroom ~10K)
- **Gateway limits**: `MAX_PROMPT_TOKENS=220000` igual para TODOS los roles (equidad total). Exceder -> 400 `prompt_tokens_exceeded`.
- **Protección real = CONCURRENCIA**: semáforo global 3 + por key 2 + cola 90s + admisión adaptativa (FRÍO/CALIENTE) + valvulas 1-5.
- **Firewall IPv6 :8000 DROP** (NUNCA quitar). Acceso: IPv4 localhost/docker bridge/LAN.
- **readonly key**: SOLO `/v1/config-guide` + `/v1/catalog` + `/v1/client-config` + `/health` + `/models`. NUNCA inferencia.

### 4.2 OpenClaw Sandbox (CONTAINER = EFÍMERO)
- **NUNCA confiar en estado del container**: `docker rm -f` / rebuild -> todo `/sandbox/.openclaw` se pierde.
- **Snapshot ANTES**: `bash /home/victoria/openclaw-persist.sh backup`
- **Gatillo rebuild**: `session.identityLinks` ausente = template fabrica -> persist.sh auto restaura.
- **Plugins npm**: SIEMPRE uid 998 (`runuser -u sandbox`), NUNCA root (root re-escribe openclaw.json 600 -> crash-loop).
- **extensions/**: debe quedar `root:root`; `chown -R sandbox:sandbox` lo bloquea.
- **Dashboard chain**: publisher :18800 (Docker --network host) -> relay :18790 (openshell forward service) -> gateway INTERNO sandbox.
- **Policies egress**: `personal-open-internet` = switch maestro (subsume especificos). `nemoclaw policy` SOLO como victoria (runuser + PATH absoluto).

### 4.3 Sentidos (HOST, puertos 18810-18850)
| Puerto | Servicio | Auth | Notas |
|--------|----------|------|-------|
| 18810 | Voz TTS/STT (Qwen3-TTS + Whisper) | llave gateway admin/services | localhost+docker sin llave; LAN con llave |
| 18811 | Video (yt-dlp+ffmpeg+whisper) | llave gateway admin/services | |
| 18820 | Web-nav (Playwright) | filtro IP + llave gateway admin/services | |
| 18830 | Whois (whois 5.5.22 + RDAP fallback) | llave gateway admin/services | |
| 18840 | Host Admin | **bridge key O rol admin PURO** (2026-10-19: `sense_role(elevate=False)` exige `role=="admin"`) | 401 sin llave = NORMAL (no caída) |
| 18850 | Sonic (podcast talking-head) | sense_auth (llave admin/services) | single-flight, VRAM ~24GB |
| 18860 | Hunyuan3D (image->3D GLB) | sense_auth (cap art eleva) | single-flight, turno hunyuan3d-standalone |
| 18861 | lp-animate (foto->mp4) | sense_auth (cap art eleva) | single-flight, turno lp-animate kind liveportrait |

**Auth unificada**: `sense_auth.py` valida llaves gateway admin/services contra DB viva (sha256, active, no expirada). Multi-tier: llave con `art/tts/whisper/liveportrait/comfyui` en `allowed_models` eleva a services. `provision` NUNCA eleva.

### 4.4 Contenido (GPU COMPARTIDA via gpu_arbiter.py)
- **ComfyUI** :8188 (imagenes: z-image-turbo/flux-schnell/sd15-realistic via art API gateway)
- **LivePortrait** :8180 (talking-head SOTA + tab Estudio Podcast)
- **Sonic** :18850 (podcast talking-head + reels)
- **Hunyuan3D-2** :18860 (image->3D GLB)
- **Animar-chat** :18861 (foto->mp4 via LivePortrait CLI)
- **n8n** :5678 (orquestador visual)
- **Regla GPU**: `gpu_arbiter.py` = un pesado a la vez (lock `/home/victoria/logs/gpu-heavy.lock`, stale 5h). 503 ocupado, 429 ≥80C, Comfy en cola bloquea. `free_comfy` ANTES de tomar lock.
- **Clock cap**: `nvidia-smi -lgc 300,2100` (anti-sobrecorriente 2026-10-26). Swappiness 10 (2026-10-26).
- **Watchdog carga sostenida**: util ≥85% ventana 10min -> alerta WA + fallback Discord si WA falla 2x.

### 4.5 Distribución (Meta Business)
- **IG**: @victoria.armada.do (feed 3-4/sem + stories 1-2/dia, cron */20 9-21 EDT). Token refresh lunes 04:00. Formato: imagen original articulo + logo marca inf-der lw=230 (-30%).
- **Discord**: #ethical-hackers TH (cron mar 12:30, jue 19:30, dom 19:00).
- **WhatsApp**: 3 grupos TH (cron mar 13:00, jue 20:00, dom 19:30).
- **Regla owner**: NUNCA publicar por cuenta propia — solo broadcasts RSS aprobados + UIs nativas; chat solo aconseja.
- **Anti-dup**: states en `~/.victoria-custom/state/{instagram,discord,whatsapp}-sent.json`.

### 4.6 Infra (CloudFlare + nginx + SSH)
- **Tunel CF**: `victoria.armada.do` -> `127.0.0.1:8010` (SOLO gateway). `/admin` LAN-only (middleware rechaza CF-Connecting-IP -> 403).
- **nginx**: `victoria.local` solo LAN (server_name + default_server 404). Rutas: `/`->8010, `/n8n/`->5678, `/liveportrait/`->8180, `/comfyui/`->8188, `/openclaw/`->18800. `client_max_body_size 500M` en `/n8n/ /liveportrait/ /comfyui/`.
- **IPv6**: `ip6tables -P INPUT DROP` + lo/established/icmpv6 (persistido `/etc/iptables/rules.v6` via netfilter-persistent). 712 pkts dropeados.
- **SSH**: puerto 1666. `victoria` (bash, sudo) + `warcold` (rbash, grupo vllm-readers, password `colador`). `sqlite3ro` wrapper read-only DB.
- **RDP**: gnome-remote-desktop active PERO sin listener :3389 visible.

---

## 5. KALIMETE (HOST HERMANO) — CONTRATO

### 5.1 Relación
- **No mezclar trabajo sin preguntar**: Victoria NO modifica kalimete, kalimete NO modifica Victoria, sin permiso explicito owner.
- **Se conocen como agentes**: Victoria -> desarrollo/ethical (kalimete); kalimete -> inferencia/contenido/redes (Victoria).
- **Cross-machine = SSH explicito con TARGET**: `ssh -i ~/.ssh/id_victoria -p 1111 warcold@kalimete.local` + verificar `hostname` ANTES de mutar.

### 5.2 Consumo de Granja Victoria
- kalimete usa gateway Victoria: LAN `victoria.local:8010` (provider `vllm-lan`) / Internet `victoria.armada.do` (provider `vllm`).
- Llave `kalimete` (coder + caps `llm/art/tts/whisper/provision`) -> consume: LLM, art API, TTS/STT, Hunyuan3D, lp-animate, provisioning.
- **host-admin :18840**: 401 por DISEÑO con llave kalimete (rol admin puro exigido; kalimete consume recursos, NUNCA opera la maquina).
- **Provisioning**: `POST /v1/provision-key` (rol admin o cap `provision`) -> crea llaves `armada-*` rol services caps `[llm]` fijos, auditoria `provision_log`. Primera: `armada-magantech` (2026-10-20).

### 5.3 Sync y Hub
- **kalimete = HUB**: `~/armada-sync/sync.sh` cada 5 min (cron) -> GitHub `warcold/armada-sync` (agents/skills/commands + bin/ solo-texto). `opencode.jsonc` NUNCA se sync (lleva key viva).
- **Victoria = snapshots LOCALES**: `armada-sync.sh` cada 6h (timer) en `~/.armada-sync/` (opencode.jsonc REDACTADO, verify anti-secretos). Victoria NO es follower del repo GitHub.
- **Conexión off-site**: pendiente decision owner (nuevo repo + credenciales).

---

## 6. SEGURIDAD Y SECRETOS

### 6.1 Secretos
- **NUNCA commitear**: `~/.victoria-custom/secrets/data.txt` (HF_TOKEN + nvapi keys), `llm-gateway.db`, `auth.json`, tokens.
- **Solo via env o archivo 600**: `chmod 600` dentro de dir 700 (solo victoria).
- **Regla anti-leak (2026-09-19)**: secretos SOLO via env/archivo 600, JAMÁS hardcodeados en scripts/plantillas/docs.
- **Excepción documentada**: readonly `vllm-key-db13...` SÍ vive en docs (solo config-guide, revocable desde `/admin`).

### 6.2 API Keys Gateway
| Key | Rol | Acceso |
|-----|-----|--------|
| `vllm-key-811...` | admin | Total (admin panel + API) |
| `vllm-key-5d4...` | admin | Total |
| `vllm-key-434...` | coder | API + metering/budget propio |
| `vllm-key-db1...` | readonly | SOLO config-guide/catalog/client-config + health/models publicos |
| `kalimete` | coder + caps | llm/art/tts/whisper/provision (multi-tier) |
| `armada-*` | services | SOLO llm (provisioning delegado) |

### 6.3 Multi-tier por Llave (2026-10-03)
- Columna `allowed_models` (JSON 8 caps: `llm/art/liveportrait/comfyui/tts/whisper/n8n/provision`).
- Panel admin: checkboxes + presets (crear/editar). Añade caps a matriz rol.
- `sense_auth` honra override: llave con caps eleva a services para sentidos.
- `provision` NUNCA eleva (poder del gateway, no un sentido).

---

## 7. OBSERVABILIDAD Y FORENSE

### 7.1 Gateway: Detección Anomalías Tiempo Real (2026-09-20)
- **Flight recorder**: ring 300 req en memoria -> dump forense `anomaly-<key>-<ts>.json` al disparar anomalia (retencion 14 dias).
- **Burst detection**: ≥10 fallos/key en ≤30s -> fila `anomaly_events` + dump + alerta WhatsApp INMEDIATA (cooldown 900s/key).
- **Circuit breaker**: tras burst -> cooldown 60s con 429 `circuit_breaker` + Retry-After (auto-cura).
- **Warming_up**: vLLM down 3 polls (~6s) -> 503 `warming_up` + Retry-After 120.
- **Taxonomía fallos**: `reject_reason` clasificado + `head_hash`/`stream` en `usage_log`.

### 7.2 Alertero Anti-Loop (cron */15)
- Niveles: L1 AVISO ≥10 (recordatorio 4h), L2 LOOP ≥50 (1h), L3 CRITICO ≥150 (30min + consejo matar sesion).
- Heartbeat diario 1 linea "monitor vivo" (ausencia >24h = alertero muerto).

### 7.3 GPU Metrics (caja negra)
- `victoria-metrics.db` (SQLite WAL, retencion 30d): system_metrics/vllm_metrics/tick_info c/30s.
- Sobrevive freezes/reboots. Timestamps ya son hora LOCAL (NO usar `localtime` en SQLite).

### 7.4 Observación 24h (cron */15)
- Collector cero-impacto: snapshot c/15min en `~/logs/observation-24h.log` (requests/rejects/latencias/engine/GPU/RAM/anomalias/circuit) + alertas `** ALERT **` grep-eables + WhatsApp para 4 condiciones sin alertero propio.
- Gaps >45 min = firma corte electrico.

---

## 8. UPSTREAM Y VERSIONES

### 8.1 Política General
- **LIVE manda**: lo no verificado se marca pendiente, nunca se inventa.
- **Upgrades = Plan + owner** (revision trimestral para vLLM/nemoclaw; ante incidente para resto).
- **Digest PINNEADO** para vLLM (NUNCA :latest/:tag movil).
- **Upstream awareness**: saber qué rama tiene qué, quién es owner (Vincent = owner EccoSuit, kalimete = deploy only).

### 8.2 Fuentes por Componente
| Componente | Upstream | Frecuencia | Política |
|------------|----------|------------|----------|
| vLLM | NGC @sha256:9204569b + HF model card + GitHub releases | Trimestral / ante CVE | Digest PINNEADO; NGC 26.06+ bloqueado (driver >=615.71) |
| nemoclaw/openshell | nemoclaw source read-only + docs.openclaw.ai | Ante incidente / salto runtime | Upgrades runtime = Plan + owner |
| ComfyUI | GitHub master + comfy-aimdo/kitchen (pip) | upstream-sync.py 6h | Plan + owner (custom nodes pueden romper) |
| LivePortrait | KlingAIResearch/LivePortrait (HEAD 9b294b3d = origin/master) | upstream-sync.py 6h | app.py custom: NUNCA sobreescribir sin leer fixes |
| Sonic | jixiaozhong/Sonic (CVPR 2025, sin releases) | upstream-sync.py 6h | Comercial -> Tencent VCLM (decision owner) |
| blogwatcher | Hyaxia/blogwatcher v0.0.4 | upstream-sync.py 6h | Si v0.0.5+: rebuild Go estatico |
| cloudflared | GitHub releases (deb-directo) | upstream-sync.py 6h | NO auto-update; manual + backup + E2E |
| Driver/CUDA | Kernel NVIDIA host (pinned) | Ante incidente | NO actualizar sin Plan + owner |

---

## 9. RECUPERACIÓN Y DISASTER RECOVERY

### 9.1 Stack Completo (Reboot/Power Failure)
```
boot -> docker.service (enabled) -> nemoclaw-vllm (restart=unless-stopped, 5-7min carga)
       -> sandbox openshell-victoria-armada-* (restart=unless-stopped, healthy)
       -> victoria-llm-gateway.service (enabled, After=docker, Restart=always)
       -> cloudflared.service (enabled, After=gateway, Restart=always)
       -> demas systemd services (enabled, Restart=always/on-failure)
```
- **Ventana servicio**: T+0..5s gateway/sandbox/cloudflared; T+5..7min vLLM carga (502 normal).

### 9.2 Cortes Electricos + ISP Tardío
- Boot local NO espera ISP. cloudflared aguanta ~30 min reintentos (StartLimitBurst=100/1800s).
- Crons perdidos sin daño (armada-sync.timer Persistent=true se pone al dia).
- Chequeo post-apagon: `systemctl --failed` + tunel via IP real CF con `--resolve`.

### 9.3 Recuperación por Componente
| Componente | Recuperación |
|------------|--------------|
| vLLM contenedor | Receta canonica docker run (vllm.md) — confirmacion owner primero |
| Gateway | `sudo systemctl restart victoria-llm-gateway` (stateless salvo SQLite) |
| Sandbox | `nemoclaw destroy + onboard --fresh` -> ensure-loop restaura en ~2-5 min |
| GPU freeze | victoria-gpu-saver detecta (4 probes hung) -> docker restart nemoclaw-vllm (cooldown 15min) |
| Locks GPU | Stale 5h -> auto-limpia. NUNCA matar vLLM; liberar ComfyUI via /free |

---

## 10. REGLAS DE ORO (RESUMEN EJECUTIVO)

1. **LIVE manda** — validar estado real antes de actuar; curar doc si discrepa.
2. **Harness = contrato** — live_check ANTES de delegar; checks[] para validación profunda.
3. **Tres lugares** — cambio = doc subagente + harness JSON + changelog servicio + general.
4. **Delegación estricta** — Task con pre-check live_check; primaries NO ejecutan lo que cubren subagentes.
5. **Contexto por proyecto** — ledger AGENTS.md por proyecto; no pegar contexto global.
6. **Frescura TTL 24h** — doc-fresh.sh antes de Task con cambios; STALE = deep-check en Task.
7. **Sync único** — armada-sync.sh cycle (6h backup + docsync + fleet + granja-drift).
8. **Cross-machine** — SSH explicito con TARGET + verificar hostname; no tocar sin permiso owner.
9. **Secretos** — solo env/archivo 600; NUNCA commitear; readonly key compartible por diseño.
10. **NUNCA dañar lo que funciona** — reglas documentadas son sagradas; si no documentadas -> documentarlas mientras las descubres.

---

**Versión**: 1.0 (2026-10-29)  
**Mantenido por**: Victoria Armada (orquestadora)  
**Ubicación**: `/home/victoria/.victoria-custom/RULES.md` + espejo en kalimete `~/armada-sync/RULES.md`