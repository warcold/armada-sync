#!/usr/bin/env python3
"""victoria-host-admin: Host Admin Bridge — daemon del host que da a Victoria
(agente OpenClaw del sandbox) acceso SEGURO a operaciones del host.

Por que existe:
  - El sandbox es EFIMERO y aislado: no puede instalar software de forma
    persistente (rebuild = reset) ni ejecutar binarios del host.
  - Todas las capacidades reales viven en el HOST (voice, video, whois, dig...).
  - Este servicio expone al sandbox un subset SEGURO de operaciones del host:
    ejecutar tools de red/CLI, instalar paquetes apt, y gestionar servicios.

Seguridad (disenada para no romper nada):
  - API key (X-API-Key) — generada en ~/.victoria-custom/secrets/admin-bridge.key
  - 2026-09-17: TAMBIEN acepta llaves del gateway :8010 con rol admin/services
    (misma llave de servicios que voz/video/nav/whois; el sandbox sigue usando
    su bridge key sin cambios)
  - Filtro de red: localhost, docker bridges, LAN 10.x (nunca publico)
  - ALLOWLIST estricta: solo binarios/paquetes/servicios explicitos
  - subprocess con lista de args (SIN shell) + validacion de args
  - Audit log de TODA operacion en /home/victoria/logs/victoria-host-admin.log
  - Timeout por operacion

Endpoints:
  GET  /health                  -> {"ok": true}
  GET  /status                  -> servicios activos + tools disponibles
  POST /exec    {tool, args[]}  -> ejecuta tool del host (allowlist)
  POST /apt/install {package}   -> apt-get install en host (allowlist)
  POST /service {name, action}  -> systemctl sobre servicio (allowlist)

Patron: identico a victoria-whois-server.py (:18830). Unit: victoria-host-admin.service.
"""
import hmac
import ipaddress
import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

sys.path.insert(0, "/home/victoria")
import sense_auth

HOST = "0.0.0.0"
PORT = 18840
TIMEOUT = 40
KEY_FILE = "/home/victoria/.victoria-custom/secrets/admin-bridge.key"
LOG_FILE = "/home/victoria/logs/victoria-host-admin.log"
AUDIT_FILE = "/home/victoria/logs/victoria-host-admin-audit.log"

ALLOWED_NETS = [
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),   # docker bridges (172.17, 172.18, 172.22...)
    ipaddress.ip_network("10.0.0.0/8"),      # LAN domestica
]

# Tools de CLI del host permitidas via /exec (solo lectura / red / diagnostico)
ALLOWED_EXEC = {
    "dig":       "/usr/bin/dig",
    "host":      "/usr/bin/host",
    "nslookup":  "/usr/bin/nslookup",
    "curl":      "/usr/bin/curl",
    "whois":     "/usr/bin/whois",
    "jq":        "/usr/bin/jq",
    "ping":      "/usr/bin/ping",
    "openssl":   "/usr/bin/openssl",
}

# Paquetes apt permitidos via /apt/install (herramientas de diagnostico/red)
ALLOWED_APT = {
    "whois", "dnsutils", "jq", "curl", "netcat-openbsd", "traceroute",
    "openssl", "bind9-dnsutils", "iputils-ping", "nmap", "unzip", "tree",
    "ripgrep", "htop", "tcpdump",
}

# Servicios del stack permitidos via /service
ALLOWED_SERVICES = {
    "victoria-llm-gateway", "victoria-gpu-saver", "victoria-voice-server",
    "victoria-video-server", "victoria-whois-server", "victoria-host-admin",
    "victoria-openclaw-bridge", "victoria-comfyui-models-mover",
    "victoria-comfyui-models-downloader", "web-nav-server", "cloudflared",
    "nginx", "docker",
}
ALLOWED_SERVICE_ACTIONS = {"status", "is-active", "is-enabled", "start", "stop", "restart"}

# Caracteres seguros para argumentos (tools de red/diagnostico)
ARG_RE = re.compile(r"^[a-zA-Z0-9._:/=?&%+@#\-,~\[\]{}()!*$'\"]{1,300}$")
PKG_RE = re.compile(r"^[a-z0-9][a-z0-9+.-]{1,60}$")
SVC_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{1,80}$")


def log(msg):
    print(msg, flush=True)


def audit(ip, endpoint, detail):
    try:
        with open(AUDIT_FILE, "a") as f:
            f.write(f"{ip} {endpoint} {detail}\n")
    except Exception:  # noqa: BLE001
        pass


def load_key():
    try:
        with open(KEY_FILE) as f:
            return f.read().strip()
    except Exception:  # noqa: BLE001
        return ""


API_KEY = load_key()


def is_allowed(client_ip):
    try:
        ip = ipaddress.ip_address(client_ip)
    except ValueError:
        return False
    return any(ip in net for net in ALLOWED_NETS)


def check_auth(handler, body):
    # 1) bridge key propia (la que usa el sandbox via admin-cli, sin cambios)
    provided = handler.headers.get("X-API-Key", "")
    if provided and API_KEY and hmac.compare_digest(provided, API_KEY):
        return True
    # 2) llave del gateway :8010 con rol ADMIN puro (2026-10-19: se endureció).
    #    ANTES (2026-09-17): admin/services con elevacion de caps — la llave
    #    kalimete (coder+art) y kalimete-ptt (services) podian operar el host
    #    desde LAN. Directiva del owner 2026-10-19: kalimete consume los
    #    RECURSOS de victoria (LLM/arte/TTS/3D via sus puertos), NUNCA opera
    #    la maquina (exec/apt/service). elevate=False mata la elevacion por
    #    caps; el rol services se retira de aqui (no hay consumidor legitimo:
    #    el sandbox usa la bridge key y el owner usa admin).
    role = sense_auth.sense_role(handler.headers, elevate=False)
    return role == "admin"


