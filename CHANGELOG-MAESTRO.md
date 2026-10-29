# CHANGELOG MAESTRO UNIFICADO — Victoria Armada + kalimete (2026-10-29)

> Índice cruzado de TODOS los changelogs del ecosistema. Cada entrada referencia su changelog de origen.
> Formato: `[FECHA] [SERVICIO/HOST] titulo — changelog_origen`

---

## 2026-10-29

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 01:55 | Victoria | **vLLM** | Harness estandarizado schema unificado; GET /v1/granja desplegado (12 servicios + probes); provisioning delegado activo; admision adaptativa FRÍO/CALIENTE | CHANGELOG-vllm.md |
| 01:55 | Victoria | **OpenClaw** | Harness estandarizado; sandbox UP (11 plugins, 5 bridges, 2 canales, policies egress); drift-check bidireccional granja | CHANGELOG-sandbox.md |
| 01:55 | Victoria | **Comfyui** | Harness estandarizado; ComfyUI v0.42.0 + aimdo 0.6.0 + kitchen 0.2.40; LivePortrait 6.29.0; n8n 2.42.5; Hunyuan3D-2 + Animar-chat; GPU compartida | CHANGELOG-comfyui.md |
| 01:55 | Victoria | **Sonic** | Harness estandarizado; Sonic UP (single-flight, VRAM 5.3G/24G, GPU arbitro); audio propio en tab Estudio Podcast; licencia CC BY-NC-SA 4.0 | CHANGELOG-sonic.md |
| 01:55 | Victoria | **RSS System** | Harness estandarizado; 13 feeds, 7012 articles, 772 extracts, scan */2h + enrich cap 40; DevTo removido | CHANGELOG-rss.md |
| 01:55 | Victoria | **Meta Business** | Harness estandarizado; IG token OK (exp ~2026-12-04), Discord/WhatsApp broadcasts vivos, daily report OK, branding -30% | CHANGELOG-social.md |
| 01:55 | Victoria | **Weather** | Harness estandarizado; APIs UP (Open-Meteo/wttr.in/Nominatim/Overpass/weather.gov/country.io 200); rate limits vigentes | CHANGELOG-weather.md |
| 01:55 | Victoria | **CloudFlare** | Harness estandarizado; cloudflared 2026.10.0 UP (4 conexiones edge); nginx UP; IPv6 DROP total; SSH 1666 UP; E2E publico 200 | CHANGELOG-infra.md |
| 01:55 | Victoria | **Liveportrait** | Harness estandarizado; Gradio 6.29.1 + 8 fixes; pesos 2.0G; VRAM ~3G; 3 locks arbiter; tab Estudio Podcast pipeline Sonic + audio propio | CHANGELOG-liveportrait.md |
| 01:55 | Victoria | **Gpu** | Harness estandarizado; GPU GB10 121GB visibles, 50.6GB usados, 5 holders; watchdog carga sostenida + clock cap + swappiness 10; /free falso positivo FIXED | CHANGELOG-gpu.md |
| 01:30 | Victoria | **Flota** | Auditoría sincronización cross-machine (petición owner) + fixes doc-level: catálogo puertos granja en kalimete (5 puertos faltantes), TTLs doc-fresh renovados (Victoria/vLLM/OpenClaw FRESH 24h) | CHANGELOG.md |
| 00:45 | Victoria+kalimete | **Flota** | Seguridad labs (4 puertos loopback), docs_oficiales kalimete (3 gaps), MCP Blender E2E, prep ventana prod Micaserogou (3 artefactos sha256 OK, deploy bloqueado en owner) | CHANGELOG.md + kalimete CHANGELOG.md |
| 00:49 | kalimete | **Hub** | Sync 00:49 (granja-drift-kalimete.py + skills fuente viva) | kalimete CHANGELOG.md |
| 00:48 | kalimete | **victoria-server** | Catálogo puertos granja verificado LIVE (5 puertos faltantes: 8188/8180/18820/18830/5678) | kalimete CHANGELOG.md |
| 00:48 | kalimete | **Conocimiento** | Lección MCP Blender (respuesta sin newline; E2E get_scene_info) | kalimete CHANGELOG.md |
| 00:48 | kalimete | **Harness** | docs_oficiales completados (3 gaps: armada-templates, assetto, wordpress; 29 ya los tenían) | kalimete CHANGELOG.md |

