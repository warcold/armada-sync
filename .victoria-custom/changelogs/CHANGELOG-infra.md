### [2026-11-03 00:30 EDT] [stack] Huecos mejorados con mejores prácticas (petición owner): firewall LAN :8000, gate coder RAM, docs refrescadas
- **Tipo**: security + infra + docs
- **Firewall vLLM :8000 (hueco #2 CERRADO)**: el tráfico al puerto publicado pasa por FORWARD/DOCKER-USER (DNAT Docker), no por INPUT. Reglas DOCKER-USER: RETURN para 127.0.0.1 y 172.16.0.0/12 (gateway-proxy 172.17.0.1, sandbox 172.18.x, victoria-lan 172.22.x) + DROP para todo lo demás (LAN 10.x, externo). Persistido con unit oneshot `victoria-firewall-vllm.service` (enabled, After=docker.service, idempotente — patrón gpu-clock-cap; NUNCA After=multi-user.target). **E2E real desde kalimete**: LAN→10.0.0.5:8000 = 000 ANTES 200 (bloqueado), gateway loopback→vLLM = "FW-OK", sandbox 172.18.0.1→vLLM = 200, LAN→:8010 = 200 (intacto). Verificado antes: NINGÚN consumidor legítimo de :8000 desde LAN (gateway usa loopback, kalimete usa :8010).
- **Gate coder RAM endurecido (hueco #4 — swap)**: evaluación del swap 55GB: **MANTENER** — 26GB EN USO, 43 eventos NVRM NV_ERR_NO_MEMORY (nov 1-2) correlacionados con coder activo + RAM disponible 24-27GB (zona marginal UMA), 0 procesos OOM-killed, 0 freezes desde swappiness=10. El swap es load-bearing. Mejora aplicada con esa data: `CODER_START_MIN_RAM_GB=28` (drop-in systemd `coder-ram-gate.conf`, antes 20) — el coder ya no arranca presionando la UMA. Re-evaluar swap en 30 días.
- **cloudflared (hueco #5 parcial)**: 2026.10.0 ES la última del repo apt (la deriva era vs GitHub releases, que van adelante) — esperar repo, no forzar binario (rompería el paquete). Túnel 200 vía IP real CF.
- **Pendientes con receta lista (AGENTS.md §8 nueva tabla)**: #1 UPS+adaptador (OWNER físico), #2 TTS off-LAN (receta cloudflared tts.armada.do→:18810 + llave ya exigida), #3 armada-sync off-site (receta repo victoria-sync, NO el hub de kalimete), #4 swap (mantener, re-evaluar 30d), #5 derivas ComfyUI/Gradio (ventana de mantenimiento), #6 bug semanal runtime (reportable upstream).
- **Docs refrescadas (los agentes ya saben)**: openclaw.md (capacidad PDF ruta exacta + webanalyze + bug semanal), meta-business.md (fix PIL/python3.12 + diagnóstico), vllm.md (firewall + gate coder + opencode 1.19.5), AGENTS-summary (firewall), AGENTS.md §8 (blindaje LAN + tabla pendientes), harnesses openclaw/meta-business/vllm (vivo_2026_11_03).
- **Impacto**: iptables DOCKER-USER + 2 units systemd nuevos/drop-in, docs. Servicios verificados tras cambios: gateway ok, firewall active, cloudflared active, túnel 200.
- **Docs**: yes (este changelog + general + 5 docs de agentes + 3 harnesses).
### [2026-11-02 19:00 EDT] [stack] Auditoría cruzada completa victoria + kalimete (petición owner)
- **Tipo**: audit + docs + higiene
- **Validado LIVE**: 14/14 servicios systemd running (0 enabled-parados), crons todos con scripts existentes, 11/11 skills sync host↔sandbox (md5), 12 harness JSONs válidos, 14/14 changelogs de servicio presentes, scripts canónicos referenciados existen, secretos 700/600 OK, git del stack commiteado (d05ac1d).
- **Discrepancias corregidas (5)**: puerto del dashboard — AGENTS-summary `:18789`→`:18800` (carga en cada sesión), comfyui.md ×2 (bridge service + nginx /openclaw/), victoria.md topología (+ gateway binda 18789 en netns, verificado live), openclaw.md diagrama + bind (18790→18789 interno; relay socat host 18790 correcto). Cadena live verificada: 18800 (publisher) → 18790 (socat relay) → 18789 (gateway netns).
- **Falsa alarma descartada**: `victoria-voz (all)` en kalimete = modo `all` válido de opencode (primary+subagent), no el bug de symlink.
- **Higiene victoria**: eliminados imagen vLLM 26.09 sin usar + 2 sandbox images dangling + build local viejo + python:3.13-slim (~43GB liberados: 502G→459G), 2 quarantines de septiembre (documentados como obsoletos), files de test en /tmp. Docker images: 20→12.
- **Higiene kalimete**: 2 bkups stale eliminados (victoria-voz 10-27, wordpress 09-26); sync GitHub OK; ydotoold OK; disco 75%.
- **Huecos documentados (para el owner, sin acción posible desde software)**: (1) UPS + adaptador 240W (3 cortes de luz documentados); (2) vLLM :8000 abierto en LAN sin key (bypass IPv4 posible — decisión); (3) armada-sync victoria sin off-site (snapshots solo locales); (4) TTS sin exposición fuera de LAN (voz-viva roaming = solo texto); (5) swap files 55GB pendientes de evaluar tras estabilizar RAM; (6) derivas upstream menores (ComfyUI/Gradio/cloudflared) para revisión programada.
- **E2E final**: gateway ok, vLLM 200, dashboard 18800 200, inferencia "AUDIT-OK".
- **Docs**: yes (5 archivos de agentes/summary corregidos + changelog kalimete + este changelog).
# CHANGELOG — Infraestructura (Cloudflare Tunnel / Nginx / Web-Nav / respaldo)

### [2026-10-08 20:10 EDT] [infra] armada-sync: verbo `fleet` (auditoría del scaffold automatizada) + backup se incluye a sí mismo
- **Tipo**: feature + fix (cambios 100% aditivos a `armada-sync.sh`; backup/verify/restore/docsync intactos)
- **Que**: (1) **Nuevo verbo `fleet`** (`do_fleet()`): auditoría SOLO LECTURA que automatiza la auditoría manual de hoy — harness central válido → por agente: .md + frontmatter + harness JSON válido + changelogs + frescura TTL (AVISO si STALE) + resuelve en agent list → anti-duplicados (symlink prohibido, set exacto 11 .md) → boundary victoria/kalimete. Exit 0/1. (2) **`fleet` dentro de `cycle`** (no fatal): el timer 6h corre backup+docsync+fleet — lo "impecable" se auto-verifica. (3) **El backup se incluye a sí mismo** (`armada-sync.sh` en FILES — antes no se respaldaba; sin restore ante corrupción). (4) AGENTS.md §9.5 + header del script actualizados.
- **Verificado**: `bash -n` OK; `fleet` → OK (11); negativo (stray .md) → FALLA detectada → OK al limpiar; backup 37 items + verify OK sin secretos.
- **Docs**: yes (este changelog + AGENTS.md + general)

### [2026-10-08 17:25 EDT] [infra] Deep treatment CloudFlare: medición LIVE del túnel + auditoría de exposición + limites_vigentes en harness
- **Tipo**: docs + medición (SOLO medir/documentar — cero cambios de config, cero restarts)
- **Túnel LIVE**: cloudflared 2026.10.0 active since 12:42:43 EDT (4h35min al medir), token-managed (sin config.yml, ingress remoto en dashboard CF), 4 conexiones edge QUIC (iad21×2 + iad02×2), **0 reconexiones** desde boot, 3 ERR = streams /v1/chat/completions cancelados por cliente (no fallos). Métricas :20241 habilitadas (remote-managed, sin --metrics en unit), **127.0.0.1-only**: ha_connections=4, responses 200=3435, request_errors=3.
- **E2E público** (vía `--resolve` IP real CF 104.21.32.145): /health 200 (0.16s), /models 200, /v1/config-guide 200 con key readonly db13…, /admin 403. Nota: /v1/models con readonly da 403 **by design** (rol readonly no infiere — idéntico local; probe readonly correcto = /v1/config-guide, endpoint público = /models).
- **Rutas túnel**: SOLO 127.0.0.1:8010 (ingressRule=0 único; todos los requests del día a ese origin) — no expone nada más.
- **Auditoría exposición** (re-verify de la 2026-09-05): /admin túnel→403 ✓; nginx default_server 404 Host desconocido ✓; LAN /,/n8n/,/liveportrait/,/comfyui/ 200 ✓ (/openclaw/ 403 del propio gateway OpenClaw por proxy_attribution_required — dashboard se usa directo :18800 con token); ip6tables policy DROP + 3 ACCEPT (lo/established/icmpv6), DROPs específicos :8000/:18810 SUBSUMIDOS por el policy total, 712 pkts dropeados; ComfyUI 127.0.0.1:8188 ✓; OpenClaw :18800 IPv4-only ✓; SSH :1666 (victoria bash+sudo, warcold rbash/vllm-readers, root without-password) ✓.
- **Derivas doc-vs-live curadas** (cloudflare.md): AGENTS.md §7.1 dice shell victoria=/bin/bbash — live /bin/bash (bbash NO existe); RDP "escucha en *" — live servicio active SIN listener :3389 (observar). Documentadas también: ip6tables subsumido, /openclaw/ 403.
- **Harness**: `cloudflare.harness.json` + secciones `medicion_live` (versión/uptime/conexiones/E2E), `limites_vigentes` (rutas túnel, nginx+500M, IPv6 DROP, SSH, admin LAN-only), `auditoria_exposicion` (mapa completo con fecha).
- **Verificado**: JSON válido (`json.tool`); E2E 200 vía IP real CF; `opencode agent list` → CloudFlare sano; doc-fresh FRESH.
- **Docs**: yes (general — Victoria)

### [2026-10-08 15:05 EDT] [infra] Restructuring agente CloudFlare (patrón vLLM): docs oficiales + versión cloudflared curada
- **Tipo**: docs + refactor
- **Que**: §Docs oficiales (developers.cloudflare.com tunnel docs + github releases + nginx.org — verificadas vivas) + §Upstream check en `cloudflare.md`; `cloudflare.harness.json` version_cloudflared 2026.9.3→**2026.10.0** (verificado live, instalado hoy 13:15) + bloques docs_oficiales/upstream.
- **Verificado**: JSON válido, doc-fresh CloudFlare FRESH.
- **Gap profundo pendiente**: medición LIVE del túnel en el harness (estado, métricas :20241, última reconexión).

### [2026-10-08 13:15 EDT] [infra] cloudflared 2026.9.3→2026.10.0 + apt 86 pkgs security
- **Tipo**: maintenance
- **Que**: cloudflared actualizado vía .deb oficial ARM64 (GitHub release 2026.10.0) + `systemctl restart cloudflared`. apt upgrade aplicó 86 paquetes security/updates (apache2, bluez, libpng, poppler, freerdp, etc.); 21 restantes = phased Ubuntu (no forzables).
- **Verificado**: túnel 200 desde edge público (`--resolve` IP real CF); service active.
- **Docs**: yes (general)


> Servicios: `cloudflared.service`, `nginx.service`, `web-nav-server.service`, `armada-sync` (GPU tiene changelog propio `CHANGELOG-gpu.md` desde 2026-10-01)
> Responsable: `CloudFlare` (túnel/nginx/accesos) + Victoria directa (web-nav, armada-sync)
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

---

### [2026-10-05 00:30 EDT] [infra] Full update SO: 215 apt pkgs + docker 29.6.2 + kernel 7.0 + driver 580.178 (reboot pendiente)
- **Tipo**: infra (owner: full updated)
- **Que**: oleada 1 apt (~215 pkgs sin GPU/kernel: docker-ce 29.2.1->29.6.2 + containerd 2.2.5, daemon restart con contenedores reviviendo solos; fwupd 2.0.20 masked; security gnome/gstreamer/curl/apparmor). GPU batch instalado al final con holds liberados: driver 580.173.02->580.178.04, kernel 6.17.0-1031->7.0.0-1019 (DGX OTA 26.09.2, kernel viejo queda de fallback GRUB), cuda-config 13.4, linux-firmware, nvidia-container-toolkit 1.20.1, dgx-release 7.6. Reboot programado para activar. Backups previos: armada-sync 20261004-234842 + persist 1.7G + git d92f79f.
- **Verificado**: 13/13 systemd active post-oleada-1; tunel cloudflared active; nginx rutas 200; needrestart relanzo servicios sin errores.
- **Docs**: yes (general 00:30)


### [2026-10-03 16:50 EDT] [opencode] Sampling por rol en los 11 agentes + model default local + todowrite-discipline (Victoria directa)
- **Tipo**: config | best-practices (pedido del owner; validado contra la model card nvidia/Qwen3.6-35B-A3B-NVFP4 — SciCode/coding 0.6/0.95, general 1.0/0.95 — y espejo de la doctrina kalimete 2026-10-03 15:00)
- **Que**: (1) frontmatter `temperature` (+`top_p` en creativos) en los 11 agentes: Victoria 0.6+0.95, Meta Business y Sonic 0.6+0.95 (creativos: copy social, guiones), los 8 infra (vLLM, OpenClaw, Comfyui, RSS, Weather, CloudFlare, Liveportrait, Gpu) 0.1 (determinismo tool-use/APIs) — antes TODOS corrían al default 1.0 del modelo; (2) opencode.jsonc: `"model": "vllm/nvidia/Qwen3.6-35B-A3B-NVFP4-normal"` default de sesiones nuevas (backup `.bkup-20261003-sampling`) + `todowrite-discipline.md` como 2ª instruction (dueño de la lista = Victoria, subagentes no escriben la del padre #12938, item de verificación, vaciar al cerrar); (3) harness v2.4.0: temperature reflejada en central + 10 individuales + `default_model` en el principal; (4) AGENTS.md §5.0 con la doctrina de sampling documentada + §5 tabla con el default model.
- **Verificado**: opencode.jsonc JSON válido; `opencode agent list` OK (Victoria+10 resuelven); 11 harness JSON válidos; grep 8× 0.1 + 3× 0.6 en frontmatters.
- **Impacto**: requests de subagentes salen con temperature explícita → vLLM ya no aplica 1.0 por default; sesiones nuevas arrancan en el cerebro local (no en el free opencode rate-limited).
- **Docs**: yes (AGENTS.md §5.0, AGENTS-summary.md, harnesses, esta entrada + general). Efectivo tras reiniciar TUI.

### [2026-10-01 03:45 EDT] [harness] Subagentes visibles en el @ autocomplete (Victoria directa)
- **Tipo**: fix/UX del harness opencode (pedido explícito del owner)
- **Que**: los 10 subagentes pasan de `hidden: true` (no salían en `@`, solo se invocaban por Task/@Nombre escrito a ciegas) a `hidden: false` — ahora salen TODOS en el autocomplete `@` del TUI. Tab sin cambios (solo primaries Plan/Build/Victoria; los subagent nunca salen ahí, es opencode puro). Archivos tocados: 10 frontmatters `.md` + 11 harness JSON + `victoria.md` + `AGENTS-summary.md` + `harness/README.md`. Efectivo en sesión nueva de opencode (los frontmatters se cargan al arrancar).
- **Por que**: el diseño hide (documentado horas antes ese día) escondía a los 10 del `@`; el owner quiere VERLOS para decir "trabaja con @Liveportrait" y que el autocomplete lo resuelva.
- **Verificado**: grep 0 `hidden: true` en agentes+harness; 11 JSON válidos; `opencode agent list` resuelve los 11 agentes sanos.
- **Docs**: yes (general + esta entrada + docs del harness)

### [2026-10-01 02:10 EDT] [updates] cloudflared 2026.9.1→2026.9.3 (túnel victoria.armada.do)
- **Tipo**: update (autorización explícita del owner: todo lo derivado del upstream)
- **Que**: .deb `cloudflared-linux-arm64` 2026.9.3 (build 2026-09-24) vía `dpkg -i` + `restart cloudflared` (SOLO el túnel; nginx y gateway intactos). Backup previo del binario 2026.9.1 en `/tmp/cloudflared-2026.9.1.bkup` (rollback no necesario).
- **Hallazgo de canal**: NO hay repo apt (paquete `installed,local`) — el canal canónico es .deb directo de GitHub; la API `api.github.com/.../cloudflared` da 404 tras el proxy, los tags se verifican en la página HTML.
- **Verificado**: `--version` 2026.9.3; unit active con 4 conexiones QUIC registradas, journal sin DNS/backoff; público `https://victoria.armada.do/health` → 200 vía `--resolve` a IP real CF (104.21.41.113); LAN `https://victoria.local/` → 200; Host desconocido → 404; métricas `:20241` → 200; SSH :1666 y RDP :3389 intactos.
- **Docs**: yes (general + esta entrada + cloudflare.md §canal + harness con versión)

### [2026-10-01 02:05 EDT] [reporte] Daily Report consume el Sync: UPSTREAM + DOCS en WhatsApp
- **Tipo**: feature (cierra el círculo pedido por el owner: el sync avisa por WhatsApp)
- **Que**: el `armada-sync cycle` (6h) ya escribía `state/upstream.json` + `state/frescura.json` pero nadie los miraba. Ahora el reporte los lee: derivas local→loopstream + edad del chequeo + edad del snapshot + docs FRESH. Sin timers ni crons nuevos (reusa el cycle + el cron 0,8,12,16,20 del reporte).
- **Verificado**: `--dry-run` con datos live del cycle (upstream 0h, snapshot 0h).
- **Docs**: yes (general + esta entrada + social)

### [2026-10-01 01:55 EDT] [sync] Unificación: cycle en armada-sync, muere el timer separado
- **Tipo**: refactor (un solo sistema)
- **Que**: `cycle` = backup + docsync (guarda 24h); service apunta a `cycle`; units `victoria-upstream-sync.*` eliminadas. Regla standing: docs pre-aprobados, servicios no.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 01:50 EDT] [frescura] doc-fresh + upstream-sync diario (tooling Victoria directa)
- **Tipo**: feature (automatización)
- **Que**: `doc-fresh.sh` (TTL 24h) + `upstream-sync.py` + timer 05:00 ET (units en /etc/systemd/system). Primer run: 3 derivas reportadas, 0 cambios aplicados.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 01:45 EDT] [doctrina] Frescura: live manda (harness + summary)
- **Tipo**: docs
- **Que**: regla de frescura en harness central + línea en summary (con fix `default_agent` stale).
- **Docs**: yes (general + esta entrada)

### [2026-10-01 01:30 EDT] [agentes] Gpu se independiza (changelog propio); infra queda túnel/nginx/web-nav/respaldo
- **Tipo**: docs (split)
- **Que**: gpu-saver sale de este changelog (→ `CHANGELOG-gpu.md` + subagente `Gpu`); `CloudFlare` suma SSH/warcold/RDP/métricas; web-nav documenta wrappers `OpenClaw`.
- **Docs**: yes (general + esta entrada + gpu)

### [2026-10-01 01:15 EDT] [agentes] Minúsculas + fin del symlink duplicador + default Victoria
- **Tipo**: fix (estructura)
- **Que**: agentes y harness a minúsculas; symlink `agent→agents` eliminado (duplicaba); `default_agent` → `"Victoria"` exacto (case-sensitive verificado). Sin cambios a túnel/nginx.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 01:00 EDT] [agentes] Segunda ronda renombres (vLLM/RSS System/Meta Business) — infra intacta
- **Tipo**: docs (reflejo)
- **Que**: sin cambios a túnel/nginx; solo nombres en docs. Header ya dice `CloudFlare` + Victoria directa.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 00:50 EDT] [agentes] Nuevo subagente CloudFlare (túnel + nginx) + renombres simples
- **Tipo**: refactor (claridad)
- **Que**: nuevo `CloudFlare.md` (hide) con su `CloudFlare.harness.json`: cloudflared + nginx + reglas (nada público sin orden, /admin LAN-only, backup gateway.conf antes). Renombres a `Ragnarok/OpenClaw/Comfyui/Sonic/Rss/Social/Weather`, todos en hide; Victoria única visible.
- **Impacto**: Victoria directa conserva gpu-saver + web-nav. Cero servicios tocados.
- **Verificado**: frontmatters + JSON OK.
- **Docs**: yes (general + esta entrada)

