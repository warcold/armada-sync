#!/usr/bin/env bash
# openclaw-customize-apply.sh
#
# Mergea nuestros overrides canónicos (openclaw-overrides.json5 en el host)
# encima del openclaw.json del sandbox de victoria-armada. Diseñado para:
#
#   1. Ser llamado por el ensure-loop DESPUÉS del restore del persist.sh
#      (así los overrides sobreviven a rebuilds y updates del core).
#   2. Ser idempotente (se puede correr cuantas veces se quiera).
#   3. NO romper el config si el schema de overrides ya está merged.
#   4. Preservar owners críticos (openclaw.json sandbox:660, extensions root).
#
# El merge es PROFUNDO: conservamos todo lo que no esté en los overrides,
# y solo forzamos las claves que listamos. Las listas (arrays) se REEMPLAZAN,
# no se concatenan (es el comportamiento esperado para labels, agents, etc).
#
# Uso:
#   openclaw-customize-apply.sh                # aplica al sandbox actual
#   openclaw-customize-apply.sh --check        # solo verifica, no escribe
#   openclaw-customize-apply.sh --status       # reporta si hay drift
set -u

OVERRIDES_FILE="/home/victoria/.victoria-custom/openclaw-overrides.json"
SANDBOX_PREFIX="victoria-armada"
LOG_PREFIX="[openclaw-customize]"

log() { echo "$LOG_PREFIX $(date -Is) $*"; }

# Resolver el contenedor del sandbox
resolve_cid() {
    docker ps --filter "name=$SANDBOX_PREFIX" --format '{{.ID}}' | head -1
}

# Deep merge: overrides encima de base. Devuelve el JSON merged por stdout.
# Reglas:
#   - dict: merge recursivo (overrides gana)
#   - list: reemplazar (overrides gana, no concatenar)
#   - escalares: overrides gana
#   - None en overrides: eliminar la clave del base
#   - _managed (meta): lista rutas gestionadas; las que no estén en overrides
#     se ELIMINAN del sandbox (idempotencia real: quitar algo del overrides
#     lo quita del sandbox, no deja residuos).
deep_merge() {
    python3 -c '
import json, sys

base = json.load(sys.stdin)
overrides_raw = json.load(open(sys.argv[1], encoding="utf-8"))

# Extraer meta _managed antes de mergear (NO debe ir al sandbox)
managed = overrides_raw.pop("_managed", [])
overrides = dict(overrides_raw)

def merge(b, o):
    if isinstance(b, dict) and isinstance(o, dict):
        result = dict(b)
        for k, v in o.items():
            if v is None:
                result.pop(k, None)
            elif k in result:
                result[k] = merge(result[k], v)
            else:
                result[k] = v
        return result
    return o

merged = merge(base, overrides)

# Sanitize: para cada ruta en _managed, si NO está en overrides, eliminarla
def has_path(d, path):
    cur = d
    for k in path:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return False
    return True

def del_path(d, path):
    if not path:
        return
    cur = d
    for k in path[:-1]:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return
    if isinstance(cur, dict):
        cur.pop(path[-1], None)

for path in managed:
    if not has_path(overrides, path):
        del_path(merged, path)

json.dump(merged, sys.stdout, indent=2, ensure_ascii=False)
' "$OVERRIDES_FILE"
}

# Validar que el overrides existe y parsea
validate_overrides() {
    [ -f "$OVERRIDES_FILE" ] || { log "ERROR: overrides no existe: $OVERRIDES_FILE"; exit 1; }
    python3 -c "import json,sys; json.load(open(sys.argv[1]));" "$OVERRIDES_FILE" 2>/dev/null \
      || { log "ERROR: overrides no parsea como JSON"; exit 1; }
}

cmd="${1:-apply}"
case "$cmd" in
    --check|check)
        validate_overrides
        cid=$(resolve_cid)
        [ -z "$cid" ] && { log "check: sandbox no activo"; exit 0; }
        # generar el merged sin escribir
        docker exec "$cid" cat /sandbox/.openclaw/openclaw.json 2>/dev/null | \
          deep_merge 2>/dev/null | python3 -m json.tool >/dev/null 2>&1 \
          && log "check: overrides válidas y merge OK" \
          || { log "check: ERROR de merge"; exit 1; }
        ;;
    --status|status)
        validate_overrides
        cid=$(resolve_cid)
        [ -z "$cid" ] && { log "status: sandbox no activo"; exit 0; }
        # drift detection: comparar valores clave
        docker exec "$cid" python3 -c "
