---
name: hunyuan3d
description: "Convierte una foto/imagen en modelo 3D (GLB con textura) vía Hunyuan3D-2 local — avatares, bustos, piezas para Blender/visor."
command: hunyuan3d
---

# Skill `hunyuan3d` — image-to-3D local (Tencent Hunyuan3D-2)

Cuándo usar: el usuario pide convertir foto/imagen en modelo 3D, avatar 3D,
busto de Victoria, GLB para Blender/visor, o "hazme el 3D de...".

## Cómo generar

```bash
art-3d <foto.jpg> [--no-texture] [--steps 5] [--seed 2025] [--out nombre.glb]
       [--for <scope>] [--owner]
art-3d health   # salud del daemon
```

## Ventanas por grupo/canal (modo creativo v3 — `3d` es PESADO)

Scopes: `wa:<group-jid>` (ej. `wa:120363429817888300@g.us`) |
`dc:<guild-id>` (ej. `dc:1365731253629751406`) |
`dc:<guild>:<channel>` (canal Discord). Ventana 4h max (default 4), cuota 10.
DM siempre SÍ.

- **Miembro sin ventana**: NO generes. Frase guía ("ese modo aún no está
  abierto en este grupo — pídele a Alfredo que lo active 🔓") +
  `art-approve flow <scope> 3d --requester "<nombre>" --prompt "<qué>"` (UNA
  solicitud por scope+feature, 24h, sin re-notificar si ya hay vigente) + DM
  al owner con el payload (`dm.whatsapp`/`dm.discord`, comando exacto
  `art-approve approve <scope> 3d 4` o `sí 3d 4`). NUNCA mandes al miembro al DM.
- **Ventana vigente**: `art-3d <foto> --for <scope>` (SIN `--owner`) + aviso
  al owner por DM por cada uso.
- **Owner** (`senderIsOwner:true`, DM o EN EL GRUPO): `art-3d <foto> --for
  <scope> --owner` directo (bypass total, sin solicitud) + auto-ventana 3d 4h.
  En el grupo abre hablando: `abro 3d 2` / `modo creativo 2` / `cierro 3d` /
  `cierra todo` → `art-approve natural "<texto>" --scope <scope>` + anuncio
  con hora de fin.

- Default = **con textura** (mesh + Paint-turbo). `--no-texture` = mesh pelado.
- `steps` 5 = turbo rápido (default). Subir a 20-30 solo si el mesh sale pobre.
- El GLB queda en local listo para `openclaw message send --media <glb> --json`
  (**verificar `messageId`** en la respuesta: sin messageId NO fue enviado).
- GPU ocupada → el wrapper espera y reintenta solo (no insistir a mano).

## Límites honestos

- Genera **mesh ESTÁTICO con textura** desde UNA foto. NO riggea, NO anima.
- Pipeline avatar completo: `art-3d` (cuerpo) → Blender (cleanup + rig
  Rigify/Mixamo) → LivePortrait :8180 o Sonic :18850 (vida/voz).
- Mejor input: foto frontal, fondo limpio, cara visible. Las fotos de
  `victoria-reference/` (profile/posing) son el input canónico de Victoria.
- Licencia: Tencent Hunyuan 3D 2.0 Community (comercial con techo 1M MAU,
  exclusión EU/UK/KR, atribución). Igual que Sonic: no vender el modelo,
  los GLB generados son nuestros.

## Servicio

- Daemon `:18860` (`victoria-hunyuan3d.service`), salud `/health`.
- LAN: `https://victoria.local/hunyuan3d/health`. Detalle operativo en `Comfyui`.
