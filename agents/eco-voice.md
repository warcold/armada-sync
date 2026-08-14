---
description: Servicio de voz de Victoria — ELIMINADO 2026-08-14 (verificado: no existe victoria-voice, ni nginx voice, ni puertos 8765/8766). Este agente queda SOLO como documentación de reconstrucción si el usuario pide revivir el servicio de voz. No delegar para troubleshooting de voz activa (no existe).
mode: subagent
model: default
---

# eco-voice — Servicio de voz de Victoria (ELIMINADO 2026-08-14)

> ⚠️ **ESTADO ACTUAL: ELIMINADO.** Verificado 2026-08-14:
> - NO existe contenedor `victoria-voice` (victoria solo tiene `nemoclaw-vllm` y `openshell-my-assistant`).
> - NO existe `voice.conf` en nginx (sites-enabled = `default` + `gateway.conf`).
> - NADA escucha en 8765 / 8766 / 18789 / 4000 / 9001 / 9003.
> - `nvsm-api-gateway` (systemd) está INACTIVE.
>
> **No hay servicio de voz operativo.** Si el usuario pregunta por la voz o el micrófono, informar que el servicio fue eliminado y NO intentar troubleshooting sobre algo inexistente.

## Qué era (histórico — referencia para reconstrucción)

- **UI de voz**: `https://victoria.local:8765` (nginx TLS 443 en victoria, cert mkcert, proxy al contenedor `victoria-voice`).
- **Contenedor `victoria-voice`**: servía la UI y WebSocket `/ws` (STT/TTS streaming). Capas históricas: baseline (whisper-1 + XTTS), baseline-2, baseline-3, baseline-4 (probadas y abandonadas 2026-08-11/12).
- **STT/TTS**: se eliminaron (los modelos de voz no corrían bien en la GB10 junto a vLLM).
- **Espejado de idioma**: SOLUCIONADO con instrucción explícita por turno (`[EN] Answer in English, like the user. …`) — validado 8/8 + turnos mixtos.
- **401 en STT**: solucionado (auth del gateway por API key del stack anterior).
- **Regla dura**: la UI de voz NUNCA se exponía por túnel/dominio — SOLO victoria.local.

## Si el usuario pide reconstruir el servicio de voz

1. Confirmar con el usuario el alcance (¿UI simple con WebSocket?, ¿STT/TTS local?, ¿integrado a NemoClaw?).
2. Verificar estado actual: `docker ps` en victoria, `ss -tlnp` (puertos libres), nginx sites-enabled.
3. GPU: la GB10 ya corre vLLM (~47 GiB) — los modelos de voz deben caber o correr en CPU con latencia aceptable.
4. UI y WebSocket en contenedor Docker arm64; nginx TLS con cert mkcert existente (`/etc/ssl/local-certs/victoria.local.{pem,key}`).
5. SOLO victoria.local — nunca túnel/dominio (regla del ecosistema).
6. Documentar el nuevo stack en este archivo + MAPA.md + AGENTS.md + INVENTARIO.md.

## Lecciones guardadas (para no repetir)

- Las capas baseline-* (whisper/XTTS) fueron un callejón sin salida: modelos grandes + GPU compartida = degradación del LLM principal.
- El TTS nativo de OpenClaw y el gateway de STT del stack anterior quedaron validados (401 resuelto) pero el servicio completo nunca fue estable en la victoria nueva.
- Cualquier reconstrucción debe priorizar: latencia de la UI, no bloquear vLLM, y auth por llave del gateway v2.