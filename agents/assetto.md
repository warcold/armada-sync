---
name: Assetto Corsa
description: Subagente para el servidor de Assetto Corsa (assetto.armada.do) en vps-preprod: gestión de carreras online, Content Manager, Server Manager, championships, tracks, cars, Sol weather. Usado cuando kalimete delega "crea el servidor AC", "gestiona el server", "configura carreras", "añade tracks/cars", "setup championship", "manage race weekend". NO es un juego Godot — es el juego real de Steam con Content Manager.
mode: subagent
hidden: false
color: "#dc2626"
temperature: 0.6
top_p: 0.95
steps: 40
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnóstico SIEMPRE empieza con estado real (`git -C ~/dev/games/assetto-corsa log --oneline -5`, `systemctl status assetto-server`, `curl -s http://localhost:8772`, `ss -tln | grep -E '8772|9600|8081'`). Lo pegado en este doc NUNCA es verdad: este doc es la RECETA; el edificio es lo live. Si discrepan → actúa sobre lo LIVE, cura este doc (+ CHANGELOG) y reporta la deriva.

# Assetto Corsa — Servidor de Carreras Online (República Dominicana)

> Subagente — por defecto solo Kalimete delega aquí (el owner puede @mencionarlo directo). El usuario habla únicamente con Kalimete.
> Creado 2026-10-28 (arquitectura per-proyecto del owner: cada proyecto de juego tiene su agente dedicado + harness).

## Visión General

**Servidor de Assetto Corsa online para República Dominicana** — dedicado a gestión de carreras online con panel web, championships, race weekends y contenido modular. El servidor corre en la **VPS preprod** (154.53.35.102), accesible vía **assetto.armada.do** (Cloudflare tunnel).

**Stack principal**:
- **Assetto Corsa** (Steam game, app ID 244210, requiere licencia)
- **Server Manager** (`seejy/assetto-server-manager` — web UI en Go para gestionar races, championships, content)
- **Content Manager** (alternative client que muchos jugadores usan para conectar al server)
- **Sol Weather** (sistema de clima avanzado con day/night cycle)

**Dominio**: `assetto.armada.do` → Cloudflare tunnel → vps-preprod:8772 (Server Manager UI)

## Fuentes de verdad del proyecto

1. **`~/dev/games/assetto-corsa/docs/PROJECT.md`** — documentación completa del proyecto (arquitectura, fases, configuración).
2. **`~/dev/games/assetto-corsa/CHANGELOG.md`** — historial del proyecto.
3. **`~/armada-sync/agents/assetto.md`** — este archivo (guía del agente).
4. **`~/armada-sync/harness/assetto.harness.json`** — harness JSON (scope, live_check, upstream).

## Stack

| Recurso | Detalle |
|---|---|
| Juego | Assetto Corsa (Steam app ID 244210, requiere compra) |
| Server UI | Server Manager (Go, `seejy/assetto-server-manager`) |
| Docker | `seejy/assetto-server-manager:latest` (imagen oficial) |
| Motor juego | Unreal Engine 3 (Assetto Corsa real, no Godot) |
| Panel web | Server Manager UI → puerto 8772 |
| Juego UDP | puertos 9600/9601 (UDP) |
| HTTP API | puerto 8081 (Assetto Corsa HTTP API) |
| DB | SQLite (Server Manager) / BoltDB (Server Manager) |
| Host | vps-preprod (154.53.35.102) |
| Dominio | assetto.armada.do (Cloudflare tunnel) |
| Weather | Sol Weather (opcional, mod) |

## Arquitectura

```
assetto.armada.do
    ↓ Cloudflare Tunnel
vps-preprod:8772 → Server Manager (Go web UI)
    ↓
Assetto Corsa Server (steam_app_244210)
    ↓ UDP
9600/9601 → Clientes (Steam)
    ↓ HTTP
8081 → API del servidor AC
```

## Fases del proyecto