---

## 2026-10-28

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 23:45 | kalimete | **Zion CRM** | Fusión: ZionV CRM + Armada Suite → Zion CRM 2.0.0 (plugin unificado) | kalimete CHANGELOG.md |
| 23:30 | kalimete | **Zion CRM** | Armada Suite integrado en Zion CRM 2.0.0 | kalimete CHANGELOG.md |
| 23:00 | kalimete | **Zion CRM** | Inicio fusión ZionV CRM + Armada Suite | kalimete CHANGELOG.md |
| 22:40 | kalimete | **EccoSuit** | Deploy CSP-nonce a prod VPS (commit 612ea50) | kalimete CHANGELOG.md |
| 20:30 | Victoria | **Flota** | Auditoría profunda flota completa + 8 lenguajes nuevos + MCPs + cobertura 100% agents/harnesses | CHANGELOG.md |
| 04:45 | kalimete | **acServer** | Fix acServer | kalimete CHANGELOG.md |

---

## 2026-10-26

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 15:45 | Victoria | **vLLM** | NGC vLLM 26.09 BLOQUEADO (driver >=615.71 inexistente); clock cap 300/2100 MHz + swappiness 10 aplicados; plymouth masked | CHANGELOG-vllm.md |
| 15:45 | Victoria | **Comfyui** | ComfyUI v0.42.0 + aimdo 0.6.0 + kitchen 0.2.40 (actualizacion conjunta requerida) | CHANGELOG-comfyui.md |

---

## 2026-10-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 02:00 | Victoria | **vLLM/Gpu/OpenClaw** | Forense freeze 2026-10-13 + triple blindaje: sandbox RestartPolicy=unless-stopped, gpu-saver watchdog carga sostenida, gateway valvula 5 (motor sin pausas 10min -> gap 8s) | CHANGELOG-vllm.md + CHANGELOG-gpu.md + CHANGELOG-sandbox.md |

---

## 2026-10-09

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **Comfyui** | Hunyuan3D-2 :18860 + Animar-chat :18861 desplegados (single-flight, gpu_arbiter, sense_auth) | CHANGELOG-comfyui.md |
| — | Victoria | **Liveportrait** | Animar-chat :18861 desplegado (lp-animate daemon + presets 01/02/03) | CHANGELOG-liveportrait.md |

---

## 2026-10-08

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 20:25 | Victoria | **Gpu** | /free falso positivo FIXED (body vacio = exito); LivePortrait 3 holders; clock cap 300/2100 + swappiness 10 | CHANGELOG-gpu.md |
| 20:25 | Victoria | **OpenClaw** | Medicion LIVE post-fix tormenta 1,111x VLLMValidationError: models.mode=replace + contextWindow 220000/32000 | CHANGELOG-sandbox.md |
| 19:50 | Victoria | **Weather** | Re-validacion E2E completa: 6 APIs 200, Overpass Miami 79 restaurantes, Nominatim Mexico City | CHANGELOG-weather.md |
| 19:30 | Victoria | **Meta Business** | IG token renovado, Discord/WhatsApp broadcasts, daily report OK, branding -30% | CHANGELOG-social.md |
| 17:20 | Victoria | **CloudFlare** | Auditoria exposicion re-verificada: cloudflared 2026.10.0, nginx UP, IPv6 DROP total, SSH 1666, E2E 200 | CHANGELOG-infra.md |

---

## 2026-10-07

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 07:45 | Victoria | **Meta Business** | Instagram publisher ACTIVO en @victoria.armada.do (cuenta real); OAuth via /ig-callback; formato imagen original + logo marca -30% | CHANGELOG-social.md |
| 07:10 | Victoria | **Meta Business** | Instagram auto-publisher desplegado (pendiente credenciales owner) | CHANGELOG-social.md |

