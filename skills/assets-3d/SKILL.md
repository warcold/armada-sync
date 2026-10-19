---
name: assets-3d
description: Generar assets 3D (image→3D GLB con textura) y animaciones de persona (foto→mp4) vía los servicios de victoria (Hunyuan3D-2 :18860 y lp-animate :18861). Usar SIEMPRE que el usuario pida "convierte esta imagen en 3D", "un modelo 3D de esto", "asset 3D para el juego", "GLB", "anima esta foto", "video del personaje hablando/moviéndose", o cuando un pipeline de juego necesite meshes importables en Godot/Blender. La imagen puede venir de la skill art (concept art) o ser un archivo local.
---

# Assets-3D — image→3D (GLB) y animación (foto→mp4) vía los servicios de Victoria

Los modelos 3D y el motor de animación viven en el DGX Spark
(victoria.local / 10.0.0.5) y se consumen por HTTP con la llave `kalimete`
(caps `llm/art/tts/whisper` — la cap `art` eleva a services en sense_auth,
verificado E2E 2026-10-19). **Sin SSH, sin tocar la máquina de victoria**.

## Llave (extraer sin mostrarla)

```sh
KEY=$(python3 -c "import re; s=open('$HOME/.config/opencode/opencode.jsonc').read(); print(re.search(r'\"apiKey\"\s*:\s*\"([^\"]+)\"', s).group(1))")
```

## 1. Hunyuan3D-2 — image→3D GLB (:18860)

**Entrada ideal**: UN objeto aislado, centrado, fondo liso (el server hace
rembg pero un fondo limpio rinde mejor). El concept art de la skill `art`
con prompt "single object, centered, plain background" es perfecto.

```sh
# a) Preparar el body (NUNCA pasar el b64 por argv — muy largo; leer archivo directo)
python3 - <<'EOF'
import base64, json
b64 = base64.b64encode(open("concepto.png", "rb").read()).decode()
json.dump({"image_b64": b64, "face_count": 20000}, open("req3d.json", "w"))
EOF

# b) Generar (single-flight GPU, ~45-55s)
curl -s -m 300 -X POST http://10.0.0.5:18860/generate \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  --data-binary @req3d.json
# -> {"ok": true, "glb_path": "...hunyuan-<ts>.glb", "seconds_taken": 46.4,
#     "verts": 284458, "bytes": 3635724}

# c) Descargar el GLB (basename del glb_path)
curl -s -m 60 -H "Authorization: Bearer $KEY" \
  "http://10.0.0.5:18860/file/hunyuan-<ts>.glb" -o asset.glb
file asset.glb   # -> glTF binary model, version 2
```

**Parámetros**: `face_count` (default 40000 — para assets de juego usa
**10000-20000**, el target 10-20k faces del pipeline), `texture` (default true,
GLB con textura horneada), `steps` (default 5, turbo), `seed` (default 2025).

**Errores = cola, no fallo**:
- `503 {"error":"busy..."}` → hay otro 3D corriendo (single-flight): espera 30-60s y reintenta.
- `429` con `retry_after_s` → GPU ocupada o ≥80°C (árbitro): espera lo que dice y reintenta (máx ~10).
- Health: `curl -s http://10.0.0.5:18860/health` (abierto, sin key).

**En Godot**: arrastrar el .glb al proyecto → importa como escena/mesh
nativo. Para LOD: `face_count` bajo + decimate en Blender si hace falta.

## 2. lp-animate — foto→mp4 animado (:18861)

Animate un retrato (foto de cara) con un preset de movimiento o un video
guía → mp4 h264 ~17s. Útil para intros/cutscenes con personaje.

```sh
# Presets disponibles (con auth)
curl -s -H "Authorization: Bearer $KEY" http://10.0.0.5:18861/presets
# -> {ok, presets:[{n,name,bytes}]}  (01-saludo, 02-habla, 03-energia)

# Animar con preset
python3 - <<'EOF'
import base64, json
foto = base64.b64encode(open("personaje.jpg", "rb").read()).decode()
json.dump({"foto_b64": foto, "preset": "1", "out_name": "intro-personaje.mp4"},
          open("reqanim.json", "w"))
EOF
curl -s -m 700 -X POST http://10.0.0.5:18861/animate \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  --data-binary @reqanim.json
# -> {ok, out, seconds}  |  descargar: GET /file/intro-personaje.mp4 (con auth)
```

También acepta `guia_b64` (video guía mp4 en b64) en vez de `preset`.
Health: `curl -s http://10.0.0.5:18861/health` (abierto). Single-flight: 503 busy → esperar.

**Para video con LABIOS de verdad** (personaje hablando un guion): eso es
Sonic/Estudio Podcast — usar el tab `victoria.local/liveportrait/` en browser
o pedírselo a Victoria (skill `voice-video`, constraint de rutas locales).

## Pipeline recomendado para juegos (game-studio)

```
GDD → skill art (concept art del objeto, "single object, plain background")
    → esta skill (image→3D GLB, face_count 10-20k)
    → Godot (drag & drop del .glb)
    → QA: screenshot runtime → adjuntar al chat (VLM de victoria lo describe)
```

## Reglas (convivencia GPU — NO explotar la granja)

1. **UN job a la vez** — nunca lanzar 3D + arte + animación en paralelo.
2. 429/503 = cola: leer `retry_after_s`/`Retry-After`, esperar, reintentar.
3. Entre ráfagas de muchos assets: respiros de segundos — el GB10 es memoria
   unificada y victoria se protege del freeze con estas colas; respétalas.
4. Host-admin de victoria (:18840) NO acepta esta llave (401 por diseño):
   aquí SOLO se consumen recursos generadores, jamás se opera la máquina.
5. Imágenes de entrada: contenido propio o generado — nada sexual explícito
   ni personas reales sin consentimiento.
