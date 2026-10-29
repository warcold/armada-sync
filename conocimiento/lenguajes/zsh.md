# zsh — doc viva del ecosistema

> **Verificado**: 2026-10-27 (shell de usuario en kalimete; victoria usa bash)
> **Docs oficiales**: https://zsh.sourceforge.io/Doc/

## Dónde se usa

- kalimete: shell de usuario warcold (zsh) — TODOS los comandos SSH a kalimete pasan por zsh remoto
- victoria: bash 5.2 (sin zsh)

## Gotchas descubiertos (lecciones)

- **Backticks en comandos SSH con comillas dobles: zsh los sustituye** — usar `$(...)` o comillas simples. Este es el gotcha #1 del cross-machine. — (CHANGELOG)
- **Globbing distinto**: zsh expande globs sin match con error (nullglob behavior distinto a bash) — en scripts SSH usar `setopt null_glob` o evitar globs.
- **Herencia de env**: `source ~/.config/kalimete-ptt/env` con `set -a` para exportar variables antes de ejecutar python ad-hoc — sin esto los módulos leen env vacío (lección del falso 401, 2026-10-27). — (CHANGELOG-voice)

## Regla de actualización

No actualizar zsh manualmente. Scripts cross-machine: escribir bash-compatible
y probar SIEMPRE vía SSH real antes de confiar.
