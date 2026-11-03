---
name: webanalyze
description: "Analiza el stack tecnológico y seguridad de un sitio web (CMS, frameworks, plugins WordPress, headers, SSL/TLS, CDNs) con auditoría pasiva score 0-100. Usar cuando pregunten qué tecnología usa una web o para auditoría de seguridad pasiva."
command: webanalyze
---

# webanalyze - Web Page Tech Stack Analysis + Security Audit

## Cuándo usar
Usa esta skill cuando el usuario pregunta sobre:
- Versión de CMS/framework/PHP de un sitio web
- Plugins de WordPress instalados en un sitio
- Tecnología detrás de una página web
- Headers HTTP, security headers, SSL/TLS
- **Auditoría de seguridad pasiva de un sitio** (score 0-100, archivos expuestos, DNS, TLS)
- Detección de CDNs, analytics, JS frameworks
- Metadata técnica de un sitio

**NO confundir con la skill `web`** (navegación autónoma). `webanalyze` es solo análisis técnico estático (recon pasivo, ~15 requests máx).

## Comando
```bash
webanalyze <url|domain> [--json] [--full] [--no-sec] [--timeout=N]
```

### Parámetros
- `<url|domain>` - URL o dominio a analizar (se auto-completa con https://)
- `--json` - Output en formato JSON (ideal para parsing)
- `--full` - Fingerprinting profundo de JS sources y frameworks
- `--no-sec` - Omite el módulo de seguridad (modo rápido; PHP/versiones siguen)
- `--timeout=N` - Timeout en segundos (default 15)

### Ejemplos
```bash
# Análisis completo con auditoría de seguridad (default)
webanalyze alfredo.pro

# JSON para parsing
webanalyze alfredo.pro --json

# Solo tech stack, sin auditoría de seguridad
webanalyze alfredo.pro --no-sec

# Fingerprinting profundo
webanalyze techcrunch.com --json --full
```

## Módulos (2026-10-22)

### 1. Versiones PHP/CMS (vectores pasivos)
- **PHP**: header `X-Powered-By` (ej. `PHP/8.2.1`); si ausente → "no expuesto (hardened)"
- **WordPress**: meta generator (`WordPress 7.1.3`) → vector A; `/feed/` generator (`wordpress.org/?v=X.Y.Z`) → vector B (más confiable); `readme.html` ("Version X.Y") → vector C; `/wp-json/` namespaces → vector D (detecta WordPress aunque el homepage esté bloqueado por WAF)
- **Otros CMS**: meta generator genérico (Joomla, Drupal, etc.)

### 2. Plugins de WordPress (vía /wp-json/ namespaces)
Lista hasta 10 plugins detectados por sus namespaces REST (contact-form-7, elementor, jetpack, woocommerce, etc.) + description del sitio. Si wp-json responde → "expuesto" (nota: expone superficie de ataque; es común pero conviene saberlo).

### 3. Auditoría de seguridad pasiva (score 0-100)
| Componente | Puntos |
|---|---|
| HSTS | +20 |
| Content-Security-Policy | +20 |
| X-Frame-Options | +15 |
| X-Content-Type-Options (nosniff) | +15 |
| Referrer-Policy | +10 |
| Permissions-Policy | +10 |
| Cookies (Secure+HttpOnly+SameSite) | +10 (parcial +5, sin cookies +10) |

**Grades**: ≥80 BUENO · 50-79 MEJORABLE · <50 DÉBIL

Incluye además:
- **Archivos expuestos**: 12 probes (`.env`, `.git/config`, `phpinfo.php`, `backup.zip`, etc.) con baseline anti-soft-404 + verificación de contenido. 403 = protegido (defensa OK); 200 con contenido real = EXPUESTO (riesgo)
- **Paneles admin**: `/wp-admin/`, `/administrator/` (informativo; 30x a login = normal)
- **TLS**: protocolo negociado + probes TLS 1.0/1.1 (nota: el OpenSSL 3.x del sandbox no soporta legacy → "untestable", NO interpretar como seguro) + días restantes del cert
- **DNS** (vía admin-cli → host): SPF, DMARC, DNSSEC
- **Cookies**: flags Secure/HttpOnly/SameSite por cookie
- **Risk flags**: versiones viejas (WP <6.0, PHP <8.0), archivos expuestos, directory listing

## Output (JSON) — claves nuevas 2026-10-22
```json
{
  "php": { "version": "8.2.1", "display": "PHP/8.2.1", "powered_by": "..." },
  "plugins": ["contact-form-7", "elementor", "..."],
  "security_score": 45,
  "score_grade": "DEBIL",
  "exposed_files": [ { "path": "/composer.json", "verdict": "EXPOSED", "detail": "..." } ],
  "dns_security": { "source": "admin-cli (host-admin bridge)", "spf": "yes", "dmarc": "yes", "dnssec": "no" },
  "tls_protocols": { "negotiated": "TLSv1.3", "tls1_0": "...", "cert_days_left": 61 },
  "risk_flags": ["..."],
  "soft404_note": "...", "waf_note": "..."
}
```

## Interpretación (lecciones E2E 2026-10-22)
- **alfredo.pro**: score 10/100 DEBIL (sin security headers), pero archivos sensibles bien bloqueados (403 en .env/.git/etc) y PHP hardened. wp-json expuesto con ~10 plugins. Cert Let's Encrypt.
- **wordpress.org**: score 45/100, `/composer.json` REALMENTE expuesto (200 con contenido — verdadero positivo verificado).
- **github.com**: score 85/100 BUENO (referencia de headers fuertes; cookies casi perfectas).
- **TLS 1.0/1.1 "untestable"**: el cliente OpenSSL del sandbox no soporta legacy — NO es "protocolo seguro", es "no medible desde aquí".
- **WAF/challenge** (ej. "One moment, please..."): el wrapper lo detecta y marca `waf_note` — resultados parciales, NO falsos positivos. Reintentar más tarde puede dar la página real (el challenge es temporal por IP).
- **Soft-404**: sitios que responden 200 a rutas random → `soft404_note` + la detección de archivos se vuelve indeterminada (el wrapper lo declara).

## Limitaciones
- Solo análisis pasivo (recon): ~15 requests HTTP máx, sin exploits, sin fuerza bruta
- No ejecuta JS (para framework detection profundo, usar `web-navigate` para render completo)
- TLS legacy (1.0/1.1) no medible desde el sandbox (OpenSSL 3.x sin soporte)
- Sitios con WAF agresivo pueden challengear la IP de egreso tras mucho scanning (espaciar análisis repetidos del mismo dominio)

## Fallback
Si `webanalyze` no está disponible en el sandbox (rebuild), los comandos base son:
```bash
# Headers + server version
curl -sI https://example.com | head -10

# CMS detection (WordPress, Shopify, etc.)
curl -s https://example.com | grep -iE 'wp-content|myshopify|Joomla|Drupal'

# Version de WordPress via feed
curl -s https://example.com/feed/ | grep -oE 'wordpress\.org/\?v=[0-9.]+'

# Plugins via wp-json
curl -s https://example.com/wp-json/ | grep -oE '"[^"]+/v[0-9]+"' | head -20

# Meta title/description
curl -s https://example.com | grep -oi '<title>[^<]*</title>'

# SSL cert info
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -subject -issuer -dates

# DNS (SPF/DMARC) via admin-cli
admin-cli exec dig example.com TXT +short
```
