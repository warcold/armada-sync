# 🧠 LECCIONES — Ecosistema Armada (kalimete)

> **Qué es**: memoria de errores cometidos y sus reglas derivadas. **Regla de
> uso**: ANTES de actuar en un dominio, leer sus lecciones. DESPUÉS de cada
> incidente, agregar la lección aquí (1 línea de regla + ref changelog).
> Las lecciones compartidas del stack (vLLM/GPU/TTS/Docker) viven en el espejo
> de victoria (`~/.victoria-custom/conocimiento/LECCIONES.md`); aquí van las
> de kalimete y sus proyectos.

## opencode (kalimete)

- `[opencode]` **Headless auto-rechaza permisos "ask"** — los proyectos que corren agentes headless (kalimete-ptt → victoria-voz) necesitan permisos `allow` explícitos en SU `.opencode.jsonc` (edit/bash/webfetch/external_directory/task); NO copiar esa config a proyectos humanos. — (kalimete-ptt v5, 2026-10-27)
- `[opencode]` **El deploy del sync.sh es DESTRUCTIVO por diseño** (borra "agentes zombies") — no poner archivos ajenos en los dirs de opencode que sincroniza. — (armada-sync/sync.sh header)
- `[sync]` **`cp` same-file crashea con symlinks** — el sync.sh maneja nullglob y excluye symlinks; no reintroducirlos. — (CHANGELOG armada-sync)
- `[opencode.db]` **Consultar sesiones con SQLite URI mode=ro** (`file:...?mode=ro`) — la DB de opencode está viva; tablas session/message/part con JSON en `data`. — (victoria-voz v5.1)
- `[voz]` **STT sin prompt alucina vocabulario técnico** ("Comfyui"→"Confui") — enviar `?prompt=` con el vocabulario del ecosistema (≤400 chars). — (voice-server 2026-10-27)
- `[voz]` **Respuestas de voz: máx 3-4 frases, NUNCA recitar horas/IDs/listas** — el TTS se desboca con texto hostil y el owner no puede leer listas por audio. — (victoria-voz v5.2)

## Proyectos / infra

- `[proxmark]`/`[ethical]` — (agregar lecciones de pentesting/ethical aquí cuando ocurran)
- `[wordpress]`/`[erp]` — (lecciones de los proyectos web aquí)

---
*Mantener: 1 línea de regla + ref. Última revisión: 2026-10-27.*

## MCP blender — addon responde SIN newline (2026-10-27)
- **Error**: test TCP crudo con recv-loop esperando `\n` → hang infinito → timeout ssh → kill → addon EBADF + Blender quit (parecía crash del addon, era el patrón de lectura).
- **Regla**: el addon mcp-for-blender responde JSON SIN `\n` final. Tests crudos: `socket.settimeout()` + recv incremental + `json.loads` incremental. O usar el MCP real (uvx mcp-for-blender stdio).
- **Ref**: blender.harness.json + blender.md (arranque: start-blender.sh, idempotente por puerto).
