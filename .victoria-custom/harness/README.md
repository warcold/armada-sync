# Harness Victoria — victoria.local (2026-10-01)

> 1 sola Victoria principal en Tab (morada) + 10 subagentes de nombre simple, TODOS visibles en el autocomplete `@` (decisión del owner 2026-10-01: salen al escribir `@`).

## Estructura

- `victoria.harness.json` — manifiesto central (principal + 10 subagentes @-visibles + changelogs + docs + reglas).
- `<nombre>.harness.json` — harness completo de cada dedicado, basado en su documentación:
  - `vllm.harness.json` → vLLM :8000 + gateway :8010 (inferencia, llaves, panel /admin)
  - `openclaw.harness.json` → sandbox + dashboard :18789 + voz :18810 + video :18811 + whois :18830 + admin :18840 + wrappers web-nav :18820
  - `comfyui.harness.json` → ComfyUI :8188 + n8n :5678
  - `liveportrait.harness.json` → LivePortrait :8180 WebUI ES (servicio; pipeline = Sonic)
  - `sonic.harness.json` → Sonic :18850 + podcast + reels (changelog propio `CHANGELOG-sonic.md`)
  - `rss-system.harness.json` → blogwatcher + 15 feeds
  - `meta-business.harness.json` → IG + Discord + WhatsApp + daily-report
  - `weather.harness.json` → clima + geocode + POIs
  - `cloudflare.harness.json` → túnel + nginx + SSH/warcold + RDP
  - `gpu.harness.json` → guardián + árbitro + térmica + VRAM

## Reglas

1. Solo hay 1 principal visible: `Victoria` (`mode: primary`, `color: #8B5CF6`, `default_agent: Victoria` — exacto, case-sensitive).
2. Los 10 dedicados son visibles en `@` (`hidden: false`, desde 2026-10-01 por decisión del owner): se usan seleccionándolos del autocomplete `@`, por `Task` directo o `@Nombre` escrito (`vLLM`, `OpenClaw`, `Comfyui`, `Sonic`, `RSS System`, `Meta Business`, `Weather`, `CloudFlare`, `Liveportrait`, `Gpu`). Tab (lista de primaries) sigue mostrando SOLO Plan/Build/Victoria — los subagentes nunca salen en Tab, eso es opencode. NUNCA borrar (`openclaw.md` y `victoria.md` No-Touch). Sin symlink `agent→agents` (duplicaba).
3. Cada subagente tiene: su `.md` en minúsculas en `~/.config/opencode/agents/` + su changelog en `~/.victoria-custom/changelogs/` + su harness aquí.
4. Cada cambio toca 3 lugares: doc + harness JSON + changelog (servicio + `/home/victoria/CHANGELOG.md`).
5. Fuente verdad docs: `~/AGENTS.md` + `agents/victoria.md` + `AGENTS-summary.md`. El harness conecta, no duplica.

## Verificación rápida

```bash
# JSONs válidos
python3 -c "import json,glob; [json.load(open(f)) for f in glob.glob('/home/victoria/.victoria-custom/harness/*.json')]; print('harness JSON OK')"
# Agentes resueltos (nombres exactos + modos)
opencode agent list 2>/dev/null | grep -E "^(Victoria|vLLM|OpenClaw|Comfyui|Sonic|RSS|Meta|Weather|CloudFlare|Liveportrait|Gpu)"
# Frontmatters (1 primary en Tab + 10 subagent visibles en @)
head -n 6 ~/.config/opencode/agents/*.md
# Changelogs existen
ls -lh ~/.victoria-custom/changelogs/
```
