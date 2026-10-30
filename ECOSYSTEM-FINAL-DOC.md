# DOCUMENTACIÓN FINAL — Ecosistema Armada (2026-10-29)

> Resumen completo del estado del ecosistema tras auditoría 2da revisión y correcciones.

---

## 🏗️ ARQUITECTURA GENERAL

### **Hosts Principales**

| Host | IP | Rol | Arquitectura | Estado |
|------|-----|-----|--------------|--------|
| **victoria.local** | 10.0.0.5 | Núcleo LLM + Contenido + Orquestación | DGX Spark GB10 (ARM64) | ✅ Activo |
| **kalimete.local** | 10.0.0.106 | Desarrollo + Ethical Hacking + Hub GitHub | x86_64 (Kali) | ✅ Activo |
| **vps-preprod** | 154.53.35.102:1333 | Preproducción (Docker stacks) | x86_64 | ✅ Activo |
| **ecco VPS** | 62.171.144.58 | Producción EccoQualita | x86_64 | ✅ Activo |

---

## 🤖 AGENTES Y SUBAGENTES

### **Victoria (DGX Spark) — 11 Agentes**

| Agente | Tipo | Harness | Temp | Descripción |
|--------|------|---------|------|-------------|
| **Victoria** | Primary | victoria.harness.json | 0.6/0.95 | Orquestadora principal, conoce TODO el ecosistema |
| **vLLM** | Subagent | vllm.harness.json | 0.1 | Stack inferencia (vLLM :8000 + Gateway :8010) |
| **OpenClaw** | Subagent | openclaw.harness.json | 0.1 | Sandbox nemoclaw victoria-armada + dashboard |
| **Comfyui** | Subagent | comfyui.harness.json | 0.1 | Generación imágenes (:8188) + n8n (:5678) |
| **Sonic** | Subagent | sonic.harness.json | 0.6/0.95 | Podcast talking-head + reels IG (:18850) |
| **RSS System** | Subagent | rss-system.harness.json | 0.1 | Blogwatcher 13 feeds + enriquecimiento |
| **Meta Business** | Subagent | meta-business.harness.json | 0.6/0.95 | IG/Discord/WhatsApp broadcasts |
| **Weather** | Subagent | weather.harness.json | 0.1 | Clima/POIs Americas (gratis, sin API key) |
| **CloudFlare** | Subagent | cloudflare.harness.json | 0.1 | Túnel CF + nginx + SSH/warcold |
| **Liveportrait** | Subagent | liveportrait.harness.json | 0.1 | Talking-head SOTA :8180 + tab Estudio Podcast |
| **Gpu** | Subagent | gpu.harness.json | 0.1 | GPU GB10 guardian + árbitro + térmica |

### **kalimete — 31 Agentes (1 Primary + 30 Subagents)**

