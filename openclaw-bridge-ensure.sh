#!/usr/bin/env bash
# openclaw-bridge-ensure.sh
# Reasegura la cadena de acceso al dashboard de OpenClaw (victoria-armada):
#   1. container del sandbox conectado a la red victoria-lan (IP fija 172.22.0.10)
#      (se usa para voice/video/whois/admin bridges hacia el host)
#   2. forward de plataforma host 127.0.0.1:18790 -> servicio loopback
#      127.0.0.1:18790 DENTRO del sandbox (inner netns del openclaw-gateway),
#      via `openshell forward service` (gRPC). El openclaw-gateway binda 18790
#      SOLO en su netns interno: ni 127.0.0.1 ni 172.22.0.10 del host llegan.
#      (Modelo corregido 2026-09-21: el gateway NO vive en el host; lo que vive
#      en el host es este relay + el publisher. Ver ensure_dashboard_forward.)
#   3. publisher host (openclaw-publisher, 0.0.0.0:18789 -> 127.0.0.1:18790)
#      para acceso LAN (victoria.local:18789).
# Pensado para ejecutarse en loop desde systemd (Restart=always).
set -u

SANDBOX_PREFIX="victoria-armada"
# Nombre real del contenedor (cambia en cada rebuild; derivar dinámicamente)
SANDBOX_NAME=""
NETWORK="victoria-lan"
SANDBOX_IP="172.22.0.10"
PUBLISHER_PORT="18800"
# El openclaw-gateway (uid 998) escucha en 18790 SOLO dentro de su netns interno
# del sandbox (0.0.0.0:18790 en netns sandbox-*, alcanzable como 127.0.0.1:18790
# o 10.200.0.2:18790 solo desde ahi). El host lo alcanza via `openshell forward
# service` (relay gRPC) que binda 127.0.0.1:18790 en el host — eso es lo que
# `nemoclaw <sandbox> dashboard-url` anuncia. El publisher (network host) se
# conecta a ese 127.0.0.1:18790 del host, NO a la IP del sandbox (172.22.0.10
# no sirve 18790 en ningun netns).
GATEWAY_HOST="127.0.0.1"
GATEWAY_PORT="18790"

log() { echo "[openclaw-bridge] $(date -Is) $*"; }

# 2026-10-04: pid de un bridge vivo en el sandbox (pkill -f NO opera ahí).
# $1=cid $2=nombre del proceso (ej tts-bridge.py). Devuelve el pid o vacío.
bridge_pid() {
    docker exec "$1" sh -c "ps -eo pid,cmd 2>/dev/null | grep \"[${2:0:1}]${2:1}\" | awk '{print \$1}' | head -1" 2>/dev/null
}

resolve_sandbox_name() {
    SANDBOX_NAME=$(docker ps --filter "name=$SANDBOX_PREFIX" --format '{{.Names}}' | head -1)
}

ensure_network() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 || {
        docker network create --driver bridge --subnet 172.22.0.0/16 "$NETWORK" >/dev/null 2>&1
        log "red $NETWORK creada"
    }
}

ensure_sandbox_connected() {
    local cid
    # Lock de bootstrap: durante `nemoclaw onboard` el provider managed-bootstrap
    # RECHAZA workloads con múltiples redes. Si existe el lock, NO attaching
    # victoria-lan hasta que el bootstrap termine (ver CHANGELOG 2026-09-14).
    # Crear con: touch /tmp/openclaw-bootstrap.lock (o la ruta state) — borrar al terminar.
    [ -f /tmp/openclaw-bootstrap.lock ] && return 1
    [ -f /home/victoria/.victoria-custom/state/openclaw-bootstrap.lock ] && return 1
    [ -z "$SANDBOX_NAME" ] && return 1
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 1
    if ! docker inspect "$cid" --format '{{.NetworkSettings.Networks}}' 2>/dev/null | grep -q "$NETWORK"; then
        docker network connect --ip "$SANDBOX_IP" "$NETWORK" "$cid" 2>/dev/null
        log "sandbox conectado a $NETWORK ($SANDBOX_IP)"
    fi
    return 0
}

# ensure_inner_proxy ELIMINADO 2026-09-18 (era el proxy 18789->10.200.0.2:18790
# dentro del container). NOTA 2026-09-21: el diagnostico del 18-sep ("el gateway
# vive en el HOST como proceso openshell") era una lectura erronea — lo que se
# vio escuchando 127.0.0.1:18790 en el host era el relay `openshell forward
# service`, no el gateway. El openclaw-gateway sigue dentro del sandbox (inner
# netns, verificado LISTEN 0.0.0.0:18790 via nsenter). No resucitar el proxy
# interno: el relay oficial lo reemplaza.

# ensure_dashboard_forward: mantiene el relay de plataforma
# host 127.0.0.1:18790 -> 127.0.0.1:18790 dentro del sandbox (inner netns)
# via `openshell forward service` (gRPC). Sin este proceso NADA escucha en el
# 18790 del host y el publisher queda sordo (cadena rota tras cada reboot o
# rebuild, porque ningun servicio lo recreaba — causa raiz del outage
# 2026-09-20/21). Deteccion: puerto ausente en ss, o puerto presente pero sin
# respuesta HTTP (relay stale tras recreate del sandbox -> matar y recrear).
# CRITICO: openshell SIEMPRE como victoria (runuser + HOME/PATH), igual que
# ensure_policies — como root el contexto falla en silencio.
ensure_dashboard_forward() {
    [ -z "${SANDBOX_NAME:-}" ] && return 0
    # RUNTIME 2026.9.x (verificado 2026-10-05): el gateway vive en un netns INTERIOR
    # (OCSF/Landlock) — ni el forward oficial (requiere fase Ready; docker restart la
    # pone Error) ni el nsenter del contenedor lo alcanzan. Nuestro relay nsenter-socat
    # resuelve el pid HOST del gateway por conexión y puentea 127.0.0.1:18790.
    # El forward oficial queda como camino nativo si algún día la fase se estabiliza.
    local DEAD_COUNT_FILE="/home/victoria/.victoria-custom/state/dashboard-forward-dead.count"
    if ss -tln 2>/dev/null | grep -q "127.0.0.1:${GATEWAY_PORT}"; then
        if curl -s -m 5 -o /dev/null "http://127.0.0.1:${GATEWAY_PORT}/" 2>/dev/null; then
            echo 0 > "$DEAD_COUNT_FILE" 2>/dev/null
            return 0
        fi
        # Escucha pero no responde: contar ciclos; reciclar tras 4 (60s).
        local dead
        dead=$(cat "$DEAD_COUNT_FILE" 2>/dev/null || echo 0)
        dead=$((dead + 1))
        echo "$dead" > "$DEAD_COUNT_FILE" 2>/dev/null
        if [ "$dead" -lt 4 ]; then
            return 0  # transitorio (gateway del sandbox reiniciando) — esperar
        fi
        log "relay dashboard mudo ${dead} ciclos; reciclando"
        pkill -f "socat TCP-LISTEN:${GATEWAY_PORT}[,]" 2>/dev/null || true
        pkill -f "openshell forward service.*${GATEWAY_PORT}" 2>/dev/null || true
        sleep 2
    else
        echo 0 > "$DEAD_COUNT_FILE" 2>/dev/null
    fi
    if pgrep -f "socat TCP-LISTEN:${GATEWAY_PORT}[,]" >/dev/null 2>&1; then
        return 0  # proceso vivo pero puerto aun no bindeado (arrancando)
    fi
    log "relay dashboard 127.0.0.1:${GATEWAY_PORT} ausente; (re)creando via nsenter-socat (runtime 2026.9)"
    setsid nohup socat TCP-LISTEN:${GATEWAY_PORT},bind=127.0.0.1,fork,reuseaddr \
        EXEC:/home/victoria/.victoria-custom/bin/dashboard-relay-helper.sh \
        >>/home/victoria/logs/dashboard-relay.log 2>&1 < /dev/null &
    return 0
}

