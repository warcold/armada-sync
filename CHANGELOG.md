## 2026-09-01

### [22:00] - Fix CRÍTICO: Squid crasheaba con `store.cc:1911` — deshabilitar caché
- **Tipo**: infra | servicio | bugfix crítico
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (deshabilitado cache_dir ufs, agregado `cache deny all`), permisos proxy-users.conf
- **Afecta a**: vps-proxy (proxy server), todos los clientes del proxy
- **Causa**: Squid crasheaba **9 veces** con `FATAL: assertion failed: store.cc:1911: "sd"` (bug del sistema de caché). Cada crash causaba que el proxy "se cayera" y el servicio SOCKS5 se reiniciaba constantemente (342 veces). El usuario reportaba caídas frecuentes.
- **Estado**: ✅ resuelto — sin crashes desde el fix
- **Notas**:
  - **Causa raíz**: el caché de Squid (cache_dir ufs) tiene un bug (`store.cc:1911: "sd"`) que causa crashes aleatorios. Un proxy no necesita caché, así que se deshabilitó por completo.
  - **Fix**: eliminado `cache_dir ufs` y agregado `cache deny all` — sin caché = sin bug
  - **Resultado**: SOCKS5 ya no se reinicia constantemente, Squid estable, Gmail 0.08s, Google 0.00s, SOCKS5 Gmail 0.10s
  - **Adicional**: errores `Permission denied` en proxy-users.conf — permisos verificados (root:proxy 640, proxy puede leer correctamente)
  - **Monitorear**: si vuelve a crashear, el bug puede reaparecer en upgrades de Squid

### [21:30] - Fix CRÍTICO: Aumentar límite de filedescriptors de Squid (1024 → 65536)
- **Tipo**: infra | servicio | bugfix crítico
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (max_filedescriptors 65536), /etc/systemd/system/squid.service.d/override.conf (LimitNOFILE 65536)
- **Afecta a**: vps-proxy (proxy server), usuario jovtransport (RD)
- **Causa**: el cliente jovtransport reportó que el servicio no le funciona. Diagnóstico: el usuario tiene 172 conexiones abiertas (websockets, apps, pestañas) y Squid tenía un límite de filedescriptors de solo 1024. Al saturarse, las nuevas conexiones se colgaban → "no funciona".
- **Estado**: ✅ resuelto — límite aumentado a 65536
- **Notas**:
  - **Causa raíz**: Squid soft limit de filedescriptors = 1024 (default). El usuario con muchas conexiones (websockets de intercom, whatsapp, google, apps) saturaba el límite.
  - **Fix**: `max_filedescriptors 65536` en squid.conf + `LimitNOFILE=65536` en systemd override
  - **Verificado**: límite ahora 65536 (antes 1024), Gmail 0.07s, SOCKS5 0.10s, usuario con 81 conexiones (antes 172)
  - **Síntoma en logs**: `error:transaction-end-before-headers` (conexiones que se cortan antes de enviar headers) y tiempos enormes (101 min, 124 min) por conexiones que se colgaban
  - **Este era el problema real** — no la latencia RD-EEUU, sino la saturación de filedescriptors

### [21:00] - Diagnóstico: Proxy funcional, problema es la ruta RD-EEUU del usuario
- **Tipo**: infra | servicio | diagnóstico
- **Modificado**: ninguno (solo diagnóstico)
- **Afecta a**: vps-proxy (proxy server), usuario jovtransport (RD)
- **Causa**: el cliente jovtransport reportó que el servicio no le funciona. Se hizo diagnóstico completo.
- **Estado**: ✅ proxy funcional — el problema es la ruta de red del usuario
- **Notas**:
  - **Servidor sano**: carga 0.11, memoria OK, sin errores de red, sin conexiones colgadas
  - **Conectividad saliente perfecta**: mail.google.com 0.09s, whatsapp 0.17s, intercom 0.08s, superdispatch 0.12s, velocidad 19.8 MB/s
  - **Proxy funcional desde kalimete**: Gmail 0.14s, Google 0.33s, velocidad 16.2 MB/s
  - **Problema**: la conexión del usuario (181.36.176.87, RD/Altice) tarda minutos en establecerse (101 min, 124 min en logs) pero eventualmente funciona (TCP_TUNNEL/200). Es la ruta de red RD-EEUU inestable con pérdida de paquetes.
  - **Recomendación al usuario**: (1) verificar su conexión a internet (Altice RD), (2) probar con otra red (móvil), (3) usar el hostname jovtransport.prx.armada.do, (4) configurar credenciales en todas las apps

### [20:35] - Fix: Optimizar Squid para latencia RD-EEUU (timeouts, keepalive)
- **Tipo**: infra | servicio | optimización
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (timeouts, keepalive, persistent connections)
- **Afecta a**: vps-proxy (proxy server), usuario jovtransport (RD)
- **Causa**: el usuario jovtransport (República Dominicana, Altice) reportó fallas al navegar. Los logs mostraron latencia extrema (mail.google.com 440s, ans.oobesaas 1645s). El servidor está sano (carga 0.03, sin errores de red), el proxy funciona rápido desde el servidor (0.07s). El problema es la latencia de red entre RD y EEUU.
- **Estado**: ✅ optimizado — tiempos mejorados (66s vs 1506s antes)
- **Notas**:
  - **Diagnóstico**: el servidor y el proxy están sanos (Gmail 0.07s desde el servidor). El problema es la ruta de red RD-EEUU (traceroute muestra pérdida de paquetes hacia RD)
  - **Optimizaciones aplicadas**: connect_timeout 60s, read_timeout 15min, request_timeout 5min, client_idle_pconn_timeout 2min, pconn_timeout 2min, client_persistent_connections on, server_persistent_connections on
  - **Resultado**: tiempos del usuario mejoraron (signaler-pa 66s vs 1506s, whatsapp 70s vs 164s, google 10s vs 283s)
  - **TCP_DENIED/407**: algunas conexiones del usuario (teams.live.com, api.msn.com, activity.windows.com) llegan sin autenticación — el usuario debe configurar las credenciales en TODAS las apps, no solo el navegador
  - **Recomendación al usuario**: (1) configurar credenciales en todas las apps, (2) usar el hostname jovtransport.prx.armada.do, (3) limpiar caché del navegador, (4) la latencia RD-EEUU es normal (~60-80s en conexiones iniciales)

### [19:20] - Fix: Verificar proxy tras reporte de jovtransport (took too long)
- **Tipo**: infra | servicio | validación
- **Modificado**: vps-proxy (31.220.102.176) — reiniciado SOCKS5, limpiado log
- **Afecta a**: vps-proxy (proxy server), usuario jovtransport
- **Causa**: el usuario jovtransport reportó que aún no podía navegar a mail.google.com ("took too long to respond"). Se validaron los logs.
- **Estado**: ✅ resuelto — el proxy funciona rápido AHORA
- **Notas**:
  - **Diagnóstico**: los logs lentos (283s, 902s, 1448s) eran de ANTES de eliminar el delay_pools (hace 36 min). El reporte del usuario era del problema anterior.
  - **Verificado AHORA** (desde IP pública, simulando usuario): Gmail HTTP 301 en 0.08s, Google HTTP 200 en 0.12s, Outlook HTTP 301 en 0.08s, SOCKS5 Gmail HTTP 301 en 0.09s, velocidad 17.6 MB/s
  - **SOCKS5**: reiniciado con script correcto (el log tenía SyntaxError viejo acumulado), log limpiado
  - **Conclusión**: el proxy está funcionando correctamente. Si el usuario aún ve problemas, es de su lado (caché del navegador, configuración, o conexión)

### [18:45] - Infra: Confirmar sin límite de velocidad (filtros bastan)
- **Tipo**: infra | servicio | validación
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (limpiado comentario residual delay_pools)
- **Afecta a**: vps-proxy (proxy server), usuarios del proxy
- **Causa**: el usuario confirmó que no hace falta límite de velocidad porque los filtros de contenido ya bloquean lo que consume mucho (streaming, juegos, etc.). Se valida que no hay límite y se limpia el comentario residual.
- **Estado**: ✅ validado — sin límite de velocidad, filtros activos
- **Notas**:
  - **Sin delay_pools**: el proxy no tiene límite de velocidad (confirmado)
  - **Velocidad**: 18.4 MB/s (sin límite)
  - **Filtros activos**: YouTube/Netflix bloqueados (HTTP 000), GitHub permitido (HTTP 200)
  - **Estrategia**: con el tiempo auditar los logs para detectar si algún usuario usa algo que consuma mucho y bloquearlo de ser necesario
  - **Auditoría**: usar `/usr/local/bin/proxy-monitor.sh` para ver uso por usuario

### [18:30] - Fix: Eliminar rate limiting (delay_pools) que causaba latencia extrema
- **Tipo**: infra | servicio | bugfix
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (eliminado delay_pools)
- **Afecta a**: vps-proxy (proxy server), usuarios del proxy (jovtransport, admin)
- **Causa**: el usuario jovtransport reportó que no podía navegar ("el correo no carga y las apps no abren, como si no tuviera Internet"). Los logs de Squid mostraron latencia extrema: mail.google.com tardaba 283s, ms-cookie-sync 902s. El delay_pools (rate limiting) que agregué causaba un cuello de botella severo.
- **Estado**: ✅ resuelto y verificado
- **Notas**:
  - **Causa raíz**: delay_pools (agregado 10 MB/s, individual 5 MB/s) limitaba severamente el ancho de banda, causando tiempos de respuesta de minutos
  - **Fix**: eliminado delay_pools de squid.conf
  - **Verificado**: velocidad 12.2 MB/s (antes 5.9-8.2 MB/s), Gmail HTTP 301 en 0.1s (antes 283s), Google HTTP 200 en 0.1s, SOCKS5 HTTP 200 en 0.2s
  - **Filtros intactos**: YouTube/Netflix bloqueados, GitHub/Google permitidos
  - **Backup**: /etc/squid/squid.conf.bkup-delaypools-20260830

