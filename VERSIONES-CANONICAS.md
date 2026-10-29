# MATRIZ DE VERSIONES CANÓNICAS — Ecosistema Armada (2026-10-29)

> Fuente única de verdad para versiones de todos los componentes del ecosistema.
> Actualizar esta matriz cada vez que cambie una versión en PROD/PREPROD/DEV.
> Ubicación: `/home/victoria/.victoria-custom/VERSIONES-CANONICAS.md` + espejo en kalimete `~/armada-sync/VERSIONES-CANONICAS.md`

---

## 📋 Resumen Ejecutivo

| Capa | Versión Canónica | Entornos Aplicados | Estado |
|------|------------------|-------------------|--------|
| **PHP** | **8.4.x** (PROD: 8.4.27/8.5.11) | ERP Dev: 8.4.27 ✅ | WordPress: 8.3.x (pendiente imagen oficial) |
| **Python** | **3.13.x LTS** (3.13.18) | Victoria: 3.13.18 ✅ | kalimete: 3.13.5 ✅ |
| **Node.js** | **v22.x LTS** (v22.23.4) | kalimete: v22.23.4 ✅ | Victoria: v22.22.1 ✅ |
| **Go** | **1.26.5** | Hosts: 1.26.5 ✅ | — |
| **Rust** | **1.95.0** | Hosts: 1.95.0 ✅ | — |
| **MariaDB** | **10.11.18** | WP Sites: 10.11.18 ✅ | — |
| **MySQL** | **8.0.45** | ERP: 8.0.45 ✅ | — |
| **PostgreSQL** | **17.11** | Ecco: 17.11 ✅ | — |
| **Redis** | **7.4.9** | Hosts: 7.4.9 ✅ | — |
| **Nginx** | **1.30.1** (host) / 1.25-alpine (ERP) | Host: 1.30.1 ✅ | ERP: 1.25-alpine (intencional) |
| **WordPress** | **7.1.3/7.1.4** | PROD: 7.1.4 ✅ | PREPROD: 7.1.3 ✅ |
| **WP Base Image** | `wordpress:8.4-php8.4-apache` (pendiente) | Actual: `wordpress:7.1.3-php8.3-apache` | Pendiente imagen oficial PHP 8.4 |

---

## 🏷️ Versiones por Entorno (Detalle)

### PRODUCCIÓN (cPanel / VPS)
| Sitio | PHP | WP | Plugin | DB | Notas |
|-------|-----|-----|--------|-----|-------|
| **micaserogou.com** | **8.4.27** | 7.1.4 | 5.5.10 | MariaDB 10.11 | PROD real |
| **magantech.com.do** | **8.5.11** | 7.1.3 | 5.4.0 | MariaDB 10.11 | PROD real |
| **eccoqualita.com** | — | — | — | PostgreSQL 17.11 | VPS Ecco |
| **erpipos.armada.do** | 8.x (cPanel) | — | — | MySQL 8.0 | ERP PROD |

### PREPRODUCCIÓN (Docker en kalimete)
| Stack | PHP | WP | Plugin | DB | Puerto | Estado |
|-------|-----|-----|--------|-----|--------|--------|
| **micaserogou PREPROD** | **8.3.35** → **8.4.x** (pendiente) | 7.1.3 | 5.7.0 | MariaDB 10.11 | :8094 | Compose actualizado |
| **magantech PREPROD** | **8.3.35** → **8.4.x** (pendiente) | 7.1.3 | 5.7.0 | MariaDB 10.11 | :8093 | Compose actualizado |
| **ERP Dev** | **8.4.27** ✅ | — | — | MySQL 8.0 | :8100 | **ACTUALIZADO** |
| **wordpress-dev (lab)** | 8.3.20 → **8.4.x** (pendiente) | 7.1.3 | 5.8.0 | MariaDB 10.11 | :8091 | Pendiente imagen |
| **zionv-crm** | 8.3.20 → **8.4.x** (pendiente) | 7.1.3 | 1.56.3 | MariaDB 10.11 | :8092 | Compose actualizado |

