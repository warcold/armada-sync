---
name: cloudflare
description: Gestión de la cuenta Cloudflare de Alfredo@armada.do vía terminal. Usa SIEMPRE esta skill cuando el usuario mencione cloudflare, wrangler, r2, workers, dns, zonas, dominios, armada.do, micaserogou.com, buckets, kv, d1, pages, certificates, tunnels, o cualquier recurso de la cuenta. Contiene credenciales, comandos y ejemplos de la API.
---

# Cloudflare — Gestión desde terminal

## Credenciales (OBLIGATORIO cargar antes de usar wrangler)

Todos los comandos de wrangler y scripts requieren las variables de entorno.
Nunca escribir los valores de los tokens en el chat ni en archivos.

```sh
set -a && source ~/.config/cloudflare/env && set +a
```

El archivo `~/.config/cloudflare/env` (permisos 600) contiene:
- `CLOUDFLARE_API_TOKEN` — token de cuenta (spring-dream-d681): túneles, workers, R2 (al activar), DNS Edit **todas las zonas**, crea zonas, settings SSL, bot mgmt — **hace el trabajo de todos los demás tokens**
- `CLOUDFLARE_DNS_TOKEN` — DNS Read/Write armada.do (opencode-dns-cleanup) — **EN USO por el DDNS de jonas** (cron root */5, `/etc/cloudflare-ddns/token` root:600) — NO borrar
- `CLOUDFLARE_ACCOUNT_ID` — 432949306735261bec2ca45a0a2719c7
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` — credenciales S3 de R2
- (comentado: `CLOUDFLARE_ZONE_TOKEN` opencode-zone-admin — settings SSL + bot mgmt, redundante con el token de cuenta; borrar del dashboard)

## Datos de la cuenta (validados)

- Cuenta: **Alfredo@armada.do's Account**
- Account ID: `432949306735261bec2ca45a0a2719c7`
- Zonas (dominios): **armada.do** y **micaserogou.com**
- R2: las credenciales S3 existen pero **el usuario descartó R2 (decisión 2026-08-07: no pagar)** — backups en casa, disco físico separado en jonas. NO activar R2 ni proponerlo; no tocar R2.
- Workers: **ninguno desplegado** (revisado 2026-08-05)
- D1: **ninguna base** creada (revisado 2026-08-05)
- **El token `CLOUDFLARE_API_TOKEN` es de ALCANCE CUENTA** (nombre "spring-dream-d681"; tiene restricción de IP — el usuario la actualiza desde su dashboard). **Puede (verificado 2026-08-07)**: túneles, workers, r2, listar/crear zonas, DNS Edit all zones, SSL settings, bot management. Todo el DNS y settings se hace con este token; NO usar cloudflared cert.pem para DNS.

## Arquitectura de acceso — IMPORTANTE (actualizado 2026-08-07)

Los servicios públicos se sirven por **CF proxied** (A/CNAME naranja → VPS 154.53.35.102, firewall DOCKER-USER solo rangos CF). Solo un servicio usa túnel.

### Túneles activos

**1. `victoria-armada`** ID `d9abe241-fcbb-40a6-9202-36d0cfa7a95a` (en victoria, 10.0.0.5) — ÚNICO túnel de la cuenta (verificado 2026-08-13, healthy, 4 conexiones)
- Ingress: `victoria.armada.do` → `http://127.0.0.1:18789` (gateway OpenClaw de Victoria); default → 404
- `cloudflared.service` systemd en victoria (instalado 2026-08-13, arm64, token en `/etc/cloudflared/token`)

**2. ~~`kalimete-local`~~ ELIMINADO 2026-08-06**: las apps dev de kalimete (royalsmoke, woodly, micasero, kalimete, taohemps, petsuite) son SOLO `.local` (desarrollo) — nunca exponer en armada.do sin pedir confirmación al usuario.

