#!/usr/bin/env bash
# doc-fresh.sh — caché de frescura por subagente (TTL 24h).
#
# La doc YA viaja en el prompt del subagente (el .md es su prompt): releerla
# no cuesta nada. Lo caro es VALIDARLA (doc vs live vs upstream). Este caché
# evita pagar esa validación en cada delegación.
#
# Uso:
#   doc-fresh.sh <Agente>            → imprime FRESH o STALE <motivo> (solo lee)
#   doc-fresh.sh <Agente> --mark-ok  → marca verificado-ahora (tras deep-check)
#   doc-fresh.sh <Agente> --force    → imprime STALE (fuerza deep-check)
#   doc-fresh.sh --status            → tabla de todos (sin red)
#
# Flujo de Victoria antes de un Task CON CAMBIOS (config/flags/restarts/installs):
#   STALE → el Task lleva instrucción deep-check (doc vs live vs upstream);
#           al terminar, --mark-ok.  FRESH → fast path (solo health del servicio).
# Task de solo-lectura e inferencia normal (chat): no se usa esto.
set -u
STATE="$HOME/.victoria-custom/state/frescura.json"
TTL=86400

usage() { echo "uso: doc-fresh.sh <Agente> [--mark-ok|--force] | --status" >&2; exit 2; }

if [ "${1:-}" = "--status" ]; then
    python3 - "$STATE" <<'EOF'
import json, sys, time
try:
    st = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    st = {}
now = int(time.time())
print(f"{'AGENTE':<14}{'ESTADO':<8}EDAD")
for a in ["Victoria", "vLLM", "OpenClaw", "Comfyui", "Sonic", "RSS System",
          "Meta Business", "Weather", "CloudFlare", "Liveportrait", "Gpu"]:
    ts = (st.get(a) or {}).get("ts", 0)
    age = now - ts if ts else -1
    print(f"{a:<14}{'FRESH' if 0 <= age < 86400 else 'STALE':<8}{str(age)+'s' if age >= 0 else 'nunca'}")
EOF
    exit 0
fi

[ $# -ge 1 ] || usage
AGENT="$1"
MODE="${2:-check}"

python3 - "$STATE" "$AGENT" "$MODE" "$TTL" <<'EOF'
import json, sys, time
state_f, agent, mode, ttl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
try:
    st = json.load(open(state_f))
except (OSError, ValueError):
    st = {}
now = int(time.time())
if mode == "--mark-ok":
    st[agent] = {"ts": now, "ok": True}
    open(state_f, "w").write(json.dumps(st, indent=1) + "\n")
    print(f"{agent}: marcado FRESH (TTL {ttl}s)")
elif mode == "--force":
    print(f"{agent}: STALE (forzado por --force)")
elif mode == "check":
    ts = (st.get(agent) or {}).get("ts", 0)
    if ts and now - ts < ttl:
        print(f"{agent}: FRESH (verificado hace {now - ts}s, TTL {ttl}s → fast path)")
    elif ts:
        print(f"{agent}: STALE (verificado hace {now - ts}s, expiró TTL {ttl}s → deep-check)")
    else:
        print(f"{agent}: STALE (primera vez, nunca verificado → deep-check)")
else:
    sys.exit("modo inválido: --mark-ok|--force")
EOF