### [2026-10-01 00:40 EDT] [harness] Harness Victoria: principal morada + hide sandbox + 8 JSON
- **Tipo**: feature (estructura agentes)
- **Que**: harness central `victoria.harness.json` + 7 dedicados + README en `~/.victoria-custom/harness/`; `victoria.md` color `#8B5CF6` + tabla con changelog/harness; `nemoclaw-sandbox-ops` hide; `opencode.jsonc` default_agent victoria; `armada-sync.sh` respalda harness.
- **Impacto**: Victoria directa (estructura). Cero servicios tocados.
- **Verificado**: 8 JSON OK, opencode.jsonc OK, frontmatters OK.
- **Docs**: yes (general + esta entrada + victoria.md + summary)

### [2026-09-29 23:40 EDT] [sync] Red armada-sync resucitada: fix crash hub + bin/ + topología documentada
- **Tipo**: fix (la red llevaba muerta: cada corrida del cron moría sin commit/push)
- **Causa**: `agent/*.md` locales son symlinks al repo → `cp -f` sobre su propio target = error "same file" → `set -e` abortaba el hub ANTES de commit+push. Síntomas: `pull --rebase` bloqueado por cambios sin commitear + log con `cp: same file` cada 5 min.
- **Que kalimete** (autorizado): `sync.sh` parcheado (backup `sync.sh.bkup-20260930`): guard `[ -ef ]` skip en collect + bloque BIN (solo texto a `repo/bin/`: cfmb25, tmp-clean, new-project, SCRIPTS.md; fuera `.phar`/ELF/`*.bak*`; `wp` excluido por binario — el match de "secretos" era falso positivo del phar). Recuperación: commit + push `4c84fac` OK (incluye limpieza del `.bkup` + `bin/` nuevo). 2da corrida: "No local changes" = estado estable, auto cada 5 min sano.
- **Que victoria**: timer 6h activo + cobertura completa (summary, devices, ledgers, bin). NO se conecta al repo GitHub por diseño: el deploy follower destructivo borraría los agentes del stack. Topología documentada en `AGENTS-summary.md`. Off-site de victoria pendiente (repo nuevo + credenciales, decide el owner).
- **Verificado**: pull+collect+push E2E OK; `bash -n` OK; cron sigue cada 5 min; `opencode.jsonc` excluido del sync GitHub (key viva).
- **Docs**: yes (AGENTS-summary.md §Topología + esta entrada + CHANGELOG-infra.md).