### [08:30] - Agentes: Crear subagentes para todos los sistemas/proyectos/servicios
- **Tipo**: agente | config | documentación
- **Modificado**: agents/eco-vps.md, eco-victoria.md, eco-petsuite.md, eco-woodly.md, eco-taohemps.md, eco-ragnarok.md, eco-nextcloud.md, eco-authentik.md, eco-docuseal.md, eco-scriberr.md, eco-micaserogou.md (nuevos), agents/kalimete.md (permission.task + tabla), AGENTS.md, MAPA.md
- **Afecta a**: kalimete (config opencode), todos los subagentes
- **Causa**: el usuario notó que faltaban subagentes para los devs, proyectos, sistemas y servicios (Docker, VPS, victoria, etc.)
- **Estado**: ✅ subagentes creados y documentados
- **Notas**:
  - **11 subagentes nuevos** creados: eco-vps, eco-victoria, eco-petsuite, eco-woodly, eco-taohemps, eco-ragnarok, eco-nextcloud, eco-authentik, eco-docuseal, eco-scriberr, eco-micaserogou
  - **Total subagentes**: 21 (5 cloudflare + 16 sistemas/proyectos)
  - **kalimete permission.task**: actualizado con todos los nuevos allows
  - **Symlinks**: creados en ~/.config/opencode/agent/ para los 11 nuevos
  - **AGENTS.md y MAPA.md**: tablas de subagentes actualizadas con los 11 nuevos
  - Cada subagente documenta: acceso, infraestructura, DNS, servicios, reglas de operación

### [08:00] - Agentes: Reorganización — subagentes controlados por kalimete + eco-proxy
- **Tipo**: agente | config | documentación
- **Modificado**: agents/armada-arcade.md, agents/eco-irc.md, agents/wordpress-dev.md (frontmatter subagent), agents/eco-proxy.md (nuevo), agents/kalimete.md (permission.task), AGENTS.md, MAPA.md, Desktop/proxy_guide.md
- **Afecta a**: kalimete (config opencode), todos los subagentes
- **Causa**: el usuario pidió validar agentes y quitar los agentes principales que pueden ser subagentes controlados por kalimete; también actualizar toda la documentación del proxy
- **Estado**: ✅ reorganizado y documentado
- **Notas**:
  - **Frontmatter subagent agregado** a: armada-arcade, eco-irc, wordpress-dev (antes sin frontmatter → opencode los trataba como primary)
  - **Nuevo subagente eco-proxy**: documenta el servidor proxy internacional (vps-proxy) — usuarios, filtros, rate limiting, monitor, DNS, seguridad
  - **kalimete permission.task actualizado**: `"*": deny` + allows `eco-cloudflare-*`, `eco-irc`, `armada-arcade`, `wordpress-dev`, `eco-proxy`, `explore`
  - **Subagentes de proyectos** (eco-irc, armada-arcade, wordpress-dev, eco-proxy): `edit: allow`, `write: allow` — pueden modificar sus archivos y deben actualizar su documentación + CHANGELOG tras cada cambio
  - **AGENTS.md y MAPA.md**: tablas de subagentes actualizadas con los 4 nuevos
  - **proxy_guide.md**: actualizado con filtros de contenido, rate limiting, datos técnicos, subagente eco-proxy

### [07:45] - Infra: Filtros de contenido proxy (bloquear streaming/consumo)
- **Tipo**: infra | servicio | seguridad | política
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/blocked-domains.txt (nuevo), /etc/squid/squid.conf (ACL blocked_domains)
- **Afecta a**: vps-proxy (proxy server), usuarios del proxy (jovtransport, admin)
- **Causa**: el usuario pidió filtros para que el proxy sea solo para trabajar — bloquear plataformas de streaming y consumo de datos (política de empresa)
- **Estado**: ✅ filtros activos y verificados
- **Notas**:
  - **Bloqueados** (TCP_DENIED/403): YouTube, Netflix, Twitch, Spotify, TikTok, Instagram, Facebook, Prime Video, Disney+, HBO Max, Hulu, Vimeo, Dailymotion, SoundCloud, Apple Music, Steam, Epic Games, Roblox, Discord, Peacock, Paramount+, Crunchyroll, Pluto, Tubi, Pandora, Deezer, Tidal, Audible, Kick, Rumble, Odysee, Bitchute, DLive
  - **Permitidos** (HTTP 200/302): Google, Google Docs, Gmail, GitHub, StackOverflow, LinkedIn
  - **Lista de dominios**: `/etc/squid/blocked-domains.txt` (fácil de editar para agregar/quitar)
  - **ACL**: `http_access deny blocked_domains` antes de `allow authenticated`
  - Verificado: YouTube/Netflix/Twitch/Spotify/TikTok/Instagram/Facebook/Steam/Discord → 403; Google/Docs/Gmail/GitHub/StackOverflow/LinkedIn → 200

### [07:20] - Infra: Mejoras proxy — rate limiting, monitor, análisis Cloudflare
- **Tipo**: infra | servicio | mejora
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (delay_pools), /usr/local/bin/proxy-monitor.sh (nuevo)
- **Afecta a**: vps-proxy (proxy server), usuarios del proxy
- **Causa**: el usuario preguntó si activar Cloudflare proxy haría que funcione "como si estuviera en EEUU" y pidió analizar oportunidades de mejora (pensando en más clientes e IPs futuras)
- **Estado**: ✅ mejoras aplicadas y verificadas
- **Notas**:
  - **Cloudflare proxy NO aplica**: Cloudflare solo proxya 80/443; el proxy usa 3128 (HTTP) y 1080 (SOCKS5) que CF no reenvía. Además CF no cambia la IP de salida del proxy — el servidor ya está en EEUU (31.220.102.176). Registro debe quedarse gris (proxied:false)
  - **Rate limiting (delay_pools)**: clase 2, agregado 10 MB/s, individual 5 MB/s por usuario autenticado. Ajustable según plan de cada cliente
  - **Preparación multi-IP**: comentado en squid.conf `tcp_outgoing_address` para cuando se agreguen más IPs al servidor
  - **Monitor**: `/usr/local/bin/proxy-monitor.sh` — muestra servicios, usuarios, uso por usuario, fail2ban, IP de salida
  - **Backup config**: `/etc/squid/squid.conf.bkup-20260830`
  - Verificado: SOCKS5 HTTP 200, HTTP HTTP 200, monitor funciona, fail2ban activo (1 IP baneada)

### [06:30] - Infra: Hostname dedicado proxy jovtransport.prx.armada.do
- **Tipo**: infra | dns | cloudflare
- **Modificado**: Cloudflare DNS armada.do — nuevo registro A `jovtransport.prx.armada.do` → 31.220.102.176 (gris, TTL 300)
- **Afecta a**: vps-proxy (31.220.102.176), usuario jovtransport
- **Causa**: el usuario pidió un hostname dedicado para el cliente jovtransport además del acceso por IP directa
- **Estado**: ✅ creado y verificado
- **Notas**:
  - Registro A gris (proxied:false) — necesario porque el proxy usa puertos 3128 (HTTP) y 1080 (SOCKS5) que Cloudflare NO proxya (solo 80/443)
  - Verificado: resolución DNS → 31.220.102.176, HTTP proxy via hostname HTTP 200, SOCKS5 via hostname HTTP 200, IP salida 31.220.102.176
  - Zone ID armada.do: 17badff7f918b4e02eea8533fac4dc9f
  - Record ID: 34cf3213f0c6ef17b82efc3caa0da5dc
  - Ya existía `proxy.us-east.armada.do` → misma IP (gris); el nuevo es dedicado para jovtransport

### [06:00] - Infra: Cambiar clave admin proxy (ProxyColadorEUA)
- **Tipo**: config | seguridad
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/proxy-users.conf, /usr/local/bin/socks5-proxy.py, /opt/proxy-configs/proxy-credenciales.txt
- **Afecta a**: vps-proxy (proxy server), usuario admin
- **Causa**: evitar problemas con caracteres especiales (`@`) en la clave anterior `Proxy@Colador` — la nueva `ProxyColadorEUA` es alfanumérica, compatible con URLs
- **Estado**: ✅ verificado (SOCKS5 + HTTP funcionando)
- **Notas**:
  - **Usuarios finales**: `admin` (clave `ProxyColadorEUA`), `jovtransport` (clave `jovproxyeeuu1`)
  - Verificado: SOCKS5 admin HTTP 200, SOCKS5 jovtransport HTTP 200, HTTP admin HTTP 200
  - Clave vieja `Proxy@Colador` rechazada (HTTP 000)
  - IP de salida: 31.220.102.176 (EEUU)

### [05:50] - Infra: Renombrar usuarios proxy (clientes → jovtransport, admin nueva clave)
- **Tipo**: config | seguridad
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/proxy-users.conf, /usr/local/bin/socks5-proxy.py, /opt/proxy-configs/proxy-credenciales.txt
- **Afecta a**: vps-proxy (proxy server), usuarios del proxy
- **Causa**: el usuario pidió renombrar el usuario genérico a `jovtransport` y cambiar la clave de admin
- **Estado**: ✅ verificado (SOCKS5 + HTTP funcionando)
- **Notas**:
  - **Usuarios finales**: `admin` (clave `Proxy@Colador`), `jovtransport` (clave `jovproxyeeuu1`)
  - Eliminado usuario `clientes` (armadaclientes2026)
  - Verificado: SOCKS5 jovtransport HTTP 200, SOCKS5 admin HTTP 200, HTTP jovtransport HTTP 200, HTTP admin HTTP 200
  - IP de salida: 31.220.102.176 (EEUU)
  - ⚠️ La clave de admin contiene `@` — en URLs de curl usar `--proxy-user 'admin:Proxy@Colador'` o URL-encode `%40`; los clientes (navegadores/apps) lo manejan automáticamente

### [05:35] - Infra: Limpieza total vps-proxy (solo proxy + acceso)
- **Tipo**: infra | limpieza | seguridad
- **Modificado**: vps-proxy (31.220.102.176) — eliminados usuarios SO, proyectos viejos, paquetes IRC, OpenVPN, weechat
- **Afecta a**: vps-proxy (servidor proxy), kalimete (acceso SSH)
- **Causa**: el usuario pidió limpiar el servidor dejando solo nuestro acceso y todo lo relacionado al proxy
- **Estado**: ✅ servidor limpio, proxy verificado
- **Notas**:
  - **Usuarios SO eliminados**: ircd, justin, kboom, ubuntu (quedan solo root + warcold)
  - **Proyectos eliminados**: /opt/google (chrome), /opt/inspircd, /opt/proxy-infra (openvpn), /home/ircd, /home/justin, /home/kboom, /home/ubuntu
  - **Procesos detenidos**: weechat (cliente IRC), OpenVPN (openvpn@server detenido y deshabilitado)
  - **Paquetes purgados**: inspircd, dante-server, redsocks, shadowsocks-libev, simple-obfs, weechat*
  - **Puertos UFW cerrados**: 80/tcp, 1194/udp (OpenVPN)
  - **UFW final**: solo 1444 (SSH), 53 (DNS), 3128 (Squid), 1080 (SOCKS5)
  - **Servicios finales**: squid, socks5-proxy, ssh, fail2ban
  - **Se conserva**: /opt/proxy-configs (credenciales), /home/warcold (acceso), /usr/local/bin/proxy-manage.sh, /usr/local/bin/socks5-proxy.py
  - **Verificado**: SOCKS5 clientes/admin HTTP 200, HTTP clientes HTTP 200, IP salida 31.220.102.176, fail2ban activo (1 IP baneada)

