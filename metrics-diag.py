#!/usr/bin/env python3
"""
metrics-diag.py — Query tool for Victoria's metrics database.
Use to investigate system resource usage and correlate with freezes/crashes.

Database: /home/victoria/logs/victoria-metrics.db
Tables:
  - system_metrics   (RAM%, GPU%, VRAM, temp, load, swap)
  - vllm_metrics     (kv_cache, requests, prefix cache, memory)
  - tick_info        (probe results, comfyui state, memory alerts)

Usage:
  python3 metrics-diag.py [--since HOURS_AGO] [--until HOURS_AGO] [--limit N] [--top N] [--graph]

Examples:
  # Last 1 hour of data (last 120 ticks at 30s intervals)
  python3 metrics-diag.py --since 1

  # Last 24 hours
  python3 metrics-diag.py --since 24

  # Top 10 moments of highest RAM usage
  python3 metrics-diag.py --top ram_pct

  # Top 10 moments of highest GPU utilization
  python3 metrics-diag.py --top gpu_util

  # Top 10 moments with most vLLM requests running
  python3 metrics-diag.py --top vllm_requests_running

  # Top 10 moments with slowest vLLM probe (potential freeze precursors)
  python3 metrics-diag.py --top vllm_probe_ms

  # Top 10 moments of highest load
  python3 metrics-diag.py --top load_1

  # Last 30 minutes, show full table
  python3 metrics-diag.py --since 0.5

  # Graph mode: ASCII chart of RAM usage over time
  python3 metrics-diag.py --since 4 --graph ram_pct

  # Compare RAM and GPU over time (dual chart)
  python3 metrics-diag.py --since 2 --graph "ram_pct,gpu_util"

  # Find all ticks where RAM > 80% (potential OOM risk)
  python3 metrics-diag.py --since 48 --filter "ram_pct > 80"

  # Find all ticks where vLLM probe was slow (> 2000ms)
  python3 metrics-diag.py --since 48 --filter "vllm_probe_ms > 2000"

  # Find all ticks with memory safety alerts
  python3 metrics-diag.py --since 48 --filter "memory_alert = 1"

  # Last 6 hours, show summary stats
  python3 metrics-diag.py --since 6 --stats

  # Full query: last 2 hours, sorted by epoch descending
  python3 metrics-diag.py --since 2 --sort desc --limit 100
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta

DB_PATH = "/home/victoria/logs/victoria-metrics.db"

# Column descriptions for display
COLUMN_DESC = {
    "epoch": "Epoch (unix)",
    "timestamp": "ISO Timestamp",
    "tick_number": "Tick #",
    "ram_pct": "RAM %",
    "ram_available_gb": "RAM Avail (GB)",
    "ram_total_gb": "RAM Total (GB)",
    "swap_used_pct": "Swap %",
    "swap_total_gb": "Swap Total (GB)",
    "swap_free_gb": "Swap Free (GB)",
    "load_1": "Load 1min",
    "load_5": "Load 5min",
    "load_15": "Load 15min",
    "gpu_util": "GPU Util %",
    "gpu_mem_used_gb": "GPU Mem Used (GB)",
    "gpu_mem_total_gb": "GPU Mem Total (GB)",
    "gpu_temp": "GPU Temp C",
    "gpu_power_w": "GPU Power W",
    "kv_cache_usage_perc": "KV Cache %",
    "num_requests_running": "vLLM Running",
    "num_requests_waiting": "vLLM Waiting",
    "prefix_cache_hits_total": "Prefix Hits",
    "prefix_cache_queries_total": "Prefix Queries",
    "num_preemptions_total": "Preemptions",
    "num_spec_decoded_drafts_total": "Spec Drafts",
    "num_spec_decoded_accepted_tokens_total": "Spec Accepted",
    "vllm_cpu_bytes": "vLLM Mem (bytes)",
    "vllm_probe_status": "Probe Status",
    "vllm_probe_ms": "Probe ms",
    "vllm_probe_tokens": "Probe Tokens",
    "comfyui_idle_sec": "ComfyUI Idle (s)",
    "memory_alert": "Mem Alert",
}

# Columns for each table
SYSTEM_COLS = [
    "epoch", "timestamp", "ram_pct", "ram_available_gb", "ram_total_gb",
    "swap_used_pct", "swap_total_gb", "swap_free_gb",
    "load_1", "load_5", "load_15",
    "gpu_util", "gpu_temp", "gpu_power_w",
    "gpu_mem_used_gb", "gpu_mem_total_gb",
]

VLLM_COLS = [
    "epoch", "timestamp",
    "kv_cache_usage_perc", "num_requests_running", "num_requests_waiting",
    "prefix_cache_hits_total", "prefix_cache_queries_total",
    "num_preemptions_total",
    "num_spec_decoded_drafts_total", "num_spec_decoded_accepted_tokens_total",
    "vllm_cpu_bytes",
]

TICK_COLS = [
    "epoch", "timestamp", "tick_number",
    "vllm_probe_status", "vllm_probe_ms", "vllm_probe_tokens",
    "comfyui_idle_sec", "memory_alert",
]


def connect_db():
    """Connect to the metrics database."""
    if not os.path.exists(DB_PATH):
        print(f"ERROR: Database not found at {DB_PATH}", file=sys.stderr)
        print("The gpu-saver may not have been running or the database was rotated.", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def format_value(value, column):
    """Format a value for display."""
    if value is None:
        return "N/A"
    if column in ("ram_pct", "swap_used_pct", "gpu_util"):
        return f"{value:.1f}%"
    if column in ("gpu_temp",):
        return f"{value:.0f}C" if value else "N/A"
    if column in ("gpu_power_w",):
        return f"{value:.1f}W" if value else "N/A"
    if column in ("ram_available_gb", "ram_total_gb", "gpu_mem_used_gb", "gpu_mem_total_gb",
                  "swap_total_gb", "swap_free_gb"):
        return f"{value:.1f}GB" if value else "N/A"
    if column in ("vllm_cpu_bytes",):
        if value:
            mb = value / (1024 * 1024)
            return f"{mb:.0f}MB"
        return "N/A"
    if column in ("vllm_probe_ms",):
        if value:
            if value > 5000:
                return f"{value:.0f}ms ⚠️ SLOW"
            return f"{value:.0f}ms"
        return "N/A"
    if column == "vllm_probe_status":
        if value == "ok":
            return "✅"
        elif value == "hung":
            return "🚨 HUNG"
        elif value == "error":
            return "❌ ERROR"
        return str(value)
    if column == "memory_alert":
        return "🚨 YES" if value else "—"
    if column in ("load_1", "load_5", "load_15"):
        return f"{value:.2f}" if value else "N/A"
    if column in ("num_requests_running", "num_requests_waiting", "tick_number",
                  "vllm_probe_tokens", "comfyui_idle_sec"):
        return str(int(value)) if value else "—"
    return str(value)


def print_header(columns):
    """Print column headers."""
    header_parts = []
    for col in columns:
        label = COLUMN_DESC.get(col, col)
        header_parts.append(f"{label:>20}")
    print(" | ".join(header_parts))
    print("-" * (len(header_parts) * 22 - 1))


def print_row(row, columns):
    """Print a formatted row."""
    row_dict = dict(row)
    parts = []
    for col in columns:
        value = row_dict.get(col)
        parts.append(f"{format_value(value, col):>20}")
    print(" | ".join(parts))


def query_system_metrics(since_hours, until_hours, limit, sort_order, filter_clause):
    """Query system_metrics table."""
    conn = connect_db()
    cutoff_epoch = int(datetime.now().timestamp()) - int(since_hours * 3600)
    if until_hours > 0:
        until_epoch = int(datetime.now().timestamp()) - int(until_hours * 3600)
        clause = f"WHERE epoch >= {cutoff_epoch} AND epoch <= {until_epoch}"
    else:
        clause = f"WHERE epoch >= {cutoff_epoch}"
    if filter_clause:
        clause += f" AND {filter_clause}"
    clause += f" ORDER BY epoch {sort_order}"
    if limit:
        clause += f" LIMIT {limit}"
    rows = conn.execute(f"SELECT * FROM system_metrics {clause}").fetchall()
    conn.close()
    return rows


def query_vllm_metrics(since_hours, until_hours, limit, sort_order, filter_clause):
    """Query vllm_metrics table."""
    conn = connect_db()
    cutoff_epoch = int(datetime.now().timestamp()) - int(since_hours * 3600)
    if until_hours > 0:
        until_epoch = int(datetime.now().timestamp()) - int(until_hours * 3600)
        clause = f"WHERE epoch >= {cutoff_epoch} AND epoch <= {until_epoch}"
    else:
        clause = f"WHERE epoch >= {cutoff_epoch}"
    if filter_clause:
        clause += f" AND {filter_clause}"
    clause += f" ORDER BY epoch {sort_order}"
    if limit:
        clause += f" LIMIT {limit}"
    rows = conn.execute(f"SELECT * FROM vllm_metrics {clause}").fetchall()
    conn.close()
    return rows


def query_tick_info(since_hours, until_hours, limit, sort_order, filter_clause):
    """Query tick_info table."""
    conn = connect_db()
    cutoff_epoch = int(datetime.now().timestamp()) - int(since_hours * 3600)
    if until_hours > 0:
        until_epoch = int(datetime.now().timestamp()) - int(until_hours * 3600)
        clause = f"WHERE epoch >= {cutoff_epoch} AND epoch <= {until_epoch}"
    else:
        clause = f"WHERE epoch >= {cutoff_epoch}"
    if filter_clause:
        clause += f" AND {filter_clause}"
    clause += f" ORDER BY epoch {sort_order}"
    if limit:
        clause += f" LIMIT {limit}"
    rows = conn.execute(f"SELECT * FROM tick_info {clause}").fetchall()
    conn.close()
    return rows


def query_top(since_hours, top_col, limit):
    """Query top N moments by a specific column."""
    # Determine which table has this column
    conn = connect_db()
    cutoff_epoch = int(datetime.now().timestamp()) - int(since_hours * 3600)

    table = None
    columns = None
    for tbl, cols in [("system_metrics", SYSTEM_COLS), ("vllm_metrics", VLLM_COLS), ("tick_info", TICK_COLS)]:
        if top_col in cols:
            table = tbl
            columns = cols
            break

    if table is None:
        print(f"ERROR: Column '{top_col}' not found in any table.", file=sys.stderr)
        print(f"Available columns: {[c for c in COLUMN_DESC.keys()]}", file=sys.stderr)
        conn.close()
        sys.exit(1)

    rows = conn.execute(
        f"SELECT * FROM {table} WHERE epoch >= {cutoff_epoch} ORDER BY {top_col} DESC LIMIT {limit}"
    ).fetchall()
    conn.close()
    return rows, columns, table


def query_stats(since_hours):
    """Query summary statistics for the given period."""
    conn = connect_db()
    cutoff_epoch = int(datetime.now().timestamp()) - int(since_hours * 3600)

    # System metrics stats
    sys_stats = conn.execute(
        f"SELECT MIN(ram_pct) as ram_min, MAX(ram_pct) as ram_max, AVG(ram_pct) as ram_avg,"
        f" MIN(gpu_util) as gpu_min, MAX(gpu_util) as gpu_max, AVG(gpu_util) as gpu_avg,"
        f" MIN(load_1) as load_min, MAX(load_1) as load_max, AVG(load_1) as load_avg,"
        f" MIN(swap_used_pct) as swap_min, MAX(swap_used_pct) as swap_max, AVG(swap_used_pct) as swap_avg,"
        f" COUNT(*) as tick_count FROM system_metrics WHERE epoch >= {cutoff_epoch}"
    ).fetchone()

    # vLLM stats (combined from vllm_metrics + tick_info)
    vllm_stats = conn.execute(
        f"SELECT MIN(num_requests_running) as vllm_req_min, MAX(num_requests_running) as vllm_req_max,"
        f" AVG(num_requests_running) as vllm_req_avg,"
        f" MIN(kv_cache_usage_perc) as kvcache_min, MAX(kv_cache_usage_perc) as kvcache_max,"
        f" COUNT(*) as tick_count FROM vllm_metrics WHERE epoch >= {cutoff_epoch}"
    ).fetchone()

    probe_stats = conn.execute(
        f"SELECT MIN(vllm_probe_ms) as probe_min, MAX(vllm_probe_ms) as probe_max,"
        f" AVG(vllm_probe_ms) as probe_avg,"
        f" SUM(CASE WHEN vllm_probe_status = 'hung' THEN 1 ELSE 0 END) as hangs,"
        f" SUM(CASE WHEN vllm_probe_status = 'error' THEN 1 ELSE 0 END) as errors,"
        f" COUNT(*) as tick_count FROM tick_info WHERE epoch >= {cutoff_epoch}"
    ).fetchone()

    # Tick info stats
    tick_stats = conn.execute(
        f"SELECT COUNT(*) as tick_count,"
        f" SUM(CASE WHEN memory_alert = 1 THEN 1 ELSE 0 END) as mem_alerts,"
        f" SUM(CASE WHEN vllm_probe_status = 'hung' THEN 1 ELSE 0 END) as hangs,"
        f" SUM(CASE WHEN vllm_probe_status = 'error' THEN 1 ELSE 0 END) as errors,"
        f" SUM(CASE WHEN comfyui_idle_sec > 300 THEN 1 ELSE 0 END) as comfy_idle_over_5min"
        f" FROM tick_info WHERE epoch >= {cutoff_epoch}"
    ).fetchone()

    conn.close()
    return sys_stats, vllm_stats, tick_stats, probe_stats


def graph_data(rows, column, width=80, height=20):
    """Create an ASCII chart for the given column."""
    if not rows:
        print("No data to chart.")
        return

    # Determine which table this column is from
    col_table = None
    for tbl, cols in [("system_metrics", SYSTEM_COLS), ("vllm_metrics", VLLM_COLS), ("tick_info", TICK_COLS)]:
        if column in cols:
            col_table = tbl
            break

    if col_table is None:
        print(f"ERROR: Column '{column}' not found.", file=sys.stderr)
        return

    # Get min/max for scaling
    values = []
    for row in rows:
        v = dict(row).get(column)
        if v is not None:
            values.append(v)

    if not values:
        print("No numeric values to chart.")
        return

    min_val = min(values)
    max_val = max(values)
    if min_val == max_val:
        max_val = min_val + 1

    height_range = max_val - min_val
    if height_range == 0:
        height_range = 1

    # Chart
    print(f"\nChart: {COLUMN_DESC.get(column, column)} ({len(values)} data points)")
    print(f"  Min: {min_val:.2f}, Max: {max_val:.2f}")
    print()

    for row_idx in range(height, -1, -1):
        y_val = min_val + (height_range * row_idx / height)
        bar = " " * width
        for col_idx, val in enumerate(values):
            if val is not None and val > 0:
                bar_idx = int(((val - min_val) / height_range) * height)
                if bar_idx == row_idx:
                    if col_idx < len(bar):
                        bar = bar[:col_idx] + "#" + bar[col_idx+1:]

        # Label the y-axis
        if row_idx == height or row_idx == 0 or row_idx == height // 2:
            label = f"{y_val:.2f} |"
            print(f"{label}{bar}")
        else:
            print(f"     |{bar}")

    # X-axis
    x_label = f"     +{'-' * width}"
    print(x_label)
    print(f"      {datetime.fromtimestamp(rows[0]['epoch']).strftime('%H:%M')}{' ' * (len(str(rows[-1]['epoch'])) - 4)}{datetime.fromtimestamp(rows[-1]['epoch']).strftime('%H:%M')}")
    print(f"      ← {rows[0]['epoch']}{' ' * (len(str(rows[-1]['epoch'])) - 4)}→ {rows[-1]['epoch']}")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Victoria Metrics Diagnostic Tool — investigate system resource usage",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--since", type=float, default=1.0,
                        help="Hours ago to start from (default: 1)")
    parser.add_argument("--until", type=float, default=0.0,
                        help="Hours ago to end at (default: 0 = now)")
    parser.add_argument("--limit", type=int, default=50,
                        help="Max rows to show (default: 50)")
    parser.add_argument("--top", type=str, default=None,
                        help="Top N moments by column value")
    parser.add_argument("--stats", action="store_true",
                        help="Show summary statistics")
    parser.add_argument("--graph", type=str, default=None,
                        help="Column to chart (e.g., ram_pct, gpu_util, vllm_probe_ms)")
    parser.add_argument("--graph-all", action="store_true",
                        help="Chart all numeric columns")
    parser.add_argument("--filter", type=str, default=None,
                        help="SQL WHERE clause (without 'WHERE', e.g., 'ram_pct > 80')")
    parser.add_argument("--sort", type=str, default="asc", choices=["asc", "desc"],
                        help="Sort order (default: asc)")

    args = parser.parse_args()

    # --top mode
    if args.top:
        rows, columns, table = query_top(args.since, args.top, args.limit)
        if not rows:
            print(f"No data for the last {args.since} hours.")
            return
        print(f"\n🏆 TOP {len(rows)} moments by {COLUMN_DESC.get(args.top, args.top)}")
        print(f"   Period: last {args.since} hours, sorted by {args.top} DESC")
        print()
        print_header(columns)
        for row in rows:
            print_row(row, columns)
        return

    # --stats mode
    if args.stats:
        sys_stats, vllm_stats, tick_stats, probe_stats = query_stats(args.since)
        print(f"\n📊 SUMMARY STATISTICS — Last {args.since} hours")
        print("=" * 60)

        # System stats
        print("\n🖥️  System Resources:")
        print(f"  RAM:     {sys_stats['ram_min']:.1f}% → {sys_stats['ram_max']:.1f}%  (avg {sys_stats['ram_avg']:.1f}%)")
        print(f"  GPU:     {sys_stats['gpu_min']:.1f}% → {sys_stats['gpu_max']:.1f}%  (avg {sys_stats['gpu_avg']:.1f}%)")
        print(f"  Load 1m: {sys_stats['load_min']:.2f} → {sys_stats['load_max']:.2f}  (avg {sys_stats['load_avg']:.2f})")
        print(f"  Swap:    {sys_stats['swap_min']:.1f}% → {sys_stats['swap_max']:.1f}%  (avg {sys_stats['swap_avg']:.1f}%)")

        # vLLM stats
        print("\n🤖 vLLM Metrics:")
        print(f"  Requests running: {vllm_stats['vllm_req_min']} → {vllm_stats['vllm_req_max']}  (avg {vllm_stats['vllm_req_avg']:.1f})")
        print(f"  KV Cache: {vllm_stats['kvcache_min'] * 100:.1f}% → {vllm_stats['kvcache_max'] * 100:.1f}%")

        # Probe stats
        probe_ms_avg = probe_stats['probe_avg']
        probe_status_label = "✅ Healthy" if probe_ms_avg < 500 else "⚠️ Slow" if probe_ms_avg < 2000 else "🚨 Very Slow"
        print(f"  Probe latency: {probe_stats['probe_min']:.0f}ms → {probe_stats['probe_max']:.0f}ms  (avg {probe_ms_avg:.0f}ms) {probe_status_label}")
        print(f"  vLLM hangs: {probe_stats['hangs']}")
        print(f"  Probe errors: {probe_stats['errors']}")

        # Tick stats
        print("\n⏱️  Tick Summary:")
        print(f"  Total ticks: {tick_stats['tick_count']}")
        print(f"  Memory alerts: {tick_stats['mem_alerts']}")
        print(f"  vLLM hangs: {tick_stats['hangs']}")
        print(f"  Probe errors: {tick_stats['errors']}")
        print(f"  ComfyUI idle >5min: {tick_stats['comfy_idle_over_5min']}")
        print()
        return

    # --graph mode
    if args.graph:
        graph_columns = [c.strip() for c in args.graph.split(",")]
        for col in graph_columns:
            rows_list = query_system_metrics(args.since, args.until, None, "asc", args.filter) if col in SYSTEM_COLS else \
                       query_vllm_metrics(args.since, args.until, None, "asc", args.filter) if col in VLLM_COLS else \
                       query_tick_info(args.since, args.until, None, "asc", args.filter) if col in TICK_COLS else []
            graph_data(rows_list, col)
        return

    if args.graph_all:
        all_cols = [c for c in ["ram_pct", "gpu_util", "load_1", "gpu_temp", "vllm_probe_ms", "kv_cache_usage_perc"] if c in SYSTEM_COLS or c in VLLM_COLS or c in TICK_COLS]
        for col in all_cols:
            rows_list = query_system_metrics(args.since, args.until, None, "asc", args.filter) if col in SYSTEM_COLS else \
                       query_vllm_metrics(args.since, args.until, None, "asc", args.filter) if col in VLLM_COLS else \
                       query_tick_info(args.since, args.until, None, "asc", args.filter)
            graph_data(rows_list, col)
        return

    # Default: show system_metrics table
    rows = query_system_metrics(args.since, args.until, args.limit, args.sort, args.filter)
    if not rows:
        print(f"No data for the last {args.since} hours.")
        return

    # Show a combined view: system + vllm + tick (joined by epoch)
    print(f"\n📈 SYSTEM + vLLM + TICK METRICS — Last {args.since} hours")
    print(f"   {len(rows)} data points, sorted by epoch {args.sort}")
    print()

    # Show a combined view
    all_keys = set()
    for row in rows:
        all_keys.update(dict(row).keys())

    # Prioritize important columns
    priority_cols = ["timestamp", "ram_pct", "gpu_util", "load_1", "gpu_temp",
                     "kv_cache_usage_perc", "num_requests_running", "vllm_probe_ms",
                     "vllm_probe_status", "memory_alert"]
    other_cols = [c for c in SYSTEM_COLS + VLLM_COLS + TICK_COLS if c not in priority_cols]
    display_cols = [c for c in priority_cols if c in all_keys] + other_cols

    print_header(display_cols)
    for row in rows:
        print_row(row, display_cols)


if __name__ == "__main__":
    main()
