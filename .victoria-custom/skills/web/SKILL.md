---
name: web
description: Navegar/buscar en la web cuando piden hechos actuales (precios, noticias, clima, dominios, videos) — wrappers web-navigate/web-scrape, video-analyze, whois
command: web
---

# Skill: web — cuándo navegar y cómo

Navega cuando el pedido necesita hechos ACTUALES o externos que no están en
tu memoria: precios, noticias, clima, dominios, videos de YouTube, páginas
web. Responde DE MEMORIA cuando es conversación, opinión, recuerdos del grupo
o temas ya hablados — navegar de más es lento y quema GPU/tiempo.

## Cómo (vía exec, rutas absolutas /sandbox/...)

- **Página web**: `/sandbox/.openclaw/bin/web-navigate <url>` (navega) y
  `/sandbox/.openclaw/bin/web-scrape <url>` (extrae texto). Utilidad común en
  `/sandbox/.openclaw/bin/web-utils.sh`.
- **Video de YouTube**: `/sandbox/.openclaw/bin/video-analyze <url>`
  (descarga + frames + transcripción + descripciones VLM en un paso).
  En grupos con ventana del feature `video`: añade `--for <scope>` (sin
  `--owner` salvo que el mensaje ACTUAL traiga `senderIsOwner:true`).
- **Dominios**: `/sandbox/.openclaw/bin/whois <dominio>` (ruta completa — el
  PATH del netns NO incluye `/sandbox/.openclaw/bin`). Ver skill `domain`.
- **Audios**: las notas de voz llegan transcriptas (whisper automático) — no
  invoques `whisper-cli` a mano salvo prueba.

## Reglas duras

- NUNCA `find /` (Permission denied), ni tool `read`/`file_read` (no existen):
  todo por `tool_call {"id":"openclaw:core:exec","args":{"command":"..."}}`.
- Si un wrapper falla 2 veces con el mismo error, PARA y responde con lo que
  tengas (regla antibucles de TOOLS.md).
- En grupos, exec es SOLO: wrappers de esta skill + art-gen/art-approve/
  art-3d/video-analyze/message send + `ls`. CUALQUIER otro exec se RECHAZA.

## Grupos y canales (doctrina LIGERO vs PESADO 2026-10-09, orden del owner)

- **`busqueda` es LIBRE (siempre-open, informativo)**: navegar/buscar/clima/
  dominios NO piden ventana, NO se deniegan, NO generan solicitud. En grupos
  ejecuta `web-navigate`/`web-scrape`/`whois` directo (con `--for` solo como
  contexto si el wrapper lo acepta; el gate NUNCA bloquea busqueda).
- **`video` es PESADO (ventana obligatoria)**: analizar videos/transcribir
  SÍ exige ventana vigente del feature `video` en ese scope. Sin ventana:
  NO ejecutes el wrapper — responde la FRASE GUÍA y registra la solicitud:

> "ese modo aún no está abierto en este grupo — pídele a Alfredo que lo active 🔓"

Y luego (SOLO para `video`, nunca para `busqueda`): `art-approve request
<scope> --feature video --prompt "<pedido>" --requester "<nombre>"` + DM al
owner con scope y cómo aprobar (`art-approve approve <scope> video 4`, cap
4h; o el owner abre EN EL GRUPO con `abro video 2` / `modo creativo 2`).
NUNCA mandes al miembro al DM — el DM es SOLO del owner. Ventana vigente →
ejecuta con `--for <scope>` + aviso al owner por DM por cada uso.
Scopes: `wa:<group-jid>` (ej. `wa:120363429817888300@g.us`) |
`dc:<guild-id>` (ej. `dc:1365731253629751406`) |
`dc:<guild>:<channel>` (canal Discord). Anti-spam: UNA solicitud pendiente
por (scope+feature, 24h); si ya hay una vigente, SOLO la frase guía (sin
re-notificar). El owner en el grupo (`senderIsOwner:true`) NUNCA se deniega:
ejecuta directo con `--owner` (abre auto-ventana 4h).
