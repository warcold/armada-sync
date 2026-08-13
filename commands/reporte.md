---
description: Muestra la actividad de las últimas 24h del ecosistema Armada (todos los servidores) en modo grid: sesiones, agentes, tokens y resumen ejecutivo generado por llmgate. También envía el reporte a Discord Piso 14 si se pide.
---

Ejecuta el script de reporte diario del ecosistema Armada:

```bash
python3 ~/armada-sync/daily-report/report.py --dry-run
```

Muestra el resultado al usuario de forma clara y resumida:
1. La tabla de actividad (grid) con servidor, agente, sesiones, tokens y última actividad.
2. Las sesiones del día con su título y primer mensaje.
3. Si el usuario pidió enviarlo a Discord, ejecuta `python3 ~/armada-sync/daily-report/report.py` (sin `--dry-run`) que además genera el resumen ejecutivo con llmgate y lo publica en el canal Piso 14.

Si el usuario quiere más detalle de una sesión específica, consulta la DB SQLite con `sqlite3 ~/.local/share/opencode/opencode.db` (tablas `session`, `message`, `part`).