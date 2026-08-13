#!/usr/bin/env python3
"""Reporte diario de actividad del ecosistema Armada.

Recolecta las sesiones de opencode (SQLite) de los 4 servidores locales
(kalimete, victoria, rootsource, jonas) de las últimas 24 horas,
genera un resumen ejecutivo con el LLM local (llmgate) y lo envía
al canal de Discord Piso 14 (#general-chat).

Uso:
  report.py [--hours 24] [--dry-run] [--json]
"""
import argparse
import json
import os
import sqlite3
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta

# ── Configuración ────────────────────────────────────────────────
SERVERS = [
    {"name": "kalimete",  "user": "warcold",   "host": "127.0.0.1", "ssh": None},
    {"name": "victoria",  "user": "victoria",  "host": "victoria.local",  "ssh": True},
    {"name": "rootsource","user": "rootsource","host": "rootsource.local","ssh": True},
    {"name": "jonas",     "user": "jonas",     "host": "jonas.local",     "ssh": True, "optional": True},
]
DB_PATH = "~/.local/share/opencode/opencode.db"
LLMGATE = "http://10.0.0.5:4010/v1/chat/completions"
MODEL = "qwen3.6"
DISCORD_CHANNEL = "1492992262085546025"  # #general-chat Piso 14
DISCORD_TOKEN = os.environ.get("DISCORD_TOKEN", "")
STATE_FILE = os.path.expanduser("~/.config/opencode/daily-report-state.json")

SQL = """
WITH user_msgs AS (
  SELECT m.session_id, min(m.time_created) as t, m.id as mid
  FROM message m WHERE m.data LIKE '%"role":"user"%' GROUP BY m.session_id
)
SELECT s.id,
       s.agent,
       s.title,
       s.tokens_input,
       s.tokens_output,
       s.tokens_reasoning,
       s.cost,
       datetime(s.time_created/1000, 'unixepoch', 'localtime') AS created,
       datetime(s.time_updated/1000, 'unixepoch', 'localtime') AS updated,
       substr(COALESCE((SELECT p.data FROM part p
                        WHERE p.message_id = um.mid
                          AND json_extract(p.data,'$.type')='text' LIMIT 1), '{}'), 1, 400) AS first_msg
FROM session s JOIN user_msgs um ON um.session_id = s.id
WHERE s.time_updated > (strftime('%s','now')*1000 - {hours}*3600000)
  AND s.time_archived IS NULL
ORDER BY s.time_updated DESC
"""


def ssh_query(server, hours):
    """Ejecuta la query SQLite en un servidor remoto vía SSH (SQL por stdin)."""
    if not server.get("ssh"):
        return query_local(hours)
    sql = SQL.replace("{hours}", str(hours))
    db = DB_PATH.replace("~", f"/home/{server['user']}")
    cmd = f"ssh -o ConnectTimeout=6 -o BatchMode=yes {server['user']}@{server['host']} 'sqlite3 -json {db}'"
    try:
        proc = subprocess.run(cmd, shell=True, input=sql, capture_output=True, text=True, timeout=25)
        out = proc.stdout.strip()
        if not out:
            return []
        data = json.loads(out)
        return data
    except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
        print(f"  ⚠️ {server['name']}: {type(e).__name__}: {e}", file=sys.stderr)
        return None


def query_local(hours):
    """Consulta la DB local de kalimete."""
    db = os.path.expanduser(DB_PATH)
    if not os.path.exists(db):
        return None
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        sql = SQL.replace("{hours}", str(hours))
        rows = con.execute(sql).fetchall()
        cols = [d[0] for d in con.execute(sql).description]
        con.close()
        return [dict(zip(cols, r)) for r in rows]
    except sqlite3.Error as e:
        print(f"  ⚠️ kalimete: {e}", file=sys.stderr)
        return None


def first_text(raw):
    try:
        d = json.loads(raw)
        return d.get("text", "").strip()[:180]
    except Exception:
        return ""


