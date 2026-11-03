---
name: animar
description: Animar una foto por chat (videito LivePortrait 3-8s) cuando piden dar vida/hablar/mover una imagen — wrapper lp-animate con ventana del owner
command: animar
---

# Skill: animar — foto → videito (LivePortrait por chat)

Cuándo usar: el usuario manda (o señala) una FOTO pidiendo animarla, darle
vida, que hable o que se mueva ("anima esta foto", "dale vida", "haz que
hable", "muévela"), con o sin video-guía. NO es generar imagen (skill `art`)
ni modelo 3D (skill `hunyuan3d`): es la foto del usuario cobrando movimiento.

## Cómo animar (vía exec, rutas absolutas /sandbox/...)

```bash
/sandbox/.openclaw/bin/lp-animate <foto> [--guia <video>] [--preset N]
        [--for <scope>] [--owner]
        [--send-to <target> --caption "..." [--channel whatsapp|discord]]
lp-animate health            # salud (daemon + venv + pesos + GPU + presets)
lp-animate --preset lista    # ver presets (sin gastar GPU)
```

- El wrapper corre DONDE el agente tenga exec (sandbox: cliente del daemon
  host :18861; la foto viaja en base64 y el mp4 vuelve descargado — mismo
  patrón que `art-3d` a :18860, sin canal nuevo). Los presets viven SOLO en
  el host y se resuelven allá.
- Envío atómico (como `art-gen`): `--send-to <target> --caption "..."`
  genera Y envía en un solo comando; el JSON trae `"sent": {"ok": true,
  "messageId": "..."}` — **solo con `sent.messageId` hay envío** (sin él NO
  digas "listo"; reintenta solo el send, no reanimes). El send manual
  (`openclaw message send --media <mp4> --json`) queda como fallback.
- El mp4 sale H.264 yuv420p+aac+faststart (WhatsApp/Discord lo aceptan).
  Tras envío exitoso: CIERRE DE TURNO (el caption ES la respuesta, sin texto
  final extra).

## Presets (clips guía del host — `--preset N`, default 1)

| N | Clip | Dura | Audio | Cuándo |
|---|---|---|---|---|
| 1 | `01-saludo.mp4` | 3.1s | no | Saludo, parpadeo, sonrisa leve (default seguro) |
| 2 | `02-habla.mp4` | 7.2s | sí | Hablar, mover labios (el mp4 conserva el audio del guía) |
| 3 | `03-energia.mp4` | 8.3s | sí | Energía, gesto amplio |

Cómo elegir: sin pista → 1 (saludo). Si piden "que hable/diga algo" → 2.
Si mandan video-guía propio (`--guia`), el preset se ignora (el guía manda).
Si el usuario manda foto SIN decir qué movimiento → pregunta preset (1/2/3)
o usa 1 y ofrece los otros.

## Ventanas por grupo/canal (modo creativo v3 — `animar` es PESADO)

Scopes: `wa:<group-jid>` (ej. `wa:120363429817888300@g.us`) |
`dc:<guild-id>` (ej. `dc:1365731253629751406`) |
`dc:<guild>:<channel>` (canal Discord). Ventana 4h max (default 4), cuota 10.
DM siempre SÍ.

- **Miembro sin ventana**: NO animes. Frase guía ("ese modo aún no está
  abierto en este grupo — pídele a Alfredo que lo active 🔓") +
  `art-approve flow <scope> animar --requester "<nombre>" --prompt "<qué>"`
  (UNA solicitud por scope+feature, 24h, sin re-notificar si ya hay vigente)
  + DM al owner con el payload (comando exacto
  `art-approve approve <scope> animar 4` o `sí animar 4`). NUNCA mandes al
  miembro al DM.
- **Ventana vigente**: `lp-animate <foto> --preset N --for <scope>`
  (SIN `--owner`) + `--send-to` al grupo + aviso al owner por DM por cada uso.
- **Owner** (`senderIsOwner:true`, DM o EN EL GRUPO): `lp-animate <foto>
  --for <scope> --owner` directo (bypass total, sin solicitud) + auto-ventana
  animar 4h. En el grupo abre hablando: `abro animar 2` / `modo creativo 2` /
  `cierro animar` / `cierra todo` → `art-approve natural "<texto>"
  --scope <scope>` + anuncio con hora de fin.
- La foto del usuario llega como adjunto (ruta local en el sandbox): úsala
  directo como `<foto>` (el wrapper la sube solo al daemon).

## Límites honestos

- La foto con CARA visible de frente funciona mejor; sin cara detectable el
  render falla con hint ("usa una foto frontal con la cara visible") — no
  reintentes la misma foto, pide otra.
- Clips ~3-8s (los presets); con guía propio, parecido al guía. Clips >15s
  no probados (VRAM/tiempos escalan).
- UNA animación a la vez (GPU compartida con inferencia/podcast/imágenes);
  el wrapper espera turno solo (no insistir a mano).
- `lp-animate`/`animar` NO son tools: el ÚNICO camino es
  `tool_call {"id":"openclaw:core:exec","args":{"command":"..."}}`.
  En grupos, exec es SOLO: `lp-animate`, `art-approve`, `openclaw message
  send` (+ los de las skills art/hunyuan3d/video/web). CUALQUIER otro exec
  en grupo se RECHAZA en corto.