---

## 2026-10-05

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **OpenClaw** | Dashboard chain corregida: publisher :18800 -> relay :18790 -> gateway interno (ownership proof nemoclaw v0.0.130) | CHANGELOG-sandbox.md |
| — | Victoria | **OpenClaw** | Audio propio en tab Estudio Podcast (uploader nota de voz -> Sonic directo, sin TTS) | CHANGELOG-liveportrait.md |

---

## 2026-10-04

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 00:45 | kalimete | **victoria-gui** | RETIRADA + limpieza rastros (ronda 5) | kalimete CHANGELOG.md |

---

## 2026-10-03

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **Gpu** | Art API gateway es consumidor del arbol (holder comfy-art, sweeper 30s); 429 gpu_busy = cola normal | CHANGELOG-gpu.md |
| — | Victoria | **OpenClaw** | Stack voz unificado: Qwen3-TTS unico motor (XTTS/coqui eliminados); voz real Victoria clonada (Librivox) + acento nativo ES/EN | CHANGELOG-voice.md |

---

## 2026-09-29

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 20:15 | Victoria | **Sonic** | Tab Estudio Podcast en LivePortrait: guion EXACTO a duracion + pre-escucha audio REAL + gpu_wrapped_execute_podcast + biblioteca-podcast.json + guia movimiento hibridada | CHANGELOG-sonic.md |

---

## 2026-09-28

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 19:20 | Victoria | **Comfyui** | Pipeline video LTX-2.5 ELIMINADO (modelos, scripts, servicios). Nuevo stack: LivePortrait + ComfyUI + n8n. InvokeAI NO compatible ARM64. | CHANGELOG-comfyui.md |
| 19:20 | Victoria | **Liveportrait** | UI v2 ES: 3 tabs (Animar/Retoque facial/Retoque video), fotos Victoria ejemplos, CSS propio, guardias ES, retry launch 3x5s, root_path, client_max_body_size 500M | CHANGELOG-liveportrait.md |

---

## 2026-09-20

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **Infra** | RuntimeWatchdogSec=180 (SBSA GWDT) -> reboot auto si kernel freeze. OOMScoreAdjust: -500 gateway/docker/cloudflared/nginx, -750 ssh. Observacion 24h cron */15. | CHANGELOG-infra.md |

---

## 2026-09-18

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 19:00 | Victoria | **OpenClaw** | Re-arquitectura dashboard: gateway OpenClaw en HOST + changelogs por servicio (11 archivos). Publisher :18800 (network host -> 127.0.0.1:18790 relay). | CHANGELOG-sandbox.md |

---

## 2026-09-17

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **Infra** | Apagón + internet tardío runbook: boot local no espera ISP; cloudflared aguanta ~30 min reintentos; crons perdidos sin daño. | CHANGELOG-infra.md |

---

## 2026-09-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **Infra** | armada-sync creado: respaldo automatizado conocimiento (6h timer, backup + docsync + fleet). Excluye secretos/binarios. Retencion 30 snapshots. | CHANGELOG-infra.md |

---

## 2026-09-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **vLLM** | Admision adaptativa: engine poller muestrea vLLM /metrics c/2s -> FRÍO/CALIENTE en /health.engine. Valvulas 1-4 + 4b (intervalo min 15s) + 5 (carga sostenida). Retry dinamico + medición honesta + costo efectivo. | CHANGELOG-vllm.md |

---

## 2026-09-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **vLLM** | Válvula 4b: prefills 40K+ requieren >=15s desde anterior (misma key, todos roles) -> 429 large_prompt_rate_limited + Retry-After dinamico. Volumen bajado 8M->4M como red secundaria. | CHANGELOG-vllm.md |

---

## 2026-09-15

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 22:10 | Victoria | **vLLM** | Igualdad total: bypass admin ELIMINADO (owner: "admin es acceso, no privilegio inferencia"). 4 valvulas iguales para todos. | CHANGELOG-vllm.md |

---