import json
c = json.load(open('/sandbox/.openclaw/openclaw.json'))
p = c.get('channels',{}).get('discord',{}).get('streaming',{}).get('progress',{})
print('discord.streaming.progress.label:', p.get('label','(default ~Molting pool)'))
print('discord.streaming.progress.toolProgress:', p.get('toolProgress','(default true)'))
am = c.get('plugins',{}).get('entries',{}).get('active-memory',{})
print('active-memory.enabled:', am.get('enabled','AUSENTE'))
print('active-memory.allowedChatTypes:', am.get('config',{}).get('allowedChatTypes','(no)'))
d = c.get('session',{}).get('identityLinks',{})
print('session.identityLinks:', d if d else 'AUSENTE')
" 2>/dev/null
        ;;
    apply|--apply)
        validate_overrides
        cid=$(resolve_cid)
        [ -z "$cid" ] && { log "apply: sandbox no activo; reintento en próximo ciclo"; exit 0; }

        # 1. Leer el openclaw.json actual del sandbox
        current=$(docker exec "$cid" cat /sandbox/.openclaw/openclaw.json 2>/dev/null)
        [ -z "$current" ] && { log "apply: openclaw.json ilegible; no toco"; exit 1; }

        # 2. Validar que el current parsea (sino no rompo)
        echo "$current" | python3 -m json.tool >/dev/null 2>&1 \
          || { log "apply: openclaw.json actual no parsea; NO toco"; exit 1; }

        # 3. Deep merge
        merged=$(echo "$current" | deep_merge 2>/dev/null)
        [ -z "$merged" ] && { log "apply: merge falló; NO toco"; exit 1; }

        # 4. Validar que el resultado parsea
        echo "$merged" | python3 -m json.tool >/dev/null 2>&1 \
          || { log "apply: resultado merged no parsea; NO toco"; exit 1; }

        # 5. Comparar tamaño para sanity (no debe encogerse drásticamente)
        cur_size=$(echo "$current" | wc -c)
        new_size=$(echo "$merged" | wc -c)
        # si el merged es mucho más chico algo raro pasó (safety: 30% margen)
        if [ "$new_size" -lt $((cur_size * 70 / 100)) ]; then
            log "apply: AVISO — merged $new_size B vs current $cur_size B (sospechosamente pequeño); NO toco"
            exit 1
        fi

        # 7. Comparar si realmente cambió algo (drift detection real)
        cur_hash=$(echo "$current" | sha256sum | awk '{print $1}')
        new_hash=$(echo "$merged" | sha256sum | awk '{print $1}')
        if [ "$cur_hash" = "$new_hash" ]; then
            # Sin drift; las overrides ya están aplicadas. Salir silenciosamente
            # (solo loguear si DEBUG=1).
            [ "${DEBUG:-0}" = "1" ] && log "apply: sin drift (overrides ya aplicadas)"
            exit 0
        fi

        log "apply: drift detectado, aplicando overrides ($(echo "$current" | wc -c) → $(echo "$merged" | wc -c) bytes)."

        # 8. Escribir al sandbox (backup previo)
        docker exec -u root "$cid" sh -c 'cp /sandbox/.openclaw/openclaw.json /sandbox/.openclaw/openclaw.json.pre-customize 2>/dev/null'
        # copiar el merged via stdin
        echo "$merged" | docker exec -i "$cid" sh -c 'cat > /sandbox/.openclaw/openclaw.json.tmp' 2>/dev/null
        docker exec -u root "$cid" sh -c 'mv /sandbox/.openclaw/openclaw.json.tmp /sandbox/.openclaw/openclaw.json && chown sandbox:sandbox /sandbox/.openclaw/openclaw.json && chmod 660 /sandbox/.openclaw/openclaw.json' 2>/dev/null

        log "apply: overrides aplicadas (hot-reload del gateway cargará streaming/active-memory; plugins.allow o plugins nuevos requieren restart)."
        ;;
    *)
        echo "uso: openclaw-customize-apply.sh {apply|check|status}" >&2
        exit 2
        ;;
esac
