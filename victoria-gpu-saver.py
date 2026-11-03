#!/usr/bin/env python3
"""
victoria-gpu-saver.py — Unified GPU/VRAM guardian for Victoria Armada.

Combines (and supersedes) the old comfyui-idle-saver.py. Single daemon that
monitors BOTH vLLM (inference — never killed) and ComfyUI (content generation
— cleaned when idle). Built on the lessons from the 2026-08-16 16:46 UTC
incident: ComfyUI's CUDA context on a shared GB10 GPU starved vLLM into a
silent deadlock. See AGENTS.md §10 for the full postmortem.

Design principles (owner directive 2026-08-16, updated 2026-09-08):
  1. NEVER kill vLLM to free VRAM (vLLM is the revenue service and must stay up
     under normal load). BUT if vLLM is CONFIRMED HUNG (sustained probe timeouts
     = EngineCore frozen with throughput 0.0), a `docker restart` IS allowed as
     self-healing — with a restart cooldown to avoid loops. This was the fix for
     the recurring 2026-09-07 and 2026-09-08 collapses.
  2. If ComfyUI is idle (no queue, no recent history) but alive, free its
     loaded models / VRAM via the /free API. Do NOT kill the process.
  3. Detect vLLM hung-state (POST /v1/chat/completions no token in N seconds):
     after VLLM_RESTART_AFTER_HUNG consecutive 'hung' probes, restart vLLM.
  4. No auto-revive loop (victoria-comfyui.service is disabled + Restart=no,
     so no one will revive ComfyUI after a graceful stop).
  5. Health checks via curl (HTTP) + GPU stats via nvidia-smi.

Runs as User=victoria (not root). Idempotent: safe to start multiple times.
"""

import asyncio
import json
import logging
import os
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, "/home/victoria")
try:
    import gpu_arbiter
except Exception:
    gpu_arbiter = None

logger = logging.getLogger("victoria-gpu-saver")

# === Configuration ===
INTERVAL = 30                    # seconds between checks
COMFYUI_BASE = "http://127.0.0.1:8188"
VLLM_BASE = "http://127.0.0.1:8000"
COMFYUI_IDLE_FOR_FREE = 600      # 10 min idle before /free (NOT a kill)
VLLM_HANG_WARN_AFTER = 90        # how long a chat completion may stay silent
                                  # before we consider vLLM hung and log a warning
VLLM_PROBE_MAX_TOKENS = 3        # tiny probe to detect hang
VLLM_PROBE_TIMEOUT = 25          # if no response in 25s → consider hung
VLLM_HANG_COOLDOWN = 600         # log hang warning at most every 10 min (evita spam)
VLLM_BOOT_GRACE_S = 600          # tras un boot, vLLM tarda ~5-7min en cargar:
                                 # en esa ventana UNHEALTHY es esperado (INFO, no ERROR)
VLLM_RESTART_AFTER_HUNG = 4      # 'hung' probes consecutivos antes de reiniciar
                                  # (~1 tick = 30s + 25s probe => ~4 min de freeze)
VLLM_RESTART_COOLDOWN = 900      # 15 min entre reinicios (evita restart-loop)
VLLM_CONTAINER = "nemoclaw-vllm"
MEMORY_SAFETY_PCT = 90      # tope de seguridad: uso de memoria unificada (%)
MEMORY_SAFETY_COOLDOWN = 120  # alerta max cada 2 min (evita spam)
GPU_BLOCK_TEMP = 80.0   # >= esto: ningún pesado nuevo (el arbiter ya da 429)
GPU_WARN_TEMP = 75.0    # >= esto: aviso + /free preventivo de ComfyUI
GPU_THERMAL_COOLDOWN = 300  # alerta térmica max cada 5 min
# Watchdog de CARGA SOSTENIDA (2026-10-14, forense freeze 2026-10-13 19:00;
# duty-cycle 2026-10-17, forense apagón 2026-10-16 22:58):
# GPU 94-95% durante 12+ min continuos congeló el host GB10 (journal muere
# abrupto, sin Xid/OOM; power-cycle manual). Problema conocido de plataforma:
# NVIDIA container-toolkit#1910 (sin resolución upstream). La temperatura
# (75-82C) es SÍNTOMA de la carga, no la causa. Este watchdog detecta el
# patrón REAL y alerta; el gateway lo frena con su válvula 5.
# 2026-10-17: el patrón "96% con micro-pausas cada ~2 min" BURLABA el contador
# de ticks consecutivos (cada pausa lo reseteaba). Ahora se mide por
# DUTY-CYCLE: % de muestras >=85% en una ventana deslizante de 10 min.
SUSTAINED_UTIL_PCT = 85.0        # util GPU >= esto = muestra de carga alta
SUSTAINED_WINDOW_TICKS = 20      # ventana deslizante (30s c/u) = 10 min
SUSTAINED_WINDOW_MIN = 10        # mínimo de muestras antes de evaluar (5 min)
SUSTAINED_DUTY_PCT = 80.0        # % de muestras altas en la ventana = alerta
SUSTAINED_ALERT_COOLDOWN = 1800  # alerta WhatsApp max cada 30 min
# Dead man's switch del canal de alertas (2026-10-17): el listener de WhatsApp
# estuvo caído TODO un día (apagón 2026-10-16) y 3 alertas de carga sostenida
# nunca llegaron al owner. Si el envío WA falla WA_DEAD_AFTER veces seguidas,
# la siguiente alerta sale TAMBIÉN por Discord (webhook TH #ethical-hackers).
WA_DEAD_AFTER = 2
DISCORD_WEBHOOKS_FILE = "/home/victoria/.discord-webhooks"
DISCORD_WEBHOOK_KEY = "TH_ETHICAL"
PIDFILE = "/home/victoria/logs/victoria-gpu-saver.pid"
HANG_FLAG_FILE = "/home/victoria/logs/vllm-hung.flag"
LOG_FILE = "/home/victoria/logs/victoria-gpu-saver.log"

