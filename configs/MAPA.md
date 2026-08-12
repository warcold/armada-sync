# 🗺️ MAPA DE AGENTES — Sistema Cloudflare de Alfredo@armada.do

> **Para qué es esto**: este es el mapa maestro del sistema. Cada vez que interactúes con el agente Cloudflare, él debe conocer este mapa. Si no lo ves al inicio de la conversación, pídelo con `/mapa`.
>
> **Regla de oro**: el agente principal (primary) NO ejecuta operaciones él mismo — delega a los subagentes según la tabla. Los subagentes ejecutan, el principal coordina y verifica.

---

## Cómo funciona todo (visión general)

```
TÚ (Alfredo/warcold)
   │
   ▼
┌────────────────────────────────────────────┐
│ AGENTE PRINCIPAL: cloudflare (primary)     │
│ Coordina, decide qué subagente usar,       │
│ verifica resultados, responde al usuario   │
└────────────────────────────────────────────┘
   │
   ├──► cf-dns         → DNS, zonas, records (armada.do / micaserogou.com / taohemps.com)
   ├──► cf-workers     → Workers, Pages, CRON, secrets
   ├──► cf-storage     → KV, D1, Queues (R2: NO USAR — desactivado)
   ├──► cf-security    → SSL, WAF, firewall, bot mgmt, tokens, certificados
   └──► cf-tunnels     → Túneles Cloudflare, conectividad, ingress
```

Todos los agentes comparten la misma base de conocimiento:
- Skill `cloudflare` → `~/.config/opencode/skill/cloudflare/SKILL.md` (comandos, API, estado validado)
- Inventario de la cuenta → `~/.config/opencode/cloudflare-map/INVENTARIO.md` (estado verificado 2026-08-07)
- Este mapa → `~/.config/opencode/cloudflare-map/MAPA.md`

## Tabla de agentes

| Agente | Modo | Responsabilidad | Delegar cuando... |
|---|---|---|---|
| **cloudflare** | primary | Coordinador general. Carga env, verifica whoami, consulta skill+mapa, delega, verifica, resume | — (es el principal) |
| **cf-dns** | subagent | DNS de las 3 zonas: listar/crear/actualizar/borrar records, ver zonas, settings de zona | "crea un registro", "cambia el A de X", "cómo está el DNS de...", migraciones de zona |
| **cf-workers** | subagent | Workers/Pages: deploy, versiones, rollback, tail, secrets, CRON | "despliega el worker", "tail al worker", "agrega un secret" |
| **cf-storage** | subagent | KV namespaces, D1 databases, Queues. **R2: NO tocar (descartado 2026-08-07)** | "crea un KV", "haz una query D1", "revisa las colas" |
| **cf-security** | subagent | SSL modes, WAF Managed Free Ruleset, bot mgmt (dashboard), tokens, certificados, reglas firewall | "revisa el SSL", "despliega el WAF", "haz inventario de tokens" |
| **cf-tunnels** | subagent | Túneles cloudflared, ingress, estados, DNS del túnel, conectividad | "estado del túnel", "agrega un hostname al túnel", "reinicia el túnel" |

## Protocolo de operación (todos los agentes)

1. **SIEMPRE** cargar credenciales primero: `set -a && source ~/.config/cloudflare/env && set +a`
2. **SIEMPRE** confirmar autenticación: `wrangler whoami` (debe decir "Alfredo@armada.do's Account")
3. Consultar la skill `cloudflare` (estado validado + reglas aprendidas) y el `INVENTARIO.md` si aplica
4. Usar `wrangler` para Workers/Pages/R2/D1/KV/Queues/Secrets; API v4 con `curl`+`jq` para DNS/zonas/firewall/settings
5. **NUNCA** mostrar tokens, secret keys ni valores de credenciales en el chat
6. Error 403/Unauthorized → verificar env cargadas y que se usa `$CLOUDFLARE_ACCOUNT_ID`
7. Operaciones destructivas (borrar worker/record/bucket/rollback) → **confirmar con el usuario y mostrar exactamente qué se elimina**
8. Verificar SIEMPRE después de modificar (listar tras crear, `wrangler deployments` tras deploy)
9. Resultados legibles: filtrar con `jq`, responder en tablas/texto breve
10. Si algo cambia en la infraestructura → actualizar `INVENTARIO.md` y el `AGENTS.md` del sistema en `ops/agents/` (regla de la casa)

## Fallos conocidos y cómo tratarlos

| Síntoma | Causa | Acción |
|---|---|---|
| `/user` o `/user/tokens/verify` → "Invalid API Token" | Token es de alcance CUENTA, no de usuario | **Normal**. No es fallo. Proceder con operaciones de cuenta/zona |
| R2 → error 10042 | R2 no activado (descartado por el usuario 2026-08-07) | Informar, NO proponer activar R2 |
| WAF Managed Ruleset da "not entitled" | Plan Free usa el ruleset `77454fe2d30c4220b5701f6fdfb893ba`, no el estándar | Usar el ID Free (documentado en skill) |
| Bot Fight Mode no tiene API en plan Free | Solo dashboard | Indicar al usuario: 2 clics en dashboard |
| 403 en DNS de zona con token de cuenta | Token de cuenta tiene DNS Edit all zones (OK); si falla usar `$CLOUDFLARE_DNS_TOKEN` | Verificar token correcto |
| `api.x.armada.do` no funciona (SSL handshake) | Universal SSL gratis no cubre subdominios de 2 niveles | Usar `x-api.armada.do` |
| A proxied a origin sin 443 con SSL=strict | Cloudflare exige HTTPS al origin | Emitir LE en origin (grisar temporalmente, volver a naranja) |

## Zonas y datos de referencia rápida

- Account ID: `432949306735261bec2ca45a0a2719c7`
- armada.do → `17badff7f918b4e02eea8533fac4dc9f` (SSL strict)
- micaserogou.com → `fdebf4707c11ec49d9a73204457ba19c` (SSL strict)
- taohemps.com → `080b3e78b1b420f477009c5374652103` (SSL full, NO tocar DNS de correo)
- Túnel único: rootsource-local `17f5ad45-fb7c-4ddd-a8c6-9c59b2f90160` → rootsource.armada.do → localhost:4000
- Tokens: spring-dream-d681 (cuenta=env), opencode-dns-cleanup (DNS=env), erpipos-server-dns, damp-surf-3478-fusion (sin uso)

## Mantenimiento del mapa

- Cada vez que se cree/borre un agente, actualizar la tabla de este archivo
- Cada vez que cambie el estado de la cuenta, actualizar `INVENTARIO.md` con la fecha de verificación
- Este mapa debe aparecer en la conversación cuando el usuario lo pida (`/mapa`) o cuando el contexto lo requiera
