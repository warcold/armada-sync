# CHANGELOG — Voice Server (TTS/STT :18810)

### [2026-10-27 18:15 EDT] [voice] Fix "sonidos extraños": normalizador TTS-hostil (horas 21:27, rangos 2-5, em-dashes) — fin de los runaways de 74s/frase
- **Tipo**: fix (reporte del owner: "evaluar el comportamiento y los sonidos extraños"; forense con los logs reales del PTT 17:33-17:37)
- **Forense**: la respuesta del agente de voz (lista de 7 sesiones con horas "21:27", rangos "2-5", em-dashes) disparó **generación desbocada de Qwen3-TTS**: 2 frases de **74.0s y 73.4s** (tope 512 tokens ≈ 42s de audio basura + generación = los "sonidos extraños"), stream total de 16 frases/233.7s, owner tuvo que barge-in. El normalizador existente cubría dinero/siglas/% pero NO horas ni rangos ni guiones largos.
- **Que**: `normalize_for_tts()` +3 reglas antes de sintetizar (el texto visible nunca cambia): `21:27` → `21 y 27` (regex dígito:dígito), `2-5` → `2 a 5` (rango entre dígitos), `—`/`–` → `, ` (pausa natural; los guiones de palabras tipo "push-to-talk" quedan intactos — solo em/en-dash).
- **Verificado E2E**: texto hostil exacto del incidente → **10.3s generación → 11.7s audio limpio** (antes 74s); respuesta completa post-fix → **6.5s**. Falsa alarma 401 durante el test era artefacto del shell ad-hoc sin el env file (el systemd service sí lo carga) — sense_role valida la llave kalimete-ptt como 'services' OK.
- **Fixes complementarios (kalimete, commit 91a5993+)**: disciplina DURA en victoria-voz (máx 3-4 frases, NUNCA recitar horas/IDs/listas>3 — menciona en palabras) + AGENT_TTS_CAP 1200→600 chars. La respuesta de la MISMA pregunta pasó de 715 chars/16 frases/234s a **97 chars/6.5s**.
- **Impacto**: `voice-server-host.py` (backup implícito en git del stack; restart ~12s). Beneficia a TODOS los consumidores de TTS (PTT, sandbox, plugin voz-viva).
- **Docs**: yes (general + esta + kalimete project changelog).

### [2026-10-27 16:30 EDT] [voice] STT `?prompt=` — initial_prompt de Whisper para vocabulario del ecosistema (implementado 01:32 por sesión paralela del owner; verificado+documentado por Victoria)
- **Tipo**: feature (pedido del owner vía kalimete-ptt; el cliente kalimete ya mandaba el param desde 01:39)
- **Que**: `POST /stt` acepta `?prompt=` (o `?initial_prompt=`) — se pasa a `whisper.transcribe(initial_prompt=...)` como condicionamiento previo. Opt-in total (sin param = comportamiento idéntico al de siempre; backwards-compatible con sandbox whisper-cli, video-server y kalimete-ptt). Validación: >400 chars → 400 `prompt_too_long`. El cliente kalimete-ptt envía el vocabulario de la flota (Alfredo, Victoria, kalimete, armada, warcold, magantech, micaserogou, opencode, vibecoding, push-to-talk, DGX).
- **Por qué**: Whisper-small confundía nombres propios en español — verificado con roundtrip TTS→STT: "ComfyUI"→"Confui", "LivePortrait"→"Live Portrait", "kalimete"→"Calimete". Con prompt: "Prueba de Comfyui y LivePortrait en kalimete con Alfredo" — términos correctos.
- **Verificado**: roundtrip TTS→STT sin/con prompt (mejora directa), validación 400 chars → `prompt_too_long`, servicio vivo desde 01:32:35 EDT, config-guide documentado.
- **Impacto**: `voice-server-host.py` (modificado por la sesión paralela del owner ~01:32; esta entrada la escribe Victoria al verificarlo — el cambio no tenía entrada de changelog).
- **Docs**: yes (config-guide del servidor ya lo documenta + esta entrada + general).