ensure_publisher() {
    # El publisher (network host) se conecta al relay 127.0.0.1:18790 del host
    # (openshell forward service -> openclaw-gateway dentro del sandbox),
    # no a la IP del sandbox. Label victoria.group=openclaw para el mapa de
    # grupos del stack (2026-09-18).
    local need=0
    if ! docker ps --filter "name=openclaw-publisher" --format '{{.ID}}' | grep -q .; then
        need=1
    elif ! docker inspect openclaw-publisher --format '{{range .Config.Cmd}}{{.}} {{end}}' 2>/dev/null | grep -q "$GATEWAY_HOST"; then
        log "publisher con target viejo; recreando para $GATEWAY_HOST:$GATEWAY_PORT"
        need=1
    elif [ "$(docker inspect openclaw-publisher --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)" != "host" ]; then
        log "publisher con red vieja; recreando con --network host"
        need=1
    elif [ "$(docker inspect openclaw-publisher --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)" != "unless-stopped" ]; then
        log "publisher con restart policy vieja; recreando con unless-stopped"
        need=1
    elif ! docker inspect openclaw-publisher --format '{{range $k,$v := .Config.Labels}}{{$k}} {{end}}' 2>/dev/null | grep -q "victoria.group"; then
        log "publisher sin label victoria.group; recreando con label"
        need=1
    fi
    if [ "$need" -eq 1 ]; then
        docker rm -f openclaw-publisher >/dev/null 2>&1
        docker run -d --name openclaw-publisher \
            --restart unless-stopped \
            --network host \
            --user 1000:1000 \
            --label victoria.group=openclaw \
            --label victoria.group-role=dashboard \
            -p "0.0.0.0:$PUBLISHER_PORT:$PUBLISHER_PORT" \
            -v "$BRIDGE_SCRIPT":/openclaw-bridge.py:ro \
            python:3.12-slim \
            python3 /openclaw-bridge.py 0.0.0.0 "$PUBLISHER_PORT" "$GATEWAY_HOST" "$GATEWAY_PORT" >/dev/null 2>&1
        log "publisher recreado (listen :$PUBLISHER_PORT -> $GATEWAY_HOST:$GATEWAY_PORT, uid 1000, network=host, restart=unless-stopped, label victoria.group=openclaw)"
    fi
    return 0
}

ensure_voice_server() {
    /home/victoria/openclaw-voice-host.sh ensure >/dev/null 2>&1
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -n "$cid" ] && /home/victoria/openclaw-voice-host.sh ensure >/dev/null 2>&1
    return 0
}

ensure_voice_bridge() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    local log_file="/tmp/tts-bridge-ensure.log"
    local local_md5 remote_md5
    local_md5=$(md5sum /home/victoria/.victoria-custom/bin/tts-bridge.py 2>/dev/null | cut -d' ' -f1)
    remote_md5=$(docker exec "$cid" md5sum /tmp/tts-bridge.py 2>/dev/null | cut -d' ' -f1)
    if [ "$local_md5" != "$remote_md5" ]; then
        docker cp /home/victoria/.victoria-custom/bin/tts-bridge.py "$cid:/tmp/tts-bridge.py" 2>/dev/null
        # 2026-10-04: reinicio por md5 — el proceso vivo correría código viejo
        # (antes: se copiaba el archivo pero NUNCA se reiniciaba → despliegues a medias).
        local bpid
        bpid=$(bridge_pid "$cid" tts-bridge.py)
        if [ -n "$bpid" ]; then
            docker exec "$cid" kill "$bpid" 2>/dev/null
            sleep 1
            log "tts-bridge: pid $bpid matado por md5 — relanzando con código nuevo"
        fi
        log "bridge copiado al sandbox (md5=$local_md5)"
    fi

    if docker exec "$cid" sh -c 'ps aux 2>/dev/null || ps -e' 2>/dev/null | grep -v grep | grep -q '[t]ts-bridge.py'; then
        return 0
    fi

    docker exec --detach "$cid" python3 /tmp/tts-bridge.py
    log "voice bridge lanzado en $cid (sandbox→host voice-server:18810)"

    local retries=0
    while [ "$retries" -lt 10 ]; do
        if docker exec "$cid" sh -c "test -S /tmp/tts-gateway.sock 2>/dev/null"; then
            return 0
        fi
        retries=$((retries + 1))
        sleep 1
    done
    log "ALERTA: tts-gateway.sock no aparecio tras 10s"
}

ensure_ffmpeg() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if docker exec "$cid" sh -c 'command -v ffmpeg >/dev/null 2>&1'; then
        return 0
    fi

    log "ffmpeg no encontrado en sandbox; instalando..."
    if docker exec "$cid" apt-get update -qq 2>/dev/null && \
       docker exec "$cid" apt-get install -y -qq ffmpeg 2>/dev/null && \
       docker exec "$cid" dpkg --configure -a 2>/dev/null; then
        log "ffmpeg instalado en sandbox ($(docker exec $cid ffmpeg -version 2>&1 | head -1))"
    else
        log "ALERTA: fallo instalando ffmpeg en sandbox"
    fi
}

ensure_tts_wrappers() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null

    for wrapper in victoria-tts whisper-cli; do
        local host_bin="/home/victoria/.victoria-custom/bin/$wrapper"
        [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe"; continue; }

        local remote_md5 local_md5
        remote_md5=$(docker exec "$cid" md5sum "$bin_dir/$wrapper" 2>/dev/null | cut -d' ' -f1)
        local_md5=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)

        if [ "$remote_md5" != "$local_md5" ]; then
            docker cp "$host_bin" "$cid:$bin_dir/$wrapper" 2>/dev/null
            docker exec -u root "$cid" chmod +x "$bin_dir/$wrapper" 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/$wrapper" 2>/dev/null
            log "wrapper restaurado: $wrapper (sandbox<-host)"
        fi
    done
    # Limpieza era XTTS (2026-10-03): el wrapper xtts-cli quedó obsoleto
    # (renombrado a victoria-tts, mismo protocolo). Se borra del sandbox.
    docker exec -u root "$cid" rm -f "$bin_dir/xtts-cli" 2>/dev/null
}