### [2026-09-29 23:25 EDT] [ecosistema] Sistema reutilizable: scaffold + temporales KEEP + librerías + registro LAN
- **Tipo**: feature (eficiencia — pedido del owner: no adivinar, ejecutar scripts bien hechos; cada dir nuevo con guía; temporales reciclables)
- **Que victoria**: `~/tmp/` + `tmp-clean.sh` (DRY-RUN default, respeta `<x>.keep` y `KEEP.list`, `--apply` para borrar) + `new-project.sh <nombre> [destino]` (crea dir + `AGENTS.md` desde plantilla + `scripts/` + README; probado y limpiado) + `bin/SCRIPTS.md` (índice 20 scripts: buscar ANTES de crear; mejorar > duplicar). Regla: script reusado >1 vez se PROMUEVE a librería con header.
- **Que kalimete**: `~/tmp/` + mismos `tmp-clean.sh`/`new-project.sh` (idénticos, diff 0) en `~/bin/` + `bin/SCRIPTS.md` (ptt, wrapper, cfmb25, wp, osint — cfmb25/wp con uso por completar).
- **Red hogar**: `.victoria-custom/infra/devices.md` (router, victoria, kalimete con accesos; 5 IPs por identificar: .102/.134/.29/.230/.64 — falta que el owner diga qué son). Otros dispositivos pueden consumir LLM/voz/UIs por LAN con llave (flujo config-guide como kalimete).
- **Sync**: `armada-sync.sh` FILES += `AGENTS-summary.md`, `infra/devices.md`, `Documents/Victoria Armada/AGENTS.md` (+ `bin/` ya cubría los scripts nuevos); backup 32 items verify OK.
- **Verificado**: scaffold crea+limpia OK; tmp-clean DRY-RUN en ambas; diff tmp-clean victoria↔kalimete = 0; verify sin secretos.
- **Docs**: yes (SCRIPTS.md ×2, devices.md, ~/tmp/README ×2, esta entrada + CHANGELOG-infra.md).