### [2026-10-21 00:45 EDT] [voice] Locks separados TTS/STT — fix del starvation "no me respondió" (PTT kalimete)
- **Tipo**: fix (incidente reportado por el owner: presionó Ctrl_R y Victoria nunca respondió)
- **Que**: `_lock` único → **`_tts_lock` + `_stt_lock`**. Antes Qwen3-TTS y Whisper se serializaban con el mismo lock: el plugin voz-viva de opencode en victoria-host dispara una petición /tts por oración de cada respuesta de Victoria (journal: una generación cada 2-3s, GPU 77%) y el /stt del PTT de kalimete se encolaba detrás → **timeout 180s × 2 intentos = 360s sin respuesta** (log kalimete 00:25:20→00:31:31). Con locks separados ambos modelos coexisten en la GB10 (whisper-small ~1GB + Qwen3-TTS ~2.5-4GB de 128GB unificada) y solo comparten GPU (time-slicing).
- **Verificado**: (1) TTS de fondo generando 12.4s + STT simultáneo completó en **1.27s** (antes: 20s+ de hambre); (2) E2E desde kalimete por el camino exacto del PTT (LAN + llave + `?language=es`): **1.59s** con transcripción española correcta; (3) health OK post-restart.
- **Fix complementario (origen del ruido)**: `export VICTORIA_VOICE_LIVE=0` en `~/.bashrc` de victoria — este host NO tiene parlantes: el plugin sintetizaba TTS que iba a ninguna parte (pura quema de GPU + cola). Sesiones futuras de opencode no dispararán TTS aquí; la sesión actual sigue hasta que se cierre (el lock-split la vuelve inofensiva para el PTT). Re-enable: borrar la línea si algún día hay parlantes.
- **Impacto**: `voice-server-host.py` (backup `.bkup-20261021-lock-split`) + `~/.bashrc`. Restart del servicio (~15s, modelos lazy).
- **Docs**: yes (AGENTS.md §Servicio de Voz + este changelog + general + STATE kalimete-ptt con la resolución).

### [2026-10-20 23:55 EDT] [voice] `/stt` acepta `?language=` (fix alucinación de idioma en clips cortos)
- **Tipo**: fix (feature aditiva, backwards-compatible)
- **Que**: `POST /stt?language=es` — el endpoint ahora parsea query string y pasa el idioma a `whisper.transcribe(language=…)`. Antes: `language=None` hardcodeado → Whisper-small alucinaba idiomas en clips cortos (árabe/ruso/francés en el log de kalimete-ptt). Validación: ISO 639 2-3 letras minúsculas; `auto`/vacío = None; inválido → 400 `invalid_language` (después de consumir el body, sin romper keep-alive). Sin param = auto-detección = comportamiento intacto para todos los consumidores actuales (sandbox whisper-cli, video-server, kalimete-ptt v4).
- **Por que**: diagnóstico de doble lado de la sesión kalimete `ses_ea3adda92ffeYshinmCBIwQACd` (2026-10-20) — servidor nuestro con language=None + cliente kalimete-ptt que resolvía `PTT_LANGUAGE=es` pero nunca lo enviaba. Fix #1 de 4 (los #2-4 son lado kalimete: regex sí/no, idea→prompt, logs persistentes). Autorización del owner: "Procede".
- **Impacto**: `voice-server-host.py` (docstring + imports re/urllib.parse + config-guide + `_handle_stt` + transcribe). Backup: `.bkup-20261020-stt-language`. Restart del servicio (~15s, modelos lazy).
- **Verificado**: E2E 6 pruebas — (1) sin param: auto-detect intacto (ref española → español exacto); (2) `?language=es`: forzado OK; (3) inválido → 400 claro; (4) ref inglesa auto → inglés correcto; (5) misma ref inglesa `?language=es` → transcripción ESPAÑOLA distinta ("¡Muchas gracias, muy mucho!") = el param fluye hasta Whisper; (6) health OK post-restart.
- **Docs**: yes (AGENTS.md §Endpoints del servicio de voz + nota STT idioma + este changelog + general). Pendiente lado kalimete: su cliente debe enviar el param (PTT_STT_URL o código).