### DESARROLLO (Hosts)
| Host | Python | Node.js | Go | Rust | PHP (host) |
|------|--------|---------|-----|------|------------|
| **Victoria** | **3.13.18** ✅ | v22.22.1 | 1.26.5 | 1.95.0 | N/A |
| **kalimete** | **3.13.5** ✅ | **v22.23.4** ✅ | 1.26.5 | 1.95.0 | N/A |

---

## 🐳 Imágenes Docker Base (Canónicas)

| Servicio | Imagen Actual | Imagen Canónica | Estado |
|----------|---------------|-----------------|--------|
| **WordPress Sites** | `wordpress:7.1.3-php8.3-apache` | `wordpress:8.4-php8.4-apache` | ⏳ Pendiente imagen oficial |
| **WordPress Dev (lab)** | `wordpress:6.7-php8.3-apache` | `wordpress:8.4-php8.4-apache` | ⏳ Pendiente imagen oficial |
| **ERP Dev App** | `php:8.3-fpm` | **`php:8.4-fpm`** ✅ | **ACTUALIZADO** |
| **ERP Dev Nginx** | `nginx:1.25-alpine` | `nginx:1.25-alpine` | ✅ (intencional) |
| **ERP Dev DB** | `mysql:8.0` | `mysql:8.0` | ✅ |
| **ERP Dev Redis** | `redis:7-alpine` | `redis:7-alpine` | ✅ |
| **MariaDB (WP)** | `mariadb:10.11` | `mariadb:10.11` | ✅ |
| **PostgreSQL (Ecco)** | `postgres:17` | `postgres:17` | ✅ |
| **Redis** | `redis:7-alpine` | `redis:7-alpine` | ✅ |
| **Nginx (Host)** | `nginx:1.30.1` | `nginx:1.30.1` | ✅ |
| **Caddy (Ecco)** | `caddy:2` | `caddy:2` | ✅ |

---

## 📦 Versiones de Lenguajes/Tools (Hosts)

| Tool | Victoria | kalimete | Canónica | Notas |
|------|----------|---------|----------|-------|
| **Python** | **3.13.18** ✅ | **3.13.5** ✅ | **3.13.x LTS** | Victoria: deadsnakes PPA |
| **Node.js** | v22.22.1 | **v22.23.4** ✅ | **v22.x LTS** | nvm en ambos |
| **Go** | 1.26.5 | 1.26.5 | **1.26.x** | Hosts |
| **Rust** | 1.95.0 | 1.95.0 | **1.95.x** | Hosts |
| **PHP (host)** | N/A | N/A | — | Solo en contenedores |
| **Docker** | 28.x | 28.x | Latest stable | — |
| **Docker Compose** | v2.x | v2.x | v2.x | — |

---

## 🔧 Versiones de Componentes Críticos

| Componente | Versión | Ubicación | Notas |
|------------|---------|-----------|-------|
| **Armada Suite Plugin** | **5.8.0** | GitHub warcold/armada-suite | Header: `Requires PHP: 8.1` |
| **Armada Suite (preprod)** | 5.7.0 | micaserogou/magantech | Espejo de release |
| **Armada Suite (prod)** | 5.5.10 → 5.7.0 | micaserogou.com | Ventana pendiente |
| **ZionV CRM** | 1.56.3 | zionv-crm | Fusionado → Zion CRM 2.0.0 |
| **Zion CRM 2.0.0** | 2.0.0 | Fusionado 2026-10-28 | Unifica ZionV + Armada |
| **WPVibe (AI Bridge)** | 1.20.0 | Dentro de Armada Suite | — |
| **SiteBackup (AIO WP)** | 7.111 | Dentro de Armada Suite | — |
| **vLLM** | 0.21.0+2325b6f0 | NGC 26.05.post1 | Digest pinned |
| **Modelo LLM** | Qwen3.6-35B-A3B-NVFP4 | 256K contexto | 220K prompt + 32K output |
| **vLLM Gateway** | v3 (custom) | Victoria :8010 | Admisión adaptativa |
| **ComfyUI** | v0.42.0 | Victoria :8188 | aimdo 0.6.0 + kitchen 0.2.40 |
| **LivePortrait** | Gradio 6.29.1 | Victoria :8180 | 8 fixes custom |
| **Sonic** | jixiaozhong/Sonic | Victoria :18850 | CC BY-NC-SA 4.0 |
| **Hunyuan3D-2** | tencent/Hunyuan3D-2mini | Victoria :18860 | CC BY-NC-SA 4.0 |
| **lp-animate** | LivePortrait CLI | Victoria :18861 | Presets 01/02/03 |