ensure_video() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if systemctl is-active --quiet victoria-video-server.service 2>/dev/null; then
        :
    else
        log "video-server host no activo; intentando arrancarlo"
        sudo systemctl start victoria-video-server.service 2>/dev/null || systemctl start victoria-video-server.service 2>/dev/null
    fi

    local lb rb
    lb=$(md5sum /home/victoria/.victoria-custom/bin/video-bridge.py 2>/dev/null | cut -d' ' -f1)
    rb=$(docker exec "$cid" md5sum /tmp/video-bridge.py 2>/dev/null | cut -d' ' -f1)
    if [ "$lb" != "$rb" ]; then
        docker cp /home/victoria/.victoria-custom/bin/video-bridge.py "$cid:/tmp/video-bridge.py" 2>/dev/null
        # 2026-10-04: reinicio por md5 (proceso vivo = código viejo)
        local bpid
        bpid=$(bridge_pid "$cid" video-bridge.py)
        if [ -n "$bpid" ]; then
            docker exec "$cid" kill "$bpid" 2>/dev/null
            sleep 1
            log "video-bridge: pid $bpid matado por md5 — relanzando con código nuevo"
        fi
        log "video-bridge copiado al sandbox (md5=$lb)"
    fi
    if ! docker exec "$cid" sh -c 'ps aux 2>/dev/null || ps -e' 2>/dev/null | grep -v grep | grep -q '[v]ideo-bridge.py'; then
        docker exec --detach "$cid" python3 /tmp/video-bridge.py
        log "video-bridge lanzado en $cid (sandbox→host video-server:18811)"
    fi
    local retries=0
    while [ "$retries" -lt 10 ]; do
        if docker exec "$cid" sh -c "test -S /tmp/video-gateway.sock 2>/dev/null"; then
            break
        fi
        retries=$((retries + 1)); sleep 1
    done

    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null
    for wrapper in video-dl video-analyze video-analyze-local; do
        local host_bin="/home/victoria/.victoria-custom/bin/$wrapper"
        [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe"; continue; }
        # El canonico del host DEBE ser ejecutable
        [ -x "$host_bin" ] || chmod +x "$host_bin"
        local rw lw
        rw=$(docker exec "$cid" md5sum "$bin_dir/$wrapper" 2>/dev/null | cut -d' ' -f1)
        lw=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)
        if [ "$rw" != "$lw" ]; then
            docker cp "$host_bin" "$cid:$bin_dir/$wrapper" 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/$wrapper" 2>/dev/null
            log "wrapper video restaurado: $wrapper"
        fi
        # Fix permanente de permisos: aplicar +x SIEMPRE (aunque md5 no cambie),
        # para que un rebuild/persist.sh que pierda el bit ejecutable se repare solo.
        docker exec -u root "$cid" chmod 755 "$bin_dir/$wrapper" 2>/dev/null
    done

    local ws_skill="/sandbox/.openclaw/workspace/skills/video/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/video/SKILL.md"
    local hk rk
    hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
    rk=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
    if [ "$hk" != "$rk" ]; then
        docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/video 2>/dev/null
        docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills 2>/dev/null
        log "skill video restaurado en workspace"
    fi
}

# ensure_hunyuan3d (2026-10-09): reasegura image-to-3D local para el sandbox.
# hunyuan-server vive en el HOST (victoria-hunyuan3d.service :18860, venv
# hunyuan-venv cu130). El sandbox lo consume por TCP directo 172.18.0.1:18860
# (red docker trusted en sense_auth, sin llave — mismo patrón que los wrappers
# de voz que apuntan a 172.18.0.1:18810; el wrapper sube la foto en base64 y
# descarga el GLB por /file/). Anti-rebuild: re-copia wrapper + skill.
ensure_hunyuan3d() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if systemctl is-active --quiet victoria-hunyuan3d.service 2>/dev/null; then
        :
    else
        log "hunyuan3d host no activo; intentando arrancarlo"
        sudo systemctl start victoria-hunyuan3d.service 2>/dev/null || systemctl start victoria-hunyuan3d.service 2>/dev/null
    fi

    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null
    local host_bin="/home/victoria/.victoria-custom/bin/art-3d"
    [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe"; return 0; }
    [ -x "$host_bin" ] || chmod +x "$host_bin"
    local rw lw
    rw=$(docker exec "$cid" md5sum "$bin_dir/art-3d" 2>/dev/null | cut -d' ' -f1)
    lw=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)
    if [ "$rw" != "$lw" ]; then
        docker cp "$host_bin" "$cid:$bin_dir/art-3d" 2>/dev/null
        docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/art-3d" 2>/dev/null
        log "wrapper hunyuan3d restaurado: art-3d"
    fi
    docker exec -u root "$cid" chmod 755 "$bin_dir/art-3d" 2>/dev/null

    local ws_skill="/sandbox/.openclaw/workspace/skills/hunyuan3d/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/hunyuan3d/SKILL.md"
    local hk rk
    hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
    rk=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
    if [ "$hk" != "$rk" ]; then
        docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/hunyuan3d 2>/dev/null
        docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills 2>/dev/null
        log "skill hunyuan3d restaurado en workspace"
    fi
}

# ensure_lpanimate (2026-10-09): reasegura Animar por chat para el sandbox.
# El render vive en el HOST (daemon victoria-lp-animate.service :18861, thin
# stdlib sobre el CLI lp-animate + liveportrait-venv; presets SOLO host).
# El sandbox lo consume por TCP directo 172.18.0.1:18861 (mismo patrón que
# art-3d a :18860: wrapper idéntico dual-mode + foto en base64 + mp4 por
# /file/). Anti-rebuild: re-copia wrapper + skill animar por md5.
ensure_lpanimate() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if systemctl is-active --quiet victoria-lp-animate.service 2>/dev/null; then
        :
    else
        log "lp-animate host no activo; intentando arrancarlo"
        sudo systemctl start victoria-lp-animate.service 2>/dev/null || systemctl start victoria-lp-animate.service 2>/dev/null
    fi
    if [ ! -f /home/victoria/.victoria-custom/lp-presets/01-saludo.mp4 ]; then
        log "ALERTA: lp-presets incompletos en el host (el daemon no puede resolver presets)"
    fi

    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null
    local host_bin="/home/victoria/.victoria-custom/bin/lp-animate"
    [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe"; return 0; }
    [ -x "$host_bin" ] || chmod +x "$host_bin"
    local rw lw
    rw=$(docker exec "$cid" md5sum "$bin_dir/lp-animate" 2>/dev/null | cut -d' ' -f1)
    lw=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)
    if [ "$rw" != "$lw" ]; then
        docker cp "$host_bin" "$cid:$bin_dir/lp-animate" 2>/dev/null
        docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/lp-animate" 2>/dev/null
        log "wrapper lpanimate restaurado: lp-animate"
    fi
    docker exec -u root "$cid" chmod 755 "$bin_dir/lp-animate" 2>/dev/null

    local ws_skill="/sandbox/.openclaw/workspace/skills/animar/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/animar/SKILL.md"
    if [ -f "$h_skill" ]; then
        local hk rk
        hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
        rk=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
        if [ "$hk" != "$rk" ]; then
            docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/animar 2>/dev/null
            docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
            docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills/animar 2>/dev/null
            log "skill animar restaurado en workspace"
        fi
    fi
}

# ensure_whois: reasegura whois del host para el sandbox.
# El sandbox NO puede instalar whois (apt roto) ni salir por el puerto TCP 43
# (proxy L7 solo 80/443). whois-server vive en el HOST (victoria-whois-server.service
# :18830, apt sano) y el sandbox lo consume via whois-bridge (UNIX socket
# /tmp/whois-gateway.sock -> host.docker.internal:18830). Anti-rebuild: copia el
# bridge + wrapper tras docker rm -f (2026-08-28).
ensure_whois() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if systemctl is-active --quiet victoria-whois-server.service 2>/dev/null; then
        :
    else
        log "whois-server host no activo; intentando arrancarlo"
        sudo systemctl start victoria-whois-server.service 2>/dev/null || systemctl start victoria-whois-server.service 2>/dev/null
    fi

    local lb rb
    lb=$(md5sum /home/victoria/.victoria-custom/bin/whois-bridge.py 2>/dev/null | cut -d' ' -f1)
    rb=$(docker exec "$cid" md5sum /tmp/whois-bridge.py 2>/dev/null | cut -d' ' -f1)
    if [ "$lb" != "$rb" ]; then
        docker cp /home/victoria/.victoria-custom/bin/whois-bridge.py "$cid:/tmp/whois-bridge.py" 2>/dev/null
        # 2026-10-04: reinicio por md5 (proceso vivo = código viejo)
        local bpid
        bpid=$(bridge_pid "$cid" whois-bridge.py)
        if [ -n "$bpid" ]; then
            docker exec "$cid" kill "$bpid" 2>/dev/null
            sleep 1
            log "whois-bridge: pid $bpid matado por md5 — relanzando con código nuevo"
        fi
        log "whois-bridge copiado al sandbox (md5=$lb)"
    fi
    if ! docker exec "$cid" sh -c 'ps aux 2>/dev/null || ps -e' 2>/dev/null | grep -v grep | grep -q '[w]hois-bridge.py'; then
        docker exec --detach "$cid" python3 /tmp/whois-bridge.py
        log "whois-bridge lanzado en $cid (sandbox→host whois-server:18830)"
    fi
    local retries=0
    while [ "$retries" -lt 10 ]; do
        if docker exec "$cid" sh -c "test -S /tmp/whois-gateway.sock 2>/dev/null"; then
            break
        fi
        retries=$((retries + 1)); sleep 1
    done

    local bin_dir="/sandbox/.openclaw/bin"
    local host_bin="/home/victoria/.victoria-custom/bin/whois"
    [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe (whois)"; return 0; }
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null
    local rw lw
    rw=$(docker exec "$cid" md5sum "$bin_dir/whois" 2>/dev/null | cut -d' ' -f1)
    lw=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)
    if [ "$rw" != "$lw" ]; then
        docker cp "$host_bin" "$cid:$bin_dir/whois" 2>/dev/null
        docker exec -u root "$cid" chmod 755 "$bin_dir/whois" 2>/dev/null
        docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/whois" 2>/dev/null
        log "wrapper whois restaurado: whois"
    fi

    # skill domain (analisis de dominios): copiar si difiere
    local ws_skill="/sandbox/.openclaw/workspace/skills/domain/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/domain/SKILL.md"
    local hk rk
    hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
    rk=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
    if [ "$hk" != "$rk" ]; then
        docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/domain 2>/dev/null
        docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills/domain 2>/dev/null
        log "skill domain restaurado en workspace"
    fi
}