def run_cmd(cmd_list, timeout=TIMEOUT):
    """Ejecuta subprocess sin shell. Devuelve (code, stdout, stderr)."""
    try:
        proc = subprocess.run(
            cmd_list, capture_output=True, text=True, timeout=timeout,
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", f"timeout de {timeout}s"
    except Exception as e:  # noqa: BLE001
        return -1, "", str(e)


def exec_tool(tool, args):
    if tool not in ALLOWED_EXEC:
        return 400, f"tool no permitida: {tool}"
    if not isinstance(args, list) or len(args) > 20:
        return 400, "args debe ser lista de max 20 elementos"
    clean = []
    for a in args:
        if not isinstance(a, str) or not ARG_RE.match(a):
            return 400, f"arg invalido: {a!r}"
        clean.append(a)
    code, out, err = run_cmd([ALLOWED_EXEC[tool]] + clean)
    body = out
    if err and not out:
        body = f"ERROR ({code}): {err[:500]}"
    return 200, body


def apt_install(package):
    if package not in ALLOWED_APT:
        return 400, f"paquete no permitido: {package}"
    # sudo NOPASSWD de victoria
    code, out, err = run_cmd(["sudo", "-n", "apt-get", "install", "-y", "--no-install-recommends", package], timeout=300)
    tail = (out or "")[-800:]
    if code != 0:
        tail = (err or out or "")[-800:]
    return (200 if code == 0 else 502), tail


def service_action(name, action):
    if name not in ALLOWED_SERVICES:
        return 400, f"servicio no permitido: {name}"
    if action not in ALLOWED_SERVICE_ACTIONS:
        return 400, f"accion no permitida: {action}"
    if action in ("start", "stop", "restart") and name == "victoria-host-admin":
        return 400, "no se puede reiniciar el propio admin bridge desde si mismo"
    cmd = ["systemctl", action, name]
    if action in ("start", "stop", "restart"):
        cmd = ["sudo", "-n"] + cmd
    code, out, err = run_cmd(cmd, timeout=60)
    body = (out or err or f"exit {code}").strip()[-500:]
    return (200 if code == 0 else 502), body


class Handler(BaseHTTPRequestHandler):
    def _read_body(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length > 0 and length <= 65536:
            raw = self.rfile.read(length)
            try:
                return json.loads(raw)
            except Exception:  # noqa: BLE001
                return None
        return None

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body)
            ctype = "application/json"
        data = body.encode("utf-8", errors="replace")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _deny(self, code=403, msg="forbidden"):
        self._send(code, msg)

    def _handle(self, method):
        client_ip = self.client_address[0] if self.client_address else ""
        if not is_allowed(client_ip):
            log(f"DENY (red) {client_ip} {self.path}")
            self._deny(403, "forbidden: ip no permitida")
            return
        if not check_auth(self, None):
            log(f"DENY (auth) {client_ip} {self.path}")
            audit(client_ip, self.path, "AUTH_FAIL")
            self._deny(401, "unauthorized")
            return

        parsed = urlparse(self.path)
        if method == "GET" and parsed.path == "/health":
            self._send(200, {"ok": True})
            return
        if method == "GET" and parsed.path == "/status":
            # servicios activos + tools disponibles
            services = {}
            for s in sorted(ALLOWED_SERVICES):
                code, out, _ = run_cmd(["systemctl", "is-active", s], timeout=10)
                services[s] = out.strip() if out.strip() else f"exit{code}"
            tools = {}
            for t, path in ALLOWED_EXEC.items():
                tools[t] = os.path.exists(path)
            self._send(200, {"services": services, "tools": tools, "allowed_packages": sorted(ALLOWED_APT)})
            return
        if method != "POST":
            self._deny(405, "method not allowed")
            return

        body = self._read_body()
        if body is None:
            self._deny(400, "body JSON invalido")
            return

        if parsed.path == "/exec":
            tool = body.get("tool", "")
            args = body.get("args", [])
            code, out = exec_tool(tool, args)
            audit(client_ip, f"/exec {tool} {' '.join(map(str,args))[:200]}", f"->{code}")
            self._send(code, out)
            return
        if parsed.path == "/apt/install":
            pkg = body.get("package", "")
            if not PKG_RE.match(pkg):
                self._deny(400, f"paquete invalido: {pkg}")
                return
            code, out = apt_install(pkg)
            audit(client_ip, f"/apt/install {pkg}", f"->{code}")
            self._send(code, out)
            return
        if parsed.path == "/service":
            name = body.get("name", "")
            action = body.get("action", "")
            if not SVC_RE.match(name):
                self._deny(400, f"servicio invalido: {name}")
                return
            code, out = service_action(name, action)
            audit(client_ip, f"/service {action} {name}", f"->{code}")
            self._send(code, out)
            return

        self._deny(404, "not found")

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} - {fmt % args}")


def main():
    if not API_KEY:
        log("ERROR: no se pudo leer la API key")
        os._exit(1)
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    log(f"victoria-host-admin escuchando en {HOST}:{PORT} (allowlist de tools/paquetes/servicios)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()