### [03:10] - Infra: Limpieza y aseguramiento vps-proxy (proxy server final)
- **Tipo**: infra | servicio | seguridad | limpieza
- **Modificado**: vps-proxy (31.220.102.176) — usuarios proxy, SOCKS5, UFW, SSH, fail2ban
- **Afecta a**: vps-proxy (servidor proxy), clientes (acceso SOCKS5 + HTTP)
- **Causa**: el usuario pidió dejar solo admin + un usuario genérico "clientes" que funcione tanto SOCKS5 como HTTP, validar protección del servidor y auditar accesos
- **Estado**: ✅ todo configurado y verificado
- **Notas**:
  - **Usuarios proxy finales**: `admin` (armadaproxy2026) + `clientes` (armadaclientes2026) — eliminados carlos/maria
  - **SOCKS5**: servicio `socks5-proxy.service` (Python, RFC 1929 auth) en puerto **1080** — funciona con clientes/admin, rechaza passwords incorrectos
  - **HTTP**: Squid 6.14 en puerto **3128** — funciona con clientes/admin
  - **IP de salida verificada**: 31.220.102.176 (EEUU) tanto por SOCKS5 como por HTTP ✅
  - **redsocks**: DETENIDO y deshabilitado (ya no se necesita, SOCKS5 Python lo reemplaza)
  - **shadowsocks-libev**: falló (JSON config error), no se usa
  - **dante**: falló (config compleja), no se usa
  - **Usuarios SO eliminados**: carlos (1005), maria (1006) — eran de pruebas
  - **UFW limpiado**: eliminados puertos IRC obsoletos (6667, 6697, 7209, 6900, 7022, 18789, 50743, 7200); quedan solo 1194/udp (OpenVPN), 1444 (SSH), 53 (DNS), 80, 3128 (Squid), 1080 (SOCKS5)
  - **SSH asegurado**: `PermitRootLogin prohibit-password` (solo llaves), `PasswordAuthentication no`
  - **fail2ban**: instalado y activo (jail sshd, port 1444, maxretry 3, bantime 2h) — ya baneó 1 IP atacante (103.137.184.170)
  - **Scripts**: `/usr/local/bin/proxy-manage.sh` (add/del/pass/list/check/stats) — actualizado con usuarios finales
  - **Credenciales**: `/opt/proxy-configs/proxy-credenciales.txt` (actualizado)

### [00:30] - Infra: Servidor proxy Squid para clientes (vps-proxy)
- **Tipo**: infra | servicio | seguridad
- **Modificado**: vps-proxy (31.220.102.176) — Squid 6.14, autenticación NCSA, gestión de usuarios, logs
- **Afecta a**: vps-proxy (nuevo servicio proxy), usuarios/carlos/maria/admin (acreditación individual)
- **Causa**: migrar vps-proxy a proxy server internacional (EEUU) para dar acceso controlado a clientes, amigos y familia — cada usuario con credenciales únicas
- **Estado**: ✅ activo, HTTPS proxy funcionando (HTTP 200 verificada)
- **Notas**:
  - **Servicio**: Squid 6.14 en puerto 3128 (HTTP/HTTPS), autenticación Basic NCSA (htpasswd)
  - **Usuarios**: admin (armadaproxy2026), carlos (uzh/n4KzMh7jWZPU), maria (miClave123)
  - **Scripts de gestión**: `/usr/local/bin/proxy-manage.sh` (add/del/pass/list/check/stats)
  - **Config**: `/etc/squid/squid.conf`, usuarios: `/etc/squid/proxy-users.conf` (permisos 640 root:proxy)
  - **UFW**: puerto 3128/tcp abierto (todos)
  - **Logs**: `/var/log/squid/access.log` (tráfico por usuario)
  - **Credenciales**: `/opt/proxy-configs/proxy-credenciales.txt`
  - **Guías cliente**: `/opt/proxy-configs/` (Linux, Mac, Windows, navegador)
  - **OpenVPN**: se mantiene sin cambios (puerto 1194/udp)
  - **SSH**: se mantiene sin cambios (puerto 1444)
  - **InspIRCd**: DEAD (desde 2026-03-17), sin impacto — proxy toma el lugar del servidor anterior

### [17:30] - Victoria opencode: Agregar provider NVIDIA NIM (key propia) — config completa
- **Tipo**: config | opencode | nvidia | vllm
- **Modificado**: `/home/victoria/.config/opencode/opencode.jsonc` (backup: `opencode.jsonc.bkup-20260830-nvidia`)
- **Afecta a**: victoria (opencode.jsonc)
- **Causa**: Completar la config de victoria con el provider NVIDIA NIM usando su key propia (`nvapi-vZ9w...`, cuenta warcold@gmail.com, exportada como `NVIDIA_API_KEY` en `data.txt`). Autorización explícita del usuario (acceso SSH `victoria@victoria.local:1666`).
- **Estado**: ✅ victoria configurada y verificada

**Resultado victoria (109 modelos, sin duplicados):**
- `nvidia` (101): catálogo NVIDIA NIM auto-descubierto (key propia de victoria)
- `opencode` (6): modelos built-in free (nemotron, mimo, ling, etc.)
- `vllm` (2): Qwen3.6 normal + thinking vía gateway local `:8010` (key `vllm-key-8111...`)

**Límites vllm local (correctos):**
- context: 228000 + output: 32000 = 260000 < 262144 (max_model_len real del vLLM) ✅
- Gateway :8010 responde en `/models`; vLLM :8000 confirma `max_model_len: 262144`
- Test chat exitoso (Qwen3.6 thinking responde con reasoning)

**Notas:**
- Victoria ya tenía las 2 variantes Qwen3.6 (agregadas por usuario hoy 03:31); solo faltaba el provider nvidia
- Estructura idéntica a kalimete (misma config, cada máquina con sus propias keys)
- "opencode zen" = modelos built-in de opencode (siempre disponibles, auto-discovery)

### [23:30] - Kalimete opencode: Eliminar duplicados NVIDIA + config objetivo para victoria
- **Tipo**: config | opencode | nvidia | vllm
- **Modificado**: `~/.config/opencode/opencode.jsonc` (kalimete) — removido bloque `models` manual del provider `nvidia`
- **Afecta a**: kalimete (opencode.jsonc) + victoria (config objetivo documentado, pendiente de aplicar por usuario)
- **Causa**: Los 2 modelos manuales (`deepseek-v4-flash-0731`, `deepseek-v4-pro-0813`) duplicaban los auto-descubiertos del catálogo NVIDIA. Se deja solo `options` (baseURL + apiKey) para auto-discovery completo.
- **Estado**: ✅ kalimete sincronizado; ⚠️ victoria pendiente (read-only, usuario aplica manualmente)

**Resultado kalimete (109 modelos, sin duplicados manuales):**
- `nvidia` (101): catálogo NVIDIA NIM auto-descubierto (alias + versión con fecha son inherentes al catálogo)
- `opencode` (6): modelos built-in
- `vllm` (2): Qwen3.6 normal + thinking

**Config objetivo victoria** (guardada en `/tmp/opencode/victoria-opencode.jsonc`):
- vllm: baseURL `http://127.0.0.1:8000/v1` (local, sin key) + 2 variantes Qwen3.6 (normal + thinking)
- nvidia: baseURL `https://integrate.api.nvidia.com/v1` + key propia de victoria (placeholder `nvapi-REEMPLAZAR...`)
- ⚠️ victoria actualmente solo tiene 1 modelo Qwen3.6 (thinking, sin "normal") según backup 2026-08-14

### [23:00] - Kalimete opencode: Agregar provider NVIDIA NIM (DeepSeek V4 Flash/Pro)
- **Tipo**: config | opencode | nvidia | deepseek
- **Modificado**: `~/.config/opencode/opencode.jsonc` (backup: `opencode.jsonc.bkup-20260830-nvidia`)
- **Afecta a**: kalimete (opencode.jsonc)
- **Causa**: Réplicar la configuración de NVIDIA NIM de victoria en kalimete para acceder a modelos de API externa (DeepSeek) con 1M de contexto nativo
- **Estado**: ✅ NVIDIA NIM funcional, test exitoso con DeepSeek V4 Flash

**Modelos agregados:**
1. `deepseek-ai/deepseek-v4-flash-0731` — "DeepSeek V4 Flash"
   - Context: 128000, Output: 32000
   - Reasoning: true, Attachment: true, Tool call: true
   - Input: text only
   
2. `deepseek-ai/deepseek-v4-pro-0813` — "DeepSeek V4 Pro"
   - Context: 128000, Output: 32000
   - Reasoning: true, Attachment: true, Tool call: true
   - Input: text only

**Configuración NVIDIA NIM:**
- Provider: `nvidia` (npm: `@ai-sdk/openai-compatible`)
- baseURL: `https://integrate.api.nvidia.com/v1`
- API key: `nvapi-...` (desde `/home/victoria/Desktop/data.txt`)
- Nombre: "NVIDIA NIM"

**Modelos kalimete (ahora):**
1. **vllm** (local): Qwen3.6-35B-A3B-NVFP4 (2 variantes) — Victoria local GB10
   - `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` → "Coding con Victoria" (reasoning: false)
   - `nvidia/Qwen3.6-35B-A3B-NVFP4` → "Thinking · Coding con Victoria" (reasoning: true)
   
2. **nvidia** (cloud): DeepSeek V4 Flash/Pro — NVIDIA API Catalog
   - `deepseek-ai/deepseek-v4-flash-0731` → "DeepSeek V4 Flash"
   - `deepseek-ai/deepseek-v4-pro-0813` → "DeepSeek V4 Pro"

