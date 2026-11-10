#!/usr/bin/env python3
"""
Auto-Route Classifier para Victoria.
Clasifica la intención del usuario en: CONVERSATION | PLAN | CODE
Usa el modelo generalista (Using a Victoria) vía gateway local.
"""

import json
import os
import sys
import requests
from typing import Literal

# Configuración
GATEWAY_URL = os.getenv("VICTORIA_GATEWAY_URL", "http://127.0.0.1:8010/v1")
API_KEY = os.getenv("VICTORIA_API_KEY", "")  # Se inyecta desde opencode
MODEL_ID = "nvidia/Qwen3.6-35B-A3B-NVFP4-normal"  # Using a Victoria (thinking OFF)
TIMEOUT = 10  # segundos

# Prompt de clasificación few-shot
CLASSIFIER_PROMPT = """Eres un clasificador de intención para Victoria (IA principal).
Analiza el prompt del usuario y clasifica en UNA sola categoría:

CATEGORÍAS:
- CONVERSATION: chat, preguntas, análisis, visión, traducción, resumen, edits chicos (<30 líneas), explicaciones, "hola", "gracias", dudas
- PLAN: planificación, arquitectura, diseño de sistema, "cómo harías...", "diseña...", "arquitectura para...", "plan para...", "estrategia", trade-offs, decisiones de alto nivel, verificación de planes
- CODE: implementación sustancial, refactor multi-archivo, función compleja, bugfix profundo, script nuevo, feature completa, "implementa...", "escribe el código...", "refactoriza...", "arregla el bug...", "crea un script..."

EJEMPLOS:
Usuario: "hola victoria" → CONVERSATION
Usuario: "explícame cómo funciona el gateway" → CONVERSATION
Usuario: "traduce esto al inglés" → CONVERSATION
Usuario: "diseña la arquitectura para un sistema de colas" → PLAN
Usuario: "¿qué patrón usar para el router automático?" → PLAN
Usuario: "verifica mi plan de migración a PostgreSQL" → PLAN
Usuario: "implementa el router automático en Python" → CODE
Usuario: "refactoriza el módulo auth para usar JWT" → CODE
Usuario: "arregla el bug de memoria en el video server" → CODE
Usuario: "crea un script para backup de la DB" → CODE

REGLAS:
- Si hay ambigüedad entre PLAN y CODE: PLAN (planificar antes de implementar)
- Si hay ambigüedad entre CONVERSATION y PLAN: CONVERSATION (por defecto)
- Responde SOLO con la categoría: CONVERSATION | PLAN | CODE
- Sin explicaciones, sin formato, solo la palabra exacta."""

def classify(prompt: str) -> Literal["CONVERSATION", "PLAN", "CODE"]:
    """Clasifica la intención usando el gateway local."""
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_KEY}" if API_KEY else ""
    }
    
    payload = {
        "model": MODEL_ID,
        "messages": [
            {"role": "system", "content": CLASSIFIER_PROMPT},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 10,
        "temperature": 0.0,
        "stream": False
    }
    
    try:
        resp = requests.post(
            f"{GATEWAY_URL}/chat/completions",
            headers=headers,
            json=payload,
            timeout=TIMEOUT
        )
        resp.raise_for_status()
        data = resp.json()
        classification = data["choices"][0]["message"]["content"].strip().upper()
        
        # Validar respuesta
        valid = {"CONVERSATION", "PLAN", "CODE"}
        if classification not in valid:
            # Fallback conservador
            return "CONVERSATION"
        return classification
        
    except Exception as e:
        # Fallback silencioso: conversación (no delegar)
        print(f"[auto-route] Error clasificando: {e}", file=sys.stderr)
        return "CONVERSATION"


def main():
    if len(sys.argv) < 2:
        print("Uso: classifier.py \"prompt del usuario\"", file=sys.stderr)
        sys.exit(1)
    
    prompt = " ".join(sys.argv[1:])
    result = classify(prompt)
    print(result)


if __name__ == "__main__":
    main()