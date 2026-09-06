## 2026-09-06

### [02:55] - Fix: frontmatter inválido en eco-woodly y eco-alfredo-ecomm rompía el arranque de opencode
- **Tipo**: agente | config
- **Modificado**: `agents/eco-woodly.md`, `agents/eco-alfredo-ecomm.md`, symlinks en `~/.config/opencode/agent/`
- **Afecta a**: kalimete (opencode)
- **Causa**: Ambos agentes (creados/modificados en sesión Alfredo Pro Ecomm del 2026-09-06 01:26) tenían frontmatter inválido: `mode: agent` (solo son válidos `primary`/`subagent`/`all`), `max_steps` (correcto: `steps`) y claves no estándar (`tools:` en lista, `hidden: true`). El schema de opencode rechazaba los agentes al arrancar; eco-woodly fue renombrado a `.backup` como workaround y eco-alfredo-ecomm nunca tuvo symlink.
- **Estado**: ✅ verificado — ambos agentes cargan como subagent (`opencode agent list`)
- **Notas**: frontmatter normalizado al estándar de los demás eco-* (description/mode/subagent/temperature/steps/permission). Restaurado symlink `eco-woodly.md`; creado symlink `eco-alfredo-ecomm.md`.

## 2026-09-05

### [17:00] - Alfredo Pro Ecomm: nuevo backend ERP + integración con Woodly
- **Tipo**: infra | proyecto | backend | docker
- **Modificado**: `~/projects/alfredo-pro-ecomm/` + `~/projects/woodly/` (frontend)
- **Afecta a**: kalimete, vps-preprod
- **Causa**: Necesitamos backend propio para e-commerce multi-tenant (antes el API era de terceros FlowHub)
- **Estado**: ✅ Backend operativo en Docker (API :3004, Postgres:5432, Redis:6379)
- **Notas**: 
  - Backend completo: stores, products, carts, orders, customers, deals, admin panel
  - Woodly adaptado: api.ts, StoreContext, CartContext → consume API en lugar de mocks
  - Puertos: API→3004, DB→5432, Redis→6379
  - Próximo despliegue: VPS (dockerizado + reverse proxy por Caddy)
  - Documentación: `~/projects/alfredo-pro-ecomm/docs/DESIGN.md`, flowhub API de referencia
  - Dockerfile del ERP: postgres + redis + api (HEALTHCHECK incluídos)
  - Test local (y credenciales para demo):
    - Store slug: "woodly-park" — tenant de prueba
    - Admin: admin@woodly.armada.do / admin123
    - Customer: juan@example.com / password123
  - Endpoint `GET /v1/stores/woodly-park/config` added
  - Cart: create + add items + update + submit dedicado a cada tenant
  - Carnoversión frontend: http://localhost:5174/
  - Frontend changes:
    - `src/services/api.ts` (nuevo)
    - `src/context/StoreContext.tsx` (nuevo)
    - `src/hooks/useProducts.ts` (nuevo)
    - `mockProducts.ts` (legacy — reemplazado por API)
    - `CartDrawer.tsx` — actualizado con submit vía API
    - `App.tsx` — actualizado con provider StoreContext
  - El framework base en el frontend es referencia para futuros tenants (micaserogou, wisp, etc.)
  - Ruta en Docker: alfredo-ecomm-api (contenedor) — expone puerto 3004
  - Proyectos verificados corren sobre: npm run dev; docker compose up -d

---

## 2026-09-03
- **Tipo**: proyecto | plugin | wordpress | api
- **Modificado**: `/home/warcold/dev/wordpress/wp-content/plugins/erpecomm-alfredo-pro/`
- **Afecta a**: kalimete (WordPress local, localhost:8090)
- **Causa**: Validar login/registro de usuarios — el usuario creía que el ERPipos tenía endpoints de auth
- **Estado**: ✅ flujo completo funcionando
- **Hallazgos críticos del ERPipos (erpipos.armada.do)**:
  - ❌ NO existen endpoints de auth (login/register = 404 en todas las variantes probadas)
  - ✅ Existe `POST /erpipos/v3/customers` (crear cliente) — pero está **ROTO**: `EcommController::customerCreate` (línea 252) inserta `tenant_id=0` → FK violation. El middleware TenantMiddleware no resuelve el tenant en ese método.
  - ✅ `GET /erpipos/v3/customers` funciona pero devuelve lista vacía (mismo problema de tenant)
  - ✅ `checkout_guest` SÍ funciona: crea cliente automáticamente (confirmado: cliente_id 56, 59 de pruebas)
  - ⚠️ El ERP tiene `APP_DEBUG=true` — expone stack traces completos con SQL y rutas internas (riesgo de seguridad en producción, notificar al dueño)
- **Solución implementada en el plugin**:
  - Registro/login = WordPress nativo (`users_can_register=1` habilitado)
  - Al hacer checkout logueado: se guarda `magantech_cliente_id` (del ERP) en user_meta de WP
  - Teléfono/dirección guardados en user_meta (`magantech_phone`, `magantech_address`) → pre-fill en próximos checkouts
  - Historial de pedidos por usuario en `magantech_orders` (la API no expone historial por cliente)
  - Nuevo shortcode `[flowapi_mi_cuenta]` + página /mi-cuenta/ (perfil + pedidos + badge de cliente ERP)
  - Nav actualizada: Mi Cuenta/Salir si logueado, Login/Registrate si no
