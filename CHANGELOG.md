# CHANGELOG — Ecosistema Armada

Registro de cambios que afectan infraestructura, agentes, servicios o configuración.
Cada entrada se crea al finalizar una tarea que modifique algo en el ecosistema.

## Formato de entrada

```markdown
## YYYY-MM-DD

### [Hora] - Cambio: descripción corta
- **Tipo**: agente | config | sync | infra | servicio | red | seguridad | otro
- **Modificado**: archivo o componente que cambió
- **Afecta a**: máquina o agente que se ve impactado
- **Causa**: por qué se hizo el cambio (tarea/razón)
- **Estado**: ✅ sincronizado | ⚠️ pendiente | ❌ error
- **Notas**: detalles adicionales, alertas, observaciones
```

---

## 2026-08-13

### [23:35] - Red: rootsource → NUEVA victoria (10.0.0.5) + fix RDP headless
- **Tipo**: red | infra | servicio | config
- **Modificado**: hosts, SSH configs, MAPA.md, kalimete.md, eco-accesos.md, AGENTS.md, perfil remmina, victoria (10.0.0.5): xrdp desactivado, grd RDP habilitado con credenciales + TLS
- **Afecta a**: kalimete, victoria (ex-rootsource), Alfredo (Windows en 10.0.0.64)
- **Causa**: usuario reportó RDP rechazado tras credenciales; validación de logs mostró: (1) el host 10.0.0.5 ya no es rootsource sino la NUEVA victoria (puerto 1666, user victoria), (2) xrdp validaba OK pero GNOME mataba la sesión ("Session manager already running" — sesión local activa), (3) grd tenía RDP disabled y sin credenciales
- **Estado**: ✅ sincronizado
- **Notas**: llave `id_ed25519_kalimete` autorizada en victoria. `grdctl --system rdp set-credentials victoria vcolador` + cert self-signed en /var/lib/gnome-remote-desktop/. xrdp y xrdp-sesman DISABLED. ⚠️ llmgate y cloudflared INACTIVE en victoria — pendiente reactivar. Victoria vieja (10.0.0.64) ya no existe como Ubuntu (IP ahora del Windows de Alfredo).

### [13:30] - Fix: vLLM context overflow (163K → 262K)
- **Tipo**: config | infra
- **Modificado**: opencode.jsonc (baseline-thinking), MAPA.md (regla anti-desborde)
- **Afecta a**: kalimete (config opencode)
- **Causa**: 147,457 input + 16,384 max_tokens = 163,841 > 163,840 vLLM limit → "Type validation failed". El modelo soporta 262K según NVIDIA docs.
- **Estado**: ✅ sincronizado
- **Notas**: baseline-thinking: max_tokens 16384→8192, context 158000→245000. MAPA.md actualizado con contexto real 262K. vLLM contenedor aún en 163K → no urgente (opencode.jsonc tiene margen).

---

## 2026-08-13

### [05:35] - Sync: integración de rootsource al ecosistema (follower)
- **Tipo**: sync | infra | agente
- **Modificado**: armada-sync/AGENTS.md, armada-sync/agents/docs-keeper.md (nuevo), rootsource: ~/.ssh/id_github_rootsource + ~/.ssh/config, cron, opencode.jsonc (default_agent)
- **Afecta a**: kalimete, victoria, rootsource
- **Causa**: rootsource es el proveedor de modelos (vLLM/llmgate) de todo el ecosistema; quedaba fuera del sync de agentes
- **Estado**: ✅ sincronizado
- **Notas**: rootsource ahora es FOLLOWER (pull+deploy, nunca push). Deploy key `rootsource-follower-readonly` (solo lectura) registrada en GitHub vía gh. docs-keeper.md (agente local de rootsource) añadido al repo con model portable (sin model fijo → usa default de cada máquina). Cron `*/5` instalado. default_agent: kalimete añadido al opencode.jsonc de rootsource. md5 de kalimete.md idéntico al repo. jonas queda pendiente (SSH roto).

### [00:15] - Sync: arquitectura hub/follower, collect/deploy destructivos, cron.log gitignore
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh, armada-sync/.gitignore
- **Afecta a**: kalimete, victoria
- **Causa**: race condition entre crons de kalimete y victoria, agentes zombies
- **Estado**: ✅ sincronizado
- **Notas**: kalimete es ahora el único writer (HUB). Victoria solo pull+deploy. collect y deploy son destructivos (eliminan zombies). cron.log ya no se sube al repo.

### [00:30] - Fix: sync.sh nullglob syntax error
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh
- **Afecta a**: kalimete, victoria
- **Causa`: syntax error en línea 45 (redirección no válida en for)
- **Estado**: ✅ sincronizado
- **Notas**: reemplazar `for ... 2>/dev/null` por `shopt -s nullglob` + for limpio. Victoria necesita actualizar sync.sh del remoto.

### [00:35] - Sync: arquitectura hub/follower, collect/deploy destructivos, cron.log gitignore
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh, armada-sync/.gitignore
- **Afecta a**: kalimete, victoria
- **Causa**: race condition entre crons de kalimete y victoria, agentes zombies
- **Estado**: ✅ sincronizado
- **Notas**: kalimete es ahora el único writer (HUB). Victoria solo pull+deploy. collect y deploy son destructivos (eliminan zombies). cron.log ya no se sube al repo.

### [00:36] - Fix: sync.sh nullglob syntax error
- **Tipo**: sync
- **Modificado**: armada-sync/sync.sh
- **Afecta a**: kalimete, victoria
- **Causa**: syntax error en línea 45 (redirección no válida en for)
- **Estado**: ✅ sincronizado
- **Notas**: reemplazar `for ... 2>/dev/null` por `shopt -s nullglob` + for limpio. Victoria necesita actualizar sync.sh del remoto.

### [00:40] - Sync: completar AGENTS.md con datos reales
- **Tipo**: infra
- **Modificado**: armada-sync/AGENTS.md
- **Afecta a**: kalimete, victoria
- **Causa**: AGENTS.md tenía campos vacíos (URL, estructura, conectividad)
- **Estado**: ✅ sincronizado
- **Notas**: se completaron URLs, conectividad SSH, estructura del repo, automatización, servicios (OpenShell corregido), reglas de operación con límites de contexto y GLM-5.2.

---

<continuar arriba — los más recientes primero>
