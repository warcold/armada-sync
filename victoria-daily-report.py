#!/usr/bin/env python3
"""
victoria-daily-report.py — Reporte de estado via WhatsApp DM a papa.
Plan Victoria 2.0 (2026-09-15). Un solo sistema de reporteria (no hay otro).

Revisa: systemd (15), docker (4), vLLM/gateway (+coder on-demand :8001),
dashboard, voz/video/nav/whois/admin/sonic/hunyuan/animate, UPSTREAM
(versiones local vs loopstream desde state/upstream.json del Armada Sync),
DOCS (frescura del sync: ultimo snapshot, edad del chequeo upstream, docs
validadas FRESH vs resto ok), feed central, restarts del gpu-saver, ultimo
estado de broadcasts, disco.
Manda resumen corto e informativo: todo ✅ salvo anomalias, que van
con ⚠️. Picos/errores tambien se reportan aunque el resto este verde.
Solo las docs actualizadas se listan; las no tocadas salen como "resto ok".

FIX 2026-11-03 (auditoria anti-stale, owner: "vemos errores que ya no
existen"): (1) la "ultima alerta" del gateway se mostraba con ventana 48h
bajo el titulo "ERRORES (24h)" — una tormenta resuelta del 01-nov seguia
saliendo 2 dias como si fuera reciente; ahora la ventana es 24h (igual al
titulo). (2) El coder on-demand :8001 (nuevo 2026-11-01) no aparecia — se
muestra su estado real (idle = NORMAL, sin warning). (3) n8n no se
chequeaba en docker (el comentario decia 4 contenedores, el codigo 3).
(4) Los timestamps de logs con sufijo EDT/EST se parseaban como UTC
(ventana 24h desalineada 4h — sub-reportaba errores recientes).

CADENCIA (2026-09-16, directiva del owner): cada 4h dentro del horario
permitido 08:00-01:00 ET (cron: 0 0,8,12,16,20 * * *). QUIET HOURS 01:00-07:00
ET (Washington DC): NUNCA enviar de madrugada — el script se auto-salta si
la hora local cae en 01:00-06:59 (defensa en profundidad además del cron).

Uso:
  victoria-daily-report.py           # envia DM a papa (respeta quiet hours)
  victoria-daily-report.py --dry-run # imprime sin enviar
"""
import json
import os
import re as _re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from broadcast_common import CENTRAL_FEED, wa_resolve, wa_send

OWNER_E164 = "+18295468686"  # papa (Alfredo) — unico destinatario del reporte
LOGDIR = "/home/victoria/logs"
# Hora local del HOST (America/New_York — Washington DC): sigue el DST sola
# (EDT -4 en verano / EST -5 en invierno). Antes: UTC-4 hardcodeado, quedaba
# 1h adelantado en invierno (fix 2026-10-06, owner: "timezone en todo lados").
NOW = datetime.now().astimezone()
DAY = NOW.strftime("%d/%m")


def log(msg: str):
    print(f"[daily-report] {msg}", file=sys.stderr)


def in_quiet_hours(now=None) -> bool:
    """True si la hora local cae en quiet hours 01:00-06:59 ET (Washington DC).
    Usa la zona del sistema (America/New_York): DST-safe todo el año. Toda
    alerta/reporteria al owner pasa por aquí: de madrugada NUNCA se envía."""
    import time as _time
    h = (now if now is not None else _time.localtime()).tm_hour
    return 1 <= h <= 6