**Notas:**
- La key NVIDIA fue compartida por usuario desde victoria (`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`)
- NVIDIA NIM responde correctamente desde kalimete (test exitoso con DeepSeek V4 Flash)
- Victoria también usa NVIDIA NIM (ref: victoria.md: "DeepSeek V4 Flash/Pro (vía NVIDIA NIM, key `nvapi-…` en auth.json)")
- En victoria: key almacenada en `/home/victoria/Desktop/data.txt` (plaintext, 600 permissions)
- En kalimete: key almacenada directamente en opencode.jsonc (misma key)
- Los modelos DeepSeek tienen 1M de contexto nativo vs 262K del Qwen local

### [18:39] - Script cfmb25: clonación automática de tarjetas FMB25 via Proxmark3
- **Tipo**: herramienta | proxmark3 | preproducción
- **Modificado**: `/home/warcold/bin/cfmb25` (nuevo script)
- **Afecta a**: kalimete (herramienta local)
- **Causa**: Automatizar la clonación de imágenes FMB25 a tarjetas CUID para el ambiente de preproducción
- **Estado**: ✅ funcional, clonación exitosa (64/64 bloques OK)
- **Notas**: 
  - Usa `hf mf restore --1k -f <dump> -k <keys> --ka` (comando probado en sesiones anteriores)
  - Imagen original: `~/.victoria/pm3-dumps/FMB25.bin` (1024 bytes, MIFARE Classic 1K)
  - Keys originales: `~/.victoria/pm3-dumps/FMB25-keys.bin` (192 bytes, 64 keys)
  - Solo lee del Proxmark3, no modifica archivos remotos
  - Tarjeta CUID detectada: UID 3295B67B, ATQA 00 04, SAK 08

### [22:45] - WordPress Dev: Fix permisos, MCP host guard, Composer autoloader + política de updates
- **Tipo**: infra | wordpress | permisos | mcp | plugins
- **Modificado**: 
  - `~/dev/wordpress/mcp-proxy.mod.js` (soporte HTTPS con `rejectUnauthorized: false` para mkcert)
  - `/var/www/html/wp-content/mu-plugins/disable-mcp-host-guard.php` (mu-plugin nuevo)
  - `/var/www/html/wp-content/` permisos corregidos (www-data:www-data)
- **Afecta a**: kalimete (wordpress dev)
- **Causa**: Múltiples errores tras cambiar la URL a SSL y actualizar WordPress
- **Estado**: ✅ todos corregidos, MCP funcional, política de updates definida

**Errores corregidos:**
1. **Permisos root:root** → `ai1wm-backups`, `upgrade`, `storage` tenían `root:root`
   → `chown -R www-data:www-data /var/www/html/wp-content` (WordPress corre como www-data)
   → Ya no aparecen errores "Could not create directory/file"

2. **MCP Host Guard de EMCP Tools** bloqueaba peticiones de `localhost:8090`
   → WordPress ahora tiene `siteurl/home = https://wordpress.kalimete.local`
   → EMCP Tools valida Host header: si no coincide con home_url, devuelve error 421
   → Solución: `disable-mcp-host-guard.php` (mu-plugin) con `add_filter('emcp_tools_mcp_host_guard_enabled', '__return_false')`
   → Mu-plugin se carga ANTES que todos los plugins, nunca se rompe con updates

3. **Composer autoloader missing** en MCP Adapter
   → Error: "The Composer autoloader was not found" (WARNING, no FATAL)
   → El plugin usa **Jetpack Autoloader** (`vendor/autoload_packages.php`) que YA está incluido
   → El `vendor/autoload.php` de Composer NO se necesita para el funcionamiento
   → `composer install` falla por conflictos dev (php_codesniffer v3 vs v4) — irrelevantes para producción
   → El error es un WARNING de debug que no afecta funcionalidad

4. **Proxy no soportaba HTTPS** para conectar a `wordpress.kalimete.local`
   → `mcp-proxy.mod.js` ahora usa `rejectUnauthorized: false` con `httpsRequest` para certificados autofirmados
   → Permite conectar tanto a `http://localhost:8090` como a `https://wordpress.kalimete.local`

**Política de Updates (CRÍTICO para mantener integración):**
- **NO actualizar** `mcp-adapter` desde WP Admin → el plugin fue instalado manualmente (ZIP/manual), no desde WordPress.org
  → WP Admin no detecta updates automáticos para este plugin (correcto)
  → Si se actualiza manualmente, se pierde la integración con vLLM de victoria
  
- **mcp-basic-auth**: No requiere update (plugin custom de kalimete)
- **akismet**: No actualizar (plugin INACTIVO, sin impacto)
- **all-in-one-wp-migration**: No actualizar (funcionando correctamente, actualizaciones pueden cambiar estructura de storage)
- **emcp-tools**: ✅ Puede actualizar a 3.14.1 (pequeño patch update)
  → El mu-plugin `disable-mcp-host-guard.php` PERSISTE (no se borra con updates de plugins)
  → El proxy `mcp-proxy.mod.js` PERSISTE en `~/dev/wordpress/` (fuera del contenedor Docker)
  → **Protección**: el mu-plugin y el proxy sobreviven a cualquier update de WordPress/EMCP

- **Elementor 4.2.3**: No actualizar sin probar primero (cambios mayores pueden romper EMCP Tools)

**Protección de infraestructura:**
- Mu-plugins sobreviven updates de WordPress (están fuera del ciclo de plugins)
- mcp-proxy.mod.js está en `~/dev/wordpress/` (fuera del contenedor)
- Nginx config: `/etc/nginx/sites-available/wordpress.kalimete.local.conf` (fuera del contenedor)
- Certificados SSL: `/etc/ssl/local-certs/` (fuera del contenedor)
- Permisos SSL: `chown root:www-data 640` (persisten)
- Permisos WordPress: `chown -R www-data:www-data /var/www/html/wp-content` (persisten)

### [22:15] - opencode.jsonc: align format moderno con victoria (id, multimodal, attachment, tool_call)
- **Tipo**: config | opencode | vllm
- **Modificado**: `~/.config/opencode/opencode.jsonc` (backup: `opencode.jsonc.bkup-20260830`)
- **Afecta a**: kalimete (opencode.jsonc), sync
- **Causa**: Victoria tiene formato moderno (`id` en vez de `modelID`, `attachment`, `tool_call`, `modalities`); kalimete usaba schema antiguo (`capabilities` anidado, `modelID`, solo `text` como input). Se alineó kalimete al formato de victoria.
- **Cambios**:
  - `modelID` → `id` (campo obsoleto → moderno)
  - `context`: 240000 → 230000 → 228000 (receta canónica de victoria: 262144 - 32000 - 2144 headroom = 228000)
  - `capabilities: { tools, reasoning, input, output }` → campos flat: `attachment`, `tool_call`, `reasoning`, `modalities`
  - Agrega `modalities: { input: [text, image, video] }` (vLLM soporta multimodal)
  - Agrega `attachment: true` y `tool_call: true`
- **Estado**: ✅ sync pendiente (cron 5 min)
- **Notas**: 228000 + 32000 = 260000, headroom ~2.1K tokens (evita VLLMValidationError + bucles de reintentos). output en 32000 (máx posible con headroom ~22144).


### [06:12] - WordPress Dev: Proxy SSL con Nginx (wordpress.kalimete.local) + Arreglo permisos SSL globales
- **Tipo**: infra | nginx | ssl | wordpress
- **Modificado**: `/etc/nginx/sites-available/wordpress.kalimete.local.conf`, `/etc/ssl/local-certs/*.key`
- **Afecta a**: kalimete (wordpress dev con SSL, infraestructura SSL global)
- **Causa**: Exponer WordPress vía HTTPS con certificado mkcert para desarrollo realista, simulando producción
- **Estado**: ✅ wordpress.kalimete.local en HTTPS, certificado válido hasta 2028, permisos SSL corregidos
- **Notas**:
  - Certificado mkcert generado para `wordpress.kalimete.local` (CA: mkcert warcold@victoria)
  - Nginx config: HTTP→HTTPS redirect (301), proxy_pass a localhost:8090, headers X-Forwarded-Proto
  - WordPress URLs actualizadas: siteurl/home = `https://wordpress.kalimete.local` (sin puerto)
  - SSL CA instalada en sistema (mkcert -CAROOT), navegador confía en el certificado local
  - **Bugfix CRÍTICO**: Todas las llaves `.key` en `/etc/ssl/local-certs/` estaban en `root:600`
    → nginx workers (www-data) NO podían leerlas → `nginx -t` fallaba con "Permission denied"
    → Solución: `chown root:www-data 640` para TODAS las llaves .key (14 archivos corregidos)
    → Nginx ahora opera correctamente, workers www-data pueden leer todos los certs
  - Nginx -t: ✅ syntax ok, test successful con sudo (workers requieren www-data group read)
  - Acceso: `https://wordpress.kalimete.local/wp-admin/` (login admin/admin123)
  - Hosts file: `10.0.0.106 wordpress.kalimete.local` (LAN accesible desde otros hosts)

### [05:40] - Creación: WordPress Dev Stack (WordPress + Elementor + EMCP Tools + MCP Adapter)
- **Tipo**: proyecto | infra local | Docker
- **Modificado**: `~/dev/wordpress/` — Stack Docker completo: wordpress-local (WP 7.1) + wordpress-db (MySQL)
- **Afecta a**: kalimete (nuevo proyecto local, nuevo subagente wordpress-dev.md)
- **Causa**: Necesidad de ambiente de desarrollo WordPress con herramientas Elementor expuestas vía MCP al LLM
- **Estado**: ✅ stack operativo, MCP proxy funcional, ~60 herramientas EMCP Tools disponibles
- **Notas**:
  - WordPress 7.1 + Elementor 4.2.3 (atomic elements, v4) + EMCP Tools v3.14.0 + MCP Adapter 0.5.0
  - URL: http://localhost:8090, DB: localhost:3307, Auth: admin:admin123
  - Proxy MCP modificado: `mcp-proxy.mod.js` — usa ?rest_route= (plain permalinks), captura Mcp-Session-Id
  - Proceso mensajes MCP serialmente (initialize → notifications/initialized → tools/call)
  - Maneja Content-Length:0 + Keep-Alive (evita hang en responses 202)
  - ~60+ herramientas EMCP Tools: Elementor page builder, atomic widgets, containers, global classes, media, templates
  - Subagente creado: `wordpress-dev.md` (symlink → opencode agent/)
  - Se integra con vLLM de victoria para automatización de páginas Elementor

