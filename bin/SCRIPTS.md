# SCRIPTS.md - Libreria reutilizable de Kalimete (2026-09-30)

> ANTES de crear un script nuevo, busca aqui y en ~/.local/bin/. Si existe, EJECUTALO.
> Viven en ~/bin/ (propios). Los de ~/.local/bin/ son mayoria herramientas pip/OSINT.

## Propios (~/bin/)

| Script | Que hace | Uso |
|---|---|---|
| kalimete-ptt | Push-to-talk: graba, transcribe via Victoria :18810, pega con ydotool | servicio por tecla (ver ~/.config/kalimete-ptt/env) |
| kalimete-ptt-wrapper.sh | wrapper del PTT | invocado por el atajo de teclado |
| tmp-clean.sh | limpiar ~/tmp respetando KEEP (DRY-RUN default) | tmp-clean.sh, aplicar: --apply |
| new-project.sh | andamiaje: dir + AGENTS.md + scripts/ + README | new-project.sh <nombre> [destino] |
| cfmb25 | (completar: que hace) | cfmb25 --help |
| wp | (completar: que hace) | wp --help |
| osint | busqueda OSINT (motor mudado aqui 2026-09-11) | osint --help |

## Reglas
1. Ejecutar > adivinar. 2. Mejorar > duplicar (no *-v2).
3. Header obligatorio en scripts nuevos. 4. Secretos por env/archivo 600, jamas hardcodeados.
