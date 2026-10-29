# Git — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `git version` → 2.43.0)
> **Docs oficiales**: https://git-scm.com/doc

## Repos del ecosistema

| Repo | Dónde | Particularidad |
|---|---|---|
| `/home/victoria/.git` | victoria (stack) | **whitelist-only** (docs+gateway+web/brand); NUNKA `git add` fuera de la whitelist; secrets/ en .gitignore |
| `~/armada-sync` | kalimete (HUB) | push a GitHub `warcold/armada-sync` cada 5 min (cron); deploy/collect DESTRUCTIVOS |
| `~/dev/apps/kalimete-ptt` | kalimete | proyecto PTT (commits v5.x) |
| `~/dev/wordpress/plugins/armada-suite` | kalimete | plugin WP (HEAD e2c86ed, remote vacío — local only) |
| `~/dev/victoria` | kalimete | monorepo Victoria app (overlay/server/web) |
| ComfyUI/LivePortrait/Sonic/Hunyuan3D | victoria | clones upstream (git pull para upgrades) |

## Patrones que usamos

- Commits con mensaje descriptivo + versión (ej. "v5.2: disciplina dura de voz...")
- `git log --oneline -1` para verificar el commit tras cada cambio
- `.gitignore` con secrets/ SIEMPRE antes del primer add
- Backups `.bkup-<fecha>-<motivo>` en vez de branches para configs vivas

## Gotchas descubiertos (lecciones)

- **NUNKA commitear secretos** — `verify` de armada-sync falla si encuentra `vllm-key-*` completas (excepción: la readonly db13… documentada). — (AGENTS.md §8)
- **`git pull` en clones de contenido puede traer breaking changes** — ComfyUI 0.39→0.42 exigió actualizar DOS deps propias (aimdo+kitchen) ANTES de reiniciar. Leer el diff de requirements siempre. — (CHANGELOG-comfyui 2026-10-26)
- **Repos con remote vacío**: el plugin armada-suite es local-only — no intentar push sin configurar remote primero.

## Regla de actualización

git del sistema: no tocar. Repos nuevos: .gitignore primero, whitelist si es
el repo del stack, y changelog si el repo es parte de un servicio.