# ensure_art: reasegura el wrapper de generación de IMÁGENES (art-gen) + skill
# para el sandbox (2026-10-03). El wrapper habla con la art API del gateway
# (:8010) desde el netns; llave dedicada rol art en .art-key (600, uid 998).
# SOLO imágenes — video excluido por política del owner.
ensure_art() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    local bin_dir="/sandbox/.openclaw/bin"
    local host_bin="/home/victoria/.victoria-custom/bin/art-gen"
    [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe (art-gen)"; return 0; }
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null

    local ra la
    ra=$(docker exec "$cid" md5sum "$bin_dir/art-gen" 2>/dev/null | cut -d' ' -f1)
    la=$(md5sum "$host_bin" | cut -d' ' -f1)
    if [ "$ra" != "$la" ]; then
        docker cp "$host_bin" "$cid:$bin_dir/art-gen" 2>/dev/null
        log "art-gen copiado al sandbox (md5=$la)"
    fi
    docker exec -u root "$cid" chmod 755 "$bin_dir/art-gen" 2>/dev/null

    # art-approve (2026-10-05): ventanas por grupo, solo owner vía DM
    local host_appr="/home/victoria/.victoria-custom/bin/art-approve"
    if [ -f "$host_appr" ]; then
        local rap lap
        rap=$(docker exec "$cid" md5sum "$bin_dir/art-approve" 2>/dev/null | cut -d' ' -f1)
        lap=$(md5sum "$host_appr" | cut -d' ' -f1)
        if [ "$rap" != "$lap" ]; then
            docker cp "$host_appr" "$cid:$bin_dir/art-approve" 2>/dev/null
            log "art-approve copiado al sandbox (md5=$lap)"
        fi
        docker exec -u root "$cid" chmod 755 "$bin_dir/art-approve" 2>/dev/null
        docker exec -u root "$cid" chown 998:998 "$bin_dir/art-approve" 2>/dev/null
    fi

    # archivo de ventanas (2026-10-05 v2): init {scopes,pending} si falta, NUNCA sobreescribir
    docker exec "$cid" sh -c "[ -f /sandbox/.openclaw/workspace/art-approvals.json ] || echo '{\"scopes\":{},\"pending\":{}}' > /sandbox/.openclaw/workspace/art-approvals.json; chown sandbox:sandbox /sandbox/.openclaw/workspace/art-approvals.json" 2>/dev/null

    # llave de la art API (rol art): sincronizada desde secrets del host
    local host_key="/home/victoria/.victoria-custom/secrets/sandbox-art.key"
    if [ -f "$host_key" ]; then
        local rk lk
        rk=$(docker exec "$cid" md5sum "$bin_dir/.art-key" 2>/dev/null | cut -d' ' -f1)
        lk=$(md5sum "$host_key" | cut -d' ' -f1)
        if [ "$rk" != "$lk" ]; then
            docker cp "$host_key" "$cid:$bin_dir/.art-key" 2>/dev/null
            log "art-key sincronizado al sandbox"
        fi
        docker exec -u root "$cid" chmod 600 "$bin_dir/.art-key" 2>/dev/null
    fi
    docker exec -u root "$cid" chown 998:998 "$bin_dir/art-gen" "$bin_dir/.art-key" 2>/dev/null

    # skill art en el workspace
    local h_skill="/home/victoria/.victoria-custom/skills/art/SKILL.md"
    local ws_skill="/sandbox/.openclaw/workspace/skills/art/SKILL.md"
    if [ -f "$h_skill" ]; then
        local rs ls_
        rs=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
        ls_=$(md5sum "$h_skill" | cut -d' ' -f1)
        if [ "$rs" != "$ls_" ]; then
            docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/art 2>/dev/null
            docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
            log "skill art restaurado en workspace"
        fi
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills/art 2>/dev/null
    fi

    # skills web + vox (2026-10-09, modo creativo Fase A): decisión operativa
    # (cuándo navegar / voz vs texto). Mismo patrón anti-rebuild que skill art.
    # pdf (2026-10-17): generación local de PDFs con fpdf2 (lección CV 10-16).
    for sk in web vox pdf; do
        local h_sk="/home/victoria/.victoria-custom/skills/$sk/SKILL.md"
        local ws_sk="/sandbox/.openclaw/workspace/skills/$sk/SKILL.md"
        if [ -f "$h_sk" ]; then
            local rs2 ls2
            rs2=$(docker exec "$cid" md5sum "$ws_sk" 2>/dev/null | cut -d' ' -f1)
            ls2=$(md5sum "$h_sk" | cut -d' ' -f1)
            if [ "$rs2" != "$ls2" ]; then
                docker exec -u root "$cid" mkdir -p "/sandbox/.openclaw/workspace/skills/$sk" 2>/dev/null
                docker cp "$h_sk" "$cid:$ws_sk" 2>/dev/null
                log "skill $sk restaurado en workspace"
            fi
            docker exec -u root "$cid" chown -R sandbox:sandbox "/sandbox/.openclaw/workspace/skills/$sk" 2>/dev/null
        fi
    done

    # TOOLS.md con bloque art + antibucles (2026-10-05): se inyecta INTEGRO en el
    # prompt (injectedWorkspaceFiles). Solo restaura si el live es template
    # (sin el marcador) para no pisar ediciones live de Victoria.
    local h_tools="/home/victoria/.victoria-custom/openclaw-TOOLS.md"
    local ws_tools="/sandbox/.openclaw/workspace/TOOLS.md"
    if [ -f "$h_tools" ]; then
        local has_block
        has_block=$(docker exec "$cid" grep -q "Generar IMÁGENES (skill art)" "$ws_tools" 2>/dev/null; echo "$?")
        if [ "${has_block:-1}" != "0" ]; then
            docker cp "$h_tools" "$cid:$ws_tools" 2>/dev/null
            log "TOOLS.md con bloque art restaurado en workspace"
        fi
        docker exec -u root "$cid" chown sandbox:sandbox "$ws_tools" 2>/dev/null || true
    fi

    # HEARTBEAT.md solo-comentarios (2026-10-05): desactiva el heartbeat poll
    # (skip reason=empty-heartbeat-file) — un poll filtró texto al DM del owner.
    # El template de fábrica (con doc en texto) lo re-activa tras rebuild.
    local h_hb="/home/victoria/.victoria-custom/openclaw-HEARTBEAT.md"
    local ws_hb="/sandbox/.openclaw/workspace/HEARTBEAT.md"
    if [ -f "$h_hb" ]; then
        local hb_rmd5 hb_hmd5
        hb_rmd5=$(docker exec "$cid" md5sum "$ws_hb" 2>/dev/null | cut -d' ' -f1)
        hb_hmd5=$(md5sum "$h_hb" | cut -d' ' -f1)
        if [ "$hb_rmd5" != "$hb_hmd5" ]; then
            docker cp "$h_hb" "$cid:$ws_hb" 2>/dev/null
            log "HEARTBEAT.md solo-comentarios restaurado (heartbeat off)"
        fi
        docker exec -u root "$cid" chown sandbox:sandbox "$ws_hb" 2>/dev/null || true
    fi

    # fotos personales de Victoria (2026-10-05): repo canónico host ->
    # media/outbound/victoria-photos/ (outbound = managed root del gateway,
    # el send CLI puede adjuntar directo sin cp). El agente las comparte
    # cuando piden "una imagen de ELLA" (NO genera). Sync por md5.
    local h_photos="/home/victoria/.victoria-custom/victoria-photos"
    local r_photos="/sandbox/.openclaw/media/outbound/victoria-photos"
    if [ -d "$h_photos" ]; then
        docker exec -u root "$cid" mkdir -p "$r_photos" 2>/dev/null
        local p_need=0
        for pf in "$h_photos"/*; do
            [ -f "$pf" ] || continue
            local pbn pr_md5 ph_md5
            pbn=$(basename "$pf")
            pr_md5=$(docker exec "$cid" md5sum "$r_photos/$pbn" 2>/dev/null | cut -d' ' -f1)
            ph_md5=$(md5sum "$pf" | cut -d' ' -f1)
            if [ "$pr_md5" != "$ph_md5" ]; then
                docker cp "$pf" "$cid:$r_photos/$pbn" 2>/dev/null
                p_need=1
            fi
        done
        [ "$p_need" = "1" ] && log "fotos victoria-photos sincronizadas al sandbox"
        docker exec -u root "$cid" chown -R sandbox:sandbox "$r_photos" 2>/dev/null
    fi

    # art-bridge (2026-10-05): socket UNIX /tmp/art-gateway.sock (container level)
    # -> 172.18.0.1:8010 directo. Sin esto art-gen muere en policy_denied (el
    # netns del gateway sale solo por proxy L7 y los presets de usuario no
    # pueden abrir destinos privados). Mismo patron que tts/video/whois/admin.
    local h_abridge="/home/victoria/.victoria-custom/bin/art-bridge.py"
    local r_abridge="/tmp/art-bridge.py"
    local a_sock="/tmp/art-gateway.sock"
    if [ -f "$h_abridge" ]; then
        local ha_md5 ra_md5
        ha_md5=$(md5sum "$h_abridge" 2>/dev/null | cut -d' ' -f1)
        ra_md5=$(docker exec "$cid" md5sum "$r_abridge" 2>/dev/null | cut -d' ' -f1)
        if [ "$ha_md5" != "$ra_md5" ]; then
            docker cp "$h_abridge" "$cid:$r_abridge" 2>/dev/null
            local abpid
            abpid=$(bridge_pid "$cid" art-bridge.py)
            if [ -n "$abpid" ]; then
                docker exec "$cid" kill "$abpid" 2>/dev/null
                sleep 1
                log "art-bridge: pid $abpid matado por md5 — relanzando con código nuevo"
            fi
            log "art-bridge copiado al sandbox (md5=$ha_md5)"
        fi
        if docker exec "$cid" sh -c 'ps aux 2>/dev/null || ps -e 2>/dev/null' 2>/dev/null | grep -v grep | grep -q '[a]rt-bridge.py'; then
            :
        else
            docker exec --detach "$cid" python3 "$r_abridge" 2>/dev/null
            log "art bridge lanzado en $cid (sandbox→172.18.0.1:8010)"
        fi
        if ! docker exec "$cid" sh -c "test -S $a_sock 2>/dev/null"; then
            log "ALERTA: art-gateway.sock no aparecio (art-gen caera a TCP/policy_denied)"
        fi
    fi

    # art-pending-notify (2026-10-06): job nativo del scheduler del runtime
    # (docs/automation/cron-jobs.md "Event triggers") — sensor headless cada 2m
    # (0 inferencia) que dispara un agent-turn aislado SOLO cuando hay pedidos
    # de imagen nuevos esperando al owner; el agente avisa por DM. Sobrevive al
    # rebuild re-declarandolo (declaration-key converge: created:false/updated:true
    # — PISA el payload, re-declarar SIEMPRE con el texto canónico completo).
    local h_watch="/home/victoria/.victoria-custom/bin/art-pending-watcher.js"
    local ws_watch="/sandbox/.openclaw/workspace/art-pending-watcher.js"
    if [ -f "$h_watch" ]; then
        local w_rmd5 w_hmd5
        w_rmd5=$(docker exec "$cid" md5sum "$ws_watch" 2>/dev/null | cut -d' ' -f1)
        w_hmd5=$(md5sum "$h_watch" | cut -d' ' -f1)
        if [ "$w_rmd5" != "$w_hmd5" ]; then
            docker cp "$h_watch" "$cid:$ws_watch" 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox "$ws_watch" 2>/dev/null || true
            log "art-pending-watcher.js copiado al workspace"
        fi
        local gw_pid gw_tok
        gw_pid=$(docker exec "$cid" sh -c 'pgrep -f openclaw-gateway | head -1' 2>/dev/null)
        gw_tok=$(docker exec "$cid" python3 -c "import json; print(json.load(open('/sandbox/.openclaw/openclaw.json'))['gateway']['auth']['token'])" 2>/dev/null)
        if [ -n "$gw_pid" ] && [ -n "$gw_tok" ]; then
            # FIX 2026-10-06 12:00: re-declarar CADA ciclo (15s) reseteaba el
            # timer every-2m del sensor (nunca evaluaba) + spameaba el log
            # (~2800 "job added"). Ahora: solo declarar si el job FALTA.
            local job_present
            job_present=$(docker exec "$cid" nsenter -t "$gw_pid" -n -- env HOME=/sandbox \
                OPENCLAW_GATEWAY_URL='ws://127.0.0.1:18790' OPENCLAW_GATEWAY_TOKEN="$gw_tok" \
                runuser -u sandbox -- openclaw cron list 2>/dev/null | grep -c "art-pending-notify" || true)
            if [ "${job_present:-0}" = "0" ]; then
                docker exec "$cid" nsenter -t "$gw_pid" -n -- env HOME=/sandbox \
                    OPENCLAW_GATEWAY_URL='ws://127.0.0.1:18790' OPENCLAW_GATEWAY_TOKEN="$gw_tok" \
                runuser -u sandbox -- openclaw automations add \
                --name "art-pending-notify" \
                --declaration-key "victoria:art-pending-notify" \
                --description "Sensor 2m de pedidos de imagen pendientes (sin LLM) — dispara aviso DM al owner solo con pedidos nuevos" \
                --every 2m \
                --trigger-script "$ws_watch" \
                --message "[AVISO AUTOMATICO · pendientes de arte] El sensor detecto pedidos de imagen nuevos esperando TU aprobacion (detalle arriba). Tu UNICA tarea: avisar a Alfredo (mi padre, el owner) por DM de WhatsApp al +18295468686, en espanol, breve y claro: que grupo, quien pidio, que pidio, y que puede aprobar respondiendo \"aprueba <grupo> 4\" o denegar con \"deniega <grupo>\". NO escribas nada en ningun grupo. NO generes imagenes. NO menciones este mecanismo. Si el envio falla, reintentalo una vez. Comando de envio: env HOME=/sandbox OPENCLAW_HOME=/sandbox openclaw message send --channel whatsapp --target +18295468686 --message \"<tu texto>\" --json — verifica que la respuesta traiga messageId. Corres en sesion aislada: no hay conversacion previa, solo este aviso." \
                --session isolated --light-context --no-deliver >/dev/null 2>&1 || log "ALERTA: no se pudo re-declarar art-pending-notify"
            fi
        fi
    fi
}

# ensure_admin: reasegura el Host Admin Bridge (victoria-host-admin) para el sandbox.
# Da a Victoria acceso SEGURO a tools del host (dig/curl/whois/...), apt install
# (allowlist) y servicios del stack via admin-bridge (UNIX socket
# /tmp/admin-gateway.sock -> host.docker.internal:18840) + wrapper admin-cli.
# Anti-rebuild: copia bridge + wrapper + key + skill tras docker rm -f (2026-08-29).
ensure_admin() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    if systemctl is-active --quiet victoria-host-admin.service 2>/dev/null; then
        :
    else
        log "victoria-host-admin no activo; intentando arrancarlo"
        sudo systemctl start victoria-host-admin.service 2>/dev/null || systemctl start victoria-host-admin.service 2>/dev/null
    fi

    # key del admin bridge (secreto del sandbox)
    docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/.secrets 2>/dev/null
    if [ -f /home/victoria/.victoria-custom/secrets/admin-bridge.key ]; then
        local key_host key_sbox
        key_host=$(md5sum /home/victoria/.victoria-custom/secrets/admin-bridge.key 2>/dev/null | cut -d' ' -f1)
        key_sbox=$(docker exec "$cid" md5sum /sandbox/.openclaw/.secrets/admin-bridge.key 2>/dev/null | cut -d' ' -f1)
        if [ "$key_host" != "$key_sbox" ]; then
            docker cp /home/victoria/.victoria-custom/secrets/admin-bridge.key "$cid:/sandbox/.openclaw/.secrets/admin-bridge.key" 2>/dev/null
            docker exec -u root "$cid" chmod 600 /sandbox/.openclaw/.secrets/admin-bridge.key 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox /sandbox/.openclaw/.secrets/admin-bridge.key 2>/dev/null
            log "admin-bridge key copiada al sandbox"
        fi
    else
        log "ALERTA: falta admin-bridge.key en host"
    fi

    local lb rb
    lb=$(md5sum /home/victoria/.victoria-custom/bin/admin-bridge.py 2>/dev/null | cut -d' ' -f1)
    rb=$(docker exec "$cid" md5sum /tmp/admin-bridge.py 2>/dev/null | cut -d' ' -f1)
    if [ "$lb" != "$rb" ]; then
        docker cp /home/victoria/.victoria-custom/bin/admin-bridge.py "$cid:/tmp/admin-bridge.py" 2>/dev/null
        # 2026-10-04: reinicio por md5 (proceso vivo = código viejo)
        local bpid
        bpid=$(bridge_pid "$cid" admin-bridge.py)
        if [ -n "$bpid" ]; then
            docker exec "$cid" kill "$bpid" 2>/dev/null
            sleep 1
            log "admin-bridge: pid $bpid matado por md5 — relanzando con código nuevo"
        fi
        log "admin-bridge copiado al sandbox (md5=$lb)"
    fi
    if ! docker exec "$cid" sh -c 'ps aux 2>/dev/null || ps -e' 2>/dev/null | grep -v grep | grep -q '[a]dmin-bridge.py'; then
        docker exec --detach "$cid" python3 /tmp/admin-bridge.py
        log "admin-bridge lanzado en $cid (sandbox->host victoria-host-admin:18840)"
    fi
    local retries=0
    while [ "$retries" -lt 10 ]; do
        if docker exec "$cid" sh -c "test -S /tmp/admin-gateway.sock 2>/dev/null"; then
            break
        fi
        retries=$((retries + 1)); sleep 1
    done

    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null
    local rw lw
    rw=$(docker exec "$cid" md5sum "$bin_dir/admin-cli" 2>/dev/null | cut -d' ' -f1)
    lw=$(md5sum /home/victoria/.victoria-custom/bin/admin-cli 2>/dev/null | cut -d' ' -f1)
    if [ "$rw" != "$lw" ]; then
        docker cp /home/victoria/.victoria-custom/bin/admin-cli "$cid:$bin_dir/admin-cli" 2>/dev/null
        docker exec -u root "$cid" chmod 755 "$bin_dir/admin-cli" 2>/dev/null
        docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/admin-cli" 2>/dev/null
        log "wrapper admin-cli restaurado"
    fi

    # skill admin: copiar si difiere
    local ws_skill="/sandbox/.openclaw/workspace/skills/admin/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/admin/SKILL.md"
    local hk rk2
    hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
    rk2=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
    if [ "$hk" != "$rk2" ]; then
        docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/admin 2>/dev/null
        docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills/admin 2>/dev/null
        log "skill admin restaurado en workspace"
    fi
}

ensure_npm_plugins() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 1
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 1
    # Detección flexible de layout: 2026.7.x usa npm/projects/openclaw-<canal>-*
    # (glob sobrevive a sufijos hash); runtimes nuevos pueden usar extensions/.
    local have_discord have_whatsapp
    have_discord=$(docker exec "$cid" sh -c 'test -f /sandbox/.openclaw/npm/projects/openclaw-discord-*/node_modules/@openclaw/discord/dist/index.js -o -f /sandbox/.openclaw/extensions/discord/dist/index.js && echo yes || echo no' 2>/dev/null)
    have_whatsapp=$(docker exec "$cid" sh -c 'test -f /sandbox/.openclaw/npm/projects/openclaw-whatsapp-*/node_modules/@openclaw/whatsapp/dist/index.js -o -f /sandbox/.openclaw/extensions/whatsapp/dist/index.js && echo yes || echo no' 2>/dev/null)
    [ "$have_discord" = "yes" ] && [ "$have_whatsapp" = "yes" ] && return 0
    # NATIVO PRIMERO (2026-10-05): npm egress abierto (personal-open-internet) —
    # `openclaw plugins install` baja la versión MATCHING del runtime y escribe
    # install records propios (trusted de fábrica, sin trust-record patch).
    # Siempre uid 998 (NUNCA root). Fallback: tgz local 2026.7.1 (mundo offline).
    if [ "$have_discord" != "yes" ] || [ "${1:-}" = "force" ]; then
        log "plugin discord ausente; install nativo npm (fallback tgz)"
        docker exec -u 998 "$cid" openclaw plugins install @openclaw/discord >/dev/null 2>&1 \
            && log "discord npm install OK" \
            || { /home/victoria/openclaw-discord-fix.sh apply >/dev/null 2>&1 && log "discord fix tgz OK" || log "discord fix FALLO"; }
    fi
    if [ "$have_whatsapp" != "yes" ] || [ "${1:-}" = "force" ]; then
        log "plugin whatsapp ausente; install nativo npm (fallback tgz)"
        docker exec -u 998 "$cid" openclaw plugins install @openclaw/whatsapp >/dev/null 2>&1 \
            && log "whatsapp npm install OK" \
            || { /home/victoria/openclaw-whatsapp-fix.sh apply >/dev/null 2>&1 && log "whatsapp fix tgz OK" || log "whatsapp fix FALLO"; }
    fi
    docker exec -u root "$cid" chown sandbox:sandbox /sandbox/.openclaw/openclaw.json 2>/dev/null
    return 0
}