# Observabilidad: métricas persistidas por tick → SQLite.
# Sobrevive a cualquier freeze/reboot, permite investigar el pre-freeze.
METRICS_DB = Path("/home/victoria/logs/victoria-metrics.db")
METRICS_ROTATION_DAYS = 30  # borra métricas >30d al inicio de cada tick (guardamos 30d)

# ********************************************************************************
# Observability: system metrics collection & persistence
# ********************************************************************************

# Asyncio scaffolding
_shutdown = asyncio.Event()

async def _setup_signals():
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(sig, _shutdown.set)


def _write_pid():
    Path(PIDFILE).write_text(str(os.getpid()))


def _remove_pid():
    try:
        os.remove(PIDFILE)
    except OSError:
        pass


async def _curl_json(url, timeout=5, method="GET", body=None):
    """Generic curl wrapper. Returns parsed JSON, {} on empty-body success,
    or None on fail."""
    try:
        args = ["curl", "-s", "-m", str(timeout), "-X", method]
        if body is not None:
            args += ["-H", "Content-Type: application/json", "-d", body]
        args.append(url)
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        if proc.returncode != 0:
            return None
        if not stdout:
            # FIX 2026-10-08 (forense: 2,863 warnings falsos desde 09-01):
            # HTTP 200 con body vacío ES éxito (ej. POST /free de ComfyUI
            # responde web.Response(status=200) sin texto por diseño) — no fallo.
            return {}
        return json.loads(stdout.decode())
    except (json.JSONDecodeError, OSError, asyncio.TimeoutError):
        return None


# ********************************************************************************
# vLLM monitoring  (NEVER killed — only detected + flagged)
# ********************************************************************************

async def _vllm_health():
    """Return (ok, payload) where ok=True if /health responded 200."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "curl", "-s", "-m", "5", "-o", "/dev/null", "-w", "%{http_code}",
            f"{VLLM_BASE}/health",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        code = stdout.decode().strip()
        return code == "200", code
    except OSError:
        return False, "0"


async def _vllm_probe_generation():
    """
    Most sensitive health probe: send a tiny chat-completion and time it.
    If vLLM doesn't return tokens in VLLM_PROBE_TIMEOUT seconds → HUNG.

    Returns dict:
        {"status": "ok" | "hung" | "down" | "slow",
         "elapsed_ms": int, "tokens": int | None}
    """
    body = json.dumps({
        "model": "nvidia/Qwen3.6-35B-A3B-NVFP4",
        "messages": [{"role": "user", "content": "ok"}],
        "max_tokens": VLLM_PROBE_MAX_TOKENS,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    })
    start = time.monotonic()
    try:
        proc = await asyncio.create_subprocess_exec(
            "curl", "-s", "-m", str(VLLM_PROBE_TIMEOUT),
            "-X", "POST", "-H", "Content-Type: application/json",
            "-d", body, f"{VLLM_BASE}/v1/chat/completions",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(
            proc.communicate(), timeout=VLLM_PROBE_TIMEOUT + 2
        )
        elapsed_ms = int((time.monotonic() - start) * 1000)
        text = stdout.decode().strip()
        if not text:
            return {"status": "hung", "elapsed_ms": elapsed_ms, "tokens": None}
        try:
            data = json.loads(text)
            if "error" in data:
                return {"status": "down", "elapsed_ms": elapsed_ms, "tokens": None}
            usage = data.get("usage", {})
            tokens = usage.get("completion_tokens")
            return {"status": "ok", "elapsed_ms": elapsed_ms, "tokens": tokens}
        except json.JSONDecodeError:
            return {"status": "hung", "elapsed_ms": elapsed_ms, "tokens": None}
    except asyncio.TimeoutError:
        elapsed_ms = int((time.monotonic() - start) * 1000)
        return {"status": "hung", "elapsed_ms": elapsed_ms, "tokens": None}
    except OSError:
        return {"status": "down", "elapsed_ms": 0, "tokens": None}


async def _restart_vllm():
    """
    docker restart del contenedor vLLM (mismo container: digest y flags intactos).
    Recupera un EngineCore congelado (throughput 0.0). El modelo tarda ~5-7 min
    en recargar; la probe siguiente reportará "down" durante el reload.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "restart", VLLM_CONTAINER,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await proc.communicate()
        if proc.returncode == 0:
            logger.error(
                "vLLM HUNG confirmado -> 'docker restart %s' lanzado. "
                "Recarga del modelo en ~5-7 min.",
                VLLM_CONTAINER,
            )
        else:
            logger.error(
                "docker restart %s FALLO (rc=%s). stderr=%s",
                VLLM_CONTAINER, proc.returncode, stderr.decode()[:300],
            )
    except OSError as exc:
        logger.error("No se pudo ejecutar docker restart: %s", exc)


