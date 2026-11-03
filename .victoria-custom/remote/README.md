# Victoria Armada — Remote Connect Guide

Este es el guia publico para conectar modelos remotos al servidor de Victoria Armada.

## Acceso

- **Internet (HTTPS)**: `https://victoria.armada.do/v1`
- **LAN**: `http://victoria.local:8010/v1`

## Modelo

- **HuggingFace**: `nvidia/Qwen3.6-35B-A3B-NVFP4`
- **Tipo**: MoE, 35B params, 3B activos, NVFP4 quant
- **VLM nativo**: acepta texto, imagen y video
- **Contexto**: 220K tokens (límite del gateway `MAX_PROMPT_TOKENS=220000`, igual para todos los roles)
- **Output max**: 32K tokens

## Aliases

| Alias | Reasoning | Uso |
|---|---|---|
| `nvidia/Qwen3.6-35B-A3B-NVFP4-normal` | OFF | Coding rapido (default) |
| `nvidia/Qwen3.6-35B-A3B-NVFP4` | ON | Tareas complejas que requieren pensar |

## Credenciales para remotos

Para usar inferencia necesitas una key temporal del admin. Para leer la guia de configuracion, usa la key readonly:

```
API_KEY = vllm-key-db13590a2a256457edde74e3e116b14d181ec01fee533f62225547f7251c7aa7
```

**La key readonly SOLO permite**: `GET /health` y `GET /v1/config-guide`. NO puede inferir text.

## Config minima para clientes "coder" (amigos)

Para amigos/conocidos que usen una key `coder`, existe un template minimo:
`opencode-coder-minimal.jsonc` (en este directorio). Lleva SOLO provider + baseURL
+ apiKey + model id. Los limites (prompt 220K, output 32K, rate 120/min) los impone
el gateway — el cliente no puede sobrepasarlos aunque no los declare. El amigo solo
pone su URL y su key coder personal (que pide al admin en `http://victoria.local:8010/admin`).

## Endpoints Publicos

- `GET /health` → Estado del servicio
- `GET /v1/config-guide` → Guia completa de configuracion (sin secrets)
- `GET /models` → Modelo servido

## Servicios Disponibles

| Servicio | Puertos | Documentacion |
|---|---|---|
| vLLM + Gateway | :8000, :8010 | `agents/vllm-stack-ops.md` |
| OpenClaw Sandbox | inference.local | `agents/nemoclaw-sandbox-ops.md` |
| Voice Server (TTS/STT) | :18810 | `agents/nemoclaw-sandbox-ops.md` |
| Video Server | :18811 | `agents/nemoclaw-sandbox-ops.md` |
| ComfyUI | :8188 | `agents/comfyui-ops.md` |


## Servicio de Voz (TTS/STT)

- **Puerto**: 18810 (solo LAN)
- **Solo accesible desde**: `127.0.0.1` (localhost) o `10.x.x.x` (red domestica)
- **NO accesible desde Internet** (bloqueado por IPv6 DROP + IP filter)
- **Modelo**: XTTS v2 (TTS) + Whisper small (STT)

### Credenciales para voz
Necesitas una API key de rol `admin` (alfredo/victoria):
  - `vllm-key-5d4377...` (alfredo)
  - `vllm-key-811...` (victoria)

### Endpoints de Voz
| Endpoint | Método | Uso | Respuesta |
|---|---|---|---|
| `/voice/config-guide` | GET | Guia automatica del servicio | JSON con todos los datos |
| `/health` | GET | Verificar servicio | JSON con estado |
| `/tts` | POST | Texto a voz (XTTS v2) | WAV binario (audio/wav) |
| `/stt` | POST | Audio a texto (Whisper) | JSON con transcripcion |

### Comandos de prueva (desde la LAN)
```bash
# Config guide
curl -s -H "Authorization: Bearer vllm-key-5d4..." http://victoria.local:18810/voice/config-guide

# Health check
curl -s -H "Authorization: Bearer vllm-key-5d4..." http://victoria.local:18810/health

# TTS prueba
curl -s -X POST -H "Authorization: Bearer vllm-key-5d4..."   -H "Content-Type: application/json"   -d '{"text":"Hola, como estas","voice":"victoria","language":"es"}'   http://victoria.local:18810/tts > output.wav

# STT prueba (necesitas un archivo WAV)
curl -s -X POST -H "Authorization: Bearer vllm-key-5d4..."   http://victoria.local:18810/stt --data-binary @audio.wav
```

## Comandos para Probar

```bash
# Health check
curl -s https://victoria.armada.do/health

# Config guide
curl -s -H "Authorization: Bearer $API_KEY" https://victoria.armada.do/v1/config-guide

# Chat (con key coder temporal)
curl -s -H "Authorization: Bearer $YOUR_CODER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"nvidia/Qwen3.6-35B-A3B-NVFP4-normal","messages":[{"role":"user","content":"test"}],"max_tokens":10}' \
  https://victoria.armada.do/v1/chat/completions
```
