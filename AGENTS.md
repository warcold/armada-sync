# Armada Network — Red de Agentes Sincronizados

## Visión General

**Armada** es una red de 4 máquinas interconectadas que comparten agentes opencode, skills, commands y documentación a través de un repositorio Git central ().

## Topología de Red

| Host | IP | SSH | Usuario | GPU | Rol |
|------|-----|-----|---------|-----|-----|
| **kalimete** | 10.0.0.106 | 1111 | warcold | — | Hub principal, PC de trabajo |
| **rootsource** | 10.0.0.5 | 31337 | rootsource | GB10 124GB | Servidor LLM, gateway |
| **victoria** | 10.0.0.64 | 1666 | victoria | — | Asistente Victoria, OpenClaw |
| **jonas** | 10.0.0.20 | 1222 | jonas | — | NAS, Home Assistant |

## Conectividad SSH



## Sistema de Sincronización

### Repositorio Central
- **URL**: 
- **Rama**: 
- **Estructura**:
  

### Script sync.sh
Cada máquina ejecuta  para:
1. Pull latest from GitHub
2. Deploy agents/skills/commands a 
3. Collect local changes
4. Push to GitHub

### Automatización
- **kalimete**:  → 
- **victoria**:  → 
- **jonas**:  → 

## Agentes por Máquina

### kalimete (hub)
-  — Agente principal del ecosistema
-  — Modelo de acceso SSH
-  — Servicio de voz de Victoria
-  — Consulta solo lectura
- Cloudflare agents (cf-dns, cf-security, cf-storage, cf-tunnels, cf-workers, cloudflare)
- Skill: 
- Command: 

### victoria
-  — Consulta solo lectura a kalimete
-  — Consulta solo lectura a jonas
-  — Consulta solo lectura a rootsource

### jonas
- *(Sin agentes locales — usa los del repo)*

## Servicios Principales

| Servicio | Puerto | Máquina | Estado |
|----------|--------|---------|--------|
| vLLM | 8000 | rootsource | ✅ Qwen3.6-35B-A3B-NVFP4 |
| llmgate | 4010 | rootsource | ✅ API key auth |
| OpenShell | 8080 | rootsource | ✅ Sandbox Docker |
| ComfyUI | 8188 | rootsource | ❌ No corre |
| OpenClaw | 18789 | victoria | ✅ Gateway |
| Voice UI | 8765 | victoria | ✅ HTTPS |
| Home Assistant | 8123 | jonas | ✅ Container |

## Reglas de Operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **NUNCA** compartir llaves privadas entre personas
3. **Siempre** verificar estado de servicios antes de asumir
4. **Sync automático** cada 5 minutos vía cron
5. **Conflictos Git**: resolver manualmente, documentar en commit message