async def _vllm_monitor_tick(hang_warn_last):
    """
    Runs every INTERVAL. Returns (new_hang_warn_last, probe_result).
    probe_result = {"status": str, "elapsed_ms": int, "tokens": int|None}
    Detects hung-state and (updated 2026-09-08) restarts vLLM on sustained hang.
    Restart requires VLLM_RESTART_AFTER_HUNG consecutive 'hung' probes (~4 min
    de freeze total) y respeta VLLM_RESTART_COOLDOWN para no entrar en loop.
    """
    ok, code = await _vllm_health()
    probe_result = {"status": "unknown", "elapsed_ms": None, "tokens": None}
    if not ok:
        try:
            boot_s = time.clock_gettime(time.CLOCK_BOOTTIME)
        except Exception:
            boot_s = VLLM_BOOT_GRACE_S  # si no se puede medir, comportamiento legacy
        if boot_s < VLLM_BOOT_GRACE_S:
            logger.info(
                "vLLM aún no responde (boot hace %ds; carga del modelo ~5-7min).",
                int(boot_s),
            )
        elif time.time() - hang_warn_last >= VLLM_HANG_COOLDOWN:
            logger.error(
                "vLLM /health UNHEALTHY (code=%s). Sin restart (cargando o caido).",
                code,
            )
        Path(HANG_FLAG_FILE).touch()
        return time.time(), probe_result

    # Health OK — probe generation
    probe = await _vllm_probe_generation()
    status = probe["status"]
    probe_result = {"status": status, "elapsed_ms": probe["elapsed_ms"], "tokens": probe["tokens"]}

    if status == "ok":
        # Recuperado: limpiar streak y flag
        if getattr(_vllm_monitor_tick, "_hung_streak", 0):
            _vllm_monitor_tick._hung_streak = 0
        if Path(HANG_FLAG_FILE).exists():
            Path(HANG_FLAG_FILE).unlink(missing_ok=True)
            logger.info(
                "vLLM RECOVERED (probe OK, %dms, %s tokens)",
                probe["elapsed_ms"], probe["tokens"],
            )
        elif probe["elapsed_ms"] > 5000:
            logger.warning(
                "vLLM slow probe: %dms (%s tokens) — GPU contention?",
                probe["elapsed_ms"], probe["tokens"],
            )
        else:
            # Quiet happy path; log only on every ~10th tick (~5 min) to avoid spam
            tick_n = getattr(_vllm_monitor_tick, "_tick_n", 0) + 1
            _vllm_monitor_tick._tick_n = tick_n
            if tick_n % 10 == 0:
                logger.info(
                    "vLLM probe OK: %dms, %s tokens (tick=%d)",
                    probe["elapsed_ms"], probe["tokens"], tick_n,
                )
    elif status == "hung":
        # Timeout de un probe trivial (3 tokens). Acumular streak.
        streak = getattr(_vllm_monitor_tick, "_hung_streak", 0) + 1
        _vllm_monitor_tick._hung_streak = streak
        last_restart = getattr(_vllm_monitor_tick, "_last_restart", 0.0)
        Path(HANG_FLAG_FILE).touch()
        if streak >= VLLM_RESTART_AFTER_HUNG:
            if time.time() - last_restart >= VLLM_RESTART_COOLDOWN:
                _vllm_monitor_tick._last_restart = time.time()
                _vllm_monitor_tick._hung_streak = 0
                await _restart_vllm()
            else:
                logger.error(
                    "vLLM HUNG (streak=%d) pero en cooldown de reinicio (%.0fs).",
                    streak, VLLM_RESTART_COOLDOWN - (time.time() - last_restart),
                )
        else:
            logger.error(
                "vLLM GENERATION HUNG (streak=%d/%d): probe timeout %dms.",
                streak, VLLM_RESTART_AFTER_HUNG, probe["elapsed_ms"],
            )
        return time.time(), probe_result
    elif status == "down":
        # API devolvió error (probablemente recargando tras un restart propio).
        if time.time() - hang_warn_last >= VLLM_HANG_COOLDOWN:
            logger.error("vLLM probe returned error (down?). probe=%s", probe)
        Path(HANG_FLAG_FILE).touch()
        return time.time(), probe_result

    return hang_warn_last, probe_result


# ********************************************************************************
# ComfyUI monitoring  (clean when idle, NEVER kill if running work)
# ********************************************************************************

async def _comfyui_queue():
    data = await _curl_json(f"{COMFYUI_BASE}/queue")
    if isinstance(data, dict):
        return data
    return {"queue_running": [], "queue_pending": []}


async def _comfyui_history():
    data = await _curl_json(f"{COMFYUI_BASE}/history/")
    if isinstance(data, dict):
        return data
    return {}


async def _comfyui_free_vram():
    """
    Free ComfyUI's loaded models from VRAM via /free API.
    FIX 2026-09-28 (forense del freeze 03:25): la ruta es POST /free RAÍZ
    (server.py:1192 @routes.post("/free")) — /api/devuelve 404 silencioso y la
    válvula al 93% de RAM no liberaba NADA. Body correcto:
    {unload_models: True, free_memory: True} (unload_clip no existe en el
    handler; free_memory limpia la cache torch). No mata el proceso.
    """
    body = json.dumps({"unload_models": True, "free_memory": True})
    data = await _curl_json(f"{COMFYUI_BASE}/free", method="POST", body=body, timeout=15)
    if data is not None:
        logger.info("ComfyUI /free acknowledged: %s", data)
    else:
        logger.warning("ComfyUI /free returned no response (endpoint /free caído — revisar)")


