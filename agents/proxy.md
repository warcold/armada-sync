---
name: Proxy
description: Subagente del Proxy Armada (Squid+SOCKS5 dockerizado en vps-preprod 154.53.35.102 desde 2026-10-22). Usado cuando kalimete delega: gestión de usuarios del proxy, filtros de contenido, rate limiting, monitoreo, estado del servicio Squid/SOCKS5, DNS del proxy.
mode: subagent
hidden: false
color: "#6366f1"
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---
> **Frescura** — el diagnostico SIEMPRE empieza con estado real (docker ps, curl :health, systemctl, journalctl, ss...). Lo pegado en este doc (estados, contadores, versiones, salidas viejas) NUNCA es verdad: este doc es la RECETA (flags, topologia querida, no-touch, historia); el edificio es lo live. Si discrepan -> actua sobre lo LIVE, cura este doc + su harness (+ CHANGELOG) y reporta la deriva. Docs upstream (GitHub/vendor) solo cuando lo live no explica el fallo — no se cachean como verdad permanente.

## ✅ MIGRACIÓN A vps-preprod COMPLETADA (2026-10-22) — vps-proxy DESACTIVADO

- El proxy corre **DOCKERIZADO en vps-preprod** (154.53.35.102): stack `/opt/proxy-stack/` (compose), contenedores `proxy-squid` (Squid 6.14, :3128) + `proxy-socks5` (Python, :1080), red aislada `proxy-net`, volumen `squid-logs`.
- **vps-proxy (31.220.102.176) = DESACTIVADO** — servidor cancelado/desactivado en Contabo; NO operativo. DNS ya NO apunta ahí.
- Validado end-to-end 2026-10-22: squid 200 (admin/jovtransport), socks5 200, filtros 403 (YouTube), auth mala 407, FD 65536, 8 dominios del VPS + IRC intactos, 0 vars proxy en sistema/contenedores.

## ⚠️ REGLA CRÍTICA — El proxy es servicio PARA CLIENTES, el VPS NO lo usa

- El stack proxy vive en su propia red docker (`proxy-net`) SIN conexión a otras redes de stacks.
- **PROHIBIDO** setear `http_proxy`/`https_proxy`/`all_proxy` en: `/etc/environment`, `/etc/profile.d/`, docker daemon, systemd global, apt, git, wget/curl, o env de contenedores del VPS. Verificado limpio 2026-10-22 (0 vars en 25 contenedores + sistema).
- Los contenedores proxy salen a internet directo (HIER_DIRECT); el DOCKER-USER del host NO filtra su tráfico saliente (su DROP aplica solo `-i $IFACE` público).

# Proxy — Servicio Proxy Armada (dockerizado en vps-preprod)

## Visión

Proxy compartido internacional para clientes, amigos y familia. Migrado de vps-proxy (Contabo EEUU) a vps-preprod el 2026-10-22 para consolidar infraestructura y cancelar la caja vieja.

## Acceso y operación

- **Host**: vps-preprod (154.53.35.102), SSH 1333, root, llave `~/.ssh/id_ed25519_kalimete`, alias `ssh vps-preprod`
- **Stack**: `/opt/proxy-stack/` (docker-compose.yml, squid/, socks5/)
- **Comandos**: `cd /opt/proxy-stack && docker compose ps` (estado) · `docker compose restart` (restart) · `docker compose logs -f squid` (logs) · `docker exec proxy-squid tail -20 /var/log/squid/access.log` (tráfico)
- **Recrear tras editar configs**: `docker compose up -d --force-recreate` (squid.conf/users/filtros van montados :ro)

## Servicios

| Servicio | Puerto | Descripción |
|---|---|---|
| **Squid 6.14** (contenedor `proxy-squid`) | 3128 | Proxy HTTP/HTTPS con autenticación NCSA (htpasswd) |
| **SOCKS5** (contenedor `proxy-socks5`) | 1080 | Proxy SOCKS5 RFC 1929, backend Squid (env SQUID_HOST=squid) |
| **fail2ban** (host) | — | jails sshd + **squid** (407 auth mala: 5 fallos/10min → ban 2h, chain FORWARD, 2026-10-22) |

## Usuarios del proxy

| Usuario | Rol |
|---|---|
| `admin` | Administrador |
| `jovtransport` | Cliente (uso general, ~13k req/día) |