ensure_identity_files() {
    local cid
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0
    local ws="/sandbox/.openclaw/workspace"
    docker exec -u root "$cid" mkdir -p "$ws" 2>/dev/null
    docker exec -u root "$cid" chown sandbox:sandbox "$ws" 2>/dev/null

    for f in SOUL IDENTITY USER; do
        local host="/home/victoria/${f}-restore.md"
        local sandbox="${ws}/${f}.md"
        [ -f "$host" ] || continue

        local host_mtime
        host_mtime=$(stat -c %Y "$host" 2>/dev/null || echo 0)

        local sandbox_mtime
        sandbox_mtime=$(docker exec -u root "$cid" sh -c "stat -c %Y '$sandbox' 2>/dev/null || echo 0" 2>/dev/null || echo 0)
        sandbox_mtime="${sandbox_mtime:-0}"

        local is_template=0
        if docker exec -u root "$cid" sh -c "grep -qE 'Fill this in|\(pick something you like\)|Learn about the person' '$sandbox' 2>/dev/null"; then
            is_template=1
        fi

        if [ "$host_mtime" -gt "$sandbox_mtime" ] || [ "$is_template" = "1" ]; then
            docker cp "$host" "$cid:$sandbox" 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox "$sandbox" 2>/dev/null
            log "identidad: ${f}.md sincronizado desde host (template=$is_template host $host_mtime > sandbox $sandbox_mtime)"
        fi
    done
}