### [2026-09-29 22:55 EDT] [kalimete] Nombres lindos dual: `· www.alfredo.pro | P/L`
- **Tipo**: config (estética — pedido del owner: volver al branding lindo + sufijo P/L)
- **Que**: providers Kalimete: `vllm` → `· www.alfredo.pro | P` (pública roaming), `vllm-lan` → `· www.alfredo.pro | L` (LAN casa). Backup `bkup-20260930-names`. JSON válido.
- **Docs**: yes (esta entrada).

### [2026-09-29 22:50 EDT] [kalimete] Dual roaming: vllm (pública) + vllm-lan (casa)
- **Tipo**: config (decisión del owner: kalimete es laptop que sale de la LAN)
- **Que**: Kalimete conserva la pública como default (`vllm` → `https://victoria.armada.do/v1`, roaming siempre conecta) y suma `vllm-lan` → `http://victoria.local:8010/v1` (rápida en casa, 5ms, sin Cloudflare). Ambos con `context 120000 + timeout 3600s`. Backup `bkup-20260930-dual`. En casa usar `vllm-lan`, fuera `vllm`. Futuro opcional: Tailscale (misma URL dentro/fuera, sin CF) — no instalado en ninguno, queda propuesto.
- **Verificado**: desde Kalimete en casa LAN:200 y PUB:200. JSON válido.
- **Docs**: yes (AGENTS-summary.md + esta entrada).