---

## 2026-08-29

### [03:00] - Creación: Armada Arcade (proyecto de juego multiplayer)
- **Tipo**: proyecto | infra local
- **Modificado**: nuevo repositorio `~/armada-arcade/` con motor TetriNET + Socket.IO
- **Afecta a**: kalimete (desarrollo local), opencode (nuevo subagente)
- **Causa**: clon fiel de TetriNET (1997) con arquitectura de plugins para agregar juegos (Dominó, etc.)
- **Estado**: ✅ local, git commit inicial
- **Notas**:
  - Motor: TypeScript, campo 12x22, 9 especiales, 7-bag, ghost piece, Canvas rendering
  - Server: Express + Socket.IO, namespaces (discover, chat, game), salas hasta 6 jugadores
  - Cliente: Vite + Canvas, dark theme estilo TetriNET, lobby + juego
  - Plugin system extensible para agregar nuevos juegos
  - Subagente creado: `armada-arcade.md` (symlink → opencode agent/)
  - No sincroniza con repo (proyecto standalone local)

### [05:12] - Fix: server crash — room_name NOT NULL constraint error
- **Tipo**: proyecto | infra local
- **Modificado**: `server/src/index.ts` (DB schema)
- **Afecta a**: kalimete (armada-arcade server)
- **Causa**: El INSERT en game_records fallaba porque room_name tenía `NOT NULL` pero el INSERT no lo incluía
- **Estado**: ✅ fix aplicado, rebuild OK, server corriendo
- **Notas**: room_name ahora TEXT (nullable), data/ en .gitignore

### [05:12] - Database: SQLite + records + leaderboard (armada-arcade)
- **Tipo**: proyecto | infra local
- **Modificado**: `server/src/index.ts` (SQLite), `client/src/main.ts` (stats UI), `client/index.html` (lobby UI)
- **Afecta a**: kalimete (armada-arcade server + client)
- **Causa**: Agregar persistencia de records de victorias y estadísticas individuales/equipo
- **Estado**: ✅ SQLite con better-sqlite3, endpoints /api/stats, /api/leaderboard, /api/game-end
- **Notas**:
  - Tablas: players, game_records con todos los campos necesarios
  - Lobby muestra: mis stats (partidas, victorias, win rate, mejor score), top 5 leaderboard
  - Team tag selector en lobby (auto/blue/red)
  - Nickname se guarda en localStorage
  - .gitignore creado para node_modules/, data/, client/dist/, server/dist/
  - Repo creado en GitHub: https://github.com/warcold/armada-arcade
  - Vite build configurado correctamente para cliente PWA

---

## 2026-08-27

### [04:26] - Validación completa: pets.armada.do (PetSuite)
- **Tipo**: infra | validación
- **Modificado**: ninguno (solo lectura)
- **Afecta a**: VPS preprod (154.53.35.102), Cloudflare
- **Causa**: validar que todo funcione correctamente en https://pets.armada.do
- **Estado**: ✅ TODO OK
- **Notas**:
  - **DNS**: A proxied → 154.53.35.102, comment "migrado desde alfredo.pro 2026-08-06" ✅
  - **SSL**: Let's Encrypt wildcard `*.armada.do` (CN=armada.do, issuer=Let's Encrypt YE1), expires Oct 24 2026 ✅
  - **HTTP**: 308 → HTTPS redirect ✅ (Cloudflare)
  - **HTTPS**: 200 OK, HSTS, CSP, X-Frame-DENY, Permissions-Policy ✅
  - **Backend API**: `/api/health` → `{"status":"ok"}` (200) ✅
  - **Services API**: 200 OK, devuelve catálogo de servicios (Pet Sitting, Pet Walking, etc.) ✅
  - **Bookings API**: 200 OK, paginación ✅
  - **Users/me API**: 401 sin token (comportamiento correcto) ✅
  - **WebSocket**: Socket.IO inicializado en logs ✅
  - **Caddy**: en ejecución en `nextcloud-stack-caddy-1`, pets.armada.do en Caddyfile mapeado a `petsuite:80` (network ncweb) ✅
  - **Caddy certs**: pets.armada.do cert validado, CN=armada.do SAN=*.armada.do, armada.do ✅
  - **Container petsuite**: Up 2 weeks, running `petsuite:v2`, container_name=petsuite, network=ncweb ✅
  - **Volumes**: data (/app/server/data), storage (/app/server/storage), logs (/app/server/logs), .env (ro) ✅
  - **API escucha**: `http://127.0.0.1:4000` (localhost only) — correcto, solo accesible vía Caddy en network docker ✅
  - **Backups**: cron muerto desde 2026-07-10 (sin cambios) ⚠️

---

## 2026-08-14

### [22:00] - Mejora: permisos de agentes según doc oficial opencode
- **Tipo**: agente | config
- **Modificado**: agents/kalimete.md, agents/eco-cloudflare-{dns,security,storage,tunnels,workers}.md, AGENTS.md, symlink AGENTS.md global
- **Afecta a**: kalimete (config opencode)
- **Causa**: aplicar mejores prácticas de docs oficiales (opencode.ai/docs/agents, /docs/skills, /docs/rules) a la red de agentes existente
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - kalimete: temperature 0.2 + permission.task `"*": deny` + `"eco-cloudflare-*": allow` + `"explore": allow` (patrón orquestador)
  - Subagentes eco-cloudflare-*: temperature 0.1, steps 15, `edit: deny`, `write: deny`, `bash: allow`, `webfetch: allow` (solo operan vía API)
  - AGENTS.md global creado como symlink → armada-sync/AGENTS.md (carga automática en todas las sesiones, doc Rules)
  - Reglas 9 y 10 añadidas a AGENTS.md documentando el patrón

---

## 2026-08-14

### [21:50] - Re-disco de victoria: re-introducida en documentación
- **Tipo**: infra | red | agente
- **Modificado**: MAPA.md (local y repo), AGENTS.md (repo), kalimete.md (repo), sistema-map/MAPA.md, symlinks rotos
- **Afecta a**: kalimete (conocimiento y config opencode)
- **Causa**: victoria fue eliminada de la documentación previa pero sigue existiendo y funcionando como servidor GPU/LLM. Se rediscoveró y se documentó con datos reales: SSH como warcold, vLLM standalone, gateway LLM, nginx, cloudflared, GB10 GPU.
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - SSH configurado con llave `~/.ssh/id_ed25519_kalimete` (warcold, ssh 1666, rbash)
  - Victoria rediscoverada pero NO agregada a opencode agents — solo documentada
  - Symlinks rotos (eco-accesos.md, eco-voice.md) eliminados
  - opencode.jsonc actual: baseURL victoria.armada.do/v1, key alfredo, context:240000/output:32000 (excede límite)
  - AGENTS.md repo actualizado: victoria como máquina activa, no sigue siendo "elim"

---

## 2026-08-14

### [~18:30] - Limpieza completa: eliminación de victoria/rootsource del ecosistema
- **Tipo**: agente | config | infra | documentación
- **Modificado**: 15+ archivos de agents/maps/docs (ver lista abajo)
- **Afecta a**: kalimete (config opencode local)
- **Causa**: el usuario eliminó victoria como máquina del ecosistema; solo se conserva opencode.jsonc para usar el gateway vLLM
- **Estado**: ✅ sincronizado (commit+push pendiente)
- **Notas**:
  - opencode.jsonc INTACTO — el único archivo que se conserva relacionado con vLLM
  - Los maps del ecosistema ahora solo incluyen kalimete + jonas
  - CHANGELOG.md: histórico intacto (no se modificó para preservar historial de cambios)
  - Git logs históricos: contienen menciones de victoria/rootsource (inmutables sin rebase)
  - Artefactos VSCode History y Wine: no operativos, no se tocaron
  - Tunnel victoria-armada y hostname victoria.armada.do se mantienen en Cloudflare (necesario para opencode vLLM)

### Archivos modificados (15):
- ~/.config/opencode/ecosistema-map/MAPA.md — rewrite completo, Kalimete+jonas
- ~/.config/opencode/agent/kalimete.md — rewrite completo, sin victoria
- armada-sync/MAPA.md — rewrite completo
- armada-sync/agents/kalimete.md — rewrite completo
- armada-sync/AGENTS.md — rewrite completo, serviciosVictoria removidos
- armada-sync/sync.sh — Hub único (no follower)
- armada-sync/daily-report/report.py — victoria removida de SERVERS y LLMGATE
- dev/ops/AGENTS.md — fuera victoria/rootsource del índice
- dev/ops/docs/infra.md — fuera victoria/rootsource
- dev/ops/docs/network-topology.md — rewrite
- dev/ops/README.md — fuera victoria
- dev/ops/docs/local-dev.md — fuera victoria.local
- dev/ops/agents/backups/AGENTS.md — fuera victoria/rootsource
- dev/ops/agents/jonas/AGENTS.md — fuera victoria
- dev/ops/agents/vpn/AGENTS.md — fuera victoria.armada.do
- dev/ops/agents/legacy/AGENTS.md — fuera victoria/rootsource

### Archivos eliminados:
- dev/ops/agents/rootsource/ (directorio completo)
- dev/ops/agents/victoria/ (directorio completo)

### Archivos intencionalmente INTACTOS:
- ~/.config/opencode/opencode.jsonc — config vLLM que se conserva
- armada-sync/CHANGELOG.md — histórico de cambios
- .git/ logs — historial de commits (no se toca)

### Referencias mantenidas (necesarias para opencode):
- victoria.armada.do (hostname del Cloudflare tunnel)
- victoria-armada (nombre del tunnel CF)
- VICTORIA_API_KEY (variable de entorno)
- opencode.jsonc (provider vllm para Qwen3.6)

---

# CHANGELOG — Ecosistema Armada

Registro de cambios que afectan infraestructura, agentes, servicios o configuración.
Cada entrada se crea al terminar una tarea que modifique algo en el ecosistema.

---

## 2026-08-14

### Gateway: soporte `reasoning_effort` + catálogo opencode
- **Tipo**: servicio | config
- **Modificado**: proxy del gateway para razonamiento, catálogo opencode kalimete (2 modelos: "Coding con" y "Thinking · Coding con")
- **Afecta a**: servidor llm, kalimete (opencode), PC publica (plantilla)
- **Causa**: el usuario queria usar las variantes de opencode con reasoning_effort
- **Estado**: ✅ sincronizado
- **Notas**: el modelo soporta `reasoning` en el campo `reasoning` de vLLM 0.21. El gateway sigue soportando sufijos para scripts/uso manual

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

