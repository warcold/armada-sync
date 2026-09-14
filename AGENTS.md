# Armada Network — Reglas globales (auto-cargado)

> Este archivo se carga automáticamente en TODAS las sesiones y para TODOS los agentes.
> Son solo reglas globales y punteros. El detalle vive en la fuente única indicada abajo.
> No duplicar aquí topología, SSH, servicios ni tablas de agentes.

## Qué es Armada

Sistema de agentes opencode + documentación sincronizada vía Git.
Solo **kalimete** (hub) escribe al repo. Victoria = servidor GPU/LLM (solo lectura).
jonas = fuera de servicio (no intentar SSH ni operaciones).

## Fuente única (no duplicar)

- Topología, nodos, servicios, lista de agentes → `MAPA.md` (repo) / `~/.config/opencode/ecosistema-map/MAPA.md` (local). Esa es la verdad; este archivo no la repite.
- Orquestación, delegación, aliases SSH, detalle Victoria/Gateway, Cloudflare → agente `kalimete` (`agents/kalimete.md`).
- Credenciales y comandos Cloudflare → skill `cloudflare` (`skills/cloudflare/SKILL.md` + `cloudflare-map/INVENTARIO.md`).
- Historial de cambios de infra → `CHANGELOG.md` (el formato lo define `kalimete.md`).

## Repo y sync (hub único)

- Repo: `ssh://git@github.com/warcold/armada-sync.git`, rama `master`.
- Estructura: `agents/ skills/ commands/ configs/ daily-report/ AGENTS.md MAPA.md CHANGELOG.md sync.sh`.
- `agents/*.md` → `~/.config/opencode/agent/` por symlink. Collect/deploy son DESTRUCTIVOS (borran agentes zombies).
- Solo kalimete hace push (cron cada 5 min). victoria/jonas sin cron ni repo.

## Reglas críticas (para todos los agentes)

1. Backup `.bkup` antes de modificar cualquier config.
2. NUNCA mostrar tokens/secrets. NUNCA compartir llaves privadas.
3. Destructivo = confirmar con el usuario mostrando exactamente qué se elimina.
4. victoria = SOLO LECTURA por defecto; escritura solo con autorización explícita del usuario.
5. jonas = fuera de servicio; no intentar SSH ni operaciones.
6. Validar contra lo real antes de afirmar; si algo está roto, documentarlo, no adivinar la causa.
7. Qwen3.6 max 262144 tokens. No exceder contexto; no volcar archivos grandes al chat (usar `head`, `grep -c`, `wc -l`, `/tmp` + offset).
8. Cambio de infra → lo registra kalimete en `CHANGELOG.md` + commit/push.

## Notas opencode

- `~/.config/opencode/AGENTS.md` es symlink → `~/armada-sync/AGENTS.md`. No reemplazar por archivo real.
- Permisos (patrón orquestador): subagentes `eco-cloudflare-*` con `edit/write: deny` (solo API); `kalimete` coordina y aplica cambios de archivos. Ver frontmatter de cada agente.
