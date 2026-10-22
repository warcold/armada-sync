# 🗺️ MAPA DE AGENTES — Ecosistema Armada

## Topología (2026-09-19, validado — todos los SSH probados en vivo)

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
                     │      vps-proxy (proxy Squid/SOCKS5)      │
                     └── 31.220.102.176:1444 ─── ✅ ACTIVO     │
                     │                                          │
    Cloudflare: Alfred@armada.do                               │
    Zones: armada.do | taohemps.com          │
    Túnel: victoria-armada → victoria.local:8010 (LLM)         │
                     └───────────────────────────────────────────┘
```

## Nodos

### 1. kalimete (10.0.0.106) — HUB / Cerebral
- User: warcold (UID 1000, zsh), SSH 1111
- Sync hub: `~/armada-sync` (push/pull)
- Docker: 7 containers (tapmap, kalimete, taohemps-frontend, taohemps-backend, petsuite, **wordpress-local**, **wordpress-db**)
- **opencode.jsonc**: 4 providers + MCPs `godot-ror`, `blender` (verificado 2026-10-20; el archivo es la fuente única)
  1. **vllm** (local): Qwen3.6-35B-A3B-NVFP4 via victoria (2 variantes)
      - `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` → "Coding con Victoria" (reasoning: false)
      - `nvidia/Qwen3.6-35B-A3B-NVFP4` → "Thinking · Coding con Victoria" (reasoning: true)
      - baseURL: `http://victoria.local:8010/v1` (LAN directo al gateway)
      - limit: context 220000 / output 32000 (total 252000 < 262144 ✅)
      - apiKey: `vllm-key-5d43...` (admin alfredo)
  2. **nvidia** (cloud): DeepSeek V4 Flash/Pro via NVIDIA API Catalog
     - `deepseek-ai/deepseek-v4-flash-0731` → "DeepSeek V4 Flash" (reasoning: true)
     - `deepseek-ai/deepseek-v4-pro-0813` → "DeepSeek V4 Pro" (reasoning: true)
     - baseURL: `https://integrate.api.nvidia.com/v1`
     - apiKey: `nvapi-...` (key compartida desde victoria)
     - Contexto nativo: 1M tokens (vs 262K del Qwen local)