- Archivo: `/opt/proxy-stack/squid/proxy-users.conf` (htpasswd, **640 root:13(proxy)** — el helper basic_ncsa_auth corre como uid/gid 13 dentro del contenedor; si queda 600 root:root la auth falla con 407 en loop)
- Cambiar pass: `htpasswd /opt/proxy-stack/squid/proxy-users.conf <user>` + `docker compose restart squid`
- Scripts legacy en vps-proxy: `/usr/local/bin/proxy-manage.sh`, `proxy-monitor.sh` (referencia; adaptar a docker si se necesitan)

## DNS (gris OBLIGATORIO — CF no proxya 3128/1080)

| Hostname | Tipo | IP | Notas |
|---|---|---|---|
| `proxy.us-east.armada.do` | A (gris) | 154.53.35.102 | Registro general (cutover 2026-10-22, TTL 300) |
| `jovtransport.prx.armada.do` | A (gris) | 154.53.35.102 | Dedicado jovtransport (TTL 300) |

> ⚠️ **NUNCA** activar proxied:true en estos registros (rompería el acceso a 3128/1080).

## Filtros de contenido (política de trabajo)

- Lista: `/opt/proxy-stack/squid/blocked-domains.txt` (111 dominios)
- Bloquea: YouTube, Netflix, Twitch, Spotify, TikTok, Instagram, Facebook, Prime Video, Disney+, HBO Max, Hulu, Vimeo, Dailymotion, SoundCloud, Apple Music, Steam, Epic Games, Roblox, Discord, y más
- Permite: Google, Docs, Gmail, GitHub, StackOverflow, LinkedIn (trabajo)
- ACL: `http_access deny blocked_domains` (antes de `allow authenticated`)

## Config Squid (notas técnicas)

- `/opt/proxy-stack/squid/squid.conf` — idéntica a la de vps-proxy excepto: `cache deny all` como directiva propia (en vps-proxy quedó inertemente pegada a un comentario), sección multi-IP limpiada.
- **Sin cache_dir** (el caché de disco causaba crashes `store.cc:1911` en vps-proxy); `cache deny all` + `cache_mem 256 MB`.
- **FD 65536**: `max_filedescriptors` en squid.conf + `ulimits.nofile` en compose + verificado `/proc/1/limits` en contenedor.
- **tmpfs /run** en compose (CRÍTICO: sin esto, `docker restart` crash-loopea con "Found fresh instance PID file /run/squid.pid with PID 1").
- Timeouts generosos (connect 60s, read 15min, request 5min) — usuarios en RD con latencia alta.
- Sin rate limiting (delay_pools eliminado 2026-08-30 — causaba latencia extrema; los filtros bastan).

## Firewall (vps-preprod)

- **INPUT** (iptables, política DROP): ACCEPT tcp 3128/1080 (posiciones 8-9, persistido en `/etc/iptables/rules.v4` vía netfilter-persistent; backup `rules.v4.bkup-20261022-proxy`).
- **DOCKER-USER** (el tráfico a puertos publicados pasa por FORWARD, NO por INPUT): excepción `-i $IFACE -p tcp -m multiport --dports 3128,1080 -j ACCEPT` en `/etc/docker-firewall/apply.sh` (posición 2, tras la regla ESTABLISHED; backup `apply.sh.bkup-20261022-proxy`). El servicio `docker-cf-firewall.service` re-aplica al boot. **Sin esta regla el proxy es inaccesible desde internet** (el DROP final del hardening CF-only lo mata).
- Logs docker: json-file max-size 10m × 3 por contenedor.

## Monitoreo

- Tráfico por usuario: `docker exec proxy-squid tail -50 /var/log/squid/access.log` (volumen persistente `proxy-stack_squid-logs`)
- Uso 24h: `docker exec proxy-squid awk -v cutoff=$(($(date +%s)-86400)) '$1 > cutoff' /var/log/squid/access.log | wc -l`
- Socks5: `docker logs proxy-socks5 --tail 50`
- **Rotación de access.log** (2026-10-22): `logfile_rotate 10` en squid.conf + cron root del VPS `0 4 * * 0 docker exec proxy-squid /usr/sbin/squid -k rotate` (domingos 04:00, 10 generaciones ≈ 10 semanas). Cambios de config en caliente: `docker exec proxy-squid /usr/sbin/squid -k reconfigure` (sin downtime).

