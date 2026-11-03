---
name: domain
description: "Analiza dominios por petición del usuario: whois (registrante, fechas de creación/expiración, nameservers, estado) y datos de registro RDAP. Usa el wrapper whois del host."
---

# Análisis de dominios (whois / RDAP)

Cuando el usuario pide **whois**, **analizar un dominio**, saber quién registró un
dominio, fechas de expiración, nameservers, estado del registro, disponibilidad
de un dominio, etc., usa el wrapper `whois`.

## Comando

```bash
/sandbox/.openclaw/bin/whois <dominio>
```

- El whois corre EN EL HOST (servicio `victoria-whois-server`, whois 5.5.22).
  No puedes instalar whois en el sandbox (apt roto + puerto TCP 43 bloqueado),
  pero el wrapper lo resuelve vía bridge UNIX socket.
- **Usa SIEMPRE la ruta completa** `/sandbox/.openclaw/bin/whois` (el PATH del
  entorno de exec no incluye `/sandbox/.openclaw/bin`).
- Devuelve el registro del dominio en texto plano (whois clásico) o, si el
  whois genérico no soporta el TLD (`.pro`, `.travel`, etc.), devuelve los
  datos vía **RDAP** (RFC 7480) con la misma estructura.

## Cómo interpretar el output

Extrae y reporta al usuario los campos clave:

| Campo | Qué significa |
|---|---|
| **Domain Name** | El dominio consultado |
| **Registrar** | Quién gestiona el registro (ej. GoDaddy.com, LLC) |
| **Creation Date** | Fecha en que se registró el dominio |
| **Registry Expiry Date** | Fecha de expiración (si pasó → el dominio expiró/renovó) |
| **Updated Date** | Última actualización del registro |
| **Name Server** | Servidores DNS del dominio (puede haber 2+) |
| **Domain Status** | Estado (ok, clientTransferProhibited, clientDeleteProhibited…) |
| **DNSSEC** | signed / unsigned (seguridad DNS) |

## Cómo responder

1. **Ejecuta** `/sandbox/.openclaw/bin/whois <dominio>`.
2. Si el output tiene el registro → responde con un **resumen claro y breve**
   en el idioma del usuario: registrar, fecha de creación, fecha de expiración,
   nameservers, estado. Añade contexto útil (ej. "el dominio está activo",
   "expira en X meses", "está en GoDaddy").
3. Si dice "No match for domain" / "not found" / "domain not found" → el
   dominio **no está registrado** (o está libre): dilo y ofrece sugerir
   alternativas o verificar la disponibilidad.
4. Si el output es un error de conexión → intenta de nuevo una vez; si persiste,
   avisa que el servicio whois está temporalmente no disponible.
5. Respeta el idioma del usuario (es→es, en→en). No menciones la infraestructura
   interna (bridges, servidores) — solo el resultado del análisis.