def build_report(data, hours):
    """Genera el markdown del reporte."""
    lines = []
    total_sessions = 0
    total_in = total_out = 0
    grid = []

    for server, sessions in data:
        if sessions is None:
            grid.append((server, "ERROR", 0, 0, 0, "-"))
            continue
        if not sessions:
            grid.append((server, "sin actividad", 0, 0, 0, "-"))
            continue
        total_sessions += len(sessions)
        for s in sessions:
            total_in += int(s.get("tokens_input") or 0)
            total_out += int(s.get("tokens_output") or 0)
        agents = {}
        for s in sessions:
            a = s.get("agent") or "build"
            agents.setdefault(a, []).append(s)
        for agent, sess in sorted(agents.items()):
            ts = sum(int(s.get("tokens_input") or 0) for s in sess)
            to = sum(int(s.get("tokens_output") or 0) for s in sess)
            last = max(s["updated"] for s in sess)
            grid.append((server, agent, len(sess), ts, to, last))

    # ── Grid resumen por agente ──
    lines.append(f"# 📊 Reporte diario Armada — últimas {hours}h")
    lines.append(f"**Fecha:** {datetime.now().strftime('%A %d %b %Y, %H:%M')}")
    lines.append("")
    lines.append(f"**Total:** {total_sessions} sesiones · {total_in/1e6:.1f}M tokens in · {total_out/1e6:.1f}M tokens out")
    lines.append("")
    lines.append("## Tabla de actividad")
    lines.append("")
    lines.append("| Servidor | Agente | Sesiones | Tokens in | Tokens out | Última act. |")
    lines.append("|----------|--------|----------|-----------|------------|-------------|")
    for server, agent, n, ti, to, last in grid:
        lines.append(f"| {server} | {agent} | {n} | {ti/1e6:.2f}M | {to/1e6:.2f}M | {last[11:16]} |")

    # ── Detalle por sesión ──
    for server, sessions in data:
        if not sessions:
            continue
        lines.append("")
        lines.append(f"## {server} ({len(sessions)} sesiones)")
        for s in sessions:
            txt = first_text(s.get("first_msg", ""))
            lines.append(f"- **{s['updated'][11:16]}** `{s.get('agent') or 'build'}` · {s['title'][:60]}")
            if txt:
                lines.append(f"  > {txt[:140]}")
    return "\n".join(lines)


def llm_summary(report_md, hours):
    """Genera un resumen ejecutivo con el LLM local (llmgate)."""
    api_key = os.environ.get("ROOTSOURCE_API_KEY", "")
    if not api_key:
        return None
    prompt = f"""Eres el analista de actividad del ecosistema Armada. Genera un RESUMEN EJECUTIVO
en español de máximo 180 palabras sobre el trabajo realizado en las últimas {hours} horas,
como si fuera el reporte diario de un equipo de trabajo. Estructura:
1) Qué se hizo (2-4 líneas)
2) Agentes/servidores más activos
3) Logros destacados
4) Pendientes o riesgos

Datos brutos del día:
{report_md[:6000]}"""
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "system", "content": prompt}],
        "max_tokens": 400,
        "temperature": 0.4,
    }).encode()
    req = urllib.request.Request(LLMGATE, data=body, headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            d = json.loads(r.read())
            return d["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"  ⚠️ LLM summary: {e}", file=sys.stderr)
        return None


def send_discord(text, embed_text=None):
    """Envía el reporte al canal Piso 14 de Discord."""
    if not DISCORD_TOKEN:
        print("  ⚠️ DISCORD_TOKEN no configurado — reporte no enviado", file=sys.stderr)
        return False
    msg = text if len(text) <= 1900 else text[:1900] + "\n… (truncado)"
    body = json.dumps({"content": msg}).encode()
    req = urllib.request.Request(
        f"https://discord.com/api/v10/channels/{DISCORD_CHANNEL}/messages",
        data=body,
        headers={"Authorization": f"Bot {DISCORD_TOKEN}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception as e:
        print(f"  ⚠️ Discord: {e}", file=sys.stderr)
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=int, default=24)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    print(f"📡 Recolectando actividad de los últimos {args.hours}h…")
    data = []
    for s in SERVERS:
        print(f"  → {s['name']}…")
        res = ssh_query(s, args.hours)
        data.append((s["name"], res))

    report = build_report(data, args.hours)

    if args.json:
        print(report)
        return

    print("\n" + report)

    if args.dry_run:
        print("\n[Dry-run: no se envía a Discord]")
        return

    # Resumen ejecutivo con llmgate
    summary = llm_summary(report, args.hours)
    if summary:
        print("\n🤖 Resumen ejecutivo (llmgate):\n" + summary)

    # Enviar a Discord (grid + resumen en mensajes separados)
    ok1 = send_discord("📊 **REPORTE DIARIO ARMADA**\n" + report)
    ok2 = send_discord("🤖 **Resumen ejecutivo**\n\n" + summary) if summary else False
    print(f"\n✅ Discord: {'OK' if ok1 else 'FALLÓ'} | Resumen: {'OK' if ok2 else 'n/a'}")

    # Guardar estado (última ejecución)
    with open(STATE_FILE, "w") as f:
        json.dump({"last_run": datetime.now().isoformat(), "ok": ok1}, f)


if __name__ == "__main__":
    main()