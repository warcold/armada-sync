#!/usr/bin/env bash
# doc-fresh.sh — caché de frescura por agente en kalimete (TTL 24h).
# Mismo sistema que en victoria (armada-sync unificado, scopes separados):
# la doc viaja en el prompt del subagente; lo caro es VALIDARLA
# (doc vs live vs upstream). Este caché evita pagarla en cada delegación.
# Uso: doc-fresh.sh <Agente> | --mark-ok | --force | --status
# Task CON CAMBIOS: STALE → deep-check en el Task, luego --mark-ok.
# Lectura e inferencia: no se usa esto.
set -u
STATE="$HOME/.config/opencode/state/frescura.json"
TTL=86400
AGENTES="kalimete armada-arcade alfredo-ecomm authentik cloudflare docuseal irc nextcloud petsuite proxy ragnarok scriberr taohemps victoria-server vps woodly erp-dev godot-dev proxmark wordpress-dev"
if [ "${1:-}" = "--status" ]; then
    python3 - "$STATE" "$AGENTES" <<'EOF'
import json, sys, time
st = {}
try: st = json.load(open(sys.argv[1]))
except (OSError, ValueError): st = {}
now = int(time.time())
print(f"{'AGENTE':<18}{'ESTADO':<8}EDAD")
for a in sys.argv[2].split():
    ts = (st.get(a) or {}).get("ts", 0)
    age = now - ts if ts else -1
    print(f"{a:<18}{'FRESH' if 0 <= age < 86400 else 'STALE':<8}{str(age)+'s' if age >= 0 else 'nunca'}")
EOF
    exit 0
fi
[ $# -ge 1 ] || { echo "uso: doc-fresh.sh <Agente> [--mark-ok|--force] | --status" >&2; exit 2; }
python3 - "$STATE" "$1" "${2:-check}" "$TTL" <<'EOF'
import json, sys, time
state_f, agent, mode, ttl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try: st = json.load(open(state_f))
except (OSError, ValueError): st = {}
now = int(time.time())
if mode == "--mark-ok":
    st[agent] = {"ts": now, "ok": True}
    open(state_f, "w").write(json.dumps(st, indent=1) + "\n")
    print(f"{agent}: marcado FRESH (TTL {ttl}s)")
elif mode == "--force":
    print(f"{agent}: STALE (forzado por --force)")
elif mode == "check":
    ts = (st.get(agent) or {}).get("ts", 0)
    if ts and now - ts < ttl: print(f"{agent}: FRESH (hace {now-ts}s → fast path)")
    elif ts: print(f"{agent}: STALE (hace {now-ts}s, expiró → deep-check)")
    else: print(f"{agent}: STALE (primera vez → deep-check)")
else: sys.exit("modo inválido")
EOF