async def _comfyui_monitor_tick(last_activity_ts, last_free_ts):
    """
    Returns (new_last_activity_ts, new_last_free_ts, idle_seconds).
    If ComfyUI is down (not responding), returns (ts, ts, 0).
    If ComfyUI is up and idle for >= COMFYUI_IDLE_FOR_FREE and we haven't freed
    in the last COMFYUI_IDLE_FOR_FREE seconds, free VRAM.
    """
    queue = await _comfyui_queue()
    history = await _comfyui_history()

    if queue is None and history is None:
        # ComfyUI not running — nothing to clean
        now = time.time()
        return now, last_free_ts, now - (last_free_ts or now)

    is_running = bool(queue.get("queue_running"))
    is_pending = bool(queue.get("queue_pending"))

    if is_running or is_pending:
        new_ts = time.time()
        logger.info(
            "ComfyUI active (%s) — last activity refreshed %.0fs ago",
            "running" if is_running else "pending",
            new_ts - last_activity_ts if last_activity_ts else 0,
        )
        return new_ts, last_free_ts, 0

    # Check if history changed (new recently completed)
    cur_history_keys = set(history.keys()) if history else set()
    # Cache a history snapshot using a module-level attribute
    if not hasattr(_comfyui_monitor_tick, "_last_history_keys"):
        _comfyui_monitor_tick._last_history_keys = frozenset()
    if cur_history_keys != _comfyui_monitor_tick._last_history_keys:
        _comfyui_monitor_tick._last_history_keys = frozenset(cur_history_keys)
        new_ts = time.time()
        return new_ts, last_free_ts, 0

    # Truly idle — check threshold and cooldown
    now = time.time()
    idle_elapsed = now - (last_activity_ts or now)
    if idle_elapsed >= COMFYUI_IDLE_FOR_FREE and (now - last_free_ts) >= COMFYUI_IDLE_FOR_FREE:
        logger.info(
            "ComfyUI idle for %.0fs (>= %ds). Freeing VRAM (NOT killing).",
            idle_elapsed, COMFYUI_IDLE_FOR_FREE,
        )
        await _comfyui_free_vram()
        return last_activity_ts, now, idle_elapsed
    elif int(idle_elapsed) % 120 == 0 and idle_elapsed > 0:
        logger.info(
            "ComfyUI idle %.0fs, will free in %.0fs",
            idle_elapsed, COMFYUI_IDLE_FOR_FREE - idle_elapsed,
        )

    return last_activity_ts, last_free_ts, idle_elapsed


# ********************************************************************************
# Observability: system metrics collection & persistence
# ********************************************************************************

def _collect_system_metrics():
    """
    Collect a snapshot of system resources: RAM%, GPU%, VRAM used/total,
    GPU temp, power draw, load average, swap usage.
    Returns dict suitable for SQLite INSERT.
    """
    now = time.time()
    ts = datetime.fromtimestamp(now).isoformat()

    # RAM
    ram_pct = _system_memory_usage_pct()
    ram_available_gb = None
    ram_total_gb = None
    swap_total_gb = None
    swap_free_gb = None
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    ram_available_gb = round(int(line.split()[1]) / 1024 / 1024, 2)
                elif line.startswith("MemTotal:"):
                    ram_total_gb = round(int(line.split()[1]) / 1024 / 1024, 2)
                elif line.startswith("SwapTotal:"):
                    swap_total_gb = round(int(line.split()[1]) / 1024 / 1024, 2)
                elif line.startswith("SwapFree:"):
                    swap_free_gb = round(int(line.split()[1]) / 1024 / 1024, 2)
    except Exception:
        pass

    # Swap
    swap_used_pct = None
    if swap_total_gb and swap_total_gb > 0:
        swap_used_gb = swap_total_gb - (swap_free_gb or 0)
        swap_used_pct = round(swap_used_gb / swap_total_gb * 100, 1)

    # Load average (1, 5, 15 min)
    load_1 = load_5 = load_15 = None
    try:
        with open("/proc/loadavg") as f:
            parts = f.read().split()
            load_1 = float(parts[0])
            load_5 = float(parts[1])
            load_15 = float(parts[2])
    except Exception:
        pass

    # GPU via nvidia-smi (as root or via sudo, but we run as victoria)
    # On GB10, nvidia-smi works for user victoria for basic stats
    gpu_util = gpu_temp = gpu_power = None
    gpu_mem_used_gb = gpu_mem_total_gb = None
    try:
        import subprocess
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5
        )
        if out.returncode == 0:
            # Parse key=value pairs (resilient to column order changes)
            # Map by column index (position-based, not by name)
            cols = [c.strip() for c in out.stdout.strip().split(",")]
            if len(cols) >= 5:
                # col 0 = utilization.gpu, col 1 = memory.used, col 2 = memory.total
                # col 3 = temperature.gpu, col 4 = power.draw
                if cols[0] and cols[0] != "[N/A]":
                    gpu_util = float(cols[0])
                if cols[1] and cols[1] != "[N/A]":
                    gpu_mem_used_gb = float(cols[1]) / 1024  # MB → GB
                if cols[2] and cols[2] != "[N/A]":
                    gpu_mem_total_gb = float(cols[2]) / 1024  # MB → GB
                if cols[3] and cols[3] != "[N/A]":
                    gpu_temp = float(cols[3])
                if cols[4] and cols[4] != "[N/A]":
                    gpu_power = float(cols[4])
            elif len(cols) >= 4:
                # Older nvidia-smi format (no power.draw)
                if cols[0] and cols[0] != "[N/A]":
                    gpu_util = float(cols[0])
                if cols[1] and cols[1] != "[N/A]":
                    gpu_mem_used_gb = float(cols[1]) / 1024
                if cols[2] and cols[2] != "[N/A]":
                    gpu_mem_total_gb = float(cols[2]) / 1024
                if cols[3] and cols[3] != "[N/A]":
                    gpu_temp = float(cols[3])
    except Exception:
        pass

    return {
        "timestamp": ts,
        "epoch": int(now),
        "ram_pct": ram_pct,
        "ram_available_gb": ram_available_gb,
        "ram_total_gb": ram_total_gb,
        "swap_used_pct": swap_used_pct,
        "swap_total_gb": swap_total_gb,
        "swap_free_gb": swap_free_gb,
        "load_1": load_1,
        "load_5": load_5,
        "load_15": load_15,
        "gpu_util": gpu_util,
        "gpu_temp": gpu_temp,
        "gpu_power_w": gpu_power,
        "gpu_mem_used_gb": gpu_mem_used_gb,
        "gpu_mem_total_gb": gpu_mem_total_gb,
    }