### [2026-10-09 13:30 EDT] [voice] `voz` pasa a LIBRE (doctrina ligero/pesado del owner)
- **Tipo**: docs operativa (el servicio host :18810 no cambió; ningún wrapper tiene gate de voz)
- **Que**: skill `vox` actualizada: responder con nota de voz o texto NO pide ventana, NO se deniega, NO genera solicitud — ni en DM ni en grupos (antes: ventana `voz` + frase guía + request/DM). La ventana `voz` de `art-approve` queda INFORMATIVA (siempre-open). Límite intacto: NO leer código/paths/JSON en voz alta.
- **Verificado**: `flow … voz` → `allow-free` exit 0 en wa y dc; grep cero gates de voz en `art-gen`/`art-3d`/`video-analyze`; md5 vox host↔sandbox idéntico.
- **Docs**: yes (skill vox + TOOLS doctrina + este changelog + sandbox + social; general por Victoria)
### [2026-10-09 12:40 EDT] [voice] Skill `vox`: cuándo voz vs texto + límites (piloto modo creativo Fase A)
- **Tipo**: docs operativa (el servicio host no cambió)
- **Que**: skill `vox` nueva (canónico host `~/.victoria-custom/skills/vox/SKILL.md` + espejo sandbox, reasegurada por ensure-loop): nota de voz entrante→nota de voz; grupo con ventana `voz`→texto salvo petición explícita de voz; DM owner según pida. Límites: NO leer código/paths/JSON en voz alta (va en texto); frase guía sin ventana + request/DM al owner.
- **Verificado**: md5 host↔sandbox idéntico (16f18cf1); voice-server sano (engine=qwen3, tts+whisper loaded).
- **Docs**: yes (skill + sandbox + social; general por Victoria)

### [2026-10-05 20:25 EDT] [voice] STT consumido de nuevo por el sandbox (media-understanding 2026.9.2)
- **Tipo**: fix (config del consumidor, el servicio host no cambió)
- **Que**: tras el upgrade OpenClaw 2026.9.2, las notas de voz de WhatsApp dejaron de transcribirse (el runtime ya no usa `messages.tts.auto`; ahora exige un entry capability "audio" en `tools.media.models`). Fix: entry CLI `whisper-cli` (wrapper existente → /tmp/tts-gateway.sock → :18810 /stt). El runtime convierte ogg→wav solo.
- **Verificado**: E2E con TTS real → transcripción exacta (wav y vía ogg→wav); wrapper+socket+voice-server intactos; hot-reload limpio.
- **Docs**: general 20:25 + sandbox 20:25.


### [2026-10-05 00:30 EDT] [voice] Leccion post-needrestart: TTS lento tras restart masivo, restart limpio lo cura
- **Tipo**: ops/leccion (owner: full updated)
- **Que**: tras el apt masivo (needrestart reinicio voice-server mientras vLLM recargaba GPU), el primer TTS quedo generando a ritmo de crawl (90s+ sin terminar). Causa: contencion GPU/estado sucio del restart en caliente. Fix: systemctl restart victoria-voice-server limpio -> TTS 5.0s normal.
- **Verificado**: TTS 200 en 5.0s (RIFF 134KB) + STT roundtrip OK; health engine=qwen3 tts_loaded=true.
- **Docs**: yes (general 00:30) — regla: tras upgrades masivos con needrestart, restart limpio del voice-server antes de declarar la voz sana.