## fail2ban jail squid (2026-10-22)

- Filter `/etc/fail2ban/filter.d/squid.conf`: `failregex = ^\s*\d+\s+<HOST>\s+TCP_DENIED/407\s` + `datepattern = {^LN-BEG}EPOCH` (el timestamp epoch se consume ANTES del failregex — por eso el regex empieza en el campo elapsed). Solo 407 (auth mala); los 403 son el filtro de contenido, NO brute force.
- Jail `/etc/fail2ban/jail.d/squid.local`: **`backend = auto` OBLIGATORIO** (el default systemd de Ubuntu 24.04 ignora logpath y monitorea el journal — sin esto el jail no cuenta nada), logpath = volumen docker, `ignoreip = 127.0.0.1/8 172.20.0.0/16` (evita self-lockout del host), maxretry 5 / findtime 10m / bantime 2h.
- **`action = iptables-allports[... chain=FORWARD]`**: la coma en `port=3128,1080` ROMPE el parser de acciones ("unexpected option syntax") — por eso allports. chain=FORWARD (no INPUT ni DOCKER-USER): el tráfico a puertos docker publicados va por FORWARD tras el DNAT, y FORWARD sobrevive los flushes de DOCKER-USER de apply.sh.
- IPs reales de clientes preservadas en el log (el DNAT mantiene la source; solo el tráfico del host aparece como 172.20.0.1).
- Validado end-to-end 2026-10-22: filtro 13/13 líneas 407, ban real verificado (REJECT en f2b-squid hook FORWARD pos.1), unban OK.

## Reglas de operación

1. **NUNCA** activar `proxied:true` en los registros DNS del proxy
2. **NUNCA** mostrar contraseñas de usuarios en el chat
3. **NUNCA** setear env vars de proxy en el sistema/contenedores del VPS (servicio PARA CLIENTES)
4. **Siempre** verificar que el proxy funciona después de cambios (curl via proxy con auth)
5. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio
6. **Backup** de configs antes de modificar (`.bkup-YYYYMMDD`)
7. Tras editar squid.conf/users/filtros: `docker compose up -d --force-recreate` (montados :ro)

## Docs oficiales (2026-10-08 — directiva del owner: programar segun estandares de los creadores)
> Regla: ANTES de programar/configurar el proxy, consultar estas fuentes. Si no cubren el caso, verificar contra el LIVE. NUNCA inventar directivas squid ni tocar la politica de filtros sin el owner.
- **Squid** (usuarios, filtros de contenido, rate limiting, filedescriptors): http://www.squid-cache.org/Doc/
- **SOCKS5** (protocolo del servicio): https://www.rfc-editor.org/rfc/rfc1928
- **Docker Compose** (stack): https://docs.docker.com/compose/

## Upstream (2026-10-22)

- **Fuente**: vps-preprod /opt/proxy-stack (Squid :3128 + SOCKS5 :1080 dockerizados); origen histórico vps-proxy (misma instalación desde siempre, configs migradas fieles, **servidor desactivado 2026-10-22**).
- **Vivo**: migrado y validado 2026-10-22 (auth OK ambos usuarios, filtros 403, socks5 200, FD 65536, DNS cutover, 8 dominios VPS + IRC intactos).
- **Check**: `ssh vps-preprod "cd /opt/proxy-stack && docker compose ps" && curl -x http://admin:***@proxy.us-east.armada.do:3128 -so /dev/null -w "%{http_code}" --max-time 15 https://www.google.com`
- **Regla**: LIVE manda (doc vs live vs upstream); propone updates al owner, nunca auto-actualiza produccion sin autorizacion.

```json upstream_drk
{
  "enabled": true,
  "id": "Proxy",
  "label": "dockerized squid vps-preprod (hijo)",
  "source": "manual squid-cache.org + docs.docker.com",
  "href": "manual squid-cache.org",
  "href_docs": "https://www.squid-cache.org",
  "pin_note": "",
  "groom_clean": true
}
```

> **Harness**: `~/armada-sync/harness/proxy.harness.json` (scope + live_check + upstream + docs + changelog de este agente).