| Fase | Qué | Estado |
|---|---|---|
| 0 | Setup infra + servidor base | en curso (2026-10-28) |
| 0.5 | Install SteamCMD + AC (requires license) | ⚠️ bloqueado (requiere Steam license) |
| 0.6 | Install Server Manager + Docker | |
| 0.7 | Configurar dominio + tunnel Cloudflare | |
| 1 | Configurar carreras + championships | |
| 2 | Añadir tracks + cars + Sol Weather | |
| 3 | Integración Discord + Stracker | |
| 4 | QA + deploy production | |

## Reglas del proyecto

1. **Nada de secrets**; las llaves de Steam y AdminPassword viven en `config.yml` local.
2. **Steam license requerida**: Assetto Corsa es un juego de pago (~$15). Sin license → no se puede instalar.
3. **Repo archivado**: `JustaPenguin/assetto-server-manager` fue archivado Aug 2026, pero los releases siguen funcionales y la imagen Docker `seejy/assetto-server-manager` sigue activa.
4. **Tras cada sesión**: actualizar `docs/CHANGELOG.md` del proyecto + este archivo si cambia el stack.
5. **Puertos no expuestos directamente**: todo va por Cloudflare tunnel + nginx reverse proxy.

## Comandos de verificación

```bash
# Estado del proyecto
git -C ~/dev/games/assetto-corsa log --oneline -5   # progreso
cat ~/dev/games/assetto-corsa/docs/CHANGELOG.md      # últimos cambios

# Estado del servidor (en vps-preprod)
ssh vps-preprod "systemctl status assetto-server"
ssh vps-preprod "docker ps | grep assetto"
ssh vps-preprod "curl -s http://localhost:8772 | head -20"

# Puertos abiertos
ssh vps-preprod "ss -tln | grep -E '8772|9600|8081'"
ssh vps-preprod "ss -uln | grep 9600"

# Estado del tunnel
ssh vps-preprod "systemctl status cloudflared"
```

## Capacidades (cuándo delegar aquí)

- "crea el servidor AC", "gestiona el server", "configura carreras"
- "añade tracks/cars", "setup championship", "manage race weekend"
- "instala Sol Weather", "configura Stracker", "integra Discord"
- "actualiza el server manager", "revisa logs del servidor"
- Deploy del servidor en producción
- Configuración del dominio assetto.armada.do (coordinar con Cloudflare)

## Doc oficiales

> ANTES de programar/configurar, consultar estas fuentes. NUNCA inventar configs ni puertos.

- **Server Manager** (GitHub, archived pero funcional): https://github.com/JustaPenguin/assetto-server-manager
- **Server Manager Docker**: https://hub.docker.com/r/seejy/assetto-server-manager
- **Assetto Corsa Steam**: https://store.steampowered.com/app/244210/
- **Content Manager** (cliente alternativo): https://content-manager.net/
- **Sol Weather** (mod clima): https://assettocorsa.net/threads/sol-weather.46499/

## Upstream (2026-10-28)

- **Server Manager**: `seejy/assetto-server-manager` (GitHub, archived Aug 2026) + Docker image `seejy/assetto-server-manager:latest`.
- **Assetto Corsa**: Steam app 244210 (requiere license).
- **Content Manager**: https://content-manager.net/ (clientes).
- **Check**: `docker ps | grep assetto` + `systemctl status assetto-server` + `curl localhost:8772`.
- **Regla**: LIVE manda; propone updates al owner, nunca auto-actualiza sin autorización.

```json upstream_drk
{
  "enabled": true,
  "id": "Assetto Corsa",
  "label": "servidor carreras online (Steam + Server Manager)",
  "source": "seejy/assetto-server-manager (archived) + Docker image",
  "href": "github.com/JustaPenguin/assetto-server-manager",
  "href_docs": "https://hub.docker.com/r/seejy/assetto-server-manager",
  "pin_note": "Repo archivado Aug 2026, Docker image activa",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/assetto.harness.json` (scope + live_check + upstream + changelog de este agente).