def _collect_vllm_metrics():
    """
    Scrape vLLM Prometheus metrics and extract key gauges.
    Returns dict of metric_name -> value.
    """
    metrics = {}
    try:
        out = subprocess.run(
            ["curl", "-s", "-m", "5", f"{VLLM_BASE}/metrics"],
            capture_output=True, text=True, timeout=10
        )
        if out.returncode != 0:
            return metrics
        for line in out.stdout.splitlines():
            # Parse Prometheus format: metric_name{labels} value
            if not line.startswith("#") and line.strip():
                parts = line.strip().split()
                if len(parts) >= 2:
                    metric_name = parts[0].split("{")[0]  # strip labels
                    try:
                        value = float(parts[1])
                        metrics[metric_name] = value
                    except ValueError:
                        pass
    except Exception:
        pass
    return metrics


def _db_write(metrics, vllm_metrics, tick_info):
    """
    Write a metrics snapshot to the SQLite database.
    One table per category for easy querying.
    """
    try:
        conn = sqlite3.connect(str(METRICS_DB))
        conn.execute("PRAGMA journal_mode=WAL")  # async writes, survives crash

        # Create tables if not exist
        conn.execute("""
            CREATE TABLE IF NOT EXISTS system_metrics (
                epoch INTEGER PRIMARY KEY,
                timestamp TEXT,
                ram_pct REAL, ram_available_gb REAL, ram_total_gb REAL,
                swap_used_pct REAL, swap_total_gb REAL, swap_free_gb REAL,
                load_1 REAL, load_5 REAL, load_15 REAL,
                gpu_util REAL, gpu_temp REAL, gpu_power_w REAL,
                gpu_mem_used_gb REAL, gpu_mem_total_gb REAL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS vllm_metrics (
                epoch INTEGER PRIMARY KEY,
                timestamp TEXT,
                kv_cache_usage_perc REAL,
                num_requests_running REAL,
                num_requests_waiting REAL,
                prefix_cache_hits_total REAL,
                prefix_cache_queries_total REAL,
                num_preemptions_total REAL,
                num_spec_decoded_drafts_total REAL,
                num_spec_decoded_accepted_tokens_total REAL,
                vllm_cpu_bytes REAL  -- process_resident_memory_bytes from /metrics
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tick_info (
                epoch INTEGER PRIMARY KEY,
                timestamp TEXT,
                tick_number INTEGER,
                vllm_probe_status TEXT,
                vllm_probe_ms REAL,
                vllm_probe_tokens INTEGER,
                comfyui_idle_sec REAL,
                memory_alert BOOLEAN
            )
        """)

        # Insert system metrics
        conn.execute("""
            INSERT OR REPLACE INTO system_metrics
            (epoch, timestamp, ram_pct, ram_available_gb, ram_total_gb,
             swap_used_pct, swap_total_gb, swap_free_gb,
             load_1, load_5, load_15,
             gpu_util, gpu_temp, gpu_power_w,
             gpu_mem_used_gb, gpu_mem_total_gb)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            metrics["epoch"], metrics["timestamp"],
            metrics["ram_pct"], metrics["ram_available_gb"], metrics["ram_total_gb"],
            metrics["swap_used_pct"], metrics["swap_total_gb"], metrics["swap_free_gb"],
            metrics["load_1"], metrics["load_5"], metrics["load_15"],
            metrics["gpu_util"], metrics["gpu_temp"], metrics["gpu_power_w"],
            metrics["gpu_mem_used_gb"], metrics["gpu_mem_total_gb"],
        ))

        # Insert vLLM metrics (extract key ones)
        conn.execute("""
            INSERT OR REPLACE INTO vllm_metrics
            (epoch, timestamp, kv_cache_usage_perc, num_requests_running,
             num_requests_waiting, prefix_cache_hits_total,
             prefix_cache_queries_total, num_preemptions_total,
             num_spec_decoded_drafts_total, num_spec_decoded_accepted_tokens_total,
             vllm_cpu_bytes)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, (
            vllm_metrics["epoch"], vllm_metrics["timestamp"],
            vllm_metrics.get("vllm:kv_cache_usage_perc"),
            vllm_metrics.get("vllm:num_requests_running"),
            vllm_metrics.get("vllm:num_requests_waiting"),
            vllm_metrics.get("vllm:prefix_cache_hits_total"),
            vllm_metrics.get("vllm:prefix_cache_queries_total"),
            vllm_metrics.get("vllm:num_preemptions_total"),
            vllm_metrics.get("vllm:spec_decode_num_drafts_total"),
            vllm_metrics.get("vllm:spec_decode_num_accepted_tokens_total"),
            vllm_metrics.get("process_resident_memory_bytes"),
        ))

        # Insert tick info (probe results, comfyui state)
        conn.execute("""
            INSERT INTO tick_info
            (epoch, timestamp, tick_number, vllm_probe_status,
             vllm_probe_ms, vllm_probe_tokens, comfyui_idle_sec, memory_alert)
            VALUES (?,?,?,?,?,?,?,?)
        """, (
            tick_info["epoch"], tick_info["timestamp"],
            tick_info["tick_number"], tick_info["vllm_probe_status"],
            tick_info["vllm_probe_ms"], tick_info["vllm_probe_tokens"],
            tick_info.get("comfyui_idle_sec"),
            tick_info.get("memory_alert", False),
        ))

        conn.commit()
        conn.close()
    except Exception:
        pass  # best effort — don't crash the main loop