---

## 📋 Reglas de Actualización

1. **PROD manda**: Las versiones en PROD (cPanel/VPS) son la referencia canónica.
2. **PREPROD/DEV → PROD**: Actualizar PREPROD/DEV para que coincidan con PROD (same major version).
3. **Imágenes oficiales**: Esperar imágenes oficiales (WordPress, etc.) antes de forzar upgrades.
3. **Header Plugin**: `Requires PHP: 8.1+` = mínimo probado en PROD (8.3/8.4/8.5).
4. **Tests regresión**: 35/35 PASS obligatorio antes de deploy.
4. **Changelog**: Cada cambio de versión → entrada en CHANGELOG-MAESTRO.md + harness correspondiente.
5. **Harnesses**: Actualizar `vivo_YYYY_MM_DD` + `servicios[].php` en cada harness afectado.

---

## 📅 Historial de Cambios Recientes (2026-10-29)

| Fecha | Componente | Cambio | Responsable |
|-------|------------|--------|-------------|
| 2026-10-29 | **ERP Dev** | PHP 8.3.33 → **8.4.27** (Dockerfile `php:8.4-fpm`) | Victoria |
| 2026-10-29 | **Armada Suite** | Header `Requires PHP: 7.4` → **`8.1+`** | Victoria |
| 2026-10-29 | **Victoria** | Python 3.12.3 → **3.13.18** (deadsnakes PPA) | Victoria |
| 2026-10-29 | **kalimete** | Node.js v22.22.1 → **v22.23.4** (nvm) | Victoria |
| 2026-10-29 | **Harnesses** | PHP versions precisas por entorno (PROD/PREPROD/DEV) | Victoria |
| 2026-10-29 | **WordPress Base** | `php8.3-apache` → **`php8.4-apache`** (compose actualizados) | Victoria |
| 2026-10-29 | **WordPress Base Image** | `wordpress:7.1.3-php8.3-apache` → **pendiente `8.4-php8.4-apache`** | Victoria |

---

## 🔮 Próximos Pasos (Pendientes)

1. **WordPress Base Image PHP 8.4**: Esperar release oficial `wordpress:8.4-php8.4-apache` en Docker Hub → recrear contenedores WP.
2. **ERP Dev Build**: Completar build PHP 8.4 (en curso) → reiniciar contenedor app.
3. **WordPress Dev Lab**: Recrear `wordpress-local` con imagen `wordpress:8.4-php8.4-apache` cuando esté disponible.
3. **ZionV CRM / Magantech / Micaserogou PREPROD**: Recrear contenedores con nueva base image cuando esté disponible.
4. **Matriz de compatibilidad**: Verificar Armada Suite 5.8.0 en PHP 8.4 (tests 35/35 PASS actual).

---

**Mantenido por**: Victoria Armada (orquestadora)  
**Última actualización**: 2026-10-29 19:30 UTC  
**Próxima revisión**: Al release de `wordpress:8.4-php8.4-apache` o próximo deploy PROD.