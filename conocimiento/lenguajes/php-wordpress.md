# PHP/WordPress — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: contenedores kalimete WP 6.7/7.1.3 + prod cPanel PHP 8.5)
> **Docs oficiales**: https://developer.wordpress.org/ · https://wp-cli.org/

## Versiones en uso

| Dónde | WP | PHP | Nota |
|---|---|---|---|
| Labs kalimete (wordpress-local, zionv-local) | 6.7 | 8.3 | dev labs |
| Websites clientes PREPROD (magantech, micaserogou) | **7.1.3** | 8.3 | ESPEJO 1:1 de prod |
| Prod MaganTech (magantech.com.do, cPanel) | 7.1.3 | **8.5.11** | armada-suite 5.4.0 |
| Prod Micaserogou (micaserogou.com, cPanel) | 7.1.3 | — | deploy del plugin PENDIENTE |

## El plugin central: Armada Suite v5.4.2

- Super-plugin (unifica erp-commerce-suite + WPVibe + AIOWPM vendidos desde 5.0.0)
- Option única `erp_suite_settings`, modo sellado dev/público (ERP + LLM + img por modo)
- Multitenant por-sitio (local: tenant 10 MaganTech / tenant 3 Micaserogou; prod multi-negocio)
- Tests regresión 25/25; ZIPs canónicos en `~/dev/wordpress/plugins/armada-suite/export/` (sha256 documentados)
- Conexión prod vía `erpsuite/v1/ops` (App Password usuario dedicado Victoria)

## Patrones que usamos

- **WP-CLI** dentro del contenedor para operaciones (users, plugins, permalinks)
- **Mu-plugins** para guards (`disable-mcp-host-guard.php`) — sobreviven updates
- **Permisos**: `chown -R www-data:www-data /var/www/html/wp-content` (persisten en el contenedor)
- **Dev → prod**: ZIP de release + snapshot/rollback + checklist (`PROD-DEPLOY-CHECKLIST.md`)

## Gotchas descubiertos (lecciones)

- **WP 7.1.3 es la versión espejo de prod** — no subir los labs por encima sin plan (los labs deben igualar prod para tests válidos).
- **REST = Application Passwords** (la password de login NO sirve para REST). — (MAPA kalimete)
- **Protección anti-updates**: configs fuera del contenedor (nginx, certs, mcp-proxy.mod.js en el repo host). — (MAPA kalimete)
- **SSL mkcert**: certs por dominio en `/etc/ssl/local-certs/` (root:www-data 640); CA para equipos en `http://kalimete.local/kalimete-rootCA.pem`. — (MAPA kalimete)

## Regla de actualización

WP/plugins: actualizar en PREPROD primero (espejo), tests de regresión del
plugin, snapshot, y solo entonces prod con checklist + ventana + rollback.