- **Pruebas realizadas (todas ✅)**:
  - Registro usuario WP (cliente.prueba) → login OK
  - Checkout logueado → ERP crea cliente_id:59 → vinculado a WP user 4
  - Mi Cuenta muestra el pedido con total correcto (RD$640)
- **Pendiente al dueño del ERP**: arreglar `EcommController::customerCreate` (usar tenant del middleware) y desactivar APP_DEBUG

EOF又是

## 2026-09-03

### [00:55] - MaganTech Store v2.0: llave API corregida + plugin e-commerce completo
- **Tipo**: proyecto | plugin | wordpress
- **Modificado**: `/home/warcold/dev/wordpress/wp-content/plugins/erpecomm-alfredo-pro/` (v1.0.0 → v2.0.0)
- **Afecta a**: kalimete (WordPress local, localhost:8090)
- **Causa**: MaganTech tenía API key errónea; inventario de 400 productos requería paginación + búsqueda + carrito + checkout funcional
- **Estado**: ✅ completado y probado end-to-end
- **Detalles**:
  - API key reemplazada: `iak_hT0RO7VnY2UpPT9q0tbqdfgEaTgkEQRYoeQGTaDM` (backup en `flowapi-ecommerce.php.bkup` dentro del contenedor)
  - Paginación AJAX de 15 productos + botón "Cargar más" (API de MaganTech no soporta paginación nativa — se pagina en PHP)
  - Buscador con parámetro `?buscar=` (evita colisión con WP search nativo `?s=`)
  - Carrito persistente vía **cookie** (sessions PHP rotas en contenedor: `session.save_path` vacío)
  - Checkout guest probado contra ERP: creó `cliente_id:56`, pedido registrado OK
  - Template engine corregido (ahora respeta `wp_head()`/`wp_footer()` para cargar assets)
  - URLs del sitio corregidas a `http://localhost:8090`
  - Páginas: /productos/ [flowapi_productos], /carrito/ [flowapi_carrito], /checkout/ [flowapi_checkout]
- **Limitaciones encontradas en API MaganTech**:
  - No hay endpoints de auth (/auth/login, /auth/register → 404). Usuarios = WordPress nativo.
  - Sin parámetros limit/page — devuelve los 400 productos siempre
  - /tienda/categorias devuelve HTML (Laravel view), no JSON — select de categorías queda pendiente
  - Varios productos tienen precio RD$ 0.00 (dato del ERP, no bug del plugin)
  - `"No hay usuarios activos en la instancia"` en algunas respuestas (config del ERP MaganTech)


## 2026-09-02

### [01:00] - Restaurar acceso SSH de justin_t en vps-preprod (llave ED25519)
- **Tipo**: infra | servicio | acceso
- **Modificado**: vps-preprod (154.53.35.102) — `/home/justin_t/.ssh/` (generada `id_ed25519` + `id_ed25519.pub`, agregada a `authorized_keys`)
- **Afecta a**: justin_t (usuario sudo en vps-preprod)
- **Causa**: justin_t no podía entrar por SSH. La llave en `authorized_keys` era RSA (`andrew.ortega@gmail.com`) pero él se autenticaba antes con una ED25519 (`SHA256:6uBP5yJDEUpz+3Vo426sQ9AYNbUmMk87lMp6E1hsdfM`) que fue removida. Desde el 1 Sep sus conexiones se cerraban en preauth.
- **Estado**: ✅ resuelto — nueva llave ED25519 generada, agregada a authorized_keys, conexión verificada (justin_t + sudo OK)
- **Notas**:
  - Nueva llave: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcKPc5rVP0GxPXXo/77eYY4RPdZj42nz50aKrtt8MKc justin_t@auth.armada.do`
  - Host para SSH remoto: **NO usar `auth.armada.do`** (proxied por Cloudflare, bloquea SSH). Usar IP directa `154.53.35.102 -p 1333`
  - La llave privada se entregó al usuario para que la instale en su máquina

## 2026-09-01

### [22:00] - Fix CRÍTICO: Squid crasheaba con `store.cc:1911` — deshabilitar caché
- **Tipo**: infra | servicio | bugfix crítico
- **Modificado**: vps-proxy (31.220.102.176) — /etc/squid/squid.conf (deshabilitado cache_dir ufs, agregado `cache deny all`), permisos proxy-users.conf
- **Afecta a**: vps-proxy (proxy server), todos los clientes del proxy
- **Causa**: Squid crasheaba **9 veces** con `FATAL: assertion failed: store.cc:1911: "sd"` (bug del sistema de caché). Cada crash causaba que el proxy "se cayera" y el servicio SOCKS5 se reiniciaba constantemente (342 veces). El usuario reportaba caídas frecuentes.
- **Estado**: ✅ resuelto — sin crashes desde el fix
- **Notas**:
  - **Causa raíz**: el caché de Squid (cache_dir ufs) tiene un bug (`store.cc:1911: "sd"`) que causa crashes aleatorios. Un proxy no necesita caché, así que se deshabilitó por completo.
  - **Fix**: eliminado `cache_dir ufs` y agregado `cache deny all` — sin caché = sin bug
  - **Resultado**: SOCKS5 ya no se reinicia constantemente, Squid estable, Gmail 0.08s, Google 0.00s, SOCKS5 Gmail 0.10s
