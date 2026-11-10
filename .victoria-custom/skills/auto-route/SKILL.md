# Skill: auto-route

Clasificador automático de intención para Victoria. Analiza el prompt del usuario y determina la ruta óptima: **CONVERSATION** (Using a Victoria), **PLAN** (@Thinker), **CODE** (@Coder).

## Uso

```bash
# Desde terminal (testing)
python3 ~/.victoria-custom/skills/auto-route/classifier.py "prompt del usuario"

# Desde Victoria (opencode) - skill tool
skill auto-route --prompt "implementa el router automático"
```

## Variables de entorno requeridas

| Variable | Descripción | Default |
|---|---|---|
| `VICTORIA_GATEWAY_URL` | URL del gateway (sin /v1) | `http://127.0.0.1:8010/v1` |
| `VICTORIA_API_KEY` | API key con rol `coder` o `admin` | (inyectada por opencode) |

## Salida

Una sola línea: `CONVERSATION` | `PLAN` | `CODE`

## Integración en Victoria (doctrina)

Victoria invoca esta skill **al inicio de cada turno** (antes de responder) para decidir:

```
Prompt usuario → auto-route → 
  CONVERSATION → Respondo directo (Using a Victoria)
  PLAN → Task → @Thinker (razonamiento profundo, thinking ON)
  CODE → Task → @Coder (implementación, modelo Coding con Victoria)
```

## Umbrales de confianza (futuro)

Actualmente es determinístico (temperature=0). Si se añade scoring:
- `confidence > 0.85` → auto-delegar
- `0.6-0.85` → preguntar al usuario
- `< 0.6` → CONVERSATION (seguro)

## Testing

```bash
# Conversación
python3 classifier.py "hola victoria"                    # → CONVERSATION
python3 classifier.py "explícame el gateway"             # → CONVERSATION

# Plan
python3 classifier.py "diseña la arquitectura del router" # → PLAN
python3 classifier.py "verifica mi plan de migración"     # → PLAN

# Código
python3 classifier.py "implementa el router en Python"    # → CODE
python3 classifier.py "refactoriza el módulo auth"        # → CODE
```