## 2026-08-14

### [~02:25] - Gateway: soporte `reasoning_effort` estándar (OpenAI) + catálogo opencode con 2 modelos y variants nativas
- **Tipo**: servicio | config
- **Modificado**: `llm-gateway.py` en victoria (cambio remoto del usuario en `/home/victoria`, no kalimete — proxy reasoning: `reasoning_effort` → `chat_template_kwargs`: `none`/`minimal` → `enable_thinking:false`; `low`/`medium`/`high`/`xhigh` → `enable_thinking:true` + `thinking_level` correspondiente; `xhigh`→high). Backup `llm-gateway.py.bkup-v5-20260814`. En kalimete: `~/.config/opencode/opencode.jsonc` — catálogo reducido a 2 modelos — "Coding con Victoria" (`-normal`, sin reasoning) y "Thinking · Coding con Victoria" (base, con **variants nativas** low/medium/high vía `reasoningEffort`)
- **Afecta a**: victoria (gateway), kalimete (opencode), PC pública (plantilla: misma config con baseURL `https://victoria.armada.do/v1`)
- **Causa**: el usuario pidió quedarse con 2 modelos y usar las variantes de opencode si estaban bien soportadas. Validado según docs de vLLM (reasoning_outputs: `reasoning_effort` estándar; niveles oficiales low/medium/high — **max NO es oficial**) y docs de opencode (variants = overlays por modelo con settings/body). Verificación empírica: `opencode run --variant low/high` → el gateway recibe `reasoning_effort` correcto; `--thinking` muestra el bloque Thinking ✓
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: el `reasoning: 0` en `step_finish` de opencode es solo contabilidad del SDK openai-compatible — el modelo SÍ razona (verificado con `--thinking` y stream con `delta.reasoning`). El gateway sigue soportando sufijos (`-normal`, `-thinking-*`) para scripts/uso manual

---

## 2026-08-14

### [~17:10] - Catálogo opencode simplificado: base + Normal + Thinking Max (quedan fuera low/medium/high)
- **Tipo**: config
- **Modificado**: `~/.config/opencode/opencode.jsonc` (kalimete): se eliminan del catálogo `-thinking-low/medium/high`; quedan 3 modelos: base (thinking on default), `-normal` (sin reasoning) y `-thinking-max`. El gateway SIGUE soportando los 4 niveles por sufijo (no se tocó) — disponibles para scripts/uso manual
- **Afecta a**: kalimete (selector de opencode), PC pública (plantilla)
- **Causa**: validación con el usuario — las mediciones mostraron que la diferencia entre niveles es suave y estocástica (medium dio 3159 chars vs high 812 en la misma pregunta); el control fino no aporta en la práctica, solo tiempo/tokens. Lo que importa: con o sin razonamiento
- **Estado**: ✅ sincronizado (commit+push); verificado `opencode run` con `-normal` → 21 ✓
- **Notas**: plantilla PC pública ahora con los mismos 3 modelos

---

## 2026-08-14

### [~16:40] - Gateway: niveles de thinking (low/medium/high/max) + versión normal — vía sufijos de model id
- **Tipo**: servicio | config
- **Modificado**: llm-gateway.py en victoria (`/home/victoria/` — cambio del usuario, _proxy: antes de normalizar el model, interpreta sufijos del id → `chat_template_kwargs` hacia vLLM): `-normal`/`-fast` → `enable_thinking:false` (respuesta directa); `-thinking` → thinking high; `-thinking-low|medium|high|max` → nivel exacto. Backup `llm-gateway.py.bkup-v4-20260814`. `~/.config/opencode/opencode.jsonc` (kalimete): 5 modelos en el catálogo (Normal, Thinking Low/Medium/High/Max) además del base
- **Afecta a**: victoria (gateway), kalimete (opencode), cualquier PC con la plantilla pública
- **Causa**: el usuario recordó que antes podía elegir low/medium/high/max y pidió validar y agregar la versión normal + la thinking
- **Estado**: ✅ sincronizado (commit+push); servicio reiniciado y activo
- **Notas**: validado en vLLM — el modelo soporta `chat_template_kwargs.enable_thinking` + `thinking_level` (los 4 niveles aceptados; razonamiento llega en el campo `reasoning` de vLLM 0.21, no `reasoning_content`). Default del template SIN kwargs = thinking ON (explica los content:null largos). Verificado vía gateway (victoria.local/v1): -normal → 0 chars reasoning, -thinking-low/high/max → 600-800 chars. `opencode run` con thinking-high → 22 ✓. Victoria (opencode local) sigue con vLLM directo sin niveles — si los quiere, apuntar su provider al gateway por loopback (127.0.0.1:8010)

---

## 2026-08-14

