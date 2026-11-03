---
name: admin
description: "Acceso seguro a herramientas y servicios del HOST: ejecutar dig/host/curl/whois/nslookup/jq/ping/openssl, instalar paquetes apt permitidos, y gestionar servicios del stack. Usa el wrapper admin-cli."
---

# Herramientas del host (admin-cli)

Cuando necesites **herramientas que no existen en el sandbox** — resolver DNS
(`dig`), ver cabeceras HTTP (`curl -I`), consultar whois, validar certificados
(`openssl`), parsear JSON (`jq`), etc. — o **instalar un paquete** o **gestionar
un servicio**, usa el wrapper `admin-cli`. El trabajo corre EN EL HOST (servicio
`victoria-host-admin`), con allowlist y auditoría.

## Comando

```bash
/sandbox/.openclaw/bin/admin-cli status
/sandbox/.openclaw/bin/admin-cli exec <tool> [args...]
/sandbox/.openclaw/bin/admin-cli apt <package>
/sandbox/.openclaw/bin/admin-cli service <status|is-active|start|stop|restart> <service>
```

- **Usa SIEMPRE la ruta completa** `/sandbox/.openclaw/bin/admin-cli` (el PATH del
  entorno de exec no incluye `/sandbox/.openclaw/bin`).

## Tools permitidas (exec)

`dig`, `host`, `nslookup`, `curl`, `whois`, `jq`, `ping`, `openssl`

Ejemplos útiles:
- `admin-cli exec dig <dominio> +short` — IP(s) del dominio
- `admin-cli exec dig <dominio> MX +short` — servidores de correo
- `admin-cli exec dig <dominio> NS +short` — nameservers
- `admin-cli exec curl -sI <url>` — cabeceras HTTP de un sitio
- `admin-cli exec curl -s <url>` — contenido de una URL (puede ser largo)
- `admin-cli exec whois <dominio>` — registro whois del dominio
- `admin-cli exec openssl s_client -connect <host>:443 -servername <host> </dev/null 2>/dev/null | openssl x509 -noout -dates` — fechas del certificado TLS
- `admin-cli exec jq ...` — procesar JSON (menos común)

## Paquetes apt permitidos (apt)

`whois dnsutils jq curl netcat-openbsd traceroute openssl bind9-dnsutils
iputils-ping nmap unzip tree ripgrep htop tcpdump`

Usa `admin-cli apt <paquete>` SOLO si realmente necesitas una herramienta
nueva y no está instalada. El host lo instala (sudo, allowlist).

## Servicios permitidos (service)

Servicios del stack: `victoria-llm-gateway`, `victoria-voice-server`,
`victoria-video-server`, `victoria-whois-server`, `victoria-host-admin`,
`victoria-openclaw-bridge`, `cloudflared`, `nginx`, `armada-osint-api`, etc.
Acciones: `status`, `is-active`, `is-enabled`, `start`, `stop`, `restart`.

## Cómo responder

1. Ejecuta el comando admin-cli necesario.
2. Interpreta el output y responde al usuario en su idioma.
3. Para DNS: reporta las IPs o records encontrados. Para HTTP: status + headers
   clave (server, content-type). Para whois: registrar, fechas, nameservers.
4. NO menciones la infraestructura interna (bridges, host-admin) — solo el
   resultado. Si algo no está permitido, dilo y ofrece alternativas.