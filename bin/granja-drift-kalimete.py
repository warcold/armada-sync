#!/usr/bin/env python3
"""granja-drift (kalimete side, 2026-10-29): compara el catalogo LIVE
/v1/granja del gateway de Victoria contra las skills locales. Solo reporta
a ~/armada-sync/granja-drift.log; el fix es actualizar la skill (pre-aprobado)."""
import json, os, urllib.request, glob, datetime, re

KEY = None
try:
    txt = open(os.path.expanduser("~/.config/opencode/opencode.jsonc")).read()
    m = re.search(r'"apiKey"\s*:\s*"(vllm-key-[a-f0-9]+)"', txt)
    if m:
        KEY = m.group(1)
except Exception:
    pass
if not KEY:
    print(datetime.datetime.now().isoformat(), "sin key, skip")
    raise SystemExit(0)

try:
    req = urllib.request.Request(
        "http://victoria.local:8010/v1/granja",
        headers={"Authorization": "Bearer " + KEY})
    d = json.load(urllib.request.urlopen(req, timeout=15))
except Exception as e:
    print(datetime.datetime.now().isoformat(), "gateway no alcanza (normal fuera de LAN):", e)
    raise SystemExit(0)

up = [k for k, v in d.get("health_probes", {}).items() if v == "up"]
skills = {}
for p in glob.glob(os.path.expanduser("~/.config/opencode/skills/*/SKILL.md")):
    name = os.path.basename(os.path.dirname(p))
    skills[name] = open(p).read()

drifts = []
# 1. skills de la granja deben referenciar la fuente viva
for s in ("art", "voice-video", "assets-3d"):
    if s in skills and "v1/granja" not in skills[s]:
        drifts.append("skill " + s + " sin fuente viva /v1/granja")
# 2. servicios up cubiertos por alguna skill o el agente victoria-server
agente = ""
try:
    agente = open(os.path.expanduser("~/.config/opencode/agent/victoria-server.md")).read()
except Exception:
    pass
MAP = {"tts_stt": ["TTS", "STT", "voice"], "video": ["video"], "webnav": ["web-nav", "webnav"],
       "whois": ["whois"], "sonic": ["onic"], "hunyuan3d": ["unyuan"], "lp_animate": ["lp-animate", "animar"]}
for svc in up:
    pats = MAP.get(svc, [svc])
    covered = any(pat.lower() in agente.lower() or
                  any(pat.lower() in t.lower() for t in skills.values())
                  for pat in pats)
    if not covered:
        drifts.append("servicio " + svc + " up en victoria sin cobertura documental en kalimete")

log = os.path.expanduser("~/armada-sync/granja-drift.log")
with open(log, "a") as f:
    if drifts:
        for dr in drifts:
            f.write(datetime.datetime.now().isoformat() + " DRIFT: " + dr + "\n")
    else:
        f.write(datetime.datetime.now().isoformat() + " OK sincronizado (" + str(len(up)) + " servicios up)\n")
print(datetime.datetime.now().isoformat(), "OK" if not drifts else "DRIFT x" + str(len(drifts)))
