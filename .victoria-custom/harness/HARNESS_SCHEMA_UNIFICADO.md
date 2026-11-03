# HARNESS SCHEMA UNIFICADO (v1.0, 2026-10-29)
# Basado en el gold standard de ecco-suit.harness.json + análisis Ecco Suite
# TODOS los harness (Victoria + kalimete) DEBEN seguir este schema.
# Campos obligatorios marcados con ★, opcionales con ○.

{
  "harness": "string ★",                    // id único = nombre del agente (ej: "vLLM", "ecco-suit")
  "updated": "YYYY-MM-DD ★",                // fecha última actualización del harness
  "mode": "primary|subagent ★",             // modo en opencode
  "hidden": "boolean ★",                    // visible en @ autocomplete (owner quiere todos false)
  "agent_file": "string ★",                 // ruta al .md del agente (prompt)
  "scope": "string ★",                      // descripción breve del dominio
  "temperature": "number ★",                // sampling temp para este agente
  "top_p": "number ○",                      // solo si temp != 0.1

  // ===== ESTADO VIVO (fuente de verdad, NO docs estáticos) =====
  "vivo_YYYY_MM_DD": "string ★",            // auditoría LIVE con fecha: hallazgos reales, discrepancias corregidas, mediciones. Formato: "vivo_2026_10_29": "Auditoría LIVE: ..."
  "live_check": "string ★",                 // COMANDO EJECUTABLE ÚNICO para verificar estado real ANTES de actuar (ej: "curl -s https://suite.eccoqualita.com/api/health"). Debe ser rápido (<5s), binario up/down.
  "checks": ["string ★"],                   // ARRAY de comandos de verificación completos (health, docker ps, ssh, ufw, etc.). Se ejecutan en orden para validación profunda.

  // ===== UPSTREAM / VERSIONES =====
  "upstream": {
    "fuente": "string ★",                   // ÚNICA fuente de verdad upstream (ej: "github VincentEQ/EccoSuit (copia local ~/dev/..., solo lectura)"). Si no hay upstream externo: "ninguno (servicio propietario/local)".
    "nota": "string ○",                     // regla operativa (ej: "LIVE manda; lo no verificado se marca pendiente, nunca se inventa")
    "version_servida_live": "string ○",     // comando para obtener version live (ej: "docker inspect ... + docker exec ... vllm.__version__")
    "donde_mirar": ["string ○"],            // URLs a vigilar (releases, security, model card)
    "frecuencia": "string ○",               // "trimestral" | "ante incidente" | "mensual"
    "politica": "string ○",                 // "upgrades = Plan + owner" etc.
    "como_reportar": "string ○"             // "entrada en CHANGELOG-X.md + aviso a Victoria en Task"
  },

  // ===== SERVICIOS / INFRAESTRUCTURA =====
  "servicios": [                            // array de objetos servicio
    {
      "name": "string ★",
      "puerto": "number ○",
      "codigo": "string ○",                 // path al script/servicio
      "red": "string ○",
      "via": "string ○",
      "target": "string ○",
      "label": "string ○",
      "version": "string ○",
      "flags_live": "string ○",
      "imagen": "string ○",
      "restart": "string ○"
    }
  ],

  // ===== SCRIPTS HOST =====
  "scripts_host": ["string ○"],             // paths a scripts de administración

  // ===== DOCUMENTACIÓN =====
  "docs": ["string ★"],                     // docs LOCALES del proyecto/servicio (paths absolutos o file://)
  "docs_oficiales": {                       // fuentes upstream versionadas
    "regla": "string ★",
    "fuentes": [
      {
        "nombre": "string ★",
        "url": "string ★",
        "contenido_clave": "string ★",
        "verificada": "YYYY-MM-DD ★"
      }
    ]
  },

  // ===== CHANGELOG =====
  "changelog": [                            // array de objetos con fecha/cambio (NO solo paths)
    {
      "fecha": "YYYY-MM-DD ★",
      "cambio": "string ★"
    }
  ],
  "changelogs": ["string ○"],               // paths a archivos CHANGELOG (general + servicio)

  // ===== REGLAS NO-TOUCH / RECUPERACIÓN =====
  "no_touch": ["string ★"],                 // reglas sagradas (nunca romper)
  "recovery": "string ★",                   // procedimiento de recuperación (texto o array)

  // ===== MEDICIÓN / OBSERVABILIDAD =====
  "medicion_live": {                        // opcional, para auditorías puntuales
    "fecha": "ISO8601",
    "nota": "string",
    "versiones": {}
  },

  // ===== DELEGACIÓN / PERMISOS =====
  "delegacion": {                           // para primaries: cómo delegar a este subagente
    "cuando_usar": "string ★",              // criterio exacto de invocación
    "pre_check": "string ★",                // comando live_check ANTES de delegar (obligatorio)
    "post_check": "string ○"                // verificación tras delegación
  }
}

# REGLAS DE USO DEL SCHEMA
# 1. live_check DEBE ser ejecutable y retornar 0/1 o up/down en <5s. Es el gate ANTES de cualquier Task.
# 2. vivo_YYYY_MM_DD se actualiza CADA vez que se hace una auditoría live real (no cada commit).
# 3. upstream.fuente es la ÚNICA fuente; si hay discrepancia live vs upstream -> gana LIVE, se reporta.
# 4. checks[] son para validación PROFUNDA (post-deploy, post-cambio); live_check es para gate rápido.
# 4. docs[] = locales (paths absolutos); docs_oficiales.fuentes = upstream versionados con fecha verificada.
# 5. changelog[] = objetos estructurados; changelogs[] = paths a archivos markdown.
# 6. temperature: 0.1 para infra/operacionales, 0.6+top_p 0.95 para creativos (coding/orquestación).
# 7. El harness ES el contrato. El .md del agente es el prompt operativo que REFERENCIA el harness.
# 8. Al delegar con Task: LEER harness del subagente -> EJECUTAR live_check -> si up, delegar; si down, NO delegar, reportar.