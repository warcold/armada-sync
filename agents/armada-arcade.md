# 🎮 Armada Arcade — Subagente de Juego

## Visión General

**Armada Arcade** es un proyecto de juego multiplayer con motor de TetriNET y arquitectura de plugins extensible. Este subagente gestiona el desarrollo, mantenimiento y mejoras del servidor y cliente de juego.

## Repositorio

- **Path**: `~/armada-arcade/`
- **Tipo**: Proyecto Node.js (monorepo con workspaces)
- **Servidor**: `~/armada-arcade/server/` (Express + Socket.IO)
- **Cliente**: `~/armada-arcade/client/` (Vite + TypeScript + Canvas)
- **Shared**: `~/armada-arcade/shared/` (tipos compartidos)
- **Engine**: `~/armada-arcade/server/engine/` (lógica de juegos)

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Servidor | Node.js, Express, Socket.IO, TypeScript |
| Cliente | TypeScript, Canvas API, Vite |
| Motor de Juego | TypeScript (engine puro, sin I/O) |
| Plugin System | Registry pattern (GamePlugin interface) |

## Comandos Útiles

```bash
# Instalar
cd ~/armada-arcade && npm install

# Ejecutar servidor en dev
cd ~/armada-arcade && npm run dev

# Ejecutar cliente (Vite dev server)
cd ~/armada-arcade/client && npx vite

# Build completo
cd ~/armada-arcade && npm run build

# Ejecutar en producción
cd ~/armada-arcade && npm start
```

## Acceso

- **Servidor**: `http://localhost:3000`
- **API**: `http://localhost:3000/rooms`
- **Cliente**: `http://localhost:5173` (Vite dev) o `http://localhost:3000` (producción con proxy)

## Estructura del Motor de Juego

### TetriNET (`engine/tetrinet.ts`)
- 7 piezas TetriNET (LINE, SQUARE, LEFTL, RIGHTL, LEFTZ, RIGHTZ, HALFCROSS)
- Rotación CW/CCW con wall kicks simples
- Campo 12x22
- 9 especiales: a, c, b, r, o, q, g, s, n
- 7-bag randomizer
- Next queue (3 piezas)
- Garbage lines con gap

### Game State (`engine/game.ts`)
- Creación de rooms/salas
- Player management (slot 1-6, teams)
- Line clearing y scoring
- Special usage y effects
- Sudden death timer
- Win condition (last player standing)
- Ghost piece (client-side)

### Plugin System (`engine/plugins.ts`)
- `GamePlugin` interface extensible
- `PluginRegistry` singleton
- Registro dinámico de juegos
- Base para Dominoes y otros juegos

## Desarrollo de Plugins

Para agregar un nuevo juego:

```typescript
// En engine/plugins.ts o como módulo separado
import { GamePlugin } from './plugins.js';

const DominoesPlugin: GamePlugin = {
  id: 'dominoes',
  name: 'Dominoes',
  minPlayers: 2,
  maxPlayers: 4,
  create(players): GameState { /* ... */ },
  action(state, from, action, data): GameEvent[] { /* ... */ },
  checkEnd(state): GameEndState | null { /* ... */ },
  serialize(state): string { return JSON.stringify(state); },
  deserialize(data): GameState { return JSON.parse(data); },
};

pluginRegistry.register(DominoesPlugin);
```

## Flujo de Juego

1. Cliente abre → Lobby (lista de salas)
2. Cliente crea/une a sala → Socket.IO join
3. Host presiona "start" → Juego inicia
4. Juego loop: cliente envía field updates → servidor relay → otros clientes reciben
5. Líneas limpiadas → server envía garbage a oponentes
6. Especial usado → server broadcast a todos
7. Todos menos uno pierden → winner announced

## Reglas de Operación

1. **NUNCA** tocar Victoria con este proyecto (solo local en kalimete)
2. **NUNCA** hacer deploy a producción sin aprobación del usuario
3. **SIEMPRE** actualizar docs/README.md al cambiar arquitectura
4. **SIEMPRE** documentar cambios en CHANGELOG.md
5. Los archivos de código del juego están en `engine/` del servidor
6. El cliente Canvas está en `client/src/game/client_engine.ts`
7. La UI del juego está en `client/src/ui/game.ts`
8. La UI del lobby está en `client/src/ui/lobby.ts`
9. El socket client está en `client/src/game/client.ts`

## Estado Actual

- ✅ Motor TetriNET completo (piezas, rotation, specials, garbage, 7-bag)
- ✅ Servidor Socket.IO (lobby, salas, relay)
- ✅ Cliente Canvas con UI dark theme
- ✅ Plugin system base (TetriNET + placeholder Dominoes)
- ✅ Documentación (README, PROTOCOL.md)
- 📝 Dominó: placeholder, necesita lógica completa
- 📝 Especiales multi-target: necesita implementación en servidor
- 📝 Sudden death visible en UI
- 📝 Winlist persistente (SQLite)

## Cambios Recientes

- **2026-08-29**: Proyecto creado desde cero — motor TetriNET + Socket.IO server + Canvas client