### Orígenes directos proxied (no túnel) — cada uno con TLS propio
- **VPS prod** 154.53.35.102 (armada.do y taohemps.com): TLS por caddy (Let's Encrypt), origin cerrado a solo rangos CF (DOCKER-USER).
- **erpipos** 147.93.6.112: `erpipos.armada.do` + `erpipos.micaserogou.com` (A proxied → 147.93.6.112). **TLS por Let's Encrypt en el propio nginx** desde 2026-08-07 (cert CN=erpipos.armada.do, SAN ambos dominios, certbot.timer renueva). Detalles: `ops/agents/legacy/AGENTS.md` (vps-erpipo).

### Red local / acceso remoto
- VPN WireGuard: servidor **jonas (10.0.0.20, wg0=10.0.100.1)**, clientes kalimete (10.0.100.2) y vps-preprod (10.0.100.3). Port-forward del router: UDP 51820 → jonas.
- **DDNS de la casa (2026-08-06)**: `home.armada.do` → IP pública (A, `proxied:false`, TTL 120) — endpoint oficial del WG. `victoria.armada.do` es alias del mismo DDNS (también actualizado por el updater). **Updater**: `/usr/local/sbin/cloudflare-ddns.sh` en jonas (token DNS en `/etc/cloudflare-ddns/token` root:600), cron `*/5`, actualiza ambos registros si la IP cambia (ipify). Los clientes WG usan `Endpoint = home.armada.do:51820` (kalimete: `/etc/wireguard/bridge-to-local.conf`; vps: `/etc/wireguard/wg0.conf`).
- DNS LAN: resolver `10.0.0.20` (dnsmasq en jonas, `/etc/dnsmasq.d/lan-overrides.conf`). Sirve los `.local` (kalimete.local=10.0.0.106, victoria.local=10.0.0.5, jonas.local=10.0.0.20) y split-horizon `.armada.do` internos (jonas.armada.do, victoria.armada.do → LAN; el bug victoria→10.0.0.106 fue corregido el 2026-08-06). Clientes WG externos: usar `DNS=10.0.0.20` para resolver los `.local` igual que en casa.
- Las apps dev de kalimete SOLO se acceden en localhost:PUERTO — no exponer

### Politica SSH (todos los servers, local y remoto)
- **Sin restriccion por IP** (amigos con usuarios propios conectan desde cualquier lado)
- Autenticacion SOLO por llave (`PasswordAuthentication no`), root directo solo con la llave de kalimete (`warcold@kalimete.local`, ~/.ssh/id_ed25519_kalimete)
- vps-preprod: puerto 1333, root + key, usuario amigo `justin_t` (sin llaves aun — avisar cuando quiera conectar), fail2ban activo (jail sshd)
- victoria: puerto 1666, root SIN llaves (solo usuario victoria + sudo con password)
- kalimete: puerto 1111, root prohibit-password

### VPS preprod/produccion (`vps-preprod` = auth.armada.do = 154.53.35.102)
- Ubuntu 24.04, Docker (12 proyectos), reverse proxy único: contenedor caddy (nextcloud-stack-caddy-1, 80/443), authentik SSO, sshd puerto **1333**
- **Firewall (2026-08-06)**: INPUT policy DROP (SSH 1333 abierto por llave; 80/443 host solo rangos CF — cosmético, docker no pasa por INPUT); DOCKER-USER: 80/443 abiertos (zonas externas aún no en CF), resto de puertos eth0 DROP; persistido con netfilter-persistent + servicio `docker-cf-firewall` (re-aplica DOCKER-USER post-reboot)
- **PENDIENTE para cerrar 80/443 a solo Cloudflare**: agregar zonas taohemps.com y alfredo.pro (o migrar alfredo.pro→armada.do, acordado; alfredo.pro es de banahosting) y luego unificar DOCKER-USER a solo rangos CF (15 rangos en /etc/docker-firewall/apply.sh)
- **taohemps.com MIGRADO A ZONA CF 2026-08-07** (id `080b3e78b1b420f477009c5374652103`, **ACTIVE**): A proxied → 154.53.35.102, www CNAME, DNS de correo banahosting preservado (autoconfig/autodiscover/cpanel/webmail/whm/MX/SRV/DKIM/DMARC/SPF — NO tocar), SPF duplicado limpiado. NS cambiados en banahosting (`johnathan.ns.cloudflare.com`/`vita.ns.cloudflare.com`). **DOCKER-USER del VPS cerrado a solo rangos CF v4+v6** (`docker-cf-firewall.service` → `/etc/docker-firewall/apply.sh`, fetch `api.cloudflare.com/client/v4/ips` + caché) — directo por IP bloqueado. El token `spring-dream-d681` se amplió 2026-08-07 (Zone:Edit+DNS:Edit all zones): ya cubre DNS, settings y **crea zonas** (sonda `prueba-invalida.com` creada y borrada).
- **pets y woodly MIGRADOS a armada.do 2026-08-06**: `pets.armada.do` y `woodly.armada.do` (A proxied → 154.53.35.102, caddy con ambos nombres, CORS actualizado, rebuild). **`.alfredo.pro` RETIRADO 2026-08-07**: pets/woodly eliminados del Caddyfile (verificado: alfredo.pro ya no responde, armada.do 200). Dominio alfredo.pro es de banahosting — el retiro del *.alfredo.pro pendiente de listado (mail.alfredo.pro vive en cPanel de banahosting, usar no-reply@armada.do para SMTP) **IMPORTANTE**: el caddy contenedor monta `/opt/nextcloud-stack/Caddyfile` (ro) — `/etc/caddy/Caddyfile` es ahora SYMLINK a ese archivo (evitar desync; caddy reload NO aplica por admin API deshabilitada, hay que `docker restart nextcloud-stack-caddy-1`)
- SMTP de apps (2026-08-06): **petsuite migrado a mail.armada.do** (antes mail.alfredo.pro). Credenciales mailbox compartida `no-reply@armada.do` = `Dn%q#U0tV,65FqSU` (la de docuseal; la de woodly está STALE — 535). **nextcloud: config OK y verificado** (mail_smtpauthtype=LOGIN añadido; envío de prueba 250 por mail.armada.do). mail.alfredo.pro y mail.armada.do resuelven al MISMO cPanel 66.225.201.198. MX de armada.do = Cloudflare Email Routing (_dc-mx). **OJO**: en .env de petsuite la pass va ENTRE COMILLAS por el `#` (dotenv la corta como comentario). El branding "alfredo.pro" en textos legales de petsuite es la marca de empresa, no el dominio del sitio
- Certificados: caddy Let's Encrypt, renuevan ~Sep-Oct 2026; con proxy ON la renovacion va por HTTP-01 via Cloudflare (OK). taohemps.com/pets/woodly son directos (zonas externas)
- staging-postgres/minio: SOLO red docker (sin bind publico); platform-traefik ELIMINADO (config en /opt/residencial-staging/traefik.removed-20260806)
- **VPN wg `bridge-to-local` ARREGLADA 2026-08-06**: el wg server es **jonas (10.0.0.20, wg0=10.0.100.1)**; relé kalimete (10.0.100.2) ↔ vps (10.0.100.3). El bug: ufw de jonas tiene default "deny (routed)" y ufw-before-forward solo acepta ICMP echo → TCP entre peers se caía en el policy DROP del FORWARD. Fix: `sudo ufw route allow in on wg0 out on wg0` (persiste). Verificado: SSH root@10.0.100.3:1333 desde kalimete (host key idéntica a la del IP público); puerto 22 del vps queda DROP (firewall)
- royalsmoke ELIMINADO (kalimete y vps) 2026-08-06 — ya no procede
- **Backups (2026-08-06): NAS central = jonas** (`/srv/backups/<host>/<servicio>/`). Timers: jonas 03:00, vps 03:20 (nextcloud-db, ragnarok/woodly, taohemps, petsuite, infra+env), victoria 04:05; prune 30 días 06:00. Push vía rsync+SSH 1222 con llaves `id_backup` forzadas al gate `backup-gate.sh` (solo rsync y /srv/backups). Restauración nextcloud-db PROBADA. Detalles: `ops/agents/backups/AGENTS.md`

- **Agentes por sistema**: repositorio `ops/agents/<sistema>/AGENTS.md` (jonas, vps, victoria, kalimete, vpn, backups) en https://github.com/warcold/armada-ops — **actualizar el agente correspondiente tras CADA cambio** en cualquier sistema.
- **Git = solo SSH keys** (sin PATs): remotes `git@github.com:warcold/*.git`. PAT clásico filtrado revocado; gho_ muerto eliminado del VPS.

### Credenciales y tokens
- `CLOUDFLARE_API_TOKEN` (spring-dream-d681, en env): cuenta entera (túneles, R2, workers) — NO DNS de zona
- `CLOUDFLARE_DNS_TOKEN` (opencode-dns-cleanup, en env): **DNS Read/Write solo armada.do** — creado 2026-08-06 vía API, para operaciones de DNS
- Otros tokens del inventario: `erpipos-server-dns` (DNS+SSL en armada.do y micaserogou.com, en uso) y `damp-surf-3478-fusion` (DNS armada.do, SIN uso desde 27-jul — candidato a borrar)
- `VICTORIA_API_KEY` (env shell, ~/.zshrc): bearer del gateway LLM de victoria (`victoria-llm-gateway` :8010, auth por NOMBRE de key — la key activa se llama `demo`; validado 2026-08-13)
- La zona `micaserogou.com` (fdebf4707c11ec49d9a73204457ba19c) aún NO tiene token de DNS propio (erpipos-server-dns la cubre)

### Reglas aprendidas
- **NUNCA registrar un A proxied (nube naranja) apuntando a un origin sin 443 si la zona está en SSL=strict**: Cloudflare exige HTTPS:443 con cert válido al origin → si no existe, timeout total (caso erpipos 2026-08-07: el origin solo servía HTTP; con flexible funcionaba, strict lo tumbó). Al emitir cert LE en un origin proxied, **grisar temporalmente el registro** (challenge HTTP-01 directo) y volver a naranja después.
- **NUNCA subdominios de 2 niveles** (api.x.armada.do): Universal SSL gratis no los cubre → handshake_failure. Usar `x-api.armada.do`
- DNS CNAME: crear con `cloudflared tunnel route dns --overwrite-dns <tunnel_id> <host>` (usa cert.pem de `~/.cloudflared/`, cubre armada.do y micaserogou.com)
- **PENDIENTE (dashboard)**: NADA en DNS — los 9 CNAME muertos del túnel kalimete ya fueron borrados 2026-08-06 (API con token opencode-dns-cleanup). `kalimete.armada.do` ELIMINADO 2026-08-06 (era CNAME al túnel borrado). El CNAME activo es `victoria.armada.do` (túnel victoria-armada)
- ufw victoria: SOLO LAN (4000, 443, 1666, 8000, 8010, 18789, 127.0.0.1) — nada abierto a internet (el túnel no lo necesita)

### Playbook: agregar un servidor/servicio nuevo a armada.do

1. Crear túnel: `curl -X POST https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel -d '{"name":"<nombre>","config_src":"cloudflare"}'` (token de cuenta SÍ puede)
2. Setear ingress: `PUT /accounts/{id}/cfd_tunnel/{tunnel_id}/configurations` con `{"config":{"ingress":[{"hostname":"<sub>.armada.do","service":"http://localhost:<puerto>"},{"service":"http_status:404"}]}}`
3. En el servidor nuevo: instalar cloudflared + `sudo cloudflared service install "<TOKEN_DEL_TUNEL>"` (GET /cfd_tunnel/{id}/token — `.result` es string)
4. DNS: `cloudflared tunnel route dns --overwrite-dns <tunnel_id> <sub>.armada.do` (usa cert.pem de `~/.cloudflared/`)
5. Verificar: `curl https://<sub>.armada.do/health` y estado del túnel (`GET /cfd_tunnel/{id}` → status healthy)

## Herramienta principal: wrangler 4.x

Instalado globalmente (`npm i -g wrangler`). Autenticación vía `CLOUDFLARE_API_TOKEN`.

Comandos principales (prefijo `wrangler`):
- `wrangler whoami` — ver usuario/cuenta/token activo
- `wrangler deploy [path]` — desplegar Worker
- `wrangler dev [script]` — desarrollo local
- `wrangler delete [name]` — eliminar Worker
- `wrangler versions`, `wrangler deployments`, `wrangler rollback [id]` — versionado
- `wrangler tail [worker]` — logs en vivo
- `wrangler secret put <name>` — secretos de Worker
- `wrangler r2 bucket list|create|delete <name>` — R2 (requiere activar R2 antes)
- `wrangler r2 object get|put|delete <bucket> <key>` — objetos R2
- `wrangler d1 list|create|execute` — bases D1
- `wrangler kv namespace list|create` — KV (el token puede no tener permiso)
- `wrangler queues`, `wrangler workflows`, `wrangler vectorize` — colas y más
- `wrangler pages` — Pages
- `wrangler ai` — Workers AI
- `wrangler tunnel` — túneles (experimental; preferir cloudflared)
- `wrangler email` — Email Routing
- `wrangler complete zsh` — completions (una vez, luego funciona)

Nota: este wrangler 4.119 NO incluye comandos de DNS ni zonas → usar API v4 (abajo).

## API v4 directa (DNS, zonas, todo lo demás)

Usar `curl` + `jq` con el token. Endpoint base: `https://api.cloudflare.com/client/v4`.

Auth: `-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"`

### Zonas
```sh
# Listar zonas de la cuenta
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result[] | "\(.id) \(.name) \(.status)"'
```

### DNS (records de armada.do o micaserogou.com)
```sh
# Obtener zone_id: usar el listado de zonas y el .result[].id correspondiente
ZONE_ID="<id de la zona>"

# Listar registros DNS
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[] | {name, type, content, proxied, ttl, id}'

# Crear registro (ejemplo A record)
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  --data '{"type":"A","name":"subdominio","content":"1.2.3.4","proxied":true}' | jq .

# Actualizar registro (PUT con id del record)
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  --data '{"type":"A","name":"subdominio","content":"5.6.7.8","proxied":true}' | jq .

# Eliminar
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq .
```

### Configuración de zona (SSL, caché, seguridad)
- **SSL por zona (2026-08-07)**: `armada.do` y `micaserogou.com` = **strict** (PATCH 2026-08-06; antes flexible); `taohemps.com` = **full**. Con strict, TODO origin proxied debe servir 443 con cert válido (ver "Reglas aprendidas" — caso erpipos).
- **WAF Managed Free Ruleset DEPLOYADO en ambas zonas** (2026-08-06): plan Free usa el ruleset **`77454fe2d30c4220b5701f6fdfb893ba`** ("Cloudflare Managed Free Ruleset"), NO el ID estándar `efb7b8c949ac4650a09736fc376e9aee` (da error "not entitled"). Deploy: PUT /zones/{id}/rulesets/phases/http_request_firewall_managed/entrypoint `{"rules":[{"action":"execute","action_parameters":{"id":"77454fe2d30c4220b5701f6fdfb893ba"},"expression":"true","description":"Execute Cloudflare Managed Free Ruleset"}]}`. Verificar: GET .../entrypoint → 1 regla execute
- **Bot Fight Mode: NO tiene API en plan Free** ("Method not allowed"/sin endpoint /bots) → solo dashboard, 2 clics
- **R2: NO USAR (decisión 2026-08-07)** — usuario descartó el servicio; backups locales en NAS jonas (disco sdb). Ignorar error 10042.

```sh
# Ver ajustes de la zona
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[] | {id, value}'

# Cambiar un ajuste (ej: ssl a "full")
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  --data '{"value":"full"}' | jq .
```

### Otros endpoints útiles (documentación completa: https://developers.cloudflare.com/api)
- `/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts` — listar Workers
- `/user/tokens/verify` — verificar token ⚠️ **con token de cuenta da SIEMPRE "Invalid API Token" (error 1000): ES NORMAL, el token es de alcance CUENTA, no de usuario. No es un fallo.**
- `/user` — información de usuario (igual: no accesible con token de cuenta)
- `/accounts/$CLOUDFLARE_ACCOUNT_ID/tokens` — listar tokens de la cuenta ✅ (funciona con token de cuenta)
- `/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?is_deleted=false` — listar túneles ✅
- `/zones/$ZONE_ID/analytics/dashboard` — analytics
- `/zones/$ZONE_ID/firewall/rules` — reglas firewall (también WAF)

## R2 vía S3 (NO USAR — descartado 2026-08-07, ver arriba)

Endpoints S3 compatibles en `$R2_ENDPOINT` con `$R2_ACCESS_KEY_ID` / `$R2_SECRET_ACCESS_KEY`.
Se puede usar con `aws cli --endpoint-url` o `rclone`. Alternativa nativa: `wrangler r2`.

## Reglas de seguridad

1. NUNCA imprimir `CLOUDFLARE_API_TOKEN`, `R2_SECRET_ACCESS_KEY`, `VICTORIA_API_KEY` ni tokens de túnel en respuestas ni logs.
2. Si un comando falla con "Unauthorized"/403, verificar que se cargaron las env.
3. Operaciones destructivas (delete, overwrite, rollback) → confirmar antes con el usuario.
4. No subir el archivo `~/.config/cloudflare/env` a ningún repositorio.
5. **Pendiente de privacidad**: el router Comcast aún tiene port-forward `443 → 10.0.0.5` (ya innecesario con el túnel). Recomendado eliminarlo del router para ocultar el origin por completo. En ufw del servidor: 4000 y 443 deberían restringirse a LAN/127.0.0.1 (el tráfico externo ya entra solo por túnel).
6. La IP pública del origin (`69.143.73.120` y rango IPv6 `2601:152:1580:92d0::/64`) solo debe aparecer en los registros DDNS del WG (`home.armada.do`/`victoria.armada.do`, grises, gestionados por el updater de jonas). Para servicios web: SIEMPRE CNAME → cfargotunnel.com.

## Sistema de agentes Cloudflare (mapa)

Esta skill es parte de un sistema de agentes. El agente principal es `cloudflare` (primary) y delega en subagentes:

| Agente | Modo | Rol |
|---|---|---|
| `cloudflare` | primary | Coordinador: decide, delega, verifica, responde |
| `cf-dns` | subagent | DNS y zonas de armada.do / micaserogou.com / taohemps.com |
| `cf-workers` | subagent | Workers/Pages: deploy, versiones, rollback, tail, secrets, CRON |
| `cf-storage` | subagent | KV, D1, Queues (R2: NO usar) |
| `cf-security` | subagent | SSL, WAF, bot mgmt, tokens, firewall, certificados |
| `cf-tunnels` | subagent | Túneles cloudflared, ingress, conectividad |

Archivos de contexto:
- **Mapa completo**: `~/.config/opencode/cloudflare-map/MAPA.md` (tabla, protocolo, fallos conocidos)
- **Inventario de la cuenta** (estado verificado): `~/.config/opencode/cloudflare-map/INVENTARIO.md`
- **Comando** `/mapa` — muestra el mapa en cualquier conversación

Actualizar `INVENTARIO.md` cada vez que cambie el estado de la cuenta (nuevo worker, zona, token, record, túnel).