### [2026-09-29 22:35 EDT] [contexto+agentes] Fix compactación prematura 100K + reparación total agentes victoria+kalimete
- **Tipo**: fix + docs (contexto, agentes, sync — pedido del owner: "repara todo, optimiza estructura, limpia discrepancias")
- **Causa raíz compactación 100K**: `instructions: ["AGENTS.md", "agents/victoria.md"]` = 232KB (~57K tokens) en CADA request → sistema 57K + historial 40K = 100K → opencode compactaba joven por peso del manual, no del trabajo. VLM sano (KV 12.5%, prefix 79%, 0 rechazos hoy); sesiones `alfredo` en 117K/120K al borde del 400.
- **Que victoria.local**: (1) Nuevo `~/.config/opencode/AGENTS-summary.md` (slim ~5K tokens, mapa+límites+subagentes+kalimete) y `opencode.jsonc` → `instructions: [AGENTS-summary.md]` (backup `bkup-20260930-contextfix`). (2) `name:` agregado a `comfyui-ops/vllm-stack-ops/nemoclaw-sandbox-ops.md` (sin name el Task no invoca). (3) Symlink `~/.config/opencode/agent` → `agents/` (compat opencode 1.18 singular/plural). (4) Ledger `Documents/Victoria Armada/AGENTS.md` creado + README con sección ledger. (5) `AGENTS.md` §6: frontmatter obligatorio + summary + symlink. (6) `armada-sync.sh`: FILES += `AGENTS-summary.md`, verify must += summary; backup+verify OK (30 items, 1.4M, sin secretos).
- **Que kalimete.local** (excepción autorizada al contrato): (1) `opencode.jsonc` backup `bkup-20260930-120k-fix`: `context 220000→120000` (fósil era 262K; gateway corta en 120K), `baseURL https://victoria.armada.do/v1` → `http://victoria.local:8010/v1` (LAN 5ms, era loop WAN con IP pública 69.143.73.120), `timeout 300s→3600s` + `chunkTimeout 120s→600s` + `maxRetries: 3`. Verificado `/health` + `/v1/config-guide` por LAN (key alfredo, limits 120K). (2) Agentes: symlink roto `eco-micaserogou.md` eliminado (target inexistente), `agents/` → `agent/` compat creado, `wordpress-dev.md.bkup-20260926` movido a `bkup-agents/` (no cargar bakups como agentes). (3) Ledger `~/armada-arcade/AGENTS.md` creado.
- **Limpieza**: 0 `.bkup` en dirs de agentes victoria; kalimete agent/ sin rotos; bkups viejos con keys quedan locales 600 (no se sync, verify OK).
- **Verificado**: victoria `opencode.jsonc` JSON válido; kalimete config-guide LAN 200 con limits correctos; `find agent/ -xtype l` vacío en ambas; armada-sync backup+verify OK; VLM `/metrics` KV 12.5%.
- **Docs**: yes (AGENTS.md §6, README Victoria Armada, ledgers nuevos, esta entrada + CHANGELOG-vllm.md + CHANGELOG-infra.md).

