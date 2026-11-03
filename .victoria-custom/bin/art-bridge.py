#!/usr/bin/env python3
"""Bridge art API via UNIX socket.

Corre en el container level (gateway :8010 via 172.18.0.1 directo, SIN proxy
L7) y expone HTTP en socket UNIX /tmp/art-gateway.sock accesible desde el
netns del gateway.

POR QUE EXISTE (2026-10-05): el netns del gateway sale a red SOLO por el proxy
L7 (10.200.0.1:3128) y el motor de policies NO permite a presets de usuario
destinos privados (172.18.0.1:8010 da policy_denied aunque el preset
victoria-art-api este aplicado con pins). Los otros 4 sentidos (voz/video/
whois/admin) usan este mismo patron puente-socket; el arte era el unico con
HTTP directo y por eso nunca funciono desde el agente. art-gen habla al
socket cuando existe (ART_SOCKET, default /tmp/art-gateway.sock) y cae a TCP
solo fuera del sandbox.

Forwardea TODOS los paths del art API (/health, /v1/images, /v1/jobs/*,
/v1/art-files/*) con passthrough del header Authorization (la llave art va
en cada request de art-gen).
Replica el patron endurecido de video-bridge.py (thread por conexion +
timeouts + close garantizado).
"""
import json, os, socket, sys, threading, urllib.request, urllib.error

ART_SERVER = "http://172.18.0.1:8010"
SOCKET_PATH = "/tmp/art-gateway.sock"

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


def forward(method, path, body, headers_in, timeout=1800):
    url = ART_SERVER + path
    headers = {}
    for k in ("Content-Type", "Authorization", "Accept"):
        for hk, hv in (headers_in or {}).items():
            if hk.lower() == k.lower():
                headers[k] = hv
    if "Content-Type" not in headers:
        headers["Content-Type"] = "application/json"
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
        return 502, {}, json.dumps({"error": f"upstream: {e}"}).encode()


def send(client_sock, status, headers, body):
    status_map = {200: "OK", 201: "Created", 202: "Accepted", 400: "Bad Request",
                  401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
                  429: "Too Many Requests", 500: "Internal Server Error", 502: "Bad Gateway"}
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
    headers_in = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k = k.strip()
        v = v.strip()
        headers_in[k] = v
        if k.lower() == "content-length":
            try:
                content_length = int(v)
            except ValueError:
                content_length = 0
    return method, path, content_length, headers_in, idx


def handle(client_sock):
    try:
        client_sock.settimeout(60)
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
        method, path, content_length, headers_in, hdr_end = parsed
        body = b""
        if hdr_end < len(header_data):
            body = header_data[hdr_end:hdr_end + content_length]
        while len(body) < content_length:
            chunk = client_sock.recv(min(65536, content_length - len(body)))
            if not chunk:
                break
            body += chunk
        body = body[:content_length]
        status, rheaders, rbody = forward(method, path, body, headers_in)
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
    print(f"Art bridge listening on {SOCKET_PATH}")
    sys.stderr.flush()
    while True:
        client_sock, _ = server.accept()
        threading.Thread(target=handle, args=(client_sock,), daemon=True).start()
