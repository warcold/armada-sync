# INVENTARIO — Cuenta Cloudflare de Alfredo@armada.do

> **Última verificación completa: 2026-08-14** (recolectado vía API v4 con el token de cuenta)
> Este archivo es la fuente de verdad del ESTADO de la cuenta. Si algo cambia, actualízalo.

---

## 1. Identidad

| Campo | Valor |
|---|---|
| Cuenta | **Alfredo@armada.do's Account** |
| Account ID | `432949306735261bec2ca45a0a2719c7` |
| Máquina principal (origen) | **kalimete** (usuario `warcold` = Alfredo Armada), host 10.0.0.106 |
| Máquina de trabajo de este agente | la máquina local de warcold (kalimete) |
| Herramientas | `wrangler` 4.119.0 (global) + API v4 con `curl`/`jq` |

## 2. Zonas (3 activas) — verificadas 2026-08-14

| Zona | Zone ID | Status | SSL mode |
|---|---|---|---|
| **armada.do** | `17badff7f918b4e02eea8533fac4dc9f` | active | **strict** |
| **micaserogou.com** | `fdebf4707c11ec49d9a73204457ba19c` | active | **strict** |
| **taohemps.com** | `080b3e78b1b420f477009c5374652103` | active | **full** (migrada 2026-08-07) |

> SSL strict = todo origin proxied debe servir HTTPS:443 con cert válido (ver reglas aprendidas en skill).
> taohemps.com es la zona de banahosting migrada; su DNS de correo (autoconfig/autodiscover/cpanel/webmail/whm/MX/SRV/DKIM/DMARC/SPF) NO se toca.
>
> **WAF Managed Free Ruleset** (`77454fe2d30c4220b5701f6fdfb893ba`): desplegado en **armada.do** y **micaserogou.com** (2026-08-06). **taohemps.com: NO desplegado (verificado 2026-08-14)** — pendiente si el usuario lo pide.

## 3. Recursos de la cuenta (verificados 2026-08-14)

| Recurso | Estado | Notas |
|---|---|---|
| Workers | **0 desplegados** | lista vacía — cuenta sin Workers |
| Pages projects | **0** | — |
| KV namespaces | **0** | — |
| D1 databases | **0** | — |
| Queues | **0** | — |
| Workflows | **0** | — |
| R2 buckets | **DESACTIVADO** | error 10042 (R2 no activado; decisión 2026-08-07: NO usar R2, backups en NAS jonas) |
| Túneles | **1: `victoria-armada`** | ID `d9abe241-fcbb-40a6-9202-36d0cfa7a95a`, **healthy, 4 conexiones** (verificado 2026-08-13) |
| Tokens API | **4 activos** (ver §4) | listados con el token de cuenta |

## 4. Tokens API (inventario verificado 2026-08-14 — sin cambios desde 08-07)

| ID | Nombre | Alcance / Uso |
|---|---|---|
| `b9076e84545b65db035dc7328d0c5286` | **opencode-dns-cleanup** | DNS Read/Write armada.do → `$CLOUDFLARE_DNS_TOKEN` (en uso por DDNS de jonas, cron */5 — NO borrar) |
| `4142d2e99b73d6873262a263cf125b50` | **spring-dream-d681** | Token de CUENTA → `$CLOUDFLARE_API_TOKEN`. Hace TODO: túneles, workers, DNS Edit all zones, settings SSL, bot mgmt, crear zonas |
| `6d9959e277ae228473ff5562358953f7` | **erpipos-server-dns** | DNS+SSL en armada.do y micaserogou.com (en uso por el server erpipos) |
| `d9a90759bbc5f7e5cba11b06ac7c091a` | **damp-surf-3478-fusion** | DNS armada.do — SIN uso desde 27-jul → candidato a borrar (confirmar con usuario) |

### Alcances probados del token de cuenta (spring-dream-d681) — 2026-08-07

| Operación | Resultado |
|---|---|
| `wrangler whoami` | ✅ Cuenta OK |
| Listar zonas (3) | ✅ |
| Leer settings SSL de cada zona | ✅ |
| Listar DNS records (3 zonas) | ✅ |
| Listar Workers / KV / D1 / Queues / Pages / Workflows | ✅ (vacío) |
| Listar túneles + estado | ✅ (victoria-armada healthy, 4 conexiones — verificado 2026-08-13) |
| Listar tokens de la cuenta | ✅ (4 tokens) |
| Crear/borrar zona (sonda) | ✅ probado antes (prueba-invalida.com) |
| DNS create/edit/delete | ✅ (usado 2026-08-06 para cleanup) |
| `/user` y `/user/tokens/verify` | ❌ "Invalid API Token" — **ESPERADO**: el token es de alcance CUENTA, no de usuario |
| R2 buckets | ❌ error 10042 — R2 no activado (decisión: no usar) |

> ⚠️ `/user` y `/user/tokens/verify` fallan SIEMPRE con este token. NO es un bug del agente: los tokens account-scoped no tienen permisos de usuario. No insistir ni reportarlo como fallo.

## 5. Mapa DNS armada.do (verificado 2026-08-14, 35 records)

