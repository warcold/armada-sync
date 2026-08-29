# Eco Cloudflare IRC — Gestión de InspIRCd El Corito

## Visión

Gestión del servidor IRC InspIRCd de la red "El Corito" (`chatlatinos.org`), actualmente ejecutándose en vps-preprod.

## Topología IRC

| Componente | Estado | Detalle |
|------------|--------|---------|
| **Servidor IRC** | ✅ Activo | vps-preprod (154.53.35.102) |
| **Servicio** | ✅ systemd | `inspircd.service` - active (running) |
| **Usuario** | justin_t | Ejecuta InspIRCd como user non-root |
| **Servidor Name** | colador.elcorito.org | SID: 97Z |
| **Network** | El Corito | |
| **DNS** | chatlatinos.org | Apunta al servidor |

## Puertos

| Puerto | Tipo | Descripción |
|--------|------|-------------|
| 6667 | Clientes | Plaintext |
| 6697 | Clientes | TLS |
| 7209 | Server-to-Server | TLS |
| 7022 | Enlace a irc.elcorito.org | TLS |
| 1719 | Local | Internal (localhost) |

## Enlace a irc.elcorito.org

- **Host:** irc.elcorito.org → 15.204.218.254
- **Puerto:** 7022
- **Pass:** ELCORITO_7022
- **SSL Profile:** Clients
- **Autoconnect:** Cada 2 minutos
- **Estado:** Configurado (autoconnect period="2m")

## Operadores

| Operador | Tipo | VHost | Privilegios |
|----------|------|-------|-------------|
| Justin | NetAdmin | justinbeatz.elcorito.org | Full admin |
| warcold | NetAdmin | warcold.elcorito.org | Full admin |
| DiscordBot | Helper | relaybot.elcorito.org | Relay + Ban |
| HOPM | FloodControl | colacontrol.elcorito.org | Kline + Gline |

## Módulos Principales (~70 módulos)

- m_abbreviation, m_account, m_alias, m_alltime, m_anticaps, m_argon2
- m_auditorium, m_banexception, m_bcrypt, m_botmode, m_callerid
- m_cap, m_chanfilter, m_chanhistory, m_channames, m_channelban
- m_cloak, m_cloak_sha256, m_commonchans, m_conn_join, m_customprefix
- m_customtitle, m_deaf, m_denychans, m_dnsbl, m_filter, m_gateway
- m_geo_maxmind, m_geoban, m_geoclass, m_globalload, m_globops
- m_haproxy, m_helpmode, m_hidechans, m_hidelist, m_hidemode, m_hideoper
- m_ircv3, m_ircv3_accounttag, m_ircv3_batch, m_ircv3_capnotify
- m_ircv3_chghost, m_ircv3_ctctags, m_ircv3_invitenotify
- m_ircv3_labeledresponse, m_ircv3_msgid, m_joinflood, m_knock
- m_messageflood, m_monitor, m_multiprefix, m_muteban, m_nickflood
- m_ojoin, m_operchans, m_operjoin, m_operlevels, m_operlog, m_opermodes
- m_opermotd, m_override, m_permchannels, m_rline, m_sajoin, m_sakick
- m_samode, m_sanick, m_sapart, m_saquit, m_sasl, m_satopic, m_securelist
- m_serverban, m_services, m_sethost, m_setident, m_setidle, m_setname
- m_showwhois, m_shun, m_silence, m_ssl_openssl, m_sslinfo, m_sslrehashsignal
- m_starttls, m_stripcolor, m_swhois, m_tline, m_uhnames, m_uninvite
- m_vhost, m_watch, m_websocket, m_geomaxlite, m_ircv3_extjwt
- m_hidewhois, m_ipinfo_io, m_whoisport

## Geodata

- GeoLite2-City.mmdb (63 MB)
- GeoLite2-Country.mmdb (9.7 MB)

## Certificados TLS

- **CN:** el.colador.de.alfredo.pro
- **Expiración:** 2 Oct 2026
- **Archivos:** cert.pem, fullchain.pem, privkey.pem, chain.pem, dhparams.pem
- **Ruta:** /home/justin_t/inspircd/run/certs/
- **Renovable con:** /home/justin_t/inspircd/run/deploy-ssl.sh (dehydrated/certbot)

## Rutas de Archivos

| Ruta | Descripción |
|------|-------------|
| /home/justin_t/inspircd/run/ | Directorio principal de InspIRCd |
| /home/justin_t/inspircd/run/bin/inspircd | Binario (v4.7.0) |
| /home/justin_t/inspircd/run/conf/inspircd.conf | Config principal |
| /home/justin_t/inspircd/run/conf/modules.conf | Configuración de módulos |
| /home/justin_t/inspircd/run/conf/opers.conf | Operadores y clases |
| /home/justin_t/inspircd/run/conf/links.conf | Enlaces a otros servers |
| /home/justin_t/inspircd/run/conf/motd.txt | Mensaje del día |
| /home/justin_t/inspircd/run/conf/opermotd.txt | MOTD para operadores |
| /home/justin_t/inspircd/run/certs/ | Certificados TLS |
| /home/justin_t/inspircd/run/data/geodata/ | GeoLite2 databases |
| /home/justin_t/inspircd/run/logs/inspircd.log | Log principal |
| /home/justin_t/inspircd/run/modules/ | Módulos .so |

## Comandos de Gestión

```bash
# Estado del servicio
sudo systemctl status inspircd.service

# Iniciar
sudo systemctl start inspircd.service

# Detener
sudo systemctl stop inspircd.service

# Reiniciar
sudo systemctl restart inspircd.service

# Ver logs
journalctl -u inspircd -f --no-pager

# Logs del archivo
tail -f /home/justin_t/inspircd/run/logs/inspircd.log

# Ver puertos
ss -tlnp | grep inspircd

# PID
cat /home/justin_t/inspircd/run/inspircd.pid
```

## Notas de Migración (2026-08-29)

- IRC migrado de vps-proxy (31.220.102.176) a vps-preprod (154.53.35.102)
- Servicio systemd creado con User=justin_t, Group=justin_t
- Config original copiada desde /home/justin/inspircd/ en vps-proxy
- Enlace irc.elcorito.org: 15.204.218.254:7022
- Certificado SSL: el.colador.de.alfredo.pro (expira 2026-10-02)

## Estado de Conexión

- Puertos 6667, 6697, 7022, 7209, 1719 escuchando
- Servicio systemd: active (running)
- Usuario: justin_t
- Binario: InspIRCd v4.7.0
- Módulos: ~70 cargados
- Logs: activos