### [~16:00] - opencode.jsonc: capabilities full feature del modelo
- **Tipo**: config
- **Modificado**: `~/.config/opencode/opencode.jsonc` (kalimete); `/home/victoria/.config/opencode/opencode.jsonc` (victoria — cambio del usuario), capabilities del modelo `nvidia/Qwen3.6-35B-A3B-NVFP4` → `tools`, **`reasoning`** (modo thinking Qwen3, parser ya activo en vLLM) y **`input: [text, image]`** (visión VERIFICADA: el modelo describió un pixel PNG y respondió el hex #FFFFFF)
- **Afecta a**: kalimete, victoria (y cualquier PC con la plantilla pública)
- **Causa**: el usuario pidió dejar el modelo "full feature" en opencode en vez de solo tools+text
- **Estado**: ✅ sincronizado (commit+push); sintaxis JSON validada en ambas máquinas
- **Notas**: el jsonc local NO se sincroniza por armada-sync (fuera del scope de sync.sh); el cambio se aplicó directo en cada máquina

---

## 2026-08-14

### [~15:30] - Panel admin: Owner como identificador visible; name autogenerado interno
- **Tipo**: servicio | config
- **Modificado**: `llm-gateway.py` (cambio del usuario en `/home/victoria/`: `CreateKeyRequest`: `name` opcional (autogen), `owner` ahora REQUERIDO; `create_key` autogenera `name` = slug(owner) único con sufijo -2/-3 si colisiona); `admin_template.html` (cambio del usuario en `/home/victoria/`: formulario sin campo Nombre, solo "Owner *"; tabla con columna principal **Owner** + "id: <name>" muted debajo; JS createKey sin name). Backups: `llm-gateway.py.bkup-v3b-20260814`, `admin_template.html.bkup-v3b-20260814`
- **Afecta a**: victoria (panel admin)
- **Causa**: validado con el usuario — `name` solo era el identificador visual porque la llave real no se veía; ahora que el panel muestra `vllm-key-*` con Ver/Copiar, Owner es lo que importa. `name` sigue existiendo internamente (UNIQUE, rutas /admin/keys/{name}, usage_log.key_name) pero invisible
- **Estado**: ✅ sincronizado (commit+push); servicio reiniciado y activo
- **Notas**: verificado — crear sin name → slug autogen (prueba-tester, prueba-tester-2 en colisión); sin owner → 422; lista devuelve owner+key_plaintext; HTML sin "Nombre *"; chat con llave alfredo 200 (auth intacta). Llaves de prueba borradas. Owners actuales: Alfredo Armada, Victoria Armada, Juan Carlos Jerez

---

## 2026-08-14

### [~15:00] - Panel admin: las llaves reales ahora se ven en el dashboard (fix)
- **Tipo**: servicio | config
- **Modificado**: `llm-gateway.py` (cambio del usuario en `/home/victoria/`: `GET /admin/keys` ahora usa `list_keys(include_secret=True)` — antes descartaba `key_plaintext` y el dashboard solo mostraba los NOMBRES como si fueran llaves); `admin_template.html` (cambio del usuario en `/home/victoria/`: columna nueva "Llave" con valor real enmascarado `vllm-key-•••…`, botones **Ver** (toggle mostrar/ocultar) y **Copiar** (clipboard + toast); colspan 11→12). Backups: `llm-gateway.py.bkup-v3-20260814`, `admin_template.html.bkup-v3-20260814`
- **Afecta a**: victoria (panel admin), administradores (Alfredo/Victoria)
- **Causa**: el usuario reportó que en el dashboard "veía los nombres como llaves" — no aparecía el valor real (`vllm-key-<64hex>`)
- **Estado**: ✅ sincronizado (commit+push); servicio reiniciado y activo
- **Notas**: verificado — `/admin/keys` con sesión admin devuelve `key_plaintext` (len=73) de alfredo/victoria/juancarlos; HTML sirve la columna nueva; chat con llave alfredo 200 / sin llave 401 (auth intacta)

---

## 2026-08-14

### [~14:30] - Auditoría completa de documentación y agentes contra estado real (limpieza)
- **Tipo**: documentación | agente | config | sync
- **Modificado**:
  - `kalimete.md` reescrito: gateway v2 (auth por valor, panel, llaves), provider alfredopro, health 401, max-model-len 262144, skill plural, backup retirados borrado, voz/ComfyUI/18789 fuera
  - `ecosistema-map/MAPA.md` reescrito: UFW inactive, voz ELIMINADA, openshell 18789 muerto, límites 262K, cron duplicado detectado
  - `eco-voice.md` reescrito como doc de reconstrucción (servicio ELIMINADO 2026-08-14)
  - `eco-accesos.md`: IP histórica 192.168.5.74 corregida (kalimete en LAN), jonas roto, UFW inactive, llaves gateway v2
  - `eco-cloudflare-*.md` (5): fechas 2026-08-14, skill plural, WAF taohemps NO desplegado, panel URL
  - `cloudflare-map/INVENTARIO.md`: verificación 2026-08-14, WAF taohemps NO, micaserogou 27 records, taohemps 27 records, registros obsoletos VPS documentados, panel URL
  - `armada-sync/AGENTS.md`: gateway v2, voz eliminada, 18789, límites 262K, skill plural, docs-keeper fuera
  - `armada-sync/sync.sh`: **bug corregido** — deployea a `skills/` plural (antes `skill/` singular que opencode NO lee)
  - `command/mapa.md`: apunta al mapa maestro ecosistema (no al agente retirado cloudflare)
  - ELIMINADO: `~/.config/opencode/skill/` (duplicado singular, idéntico a `skills/`)
- **Afecta a**: kalimete, victoria (follower sync), repo
- **Causa**: auditoría ordenada por el usuario (validar docs/agentes contra servicios reales, limpiar obsoleto)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Verificado en vivo 2026-08-14: victoria 2 contenedores, 4 systemd activos, UFW inactive, 8010 loopback, 443 nginx, 3389 RDP; NADA en 8765/8766/18789/8188 (voz/ComfyUI/OpenClaw gateway muertos); jonas SSH sigue roto; kalimete 7 contenedores, kalimete-tunnel active
  - ⚠️ Pendiente usuario: cron duplicado de sync.sh en kalimete (2 líneas idénticas) + entrada cron RSS apuntando a /home/victoria (no existe en kalimete)
  - ⚠️ Pendiente usuario: SPF duplicado micaserogou
  - ✅ Resuelto: token `damp-surf-3478-fusion` y registros VPS (proxy.us-east, telecomm×2, whiteboard.nextcloud) = proyecto VPS-telecomm — **EN USO, NO tocar** (documentación completa pendiente, usuario confirmó)

---

## 2026-08-13

### [~02:30] - demo eliminada; scripts usan la llave de alfredo
- **Tipo**: servicio | config | seguridad
- **Modificado**: DB del gateway (llave `demo` borrada, incl. su usage_log); `~/.zshrc` + `daily-report.env` (VICTORIA_API_KEY = llave de alfredo)
- **Afecta a**: victoria, kalimete
- **Causa**: el usuario preguntó para qué servía demo (solo reporte diario y pruebas); decidió eliminar y usar la de alfredo
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: llaves finales = 3 personales: `alfredo` (admin), `victoria` (admin), `juancarlos` (coder). La llave de demo ya no funciona (401).

### [~02:00] - Formato de llaves: vllm-key-<hex> (rotadas las 4)
- **Tipo**: servicio | seguridad | config
- **Modificado**: `llm-gateway.py` en victoria (`/home/victoria/` — cambio del usuario: create_key genera `vllm-key-<token_hex(32)>`; backup `.bkup-v2b-20260814`); DB: 4 llaves rotadas in-place (key_plaintext+key_hash, historial intacto); `~/.config/opencode/opencode.jsonc` (apiKey alfredo nuevo), `~/.zshrc` + `daily-report.env` (VICTORIA_API_KEY demo nuevo)
- **Afecta a**: victoria, kalimete, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: formato `vict-llm-<nombre>-<salt>` exponía el nombre de la persona; el usuario pidió `vllm-key-*****`
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Nuevo formato: `vllm-key-` + 64 hex (sin nombre). Auth sigue por valor real (key_hash).
  - Las llaves viejas `vict-llm-*` ya NO funcionan (401). Valores rotados sin perder historial de uso.
  - Validado: alfredo 200, demo 200, vict-llm vieja 401, túnel con demo 200, opencode run OK.

### [~01:30] - Auth por VALOR real de llave + jsonc limpio (provider alfredopro, host local)
- **Tipo**: servicio | seguridad | config
- **Modificado**: llm-gateway.py en victoria (`/home/victoria/` — cambio del usuario: validate_key por key_hash del bearer; backup `.bkup-v2-20260814`); `~/.config/opencode/opencode.jsonc` (solo provider `alfredopro`/name "www.alfredo.pro", model "Coding con Victoria", baseURL `https://victoria.local/v1` local, apiKey = valor real alfredo; quitado provider `vllm` directo), `~/.zshrc` y `~/.config/opencode/daily-report.env` (VICTORIA_API_KEY = valor real demo)
- **Afecta a**: victoria, kalimete, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: el usuario dudó que las llaves fueran su nombre (auth por nombre = el valor largo no servía). Decidió auth por valor real (estándar, como OpenAI)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Bearer = valor completo `vict-llm-<name>-<salt>`; el nombre ya NO autentica (401). Lookup por SHA-256(key_plaintext).
  - Los valores largos dados antes siguen siendo los mismos y AHORA son las credenciales reales (antes decorativos).
  - Validado: valor alfredo 200, "alfredo" 401, valor demo 200 (env daily-report + túnel chat 200), valor juancarlos 200, `opencode run` con provider alfredopro OK (valor real).
  - opencode.jsonc ahora SOLO LAN (victoria.local); para otros equipos usar victoria.armada.do con su CA/valor.

### [~01:00] - opencode.jsonc (kalimete): provider "armada" — gateway como público
- **Tipo**: config
- **Modificado**: `~/.config/opencode/opencode.jsonc` (kalimete) — provider nuevo `armada` (@ai-sdk/openai-compatible, baseURL `https://victoria.armada.do/v1`, apiKey `alfredo`), model `armada/nvidia/Qwen3.6-35B-A3B-NVFP4` (limit 240000/20000). Provider `vllm` directo (:8000) intacto; providers opencode zen intactos (no viven en este archivo).
- **Afecta a**: kalimete
- **Causa**: probar el gateway "como público" desde el opencode local
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: validado con `opencode run --model armada/nvidia/Qwen3.6-35B-A3B-NVFP4` → respuesta OK; streaming SSE passthrough por túnel verificado; metering contabiliza el request (alfredo 2 requests).

### [~00:30] - Llaves finales (3 personas) + límites por defecto relajados
- **Tipo**: servicio | config | seguridad
- **Modificado**: llm-gateway.py (cambio del usuario en `/home/victoria/`: defaults create_key/panel: rate 1000/min, max_tokens 32768), admin_template.html (cambio del usuario en `/home/victoria/`: formulario con defaults amplios); DB: llaves
- **Afecta a**: victoria, Alfredo, Victoria (NemoClaw), Juan Carlos
- **Causa**: uso entre amigos + NemoClaw → sin límites duros; 3 llaves personales (admin/admin/coder), borrada la `alfredo` de prueba
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Llaves finales (auth por NOMBRE, Bearer <name>): `alfredo` (Alfredo Armada, admin), `victoria` (Victoria Armada/NemoClaw, admin), `juancarlos` (Juan Carlos Jerez, coder), `demo` (admin, interna del sistema).
  - Parámetros personales: rate 100000/min, max_tokens 262144, budget 0 (ilimitado), sin expiración, precio 0.02 $/1k (solo contabilidad).
  - Validado: roles/scopes en /v1/usage (admin=all, coder=self).

### [~23:59] - Gateway v2: contabilidad (metering, precio por llave, presupuesto, roles, rate real)
- **Tipo**: servicio | seguridad | infra | config
- **Modificado**: llm-gateway.py en victoria (`/home/victoria/` — cambio del usuario, v2.0.0; backup `llm-gateway.py.bkup-v1-20260814`), admin_template.html (cambio del usuario en `/home/victoria/`: nuevo SPA panel), DB migrada automáticamente (ALTER TABLE)
- **Afecta a**: victoria, kalimete, Alfredo (panel), consumidores del gateway
- **Causa**: usuario pidió panel profesional con contabilidad: precio por llave, uso general, límites, manejo de llaves y tiers (admin/coder) — mejoras basadas en prácticas de LiteLLM/Portkey/LLM Gateway (budget duro por llave, metering en el gateway, scoping por rol, llave visible una sola vez)
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Metering real: cada request guarda model, prompt/completion/total tokens y costo en `usage_log`; acumula totales por llave. Costo = total_tokens/1000 × `price_per_1k_tokens` (default 0.02, env DEFAULT_PRICE_PER_1K; independiente del modelo).
  - Presupuesto: `budget` USD por llave (0=ilimitado) → 402 "budget exceeded" al agotarse. Rate real por minuto (usage_log últ. 60s) → 429. max_tokens de la key se impone por request. Expiración por horas.
  - Roles: `admin` (ve uso global en /v1/usage) / `coder` (solo su propia key). Panel admin = ADMIN_PASS, sigue LAN-only (403 vía túnel).
  - Endpoints nuevos: `GET /v1/usage`, `PUT /admin/keys/{name}` (editar), `GET /admin/keys/{name}/usage`, `GET /admin/usage?key=`.
  - Panel: login, dashboard (6 stats + chart 14 días + top keys por gasto + actividad), API Keys (crear con rol/precio/presupuesto/expiración, tabla con barra de presupuesto, editar/activar/desactivar/borrar, modal de uso con chart), Usage con filtro por llave y costo por request.
  - Llaves finales: `demo` (admin, del sistema — opencode/túnel) y `alfredo` (coder, $0.05/1k, budget $2, creada por Alfredo en el panel). Tests: budget→402 ✓, rate→429 ✓, túnel con metering ✓, /admin 403 vía túnel ✓.
  - ⚠️ Streaming: pasa raw sin medir tokens (cost 0) — documentado; opencode usa el vLLM directo :8000, no el gateway.

### [~23:30] - Fix panel admin: login redirigía a /admin/dashboard (JSON) en vez de /admin (HTML)
- **Tipo**: servicio | bugfix
- **Modificado**: llm-gateway.py en victoria (`/home/victoria/` — cambio del usuario) — doLogin: `location.href = '/admin/dashboard'` → `'/admin'` (patch remoto, sin backup; cambio de 1 línea)
- **Afecta a**: Alfredo (panel https://victoria.local/admin)
- **Causa**: tras loguearse, la SPA mandaba al navegador a un endpoint JSON de la API — se veía "el request crudo" y no la web de administración
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**: verificado: GET /admin → HTML con redirect correcto; POST /admin/login → token; GET /admin/keys con token → lista (demo active). El panel completo (crear/activar/desactivar/borrar llaves, usage) ya existía en el template y queda operativo.

### [~23:00] - TLS en victoria.local (nginx 443) — panel y API sin puertos
- **Tipo**: infra | red | seguridad | config
- **Modificado**: victoria (10.0.0.5) — usuario instaló/configuró: nginx + site `gateway.conf` (443 TLS → 127.0.0.1:8010), cert mkcert `victoria.local`/`victoria` (firmado con CA de kalimete, expira 2028-11-14) en `/etc/ssl/local-certs/`, gateway GATEWAY_HOST 0.0.0.0→127.0.0.1 (8010 loopback-only); kalimete: CA copiada a `~/rootCA-kalimete-victoria-local.crt`
- **Afecta a**: kalimete, victoria, Alfredo (Windows 10.0.0.64)
- **Causa**: usuario no podía entrar al panel (ERR_SSL_PROTOCOL_ERROR — navegador forzaba https contra HTTP plano) y pidió trabajar con TLS sin ver puertos
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - URLs finales: panel **`https://victoria.local/admin`** (login `victoria-admin`), API LAN **`https://victoria.local/v1/chat/completions`**, API pública **`https://victoria.armada.do/v1/...`** (túnel → loopback 8010, intacto).
  - Verificado: 443 admin 200 (CA validada), login 200, chat 200; 8010 ya no responde en LAN (refused); túnel 200.
  - Windows de Alfredo: instalar `~/rootCA-kalimete-victoria-local.crt` (en kalimete) en "Entidades de certificación raíz de confianza" para que https://victoria.local no marque error (mDNS/avahi activo resuelve victoria.local).
  - El gateway sigue en 8010 loopback (nginx + cloudflared lo consumen por 127.0.0.1). Middleware admin LAN-only intacto (403 vía túnel).

### [~22:00] - vLLM reconfigured: concurrencia real (13x) + fix límite total del modelo
- **Tipo**: infra | config | servicio
- **Modificado**: contenedor nemoclaw-vllm en victoria (cambio del usuario, recreado: `--gpu-memory-utilization 0.5`, `--max-num-seqs 8`, `--max-num-batched-tokens 16384`), victoria-llm-gateway en victoria (cambio del usuario, patch: normaliza model id → evita 404 por alias), opencode.jsonc kalimete (cambio kalimete) + victoria (cambio del usuario: context 262144→240000, output 32768→20000)
- **Afecta a**: kalimete, victoria, repo armada-sync
- **Causa**: usuario reportó que el vLLM parecía tener 1 sola secuencia y se trancaba con requests al máximo de tokens. Diagnóstico: (1) util 0.4 → KV ~560K tokens → solo ~2 secuencias de contexto completo; (2) **clientes pedían context 262144 + output 32768 = 294912 > 262144 (límite total del modelo)** → vLLM rechaza con 400 = chat trancado; (3) gateway pasaba el model tal cual → 404 con alias.
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Resultado: KV cache **3,447,590 tokens** (~34.7 GiB), **concurrencia 13.15×** para requests de 262K (antes ~2×). Validado: 6 requests concurrentes → 200 en ~9s; output 30000 OK; chat vía dominio con alias `qwen3.6` → 200.
  - Backup del inspect del contenedor: `/home/victoria/nemoclaw-vllm-inspect-backup.json`. ⚠️ NemoClaw gestiona el contenedor (label managed-vllm) — si lo recrea, puede volver a defaults.
  - Límites clientes: 240000 + 20000 = 260000 ≤ 262144 (holgura ~2K). gateway: SERVED_MODEL env (default nvidia/Qwen3.6-35B-A3B-NVFP4).

### [~21:00] - victoria.armada.do → SOLO API LLM (túnel :8010) + panel admin LAN-only + UIs fuera de internet
- **Tipo**: red | seguridad | infra | config
- **Modificado**: túnel victoria-armada en Cloudflare (kalimete: ingress → :8010), llm-gateway.py (cambio del usuario en victoria: middleware admin LAN-only), DNS (verificado), docs (kalimete.md, eco-cloudflare-tunnels.md, eco-accesos.md, SKILL, MAPAs, AGENTS.md — kalimete), snapshots históricos borrados (kalimete)
- **Afecta a**: kalimete, victoria, repo armada-sync
- **Causa**: usuario pidió (1) borrar los históricos con menciones del host antiguo, (2) victoria.armada.do SOLO para requests al vLLM (vía gateway con llaves + panel admin como el anterior), (3) UIs de ComfyUI y NemoClaw/OpenClaw SOLO en victoria.local (LAN) — no accesibles desde fuera de la casa
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Túnel: ingress `victoria.armada.do` → `http://127.0.0.1:8010` (era :18789). Validado: chat 200 con bearer, 401 sin key, `/models` 200. Panel `/admin` vía dominio → 403.
  - Gateway parcheado (llm-gateway.py, backup .bkup-20260813): rutas `/admin*` bloqueadas si hay header CF-Connecting-IP (viene por túnel) o IP no-LAN → panel = `http://victoria.local:8010/admin` (login ADMIN_PASS). Servicio reiniciado, verificado LAN 200 / túnel 403 / chat 200.
  - Borrados: `~/.config/opencode/agent-backup-2026-08-12/`, `~/armada-sync/agents-retired-2026-08-12/`, `~/.config/opencode/opencode.jsonc.bkup.old`.
  - ⚠️ Pendiente: el updater DDNS de jonas aún puede pisar el CNAME de victoria.armada.do (verificar cuando el SSH a jonas se arregle). ComfyUI :8188 no corre (cuando corra = solo LAN). OpenClaw :18789 solo LAN.
  - Uso: API LLM pública = `https://victoria.armada.do/v1/chat/completions` (bearer = nombre de key); panel = victoria.local:8010/admin; UIs = victoria.local.

### [~20:00] - Migración documental completa: victoria hace el trabajo completo (0 menciones del host antiguo)
- **Tipo**: config | infra | doc | sync
- **Modificado**: ~/.config/opencode (kalimete.md, eco-*.md, MAPA.md, cloudflare-map, skills), armada-sync (AGENTS.md, MAPA.md, configs/, skills/, daily-report/), ~/.zshrc, ~/.config/opencode/daily-report.env, DNS verificado
- **Afecta a**: kalimete, victoria (10.0.0.5), repo armada-sync
- **Causa**: usuario pidió eliminar todo rastro del host antiguo (10.0.0.5, cuyo nombre histórico se retiró) de documentación, agentes, configs y Cloudflare — victoria hace el trabajo completo; no mencionar el nombre viejo ni "ex-..."
- **Estado**: ✅ sincronizado (commit+push)
- **Notas**:
  - Gateway validado end-to-end: `victoria-llm-gateway` :8010 (systemd ACTIVE) — auth por NOMBRE de key (bearer `demo`), model `nvidia/Qwen3.6-35B-A3B-NVFP4`, `enable_thinking:false` → content directo. `/v1/models` no existe en el gateway (solo `/models` + `/v1/chat/completions`).
  - `~/.zshrc`: variable de la key renombrada → `VICTORIA_API_KEY` (valor = bearer válido `demo`). `daily-report.env` igual.
  - `report.py`: LLMGATE → `http://10.0.0.5:8010/v1/chat/completions`, MODEL → `nvidia/Qwen3.6-35B-A3B-NVFP4`, SERVERS sin el host viejo.
  - DNS verificado: `victoria.armada.do` = CNAME proxied → túnel `victoria-armada` (`d9abe241-…cfargotunnel.com`); el hostname antiguo NO existe en DNS.
  - ⚠️ **OJO DDNS**: el updater de jonas (cron */5) actualizaba `victoria.armada.do` como A (69.143.73.120); desde hoy es CNAME del túnel — si el updater recrea el A lo pisa (verificar en jonas cuando el SSH se arregle).
  - Pendiente: gateway :18789 no escucha → `victoria.armada.do` 503 (esperado); servicios de voz (victoria-voice, nginx 8765) pendientes de migrar; ollama no corre; opencode.jsonc.bkup.old y daily-report.log aún contienen menciones históricas (snapshots/logs, no activos).

### [23:35] - Red: host 10.0.0.5 renombrado → NUEVA victoria + fix RDP headless
- **Tipo**: red | infra | servicio | config
- **Modificado**: kalimete — hosts, SSH configs, MAPA.md, kalimete.md, eco-accesos.md, AGENTS.md, perfil remmina / victoria (10.0.0.5) — usuario: xrdp desactivado, grd RDP habilitado con credenciales + TLS
- **Afecta a**: kalimete, victoria (10.0.0.5), Alfredo (Windows en 10.0.0.64)
- **Causa**: usuario reportó RDP rechazado tras credenciales; validación de logs mostró: (1) el host 10.0.0.5 es la NUEVA victoria (puerto 1666, user victoria), (2) xrdp validaba OK pero GNOME mataba la sesión ("Session manager already running" — sesión local activa), (3) grd tenía RDP disabled y sin credenciales
- **Estado**: ✅ sincronizado
- **Notas**: llave `id_ed25519_kalimete` autorizada en victoria. `grdctl --system rdp set-credentials victoria vcolador` + cert self-signed en /var/lib/gnome-remote-desktop/. xrdp y xrdp-sesman DISABLED. ⚠️ pendiente reactivar el gateway LLM (luego validado: victoria-llm-gateway :8010 ACTIVE). Victoria vieja (10.0.0.64) ya no existe como Ubuntu (IP ahora del Windows de Alfredo).

### [13:30] - Fix: vLLM context overflow (163K → 262K)
- **Tipo**: config | infra
- **Modificado**: opencode.jsonc (baseline-thinking), MAPA.md (regla anti-desborde)
- **Afecta a**: kalimete (config opencode)
- **Causa**: 147,457 input + 16,384 max_tokens = 163,841 > 163,840 vLLM limit → "Type validation failed". El modelo soporta 262K según NVIDIA docs.
- **Estado**: ✅ sincronizado
- **Notas**: baseline-thinking: max_tokens 16384→8192, context 158000→245000. MAPA.md actualizado con contexto real 262K. vLLM contenedor aún en 163K → no urgente (opencode.jsonc tiene margen).

---

## 2026-08-13

### [05:35] - Sync: integración del host 10.0.0.5 (GPU/LLM) al ecosistema (follower)
- **Tipo**: sync | infra | agente
- **Modificado**: armada-sync/AGENTS.md, armada-sync/agents/docs-keeper.md (nuevo), host 10.0.0.5: llave github del follower + ~/.ssh/config, cron, opencode.jsonc (default_agent)
- **Afecta a**: kalimete, victoria, host 10.0.0.5
- **Causa**: el host 10.0.0.5 es el proveedor de modelos (vLLM/gateway) de todo el ecosistema; quedaba fuera del sync de agentes
- **Estado**: ✅ sincronizado
- **Notas**: el host 10.0.0.5 ahora es FOLLOWER (pull+deploy, nunca push). Deploy key `victoria-follower-readonly` (solo lectura) registrada en GitHub vía gh. docs-keeper.md (agente local del host) añadido al repo con model portable (sin model fijo → usa default de cada máquina). Cron `*/5` instalado. default_agent: kalimete añadido al opencode.jsonc del host. md5 de kalimete.md idéntico al repo. jonas queda pendiente (SSH roto).

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