### [2026-09-29 22:00 EDT] [docs+config] instructions rotas + protocolo contexto por proyecto
- **Tipo**: docs + config
- **Que**: (1) `opencode.jsonc`: `instructions ["victoria.md"]` (inexistente) → `["AGENTS.md", "/home/victoria/.config/opencode/agents/victoria.md"]` (requiere restart TUI). (2) Protocolo de Contexto por Proyecto (victoria.md § nuevo + AGENTS.md §9.6 + plantilla `~/.victoria-custom/templates/AGENTS-project-template.md`): ledgers `AGENTS.md` por proyecto para no quemar contexto global. (3) AGENTS.md §4/§7/§9.5 + victoria.md (paths, servicios, No-Touch, auth :18840, delegación). Detalle en CHANGELOG general misma fecha.
- **Verificado**: JSON válido; 14 units + 4 dockers + 12 puertos OK.
- **Docs**: yes

### [2026-09-21 00:20] daily-report: historial de errores 24h + sección gateway (cierre petición owner)
- **Tipo**: fix + feature (reportería; el owner recibió el reporte 00:00 con error fósil del 18/09 y sin lo del gateway)
- **Que**: `victoria-daily-report.py`: (1) "último error" ahora filtra ÚLTIMAS 24H con fecha/hora (antes: grep sin fecha → el ALERTA rss del 18/09 salía eterno); líneas sin timestamp se ignoran. (2) Nueva sección `ERRORES · Historial de los últimos errores registrados (24h)` con línea Gateway (`hoy N · rep <timestamp_reporte> · ult: <descripcion> [<timestamp>]`, leído del `/health`) + conteo de logs recientes + bloque `📌 Historial...` con los últimos 2 (crudos, con su fecha/hora). El dashboard 000 del reporte era REAL (relay 18790 muerto; reparado por sandbox-ops, ver CHANGELOG-sandbox).
- **Verificado**: `py_compile` OK, `--dry-run` muestra sección ERRORES + 2 errores reales del 20/09 10:20 (502s en ventana de arranque vLLM) en vez del fósil; tras el fix del relay, `Panel web ... OK`.
- **Docs**: yes (general + este)

