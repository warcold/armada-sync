# MCPs — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: opencode.jsonc de kalimete)
> **Docs oficiales**: https://modelcontextprotocol.io/ (spec MCP) · https://opencode.ai/docs/mcp/

## Qué es un MCP

Model Context Protocol: servidores que exponen herramientas (tools) a los
agentes opencode. En opencode se declaran en `opencode.jsonc` → `"mcp": {}`
con `type: local` (comando) y opcional `enabled`. El agente los descubre vía
`tool_search`/`tool_describe`.

## MCPs activos (kalimete)

| MCP | Comando | Qué expone | Proyecto que lo usa |
|---|---|---|---|
| **godot** (GENERAL) | `godot-mcp` sin `-p`, cwd `~/dev/games` | Tools del Godot Engine con auto-detección del proyecto activo (escenas, nodos, scripts, ejecución) | Uso general de juegos (`Blender` + `Game Studio`); con 1 solo project.godot detecta ese; con varios, crear `godot-<slug>` dedicado |
| **godot-ror** | `godot-mcp -p ~/dev/games/record-of-ragnarok` | Tools del Godot Engine apuntadas al proyecto RoR (escenas, nodos, scripts, ejecución) | Record of Ragnarok (juego, agente `Record of Ragnarok` + `Game Studio`) |
| **blender** | `uvx mcp-for-blender` (env `BLENDER_HOST=localhost BLENDER_PORT=9876`) | Tools de Blender (modelado, rigging, export GLB) — requiere Blender corriendo con el addon server en :9876 | Cadena de avatar 3D: Hunyuan3D (GLB estático) → rig en Blender → overlay/LivePortrait |

## Patrones de uso

- **godot (general)**: sin `-p` — auto-detección escanea subdirectorios de `~/dev/games` buscando `project.godot`. Verificado 2026-11-11 (detecta record-of-ragnarok). Cuando existan 2+ juegos, la detección es ambigua → crear MCP `godot-<slug>` dedicado por juego (patrón 2026-10-20).
- **godot-ror**: el agente edita escenas/scripts del juego SIN abrir el editor — el MCP corre el binario `godot-mcp` (instalado en PATH de kalimete) con cwd del proyecto.
- **blender**: `uvx` lo baja on-demand (uv tool runtime); el addon de Blender debe estar escuchando en localhost:9876 ANTES de invocar tools — si Blender no corre, las tools fallan con connection refused.
- Los MCPs son **por-máquina** (kalimete los declara; victoria no tiene MCPs aún — candidatos: ComfyUI API, gateway art API).

## Gotchas descubiertos (lecciones)

- **El MCP blender depende de un proceso externo** (Blender + addon) — verificar `ss -tlnp | grep 9876` en kalimete antes de culpar al MCP.
- **uvx cache**: la primera invocación descarga el paquete (lenta); las siguientes usan cache.
- **MCPs y headless**: en sesiones headless (PTT) los MCPs del proyecto aplican si el `.opencode.jsonc` del proyecto los hereda — verificar con `opencode` en el proyecto antes de asumir.

## Regla de actualización

`godot-mcp`/`mcp-for-blender`: actualizar con `uvx --upgrade` / rebuild del
binario + probar 1 tool real del proyecto + changelog del proyecto afectado.
