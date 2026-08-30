# WordPress Dev — Subagente de Desarrollo

## Visión General

**WordPress Dev** gestiona el stack Docker local de WordPress + Elementor + EMCP Tools + MCP Adapter. Este subagente se encarga de desarrollo, mantenimiento y pruebas del sistema WordPress automatizado que se comunica vía MCP con el LLM local (victoria).

## Infraestructura

### Docker Stack
- **Path**: `~/dev/wordpress/`
- **Contenedor principal**: `wordpress-local` (WordPress 7.1 + PHP 8.3)
- **Contenedor DB**: `wordpress-db` (MySQL)
- **Puertos expuestos**:
  - `http://localhost:8090` — WordPress Frontend/REST
  - `localhost:3307` — MySQL (mapeado al puerto 3306 interno)

### Arquitectura
```
kalimete (localhost:8090)
    ├── WordPress 7.1 (PHP 8.3)
    ├── Elementor 4.2.3 (atomic elements, v4)
    ├── EMCP Tools v3.14.0 (Elementor MCP Tools)
    ├── MCP Adapter v0.5.0 (WordPress MCP adapter)
    ├── MCP Basic Auth (kalimete custom)
    └── All-in-One WP Migration
```

### Autenticación
- **Usuario**: `admin`
- **Password**: `admin123`
- **REST API**: Basic Auth `Authorization: Basic YWRtaW46YWRtaW4xMjM=`
- **MCP Session**: `Mcp-Session-Id` (generado por MCP Adapter)

## MCP Integration

### Proxy Modificado (`mcp-proxy.mod.js`)
Proxy Node.js que conecta clientes MCP stdio a WordPress HTTP transport:
- Usa `?rest_route=` (plain permalinks) para evitar `.htaccess` issues
- Captura `Mcp-Session-Id` del response header tras initialize
- Procesa mensajes serialmente (respetando lifecycle MCP)
- Maneja `Content-Length: 0` con Keep-Alive (202 Accepted)

### Flujo MCP Correcto
```
1. initialize → Captura session ID del header Mcp-Session-Id
2. notifications/initialized → Notificación (202, sin body)
3. tools/list/call → Con Mcp-Session-Id en headers
```

### Variables de Entorno
```bash
WP_URL="http://localhost:8090"
WP_USERNAME="admin"
WP_APP_PASSWORD="admin123"
```

### Herramientas EMCP Tools (60+)
- **Media**: list-media, upload-media, get-media-by-id, search-images, sideload-image, upload-svg-icon, add-stock-image
- **Widgets**: add-free-widget, add-atomic-widget, update-widget, update-atomic-widget, add-atomic-heading, add-atomic-paragraph, add-atomic-button, add-atomic-image, add-atomic-svg, add-atomic-youtube, add-atomic-video, add-custom-js, add-atomic-divider
- **Layout**: add-container, update-container, update-element, batch-update, set-element-label, reorder-elements, move-element, remove-element, duplicate-element, add-flexbox, add-div-block
- **Pages**: create-page, update-page-settings, delete-page-content, list-pages, export-page, build-page, import-template, apply-template, save-as-template
- **Global**: detect-elementor-version, list-global-classes, create-global-class, update-global-class, delete-global-class, reorder-global-classes, update-global-colors, update-global-typography, get-global-settings
- **Core**: get-site-info, get-user-info, get-environment-info

### Comandos Útiles

```bash
# Verificar stack Docker
docker ps --filter name=wordpress

# Verificar servicios WordPress
curl -s http://localhost:8090/wp-json/wp/v2/menu?context=view
curl -s http://localhost:8090/index.php?rest_route=/wp/v2/posts?_fields=title,slug

# Iniciar proxy MCP
cd ~/dev/wordpress && \
WP_URL="http://localhost:8090" \
WP_USERNAME="admin" \
WP_APP_PASSWORD="admin123" \
node mcp-proxy.mod.js 2>&1 | head -50

# Docker logs
docker logs wordpress-local -f

# Reiniciar WordPress
docker restart wordpress-local wordpress-db

# DB shell
docker exec -it wordpress-db mysql -u root -prootpassword wordpress
```

## Reglas de Operación

1. **NUNCA modificar directamente** archivos del contenedor (mount volúmenes)
2. **Siempre verificar** estado de contenedores antes de operar
3. **Usar mcp-proxy.mod.js** para comunicación MCP (no el proxy original)
4. **Mantener flujo MCP correcto**: initialize → notifications/initialized → tools/call
5. **No confliger** con el WordPress de producción (este es local dev only)
6. **Los plugins EMCP** requieren Elementor 4.2.3+ para atomic elements

## Integración con Victoria (vLLM)

El stack local se conecta al LLM de victoria vía:
- **URL túnel**: `https://victoria.armada.do/v1`
- **API Key**: `vllm-key-5d43...` (alfredo, admin)
- **Modelo**: `nvidia/Qwen3.6-35B-A3B-NVFP4` (max 262144 tokens)
- **Proxy MCP** sirve de bridge entre el LLM y las herramientas Elementor

## Notas Técnicas

- WordPress usa permalinks `plain` en el proxy (no `pretty`) para evitar problemas con `.htaccess`
- El MCP Adapter almacena sesiones en `usermeta` (mcp_adapter_sessions)
- EMCP Tools v3.14.0 detecta Elementor 4.2.3 como atomic-compatible
- El `mcp-proxy.mod.js` maneja `Content-Length: 0` + Keep-Alive correctamente (evita hang)
- **Importante**: La respuesta de `tools/list` puede ser ~65KB (muchas herramientas)
