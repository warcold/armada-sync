#!/usr/bin/env python3
"""Bridge TTS/STT via UNIX socket.

Corre en el container level (voice-server via host.docker.internal) y expone
HTTP en socket UNIX /tmp/tts-gateway.sock accesible desde el netns del gateway.

2026-08-26: Added admin API key auth to voice-server requests.
2026-09-19: key hardcodeada eliminada (era admin viva en snapshots); auth solo via env VOICE_API_KEY.
2026-10-04: endurecido (thread por conexion + timeouts + close garantizado);
           el ensure-loop ahora reinicia el proceso cuando el md5 difiere (deploy automatico).
"""
import json, os, socket, sys, threading, urllib.request, urllib.error

VOICE_SERVER = "http://host.docker.internal:18810"
SOCKET_PATH = "/tmp/tts-gateway.sock"

# Admin API key for voice-server auth (same as llm-gateway admin keys)
VOICE_API_KEY = os.environ.get("VOICE_API_KEY", "")  # SIN default hardcodeado (2026-09-19): la red docker es keyless por sense_auth.py; solo se usa si se exporta VOICE_API_KEY (p.ej. uso LAN)

if os.path.exists(SOCKET_PATH):
    os.remove(SOCKET_PATH)

def unix_listen(path):
    if os.path.exists(path):
        os.remove(path)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    os.chmod(path, 0o666)
    s.listen(20)
    return s

def forward(method, path, body, content_type, timeout=420):
    url = VOICE_SERVER + path
    headers = {"Content-Type": content_type}
    if VOICE_API_KEY:
        headers["Authorization"] = f"Bearer {VOICE_API_KEY}"
    req = urllib.request.Request(url, data=body or b"", method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            rdata = resp.read()
            rheaders = {k: v for k, v in resp.getheaders() if k.lower() not in ("transfer-encoding", "connection")}
            return resp.status, rheaders, rdata
    except urllib.error.HTTPError as e:
        rdata = e.read()
        rheaders = {k: v for k, v in e.headers.items() if k.lower() not in ("transfer-encoding", "connection")}
        return e.code, rheaders, rdata
    except Exception as e:
        # URLError/DNS/conexión rota → 502 limpio (antes: excepción sin capturar
        # mataba el handle y con él el loop mono-hilo del bridge entero).
        return 502, {}, json.dumps({"error": f"upstream: {e}"}).encode()

def send(client_sock, status, headers, body):
    status_map = {200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error", 502: "Bad Gateway"}
    lines = [f"HTTP/1.1 {status} {status_map.get(status, 'OK')}", "Connection: close"]
    for k, v in headers.items():
        lines.append(f"{k}: {v}")
    lines.append(f"Content-Length: {len(body)}")
    lines.append("")

    client_sock.sendall(("\r\n".join(lines) + "\r\n").encode())
    client_sock.sendall(body)
    client_sock.close()

def parse_request_header(data):
    """Extract method, path, content_length, content_type, body_offset from raw HTTP headers."""
    idx = -1
    for sep in [b"\r\n\r\n", b"\n\n"]:
        i = data.find(sep)
        if i >= 0:
            idx = i + 4
            break
    if idx <= 0:
        return None

    header_text = data[:idx].decode("utf-8", errors="replace")
    lines = header_text.split("\n")
    first_line = lines[0].strip()
    parts = first_line.split()
    method = parts[0] if parts else "GET"
    path = parts[1] if len(parts) > 1 else "/"

    content_length = 0
    content_type = "application/json"
    for line in lines[1:]:
        if line.lower().startswith("content-length:"):
            try:
                content_length = int(line.split(":", 1)[1].strip())
            except ValueError:
                content_length = 0
        if line.lower().startswith("content-type:"):
            content_type = line.split(":", 1)[1].strip()

    return method, path, content_length, content_type, idx

def handle(client_sock):
    try:
        # 2026-10-04: antes settimeout(None) — un cliente mudo/parcial bloqueaba
        # el recv para siempre y, con el loop mono-hilo, TODA la voz del sandbox.
        client_sock.settimeout(60)
        # Read headers
        header_data = b""
        while True:
            chunk = client_sock.recv(4096)
            if not chunk:
                break
            header_data += chunk
            if b"\r\n\r\n" in header_data or b"\n\n" in header_data:
                break

        parsed = parse_request_header(header_data)
        if parsed is None:
            send(client_sock, 400, {}, b"Bad request - no headers")
            return

        method, path, content_length, content_type, hdr_end = parsed

        # Read body from socket
        body = b""
        if hdr_end < len(header_data):
            body = header_data[hdr_end:hdr_end + content_length]
        while len(body) < content_length:
            chunk = client_sock.recv(min(65536, content_length - len(body)))
            if not chunk:
                break
            body += chunk
        body = body[:content_length]

        if method == "GET" and path == "/health":
            status, rheaders, rbody = forward("GET", "/health", b"", "application/json", timeout=5)
            send(client_sock, status, rheaders, rbody)
        elif method == "POST":
            endpoint = path.rsplit("/", 1)[-1] or "tts"
            if endpoint not in ("tts", "stt"):
                send(client_sock, 404, {}, json.dumps({"error": "Unknown endpoint"}).encode())
                return
            to = 300 if endpoint == "stt" else 420
            status, rheaders, rbody = forward("POST", "/" + endpoint, body, content_type, timeout=to)
            if endpoint == "tts":
                rheaders["Content-Type"] = "audio/wav"
            elif endpoint == "stt":
                rheaders["Content-Type"] = "text/plain"
            send(client_sock, status, rheaders, rbody)
        else:
            send(client_sock, 405, {}, json.dumps({"error": "Method not allowed"}).encode())
    except Exception as e:
        try:
            send(client_sock, 500, {}, json.dumps({"error": str(e)}).encode())
        except Exception:
            pass
    finally:
        try:
            client_sock.close()
        except Exception:
            pass

if __name__ == "__main__":
    server = unix_listen(SOCKET_PATH)
    print(f"Bridge listening on {SOCKET_PATH}")
    sys.stderr.flush()
    while True:
        client_sock, _ = server.accept()
        # 2026-10-04: thread por conexión — un cliente atascado ya no bloquea
        # a los demás (el bridge viejo murió atascado por esto).
        threading.Thread(target=handle, args=(client_sock,), daemon=True).start()
