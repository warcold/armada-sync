# Bash — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `bash --version` → 5.2.21)
> **Docs oficiales**: https://www.gnu.org/software/bash/manual/

## Versiones en uso

- Host victoria: bash 5.2.21 (aarch64) — scripts del stack, ensure-loops, units
- kalimete: **zsh** como shell de usuario (⚠️ los comandos SSH con comillas dobles pasan por zsh remoto)

## Patrones que usamos

- Scripts con `set -u` en daemons largos (ensure-loop) — cuidado con variables unbound en funciones reutilizadas (`${1:-}` no `$1`)
- systemd units `ExecStart` con rutas absolutas SIEMPRE
- Cron + timers systemd (timers preferidos: `Persistent=true` recupera slots perdidos)

## Gotchas descubiertos (lecciones)

- **`pkill -f <patrón>` se mata a sí mismo si el patrón matchea la línea de comando del propio shell del tool** — excluir el propio PID o refinar el patrón. — (CHANGELOG-sonic)
- **Backticks en comandos SSH con comillas dobles: el zsh remoto los sustituye** — usar `$(...)` o comillas simples. — (CHANGELOG)
- **`set -u` + funciones llamadas sin argumentos = crash del daemon largo** (`$1` unbound) — siempre `${1:-}`. — (CHANGELOG 2026-08-16, crash-loop del ensure-loop)
- **Editar un script NO recarga el proceso vivo** — `systemctl restart` tras editar. — (CHANGELOG-sandbox)
- **rbash (usuario warcold) bloquea `cd` y redirecciones `>`/`>>`** — los scripts para warcold deben asumir eso. — (AGENTS.md §7.1)

## Regla de actualización

Bash del sistema: no tocar (Ubuntu base). Los scripts nuevos: rutas absolutas,
`${var:-}` defensivo, sin backticks en SSH, y changelog si toca el stack.
