# devices.md — Registro de dispositivos del hogar (2026-09-30)

> Inventario LAN para saber a dónde llegan nuestras máquinas y con qué acceso.
> Descubrimiento pasivo (`ip neigh`, sin escaneo agresivo). Actualizar al detectar cambios.
> Accesos con secreto van por env/archivo 600, NUNCA en este archivo.

## Conocidos

| IP | Host | Rol | Acceso Victoria→ello | Notas |
|---|---|---|---|---|
| `10.0.0.1` | router | gateway LAN | — | — |
| `10.0.0.5` | victoria.local (DGX Spark) | inferencia+contenido+OpenClaw | local | este host |
| `10.0.0.106` | kalimete.local | dev/ethical, laptop roaming | `ssh -i ~/.ssh/id_victoria -p 1111 warcold@kalimete.local` | providers `vllm` (P) + `vllm-lan` (L); principal `kalimete` + 19 hide; contrato flota: TARGET explícito + scopes separados (ver victoria.md) |

## Por identificar (vistos en ARP, sin rol confirmado)

| IP | MAC | Estado |
|---|---|---|
| `10.0.0.102` | `d4:f9:21:b7:cd:6a` | STALE |
| `10.0.0.134` | `a8:b1:3b:e5:58:4d` | STALE |
| `10.0.0.29` | `1c:61:b4:16:8d:e9` | STALE |
| `10.0.0.230` | `da:be:87:6d:65:c3` | STALE |
| `10.0.0.64` | `34:5a:60:c5:a9:4c` | STALE |

- Papá: dime qué son (teles, impresoras, laptops, IoT) y los registro con su rol.
- Si alguno debe consumir inferencia/voz de Victoria, se le da key `coder`/`services` temporal + su `config-guide`, igual que el flujo de kalimete.

## Servicios que pueden consumir otros dispositivos (todos LAN, con llave gateway)

- LLM: `http://victoria.local:8010/v1` (+ `/v1/config-guide` para auto-configurarse)
- Voz TTS/STT: `http://victoria.local:18810` (requiere llave admin/services en LAN)
- UIs (solo LAN, sin túnel): `/comfyui/`, `/liveportrait/`, `/n8n/`, `/openclaw/` vía `https://victoria.local/`
