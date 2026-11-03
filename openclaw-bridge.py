#!/usr/bin/env python3
"""openclaw-bridge.py - TCP proxy crudo (HTTP + WebSocket OK).

Uso: openclaw-bridge.py <listen_host> <listen_port> <target_host> <target_port>
"""
import socket
import sys
import threading
import os


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                s.close()
            except Exception:
                pass


def handle(client):
    try:
        upstream = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=10)
        # FIX 2026-09-19: create_connection DEJA el timeout=10s seteado en el
        # socket para TODAS las operaciones siguientes. El recv() del relay
        # lanzaba socket.timeout a los 10s idle -> cerraba AMBAS puntas y mataba
        # todo WS quieto >10s (dashboard en loop conect/drop cada ~15s).
        # El timeout solo se queria para el connect: se quita aqui.
        upstream.settimeout(None)
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        pipe(upstream, client)
    except Exception:
        try:
            client.close()
        except Exception:
            pass


def main():
    global TARGET_HOST, TARGET_PORT
    listen_host, listen_port, TARGET_HOST, TARGET_PORT = (
        sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]))
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((listen_host, listen_port))
    srv.listen(50)
    with open("/tmp/openclaw-bridge.pid", "w") as f:
        f.write(str(os.getpid()))
    print(f"openclaw-bridge: {listen_host}:{listen_port} -> {TARGET_HOST}:{TARGET_PORT}", flush=True)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()