## 2026-09-15

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 23:15 | Victoria | **vLLM** | Válvula 4b (intervalo minimo): prefills 40K+ requieren >=15s -> 429 + Retry-After dinamico. Nacio de freeze por stress test propio (86 reqs 35-60K en 6 min, 1.5M tokens, TODO bajo topes -> host colgado). | CHANGELOG-vllm.md |

---

## 2026-09-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 21:30 | Victoria | **vLLM** | Valvula 4: prefills 100K+ max 6/min (luego 100K/6 flexibilizado) -> 429 large_prompt_rate_limited. Cierra hueco ritmico (freeze 19:17: 150K c/5s x2min = 1.8M/min, dentro topes, GPU 100% prefill continuo). | CHANGELOG-vllm.md |

---

## 2026-09-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 12:00 | Victoria | **vLLM** | Proteccion real = CONCURRENCIA, no contexto. Semáforo global UPSTREAM_MAX_CONCURRENCY=3 + por key UPSTREAM_MAX_PER_KEY=2 + cola 90s. Admision por TOKENS: valvula 1 (prefill 300K), 2 (tokens/min 4M), 3 (RAM 16GB), 4 (prompts 100K max 4/min). | CHANGELOG-vllm.md |

---

## 2026-09-08

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| — | Victoria | **vLLM** | gpu-mem-util 0.4->0.25 (KV 42->24 GiB); seqs 4->6; luego 09-29 seqs 6->4 + KV explicito 12GiB (libera ~9 GiB para Sonic/OS). | CHANGELOG-vllm.md |

---

## 2026-08-31

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 02:45 | Victoria | **Voz** | Voz real Victoria clonada (Librivox Little Eve Edgarton) + pipeline clonacion. Script reutilizable clone-voice.sh. | CHANGELOG-voice.md |
| 02:21 | Victoria | **Voz** | Limpieza duplicados voz (~2.5GB) + codigo obsoleto + fix backup + sentidos verificados. | CHANGELOG-voice.md |

---

## 2026-08-30

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 22:36 | Victoria | **OpenClaw** | Fix permisos: tools.deny a nivel grupo rompía owner (bucle "procedo"). Fix: quitar deny grupo + toolsBySender con wildcard * + owner especifico (id:/e164:). | CHANGELOG-sandbox.md |
| 04:20 | Victoria | **vLLM** | Precios v3 recalibrados a costo real: Input $0.10/1M, Output $0.30/1M (output 3x = estandar). Costo real ~$0.0253/1M. Metering streaming FIX: gateway inyecta stream_options.include_usage=true + parsea chunk SSE final -> 99.97% trafico SÍ cuenta. | CHANGELOG-vllm.md |

---

## 2026-08-29

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 14:36 | Victoria | **Infra** | Endurecimiento acceso: Web UI solo LAN, firewall IPv6 DROP total (policy DROP + lo/established/icmpv6), nginx default_server 404. DMs solo owner. | CHANGELOG-infra.md |
| 13:34 | Victoria | **Voz** | Voz total activada: Discord voice (stt-tts), WhatsApp voice notes, Web UI tts-local-cli. Permisos: publico solo chat (tools.deny 15 tools), owner conserva todo via toolsBySender tipado (id:/e164:). | CHANGELOG-voice.md |
| 03:56 | Victoria | **Host Admin** | Host Admin Bridge :18840 (autonomia Victoria): exec/apt/service allowlists + API key + audit log. 100% local/gratis. | CHANGELOG-host-admin.md |

---

## 2026-08-28

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 20:10 | Victoria | **Whois** | Fallback RDAP para TLDs no soportados (.pro) + skill domain (command:domain) para Victoria. | CHANGELOG-whois.md |
| 01:35 | Victoria | **Whois** | Servicio whois host + bridge sandbox (whois 5.5.22 en host, sandbox no puede instalar + TCP 43 bloqueado). | CHANGELOG-whois.md |

---

