#!/usr/bin/env bash
# whatsapp-qr.sh — Genera un QR fresco para vincular WhatsApp de Victoria.
# Uso: whatsapp-qr.sh [segundos]   (default 240s — el QR rota solo cada ~60s)
#
# Flujo: owner abre WhatsApp en el teléfono → Linked Devices → Link a Device
# y escanea el ULTIMO QR que imprima este script (los anteriores expiran).
#
# Detalles técnicos (2026-09-19):
# - El login corre Baileys en un proceso CLI dentro del netns del gateway
#   (nsenter -t <gw-pid> -n) con WS al gateway in-sandbox (127.0.0.1:18790).
# - REQUIERE NODE_EXTRA_CA_CERTS=/etc/openshell-tls/openshell-ca.pem: sin el
#   CA del proxy, el TLS contra web.whatsapp.com muere antes de abrir ("Non-Error
#   rejection", sin QR). El gateway sí lo tiene en su env; el CLI no lo hereda.
# - Requiere egress policy `whatsapp` activa en el sandbox.
set -u

WAIT="${1:-240}"
CID=$(docker ps --filter "name=victoria-armada" --format '{{.ID}}' | head -1)
[ -n "$CID" ] || { echo "ERROR: sandbox no corriendo"; exit 1; }
GW_PID=$(docker exec "$CID" sh -c 'pgrep -f "openclaw-gatewa[y]" 2>/dev/null' 2>/dev/null | head -1)
[ -n "$GW_PID" ] || { echo "ERROR: gateway in-sandbox no encontrado"; exit 1; }
TOK=$(docker exec "$CID" python3 -c "import json; print(json.load(open('/sandbox/.openclaw/openclaw.json'))['gateway']['auth']['token'])" 2>/dev/null)
[ -n "$TOK" ] || { echo "ERROR: no se pudo leer gateway token"; exit 1; }

echo "=== QR WhatsApp Victoria (escanea el ULTIMO; rota ~60s, ventana ${WAIT}s) ==="
docker exec "$CID" sh -c "nsenter -t $GW_PID -n -- env HOME=/sandbox NODE_EXTRA_CA_CERTS=/etc/openshell-tls/openshell-ca.pem OPENCLAW_GATEWAY_URL='ws://127.0.0.1:18790' OPENCLAW_GATEWAY_TOKEN='$TOK' runuser -u sandbox -- timeout $WAIT /usr/local/bin/openclaw channels login --channel whatsapp --verbose 2>&1" 2>/dev/null
