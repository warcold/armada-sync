#!/bin/bash
# dashboard-relay-helper — por conexión: resuelve el pid HOST del gateway
# (netns interior OCSF) y conecta al gateway dentro de ese netns.
# El gateway del runtime 2026.9.x vive en un netns PROPIO (Landlock/OCSF),
# no en el netns del contenedor — por eso el forward oficial (fase Error)
# y el nsenter del contenedor no lo alcanzan. Este puente si.
# 2026-10-16: tras re-onboard con nemoclaw v0.0.130 el gateway binda 18789
# (default del onboard; antes 18790). Detección dinámica de puerto.
CID=$(docker ps --format '{{.Names}}' | grep -E "armada" | head -1)
[ -z "$CID" ] && exit 1
HGPID=$(docker top "$CID" -o pid,cmd 2>/dev/null | grep "openclaw-gateway" | awk '{print $1}' | head -1)
[ -z "$HGPID" ] && exit 1
# Detecta el puerto real del gateway dentro del netns (18789 o 18790)
GWPORT=$(nsenter -t "$HGPID" -n ss -tln 2>/dev/null | grep -oE '127\.0\.0\.1:187(89|90)|0\.0\.0\.0:187(89|90)|\*:187(89|90)' | grep -oE '187(89|90)' | head -1)
[ -z "$GWPORT" ] && GWPORT=18789
exec nsenter -t "$HGPID" -n socat - TCP:127.0.0.1:$GWPORT