## 2026-08-27

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 22:30 | Victoria | **OpenClaw** | Fix "Victoria le dice papá a desconocidos": identidad con senderIsOwner (llamar papá SOLO si owner; si false -> NUNCA papá/creador; negar con firmeza). | CHANGELOG-sandbox.md |
| 17:55 | Victoria | **OpenClaw** | Fix limites contexto opencode (context 220000 + output 32000 = 252K < 262K). Config sandbox alineada schema real plugins (discord reactionNotifications en guilds, whatsapp mentionPatterns objeto, ackReaction sin enabled). models.json agente: input ["text","image"] (video via video-server). | CHANGELOG-sandbox.md |

---

## 2026-08-24

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 22:35 | Victoria | **Infra** | Reboot mantenimiento + fix CRITICO permisos sandbox: /sandbox/.openclaw modo 700 -> 2770 (gateway uid 998 no podia escribir). Blindaje permanente en ensure-loop. | CHANGELOG-infra.md |

---

## 2026-08-19

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 18:45 | Victoria | **WhatsApp** | Whitelist egress sandbox: preset social-sites (12 policies 33+ endpoints: redes, news CDNs, weather, general-wallcard wildcard). CERO DENIEDs. | CHANGELOG-sandbox.md |
| 05:20 | Victoria | **Video** | Stack video desplegado: yt-dlp + ffmpeg + whisper en HOST :18811 (download/frames/transcribe/analyze todo-en-uno con VLM). Bridge UNIX socket + wrappers sandbox + skill video. | CHANGELOG-video.md |
| 04:10 | Victoria | **Broadcast** | Footer normalizado: linea en blanco + sin · inicial. WhatsApp + Discord. | CHANGELOG-social.md |
| 03:10 | Victoria | **Broadcast** | Auto-distribucion noticias a WhatsApp (Tech Hub): 3 grupos, LLM opinion 40 palabras, imagen feed, anti-dup state. Fix media upload: patch fetchAgent=undefined en Baileys + policy egress tls:skip. | CHANGELOG-social.md |
| 00:33 | Victoria | **vLLM** | Streaming real (StreamingResponse + aiter_bytes, no buffer). Creacion llaves simplificada (solo Nombre + Tier). Nginx proxy_read_timeout 86400 + buffering off. | CHANGELOG-vllm.md |

---

## 2026-08-18

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 13:20 | Victoria | **Broadcast** | Auto-distribucion noticias a Discord (Tech Hub): #ethical-hackers + #penetration-testers, cron 4h (07/11/15/19/23), LLM opinion 40 palabras. Solo TH. | CHANGELOG-social.md |

---

## 2026-08-17

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 06:15 | Victoria | **Voz** | Stack voz MOVIDO AL HOST (fix Python 3.13 incompatible con coqui-tts). voice-venv python3.12 + torch cu128 + Qwen3-TTS 0.6B-Base ICL 24kHz unico motor. systemd victoria-voice-server.service. | CHANGELOG-voice.md |
| 06:00 | Victoria | **WhatsApp** | Fix "Victoria no reconoce owner": dmPolicy pairing + allowFrom [18295468686] (owner pasa directo; desconocidos pairing). Persistido en 3 sitios. | CHANGELOG-sandbox.md |
| 01:15 | Victoria | **Identidad** | Blindaje anti-repeticion perdida identidad: persist.sh detecta templates (grep "Fill this in") y reemplaza con maestro host ANTES de backup. ensure_identity_files detecta template por contenido. Subagentes validados. | CHANGELOG-sandbox.md |
| 00:12 | Victoria | **Identidad** | Fix "Victoria no reconoce por WhatsApp": identidad template + active-memory perdidos. ensure_identity_files detecta template por contenido (no mtime). active-memory en overrides + re-aplicado. | CHANGELOG-sandbox.md |

---

