#!/usr/bin/env bash
# armada-sync.sh — EL sistema de sincronización de Victoria (único, sin duplicados).
#
# Dos trabajos, un solo timer (armada-sync.timer cada 6h):
#   1. backup: snapshot de conocimiento (docs/agentes/changelogs/config).
#   2. docsync: chequeo diario doc-vs-upstream (guarda 24h; corre upstream-sync.py
#      solo si el último chequeo expiró). Solo REPORTA deriva, no actualiza nada.
#   3. fleet (2026-10-08): auditoría del scaffold de la flota — SOLO LECTURA
#      (agent list vs .md vs harness vs changelogs + frontmatter + JSON +
#      frescura + boundary victoria/kalimete). Automatiza la auditoría manual
#      2026-10-08 (patrón vLLM). Corre dentro de `cycle` (no fatal) y standalone.
# El helper doc-fresh.sh (caché TTL por agente) y upstream-sync.py pertenecen a
# este mismo sistema — NO son sistemas separados.
#
# Qué respalda (todo lo que Victoria necesita para NO perder conocimiento):
#   - AGENTS.md (mapa global del stack)
#   - CHANGELOG.md (historial de cambios — append-only)
#   - ~/.config/opencode/agents/*.md (subagentes)
#   - ~/.config/opencode/AGENTS-summary.md (instructions slim, 2026-09-30)
#   - ~/.config/opencode/opencode.jsonc (config viva, SIN secretos)
#   - ~/.victoria-custom/openclaw-overrides.json + customize-apply.sh
#   - ~/.victoria-custom/skills/ + bin/ (wrappers y skills del sandbox)
#   - ~/.nemoclaw/sandboxes.json + onboard-session.json (estado nemoclaw)
#   - llm-gateway.py + admin_template.html (código del gateway)
#   - victoria-gpu-saver.py + metrics-diag.py (observabilidad)
#   - openclaw-*.sh + openclaw-bridge.py (persistencia y bridge)
#   - Archivos de identidad (IDENTITY/SOUL/USER-restore.md)
#   - Nginx/gateway.conf + units systemd (infra)
#
# Qué NUNCA respalda (secretos):
#   - ~/.victoria-custom/secrets/ (HF_TOKEN, nvapi keys, admin-bridge.key)
#   - ~/.victoria-llm/llm-gateway.db (API keys plaintext)
#   - ~/.config/opencode/auth.json (nvapi keys)
#   - /etc/cloudflared/token
#
# Uso:
#   armada-sync.sh backup            # snapshot con timestamp + actualiza latest/
#   armada-sync.sh restore [fecha]   # lista o restaura un snapshot
#   armada-sync.sh status            # muestra snapshots y sizes
#   armada-sync.sh verify            # verifica integridad del último snapshot
#   armada-sync.sh docsync           # chequeo doc-vs-upstream si toca (guarda 24h)
#   armada-sync.sh fleet             # auditoría del scaffold de la flota (solo lectura)
#   armada-sync.sh cycle             # backup + docsync + fleet (lo que corre el timer)
#
# Automatización: systemd timer armada-sync.timer (cada 6h) corre `cycle`.
# Retención: 30 snapshots diarios (rota automáticamente).
#
# Creado 2026-09-14 tras pérdida del historial CHANGELOG por overwrite manual.
# Regla: los docs viven en UN solo lugar canónico; armada-sync es el respaldo,
# NUNCA la fuente de edición.
set -u

SYNC_ROOT="/home/victoria/.armada-sync"
SNAP_DIR="$SYNC_ROOT/snapshots"
LATEST_DIR="$SYNC_ROOT/latest"
LOG_FILE="/home/victoria/logs/armada-sync.log"
RETENTION=30

log() { echo "[armada-sync] $(date -Is) $*" | tee -a "$LOG_FILE"; }