- WordPress Dev: `~/dev/wordpress/` — HUB WP (reorg owner 2026-10-17): `plugins/` (proyectos de plugins con sus dev labs) + `websites/` (un ambiente por CLIENTE, nombrado por dominio) — agente `wordpress-dev` = SISTEMA/umbrella; cada plugin su agente; cada website su agente (primero: `MaganTech`, `Micaserogou`)
  - Dev lab Armada Suite: `http://localhost:8091` (loopback; dominio LAN `wordpress.kalimete.local` **RETIRADO 2026-10-18** — consolidación: solo `magantech.kalimete.local` para el proyecto) | DB :3307 (wordpress-db, MariaDB 10.11) — compose project `wordpress`, repo git `~/dev/wordpress/plugins/armada-suite` (HEAD e2c86ed; 5.4.0/5.4.1/5.4.2 + docs CONTROL-PLANE; remote vacío)
  - Dev lab ZionV CRM: `http://localhost:8092` | LAN/SSL `https://zionv.kalimete.local` | DB :3308 — compose project `zionv-crm`, git del plugin en `wp-content/plugins/zionv-crm-plugin/.git` (HEAD 9698224, v1.56.3)
  - Website cliente MaganTech (PREPROD): `http://localhost:8093` | LAN/SSL `https://magantech.kalimete.local` | DB :3309 — compose project `magantech`, WP 7.1.3-php8.3 ESPEJO de prod, plugin instalado desde ZIP de release, red `erpipo-dev-network` → ERP local :8100 tenant 10 + correo simulado mailpit (UI :8026) — env `~/dev/wordpress/websites/magantech.com.do/`, agente `MaganTech` — espejo 1:1 verificado 2026-10-18
  - Website cliente Micaserogou (PREPROD): `http://localhost:8094` | LAN/SSL `https://micaserogou.kalimete.local` | DB :3311 — compose project `micaserogou`, WP 7.1.3-php8.3 ESPEJO de prod, plugin 5.4.2 instalado desde ZIP, red `erpipo-dev-network` → ERP local :8100 tenant 3 + correo simulado mailpit (UI :8027) — env `~/dev/wordpress/websites/micaserogou.com/`, agente `Micaserogou` — verificado 2026-10-20 (smoke 7/7)
  - Autenticación: WP-Admin `admin` (UI labs); REST = Application Passwords — la password de login NO sirve para REST
  - SSL: mkcert CA en sistema; certs por dominio en `/etc/ssl/local-certs/` (vivos: magantech exp. 2029-01-18, micaserogou exp. 2029-01-20) | Nginx vhosts: `/etc/nginx/sites-available/` (retirado wordpress → `/etc/nginx/attic-20261018/`) | Hosts: `127.0.0.1 <dominio>.kalimete.local` | LAN clientes (2026-10-18): dnsmasq wildcard `*.kalimete.local → 10.0.0.106` (`no-hosts` — las líneas 127.0.0.1 de /etc/hosts ya no ganan) + mDNS avahi (magantech/zionv/erp/micaserogou) — CA para equipos: `http://kalimete.local/kalimete-rootCA.pem`
  - Dominios locales por proyecto (política owner 2026-10-17): cada proyecto su `<proyecto>.kalimete.local` (mkcert + nginx-TLS front-door). Verificados 200: `zionv`, `magantech`, `erp` (2026-10-18); `micaserogou` (2026-10-20). `wordpress.kalimete.local` retirado 2026-10-18 (consolidación: el dev lab :8091 queda solo por loopback; el dominio del proyecto MaganTech es `magantech`). Futuros heredan vía `docs/NUEVO-WEBSITE-TEMPLATE.md` §8
  - Puertos: nginx-TLS 443 + 8090 → Docker loopback 8091; labs 8092/8093/8094 + DBs 3307/3308/3309/3311 (**3310 ocupado por otro proceso**; convención websites 809X/330X ascendente — próximo 8095/3312, ver `docs/NUEVO-WEBSITE-TEMPLATE.md`)
  - **Plugin `Armada Suite` v5.4.2 (agente `armada-suite`)** — super-plugin (unifica erp-commerce-suite + WPVibe + AIOWPM vendored desde 5.0.0). Option única `erp_suite_settings`, modo sellado dev/público: dev = ERP `http://172.19.0.1:8100/api` + LLM `http://10.0.0.5:8010/v1` + img `https://erp.kalimete.local`; public = ERP `https://erpipos.armada.do/api` + LLM `https://victoria.armada.do/v1`. Multitenant por-sitio: local tenant 10 MaganTech / tenant 3 Micaserogou; prod multi-negocio (magantech, micaserogou, futuros). Tests regresión 25/25 (5.4.2). ZIPs canónicos en `~/dev/wordpress/plugins/armada-suite/export/` (5.4.2 sha256 157b1633…; 5.4.1 4bb2fa2c…; 5.4.0 24b4255c…). 5.4.0: el sync APLICA los datos del negocio del ERP a la tienda (paridad dev/público) + snapshot/rollback. 5.4.1: template del tema activo editable vía ops (work mode, gates fail-closed) + fix rollback v4.3.0 + fix SiteBackup. 5.4.2: auto-sync diario de identidad/config del negocio (ERP→WP, guards + setting + UX nombre faltante).
  - Producción cliente MaganTech: `https://magantech.com.do/` (cPanel, WP 7.1.3/PHP 8.5.11, armada-suite 5.4.0, tema Hello Elementor) — conexión remota vía `erpsuite/v1/ops` (App Password usuario dedicado Victoria; credencial en `websites/magantech.com.do/secrets/`)
  - Producción cliente Micaserogou: `https://micaserogou.com/` (cPanel hosting externo, WP 7.1.3, sin plugin aún) — deploy pendiente: api_key ERP prod tenant 3, usuario dedicado + App Password, permalinks, snapshot; ventana + rollback (ver `PROD-DEPLOY-CHECKLIST.md`)
  - ERP local de pruebas: `~/dev/erpipo-preprod/` (erpipo-preprod-nginx :8100) — rama dev/ecomm-erp @2306b64 (Fase 2/3 nuestras mergeadas vía PR #14 de Juan Carlos)
  - Mu-plugins: `disable-mcp-host-guard.php` (MCP host guard off). Elementor/EMCP/MCP Adapter: NO instalados en live (históricos, namespace mcp ausente)
  - **Protección contra updates**:
    - mcp-proxy.mod.js: `~/dev/wordpress/plugins/armada-suite/` (fuera del contenedor Docker)
    - Nginx config: `/etc/nginx/sites-available/` (fuera del contenedor)
    - Certificados: `/etc/ssl/local-certs/` (fuera del contenedor)
    - Permisos SSL: `chown root:www-data 640` (persisten)
    - Permisos WordPress: `chown -R www-data:www-data /var/www/html/wp-content` (persisten)
    - Mu-plugins: `/var/www/html/wp-content/mu-plugins/` (no se borran con updates)
- Systemd: ssh, nginx, docker, containerd, cron, sddm, waydroid, kalimete-tunnel, publish-kalimete-subdomains, dnsmasq
- opencode config: `~/.config/opencode/`
- opencode.jsonc usa gateway LLM de victoria en LAN: `http://victoria.local:8010/v1` (verificado 2026-09-14)

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

### 3. vps-preprod (154.53.35.102) — VPS Production (multi-app clientes)
- User: root, SSH 1333, llave `~/.ssh/id_ed25519_kalimete`
- Alias: `ssh vps-preprod`
- Servicios: Docker, caddy, auth.armada.do, pets.armada.do, ragnarok.armada.do (landing juego nuevo RoR), scriberr.armada.do, whiteboard.armada.do, docuseal.armada.do, nextcloud.armada.do, IRC El Corito (6667/6697/7209, InspIRCd nativo justin_t), **Proxy Armada (Squid 6.14 :3128 + SOCKS5 :1080 dockerizado, migrado de vps-proxy 2026-10-22 — stack `/opt/proxy-stack/`, red aislada proxy-net, servicio PARA CLIENTES, el VPS NO lo usa)**
- TLS IRC: certbot standalone (challenge 8088 + REDIRECT transitorio) — renovado 2026-10-21, expira 2027-01-19, auto-renovación certbot.timer (detalle en agents/irc.md)
- DNS: auth.armada.do, docuseal.armada.do, nextcloud.armada.do, pets.armada.do, ragnarok.armada.do, scriberr.armada.do, whiteboard.armada.do → 154.53.35.102 (CF proxied) — ragnarok.cp.armada.do BORRADO de CF 2026-10-20; **proxy.us-east.armada.do + jovtransport.prx.armada.do → 154.53.35.102 (gris, cutover 2026-10-22)**
- Proyectos locales: kalimete, victoria, jonas (fuera), Windows (10.0.0.64)
- UFW: active (solo rangos CF en DOCKER-USER + excepción 3128/1080 en /etc/docker-firewall/apply.sh); iptables INPUT: IRC 6667/6697/7209 + proxy 3128/1080 ACCEPT + CF 80/443 + SSH 1333, política DROP
- OpenVPN: active (openvpn@server.service)

### 4. vps-proxy (31.220.102.176) — ⚠️ PENDIENTE DE CANCELACIÓN (Contabo) — proxy MIGRADO a vps-preprod 2026-10-22
- User: root, SSH 1444, llave `~/.ssh/id_ed25519_kalimete`
- Alias: `ssh vps-proxy` (restaurado 2026-09-19 en `/etc/ssh/ssh_config.d/10-armada-hosts.conf`)
- **MIGRACIÓN COMPLETADA 2026-10-22**: Squid+SOCKS5 dockerizados en vps-preprod (/opt/proxy-stack), DNS repuntado (proxy.us-east + jovtransport.prx → 154.53.35.102), validado end-to-end. Esta caja queda como FALLBACK temporal hasta que el owner la cancele en Contabo — avisar a jovtransport si usa la IP 31.220.102.176 hardcodeada (usar hostname).
- Reboot 2026-10-19 = primer reboot en 260 días (kernel 6.8.0-147 por unattended-upgrades). **NO fue reinstalada** — misma instalación (wtmp/apt logs/certs intactos). Shutdown+boot limpio también el 2026-10-21 16:31→16:40 (causa por confirmar).
- Configs migradas: usuarios (admin, jovtransport), 111 filtros, filedescriptors 65536, cache deny all — copias originales intactas aquí.
- certbot 2.9.0 con /etc/letsencrypt: 2 certs expirados de dominios que ya NO apuntan a esta caja (el.colador.de.alfredo.pro → vps-preprod/IRC; colador.union-chat.online → IPs de terceros 104.219.250.37/2.59.170.20, pendiente owner).
- Sin Docker. Sin crontab.
- Servicios (aún corriendo como fallback): Squid Proxy 6.14 (HTTP :3128), SOCKS5 Python (:1080), SSH (:1444)
- DNS: proxy.us-east.armada.do → 31.220.102.176 (gris/CF); jovtransport.prx.armada.do → 31.220.102.176 (gris, dedicado jovtransport)
- **Squid Proxy (HTTP/HTTPS)**:
  - Puerto: 3128
  - Autenticación: Basic NCSA (htpasswd)
  - Usuarios: `admin` (ProxyColadorEUA), `jovtransport` (jovproxyeeuu1)
  - Scripts: `/usr/local/bin/proxy-manage.sh` (add/del/pass/list/check/stats), `/usr/local/bin/proxy-monitor.sh` (monitor uso)
  - Config: `/etc/squid/squid.conf`, usuarios: `/etc/squid/proxy-users.conf`
  - Rate limiting: SIN límite (filtros de contenido bastan, confirmado 2026-08-30)
  - Filtros de contenido: `/etc/squid/blocked-domains.txt` (bloquea streaming/consumo: YouTube, Netflix, Twitch, Spotify, TikTok, Instagram, Facebook, juegos, Discord, etc.)
  - Multi-IP: preparado en squid.conf (tcp_outgoing_address comentado)
  - Logs: `/var/log/squid/access.log` (tráfico por usuario)
- **SOCKS5 Proxy**:
  - Puerto: 1080
  - Servicio: `socks5-proxy.service` (Python, RFC 1929 username/password auth)
  - Script: `/usr/local/bin/socks5-proxy.py`
  - Backend: redirige a Squid HTTP local (:3128)
  - Usuarios: mismos que Squid (jovtransport/admin)
  - Logs: `/var/log/socks5-proxy.log`
- **Seguridad**:
  - UFW: activo — solo 1444 (SSH), 53 (DNS), 3128 (Squid), 1080 (SOCKS5)
  - SSH: `PermitRootLogin prohibit-password`, `PasswordAuthentication no` (solo llaves)
  - fail2ban: activo (jail sshd, port 1444, maxretry 3, bantime 2h)
  - unattended-upgrades: activo
- **Usuarios SO**: root, warcold (solo acceso propio; eliminados ircd/justin/kboom/ubuntu 2026-08-30)
- **Proyectos en /opt**: solo `proxy-configs` (credenciales + guías)
- **Limpieza 2026-08-30**: eliminados OpenVPN, weechat, inspircd, dante, redsocks, shadowsocks, /opt/google, /opt/inspircd, /opt/proxy-infra
- Credenciales: `/opt/proxy-configs/proxy-credenciales.txt`
- Guías cliente: `/opt/proxy-configs/`

### 5. jonass (10.0.0.20) — NAS/Respaldo — FUERA SERVICIO
- User: jonas, SSH 1222, key rota desde 2026-08-12
- Roles: NAS, backups (/srv/backups/), DDNS updater
- Sin cron de sync, sin agentes
- Verificado 2026-09-19: `No route to host` — no intentar operaciones

### 6. kalimete-preprod (erp.kalimete.local) — Preprod ERP dockerizado — ✅ ACTIVO (2026-09-19)
- **URL**: `https://erp.kalimete.local` (nginx TLS local + reverse proxy)
- **Puertos**: :8100 (Nginx proxy), :3310 (DB MySQL), :6390 (Redis), :8102 (phpMyAdmin)
- **Stack**: php:8.3-fpm + mysql:8.0 + redis:7-alpine + nginx (standalone, sin vínculo a prod)
- **Dump importado**: `facturacion_db-20260919.sql` (528M, 601 migraciones, batch 145)
- **Código**: `~/dev/erpipo-preprod/code/sistema-facturacion/`
- **Repo privado**: `github.com/warcold/erpipo-preprod` (PRIVATE, sin DB ni secrets; remotos: origin=upstream RO, preprod=push)
- **.env**: preprod.env (APP_URL=https://erp.kalimete.local, APP_DEBUG=false, uid 1000:1000)
- **SSL**: mkcert (erp.kalimete.local.pem, expira 2028-12-18)
- **Permisos**: storage/logs/ y storage/framework/ con 775 (warcold:warcold = UID 1000)
- **Workers**: queue + scheduler en Redis (mirrors dev-stack prod)
- **Subagente**: erp-dev (gestiona preprod, código, migraciones)

### 7. kalimete — Preprod ERP (erpipo) — ✅ ACTIVO (2026-09-19)
- URL: `https://erp.kalimete.local` (nginx TLS local + reverse proxy)
- Puertos: :8100 (DB MySQL), :6390 (Redis), :8101 (app FPM), :8102 (phpMyAdmin)
- Stack: php:8.3-fpm + mysql:8.0 + redis:7-alpine + nginx (mirrors dev-stack de erpipo)
- Dump importado: `facturacion_db-20260919.sql` (528M)
- Subagente: erp-dev (gestiona preprod, código, migraciones)

### 8. ecco (62.171.144.58) — VPS Ecco Qualitá (host Docker multi-servicio) — ✅ ACTIVO (desplegado 2026-10-19)
- **User**: root, SSH 22, llave `~/.ssh/id_ed25519_kalimete` (password `colador1` aún activo — pendiente apagar)
- **Alias**: `ssh ecco` (en `~/.ssh/config`)
- **Hardware**: OVH, Ubuntu 24.04.5, 4 cores AMD EPYC, 7.8GB RAM + 2G swap, 96GB disco
- **Patrón**: host Docker con servicios pequeños contenedorizados tras Caddy común (TLS Let's Encrypt automático, 80/443); red compartida `eccoqualita-proxy` para nuevos vhosts
- **Servicio 1 — EccoSuite**: `https://suit.eccoqualita.com` (Next.js 16.4 standalone + PostgreSQL 18, sin puertos públicos; contenedores ecco-caddy/ecco-app/ecco-postgres en `/opt/eccoqualita/`)
- **DNS**: suit.eccoqualita.com → 62.171.144.58 (sin Cloudflare)
- **Seguridad**: UFW (22/80/443+udp), fail2ban activos
- **Subagente**: Ecco Suit (despliegue, operación, respaldos, nuevos servicios)

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
| Cloudflare | Cloudflare único: DNS, SSL/WAF, KV/D1, túneles, Workers | ✅ |
| IRC | Servidor IRC InspIRCd (vps-preprod) | ✅ |
| Proxy | Proxy Armada dockerizado en vps-preprod (migrado de vps-proxy 2026-10-22) | ✅ |
| VPS | Servidor VPS producción (vps-preprod) | ✅ |
| Victoria Server | Servidor GPU/LLM (victoria, solo lectura) | ✅ |
| PetSuite | Proyecto PetSuite (pets.armada.do) | ✅ |
| Taohemps | Proyecto Taohemps (taohemps.com) | ✅ |
| ragnarok-server | SERVIDOR rAthena (vps-preprod) — 🔴 **CERRADO y BORRADO 2026-10-20** (containers+volúmenes+imágenes+/srv/ragnarok eliminados, ~7GB liberados; backup completo en kalimete `~/backups/ragnarok-vps-preprod-20261020/` 4.4GB; landing reciclado → container `ror-landing` en /srv/ror-landing) | ⏹ |
| Nextcloud | Proyecto Nextcloud + whiteboard | ✅ |
| Authentik | SSO Authentik (auth.armada.do) | ✅ |
| DocuSeal | Proyecto DocuSeal | ✅ |
| Scriberr | Proyecto Scriberr | ✅ |
| wordpress-dev | SISTEMA WordPress (umbrella de plugins): stack :8091/:3307, compose, certs, secrets, DB | ✅ |
| armada-suite | Plugin WP Armada Suite 5.4.2 (multitenant WP↔ERP, magantech/micaserogou/futuros) — NUEVO (2026-10-15) | ✅ |
| zionv-crm | Plugin ZionV CRM 1.56.3 (stack propio :8092, GitHub warcold/zionv-crm) — NUEVO en registro (2026-10-15) | ✅ |
| magantech | Website cliente MaganTech (magantech.com.do): preprod :8093 + dominio local; prod cPanel vía erpsuite/v1/ops (local-first) — NUEVO (2026-10-17) | ✅ |
| micaserogou | Website cliente Micaserogou (micaserogou.com): preprod :8094 + dominio local; prod cPanel hosting externo (deploy pendiente) — NUEVO (2026-10-20) | ✅ |
| erp-dev | Preprod ERP erpipo (kalimete docker) | ✅ |
| record-of-ragnarok | JUEGO Godot activo: **MMORPG** Record of Ragnarok (multiplayer día 1: zonas PvE/PvP, chars globales Postgres, Godot headless server; mecánicas RO pre-renewal 99/70 × temática anime × estética Enshrouded; landing = ragnarok.armada.do) — agente dedicado + MCP godot-ror, proyecto ~/dev/games/record-of-ragnarok/ — NUEVO (2026-10-20) | ✅ |
| game-studio | Fábrica de juegos 3D desde cero (Blender MCP + Godot MCP + victoria; pipeline 7 fases) — NUEVO (2026-10-18) | ✅ |
| blender | Blender 5.0.1 + MCP TCP :9876 (decimate/retopo GLBs, escenas procedurales; dominio ~/dev/games/) — NUEVO en registro (2026-10-20) | ✅ |
| proxmark | Proxmark3 RFID/NFC (kalimete /dev/ttyACM0) | ✅ |
| intigriti | Bug bounty Intigriti (~/dev/ethical-hacking, kalimetehunt.sh) — NUEVO (2026-10-08) | ✅ |
| ecco-suit | VPS Ecco Qualitá (62.171.144.58, `ssh ecco`): host Docker multi-servicio; hoy EccoSuite en suit.eccoqualita.com — NUEVO (2026-10-19) | ✅ |

### Agentes retirados
cloudflare → kalimete, ecosistema → kalimete, cf-dns→Cloudflare-dns, cf-security→Cloudflare-security, cf-storage→Cloudflare-storage, cf-tunnels→Cloudflare-tunnels, cf-workers→Cloudflare-workers, jonas-ro, kalimete-ro, kalimete-ro-agent — archivo backup BORRADO 2026-08-14, solo historial git.

## Reglas Anti-Desborde
- Modelo Qwen3.6 max 262144 tokens. opencode.jsonc usa context:240000 / output:32000 (**272000 total — excede el límite real de 262144**). Ajustar output a ≤22144.
- NUNCA volcar archivos grandes al chat (find/grep sobre node_modules, logs completos).
- Usar head, grep -c, wc -l, o escribir a /tmp y leer con offset.

## Mantención del Mapa
- Cada cambio de agente → actualizar este archivo + repo (agents/ + AGENTS.md).
- Cada cambio de infraestructura → actualizar MAPA local + CHANGELOG.md + commit+push.