### [2026-09-20 20:25] AUDITORÍA: NINGÚN software puede apagar la máquina → entrega de energía física
- **Tipo**: auditoría (petición del owner: otros equipos encendidos en la misma zona)
- **Veredicto**: software 100% limpio — sin poweroff/shutdown/halt en ningún script/daemon/cron; OnFailure vacío; unattended-upgrades inactive; cmdline sin panic= (pánico congela, no apaga); sin power-key events; cero Xid GPU; cero térmicos; watchdog NO puede ser (activado 13:58 hoy; cortes #1/#2 anteriores; reset GWDT = reboot, no "OFF"); pstore vacío en los 3 cortes; telemetría sin entradas.
- **Conclusión**: los 3 cortes (sáb 21:21, dom 05:21, hoy 16:34) = entrega de energía a ESTA máquina: cable flojo / regleta fallando / OCP de fuente / fuente envejeciendo. Checklist físico: reasentar cable, quitar regleta, otro enchufe, otro cable, UEFI AC Power Recovery=Power On, si persiste → fuente (garantía).
- **Docs**: yes (CHANGELOG general + este)

### [2026-09-20 20:05] observe-24h.py desplegado (collector de observación 24h)
- **Tipo**: infra/observabilidad (petición del owner: "agrega alertas para registrar logs durante el monitoreo")
- **Qué**: `/home/victoria/observe-24h.py` + cron `*/15`. CERO impacto en inferencia: sqlite `file:...?mode=ro`, nvidia-smi (query al driver), `/health` con timeout 3s, jamás escribe en la DB del gateway. Snapshot cada 15 min en `~/logs/observation-24h.log`: requests/rejects por razón, tokens, p50/p95 latencia, engine, GPU, RAM, load, anomalías (diff por id), circuit breaker. Alertas `** ALERT **` (grep): nueva_anomalia, circuito_abierto, vllm_down, vllm_container_down, gateway_down, ram_baja(<16G), gpu_temp_alta(>=80C), gap_temporal(>45m = corte eléctrico). WhatsApp SOLO para container_down/gateway_down/ram_baja/gpu_temp_alta (sin alertero propio) con cooldown 2h/tipo.
- **Cierre con aprobación del owner**: a las 24h solo marca `** 24H COMPLETADAS **` + 1 aviso WA y sigue coleccionando; el cierre lo ejecutamos juntos: `observe-24h.py report` (preview, sin WA) → owner aprueba → `observe-24h.py report --send` (WA + cierre). Borrar el state = nueva observación.
- **Contexto**: el crash de hoy 16:34 (3er corte de energía en 3 días) ocurrió SIN este collector vivo (quedó pendiente por interrupción — miss reconocido). Desplegado y verificado post-reboot.
- **Verificado**: collect/status/report-preview OK, cron instalado, primer snapshot completo (req/eng/gpu/ram/anom/circ/vllm), watchdog SBSA re-activo tras reboot.
- **Docs**: yes (CHANGELOG general + este + AGENTS.md)

### [2026-09-20 14:05] Anti-freeze del host: watchdog HW 180s + OOM protection + heartbeat del loop-alert
- **Tipo**: infra/hardening (petición del owner: "evitemos que los freez dejen la máquina inutilizable; la encuentro apagada")
- **Forense apagones primero**: los boots -1 y -2 terminaron ABDUPTOS (05:21 AM dom, 21:58 sáb) en plena actividad y SIN mensajes de shutdown ⇒ **cortes de energía eléctrica** (no crashes lógicos; pstore vacío; antecedente documentado del apagón 2026-09-17). El 15-sep 19:17 fue el único freeze lógico. Dos causas, dos fixes distintos.
- **Watchdog hardware**: `RuntimeWatchdogSec=180` + `RebootWatchdogSec=10min` en `/etc/systemd/system.conf` (descomentados con sed). Verificado en journal: `Using hardware watchdog 'SBSA Generic Watchdog', version 0, device /dev/watchdog0` + `Watchdog running with a timeout of 3min`. Si el KERNEL se congela → reboot automático en 3 min (antes: máquina colgada hasta que el owner llegara). NOTA: no cubre cortes de luz (eso es UEFI/físico: ver pendiente del owner).
- **OOM protection**: drop-ins `/etc/systemd/system/<svc>.service.d/override.conf` con `OOMScoreAdjust=-500` (victoria-llm-gateway, docker, cloudflared, nginx) y `-750` (ssh). Verificado con `systemctl show`. El OOM killer ataca sacrificables (default 0) antes que la infraestructura de acceso (ssh/túnel/gateway).
- **loop-alert heartbeat**: 1 línea diaria "monitor vivo" en el log (`_hb_ts` en state, tolerado en load_state y excluido del cleanup). Dead man's switch: la AUSENCIA de heartbeat >24h = alertero muerto. Verificado en vivo (primera línea heartbeat escrita 13:57).
- **journald persistente**: verificado YA persistente (`/var/log/journal` + Storage=auto) — por eso la forense de boots previos fue posible. Sin cambios.
- **Pendiente del owner (físico)**: (1) UEFI del DGX Spark: **"AC Power Recovery = Power On"** para que la máquina encienda sola cuando vuelve la luz tras un corte; (2) opcional: UPS. El watchdog no puede contra un corte eléctrico.
- **Docs**: yes (CHANGELOG general + este + AGENTS.md §4)

### [2026-09-19 11:45] Nginx: `location = /openclaw` para el WS sin slash (dashboard HTTPS)
- **Tipo**: fix
- **Que**: La UI usa `wss://<host>/openclaw` (bare, sin slash) y el browser no sigue el 301 en handshake WS → 1006. Agregado exact-match con rewrite a `/` + Upgrade/timeouts (backup `gateway.conf.bkup-20260919-openclaw-bare` + copia en `.victoria-custom/backups/`). Verificado 101 en bare y con slash.
- **Docs**: yes (CHANGELOG general + este + comentario inline)

### [2026-09-18 23:50] Grupos del stack documentados (infra = grupo 5)
- **Tipo**: docs (organización, OK del owner)
- **Que**: Los 5 grupos del stack quedaron documentados en victoria.md §Grupos del Stack + AGENTS.md §1.5: 1. vLLM, 2. OpenClaw/nemoclaw, 3. Sentidos, 4. Contenido, **5. Infra** (cloudflared, nginx, gpu-saver, armada-sync — Victoria directa, sin dockers, recovery via systemd units + /etc configs). Organización por labels Docker (`victoria.group=<grupo>`), NO compose ni mover paths. Cron auto-apply deshabilitado (ver CHANGELOG sandbox).
- **Impacto**: solo documentación (los servicios de infra NO fueron tocados).
- **Verificado**: cloudflared/nginx/gpu-saver/web-nav active; docs actualizadas.
- **Docs**: yes (CHANGELOG general + este + victoria.md + AGENTS.md)

### [2026-09-18 19:00] Validación post-recreación sandbox — infra sin cambios
- **Tipo**: docs (verificación, sin cambios)
- **Que**: Los servicios de infraestructura NO fueron tocados durante la recreación del sandbox: cloudflared active (túnel victoria.armada.do → 127.0.0.1:8010), nginx active (SSL LAN victoria.local + default_server 404), gpu-saver active (protección vLLM/VRAM), web-nav-server active (Playwright + Chromium :18820).
- **Verificado**: `systemctl is-active` → active en los 4; túnel + nginx + nav funcionando.
- **Docs**: yes (este changelog)