# --- listas de respaldo (relativas a /home/victoria) ---
FILES=(
    "AGENTS.md"
    "CHANGELOG.md"
    ".config/opencode/AGENTS-summary.md"
    ".victoria-custom/infra/devices.md"
    "Documents/Victoria Armada/AGENTS.md"
    "IDENTITY-restore.md"
    "SOUL-restore.md"
    "USER-restore.md"
    "llm-gateway.py"
    "admin_template.html"
    "victoria-gpu-saver.py"
    "metrics-diag.py"
    "openclaw-bridge-ensure.sh"
    "openclaw-bridge.py"
    "openclaw-persist.sh"
    "openclaw-voice-host.sh"
    "openclaw-rss-install.sh"
    "openclaw-discord-fix.sh"
    "openclaw-whatsapp-fix.sh"
    "whatsapp-qr.sh"
    "openclaw-customize-apply.sh"
    "comfyui-models-mover.sh"
    "comfyui-models-downloader.py"
    "comfyui-monitor.py"
    "whois-server.py"
    "victoria-host-admin.py"
    "victoria-video-server.py"
    "web-nav-server.py"
    "nemoclaw-vllm-inspect-backup.json"
    "doc-fresh.sh"
    "upstream-sync.py"
    "victoria-daily-report.py"
    "armada-sync.sh"
)
DIRS=(
    ".config/opencode/agents"
    ".victoria-custom/skills"
    ".victoria-custom/bin"
    ".victoria-custom/remote"
    ".victoria-custom/changelogs"
    ".victoria-custom/harness"
)
# opencode.jsonc se respalda con las API keys redactadas
# sandboxes.json / onboard-session.json son estado, no secreto

