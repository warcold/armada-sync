# 🗺️ MAPA DE AGENTES — Ecosistema Armada

## Topología (2026-08-14, validado)

```
                    ┌─────────────────────────────────────────────┐
                    │            REDES INTERNAS (LAN)              │
                    │                                            │
  kalimete ─── LAN ─┼── victoria ─── RDP/SSH tunneled ── Alfredo│
  (10.0.0.106) SSH │  (10.0.0.5)                             │
       │       1666│                                        │
       │           │      jonass local NAS (SSH roto)         │
       └───────────│─ 10.0.0.20:1222 ───⚠️ FUERA SERVICIO     │
                    │                                          │
   Cloudflare: Alfred@armada.do                               │
   Zones: armada.do | micaserogou.com | taohemps.com          │
   Túnel: victoria-armada → victoria.local:8010 (LLM)         │
                    └───────────────────────────────────────────┘
```

## Nodos

### 1. kalimete (10.0.0.106) — HUB / Cerebral
- User: warcold (UID 1000, zsh), SSH 1111
- Sync hub: `~/armada-sync` (push/pull)
- Docker: 7 containers (tapmap, woodly, micaserogou-restart, kalimete, taohemps-frontend, taohemps-backend, petsuite)
- Systemd: ssh, nginx, docker, containerd, cron, sddm, waydroid, kalimete-tunnel, publish-kalimete-subdomains, dnsmasq
- opencode config: `~/.config/opencode/`
- opencode.jsonc usa gateway LLM de victoria vía túnel CF: `https://victoria.armada.do/v1`

### 2. victoria (10.0.0.5) — Servidor GPU/LLM
#### ⚠️ Regla CRÍTICA: victoria = SOLO LECTURA, NUNCA ESCRIBIR
Acceso SSH a victoria SOLO es de lectura (monitorización). NUNCA intentes escribir/modificar/nomificar NADA en victoria. El usuario modifica archivos en victoria por su cuenta; kalimete SOLO los lee y actualiza la documentación en kalimete.
- User: warcold (UID 1001, rbash), SSH 1666, llave `~/.ssh/id_ed25519_kalimete`
- sudoers: solo `sqlite3ro_real` como victoria (NOPASSWD, requiere pty)
- GPU: NVIDIA GB10 (~48GB VRAM, driver 580.159.03, CUDA 13.0)
- vLLM: `nvidia/Qwen3.6-35B-A3B-NVFP4` (standalone, :8000, max-model-len 262144)
- CPU: 20 cores ARM64 (10x Cortex-X925 + 10x Cortex-A725), 121GB RAM, 3.7TB NVMe
- OS: Ubuntu 24.04.4 LTS, Kernel 6.17.0-1022-nvidia, ARM64
- Servicios: vLLM :8000, gateway :8010, nginx :443 SSL (mkcert), cloudflared, RDP :3389
- 6 llaves API en DB: alfredo(admin), victoria(admin), warcold(readonly), juancarlos(coder), mario(falla), friend-key(falla)
- DB: `/home/victoria/.victoria-llm/llm-gateway.db` (api_keys, usage_log, sqlite_sequence)
- CA mkcert en kalimete: `~/.local/share/mkcert/rootCA.pem`

### 3. jonass (10.0.0.20) — NAS/Respaldo — FUERA SERVICIO
- User: jonas, SSH 1222, key rota desde 2026-08-12
- Roles: NAS, backups (/srv/backups/), DDNS updater
- Sin cron de sync, sin agentes

## Agentes (solo kalimete)

### TAB visibles
| Agente | Modo | Función |
|---|---|---|
| kalimete | primary | CEREBRO CENTRAL, coordina TODO |
| plan | built-in | Planificar proyectos nuevos |
| build | built-in | Implementar código en proyectos nuevos |

### Subagentes ocultos (hidden, se delegan via tool task)
| Agente | Función | Estado |
|---|---|---|
| eco-cloudflare-dns | DNS de las 3 zonas | ✅ |
| eco-cloudflare-security | SSL, WAF, firewall, tokens | ✅ |
| eco-cloudflare-storage | KV, D1, Queues (NO R2) | ✅ |
| eco-cloudflare-tunnels | Túneles cloudflared | ✅ |
| eco-cloudflare-workers | Workers/Pages/deploy | ✅ |
| eco-accesos | ~~SSH/access management~~ | 🔴 roto (symlink sin target) |
| eco-voice | ~~Voz/STT/TTS~~ | 🔴 roto (servicio ELIMINADO) |

### Agentes retirados
cloudflare → kalimete, ecosistema → kalimete, cf-dns→eco-cloudflare-dns, cf-security→eco-cloudflare-security, cf-storage→eco-cloudflare-storage, cf-tunnels→eco-cloudflare-tunnels, cf-workers→eco-cloudflare-workers, jonas-ro, kalimete-ro, kalimete-ro-agent — archivo backup BORRADO 2026-08-14, solo historial git.

## Reglas Anti-Desborde
- Modelo Qwen3.6 max 262144 tokens. opencode.jsonc usa context:240000 / output:32000 (**272000 total — excede el límite real de 262144**). Ajustar output a ≤22144.
- NUNCA volcar archivos grandes al chat (find/grep sobre node_modules, logs completos).
- Usar head, grep -c, wc -l, o escribir a /tmp y leer con offset.

## Mantención del Mapa
- Cada cambio de agente → actualizar este archivo + repo (agents/ + AGENTS.md).
- Cada cambio de infraestructura → actualizar MAPA local + CHANGELOG.md + commit+push.