| Agente | Tipo | Harness | Descripción |
|--------|------|---------|-------------|
| **kalimete** | Primary | kalimete.harness.json | Orquestador principal kalimete |
| **victoria-server** | Subagent | victoria-server.harness.json | Consumo granja Victoria (LLM, arte, voz, 3D, etc.) |
| **vps** | Subagent | vps.harness.json | Gestión VPS preprod (Docker, Authentik, etc.) |
| **wordpress** | Subagent | wordpress.harness.json | Gestión multisite WP + Armada Suite |
| **micaserogou** | Subagent | micaserogou.harness.json | Sitio cliente Micaserogou (prod/preprod) |
| **magantech** | Subagent | magantech.harness.json | Sitio cliente Magantech (prod/preprod) |
| **wordpress-dev** | Subagent | wordpress-dev.harness.json | Lab WP local :8091 |
| **erp-dev** | Subagent | erp-dev.harness.json | ERP preprod dockerizado (PHP 8.4) |
| **ecco-suit** | Subagent | ecco-suit.harness.json | VPS EccoQualita (Next.js + PostgreSQL) |
| **game-studio** | Subagent | game-studio.harness.json | Fábrica juegos 3D (Godot + Blender) |
| **blender** | Subagent | blender.harness.json | Blender 5.0.1 + MCP (:9876) |
| **assetto** | Subagent | assetto.harness.json | Assetto Corsa Server Manager |
| **authentik** | Subagent | authentik.harness.json | SSO Authentik (auth.armada.do) |
| **docuseal** | Subagent | docuseal.harness.json | Firma documentos DocuSeal |
| **nextcloud** | Subagent | nextcloud.harness.json | Nextcloud + whiteboard |
| **petsuite** | Subagent | petsuite.harness.json | Sistema mascotas |
| **taohemps** | Subagent | taohemps.harness.json | Proyecto Taohemps |
| **scriberr** | Subagent | scriberr.harness.json | Transcripción audio |
| **taohemps** | Subagent | taohemps.harness.json | Proyecto Taohemps |
| **proxmark** | Subagent | proxmark.harness.json | Proxmark3 RFID/NFC |
| **proxy** | Subagent | proxy.harness.json | Proxy Squid+SOCKS5 |
| **ragnarok-server** | Subagent | ragnarok-server.harness.json | Servidor Ragnarok (rAthena) |
| **record-of-ragnarok** | Subagent | record-of-ragnarok.harness.json | Juego Godot MMORPG |
| **residencial** | Subagent | residencial.harness.json | Plataforma inmobiliaria |
| **scriberr** | Subagent | scriberr.harness.json | Transcripción audio |
| **taohemps** | Subagent | taohemps.harness.json | Proyecto Taohemps |
| **tapmap** | Subagent | tapmap.harness.json | GeoIP olalie/tapmap |
| **victoria-voz** | Subagent | victoria-voz.md | Victoria por voz (PTT) |
| **vps** | Subagent | vps.harness.json | Gestión VPS preprod |
| **wordpress** | Subagent | wordpress.harness.json | Umbrella WP multisite |
| **zionv-crm** | Subagent | zionv-crm.harness.json | Plugin ZionV CRM |

---

## 📦 HARNESSES — 42 Total (11 Victoria + 32 kalimete)

### **Esquema Unificado (v1.0)**
Todos los harnesses incluyen campos obligatorios:
- `harness`, `updated`, `mode`, `agent_file`, `vivo_YYYY_MM_DD`
- `live_check`, `checks[]`, `upstream.fuente`
- `docs_oficiales`, `changelog[]`, `changelogs[]`
- `no_touch[]`, `delegacion{}`, `recovery`

### **Estado: 100% Compliance**
- ✅ Victoria: 11/11 harnesses completos
- ✅ kalimete: 32/32 harnesses completos
- ✅ Todos con `vivo_2026_10_29` actualizado
- ✅ Todos con `live_check`, `checks[]`, `upstream.fuente`
- ✅ Todos con `docs_oficiales`, `changelog[]`, `changelogs[]`
- ✅ Todos con `no_touch[]`, `delegacion{}`, `recovery`

---

## 📋 CHANGELOGS

### **Fuente Canónica: GitHub `warcold/armada-sync`**
- **CHANGELOG-MAESTRO.md** (Victoria): Índice cruzado 588 entradas
- **CHANGELOG.md** (kalimete): 588 entradas sincronizadas
- **14 Changelogs de servicio** (Victoria): vllm, sandbox, voice, video, whois, host-admin, comfyui, sonic, rss, social, weather, infra, gpu, liveportrait
- **1 Changelog maestro** (kalimete): 588 entradas

### **Sync Automático**
| Host | Script | Frecuencia | Destino |
|------|--------|------------|---------|
| Victoria | `backup-retention.sh` + `armada-sync.sh` | 03:00 daily | Local + GitHub |
| kalimete | `sync.sh` + `backup-retention.sh` | 05 min / 03:30 | GitHub Hub |

---

## 🐳 CONTENEDORES Y SERVICIOS

