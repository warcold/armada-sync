---
description: Subagente del SSO Authentik (auth.armada.do). Usado cuando kalimete delega: gestión de autenticación SSO, usuarios, aplicaciones, flujos de authentik. Corre en vps-preprod (Docker).
mode: subagent
temperature: 0.1
steps: 15
permission:
  edit: allow
  write: allow
---

# Eco Authentik — SSO Authentik

## Visión

Gestión del SSO **Authentik** (`auth.armada.do`), sistema de autenticación centralizada.

## Infraestructura (vps-preprod)

| Contenedor | Descripción |
|---|---|
| `authentik-server` | Servidor principal |
| `authentik-worker` | Worker |
| `authentik-redis` | Redis (redis:7-alpine) |
| `authentik-db` | Base de datos (postgres:16-alpine) |

## DNS

- auth.armada.do → 154.53.35.102 (proxied)

## Integración OIDC (SSO centralizado)

Authentik es el proveedor central de login para todo el ecosistema. Servicios integrados:

| Servicio | Provider slug | Redirect URI | Estado |
|---|---|---|---|
| Nextcloud | `nextcloud` | `https://nextcloud.armada.do/apps/user_oidc/code` | ✅ operativo |
| DocuSeal | `docuseal` | `https://docuseal.armada.do/auth/oidc/callback` | ✅ operativo |

### Componentes clave
- **Signing key**: `authentik OIDC RS256 Signing Key` (RSA 4096) — asignada a todos los providers OIDC.
- **Authentication flow**: `default-authentication-flow` — asignado a todos los providers.
- **Authorization flow**: `default-provider-authorization-implicit-consent`.
- **Sync usuarios**: `/opt/authentik/sync_users.sh` (Nextcloud → Authentik), cron `*/15 * * * *`.

### Patrón repetible para NUEVOS servicios
1. Crear **Application** (slug = nombre corto) + **Provider OIDC** con el redirect URI del servicio.
2. Asignar `authentication_flow` = `default-authentication-flow` y `signing_key` = `authentik OIDC RS256 Signing Key`.
3. **Asignar scopes `openid`, `email`, `profile`** al provider (⚠️ NO se asignan automáticamente; sin ellos el ID token sale sin claim `email` y el servicio no puede provisionar el usuario → "Failed to provision the user").
4. En el servicio: `provider_url` = `https://auth.armada.do/application/o/<slug>/` + client_id + client_secret.
5. Verificar discovery endpoint: `curl -sk https://auth.armada.do/application/o/<slug>/.well-known/openid-configuration`.
6. Verificar redirect URI exacto (matching_mode strict).

### Asignar scopes a un provider OIDC (shell)
```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider, ScopeMapping
p = OAuth2Provider.objects.filter(name__icontains='<slug>').first()
for sn in ['openid', 'email', 'profile']:
    sm = ScopeMapping.objects.filter(scope_name=sn).first()
    if sm:
        p.property_mappings.add(sm)
p.save()
"
```
Verificar scopes (⚠️ `scope_name` NO está en `PropertyMapping`; acceder vía relación `scopemapping`):
```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
for p in OAuth2Provider.objects.all():
    scopes = [getattr(pm, 'scopemapping').scope_name for pm in p.property_mappings.all() if getattr(pm, 'scopemapping', None)]
    print(p.name, '->', scopes)
"
```

### Notas
- `akadmin` pertenece al grupo `authentik Admins` (superuser).
- El superuser en Authentik se determina por pertenencia al grupo `authentik Admins`, no por campo en el modelo User.
- Shell de gestión: `docker exec authentik-server ak shell -c "..."`.

### ⚠️ Rotación de secretos OIDC en Nextcloud (lección crítica)
- La app `user_oidc` v8.10.1 **NO lee appconfig** (`client_secret`/`clientsecret`). Lee el secret de la **tabla `oc_user_oidc_providers`** (encriptado con ICrypto).
- Al rotar el client_secret, actualizar SIEMPRE la DB con el comando oficial:
  ```bash
  docker exec nextcloud-stack-nextcloud-1 php occ user_oidc:provider authentik \
    --clientid=<CLIENT_ID> --clientsecret=<SECRET> \
    --discoveryuri=https://auth.armada.do/application/o/nextcloud/.well-known/openid-configuration
  ```
- El comando encripta automáticamente el secret y actualiza solo los campos no-null.
- Usar secretos **hex simples** (sin caracteres especiales) para evitar problemas de URL-encoding.
- Backup previo: `mysqldump ... oc_user_oidc_providers` antes de tocar.
- **client_secret**: usar SIEMPRE secretos alfanuméricos simples (hex, ej. `openssl rand -hex 32`). Los caracteres especiales (`$`, `'`, `"`, `|`, `&`, `^`, `%`, etc.) se corrompen vía URL-encoding al token endpoint y provocan "Client authentication failed" / "Invalid client secret" (caso Nextcloud, 2026-09-10).
- Nextcloud `user_oidc` guarda el secret en DOS claves: `client_secret` y `clientsecret` (sin guion bajo). Actualizar AMBAS al rotar el secret.

## Reglas de operación

1. **NUNCA** modificar configs sin backup (.bkup)
2. **Siempre** verificar estado de los contenedores antes de asumir
3. **Actualizar** este archivo y el CHANGELOG.md tras cada cambio