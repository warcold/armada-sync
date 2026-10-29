# Bun/TypeScript — doc viva del ecosistema

> **Verificado**: 2026-10-27 (proyecto dev/victoria en kalimete)
> **Docs oficiales**: https://bun.com/docs · https://www.typescriptlang.org/docs/

## Dónde se usa

- `~/dev/victoria/apps/server/` (kalimete) — backend Bun :8931 (chat, voz, aprobaciones, delegación de Victoria app)
- `~/dev/victoria/packages/` — protocol, voice, opencode-client compartidos (TS)

## Patrones que usamos

- Bun como runtime+server (API routes nativas, sin express)
- Monorepo con packages compartidos (protocol/voice/opencode-client)
- SSE para streaming (sin campo `event:` — decisión 2026-10-04)

## Gotchas descubiertos (lecciones)

- **SSE sin campo `event:`** — decisión de diseño del proyecto victoria (2026-10-04): el cliente parsea `data:` plano. — (dev/victoria/AGENTS.md)
- **Bun vs Node**: los scripts del proyecto usan `bun run` — no mezclar con node/npm del sistema.

## Regla de actualización

Bun: actualizar con el proyecto parado + E2E de chat/voz. TypeScript strict
en packages compartidos (protocol = contrato entre apps).
