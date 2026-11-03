#!/usr/bin/env bash
# nvapi-rotate.sh — rotación de llaves NVIDIA NIM (nvapi-*) para opencode.
# Fuente de verdad: ~/.victoria-custom/secrets/nvapi-keys.json (600, solo victoria).
# Actualiza: ~/.local/share/opencode/auth.json (provider "nvidia").
# Uso:
#   nvapi-rotate.sh status            → muestra llave activa (prefijo) + estado de cada llave
#   nvapi-rotate.sh test [nombre]     → prueba 1 llave (o todas) con inferencia mínima
#   nvapi-rotate.sh rotate [nombre]   → cambia la activa (argumento o siguiente que funcione)
#   nvapi-rotate.sh auto              → si la activa falla (401/403/429), rota a la siguiente que funcione
#   MODEL=deepseek-ai/deepseek-v4-flash-0731 nvapi-rotate.sh test   → probar con otro modelo
#
# Códigos de salida: 0 = hay llave funcional activa, 1 = ninguna llave funciona.
# NUNCA imprime llaves completas (solo prefijo de 12 chars). NUNCA commitear el JSON de llaves.
set -u
KEYS_FILE="$HOME/.victoria-custom/secrets/nvapi-keys.json"
AUTH_FILE="$HOME/.local/share/opencode/auth.json"
MODEL="${MODEL:-moonshotai/kimi-k3}"
API="https://integrate.api.nvidia.com/v1/chat/completions"

need() { command -v "$1" >/dev/null 2>&1 || { echo "falta $1" >&2; exit 2; }; }
need python3; need curl

prefix() { python3 -c "import json;d=json.load(open('$KEYS_FILE'));print([k for k in d['keys'] if k['name']=='$1'][0]['key'][:12]+'…')"; }
active_name() { python3 -c "import json;print(json.load(open('$KEYS_FILE'))['active'])"; }
key_of() { python3 -c "import json;d=json.load(open('$KEYS_FILE'));print([k for k in d['keys'] if k['name']=='$1'][0]['key'])"; }
all_names() { python3 -c "import json;d=json.load(open('$KEYS_FILE'));print(' '.join(k['name'] for k in d['keys']))"; }

# Prueba una llave por nombre: imprime "NOMBRE HTTP_CODE". Devuelve 0 si 200.
probe() {
  local name="$1" key code
  key="$(key_of "$name")"
  code=$(curl -s -m 60 -o /tmp/nvapi-probe.json -w "%{http_code}" "$API" \
    -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Di hola\"}],\"max_tokens\":5}")
  echo "$name $code"
  [ "$code" = "200" ]
}

# Escribe la llave <nombre> en auth.json (con backup). Solo toca provider "nvidia".
apply_to_auth() {
  local name="$1" key ts
  key="$(key_of "$name")"
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$AUTH_FILE" "$AUTH_FILE.bak-$ts"
  python3 - "$AUTH_FILE" "$key" <<'EOF'
import json,sys
p, k = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d.setdefault("nvidia", {"type": "api"})
d["nvidia"]["key"] = k
json.dump(d, open(p, "w"), indent=2)
EOF
  python3 - "$KEYS_FILE" "$name" <<'EOF'
import json,sys
p, n = sys.argv[1], sys.argv[2]
d = json.load(open(p)); d["active"] = n
json.dump(d, open(p, "w"), indent=2)
EOF
  chmod 600 "$AUTH_FILE" "$KEYS_FILE"
  echo "activa → $name ($(prefix "$name")) | backup auth.json.bak-$ts"
}

cmd_status() {
  echo "modelo de prueba: $MODEL"
  echo "activa: $(active_name) ($(prefix "$(active_name)"))"
  local rc=0
  for n in $(all_names); do
    if probe "$n"; then m="OK"; else m="FALLA"; rc=1; fi
    echo "  $n ($(prefix "$n")): $m"
    sleep 2
  done
  return 0  # status siempre 0; el estado real lo da test/auto
}

cmd_test() {
  if [ "${1:-}" != "" ]; then probe "$1"; return $?; fi
  local rc=0
  for n in $(all_names); do probe "$n" || rc=1; sleep 2; done
  return $rc
}

cmd_rotate() {
  if [ "${1:-}" != "" ]; then apply_to_auth "$1"; probe "$1" >/dev/null && echo "verificada OK" || echo "AVISO: la llave no pasó el probe"; return 0; fi
  for n in $(all_names); do
    if probe "$n" >/dev/null; then apply_to_auth "$n"; return 0; fi
    sleep 2
  done
  echo "ERROR: ninguna llave funciona" >&2; return 1
}

cmd_auto() {
  local cur; cur="$(active_name)"
  if probe "$cur" >/dev/null; then echo "activa $cur OK, sin cambios"; return 0; fi
  echo "activa $cur falla → rotando…"
  sleep 2
  for n in $(all_names); do
    [ "$n" = "$cur" ] && continue
    if probe "$n" >/dev/null; then apply_to_auth "$n"; echo "rotación completa"; return 0; fi
    sleep 2
  done
  echo "ERROR: ninguna llave de respaldo funciona" >&2; return 1
}

case "${1:-status}" in
  status) cmd_status ;;
  test)   cmd_test "${2:-}" ;;
  rotate) cmd_rotate "${2:-}" ;;
  auto)   cmd_auto ;;
  *) echo "uso: $0 {status|test [nombre]|rotate [nombre]|auto}" >&2; exit 2 ;;
esac