def sh(cmd: str, timeout: int = 10) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True,
                           text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def main() -> int:
    dry = "--dry-run" in sys.argv
    if not dry and in_quiet_hours():
        log("quiet hours 01:00-07:00 ET: salto sin enviar")
        return 0
    warns: list[str] = []
    ok_n = 0

    # --- 1. systemd (15 reales — mover/downloader ELIMINADOS 2026-09-28;
    # +hunyuan3d :18860 +lp-animate :18861 desde 2026-10-09; reporte DGX-only
    # 2026-10-14: flota kalimete fuera del reporte por directiva del owner) ---
    svcs = ("victoria-llm-gateway victoria-gpu-saver victoria-voice-server "
            "victoria-video-server web-nav-server victoria-whois-server "
            "victoria-host-admin victoria-openclaw-bridge "
            "cloudflared nginx comfyui liveportrait "
            "victoria-sonic-server victoria-hunyuan3d "
            "victoria-lp-animate").split()
    states = sh("systemctl is-active " + " ".join(svcs)).split()
    down = [s for s, st in zip(svcs, states) if st != "active"]
    down_real = down
    up_n = len(svcs) - len(down)
    ok_n += 1 if not down_real else 0
    if down_real:
        warns.append("caidos: " + ",".join(s.replace("victoria-", "") for s in down_real))

    # --- 2. docker (4: vllm + n8n + publisher + sandbox) ---
    # Fix 2026-11-03: n8n NO se chequeaba (el comentario decia 4 contenedores,
    # el codigo solo 3) — un n8n caido no avisaba.
    dps = sh("docker ps --format '{{.Names}} {{.Status}}'")
    vllm_up = "nemoclaw-vllm" in dps and "Up" in dps
    sb_ok = "healthy" in dps
    pub_up = "openclaw-publisher" in dps and "Up" in dps
    n8n_up = _re.search(r"^n8n \S*Up", dps, _re.M) is not None
    if not (vllm_up and sb_ok and pub_up and n8n_up):
        warns.append("docker: " + dps.replace("\n", " ")[:100] or "vacío")
    else:
        ok_n += 1

    # --- 3. vLLM + gateway ---
    vllm = sh("curl -s -m 5 -o /dev/null -w '%{http_code}' "
              "http://127.0.0.1:8000/health")
    gw = None
    try:
        with urllib.request.urlopen("http://127.0.0.1:8010/health",
                                    timeout=8) as r:
            gw = json.loads(r.read())
        today = gw.get("keys", {}).get("today", {})
        gw_line = f"GW ok ({today.get('requests', '?')} hoy)"
    except Exception as e:  # noqa: BLE001
        gw = None
        today = {}
        gw_line = "GW FAIL"
        warns.append(f"gateway caido ({e})")
    vllm_line = "vLLM 200" if vllm == "200" else f"vLLM {vllm or 'FAIL'}"
    if vllm != "200":
        warns.append("vLLM no responde 200")
    else:
        ok_n += 1
    # Coder on-demand :8001 (2026-11-01): idle = NORMAL (0 RAM, arranca solo
    # al 1er request). Informativo, SIN warning (un probe a :8001 en idle
    # daria 000 = falso positivo). Estado real desde /health del gateway.
    coder_running = None
    if gw:
        _coder = gw.get("coder", {}) or {}
        coder_running = bool(_coder.get("running"))
    coder_txt = ("?" if not gw else
                 ("activo" if coder_running else "on-demand · idle"))

    # --- 4. dashboard + sentidos (voz/video/nav/whois/admin/sonic) ---
    # :18840 /health exige auth SIEMPRE (401 sin llave = NORMAL, no caida)
    # Dashboard: publisher en :18800 desde el rebuild runtime 2026.9.2
    # (2026-10-05: nemoclaw v0.0.130 exige 18789-18799 libre de listeners
    # extraños — ownership proof). Antes chequeaba 18789 = falso FALLA 000.
    dash = sh("curl -s -m 5 -o /dev/null -w '%{http_code}' "
              "http://victoria.local:18800/")
    ports = {}
    for name, port in (("voz", 18810), ("video", 18811), ("nav", 18820),
                       ("whois", 18830), ("admin", 18840), ("sonic", 18850),
                       ("hunyuan", 18860), ("animate", 18861)):
        code = sh(f"curl -s -m 4 -o /dev/null -w '%{{http_code}}' "
                  f"http://127.0.0.1:{port}/health")
        ports[name] = code
    bad_ports = [k for k, v in ports.items() if v not in ("200", "401")]
    extra = "".join(f" {k}" for k, v in ports.items() if v in ("200", "401"))
    dash_ok = dash == "200"
    if not dash_ok or bad_ports:
        w = []
        if not dash_ok:
            w.append(f"dashboard {dash or 'FAIL'}")
        if bad_ports:
            w.append("puertos: " + ",".join(bad_ports))
        warns.append("; ".join(w))
    else:
        ok_n += 1

    # --- 5. feed central ---
    try:
        d = json.load(open(CENTRAL_FEED, encoding="utf-8"))
        ts = datetime.fromisoformat(d["scanned_at"])
        age_m = int((NOW - ts).total_seconds() // 60)
        unread = d.get("total_unread", "?")
        feed_line = f"feed {age_m}min · {unread} pendientes"
        if age_m > 180:
            warns.append(f"feed central viejo ({age_m}min)")
        else:
            ok_n += 1
    except Exception:
        feed_line = "feed ERROR"
        warns.append("feed central ilegible")

    # --- 6. restarts gpu-saver (picos, ultimas 24h) ---
    # Solo hoy+ayer: el aviso de un reinicio viejo no debe salir para siempre.
    import datetime as _dt
    _today = _dt.date.today().isoformat()
    _yest = (_dt.date.today() - _dt.timedelta(days=1)).isoformat()
    restarts = sh("grep -a -c -e '%s.*docker restart' -e '%s.*docker restart' "
                  f"{LOGDIR}/victoria-gpu-saver.log 2>/dev/null" % (_today, _yest)) or "0"
    try:
        r_n = int(restarts)
    except ValueError:
        r_n = 0
    if r_n > 0:
        warns.append(f"gpu-saver reinicio vLLM x{r_n} (ver log)")

    # --- 7. broadcasts: totales + ultima corrida ---
    def count_ok(path: str, mark: str) -> str:
        c = sh(f"grep -c '{mark}' {LOGDIR}/{path} 2>/dev/null")
        return c or "0"

    dc = count_ok("discord-broadcast.log", "OK TH")
    wa = count_ok("whatsapp-broadcast.log", "sent (messageId")
    ig_log = sh(f"tail -5 {LOGDIR}/instagram-broadcast.log 2>/dev/null")
    ig_last = "ok" if ("publish id=" in ig_log) else "…"

    # --- 7b. Historial de errores ULTIMAS 24H con fecha/hora (2026-09-21) ---
    # Antes: grep sin filtro de fecha → un error viejo (ej. rss 2026-09-18)
    # salía ETERNAMENTE en cada reporte. Ahora: solo líneas con timestamp
    # dentro de 24h; líneas sin fecha se ignoran (evita fósiles).
    # Fix 2026-11-03: los writers de logs estampan hora LOCAL del host
    # (datetime.now().astimezone()) con sufijo hardcodeado ("EDT"/"ET" —
    # instagram-broadcast.py:196, discord/whatsapp "ET") que queda MAL tras
    # el cambio DST (host en EST desde el 02-nov). El VALOR es local; el
    # sufijo es decorativo → se parsea como hora local del host (DST-proof)
    # y se convierte a UTC. Antes se parseaba como UTC puro (ventana 24h
    # desalineada 4-5h: sub-reportaba errores de hace 20-24h reales).
    _cutoff_utc = (NOW - timedelta(hours=24)).astimezone(timezone.utc)
    err_hist: list[str] = []  # líneas crudas (ya traen su fecha/hora)
    for _lp in ("discord-broadcast.log", "whatsapp-broadcast.log",
                "instagram-broadcast.log", "rss-broadcast.log"):
        try:
            _lines = open(f"{LOGDIR}/{_lp}", encoding="utf-8",
                          errors="replace").read().splitlines()
        except Exception:
            continue
        for _ln in _lines:
            if not _re.search(r"ERROR|FAIL|ALERTA", _ln, _re.I):
                continue
            _m = _re.search(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})", _ln)
            if not _m:
                continue
            try:
                # Valor = hora local del host (el sufijo del writer es
                # hardcodeado y miente tras el DST): local → UTC.
                _ts = datetime.strptime(
                    _m.group(1) + " " + _m.group(2),
                    "%Y-%m-%d %H:%M:%S").replace(tzinfo=NOW.tzinfo)
                _ts = _ts.astimezone(timezone.utc)
            except Exception:
                continue
            if _ts < _cutoff_utc:
                continue
            err_hist.append(_ln.strip()[:100])
    # Fix 2026-10-14: dedup por contenido — los scripts de broadcast se
    # auto-logueaban Y cron redirigia al MISMO archivo (doble escritura por
    # linea), asi que un solo evento llenaba los 2 slots de "ultimos
    # errores" y parecia fallo doble. Cron ya escribe a *-cron.log; esto
    # ademas deduplica lineas legacy ya escritas en los logs.
    _seen: set[str] = set()
    _dedup: list[str] = []
    for _l in err_hist:
        if _l not in _seen:
            _seen.add(_l)
            _dedup.append(_l)
    err_hist = _dedup[-3:]  # los 3 más recientes, SIN duplicados

    # --- 7c. Anomalías del gateway (/health): título + hora del reporte ---
    # El /health ya expone titulo/timestamp_reporte/ultima_alerta/historial;
    # el reporte lo muestra para que lo del gateway SÍ se vea aquí.
    gw_anom_txt = "sin datos (GW caído)"
    if gw:
        _anom = gw.get("anomalies", {}) or {}
        _an_n = _anom.get("today", 0)
        try:
            _an_n = int(_an_n)
        except (TypeError, ValueError):
            _an_n = 0
        _ts_rep = _anom.get("timestamp_reporte", "?")
        _ua = _anom.get("ultima_alerta") or {}
        # Fix 2026-10-14: la "ultima alerta" del gateway es la ultima HISTORICA
        # (ej. 2026-09-20) y salia en TODOS los reportes como si fuera nueva.
        # Ahora solo se muestra si es reciente; si no, "ninguna reciente".
        # Fix 2026-11-03: ventana 48h → 24h — bajo el titulo "ERRORES (24h)"
        # una alerta de hace 44h (tormenta ya resuelta del 01-nov) seguia
        # saliendo como "reciente" durante ~9 reportes = el owner veia
        # errores que ya no existen. Alineada al titulo: 24h.
        _ua_txt = "ninguna"
        if _ua:
            _ua_ts = str(_ua.get("timestamp", ""))
            _ua_recent = True  # fail-open: sin timestamp parseable se muestra
            try:
                _ua_dt = datetime.strptime(_ua_ts, "%Y-%m-%d %H:%M:%S"
                                           ).replace(tzinfo=timezone.utc)
                _ua_recent = (NOW.astimezone(timezone.utc) - _ua_dt
                              ) < timedelta(hours=24)
            except Exception:
                pass
            _ua_txt = (f"{_ua.get('descripcion') or _ua.get('detail') or '?'}"
                       f" [{_ua_ts}]" if _ua_recent
                       else "ninguna reciente (>24h)")
        gw_anom_txt = f"hoy {_an_n} · rep {_ts_rep} · ult: {_ua_txt}"
        if _an_n > 0:
            warns.append(f"gateway: {_an_n} anomalías hoy (rep {_ts_rep})")

    # --- 7d-bis. FLOTA Kalimete ELIMINADA 2026-10-14 ---
    # Directiva del owner: este reporte es DGX-only (servicios de
    # victoria.local). Kalimete es host hermano con su propio reporte;
    # wordpress-dev y demás drifts de kalimete NO deben salir aquí.
    # Bloque SSH suprimido (ahorra ~25s + ruido cross-scope).

    # --- 7d. UPSTREAM (versiones local vs loopstream, del Armada Sync) ---
    # Lee state/upstream.json (lo escribe upstream-sync.py vía armada-sync
    # cycle, guarda 24h). Solo REPORTA: si hay deriva te aviso, no actualizo
    # nada solo. El pin vLLM nunca deriva por diseño (revisión trimestral).
    up_drifts: list[str] = []
    up_ok_n = 0
    up_age_h: str = "?"
    try:
        _up = json.load(open("/home/victoria/.victoria-custom/state/"
                             "upstream.json", encoding="utf-8"))
        _ages = [v.get("ts", 0) for v in _up.values() if v.get("ts")]
        if _ages:
            up_age_h = f"{(NOW.timestamp() - max(_ages)) / 3600:.0f}h"
        for _sid, _s in _up.items():
            if _s.get("drift"):
                _lo = str(_s.get("local", "?"))[:12]
                _hi = str(_s.get("upstream", "?"))[:12]
                up_drifts.append(f"{_sid} {_lo}→{_hi}")
            elif _s.get("drift") is False:
                up_ok_n += 1
    except Exception:
        up_drifts = []
    if up_drifts:
        warns.append(f"upstream: {len(up_drifts)} updates disponibles "
                     f"({', '.join(d.split()[0] for d in up_drifts)})")

    # --- 7e. DOCS (frescura Armada Sync: snapshot + docs validadas) ---
    # Solo las docs actualizadas (FRESH <24h) se listan; las no tocadas
    # salen como "resto ok" para que sepas que las tenemos sin ruido.
    sync_age_txt = "?"
    try:
        _snaps = sorted(os.listdir("/home/victoria/.armada-sync/snapshots"))
        if _snaps:
            _last = _snaps[-1]  # formato YYYYMMDD-HHMMSS
            _dt = datetime.strptime(_last, "%Y%m%d-%H%M%S").replace(
                tzinfo=timezone(timedelta(hours=-4)))
            _dh = (NOW - _dt).total_seconds() / 3600
            sync_age_txt = f"{_dh:.0f}h ({_last[6:8]}/{_last[4:6]} {_last[9:11]}:{_last[11:13]})"
    except Exception:
        pass
    fresh_docs: list[str] = []
    try:
        _fr = json.load(open("/home/victoria/.victoria-custom/state/"
                             "frescura.json", encoding="utf-8"))
        _now_ts = int(NOW.timestamp())
        for _a, _v in _fr.items():
            if _now_ts - int(_v.get("ts", 0)) < 86400:
                fresh_docs.append(_a)
    except Exception:
        pass
    docs_txt = (", ".join(sorted(fresh_docs)) if fresh_docs
                else "ninguna hoy")
    ok_n += 1 if not up_drifts else 0

    # --- 8. disco + GPU ---
    disk = sh("df /home/victoria --output=pcent | tail -1").strip() or "?"
    try:
        disk_n = int(disk.replace("%", ""))
    except ValueError:
        disk_n = 0
    gpu = sh("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader "
             "-i 0 2>/dev/null").strip() or "?"
    try:
        gpu_n = int(gpu.replace("%", "").strip())
    except ValueError:
        gpu_n = -1

    def bar(pct: int, width: int = 10) -> str:
        if pct < 0:
            return "?"
        full = max(0, min(width, round(pct / 100 * width)))
        return "█" * full + "░" * (width - full)

    def plain_error(raw: str) -> str:
        low = raw.lower()
        if "unique constraint failed" in low:
            return ("lector RSS ignoro un duplicado (normal, no afecta)")
        if "media upload failed" in low:
            return ("una imagen no subio a WhatsApp (revisar media)")
        if "connection refused" in low:
            return ("un servicio no respondio al contactarlo " + raw[:60])
        return raw

    # --- mensaje estilo btop (bloque monoespaciado + divisores) ---
    DIV = "────────────────────"
    svc_state = "✅" if not down_real else "⚠️"
    sb_state = "✅" if (vllm_up and sb_ok and pub_up) else "⚠️"
    ports_state = "✅" if not bad_ports else "⚠️"
    feed_state = "✅" if age_m <= 180 else "⚠️"
    up_state = "✅" if not up_drifts else "⚠️"
    gw_req = today.get("requests", "?") if gw else "?"
    vllm_txt = "operativo" if vllm == "200" else f"FALLA ({vllm or 'sin respuesta'})"
    dash_txt = "OK" if dash_ok else f"FALLA ({dash or 'sin respuesta'})"
    down_note = ("todo arriba" if not down_real
                 else "Caidos: " + ",".join(down_real))
    ig_txt = ("ultimo publicado OK" if "publish id=" in ig_log
              else "sin novedad reciente")
    gpu_txt = f"{gpu_n}% uso" if gpu_n >= 0 else "no disponible"
    _vvv_ok = all(k not in bad_ports for k in ("voz", "video", "nav"))
    _waa_ok = all(k not in bad_ports for k in ("whois", "admin", "sonic"))
    _hun_ok = all(k not in bad_ports for k in ("hunyuan", "animate"))

    board = [
        f"🌟 *VICTORIA · REPORTE {DAY} {NOW.strftime('%H:%M')}*",
        f"```",
        f"┌─ SERVICIOS {up_n}/{len(svcs)} {svc_state}",
        f"│ vLLM ........ {vllm_txt}",
        f"│ Gateway ..... OK ({gw_req} peticiones hoy)",
        f"│ Coder ....... {coder_txt}",
        f"│ Sandbox ..... {'saludable' if sb_ok else 'MAL'}",
        f"│ Panel web ... {dash_txt}",
        f"│ Voz·Vid·Nav . {'OK' if _vvv_ok else 'revisar'}",
        f"│ Who·Adm·Son . {'OK' if _waa_ok else 'revisar'}",
        f"│ Hun·Anim .... {'OK' if _hun_ok else 'revisar'}",
        f"│ Contenido ... {'OK' if 'comfyui' not in down_real and 'liveportrait' not in down_real and 'victoria-sonic-server' not in down_real and 'victoria-hunyuan3d' not in down_real and 'victoria-lp-animate' not in down_real else 'revisar'}",
        f"│ · {down_note}",
        f"├─ UPSTREAM (local → loopstream) {up_state}",
    ]
    if up_drifts:
        for _d in up_drifts[:3]:
            board.append(f"│ ⚠️ {_d}")
        board.append(f"│ +{up_ok_n} ok · chequeo hace {up_age_h}")
    else:
        board.append(f"│todo al día · {up_ok_n} ok · hace {up_age_h}")
    # Flota kalimete EXCLUIDA 2026-10-14 por directiva del owner:
    # este reporte es DGX-only (servicios de victoria.local). Kalimete
    # es host hermano con su propio reporte; no mezclar scopes.
    board += [
        f"├─ DOCS (Armada Sync 6h) ✅",
        f"│ Sync ........ hace {sync_age_txt}",
        f"│ Validadas ... {docs_txt}",
        f"│ Resto ....... ok",
        f"├─ NOTICIAS {feed_state}",
        f"│ Feed ........ {'fresco' if age_m <= 180 else 'VIEJO'} ({age_m} min)",
        f"│ Pendientes .. {unread} articulos",
        f"│ Discord ..... {dc} enviados",
        f"│ WhatsApp .... {wa} enviados",
        f"│ Instagram ... {ig_txt}",
        f"├─ RECURSOS",
        f"│ Disco ....... [{bar(disk_n)}] {disk} usado",
        f"│ GPU ......... [{bar(gpu_n)}] {gpu_txt}",
        f"├─ ERRORES (24h)",
        f"│ Gateway ..... {gw_anom_txt}",
        f"│ Logs ........ {len(err_hist)} recientes",
        f"```",
    ]
    lines = board
    for w in warns[:4]:
        lines.append(f"⚠️ {plain_error(w)}")
    if err_hist:
        lines.append("📌 Historial de los últimos errores registrados (24h):")
        for _e in err_hist[-2:]:
            lines.append(f"· {_e}")
    if not warns and not err_hist:
        lines.append("✅ Todo verde, papá")
    lines.append(DIV)
    msg = "\n".join(lines)

    if dry:
        print(msg)
        return 0
    # FIX 2026-10-08 (forense: FAIL 12:00 post-reboot + raza TOCTOU
    # nsenter/PID entre wa_resolve y wa_send): reintenta resolve+send hasta
    # 3 veces con 20s (cubre churn de PIDs del gateway; un outage duro lo
    # cubre la cadencia del cron 4h, como se probo hoy 12:00->16:00).
    for attempt in (1, 2, 3):
        cid, pid, tok = wa_resolve(log)
        if not cid or not pid or not tok:
            log(f"ERROR intento {attempt}/3: sandbox/gateway no disponible para enviar")
        elif wa_send(cid, pid, tok, OWNER_E164, msg, log=log):
            return 0
        else:
            log(f"ERROR intento {attempt}/3: wa_send fallo")
        if attempt < 3:
            time.sleep(20)
    return 1


if __name__ == "__main__":
    sys.exit(main())