# NOTA 2026-09-16: se intento rutear el cerebro del sandbox por el gateway
# (providers.inference -> 172.18.0.1:8010) y se REVIRTIO: el schema OpenClaw
# rechaza top-level "providers" ("Unrecognized key", INVALID_CONFIG -> el
# gateway no bootea). El ruteo de inferencia del sandbox lo posee la
# plataforma nemoclaw (sandboxes.json endpointUrl + managed bootstrap) y no
# se toca. Excepcion documentada: el cerebro del agente es el unico trafico
# fuera del gateway; su carga se ve en /metrics y la admision adaptativa
# reacciona igual. Todo lo demas (opencode, broadcasts, video, art, remoto)
# SI pasa por el gateway con matriz rol x capacidad.
ensure_plugins_allow() {
    # Asegura que openclaw.json tenga plugins.allow configurado.
    # Un rebuild del container resetea el config al template de fábrica
    # que no incluye plugins.allow. El gateway lo requiere para cargar
    # los plugins de canales (discord, whatsapp).
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    local has_allow
    has_allow=$(docker exec "$cid" python3 -c '
import json
with open("/sandbox/.openclaw/openclaw.json") as f:
    c = json.load(f)
al = c.get("plugins", {}).get("allow", [])
print("yes" if al else "no")
' 2>/dev/null)

    # Postura 2770/660 (shared): la impone el gateway vivo (revierte 600→660 en
    # <10s vía su watcher; competir desde ciclos de 15s es inútil). El guard del
    # CLI nemoclaw (0.0.119) espera 0700/0600 privado — version-skew vs el
    # runtime pineado 2026.7.1, warn cosmético (doctor) sin impacto operativo:
    # el stack funcionó 2 días así. Revisar al upgradear el runtime.
    docker exec -u root "$cid" chown sandbox:sandbox /sandbox/.openclaw 2>/dev/null
    docker exec -u root "$cid" chmod 2770 /sandbox/.openclaw 2>/dev/null

    if [ "$has_allow" = "yes" ]; then
        return 0
    fi

    docker exec "$cid" python3 -c '
import json
path = "/sandbox/.openclaw/openclaw.json"
with open(path, "r") as f:
    c = json.load(f)
if "plugins" not in c:
    c["plugins"] = {}
if not c["plugins"].get("allow"):
    c["plugins"]["allow"] = [
        "active-memory", "browser", "canvas", "device-pair",
        "discord", "file-transfer", "memory-core", "ollama",
        "phone-control", "talk-voice", "tts-local-cli",
        "whatsapp"
    ]
with open(path, "w") as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
' 2>/dev/null

    docker exec -u root "$cid" chown sandbox:sandbox /sandbox/.openclaw/openclaw.json 2>/dev/null
    docker exec -u root "$cid" chmod 660 /sandbox/.openclaw/openclaw.json 2>/dev/null

    log "plugins.allow ensured in openclaw.json"
}

ensure_web_nav() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    # Copiar wrappers web-utils.sh al sandbox cada ciclo
    local bin_dir="/sandbox/.openclaw/bin"
    docker exec -u root "$cid" mkdir -p "$bin_dir" 2>/dev/null

    local host_bin="/home/victoria/.victoria-custom/bin/web-utils.sh"
    [ -f "$host_bin" ] || { log "ALERTA: $host_bin no existe"; return 0; }
    local lw rw
    rw=$(docker exec "$cid" md5sum "$bin_dir/web-utils.sh" 2>/dev/null | cut -d' ' -f1)
    lw=$(md5sum "$host_bin" 2>/dev/null | cut -d' ' -f1)
    if [ "$lw" != "$rw" ] || [ -z "$rw" ]; then
        docker cp "$host_bin" "$cid:$bin_dir/web-utils.sh" 2>/dev/null
        docker exec -u root "$cid" chmod 755 "$bin_dir/web-utils.sh" 2>/dev/null
        docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/web-utils.sh" 2>/dev/null
        log "wrapper web-utils restaurado en sandbox"
    fi
    # Wrappers individuales
    for wrapper in web-navigate web-scrape; do
        local wb="/home/victoria/.victoria-custom/bin/$wrapper"
        [ -f "$wb" ] || continue
        local lw2 rw2
        rw2=$(docker exec "$cid" md5sum "$bin_dir/$wrapper" 2>/dev/null | cut -d' ' -f1)
        lw2=$(md5sum "$wb" 2>/dev/null | cut -d' ' -f1)
        if [ "$lw2" != "$rw2" ] || [ -z "$rw2" ]; then
            docker cp "$wb" "$cid:$bin_dir/$wrapper" 2>/dev/null
            docker exec -u root "$cid" chmod 755 "$bin_dir/$wrapper" 2>/dev/null
            docker exec -u root "$cid" chown sandbox:sandbox "$bin_dir/$wrapper" 2>/dev/null
            log "wrapper $wrapper restaurado en sandbox"
        fi
    done
}