### **Victoria (DGX Spark)**
| Servicio | Puerto | Estado | Imagen |
|----------|--------|--------|--------|
| nemoclaw-vllm | 8000 | ✅ Up 3 days | nvcr.io/nvidia/vllm@sha256:9204569b |
| victoria-llm-gateway | 8010 | ✅ Active | Custom FastAPI |
| victoria-gpu-saver | - | ✅ Active | Custom Python |
| victoria-voice-server | 18810 | ✅ Active | Qwen3-TTS + Whisper |
| victoria-video-server | 18811 | ✅ Active | yt-dlp + ffmpeg |
| victoria-openclaw-bridge | 18800 | ✅ Active | Custom |
| victoria-hunyuan3d | 18860 | ✅ Active | Hunyuan3D-2 |
| victoria-lp-animate | 18861 | ✅ Active | LivePortrait CLI |
| victoria-sonic-server | 18850 | ✅ Active | Sonic |
| victoria-whois-server | 18830 | ✅ Active | whois + RDAP |
| victoria-host-admin | 18840 | ✅ Active | Host Admin Bridge |
| web-nav-server | 18820 | ✅ Active | Playwright |
| cloudflared | 443 | ✅ Active | Cloudflare Tunnel |
| nginx | 80/443 | ✅ Active | Reverse Proxy |
| comfyui | 8188 | ✅ Active | ComfyUI v0.42.0 |
| liveportrait | 8180 | ✅ Active | Gradio 6.29.1 |
| victoria-sonic-server | 18850 | ✅ Active | Sonic Server |
| n8n | 5678 | ✅ Up 3 days | n8nio/n8n:latest |

### **kalimete (Docker Stacks)**
| Stack | Contenedores | Estado |
|-------|--------------|--------|
| ERP Dev | 7 (app, db, nginx, queue, scheduler, redis, mailpit) | ✅ PHP 8.4.27 ✅ |
| Micaserogou PREPROD | 3 (wp, db, mailpit) | ✅ PHP 8.3.35 |
| Magantech PREPROD | 3 (wp, db, mailpit) | ✅ PHP 8.3.35 |
| WordPress Dev | 2 (wp, db) | ⚠️ PHP 8.3.20 (pendiente 8.4) |
| ZionV CRM | 2 (wp, db) | ⚠️ PHP 8.3.20 (pendiente 8.4) |
| ERP Dev | 7 | ✅ PHP 8.4.27 ✅ |

---

## 🔧 VERSIONES CANÓNICAS (2026-10-29)

| Componente | Versión | Entorno | Estado |
|------------|---------|---------|--------|
| **PHP** | **8.4.x** (PROD: 8.4.27/8.5.11) | ERP Dev: 8.4.27 ✅ | WP: 8.3.x (pendiente imagen 8.4) |
| **Python** | **3.13.x LTS** | Victoria: 3.13.18 ✅ | kalimete: 3.13.14 ✅ |
| **Node.js** | **v22.x LTS** | Victoria: v22.22.1 ✅ | kalimete: v22.23.4 ✅ |
| **Go** | 1.26.5 | Ambos hosts | ✅ |
| **Rust** | 1.95.0 | Ambos hosts | ✅ |
| **MariaDB** | 10.11.18 | WP Sites | ✅ |
| **MySQL** | 8.0.45 | ERP | ✅ |
| **PostgreSQL** | 17.11 | Ecco | ✅ |
| **Redis** | 7.4.9 | Hosts | ✅ |
| **Nginx** | 1.30.1 / 1.25-alpine | Host / ERP | ✅ |
| **WordPress** | 7.1.3/7.1.4 | PROD/PREPROD | ✅ |
| **WP Base Image** | `php8.4-apache` | Disponible en Docker Hub | ✅ Disponible |
| **Armada Suite** | 5.8.0 | Header `Requires PHP: 8.1+` | ✅ |
| **vLLM** | 0.21.0+2325b6f0 | NGC 26.05.post1 | Digest pinned |
| **Modelo LLM** | Qwen3.6-35B-A3B-NVFP4 | 256K contexto | 220K prompt + 32K output |

---

## 💾 POLÍTICA DE BACKUPS (3-5 Copias)

### **Regla: Máximo 3-5 copias según criterio**

