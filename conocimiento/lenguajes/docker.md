# Docker — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `docker --version` → 29.6.2)
> **Docs oficiales**: https://docs.docker.com/reference/cli/docker/

## Versiones en uso

- Docker 29.6.2 en victoria — 3 contenedores del stack (vllm, sandbox, publisher) + n8n
- kalimete: 7 contenedores (proyectos web)

## Contenedores del stack (victoria)

| Contenedor | Red | Restart | Label |
|---|---|---|---|
| `nemoclaw-vllm` | -p 8000 | unless-stopped | `com.nvidia.nemoclaw.managed-vllm=true` |
| `openshell-default--victoria-armada-*` | openshell-docker + victoria-lan (172.22.0.10) | unless-stopped | `openshell.ai.*` |
| `openclaw-publisher` | **host** | unless-stopped | `victoria.group=openclaw` |
| `n8n` | bridge | unless-stopped | — |

## Patrones que usamos

- **Digest pinned** para imágenes críticas (`@sha256:...` — NUNKA tags móviles)
- Labels de grupo (`victoria.group=`) para el ensure-loop
- Redes dedicadas: `victoria-lan` (172.22.0.0/16) para bridges, `openshell-docker` del sandbox
- `-v` mounts para TODO lo grande (HF cache, compile cache) — el container es efímero

## Gotchas descubiertos (lecciones)

- **NADA dentro de un contenedor es permanente** — snapshot antes, datos fuera, el container puede morir en cualquier momento. — (AGENTS.md §0)
- **`-p 127.0.0.1:8000:8000` rompería el sandbox** (su proxy ataca vía 172.18.0.1:8000 que NATs al publicado) — por eso el blindaje es ip6tables DROP, no bind loopback. — (CHANGELOG 2026-08-16)
- **`docker logs` corrupto tras corte eléctrico** — usar `--tail N` o LogPath directo. — (vllm.harness)
- **NO imponer docker-compose** (pelearía con nemoclaw surveillance + ensure-loop). — (victoria.md §Grupos)
- **DNS Docker no resuelve nombres >63 chars** (esquema nuevo del sandbox) — publisher por IP fija 172.22.0.10. — (CHANGELOG 2026-09-05)
- **`--network host` para el publisher** (dashboard necesita loopback del host). — (CHANGELOG 2026-09-18)

## Regla de actualización

Docker engine: actualizar con apt coordinado + reboot. Imágenes: digest pinned,
revisión trimestral (vLLM), NUNKA :latest en producción.