ensure_ownership_fix() {
    # Fix permanente: docker cp preserva el owner del host (victoria=uid 1000),
    # que dentro del container aparece como 'node'. El gateway OpenClaw
    # rechaza arrancar si encuentra archivos no-sandbox en /sandbox/.openclaw.
    # ownership: chown -R preserva modos (verificado); el modo del dir lo fija
    # ensure_plugins_allow (2770, postura shared que impone el gateway vivo).
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0
    docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw 2>/dev/null
}

# ensure_policies: re-aplica el egress del agente que un rebuild (`onboard
# --fresh`) resetea (weather, RSS y web general se pierden → Victoria sin clima,
# noticias ni web_fetch).
#
# REGLAS (lección 2026-09-19):
# 1. CRITICO: nemoclaw SIEMPRE como victoria (runuser). Como ROOT el contexto
#    está roto: los adds fallan en silencio (213 ciclos de errores tragados).
# 2. personal-open-internet es el switch maestro: su regla broad 80/443 SUBSUME
#    las específicas (weather/rss/etc). Tras aplicarlo, `policy list` puede
#    mostrar los subsumidos como ○ y sus adds no-opean SILENTES (by design,
#    no es error). NO perseguir ●/○ de presets subsumidos.
# 3. Tras rebuild (todo ○): aplicar el set completo; el broad compacts todo.
ensure_policies() {
    local pl preset
    local NEMO="runuser -u victoria -- env HOME=/home/victoria PATH=/home/victoria/.local/bin:/usr/local/bin:/usr/bin:/bin nemoclaw"
    pl="$($NEMO victoria-armada policy list 2>/dev/null || true)"
    [ -z "$pl" ] && { log "policy list no disponible; skip"; return 0; }
    # art API (2026-10-05): preset victoria-art-api abre 172.18.0.1:8010 para
    # art-gen. Independiente del broad (puertos 80/443 no cubren el 8010).
    # Requiere --trusted-private-host (destino RFC1918, solo declarable asi).
    if ! grep -q "● victoria-art-api" <<<"$pl"; then
        $NEMO victoria-armada policy add --from-file \
            /home/victoria/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/victoria-art-api.yaml \
            --trusted-private-host 172.18.0.1 --yes >/dev/null 2>&1 || true
        log "preset victoria-art-api re-aplicado"
    fi
    if grep -q "● personal-open-internet" <<<"$pl"; then
        return 0  # egress broad activo: cubre weather, RSS y web general
    fi
    log "egress broad faltante; aplicando set de policies tras rebuild/reset"
    for preset in weather personal-open-internet discord whatsapp local-inference brew huggingface npm pypi openclaw-pricing; do
        $NEMO victoria-armada policy add "$preset" >/dev/null 2>&1 || true
    done
    $NEMO victoria-armada policy add --from-file \
        /home/victoria/.nemoclaw/nemoclaw-blueprint/policies/presets-custom/rss-feeds.yaml \
        >/dev/null 2>&1 || true
}