### [2026-10-04 18:50 EDT] [sense_auth] ALL_CAPABILITIES fuente única + SENSE_ELEVATION_CAPS derivado
- **Tipo**: refactor (paso #1 de proximos pasos)
- **Que**: sense_auth.py ahora define ALL_CAPABILITIES (las 7 caps del stack) y deriva SENSE_ELEVATION_CAPS (todo menos llm/n8n); la elevacion usa la constante en vez de tupla inline. llm-gateway.py la IMPORTA de aqui — una sola fuente para gateway + los 6 daemons que ya importan sense_auth (verificado: una sola copia de sense_auth.py en el disco, todos resuelven igual).
- **Verificado**: unit test sense_role: kalimete (coder+tts/whisper) -> services; juancarlos (coder solo) -> None. Comportamiento identico, cero drift futuro.
- **Docs**: yes (general + vllm changelog)
### [2026-10-04 17:50 EDT] [voice] cap xtts->tts + tts-bridge endurecido (thread+timeout)
- **Tipo**: security/fix (autorizacion owner: procede con todo)
- **Que**: (1) `sense_auth.py`: SENSE_ROLES y elevacion ahora usan `tts` (antes `xtts`, nombre historico del motor viejo); docstring actualizado. (2) `tts-bridge.py` endurecido: thread por conexion + `settimeout(60)` (antes None = recv infinito) + close garantizado en finally + URLError->502. Root cause verificado en vivo: el bridge mono-hilo quedo atascado por un cliente (wrapper colgaba 420s mientras curl directo al server funcionaba) y un send sobre cliente muerto lo mato (proceso de 20h muerto 17:26; ensure-loop relanzo). Un cliente mudo ya NO bloquea las notas de voz de WhatsApp/Discord.
- **Verificado**: E2E wrapper desde sandbox: TTS exit=0 (107KB WAV) — el test exacto que colgaba; STT via bridge casi exacto; voice-server restart + health engine=qwen3.
- **Docs**: yes (general + openclaw.md + AGENTS.md)
- **Tipo**: feature (multi-tier del owner)
- **Que**: `sense_role()` además del rol consulta `allowed_models` de la llave: si el rol no está en SENSE_ROLES pero la llave tiene `art/xtts/whisper/liveportrait/comfyui` en su override → devuelve "services" (elevación explícita por capacidad). Compat total: admin/services/art/xtts/whisper/liveportrait/comfyui por rol siguen igual; una llave coder con `["llm","art","xtts","whisper"]` (kalimete) ahora puede usar TTS/STT con su propia llave y metering.
- **Verificado**: unit-test de `sense_role()` con 4 llaves: kalimete(coder+override)→"services" ✓, juancarlos(coder limpio)→None ✓, servicios-alfredo-pro-llc(services)→"services" ✓, warcold(readonly)→None ✓; los 5 sentidos restarteados con el sense_auth nuevo y sanos (:18810 ok, :18811 ok, :18820 ok, :18830 ok, :18840 → 401 sin llave = comportamiento documentado); compat intacta: localhost+docker siguen sin llave.
- **Docs**: yes (AGENTS.md §Auth sentidos, general)


> Servicio: `victoria-voice-server.service` (Qwen3-TTS único motor + Whisper small, HOST, python3.12 — XTTS eliminado 2026-10-03)
> Subagente: `OpenClaw` (`~/.config/opencode/agents/openclaw.md`)
> Script host: `openclaw-voice-host.sh`, `voice-venv/voice-server-host.py`
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

---

### [2026-10-03 16:50 EDT] [voice] Auditoría post-XTSS: docs curadas (8 archivos) + E2E re-verificado (es nativo + en)
- **Tipo**: docs | verificación (pedido del owner; parte de la auditoría cross-machine del mismo día)
- **Que**: (1) referencias XTTS muertas eliminadas de TODA la doc activa — quedan solo menciones históricas explícitas ("eliminado 2026-10-03"): AGENTS.md (fila de `~/.voice-models/` sin XTTS-v2 + whisper-small, fila runbook sin `VOICE_TTS_ENGINE=xtts`, `/health` con los campos REALES ok/uptime_s/engine/tts_loaded/whisper_loaded/voices/auth_required, venv sin coqui, modelos sin fallback), victoria.md (venv+modelos), openclaw.md (venv, health, modelos, monkeypatches XTTS marcados obsoletos — ya no viven en el código, modelos "se copian al sandbox" de la era 2026-08-17 → bridge), comfyui.md ×4, gpu.md, sonic.md ×2 (incl. frontmatter), sonic.harness.json (pipeline), header de este changelog; (2) E2E re-verificado HOY: `/tts` es con `victoria-es-reference` (nativa) → STT "¡Hola, Papa! Esta es una prueba de mi voz en español nativo." EXACTO; `/tts` en → STT exacto; plugin `victoria-voice-live.js` md5 idéntico en ambas máquinas tras eliminar línea duplicada de comentario (`bc531e54…`); (3) confirmado live: venv SIN coqui/XTTS (pip), `~/.voice-models/` sin XTTS-v2, `enhance_clarity()` sigue activa (VOICE_NO_ENHANCE=1 para off), wrappers `victoria-tts`/`whisper-cli` en overrides.
- **Verificado**: grep xtts en docs activas = solo histórico; TTS/STT round-trip es+en; health JSON completo.
- **Docs**: yes (AGENTS.md, victoria.md, openclaw.md, comfyui.md, gpu.md, sonic.md, sonic.harness.json, header propio, esta entrada + general).

### [2026-10-03 15:05 EDT] [voice] Acento nativo: referencia POR IDIOMA (misma voz, español nativo por auto-recitación)
- **Tipo**: feature (fix de acento, pedido del owner: "misma voz, español nativo + inglés bien")
- **Que**: (1) Diagnóstico: el clon ICL hereda la prosodia de la referencia — la de Victoria era lectura en INGLÉS (Librivox) → español con acento gringo (oído del owner). (2) Solución MISMA VOZ: `victoria-es-reference.wav`+`.txt` (8.5s) fabricada por AUTO-RECITACIÓN — su embedding de timbre (x-vector desde su wav) + 1.7B-Base generando español nativo → ese clip es SU referencia española. (3) Server: `resolve_voice(voice, language)` + `get_qwen_prompt(voice, language)` — el español clona desde la ref nativa, inglés desde la original; prompt cacheado por `voz:idioma`; fallback a ref base si falta la variante (degradación = acento, no caída). (4) Descartadas honestamente: Vía A (solo 1.7B — mejora parcial, 2x latencia+VRAM) y ref VoiceDesign (cambia el timbre — el owner quiere SU voz). Muestras A/B: acento-C-xvec17-{es,en}, acento-D-recit-{ref,06b-es,06b-en}, acento-D-orig-06b-en + PRODUCCION-{es-nativa,en-orig} en `Documents/Victoria Armada/jarvis-eval/`.
- **Por que**: "misma voz para eso la clonamos" (owner) — la identidad vive en el timbre (x-vector), el acento en la prosodia de la referencia; separarlos por idioma da ambas cosas.
- **Verificado**: /tts es 200 (ref nativa) STT exacto + eco-check primeros 2.5s = mensaje pedido (no la ref — la ref de 8.5s no sangra); /tts en 200 (ref original) STT exacto; recitación transcript 100% por Whisper; health OK.
- **Impacto**: voice-server (resolve_voice + get_qwen_prompt por idioma), ~/voices (nueva ref es), openclaw-voice-host.sh (WARN si falta), WhatsApp/Discord/Web/PTT/opencode-voz-viva heredan.
- **Docs**: yes (AGENTS.md, victoria.md VOZ REAL, openclaw.md, este changelog + general).
- **Revert simple**: `rm ~/voices/victoria-es-reference.*` + restart → vuelve a la ref única inglesa (acento, no caída).

### [2026-10-03 11:35 EDT] [voice] XTTS eliminado del todo + eco ICL corregido (ref corta 7s) + voz viva en opencode
- **Tipo**: refactor+feature (orden del owner: "si Qwen3 hace el trabajo, borra XTTS")
- **Que**: (1) Migradas daisy/tanja/dionisio/damien a clonación Qwen3 (refs wav+.txt generados con XTTS ANTES de borrarlo) → borrados pesos XTTS 2G + coqui-tts/monotonic + monkeypatches + fallback + `VOICE_TTS_ENGINE` + `BUILTIN_VOICES`; server Qwen3 puro. (2) Eco ICL cazado y corregido: el clon con ref de 30s repetía ~2s de la referencia al inicio (STT oía "asked me to come back..." antes de cada frase; correlación inútil porque el eco es RE-generado, no copia) → referencia victoria recortada a 7s expresivos (+.txt exacto) → eco cero + STT 100% exacto (las demás voces con refs 8-10s nunca tuvieron eco). Backup `victoria-reference.wav.bak-30s-20261003`. Se probó y descartó `_strip_ref_echo` por correlación (scores ~0.000, código muerto eliminado). (3) Plugin `victoria-voice-live.js` (opencode habla: deltas→oraciones→TTS→cola paplay/aplay/ffplay, narra edit/write/bash con cooldown, no lee código, tope 1200 chars, barge-in tipado+externo; env por máquina). Verificado E2E en victoria (localhost trusted) y kalimete (LAN con llave services, tts ok 119KB). Bugs del plugin cazados: `VICTORIA_VOICE=1` llegaba como voice:"1"→500 (filtro defensivo) + `const VOICE_NAME` duplicado (plugin no cargaba en silencio; validado con import+factory test). (4) kalimete-ptt: `PTT_SUBMIT` (Enter tras pegar, opt-in) + toque-corto = solo callar + `PTT_BARGE_ABORT` (Esc opt-in). (5) Recursos revalidados: VRAM real GPU 48.3/128GB (vLLM 37.5 + Sonic 5.2 idle + voz 4.4 + LP 1.2) → ~80GB libres; RAM 53G avail. Sin cambios de reparto (turnos sanos, cero OOMs desde 09-27/28).
- **Verificado**: 6 voces 200@24kHz + STT exacto + 0 tracebacks; `openclaw-voice-host.sh status` OK; plugin: carga + deltas + tts ok + narración en ambas máquinas; kalimete-ptt compila + active + teclado.
- **Docs**: yes (AGENTS.md, victoria.md + best practices multi-máquina, openclaw.md lecciones, comfyui.md, USER-restore.md, harnesses, SCRIPTS.md, unit Description; este changelog + general + kalimete)
- **Nota**: sesiones opencode TUI abiertas deben REINICIARSE para cargar el plugin nuevo (config se lee al arrancar).

### [2026-10-03 11:00 EDT] [voice] Motor TTS Qwen3-TTS-0.6B-Base (clonación ICL 24kHz) + wrapper victoria-tts + kalimete-ptt conversacional
- **Tipo**: feature (mejora de voz, Fase Jarvis-Victoria) — pedido del owner ("cambiar para mejorar, mantener la voz de Victoria")
- **Que**: (1) `voice-server-host.py` reescrito: motor principal Qwen3-TTS-12Hz-0.6B-Base (Apache 2.0) con clonación ICL de `victoria-reference.wav` + `victoria-reference.txt` (transcript exacto canónico; prompt reutilizable 0.9s una vez; `max_new_tokens=512` anti-descontrol; salida 24kHz), fallback XTTS v2 intacto (`VOICE_TTS_ENGINE=xtts`, loader lazy separado; voces integradas daisy/tanja/dionisio/damien SIEMPRE por XTTS). `enhance_clarity` intacto (target por motor). API `/tts` idéntica → WhatsApp/Discord/Web/Estudio heredan sin tocar nada. (2) Wrapper `xtts-cli` renombrado a `victoria-tts` (mismo protocolo socket): overrides (`talk` + `messages.tts`) + `ensure_tts_wrappers` + backup nuevo + restart gateway (12 plugins). (3) `openclaw-voice-host.sh` + `clone-voice.sh` actualizados (Qwen3 checks, transcript .txt, 24kHz). (4) kalimete-ptt conversacional (TARGET=kalimete, autorización owner): tras pegar, Victoria RESPONDE POR VOZ (LLM Qwen-normal → TTS → paplay); llave dedicada `kalimete-ptt` rol services; A/B de evaluación + opción VoiceDesign en `Documents/Victoria Armada/jarvis-eval/`.
- **Por que**: XTTS v2 (2023, Coqui cerrado) no puede dar emoción/suspiros/streaming moderno; el owner pidió voz más humana manteniendo su voz (joven anime F divertida/amable).
- **Bugs cazados**: (a) deadlock `threading.Lock` no-reentrante (`_handle_tts→synth_wav→get_qwen_prompt` re-adquiría `_lock` en voces sin .txt → colgaba TODO el server; fix: sin lock interno + comentario); (b) fallback XTTS usaba `get_tts_model()` (devolvía el modelo Qwen → `AttributeError parameters`; fix: loader dedicado `_get_xtts_model`); (c) ref_text incorrecto → 655s audio basura (fix: transcript canónico + tope tokens); (d) Qwen3-TTS quiere idiomas completos (`spanish`, no `es`).
- **Medido**: carga 15s (vs 2min), VRAM ~3.6GB pico (vs ~6GB), RTF ~0.65; latencias /tts: saludo 5.6s, larga 15.4s/11.9s, daisy-fallback 200; STT roundtrip exacto; kalimete E2E (LLM 200 OK + TTS 200 176KB + PLAY_OK).
- **Impacto**: :18810 (todos los consumidores), sandbox (wrappers+overrides+gateway restart), kalimete (script+key+env), venv (transformers 4.57.3, qwen-tts 0.1.1, accelerate 1.12.0, sox binario), disco (modelos Qwen3 0.6B 2.4G + 1.7B-Base + 1.7B-VoiceDesign; jarvis-tts-venv 5.3G eliminado).
- **Verificado**: /tts es/en/larga/usuario/daisy 200 + sr correcto por motor; /stt 200 exacto; wrapper E2E por socket; gateway 12 plugins + WhatsApp listening; `openclaw-voice-host.sh status` OK; kalimete-ptt compila + servicio active + pipeline remoto OK.
- **Docs**: yes (AGENTS.md §voice+tablas, victoria.md §voice+kalimete-ptt, openclaw.md §voz, comfyui.md voces Estudio, USER-restore.md, harness openclaw+sonic, este changelog + general)
- **Pendiente oído del owner**: A/B en `jarvis-eval/` (icl vs xvec vs xtts vs design) — si prefiere XTTS, revert con `VOICE_TTS_ENGINE=xtts` (fallback funcional, pesos en disco).

### [2026-09-29 12:45] [voice] Normalización TTS: siglas, cifras y símbolos se dicen precisos (NEAR≠"Nihar")
- **Tipo**: fix (pronunciación) — pedido del owner
- **Que**: `normalize_for_tts` (siglas→deletreo, $M/B→millones vía num2words ES/EN, miles con coma, cleaners XTTS nativos, %→por ciento) aplicado en `synth_wav` antes del chunking: vale para TODO (podcast, WhatsApp, Discord, Web UI). Texto visible intacto.
- **Verificado**: 4 casos ES/EN + TTS→STT "50 millones de dólares" exacto; health TTS+STT true.
- **Docs**: yes (general)

### [2026-09-29 02:55] [voice] Chunking TTS ≤200 chars: audios largos SIEMPRE completos (fix corte a mitad)
- **Tipo**: fix crítico (voz)
- **Que**: `split_tts_chunks` (≤200 chars por frase; si una frase se pasa, por comas y luego por palabras) + `synth_wav` reusa conditioning y concatena con 0.15s silencio. Causa: XTTS avisa `truncated audio` >239 chars (es) y revienta `AssertionError 400 tokens` ~1000 chars → 500 (logs 02:30/02:45). Los guiones 30-60s se quedaban POR MITAD. Timbre intacto (mismo conditioning).
- **Verificado**: 1000 chars/170pal antes 500 → ahora 99.9s OK (esperado ~77s + silencios); 91 chars→8.3s; health tts_loaded:true.
- **Docs**: yes (general + comfyui)

### [2026-09-18 19:00] Validación post-recreación sandbox — voz sin cambios
- **Tipo**: docs (verificación, sin cambios al servicio)
- **Que**: El voice-server NO fue tocado durante la recreación del sandbox. Servicio active, TTS+STT cargados, auth unificada sense_auth.py (llaves gateway admin/services, DB viva). La voz real de Victoria (clon Librivox `~/voices/victoria-reference.wav`) intacta. Bridge `tts-bridge.py` relanzado en el sandbox nuevo por el ensure-loop (socket `/tmp/tts-gateway.sock` verificado).
- **Verificado**: `curl 127.0.0.1:18810/health` → `tts_loaded:true, whisper_loaded:true`; socket en sandbox OK.
- **Docs**: yes (este changelog)