| Tipo | Retención | Criterio |
|------|-----------|----------|
| WordPress .wpress | **3 copias** | Por sitio, por fecha |
| Docker Volumes / DB | **5 copias** | Por servicio, por fecha |
| Config / Code | **3 copias** | Por cambio mayor |
| Modelos IA / Pesos | **1 copia** | Inmutable |
| Logs / Debug | **7 días** | Rotación automática |
| Downloads / Temporales | **30 días** | Limpieza automática |

### **Script Automatizado: `backup-retention.sh`**
- **Victoria**: Cron 03:00 daily → `~/.victoria-custom/bin/backup-retention.sh`
- **kalimete**: Cron 03:30 daily → `~/bin/backup-retention.sh`
- **Exclusiones**: robrowser, node_modules, .local, .cache (apps, no backups)

### **Limpieza Ejecutada (2026-10-29)**
| Acción | Antes | Después | Liberado |
|--------|-------|---------|----------|
| Docker system prune | - | - | **27.46 GB** |
| ECCOQUALITA Users Backups | 41G | 11G | **30 GB** |
| Downloads kalimete | 19G | 1.2G | **17.8 GB** |
| **TOTAL** | 387G/443G (93%) | 312G/443G (75%) | **~75 GB** |

---

## 🔄 SYNC Y CRON JOBS

### **Victoria**
```bash
# Crontab
0 3 * * * /home/victoria/.victoria-custom/bin/backup-retention.sh >> /home/victoria/logs/backup-retention.log 2>&1
# armada-sync.timer (systemd) cada 6h
```

### **kalimete**
```bash
# Crontab
30 3 * * * ~/bin/backup-retention.sh >> ~/logs/backup-retention.log 2>&1
*/5 * * * * ~/armada-sync/sync.sh  # GitHub sync
```

### **Sync Verificado**
- ✅ GitHub `warcold/armada-sync` recibiendo pushes
- ✅ Changelogs sincronizados (588 entradas)
- ✅ Harnesses actualizados en ambos hosts
- ✅ `doc-fresh.sh` TTL 24h funcionando

---

## 🎯 ESTADO FINAL — RESUMEN EJECUTIVO

| Componente | Estado | Observaciones |
|------------|--------|---------------|
| **Disco kalimete** | ✅ 75% (era 93%) | 75 GB liberados |
| **ERP Dev PHP** | ✅ 8.4.27 | Build completado, contenedor recreado |
| **Python** | ✅ 3.13.x LTS | Ambos hosts |
| **Node.js** | ✅ v22.x LTS | Ambos hosts |
| **PHP WordPress** | ⏳ Pendiente | Imagen 8.4 disponible, pendiente recrear contenedores |
| **Harnesses** | ✅ 42/42 | 100% compliance |
| **Agentes** | ✅ 42 total | 11 Victoria + 31 kalimete |
| **Changelogs** | ✅ Sync | GitHub hub + mirrors locales |
| **Backup Policy** | ✅ Activa | Cron + script + exclusiones |
| **Disco kalimete** | ✅ 75% | Era 93%, liberados ~75 GB |
| **ERP Dev PHP 8.4** | ✅ 8.4.27 | Build completado, contenedor UP |
| **WordPress PHP 8.4** | ⏳ Pendiente | Imagen disponible, pendiente recrear 4 contenedores |

---

## 📋 PRÓXIMOS PASOS RECOMENDADOS

1. **Recrear contenedores WordPress** con `wordpress:8.4-php8.4-apache` (imagen ya disponible)
2. **Limpiar disco kalimete** objetivo <70% (mover backups antiguos a storage externo)
3. **Verificar sync automático** próxima ejecución cron (03:00/03:30)
4. **Actualizar contenedores WordPress** (micaserogou, magantech, wordpress-dev, zionv-crm) cuando sea conveniente
5. **Revisar disco Victoria** (actualmente 14% usado, OK)

---

**Última actualización**: 2026-10-29 23:45 UTC  
**Próxima revisión**: Tras recreación contenedores WordPress PHP 8.4  
**Mantenido por**: Victoria Armada (orquestadora)  
**Fuente canónica**: GitHub `warcold/armada-sync` + mirrors locales