def _rotate_metrics():
    """Delete system_metrics and vllm_metrics rows older than METRICS_ROTATION_DAYS."""
    try:
        conn = sqlite3.connect(str(METRICS_DB))
        cutoff = time.time() - (METRICS_ROTATION_DAYS * 86400)
        conn.execute("DELETE FROM system_metrics WHERE epoch < ?", (int(cutoff),))
        conn.execute("DELETE FROM vllm_metrics WHERE epoch < ?", (int(cutoff),))
        conn.execute("DELETE FROM tick_info WHERE epoch < ?", (int(cutoff),))
        conn.commit()
        conn.close()
    except Exception:
        pass


# ********************************************************************************
# Memory safety guard rail (unified memory — GB10 shares CPU+GPU RAM)
# ********************************************************************************

def _system_memory_usage_pct():
    """
    Return % of UNIFIED memory in use. On GB10 there is a single 128 GB pool
    (LPDDR5X) shared by CPU (system RAM) and GPU (VRAM), so the correct signal
    is MemAvailable from /proc/meminfo (not nvidia-smi, which returns empty
    for user victoria).
    """
    try:
        total = available = None
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    total = int(line.split()[1])  # kB
                elif line.startswith("MemAvailable:"):
                    available = int(line.split()[1])  # kB
        if not total or not available:
            return None
        used = total - available
        return round(used / total * 100.0, 1)
    except (OSError, ValueError, IndexError):
        return None


async def _memory_safety_tick(last_alert_ts):
    """
    Guard rail against host OOM/swap. If unified memory exceeds
    MEMORY_SAFETY_PCT%, immediately force-free ComfyUI's loaded models via
    /api/free (ComfyUI is the only elastic consumer; vLLM is NEVER touched).
    Returns updated last_alert_ts.
    """
    pct = _system_memory_usage_pct()
    if pct is None:
        return last_alert_ts
    if pct >= MEMORY_SAFETY_PCT:
        now = time.time()
        if now - last_alert_ts >= MEMORY_SAFETY_COOLDOWN:
            logger.error(
                "MEMORY SAFETY: uso %s%% >= %d%%. Forzando /free de ComfyUI "
                "para proteger el host (OOM/swap). vLLM NO se toca.",
                pct, MEMORY_SAFETY_PCT,
            )
            await _comfyui_free_vram()
            return now
    return last_alert_ts


# ********************************************************************************
# Guardián térmico + limpieza de locks stales (2026-09-30, lección del corte
# 09:19: GPU 96% + 78C sostenidos → freeze + apagón duro. Un solo pesado a
# la vez; si la GPU hierve, se libera ComfyUI y se bloquean nuevos pesados).
# ********************************************************************************

async def _thermal_tick(last_alert_ts):
    """Vigila temp GPU + limpia locks stales. Devuelve updated last_alert_ts."""
    if gpu_arbiter is None:
        return last_alert_ts
    # 1. Limpieza de lock stale (muerto >5h: el archivo queda, read_lock da None)
    try:
        lf = gpu_arbiter.LOCK_FILE
        if os.path.isfile(lf):
            st = gpu_arbiter.read_lock()
            if st is None:
                try:
                    age = time.time() - os.path.getmtime(lf)
                except OSError:
                    age = 0
                if age > gpu_arbiter.LOCK_MAX_AGE_S:
                    os.remove(lf)
                    logger.error("GPU LOCK stale (%.1fh) limpiado.", age / 3600)
    except Exception:
        pass
    # 2. Temperatura
    try:
        temp, util = gpu_arbiter.gpu_temp_util()
    except Exception:
        return last_alert_ts
    if temp is None:
        return last_alert_ts
    now = time.time()
    if temp >= GPU_BLOCK_TEMP:
        if now - last_alert_ts >= GPU_THERMAL_COOLDOWN:
            logger.error("GPU THERMAL: %.0fC >= %.0fC. Forzando /free de ComfyUI; "
                         "el árbitro bloquea pesados nuevos hasta enfriar.",
                         temp, GPU_BLOCK_TEMP)
            await _comfyui_free_vram()
            return now
    elif temp >= GPU_WARN_TEMP:
        if now - last_alert_ts >= GPU_THERMAL_COOLDOWN:
            logger.warning("GPU caliente: %.0fC (aviso ≥%.0fC, bloqueo ≥%.0fC, util %.0f%%). "
                           "/free preventivo de ComfyUI.", temp, GPU_WARN_TEMP,
                           GPU_BLOCK_TEMP, util or 0)
            await _comfyui_free_vram()
            return now
    return last_alert_ts


