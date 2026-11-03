#!/usr/bin/env python3
"""whois-server: daemon del host que ejecuta `whois` para el sandbox OpenClaw.

El sandbox NO puede instalar whois (apt roto) ni salir por el puerto TCP 43
(proxy L7 solo permite 80/443). Este servicio corre en el host (apt sano,
puerto 43 abierto) y expone el whois por HTTP al sandbox.

Endpoints:
  GET /health                  -> {"ok": true}
  GET /whois?domain=example.com -> texto whois del dominio (o 400/502)

Seguridad:
  - Filtro de red: solo 127.0.0.1, red docker (172.18.0.0/16, 172.17.0.0/16) y LAN 10.x
  - Auth 2026-09-17: localhost/docker sin llave; LAN exige llave gateway
    admin/services (mismo esquema que voz/video/nav)
  - Validacion del dominio con regex (nada de inyeccion)
  - subprocess con lista de args (sin shell)
  - Timeout 30s por consulta

Patron: identico a victoria-video-server.py (video :18811) y voice-server (:18810).
Unit: victoria-whois-server.service
"""
import ipaddress
import json
import re
import subprocess
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, "/home/victoria")
import sense_auth

HOST = "0.0.0.0"
PORT = 18830
TIMEOUT = 30
MAX_DOMAIN_LEN = 253

# Redes permitidas: localhost, docker bridges del host, LAN domestica
ALLOWED_NETS = [
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),   # docker (172.17, 172.18, 172.22...)
    ipaddress.ip_network("10.0.0.0/8"),      # LAN domestica
]

# Solo dominios/hosts validos: letras, digitos, guiones, puntos (IDN punycode ok)
DOMAIN_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$")


def log(msg):
    print(msg, flush=True)


def is_allowed(client_ip):
    try:
        ip = ipaddress.ip_address(client_ip)
    except ValueError:
        return False
    return any(ip in net for net in ALLOWED_NETS)


def run_whois(domain):
    """Ejecuta whois(1) del host contra el dominio. Devuelve (texto, error)."""
    try:
        proc = subprocess.run(
            ["/usr/bin/whois", domain],
            capture_output=True, text=True, timeout=TIMEOUT,
        )
        out = proc.stdout or ""
        err = proc.stderr or ""
        if proc.returncode != 0 and not out:
            return "", f"whois salio con codigo {proc.returncode}: {err.strip()[:300]}"
        return out, None
    except subprocess.TimeoutExpired:
        return "", f"timeout de {TIMEOUT}s consultando whois de {domain}"
    except Exception as e:  # noqa: BLE001
        return "", f"error ejecutando whois: {e}"


def rdap_looks_like_failure(whois_text):
    """El whois generico no soporta algunos TLDs (.pro, .travel, etc.): el
    output dice 'TLD is not supported' / 'TLD not supported' / 'no match' sin
    datos utiles. RDAP (RFC 7480) es el estandar moderno sobre HTTPS y cubre
    esos casos."""
    low = whois_text.lower()
    return (
        "tld is not supported" in low
        or "tld not supported" in low
        or ("no match" in low and "registrar" not in low)
        or whois_text.strip() == ""
    )


def run_rdap(domain):
    """Consulta RDAP (https://rdap.org/domain/<dominio>) como fallback cuando
    el whois generico no soporta el TLD. rdap.org redirige al registry correcto.
    Devuelve (texto_formateado, error)."""
    url = f"https://rdap.org/domain/{domain}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "victoria-whois-server/1.0"})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "", "dominio no encontrado en RDAP (no registrado o TLD no soportado)"
        return "", f"RDAP HTTP {e.code}"
    except Exception as e:  # noqa: BLE001
        return "", f"RDAP error: {e}"

    lines = [f"Domain Name: {data.get('ldhName', domain).upper()}"]
    # eventos: registration, expiration, last changed
    events = {}
    for ev in data.get("events", []):
        kind = ev.get("eventAction", "")
        if kind in ("registration", "expiration", "last changed"):
            events[kind] = ev.get("eventDate", "")
    if events.get("registration"):
        lines.append(f"Creation Date: {events['registration']}")
    if events.get("expiration"):
        lines.append(f"Registry Expiry Date: {events['expiration']}")
    if events.get("last changed"):
        lines.append(f"Updated Date: {events['last changed']}")
    # entidades (registrar)
    for ent in data.get("entities", []):
        roles = ent.get("roles", [])
        if "registrar" in roles:
            vcard = ent.get("vcardArray", [])
            if len(vcard) > 1:
                for item in vcard[1]:
                    if item[0] == "fn":
                        lines.append(f"Registrar: {item[3]}")
    # status
    for st in data.get("status", []):
        lines.append(f"Domain Status: {st}")
    # nameservers
    for ns in data.get("nameservers", []):
        ldh = ns.get("ldhName", "")
        if ldh:
            lines.append(f"Name Server: {ldh.upper()}")
    # secureDNS
    if "secureDNS" in data:
        sec = data["secureDNS"]
        if isinstance(sec, dict) and sec.get("delegationSigned"):
            lines.append("DNSSEC: signed")
        else:
            lines.append("DNSSEC: unsigned")
    # url de la ficha
    links = data.get("links", [])
    for ln in links:
        href = ln.get("href", "")
        if href and "rdap.org" not in href:
            lines.append(f"RDAP Record: {href}")
            break
    lines.append("")
    lines.append("(via RDAP - whois generico no soporta este TLD)")
    return "\n".join(lines), None


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8", errors="replace") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _deny(self, code=403, msg="forbidden"):
        self._send(code, msg)

    def do_GET(self):
        client_ip = self.client_address[0] if self.client_address else ""
        if not is_allowed(client_ip):
            log(f"DENY {client_ip} {self.path}")
            self._deny(403, "forbidden: ip no permitida")
            return

        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send(200, '{"ok": true}', "application/json")
            return

        if parsed.path == "/whois":
            ip = sense_auth.norm_ip(client_ip)
            if not sense_auth.is_trusted(ip):
                if not (sense_auth.is_lan(ip) and sense_auth.sense_role(self.headers)):
                    self._deny(401, "unauthorized: se requiere llave gateway admin/services (o red local/docker)")
                    return
            qs = parse_qs(parsed.query)
            domain = (qs.get("domain") or [""])[0].strip().lower()
            if not domain:
                self._deny(400, "parametro 'domain' requerido")
                return
            if len(domain) > MAX_DOMAIN_LEN or not DOMAIN_RE.match(domain):
                self._deny(400, f"dominio invalido: {domain}")
                return
            log(f"WHOIS {client_ip} {domain}")
            text, err = run_whois(domain)
            if err:
                self._deny(502, err)
                return
            # Fallback RDAP si el whois generico no soporta el TLD
            if rdap_looks_like_failure(text):
                log(f"WHOIS fallback RDAP {domain}")
                rdap_text, rdap_err = run_rdap(domain)
                if not rdap_err:
                    self._send(200, rdap_text)
                    return
                log(f"RDAP fallback fallo para {domain}: {rdap_err}")
            self._send(200, text)
            return

        self._deny(404, "not found")

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} - {fmt % args}")


def main():
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    log(f"whois-server escuchando en {HOST}:{PORT} (whois del host, filtro de red)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()