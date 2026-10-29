# Electron/Three.js — doc viva del ecosistema

> **Verificado**: 2026-10-27 (proyecto dev/victoria en kalimete)
> **Docs oficiales**: https://www.electronjs.org/docs/latest · https://threejs.org/docs/

## Dónde se usa

- `~/dev/victoria/apps/overlay/` (kalimete) — avatar Victoria 3D caminando sobre el taskbar (Electron + Three.js)
- Toggle: Ctrl+Shift+V

## Patrones que usamos

- Electron window transparente + always-on-top para el overlay
- Three.js para el avatar 3D (modelos GLB — conecta con la granja de contenido: Hunyuan3D :18860 genera GLB, lp-animate :18861 anima)
- Comunicación overlay ↔ backend Bun :8931

## Gotchas descubiertos (lecciones)

- **Electron en Wayland (kalimete usa SDDM/Wayland)**: verificar flags de plataforma si el overlay no aparece — pendiente primera prueba real del overlay.
- **GLB del avatar**: la cadena de contenido es Hunyuan3D (estático) → rig en Blender (MCP) → LivePortrait/Sonic para cara. El MCP blender (:9876) es el puente para rigging.

## Regla de actualización

Electron/Three: actualizar con el proyecto parado + prueba visual del overlay.
El avatar es la cara pública de Victoria — cualquier cambio visual pasa por el owner.