### A records
| Name | Content | Proxied |
|---|---|---|
| armada.do (root) | 66.225.201.198 | ✅ (cPanel email) |
| auth.armada.do | 154.53.35.102 | ✅ VPS prod |
| docuseal.armada.do | 154.53.35.102 | ✅ VPS prod |
| erpipos.armada.do | 147.93.6.112 | ✅ erpipos |
| home.armada.do | 69.143.73.120 | ❌ **DDNS WG** (TTL 120, updater jonas) |
| nextcloud.armada.do | 154.53.35.102 | ✅ VPS prod |
| pets.armada.do | 154.53.35.102 | ✅ VPS prod |
| proxy.us-east.armada.do | 31.220.102.176 | ❌ |
| ragnarok.armada.do | 154.53.35.102 | ✅ VPS prod |
| ragnarok.cp.armada.do | 154.53.35.102 | ✅ VPS prod |
| scriberr.armada.do | 154.53.35.102 | ✅ VPS prod |
| telecomm.armada.do | 207.244.236.223 | ❌ |
| *.telecomm.armada.do | 207.244.236.223 | ❌ wildcard |
| victoria.armada.do | — | ❌→✅ **2026-08-13: CNAME al túnel victoria-armada** (ver CNAME) |
| whiteboard.armada.do | 154.53.35.102 | ✅ VPS prod |
| whiteboard.nextcloud.armada.do | 154.53.35.102 | ❌ |
| woodly.armada.do | 154.53.35.102 | ✅ VPS prod |

### CNAME
| Name | Content | Notas |
|---|---|---|
| ftp.armada.do | armada.do | cPanel |
| mail.armada.do | armada.do | cPanel (SMTP apps) |
| **victoria.armada.do** | `d9abe241-....cfargotunnel.com` | **túnel victoria-armada** → :8010 (SÓLO API LLM con llaves; panel /admin da 403 vía túnel — panel solo LAN en **https://victoria.local/admin**) |
| www.armada.do | armada.do | — |

### Email/otros
- MX → armada.do (Cloudflare Email Routing `_dc-mx`... verificar: el MX apunta a armada.do)
- TXT: SPF (mailchannels), DMARC p=none, DKIM default._domainkey, caldav/carddav SRVs (cPanel), `_acme-challenge` (cPanel LE)
- SRV: _autodiscover, _caldav(s), _carddav(s) → cPanel

## 6. Mapa DNS micaserogou.com (verificado 2026-08-14, 27 records)

### A records
| Name | Content | Proxied |
|---|---|---|
| micaserogou.com (root) | 154.53.35.102 | ✅ VPS prod |
| erpipos.micaserogou.com | 147.93.6.112 | ✅ erpipos |
| autoconfig / autodiscover / cpanel / cpcalendars / cpcontacts / webdisk / webmail / whm | 66.225.201.198 | ❌ cPanel email |

### CNAME
- www → micaserogou.com (✅ proxied), ftp → micaserogou.com, mail → micaserogou.com

### Email/otros
- MX → micaserogou.com, TXT: **2 SPF duplicados** (uno con mailchannels, otro simple), DMARC, DKIM, SRVs cPanel

## 7. Mapa DNS taohemps.com (verificado 2026-08-14, 27 records)

- A root → 154.53.35.102 (✅ proxied) + cPanel records (66.225.201.198, ahora **proxied**)
- CNAME www/ftp/mail → taohemps.com
- **NO TOCAR**: autoconfig/autodiscover/cpanel/webmail/whm/MX/SRV/DKIM/DMARC/SPF de correo banahosting
- ⚠️ WAF Managed Free Ruleset **NO desplegado** en esta zona (verificado 2026-08-14)

## 8. Infraestructura relacionada (recordatorio — detalle en skill cloudflare)

- **VPS prod** `vps-preprod`: 154.53.35.102 (auth.armada.do) — Docker + caddy, firewall DOCKER-USER solo rangos CF
- **erpipos**: 147.93.6.112 — nginx con LE
- **kalimete** (esta máquina): 10.0.0.106, dev apps solo `.local`
- **victoria**: 10.0.0.5 — GPU GB10, vLLM :8000, victoria-llm-gateway :8010 (loopback), túnel victoria.armada.do → :8010 (solo API LLM); RDP headless :3389; panel admin https://victoria.local/admin (nginx TLS). **ComfyUI NO existe; OpenClaw :18789 NO responde; voz ELIMINADA (2026-08-14)**
- **jonas**: 10.0.0.20 — NAS backups + DDNS updater + dnsmasq + WireGuard server
- **Windows Alfredo**: 10.0.0.64 (cliente RDP; la victoria vieja ya no existe)
- WireGuard: jonas=10.0.100.1, kalimete=10.0.100.2, vps=10.0.100.3; Endpoint `home.armada.do:51820`
- ⚠️ **OJO DDNS**: el updater de jonas actualiza `home.armada.do` (A) y ANTES también `victoria.armada.do` — desde 2026-08-13 `victoria.armada.do` es CNAME del túnel; si el updater recrea el A lo pisa (verificar en jonas cuando el SSH se arregle)
- ⚠️ **Registros obsoletos no documentados (2026-08-14)**: `proxy.us-east.armada.do` (31.220.102.176, gris), `telecomm.armada.do` + `*.telecomm.armada.do` (207.244.236.223, gris), `whiteboard.nextcloud.armada.do` (gris). Sin uso documentado → candidatos a revisar/borrar con confirmación del usuario.
- ⚠️ **SPF duplicado en micaserogou.com**: persisten 2 registros SPF (uno con mailchannels, otro simple) — no tocar sin confirmación.

## 9. Cómo actualizar este inventario

1. Cargar env + verificar: `set -a && source ~/.config/cloudflare/env && set +a && wrangler whoami`
2. Recolectar: zonas, DNS de cada zona, workers, kv, d1, r2, queues, túneles, tokens (comandos en la skill cloudflare)
3. Actualizar este archivo con la fecha de verificación
4. Actualizar el AGENTS.md correspondiente en `ops/agents/` si el cambio afecta a un sistema (regla de la casa)
