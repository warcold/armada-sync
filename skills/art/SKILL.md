---
name: art
description: Generar imágenes con los modelos de arte de Victoria (Z-Image-Turbo, FLUX-schnell, SD15-realistic) vía el gateway de Alfredo Pro. Usa esta skill SIEMPRE que el usuario pida generar/crear/dibujar una imagen, foto, thumbnail, ilustración, concepto visual, post, banner, o "hazme una imagen de...". El pipeline es async (encolar → poll → descargar) y la imagen se guarda donde el usuario pida (escritorio, proyecto, etc.).
---

# Art — generación de imágenes vía el gateway de Victoria

Los modelos de imagen viven en el DGX Spark (victoria.local / 10.0.0.5) y se
consumen por la art API del gateway `:8010` con la llave `kalimete` (rol coder
+ capacidades llm/art — ya configurada).

## Endpoint y llave

- **En LAN**: `http://10.0.0.5:8010` (o `http://victoria.local:8010`)
- **Fuera de LAN**: `https://victoria.armada.do` (túnel Cloudflare)
- **Llave**: la misma del provider `vllm` en `~/.config/opencode/opencode.jsonc`
  (campo `apiKey`). Extraerla sin mostrarla en el chat:
  ```sh
  KEY=$(python3 -c "import re; s=open('$HOME/.config/opencode/opencode.jsonc').read(); print(re.search(r'\"apiKey\"\s*:\s*\"([^\"]+)\"', s).group(1))")
  ```

## Flujo (async: 202 → poll → download)

```sh
BASE="http://10.0.0.5:8010"
# 1) Encolar (devuelve job_id)
JOB=$(curl -s -X POST "$BASE/v1/images" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"template":"z-image-turbo","prompt":"TU PROMPT AQUI","width":1024,"height":1024}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")
# 2) Poll cada 5s hasta status done (tarda 15s-3min)
curl -s -H "Authorization: Bearer $KEY" "$BASE/v1/jobs/$JOB"
#    -> {"status":"done","files":["art-zimage_00001_.png"],"download":["/v1/art-files/art-zimage_00001_.png"]}
# 3) Descargar donde el usuario pida
curl -s -H "Authorization: Bearer $KEY" "$BASE/v1/art-files/art-zimage_00001_.png" -o ~/Desktop/imagen.png
```

## Templates

| Template | Cuándo | Notas |
|---|---|---|
| `z-image-turbo` | Default: rápido (8 steps, ~15-60s), versátil, es/en | 1024x1024 nativo, rango 640-1344 |
| `flux-schnell` | Calidad alta FLUX (4 steps, ~30-90s) | 1024x1024 nativo, rango 768-1344 |
| `sd15-realistic` | Fotorrealismo clásico/retratos (30 steps, lento) | 512x768 nativo, NO pasar de 768 |

Parámetros: `prompt` (inglés = mejor calidad), `negative_prompt` (solo aplica
en sd15), `seed` (aleatorio si no viene), `width`/`height`.

## Cola y reintentos (GPU compartida — NO martillar)

La GPU del DGX la comparten la inferencia LLM y los renders. Si el POST
responde **429** (`art_busy` / `gpu_busy` / `art_rate_limited`): NO es error —
es la cola. Lee el header `Retry-After`, espera ese tiempo y reintenta
(máx ~10 intentos). Nunca lances varios jobs en paralelo: UNO a la vez.

## Reglas

1. Escribe prompts ricos: sujeto + estilo + ambiente + iluminación.
2. Guarda la imagen donde el usuario pida (`~/Desktop/`, carpeta del
   proyecto) y dile la ruta absoluta al terminar.
3. `503 comfyui_offline` → avisa: "ComfyUI está apagado en Victoria, reintenta en un rato" (se enciende solo).
4. Nada de contenido sexual explícito ni personas reales sin consentimiento.
5. El catálogo vivo: `GET $BASE/v1/catalog` (con Bearer) lista templates reales.

