---
name: pdf
description: "Genera documentos PDF (currículums, cartas, reportes, CVs) LOCALMENTE en el sandbox con fpdf2 — sin servicios externos ni POSTs a localhost."
command: pdf
---

# Skill `pdf` — generar PDFs localmente (fpdf2)

## REGLA CRÍTICA (lección 2026-10-16, CV de José Armada)

NUNCA intentes `POST http://localhost:PUERTO/*.pdf` ni llames a servicios web
locales para crear PDFs — **NO EXISTEN** en el sandbox y la policy de egress los
DENIEGA (SSRF hardening). El PDF se genera LOCALMENTE con `fpdf2` (ya instalado;
si faltara: `pip install fpdf2` funciona, PyPI está permitido).

## Cómo generar (patrón verificado)

```python
# /tmp/mi-doc.py — correr con: python3 /tmp/mi-doc.py
from fpdf import FPDF

pdf = FPDF(format="letter")          # o format="A4"
pdf.set_auto_page_break(auto=True, margin=20)
pdf.add_page()

# Fuente unicode para acentos/ñ (core fonts NO soportan UTF-8 completo)
pdf.add_font("DejaVu", "", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
pdf.add_font("DejaVu", "B", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")

pdf.set_font("DejaVu", "B", 18)
pdf.cell(0, 10, "Título del documento", new_x="LMARGIN", new_y="NEXT")
pdf.set_font("DejaVu", "", 11)
pdf.multi_cell(0, 6, "Párrafo con acentos: José, María, ñ, áéíóú.")

pdf.output("/sandbox/.openclaw/media/outbound/documento.pdf")
```

Luego envíalo igual que una imagen:

```bash
openclaw message send --channel whatsapp --target <dest> \
  --media /sandbox/.openclaw/media/outbound/documento.pdf --json
```

## Reglas

- **Ruta de salida (EXACTA, lección 2026-11-02 — 3 envíos rechazados)**: SIEMPRE
  la ruta COMPLETA `/sandbox/.openclaw/media/outbound/<archivo>.pdf` (managed root
  real — es la que usa art-gen y la ÚNICA que el runtime acepta). **NUNCA**
  `/sandbox/.openclaw/workspace/media/outbound/` (el runtime la rechaza con
  `LocalMediaAccessError: path-not-allowed` — probado 2026-10-17 y 2026-10-22 con
  el CV de José). El script puede vivir en /tmp, el PDF NO.
- **Acentos/ñ**: usa la fuente DejaVu (está en el sandbox) — las core fonts
  (helvetica/arial) corrompen UTF-8.
- **Confirma el envío**: solo hay éxito si el JSON trae `"messageId"`. Sin
  messageId NO digas "listo".
- **CIERRE DE TOCA**: tras el send exitoso, TERMINA el turno (sin texto extra —
  cada texto extra llega como OTRO mensaje al chat).
- CVs: pide datos al usuario si faltan; estructura clásica = nombre grande +
  contacto + experiencia (empresa, cargo, fechas, bullets) + educación +
  habilidades. No inventes experiencia laboral.