do_backup() {
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    local dest="$SNAP_DIR/$ts"
    mkdir -p "$dest" "$LATEST_DIR"
    log "snapshot $ts iniciado"

    local count=0
    for f in "${FILES[@]}"; do
        if [ -f "/home/victoria/$f" ]; then
            mkdir -p "$dest/$(dirname "$f")"
            cp -p "/home/victoria/$f" "$dest/$f"
            count=$((count + 1))
        fi
    done
    for d in "${DIRS[@]}"; do
        if [ -d "/home/victoria/$d" ]; then
            mkdir -p "$dest/$d"
            # Excluye binarios reinstalables (blogwatcher se reinstala con
            # openclaw-rss-install.sh; phoneinfoga vive en kalimete)
            if [ "$d" = ".victoria-custom/bin" ]; then
                for item in /home/victoria/.victoria-custom/bin/*; do
                    base=$(basename "$item")
                    case "$base" in
                        blogwatcher*) continue ;;
                        phoneinfoga*) continue ;;
                    esac
                    cp -rp "$item" "$dest/$d/"
                done
            else
                cp -rp "/home/victoria/$d/." "$dest/$d/"
            fi
            count=$((count + 1))
        fi
    done

    # opencode.jsonc con secretos redactados
    if [ -f /home/victoria/.config/opencode/opencode.jsonc ]; then
        mkdir -p "$dest/.config/opencode"
        sed -E 's/"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"/"apiKey": "REDACTED"/g' \
            /home/victoria/.config/opencode/opencode.jsonc > "$dest/.config/opencode/opencode.jsonc"
        count=$((count + 1))
    fi

    # estado nemoclaw (sin credenciales: solo topología)
    mkdir -p "$dest/.nemoclaw"
    for sf in sandboxes.json onboard-session.json; do
        [ -f "/home/victoria/.nemoclaw/$sf" ] && cp -p "/home/victoria/.nemoclaw/$sf" "$dest/.nemoclaw/$sf"
    done
    # overrides canónicos de OpenClaw
    mkdir -p "$dest/.victoria-custom"
    for of in openclaw-overrides.json openclaw-customize-apply.sh; do
        [ -f "/home/victoria/.victoria-custom/$of" ] && cp -p "/home/victoria/.victoria-custom/$of" "$dest/.victoria-custom/$of"
    done

    # manifiesto del snapshot
    {
        echo "timestamp=$ts"
        echo "host=$(hostname)"
        echo "items=$count"
        echo "gateway_max_prompt_tokens=$(grep -oE 'MAX_PROMPT_TOKENS = [0-9]+' /home/victoria/llm-gateway.py 2>/dev/null | head -1)"
        echo "vllm_digest=$(docker inspect nemoclaw-vllm --format '{{.Image}}' 2>/dev/null || echo unknown)"
        echo "sandbox=$(docker ps --filter 'name=openshell-default--victoria-armada' --format '{{.Names}} {{.Status}}' 2>/dev/null | head -1 || echo none)"
    } > "$dest/MANIFEST.txt"

    # latest/ = copia espejo del último snapshot (lectura rápida)
    rm -rf "$LATEST_DIR"
    cp -rp "$dest" "$LATEST_DIR"

    # rotación: conserva los últimos $RETENTION
    local n
    n=$(ls -1 "$SNAP_DIR" 2>/dev/null | wc -l)
    if [ "$n" -gt "$RETENTION" ]; then
        ls -1 "$SNAP_DIR" | head -n $((n - RETENTION)) | while read -r old; do
            rm -rf "$SNAP_DIR/$old"
            log "rotado snapshot viejo $old"
        done
    fi

    local size
    size=$(du -sh "$dest" | cut -f1)
    log "snapshot $ts completo: $count items, $size"
}

do_status() {
    echo "=== armada-sync ==="
    echo "root: $SYNC_ROOT"
    echo "snapshots: $(ls -1 "$SNAP_DIR" 2>/dev/null | wc -l) (retención: $RETENTION)"
    echo "total: $(du -sh "$SNAP_DIR" 2>/dev/null | cut -f1)"
    echo "--- últimos 5 ---"
    ls -1 "$SNAP_DIR" 2>/dev/null | tail -n 5
    echo "--- último manifiesto ---"
    cat "$SNAP_DIR/$(ls -1 "$SNAP_DIR" 2>/dev/null | tail -n 1)/MANIFEST.txt" 2>/dev/null || echo "(sin snapshots)"
}

do_verify() {
    local latest
    latest=$(ls -1 "$SNAP_DIR" 2>/dev/null | tail -n 1)
    [ -z "$latest" ] && { echo "sin snapshots"; return 1; }
    local dest="$SNAP_DIR/$latest"
    local fail=0
    for must in "AGENTS.md" "CHANGELOG.md" ".config/opencode/agents" ".config/opencode/AGENTS-summary.md"; do
        if [ ! -e "$dest/$must" ]; then
            echo "FALTA: $must"
            fail=1
        fi
    done
    # ningún secreto COMPLETO debió colarse (las docs mencionan prefijos
    # truncados tipo nvapi-AuHo… legítimamente; solo alertar por keys enteras)
    local leaks
    leaks=$(grep -rIlE "nvapi-[A-Za-z0-9._-]{20,}|hf_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY" "$dest" 2>/dev/null | grep -v MANIFEST | head -n 3)
    if [ -n "$leaks" ]; then
        echo "ALERTA: posible secreto en el snapshot:"
        echo "$leaks"
        fail=1
    fi
    # gateway keys completas: SOLO la readonly db13… es compartible por diseño
    # (documentada en AGENTS.md §7.4). Cualquier otra vllm-key entera = leak
    # (higiene 2026-09-19: una admin viva estuvo hardcodeada en tts-bridge.py).
    local vkeys
    vkeys=$(grep -rIoE "vllm-key-[0-9a-f]{60,64}" "$dest" 2>/dev/null | grep -v "vllm-key-db13590a2a256457edde74e3e116b14d181ec01fee533f62225547f7251c7aa7" | head -n 3)
    if [ -n "$vkeys" ]; then
        echo "ALERTA: gateway key completa (no-readonly) en el snapshot:"
        echo "$vkeys" | awk -F: '{print $1}'
        fail=1
    fi
    # opencode.jsonc debe estar redactado
    if grep -q '"apiKey": "vllm-key-' "$dest/.config/opencode/opencode.jsonc" 2>/dev/null; then
        echo "ALERTA: opencode.jsonc con key sin redactar"
        fail=1
    fi
    [ "$fail" -eq 0 ] && echo "verify OK: snapshot $latest íntegro y sin secretos"
    return "$fail"
}

DOCSYNC_TTL=86400
DOCSYNC_STATE="/home/victoria/.victoria-custom/state/upstream.json"

do_docsync() {
    # Chequeo doc-vs-upstream, como máximo 1 vez cada 24h. Solo REPORTA
    # (upstream-sync.py no edita nada); actualizar docs está pre-aprobado
    # por el owner, actualizar servicios/código NO.
    local now last age
    now=$(date +%s)
    last=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(max((v.get("ts",0) for v in d.values()),default=0))' "$DOCSYNC_STATE" 2>/dev/null || echo 0)
    [ -z "$last" ] && last=0
    age=$((now - last))
    if [ "$age" -ge "$DOCSYNC_TTL" ]; then
        log "docsync: último hace $((age/3600))h, corriendo upstream-sync.py"
        /usr/bin/python3 /home/victoria/upstream-sync.py || log "docsync: upstream-sync falló (reintenta próximo ciclo)"
    else
        log "docsync: al día (hace $((age/3600))h), se omite"
    fi
}

do_offsite() {
    # Off-site push (2026-11-03, pendiente #3 owner "procede"): espeja latest/
    # en ~/.armada-sync/offsite/ (worktree git dedicado) y hace push al repo
    # privado warcold/victoria-sync. NO-FATAL: sin remote/key salta en silencio.
    # El repo lo crea el owner (GitHub UI) + deploy key id_github_victoria.
    local wt="/home/victoria/.armada-sync/offsite"
    [ -d "$wt/.git" ] || { log "offsite: worktree sin .git, skip"; return 0; }
    if ! git -C "$wt" remote get-url origin >/dev/null 2>&1; then
        log "offsite: sin remote origin (repo pendiente del owner), skip"
        return 0
    fi
    rsync -a --delete --exclude .git "$LATEST_DIR/" "$wt/" 2>/dev/null || { log "offsite: rsync fallo, skip"; return 0; }
    git -C "$wt" add -A >/dev/null 2>&1
    if git -C "$wt" diff --cached --quiet >/dev/null 2>&1; then
        log "offsite: sin cambios nuevos"
        return 0
    fi
    git -C "$wt" commit -q -m "snapshot $(date +%Y%m%d-%H%M%S) ($(hostname))" >/dev/null 2>&1
    if timeout 60 git -C "$wt" push -q origin main >/dev/null 2>&1; then
        log "offsite: push OK a $(git -C "$wt" remote get-url origin 2>/dev/null)"
    else
        log "offsite: push FALLO (remote/key?) — el commit local queda, reintenta el proximo ciclo"
        return 1
    fi
}

do_cycle() {
    do_backup
    do_docsync
    do_fleet || log "fleet: scaffold con hallazgos (ver arriba, no fatal)"
    do_granja_drift || log "granja-drift: con hallazgos (ver arriba, no fatal)"
    do_offsite || log "offsite: con fallo (ver arriba, no fatal)"
}

do_granja_drift() {
    # Drift-check cross-machine (2026-10-29, aprobado por el owner): compara el
    # catálogo LIVE /v1/granja del gateway contra lo que kalimete documenta de
    # la granja (skills + agente victoria-server). SOLO LECTURA + reporte a
    # state/granja-drift.json. Exit 0 = sincronizado, 1 = drift.
    local state_f="/home/victoria/.victoria-custom/state/granja-drift.json"
    local key out drift=0
    key=$(sqlite3 /home/victoria/.victoria-llm/llm-gateway.db \
        "SELECT key_plaintext FROM api_keys WHERE name='kalimete' AND active=1" 2>/dev/null | head -1)
    [ -z "$key" ] && { log "granja-drift: sin llave kalimete, skip"; return 0; }
    out=$(curl -s -m 15 -H "Authorization: Bearer $key" http://127.0.0.1:8010/v1/granja 2>/dev/null)
    [ -z "$out" ] && { log "granja-drift: /v1/granja no responde, skip"; return 0; }
    # Servicios vivos según el gateway
    local vivos
    vivos=$(echo "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(k for k,v in d.get("health_probes",{}).items() if v=="up"))' 2>/dev/null)
    # Lo que kalimete documenta (skills con fuente viva + agente con catálogo)
    local kcheck
    kcheck=$(ssh -i ~/.ssh/id_victoria -p 1111 -o ConnectTimeout=8 -o BatchMode=yes warcold@kalimete.local '
        n=0
        for s in art voice-video assets-3d; do
            grep -q "v1/granja" ~/.config/opencode/skills/$s/SKILL.md 2>/dev/null && n=$((n+1))
        done
        grep -q "Catálogo de puertos" ~/.config/opencode/agent/victoria-server.md 2>/dev/null && echo "agente_ok"
        echo "skills_con_fuente_viva=$n"' 2>/dev/null)
    local skills_viva
    skills_viva=$(echo "$kcheck" | grep -oE "skills_con_fuente_viva=[0-9]+" | cut -d= -f2)
    local agente_ok
    agente_ok=$(echo "$kcheck" | grep -c "agente_ok")
    [ "${skills_viva:-0}" -lt 3 ] && { echo "DRIFT: skills de kalimete sin fuente viva ($skills_viva/3 referencian /v1/granja)"; drift=1; }
    [ "$agente_ok" -eq 0 ] && { echo "DRIFT: agente victoria-server de kalimete sin catálogo de puertos"; drift=1; }
    # Servicios up sin mención en el agente de kalimete (mapa de patrones:
    # el nombre del probe no siempre coincide con cómo se escribe en el doc)
    local pat
    for svc in tts_stt video webnav whois sonic hunyuan3d lp_animate; do
        echo "$vivos" | grep -q "$svc" || continue
        case "$svc" in
            tts_stt)    pat="TTS|STT|18810|voice" ;;
            video)      pat="video|18811" ;;
            webnav)     pat="web-nav|webnav|18820" ;;
            whois)      pat="whois|18830" ;;
            sonic)      pat="[Ss]onic|18850" ;;
            hunyuan3d)  pat="hunyuan|Hunyuan|18860" ;;
            lp_animate) pat="lp-animate|lp_animate|animar|18861" ;;
            *)          pat="$svc" ;;
        esac
        ssh -i ~/.ssh/id_victoria -p 1111 -o ConnectTimeout=8 -o BatchMode=yes warcold@kalimete.local \
            "grep -qiE '$pat' ~/.config/opencode/agent/victoria-server.md 2>/dev/null" || {
            echo "DRIFT: servicio '$svc' up en victoria pero sin mención en victoria-server.md de kalimete"; drift=1; }
    done
    python3 - "$state_f" "$vivos" "$skills_viva" "$drift" <<'PYEOF' 2>/dev/null
import json, sys, time
path, vivos, skills, drift = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try: d = json.load(open(path))
except Exception: d = {}
d["last_check"] = time.time()
d["servicios_up"] = vivos.split(",") if vivos else []
d["skills_con_fuente_viva"] = int(skills or 0)
d["drift"] = drift == "1"
d["historial"] = ([{"ts": time.time(), "drift": drift == "1"}] + d.get("historial", []))[:10]
json.dump(d, open(path, "w"), indent=1)
PYEOF
    if [ "$drift" = "0" ]; then log "granja-drift: sincronizado (skills 3/3 con fuente viva, agente OK, servicios: $vivos)"; fi
    return $drift
}

do_fleet() {
    # Auditoría del scaffold de la flota (2026-10-08). SOLO LECTURA, no edita
    # nada. Verifica: harness central válido; por cada agente (principal + los
    # del central): .md existe + frontmatter name/mode + harness existe y JSON
    # válido + changelogs existen + frescura TTL 24h + resuelve en
    # 'opencode agent list'; anti-duplicados (symlink agent prohibido, set
    # exacto de 11 .md); boundary (nada de kalimete en dirs de victoria).
    # Exit 0 = consistente, 1 = hay fallas.
    local central="/home/victoria/.victoria-custom/harness/victoria.harness.json"
    local fstate="/home/victoria/.victoria-custom/state/frescura.json"
    local agents_dir="/home/victoria/.config/opencode/agents"
    local fail=0 now
    now=$(date +%s)
    [ -f "$central" ] || { echo "FALLA: falta harness central"; return 1; }
    python3 -m json.tool "$central" >/dev/null 2>&1 || { echo "FALLA: harness central JSON inválido"; return 1; }
    local cdir
    cdir=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("changelogs_dir",""))' "$central")
    local obin=""
    if command -v opencode >/dev/null 2>&1; then obin="opencode";
    elif [ -x "/home/victoria/.opencode/bin/opencode" ]; then obin="/home/victoria/.opencode/bin/opencode"; fi
    local alist=""
    if [ -n "$obin" ]; then
        alist=$("$obin" agent list 2>/dev/null | grep -E "\(primary\)|\(subagent\)" || true)
    else
        echo "AVISO: binario opencode no encontrado, se omite agent list"
    fi
    local n f h bad ts
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        f=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));p=d["principal"];print(p["file"] if p["name"]==sys.argv[2] else next((s["file"] for s in d["subagents"] if s["name"]==sys.argv[2]),""))' "$central" "$n")
        if [ -z "$f" ] || [ ! -f "$f" ]; then echo "FALLA: [$n] falta agent file"; fail=1; continue; fi
        grep -qE "^name: " "$f" || { echo "FALLA: [$n] frontmatter sin name:"; fail=1; }
        grep -qE "^mode: (primary|subagent)" "$f" || { echo "FALLA: [$n] frontmatter sin mode válido"; fail=1; }
        h=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));p=d["principal"];print(p.get("harness","") if p["name"]==sys.argv[2] else next((s.get("harness","") for s in d["subagents"] if s["name"]==sys.argv[2]),""))' "$central" "$n")
        if [ -n "$h" ]; then
            if [ ! -f "$h" ]; then echo "FALLA: [$n] falta harness"; fail=1;
            elif ! python3 -m json.tool "$h" >/dev/null 2>&1; then echo "FALLA: [$n] harness JSON inválido"; fail=1; fi
        fi
        bad=$(python3 -c 'import json,sys,os;d=json.load(open(sys.argv[1]));subs=[s for s in d["subagents"] if s["name"]==sys.argv[2]];cs=(subs[0].get("changelogs",[]) if subs else []);print("\n".join("FALTA-CHANGELOG:"+c for c in cs if not os.path.isfile(os.path.join(sys.argv[3],c))))' "$central" "$n" "$cdir")
        while IFS= read -r line; do
            [ -n "$line" ] && { echo "FALLA: [$n] $line"; fail=1; }
        done <<< "$bad"
        ts=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get(sys.argv[2],{}).get("ts",0))' "$fstate" "$n" 2>/dev/null || echo 0)
        case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
        if [ $((now - ts)) -gt 86400 ]; then echo "AVISO: [$n] doc STALE (doc-fresh.sh $n)"; fi
        if [ -n "$alist" ]; then
            echo "$alist" | grep -qE "^${n} \((primary|subagent)\)" || { echo "FALLA: [$n] no resuelve en agent list"; fail=1; }
        fi
    done < <(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["principal"]["name"]);[print(s["name"]) for s in d["subagents"]]' "$central")
    [ -e "/home/victoria/.config/opencode/agent" ] && { echo "FALLA: symlink agent→agents prohibido existe"; fail=1; }
    [ -d "/home/victoria/agent" ] && { echo "FALLA: dir ~/agent singular en victoria (convención kalimete)"; fail=1; }
    local want="victoria.md vllm.md openclaw.md comfyui.md sonic.md rss-system.md meta-business.md weather.md cloudflare.md liveportrait.md gpu.md"
    local have extra missing
    have=$(ls "$agents_dir" 2>/dev/null | grep "\.md$" | grep -v "bkup" | sort || true)
    extra=$(comm -13 <(printf "%s\n" $want | sort) <(printf "%s\n" "$have") || true)
    missing=$(comm -23 <(printf "%s\n" $want | sort) <(printf "%s\n" "$have") || true)
    [ -n "$extra" ] && { echo "FALLA: .md inesperados en agents/: $extra"; fail=1; }
    [ -n "$missing" ] && { echo "FALLA: .md esperados faltantes: $missing"; fail=1; }
    if [ "$fail" -eq 0 ]; then echo "fleet OK: scaffold de la flota consistente (11 agentes)"; else echo "fleet: HAY FALLAS (ver arriba)"; fi
    return "$fail"
}

do_restore() {
    local which="${1:-}"
    if [ -z "$which" ]; then
        echo "snapshots disponibles:"
        ls -1 "$SNAP_DIR" 2>/dev/null
        echo "uso: $0 restore <timestamp>  (restaura SOLO docs, nunca secretos ni DBs)"
        return 0
    fi
    local src="$SNAP_DIR/$which"
    [ -d "$src" ] || { echo "snapshot no existe: $which"; return 1; }
    log "restore de $which (solo docs, confirmación manual archivo por archivo)"
    # Por seguridad NO restaura automáticamente: muestra diff por archivo
    (cd "$src" && find . -type f | sort) | while read -r f; do
        f="${f#./}"
        [ "$f" = "MANIFEST.txt" ] && continue
        if [ -f "/home/victoria/$f" ]; then
            if ! cmp -s "$src/$f" "/home/victoria/$f"; then
                echo "DIFIERE: $f"
            fi
        else
            echo "NUEVO (solo en backup): $f"
        fi
    done
    echo "---"
    echo "Para restaurar un archivo: cp '$src/<archivo>' '/home/victoria/<archivo>'"
}

case "${1:-backup}" in
    backup) do_backup ;;
    status) do_status ;;
    verify) do_verify ;;
    restore) do_restore "${2:-}" ;;
    docsync) do_docsync ;;
    fleet) do_fleet ;;
    offsite) do_offsite ;;
    # FIX 2026-11-03: el branch inline NO llamaba do_cycle() -> do_granja_drift
    # (29-oct) y do_offsite nunca corrían con el timer. Fuente única: do_cycle.
    cycle) do_cycle ;;
    *) echo "uso: $0 {backup|status|verify|restore [timestamp]|docsync|fleet|cycle}"; exit 1 ;;
esac
