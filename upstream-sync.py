#!/usr/bin/env python3
"""upstream-sync.py — compara versiones LOCALES vs UPSTREAM una vez al día.

NO edita docs ni actualiza nada: solo REPORTA deriva. Actualizar es decisión
del owner (plan si es grande). Corre por timer diario 05:00 ET; solo red de
lectura (GitHub API + PyPI), sin tocar servicios ni GPU.

Uso:
  upstream-sync.py           # chequea red y escribe state/upstream.json + log
  upstream-sync.py --status  # muestra el último estado guardado (sin red)

Estado: ~/.victoria-custom/state/upstream.json
Log:    ~/logs/upstream-sync.log
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".victoria-custom/state/upstream.json")
LOG = os.path.join(HOME, "logs/upstream-sync.log")
UA = {"User-Agent": "Victoria-Armada/1.0 (doc-sync diario)"}
TIMEOUT = 20


def log(msg):
    line = f"[upstream-sync {time.strftime('%Y-%m-%d %H:%M')}] {msg}"
    print(line)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def http_json(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            if "X-RateLimit-Remaining" in r.headers and \
               r.headers["X-RateLimit-Remaining"] == "0":
                return {"_ratelimit": True}
            return json.load(r)
    except Exception as e:
        return {"_error": str(e)[:100]}


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True,
                              text=True, timeout=30).stdout.strip()
    except Exception:
        return ""


def git_head(path):
    return sh(f"git -C {path} rev-parse HEAD 2>/dev/null")


def norm_tag(t):
    return (t or "").strip().lstrip("v").replace("-", ".")


CHECKS = [
    {"id": "ComfyUI", "doc": "Comfyui",
     "local": lambda: git_head(f"{HOME}/ComfyUI")[:12],
     "upstream": lambda: (http_json(
        "https://api.github.com/repos/comfyanonymous/ComfyUI/commits/master"
        ).get("sha", "") or "")[:12],
     "nota": "git HEAD vs origin/master"},
    {"id": "LivePortrait", "doc": "Liveportrait",
     "local": lambda: git_head(f"{HOME}/LivePortrait")[:12],
     "upstream": lambda: (http_json(
        "https://api.github.com/repos/KlingAIResearch/LivePortrait/commits/main"
        ).get("sha", "") or "")[:12],
     "nota": "git HEAD vs origin/master (app.py es custom, upstream rara vez aplica)"},
    {"id": "Sonic", "doc": "Sonic",
     "local": lambda: git_head(f"{HOME}/Sonic")[:12],
     "upstream": lambda: (http_json(
        "https://api.github.com/repos/jixiaozhong/Sonic/commits/main"
        ).get("sha", "") or "")[:12],
     "nota": "git HEAD vs origin/main"},
    {"id": "Gradio", "doc": "Liveportrait",
     "local": lambda: sh(f"{HOME}/liveportrait-venv/bin/pip show gradio 2>/dev/null"
                         " | awk '/^Version/{{print $2}}'"),
     "upstream": lambda: (http_json("https://pypi.org/pypi/gradio/json")
                          .get("info", {}) or {}).get("version", ""),
     "nota": "venv vs PyPI (pin deliberado 6.28: fixes Gradio 6 aplicados a mano)"},
    {"id": "yt-dlp", "doc": "OpenClaw",
     "local": lambda: sh(f"{HOME}/video-venv/bin/python3 -m yt_dlp --version 2>/dev/null"),
     "upstream": lambda: norm_tag((http_json(
        "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
        ) or {}).get("tag_name", "")),
     "nota": "video-venv vs release (player android + deno; si deriva, probar antes de subir)"},
    {"id": "cloudflared", "doc": "CloudFlare",
     "local": lambda: (sh("cloudflared --version 2>/dev/null").split() or ["", "", ""])[2],
     "upstream": lambda: norm_tag((http_json(
        "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
        ) or {}).get("tag_name", "")),
     "nota": "binario vs release (túnel crítico: no auto-update, solo reportar)"},
    {"id": "blogwatcher", "doc": "RSS System",
     "local": lambda: "v0.0.4",
     "upstream": lambda: (http_json(
        "https://api.github.com/repos/Hyaxia/blogwatcher/releases/latest"
        ) or {}).get("tag_name", ""),
     "nota": "compilado local (esperado v0.0.4) vs release (rebuild Go si aplica)"},
    {"id": "vLLM-digest", "doc": "vLLM",
     "local": lambda: "@sha256:9204569b (pin inmutable)",
     "upstream": lambda: "pin por política (revisión manual trimestral)",
     "nota": "SIN fetch a propósito: el digest nunca se mueve solo", "pinned": True},
]


def check():
    state, drifts, unknowns = {}, [], []
    for c in CHECKS:
        try:
            local = (c["local"]() or "").strip()
        except Exception:
            local = ""
        if c.get("pinned"):
            state[c["id"]] = {"local": local, "upstream": c["upstream"](),
                              "drift": False, "ts": int(time.time()),
                              "doc": c["doc"], "nota": c["nota"]}
            continue
        try:
            up = (c["upstream"]() or "").strip()
        except Exception:
            up = ""
        if not local or not up or up.startswith("{"):
            unknowns.append(c["id"])
            drift = False
        else:
            drift = norm_tag(local) != norm_tag(up) if c["id"] in (
                "Gradio", "yt-dlp", "cloudflared", "blogwatcher") else local != up
            if drift:
                drifts.append(f"{c['id']}: local={local} upstream={up}")
        state[c["id"]] = {"local": local or "?", "upstream": up or "?",
                          "drift": drift if (local and up) else None,
                          "ts": int(time.time()), "doc": c["doc"],
                          "nota": c["nota"]}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    json.dump(state, open(STATE, "w"), indent=1)
    log(f"chequeo completo: {len(state)} sistemas, "
        f"{len(drifts)} derivas, {len(unknowns)} sin-datos")
    for d in drifts:
        log(f"DERIVA: {d}")
    for u in unknowns:
        log(f"SIN-DATOS (red o parseo, no es deriva): {u}")
    if not drifts and not unknowns:
        log("todo alineado con upstream")
    return 0


def status():
    try:
        state = json.load(open(STATE))
    except (OSError, ValueError):
        print("sin estado: aún no corre el chequeo diario")
        return 0
    print(f"{'SISTEMA':<13}{'LOCAL':<16}{'UPSTREAM':<16}ESTADO")
    for sid, s in state.items():
        est = "DERIVA" if s.get("drift") else (
            "?" if s.get("drift") is None else "ok")
        print(f"{sid:<13}{str(s.get('local')):<16}"
              f"{str(s.get('upstream')):<16}{est}")
    return 0


if __name__ == "__main__":
    sys.exit(status() if "--status" in sys.argv else check())
