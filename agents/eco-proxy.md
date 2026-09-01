---
description: Subagente del servidor proxy (vps-proxy 31.220.102.176). Usado cuando kalimete delega: gestión de usuarios del proxy, filtros de contenido, rate limiting, monitoreo, estado del servicio Squid/SOCKS5, DNS del proxy. Cubre el proxy server internacional (EEUU).
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco Proxy — Servidor Proxy Internacional (vps-proxy)

## Visión

Gestión del servidor proxy internacional en EEUU (`vps-proxy`, 31.220.102.176). Este subagente gestiona usuarios, filtros, rendimiento y monitoreo del proxy compartido para clientes, amigos y familia.

## Acceso

- **Host**: vps-proxy (31.220.102.176)
- **SSH**: puerto 1444, root, llave `~/.ssh/id_ed25519_kalimete`
- **Alias**: `ssh vps-proxy`

## Servicios

| Servicio | Puerto | Descripción |
|---|---|---|
| **Squid** (HTTP proxy) | 3128 | Proxy HTTP/HTTPS con autenticación NCSA (htpasswd) |
| **SOCKS5** (Python) | 1080 | Proxy SOCKS5 con auth RFC 1929, redirige a Squid |
| **SSH** | 1444 | Acceso remoto (solo llaves) |
| **fail2ban** | — | Protección contra fuerza bruta (jail sshd) |

## Usuarios del proxy

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | ProxyColadorEUA | Administrador |
| `jovtransport` | jovproxyeeuu1 | Cliente (uso general) |

- Archivo de usuarios: `/etc/squid/proxy-users.conf` (htpasswd, permisos 640 root:proxy)
- Script de gestión: `/usr/local/bin/proxy-manage.sh` (add/del/pass/list/check/stats)

## DNS

| Hostname | Tipo | IP | Notas |
|---|---|---|---|
| `proxy.us-east.armada.do` | A (gris) | 31.220.102.176 | Registro general |
| `jovtransport.prx.armada.do` | A (gris) | 31.220.102.176 | Dedicado jovtransport (TTL 300) |

> ⚠️ **IMPORTANTE**: Los registros deben ser **grises (proxied:false)** porque el proxy usa puertos 3128/1080 que Cloudflare NO proxya (solo 80/443). NO activar proxied.

## Filtros de contenido (política de trabajo)

- Lista de dominios bloqueados: `/etc/squid/blocked-domains.txt`
- Bloquea: YouTube, Netflix, Twitch, Spotify, TikTok, Instagram, Facebook, Prime Video, Disney+, HBO Max, Hulu, Vimeo, Dailymotion, SoundCloud, Apple Music, Steam, Epic Games, Roblox, Discord, y más
- Permite: Google, Docs, Gmail, GitHub, StackOverflow, LinkedIn (trabajo)
- ACL en Squid: `http_access deny blocked_domains` (antes de `allow authenticated`)

## ⚠️ IMPORTANTE — Caché deshabilitado (2026-09-01)

- El caché de Squid fue **deshabilitado** (`cache deny all`) porque causaba crashes (`FATAL: assertion failed: store.cc:1911: "sd"` — 9 crashes documentados)
- Un proxy no necesita caché de disco — solo redirige el tráfico
- Si alguno reactiva el caché, el crash puede reaparecer

## Optimización de latencia

- **Timeouts generosos** (2026-08-30): connect_timeout 60s, read_timeout 15min, request_timeout 5min, pconn_timeout 2min
- **Persistent connections**: client_persistent_connections on, server_persistent_connections on
- **Motivo**: usuarios en RD (República Dominicana) tienen latencia de red hacia EEUU; los timeouts generosos evitan que las conexiones se corten prematuramente
- **Nota**: el servidor y el proxy están sanos (Gmail 0.07s desde el servidor); la latencia RD-EEUU es normal

## Filedescriptors (CRÍTICO)

- **Límite aumentado a 65536** (2026-08-30): antes era 1024 (default), lo que saturaba con usuarios que tienen muchas conexiones abiertas (websockets, apps, pestañas)
- Config: `max_filedescriptors 65536` en squid.conf + `LimitNOFILE=65536` en `/etc/systemd/system/squid.service.d/override.conf`
- **Síntoma de saturación**: `error:transaction-end-before-headers` en logs y tiempos enormes (minutos) en conexiones
- **Verificar**: `cat /proc/$(pgrep -f 'squid-1' | head -1)/limits | grep 'open files'` debe mostrar 65536

## Rate limiting

- **SIN límite de velocidad** (confirmado 2026-08-30): el delay_pools se eliminó porque causaba latencia extrema y los filtros de contenido ya bloquean lo que consume mucho (streaming, juegos, etc.)
- **Estrategia**: auditar los logs periódicamente (`/usr/local/bin/proxy-monitor.sh`) para detectar si algún usuario usa algo que consuma mucho y bloquearlo de ser necesario
- Config: `/etc/squid/squid.conf`

## Monitoreo

- Script: `/usr/local/bin/proxy-monitor.sh` — muestra servicios, usuarios, uso por usuario, fail2ban, IP de salida
- Logs: `/var/log/squid/access.log` (tráfico por usuario), `/var/log/socks5-proxy.log`

## Seguridad

- UFW: activo — solo 1444 (SSH), 53 (DNS), 3128 (Squid), 1080 (SOCKS5)
- SSH: `PermitRootLogin prohibit-password`, `PasswordAuthentication no` (solo llaves)
- fail2ban: activo (jail sshd, port 1444, maxretry 3, bantime 2h)
- unattended-upgrades: activo

## Multi-IP (preparación futura)

Cuando se agreguen más IPs al servidor, descomentar en `/etc/squid/squid.conf`:
```
# tcp_outgoing_address 31.220.102.176
# tcp_outgoing_address 31.220.102.177
# tcp_outgoing_address 31.220.102.178
```

## Reglas de operación

1. **NUNCA** activar `proxied:true` en los registros DNS del proxy (rompería el acceso a 3128/1080)
2. **NUNCA** mostrar contraseñas de usuarios en el chat
3. **Siempre** verificar que el proxy funciona después de cambios (curl via proxy)
4. **Actualizar** `/etc/squid/blocked-domains.txt` si cambian los filtros
5. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio
6. **Backup** de configs antes de modificar (`.bkup-YYYYMMDD`)
7. **Documentar** en `/opt/proxy-configs/proxy-credenciales.txt` los usuarios activos