#!/usr/bin/env python3
"""Bridge admin via UNIX socket (victoria-host-admin host :18840).

Corre en el container level (host-admin via host.docker.internal) y expone
HTTP en socket UNIX /tmp/video-gateway.sock accesible desde el netns del gateway.
Forwardea TODOS los paths del admin-server host (/exec /apt/install /service
/status /health) anadiendo X-API-Key.
"""
import json, os, socket, sys, threading, urllib.request, urllib.error

ADMIN_SERVER = "http://host.docker.internal:18840"
SOCKET_PATH = "/tmp/admin-gateway.sock"
KEY_PATH = "/sandbox/.openclaw/.secrets/admin-bridge.key"

def load_key():
    try:
        with open(KEY_PATH) as f:
            return f.read().strip()
    except Exception:  # noqa: BLE001
        return ""

API_KEY = load_key()

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

def forward(method, path, body, content_type, timeout=1800):
    url = ADMIN_SERVER + path
    headers = {"Content-Type": content_type, "X-API-Key": API_KEY}
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
        # 2026-10-04: URLError/DNS roto → 502 limpio en vez de matar el bridge.
        return 502, {}, json.dumps({"error": f"upstream: {e}"}).encode()

def send(client_sock, status, headers, body):
    status_map = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error", 502: "Bad Gateway"}
    lines = [f"HTTP/1.1 {status} {status_map.get(status, 'OK')}", "Connection: close"]
    for k, v in headers.items():
        lines.append(f"{k}: {v}")
    lines.append(f"Content-Length: {len(body)}")
    lines.append("")
    client_sock.sendall(("\r\n".join(lines) + "\r\n").encode())
    client_sock.sendall(body)
    client_sock.close()

def parse_request_header(data):
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
        client_sock.settimeout(60)  # 2026-10-04: antes None — cliente mudo = bridge atascado
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
        body = b""
        if hdr_end < len(header_data):
            body = header_data[hdr_end:hdr_end + content_length]
        while len(body) < content_length:
            chunk = client_sock.recv(min(65536, content_length - len(body)))
            if not chunk:
                break
            body += chunk
        body = body[:content_length]
        status, rheaders, rbody = forward(method, path, body, content_type)
        send(client_sock, status, rheaders, rbody)
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
    print(f"Admin bridge listening on {SOCKET_PATH}")
    sys.stderr.flush()
    while True:
        client_sock, _ = server.accept()
        # 2026-10-04: thread por conexión (endurecido igual que tts-bridge).
        threading.Thread(target=handle, args=(client_sock,), daemon=True).start()