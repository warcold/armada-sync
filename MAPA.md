# 🗺️ MAPA DE AGENTES — Ecosistema Armada

## Topología (2026-08-30, validado)

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
                    │      vps-preprod (VPS prod)              │
                    └── 154.53.35.102:1333 ─── IRC, auth.do   │
                    │      vps-proxy (VPS proxy)               │
                    └── 31.220.102.176:1444 ─── Squid Proxy   │
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
- Docker: 9 containers (tapmap, woodly, micaserogou-restart, kalimete, taohemps-frontend, taohemps-backend, petsuite, **wordpress-local**, **wordpress-db**)
- **opencode.jsonc**: 2 providers configurados
  1. **vllm** (local): Qwen3.6-35B-A3B-NVFP4 via victoria (2 variantes)
     - `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` → "Coding con Victoria" (reasoning: false)
     - `nvidia/Qwen3.6-35B-A3B-NVFP4` → "Thinking · Coding con Victoria" (reasoning: true)
     - baseURL: `https://victoria.armada.do/v1`
     - apiKey: `vllm-key-5d43...` (admin alfredo)
  2. **nvidia** (cloud): DeepSeek V4 Flash/Pro via NVIDIA API Catalog
     - `deepseek-ai/deepseek-v4-flash-0731` → "DeepSeek V4 Flash" (reasoning: true)
     - `deepseek-ai/deepseek-v4-pro-0813` → "DeepSeek V4 Pro" (reasoning: true)
     - baseURL: `https://integrate.api.nvidia.com/v1`
     - apiKey: `nvapi-...` (key compartida desde victoria)
     - Contexto nativo: 1M tokens (vs 262K del Qwen local)
- WordPress Dev: `~/dev/wordpress/` — Stack Docker local con WordPress 7.1 + Elementor 4.2.3 + EMCP Tools v3.14.0 + MCP Adapter 0.5.0
  - URL local: `http://localhost:8090` | URL LAN/SSL: `https://wordpress.kalimete.local`
  - URL LAN: `http://wordpress.kalimete.local` (redirect 301 → HTTPS)
  - DB: localhost:3307 (wordpress-db container)
  - Autenticación: `admin:admin123` (Basic Auth REST)
  - SSL: mkcert CA instalada en sistema, certificado válido hasta 2028-11-30
  - Proxy MCP modificado: `mcp-proxy.mod.js` (usa ?rest_route=, captura Mcp-Session-Id)
  - ~60+ herramientas EMCP Tools expuestas vía MCP (Elementor page builder)
  - Se integra con vLLM de victoria para automatización de páginas Elementor
  - Nginx config: `/etc/nginx/sites-available/wordpress.kalimete.local.conf`
  - Hosts: `10.0.0.106 wordpress.kalimete.local` (accesible desde LAN)
  - SSL: `mkcert` con CA instalada en sistema y Firefox (trust store)
  - Mu-plugin de protección: `/var/www/html/wp-content/mu-plugins/disable-mcp-host-guard.php`
    → Deshabilita EMCP Tools MCP host guard (permite proxy `localhost:8090` → `wordpress.kalimete.local`)
    → PERSISTE: los mu-plugins no se borran con updates de WordPress/plugins
  - **Protección contra updates**:
    - mcp-proxy.mod.js: `~/dev/wordpress/` (fuera del contenedor Docker)
    - Nginx config: `/etc/nginx/sites-available/` (fuera del contenedor)
    - Certificados: `/etc/ssl/local-certs/` (fuera del contenedor)
    - Permisos SSL: `chown root:www-data 640` (persisten)
    - Permisos WordPress: `chown -R www-data:www-data /var/www/html/wp-content` (persisten)
    - Mu-plugins: `/var/www/html/wp-content/mu-plugins/` (no se borran con updates)
  - **Política de updates**: NO actualizar `mcp-adapter` (manual), NO actualizar `elementor` sin probar, actualizar `emcp-tools` solo patch updates (3.14.0 → 3.14.1)
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

### 3. vps-preprod (154.53.35.102) — VPS Production
- User: root, SSH 1333, llave `~/.ssh/id_ed25519_kalimete`
- Alias: `ssh vps-preprod`
- Servicios: Docker, caddy, auth.armada.do, pets.armada.do, ragnarok.armada.do, scriberr.armada.do, whiteboard.armada.do, docuseal.armada.do, nextcloud.armada.do
- DNS: auth.armada.do, docuseal.armada.do, nextcloud.armada.do, pets.armada.do, ragnarok.armada.do, ragnarok.cp.armada.do, scriberr.armada.do, whiteboard.armada.do, woodly.armada.do → 154.53.35.102 (CF proxied)
- UFW: active (solo rangos CF en DOCKER-USER)
- OpenVPN: active (openvpn@server.service)

### 4. vps-proxy (31.220.102.176) — Proxy Server Internacional
- User: root, SSH 1444, llave `~/.ssh/id_ed25519_kalimete`
- Alias: `ssh vps-proxy`
- Servicios: Squid Proxy 6.14 (puerto 3128), OpenVPN (puerto 1194/udp), SSH (puerto 1444)
- DNS: proxy.us-east.armada.do → 31.220.102.176 (gris/CF)
- Squid Proxy:
  - Puerto: 3128 (HTTP/HTTPS)
  - Autenticación: Basic NCSA (htpasswd)
  - Usuarios: admin (armadaproxy2026), carlos (uzh/n4KzMh7jWZPU), maria (miClave123)
  - Scripts: `/usr/local/bin/proxy-manage.sh` (add/del/pass/list/check/stats)
  - Config: `/etc/squid/squid.conf`, usuarios: `/etc/squid/proxy-users.conf`
  - Logs: `/var/log/squid/access.log` (tráfico por usuario)
  - Guías cliente: `/opt/proxy-configs/`
  - UFW: puerto 3128/tcp abierto
- InspIRCd: DEAD (desde 2026-03-17), sin impacto
- UFW: active (1194/udp, 1444/tcp, 3128/tcp, 80/tcp, 53/tcp, 53/udp)

### 5. jonass (10.0.0.20) — NAS/Respaldo — FUERA SERVICIO
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
| wordpress-dev | WordPress+Elementor+EMCP+MCP stack | ✅ |
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