## 2026-08-16

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 23:24 | Victoria | **Persistencia** | Auditoria completa: sandbox SIN volumen /sandbox/.openclaw (solo binds RO TLS/token). Test destructivo end-to-end SUPERADO: template fabrica -> ensure-loop detecta via session.identityLinks -> persist.sh auto restaura -> flag .gateway-restart-needed -> pkill gateway -> supervisor revive. Fix crash-loop ensure-loop (set -u bugs). Backup final 174M sincronizado. | CHANGELOG-sandbox.md |
| 22:50 | Victoria | **WhatsApp** | Fix definitivo: trust record para openKeyedStore (install record correcto en SQLite: source=npm, spec=@openclaw/whatsapp, resolvedName=@openclaw/whatsapp). Script openclaw-whatsapp-fix.sh + ensure-loop. | CHANGELOG-sandbox.md |
| 15:30 | Victoria | **ComfyUI** | Fase 1+2+3: Discord streaming humanizado (18 labels) + active-memory cross-canal + RSS blogwatcher persistente + identidad SOUL.md memoria cross-canal. | CHANGELOG-comfyui.md |
| 04:30 | Victoria | **ComfyUI** | Fix SAM3_VideoTrack cuDNN failure GB10 (sm_121a): upgrade comfy-venv cu128->cu130 (torch 2.11.0+cu130 + torchvision/torchaudio/triton). comfy_kitchen backend cuda habilitado (49 capabilities). | CHANGELOG-comfyui.md |
| 04:20 | Victoria | **Contenido** | Victoria content bundle: 6 templates Victoria-template-* + 13 videos referencia + docs alineada. Symlinks 9 imagenes + 13 videos a ComfyUI/input/victoria-reference/. | CHANGELOG-comfyui.md |
| 02:50 | Victoria | **vLLM** | Fix IPv6 blindaje: ip6tables -I INPUT 1 -p tcp --dport 8000 -j DROP (bloquea inbound IPv6 a vLLM, mantiene IPv4 localhost/docker bridge/LAN). Persistido netfilter-persistent. | CHANGELOG-vllm.md |
| 02:30 | Victoria | **Seguridad** | Audit exposicion Internet: solo tunel CF publico; dashboards NO. Riesgo unico: vLLM [::]:8000 dual-stack si router permite inbound IPv6. | CHANGELOG-vllm.md |
| 02:00 | Victoria | **Identidad** | Victoria re-escrita: humanoid, hija de Alfredo Armada (dueño Alfredo Pro LLC). No revela tech; femenina; business: IT support/cloud/automation/software dev/consulting; subs $100/mo. | CHANGELOG-sandbox.md |

---

## 2026-08-15

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 19:45 | Victoria | **ComfyUI** | Idle-saver desplegado + fix crash-loop: daemon monitorea /queue+/history c/30s, SIGTERM 10min idle -> libera 8-30GB VRAM. Fix: reset last_history_ts tras kill (evita crash-loop cada 30s). | CHANGELOG-comfyui.md |
| 02:55 | Victoria | **vLLM** | Modelo SÍ es VLM nativo (vision_config depth 27, hidden 1152, 16 heads, RGB + tokens 248053-248057). Validado PNG rojo 8x8 -> "rojo" 200. opencode.jsonc migrado a modalities/attachment/tool_call/reasoning (schema oficial). | CHANGELOG-vllm.md |

---

## 2026-08-14