# ********************************************************************************
# Watchdog de carga sostenida (2026-10-14, duty-cycle 2026-10-17). El térmico
# ve la temperatura; este ve el PATRÓN que congeló el host: util GPU alta SIN
# descanso suficiente. NO mata nada (vLLM intocable, ComfyUI solo /free):
# detecta, libera lo elástico y alerta.
# ********************************************************************************

# Dead man's switch: racha de envíos WhatsApp fallidos (module-level, sobrevive
# entre alertas). >=WA_DEAD_AFTER → la alerta también sale por Discord.
_wa_fail_streak = 0


def _discord_fallback_send(msg):
    """Envía msg por el webhook Discord (TH #ethical-hackers). Stdlib only,
    fire-and-forget. Devuelve True si el POST respondió 2xx."""
    try:
        import urllib.request
        url = None
        with open(DISCORD_WEBHOOKS_FILE) as fh:
            for line in fh:
                line = line.strip()
                if line.startswith(f"{DISCORD_WEBHOOK_KEY}="):
                    url = line.split("=", 1)[1].strip()
                    break
        if not url:
            logger.warning("discord fallback: webhook %s no encontrado", DISCORD_WEBHOOK_KEY)
            return False
        req = urllib.request.Request(
            url, data=json.dumps({"content": msg[:1900]}).encode(),
            headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            ok = 200 <= resp.status < 300
        if ok:
            logger.info("discord fallback: alerta enviada por Discord")
        return ok
    except Exception as exc:
        logger.warning("discord fallback fail (no crítico): %s", exc)
        return False


def _sustained_wa_alert(util, temp, minutes, duty_pct=None):
    """Alerta WhatsApp al owner (fire-and-forget, best-effort, hilo daemon).
    Reusa broadcast_common (misma vía que el alertero del gateway).
    Dead man's switch (2026-10-17): si WA falla WA_DEAD_AFTER veces seguidas,
    la alerta sale TAMBIÉN por Discord (el listener WA pudo estar caído)."""
    global _wa_fail_streak
    try:
        def _logw(m):
            logger.info("wa: %s", m)
        duty_txt = f", duty {duty_pct:.0f}%" if duty_pct is not None else ""
        msg = (f"🌡️ *GPU bajo carga sostenida*: {util:.0f}% durante "
               f"{minutes:.0f} min (ventana 10 min{duty_txt}, temp {temp or 0:.0f}C). "
               "Ya liberé ComfyUI y el gateway está frenando el ritmo (válvula 5). "
               "Protejo el host de freeze — si se colgara igual, power-cycle y "
               "todo auto-arranca.")
        wa_ok = False
        from broadcast_common import wa_resolve, wa_send
        cid, pid, tok = wa_resolve(_logw)
        if cid and pid and tok:
            wa_ok = wa_send(cid, pid, tok, "18295468686", msg, log=_logw)
            if wa_ok:
                logger.info("carga sostenida: alerta WhatsApp enviada al owner")
        else:
            logger.warning("carga sostenida: sin canal WA disponible")
        if wa_ok:
            _wa_fail_streak = 0
            return
        # WA falló o no hay canal → dead man's switch
        _wa_fail_streak += 1
        logger.warning("carga sostenida: WA fail (racha %d/%d)",
                       _wa_fail_streak, WA_DEAD_AFTER)
        if _wa_fail_streak >= WA_DEAD_AFTER:
            dc_msg = ("⚠️ *Canal WhatsApp CAÍDO* (racha " + str(_wa_fail_streak) +
                      " envíos fallidos — listener muerto o sandbox sin sesión).\n" +
                      msg + "\n_Fallback automático gpu-saver → Discord._")
            threading.Thread(target=_discord_fallback_send, args=(dc_msg,),
                             daemon=True).start()
    except Exception as exc:
        logger.warning("carga sostenida WA fail (no crítico): %s", exc)


async def _sustained_load_tick(metrics, window, last_alert_ts):
    """DUTY-CYCLE (2026-10-17): mantiene una ventana deslizante de las últimas
    SUSTAINED_WINDOW_TICKS muestras (10 min) y marca 1 si util >= SUSTAINED_UTIL_PCT.
    Con >=SUSTAINED_WINDOW_MIN muestras: si el % de muestras altas llega a
    SUSTAINED_DUTY_PCT → log ERROR + /free de ComfyUI + alerta WA (cooldown
    30 min) y re-arma (vacía la ventana). Esto caza tanto el patrón continuo
    (freeze 2026-10-13) como el de micro-pausas (apagón 2026-10-16: 96% con
    pausas cada ~2 min que reseteaban el contador de ticks consecutivos).
    Retorna (window, last_alert_ts).
    """
    from collections import deque
    util = metrics.get("gpu_util")
    temp = metrics.get("gpu_temp")
    if util is None:
        return window, last_alert_ts
    window.append(1 if util >= SUSTAINED_UTIL_PCT else 0)
    n = len(window)
    if n < SUSTAINED_WINDOW_MIN:
        return window, last_alert_ts
    duty = 100.0 * sum(window) / n
    if duty < SUSTAINED_DUTY_PCT:
        return window, last_alert_ts
    minutes = n * INTERVAL / 60.0
    now = time.time()
    if now - last_alert_ts >= SUSTAINED_ALERT_COOLDOWN:
        logger.error(
            "CARGA SOSTENIDA: GPU %.0f%%, duty %.0f%% en ventana de %.0f min "
            "(temp %.0fC) — patrón freeze 2026-10-13 / apagón 2026-10-16 "
            "(NVIDIA container-toolkit#1910). /free de ComfyUI + alerta al "
            "owner. vLLM NO se toca.",
            util, duty, minutes, temp or 0)
        await _comfyui_free_vram()
        threading.Thread(target=_sustained_wa_alert,
                         args=(util, temp, minutes, duty), daemon=True).start()
        last_alert_ts = now
    window.clear()  # re-armar: exigir otra ventana antes de re-alertar
    return window, last_alert_ts


# ********************************************************************************
# Main loop
# ********************************************************************************

async def _sleep_interruptibly(seconds):
    """asyncio.sleep but cancellable by _shutdown event."""
    try:
        await asyncio.wait_for(_shutdown.wait(), timeout=seconds)
        return True  # shutdown was set during the wait
    except asyncio.TimeoutError:
        return False


async def run():
    _write_pid()
    await _setup_signals()
    logger.info(
        "victoria-gpu-saver started. INTERVAL=%ds, COMFYUI_FREE_AFTER=%ds, "
        "VLLM_HANG_WARN_AFTER=%ds, VLLM_PROBE_TIMEOUT=%ds, "
        "Metrics DB=%s",
        INTERVAL, COMFYUI_IDLE_FOR_FREE,
        VLLM_HANG_WARN_AFTER, VLLM_PROBE_TIMEOUT,
        METRICS_DB,
    )

    # Init metrics DB and rotate old data
    try:
        _db_write.__globals__["METRICS_DB"] or None  # noqa: used in _db_write
        conn = sqlite3.connect(str(METRICS_DB))
        conn.close()
        _rotate_metrics()
        logger.info("Metrics DB initialized: %s", METRICS_DB)
    except Exception:
        pass

    hang_warn_last = 0.0
    comfy_last_activity = 0.0
    comfy_last_free = 0.0
    mem_last_alert = 0.0
    thermal_last_alert = 0.0
    from collections import deque
    sustained_window = deque(maxlen=SUSTAINED_WINDOW_TICKS)
    sustained_last_alert = 0.0
    tick = 0

    while not _shutdown.is_set():
        logger.info("tick %d starting", tick)
        tick_epoch = int(time.time())

        # --- vLLM monitor (capture probe results) ---
        try:
            hang_warn_last, probe_result = await _vllm_monitor_tick(hang_warn_last)
        except Exception as exc:
            logger.error("vLLM monitor exception: %s", exc)
            probe_result = {"status": "error", "elapsed_ms": None, "tokens": None}

        # --- ComfyUI monitor (capture idle time) ---
        comfy_idle_sec = 0
        try:
            comfy_last_activity, comfy_last_free, comfy_idle_sec = await _comfyui_monitor_tick(
                comfy_last_activity, comfy_last_free
            )
        except Exception as exc:
            logger.error("ComfyUI monitor exception: %s", exc)

        # --- Memory safety (capture alert state) ---
        mem_alert = False
        try:
            mem_last_alert = await _memory_safety_tick(mem_last_alert)
            mem_alert = (mem_last_alert > 0 and
                        time.time() - mem_last_alert < INTERVAL * 2)
        except Exception as exc:
            logger.error("Memory safety tick exception: %s", exc)

        # --- Thermal guardian (2026-09-30) ---
        try:
            thermal_last_alert = await _thermal_tick(thermal_last_alert)
            if (thermal_last_alert > 0 and
                    time.time() - thermal_last_alert < INTERVAL * 2):
                mem_alert = True
        except Exception as exc:
            logger.error("Thermal tick exception: %s", exc)

        # --- Collect system metrics ---
        sys_metrics = _collect_system_metrics()

        # --- Sustained-load watchdog (2026-10-14, duty-cycle 2026-10-17) ---
        try:
            sustained_window, sustained_last_alert = await _sustained_load_tick(
                sys_metrics, sustained_window, sustained_last_alert)
        except Exception as exc:
            logger.error("Sustained-load tick exception: %s", exc)

        # --- Collect vLLM metrics (lightweight scrape) ---
        vllm_m = _collect_vllm_metrics()
        vllm_m["epoch"] = tick_epoch
        vllm_m["timestamp"] = datetime.fromtimestamp(tick_epoch).isoformat()

        # --- Write to SQLite (best effort) ---
        tick_info = {
            "epoch": tick_epoch,
            "timestamp": datetime.fromtimestamp(tick_epoch).isoformat(),
            "tick_number": tick,
            "vllm_probe_status": probe_result.get("status"),
            "vllm_probe_ms": probe_result.get("elapsed_ms"),
            "vllm_probe_tokens": probe_result.get("tokens"),
            "comfyui_idle_sec": comfy_idle_sec,
            "memory_alert": mem_alert,
        }
        _db_write(sys_metrics, vllm_m, tick_info)

        logger.info("tick %d complete, sleeping %ds", tick, INTERVAL)
        tick += 1

        if await _sleep_interruptibly(INTERVAL):
            break


def main():
    Path("/home/victoria/logs").mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )
    try:
        asyncio.run(run())
    finally:
        _remove_pid()
    logger.info("victoria-gpu-saver stopped.")


if __name__ == "__main__":
    main()