# ensure_alfredopro: reasegura el skill de ventas de Alfredo Pro en el workspace.
# El catálogo (servicios/planes/precios verificados 2026-09-14 en www.alfredo.pro)
# + guion de ventas vive en el HOST; el sandbox lo consume como skill `alfredo-pro`.
# Anti-rebuild: compara md5 y re-copia tras docker rm -f (mismo patrón video/domain/admin).
ensure_alfredopro() {
    local cid
    [ -z "$SANDBOX_NAME" ] && return 0
    cid=$(docker ps --filter "name=$SANDBOX_NAME" --format '{{.ID}}' | head -1)
    [ -z "$cid" ] && return 0

    local ws_skill="/sandbox/.openclaw/workspace/skills/alfredo-pro/SKILL.md"
    local h_skill="/home/victoria/.victoria-custom/skills/alfredo-pro/SKILL.md"
    [ -f "$h_skill" ] || { log "ALERTA: $h_skill no existe"; return 0; }
    local hk rk
    hk=$(md5sum "$h_skill" 2>/dev/null | cut -d' ' -f1)
    rk=$(docker exec "$cid" md5sum "$ws_skill" 2>/dev/null | cut -d' ' -f1)
    if [ "$hk" != "$rk" ]; then
        docker exec -u root "$cid" mkdir -p /sandbox/.openclaw/workspace/skills/alfredo-pro 2>/dev/null
        docker cp "$h_skill" "$cid:$ws_skill" 2>/dev/null
        docker exec -u root "$cid" chown -R sandbox:sandbox /sandbox/.openclaw/workspace/skills 2>/dev/null
        log "skill alfredo-pro restaurado en workspace"
    fi
}

# ensure_sandbox_restart_policy (2026-10-14, forense freeze 2026-10-13):
# el rebuild nemoclaw v0.0.130 (2026-10-05) creó el sandbox con
# RestartPolicy=no — tras el freeze del host (19:00) el sandbox NO auto-arrancó
# con el boot de las 22:47 y WhatsApp/Discord quedaron muertos ~2h (la doc
# decía unless-stopped; el drift lo cazó lo LIVE). docker update es
# metadata-only: no reinicia ni toca el contenedor. Idempotente.
ensure_sandbox_restart_policy() {
    [ -z "$SANDBOX_NAME" ] && return 0
    local pol
    pol=$(docker inspect "$SANDBOX_NAME" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null) || return 0
    if [ "$pol" != "unless-stopped" ]; then
        if docker update --restart unless-stopped "$SANDBOX_NAME" >/dev/null 2>&1; then
            log "restart policy del sandbox: '$pol' -> unless-stopped (blindaje anti-reboot)"
        else
            log "FALLO docker update restart policy del sandbox (revisar a mano)"
        fi
    fi
    return 0
}

while true; do
    resolve_sandbox_name
    ensure_network
    # Lock de bootstrap: durante `nemoclaw onboard` NO tocar el sandbox en
    # absoluto (el managed-bootstrap rechaza workloads con múltiples redes y
    # con archivos/procesos inyectados). Ver CHANGELOG 2026-09-14.
    if [ -f /tmp/openclaw-bootstrap.lock ] || [ -f /home/victoria/.victoria-custom/state/openclaw-bootstrap.lock ]; then
        sleep 15
        continue
    fi
    if ensure_sandbox_connected; then
        ensure_sandbox_restart_policy
        /home/victoria/openclaw-persist.sh auto
        /home/victoria/openclaw-voice-host.sh ensure >/dev/null 2>&1
        ensure_voice_bridge
        ensure_ffmpeg
        ensure_tts_wrappers
        ensure_video
        ensure_hunyuan3d
        ensure_lpanimate
        ensure_whois
        ensure_admin
        ensure_art
        ensure_alfredopro
        ensure_npm_plugins
        /home/victoria/openclaw-discord-fix.sh apply 2>/dev/null
        /home/victoria/openclaw-whatsapp-fix.sh apply 2>/dev/null
        ensure_policies
        /home/victoria/openclaw-rss-install.sh ensure 2>/dev/null
        ensure_identity_files
        /home/victoria/.victoria-custom/openclaw-customize-apply.sh apply 2>/dev/null
        ensure_plugins_allow
        ensure_web_nav
        ensure_ownership_fix
        if [ -f /home/victoria/.nemoclaw/persistent/victoria-armada/.gateway-restart-needed ]; then
            # RUNTIME 2026.9.x: el gateway es lifecycle-managed (docker restart = fase Error
            # que bloquea el forward del dashboard). ESTRATEGIA ADAPTATIVA: dar 4 ciclos
            # (~60s) al hot-reload hybrid para cargar la config restaurada SIN restart;
            # si los canales suben por hot-reload -> listo, sin restart (fase Ready intacta).
            # Solo si no levantan en 4 ciclos -> docker restart como ultimo recurso.
            # NOTA: sin `local` (esto es cuerpo del loop, no funcion; `local`
            # aqui + `set -u` = crash-loop del service). Ver CHANGELOG 2026-10-08.
            WCOUNT_FILE="/home/victoria/.victoria-custom/state/gateway-restart-wait.count"
            wcount=
            wcount=$(cat "$WCOUNT_FILE" 2>/dev/null || echo 0)
            if docker exec "$SANDBOX_NAME" sh -c 'grep -q "Listening for WhatsApp" /tmp/gateway.log 2>/dev/null'; then
                rm -f "$WCOUNT_FILE" /home/victoria/.nemoclaw/persistent/victoria-armada/.gateway-restart-needed 2>/dev/null
                log "restore detectado y canales UP via hot-reload hybrid — sin restart (fase intacta)"
            elif [ "$wcount" -lt 4 ]; then
                wcount=$((wcount + 1))
                echo "$wcount" > "$WCOUNT_FILE" 2>/dev/null
                log "restore detectado; ciclo $wcount/4 — esperando hot-reload hybrid (sin restart)"
            else
                rm -f "$WCOUNT_FILE" 2>/dev/null
                rm -f /home/victoria/.nemoclaw/persistent/victoria-armada/.gateway-restart-needed
                log "hot-reload no levanto canales en 4 ciclos; docker restart del sandbox"
                docker restart "$SANDBOX_NAME" >/dev/null 2>&1 \
                    && log "sandbox reiniciado (docker restart) para cargar config restaurada" \
                    || log "docker restart fallo (revisar a mano)"
            fi
        else
            rm -f /home/victoria/.victoria-custom/state/gateway-restart-wait.count 2>/dev/null
        fi
    else
        log "sandbox no levantado; reintento en 15s"
    fi
    ensure_publisher
    ensure_dashboard_forward
    sleep 15
done