| Hora | Host | Servicio | Cambio | Changelog Origen |
|------|------|----------|--------|------------------|
| 23:45 | Victoria | **OpenClaw** | Dashboard accesible via network-bridge: red victoria-lan 172.22.0.0/16, sandbox IP 172.22.0.10, proxy openclaw-bridge.py (0.0.0.0:18789 -> 10.200.0.2:18789 netns interno) + publisher. Verificado HTTP 200 + WS 101 + connect.challenge. | CHANGELOG-sandbox.md |
| 23:00 | Victoria | **vLLM** | Rename sandbox my-assistant -> victoria-armada. Subagente nemoclaw-sandbox-ops.md auto-actualizable. CHANGELOG.md creado. | CHANGELOG.md |
| 22:40 | Victoria | **Infra** | Blindaje reboot-readiness: victoria-llm-gateway.service + cloudflared.service (enabled, Restart=always, After/Wants). Bind 0.0.0.0:8010 confirmado. Orden boot: docker -> gateway -> cloudflared. | CHANGELOG-infra.md |
| 22:00 | Victoria | **vLLM** | readonly restringido a SOLO /v1/config-guide + /health (antes podia chat completions). Prompt §7.4 ajustado. | CHANGELOG-vllm.md |
| 21:20 | Victoria | **vLLM** | Endpoint GET /v1/config-guide añadido (guia auto-descriptiva sin secretos para agentes remotos). Prompt bootstrap §7.3. | CHANGELOG-vllm.md |
| 20:55 | Victoria | **vLLM** | Tunel Cloudflare victoria.armada.do verificado (/health, /v1/config-guide, chat completions 200 via HTTPS). Prompt publico §7.4 con auto-deteccion host + key readonly inline. | CHANGELOG-vllm.md |
| 20:10 | Victoria | **vLLM** | Audit corte prematuro conversaciones largas (~118k tokens): output 20000->32000 (finish_reason length -> stop natural). Validado request max_tokens 32000 -> 14120 tokens stop. | CHANGELOG-vllm.md |
| 19:30 | Victoria | **vLLM** | Rol readonly añadido; usuario warcold creado (SSH read-only + API key readonly); wrapper sqlite3ro; sudoers victoria NOPASSWD. | CHANGELOG-vllm.md |
| 18:40 | Victoria | **vLLM** | Contenedor nemoclaw-vllm eliminado (causa outage). Relanzado receta canonica; inferencia recuperada; branding · www.alfredo.pro alineado. | CHANGELOG-vllm.md |
| 16:08 | Victoria | **vLLM** | Gateway v2 + admin panel reescritos (v1->v5). | CHANGELOG-vllm.md |
| 15:23 | Victoria | **vLLM** | Onboard nemoclaw completo, sandbox my-assistant creado, vLLM lanzado. | CHANGELOG-vllm.md |

---

## ÍNDICE DE CHANGELOGS POR SERVICIO

| Servicio | Archivo | Host |
|----------|---------|------|
| General (maestro) | `/home/victoria/CHANGELOG.md` | Victoria |
| vLLM + Gateway | `~/.victoria-custom/changelogs/CHANGELOG-vllm.md` | Victoria |
| OpenClaw Sandbox | `~/.victoria-custom/changelogs/CHANGELOG-sandbox.md` | Victoria |
| Voz (TTS/STT) | `~/.victoria-custom/changelogs/CHANGELOG-voice.md` | Victoria |
| Video | `~/.victoria-custom/changelogs/CHANGELOG-video.md` | Victoria |
| Whois | `~/.victoria-custom/changelogs/CHANGELOG-whois.md` | Victoria |
| Host Admin | `~/.victoria-custom/changelogs/CHANGELOG-host-admin.md` | Victoria |
| ComfyUI + LivePortrait + n8n + Hunyuan3D + Animar | `~/.victoria-custom/changelogs/CHANGELOG-comfyui.md` | Victoria |
| Sonic Podcast | `~/.victoria-custom/changelogs/CHANGELOG-sonic.md` | Victoria |
| RSS System | `~/.victoria-custom/changelogs/CHANGELOG-rss.md` | Victoria |
| Meta Business (IG/DC/WA) | `~/.victoria-custom/changelogs/CHANGELOG-social.md` | Victoria |
| Weather | `~/.victoria-custom/changelogs/CHANGELOG-weather.md` | Victoria |
| Infra (CF/nginx/SSH/armada-sync) | `~/.victoria-custom/changelogs/CHANGELOG-infra.md` | Victoria |
| GPU | `~/.victoria-custom/changelogs/CHANGELOG-gpu.md` | Victoria |
| Hub kalimete | `~/armada-sync/CHANGELOG.md` | kalimete |

---

**Última actualización**: 2026-10-29 01:55 EDT  
**Mantenido por**: Victoria Armada (orquestadora)  
**Regla**: Cada cambio en servicio/subagente -> entrada en changelog servicio + changelog general + este maestro.