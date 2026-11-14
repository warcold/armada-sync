# vr506_dominicana_2_0 — Mapa de Restore Funcional (2026-11-14)

> Estado: **FUNCIONAL** — track restaurado a distribución original, checksum correcto, servidor corriendo.
> Fecha: 2026-11-14 02:33 UTC (acServer fresh start con archivos correctos).

---

## 1. Estado actual del servidor (VPS: 154.53.35.102)

| Componente | Estado | Detalle |
|---|---|---|
| **acServer** | ✅ Running | PID 1508092, puertos 8082 (HTTP) + 9600 (game) |
| **Server Manager** | ✅ Running | Puerto 8772 (UI), 8773 (CM wrapper API) |
| **Evento activo** | ✅ Custom Race | RID `371cd0f4-3e56-416f-8e1f-235d2b9b336f` — Practice 30min, LOOP_MODE=1 |
| **Track en disco** | ✅ Original | `/srv/assetto-corsa/assetto/content/tracks/vr506_dominicana_2_0/` |
| **Zip de descarga** | ✅ Correcto | `https://nextcloud.armada.do/acdl/vr506_dominicana_2_0.zip?v=2` (146,221,589 B, 47 files) |
| **Checksum** | ✅ Coincide | acServer cargó archivos restaurados al arrancar 02:33:44 UTC |

---

## 2. Archivos clave en el servidor (track folder)

```
/srv/assetto-corsa/assetto/content/tracks/vr506_dominicana_2_0/
├── vr506_dominicana_2_0.kn5          # 220,863,735 B, md5 0aee1111bf2429ae806d9e6678c293a8 (señales intactas)
├── circu.kn5                          # 25,095 B (stub)
├── drag.kn5                           # 12,608 B
├── models_circu.ini                   # 137 B — MODEL_0=vr506_dominicana_2_0.kn5 + MODEL_1=circu.kn5
├── models_drag.ini                    # 136 B — MODEL_0=drag.kn5
├── surfaces.ini                       # 1,351 B (en circu/data/)
├── circu/                             # layout circu (ai/, data/, gen_map.*, map.png)
├── drag/                              # layout drag (vacío, solo dir)
├── extension/                         # CSP extension
├── ui/                                # UI + meta_data.json (downloadURL con ?v=2)
├── map.png                            # 72,396 B
├── readme.txt                         # 736 B
└── (NO hay .CORRUPTO, NO hay download/, NO vao-patch)
```

**Backups de lo eliminado (en `/srv/assetto-corsa/backups/vr506-20261110/`):**
- `vr506_dominicana_2_0.kn5.CORRUPTO` (220MB, md5 a2c39948 — kn5 renombrado durante sesión de señales)
- `old-stale-20261109.zip` (fuente del restore, 141,846,896 B, 61 files — incluía vao-patch + stub configs)
- `Config.ini.removed-20261114`, `Manifest.json.removed-20261114`, `patch_data_new.dat.removed-20261114`
- `vao-patch` (120,121,678 B en zip; 117,219,606 B suelto)

---

## 3. Zip de descarga (Nextcloud / Caddy)

| Ubicación | Tamaño | Files | Notas |
|---|---|---|---|
| `/var/lib/docker/volumes/nextcloud-stack_caddy_data/_data/acdl/vr506_dominicana_2_0.zip` | 146,221,589 B | 47 | **Actual** — creado desde track folder restaurado, `zip -d` eliminó vao-patch |
| URL pública | — | — | `https://nextcloud.armada.do/acdl/vr506_dominicana_2_0.zip?v=2` (cache-bust) |
| Caddy config | — | — | `/opt/nextcloud-stack/Caddyfile` líneas 26–29: `handle_path /acdl/*` |

> **Por qué `?v=2`**: Cloudflare cacheaba el zip viejo (TTL 4h, `cf-cache-status: HIT`). El origen ya servía el nuevo; `?v=2` forzó MISS → ahora cacheado con contenido correcto. Si se purga CF, se puede volver a URL limpia.

---

## 4. Configuración del evento (server_cfg.ini relevante)

```ini
[SERVER]
TRACK=vr506_dominicana_2_0
CONFIG_TRACK=circu
LOOP_MODE=1
PICKUP_MODE_ENABLED=1
HTTP_PORT=8082
MAX_CLIENTS=21
RACE_PIT_WINDOW_START=0
RACE_PIT_WINDOW_END=0
```

---

## 5. Procedimiento de RESTORE (si se rompe de nuevo)

### A. Restaurar track folder desde backup original
```bash
ssh vps-preprod "
cd /srv/assetto-corsa/assetto/content/tracks/
rm -rf vr506_dominicana_2_0
unzip -o /srv/assetto-corsa/backups/vr506-20261110/old-stale-20261109.zip -x '*/vao-patch*'
# Mover configs stub a backup si existen
mv vr506_dominicana_2_0/Config.ini vr506_dominicana_2_0/Config.ini.removed-$(date +%Y%m%d) 2>/dev/null || true
mv vr506_dominicana_2_0/Manifest.json vr506_dominicana_2_0/Manifest.json.removed-$(date +%Y%m%d) 2>/dev/null || true
mv vr506_dominicana_2_0/patch_data_new.dat vr506_dominicana_2_0/patch_data_new.dat.removed-$(date +%Y%m%d) 2>/dev/null || true
chown -R assetto:sftpgate vr506_dominicana_2_0
chmod -R g+w vr506_dominicana_2_0
"
```

### B. Recrear zip de descarga
```bash
ssh vps-preprod "
cd /srv/assetto-corsa/assetto/content/tracks
zip -r /var/lib/docker/volumes/nextcloud-stack_caddy_data/_data/acdl/vr506_dominicana_2_0.zip vr506_dominicana_2_0 -x '*/vao-patch*'
# Verificar
unzip -l /var/lib/docker/volumes/nextcloud-stack_caddy_data/_data/acdl/vr506_dominicana_2_0.zip | tail -3
"
```

### C. Actualizar DownloadURL en meta_data.json (si cambió el zip)
```bash
ssh vps-preprod "
curl -s -c /tmp/sm-cookie.txt -o /dev/null -d 'Username=admin&Password=colador' http://127.0.0.1:8772/login
curl -s -b /tmp/sm-cookie.txt -o /dev/null \
  --data-urlencode 'Notes=VR506 Dominicana 2.0 - Autodromo Las Americas (CSP patch track, 2 layouts: circu + drag). Free for personal use by VR506 Simulacion (vr506.gumroad.com).' \
  --data-urlencode 'DownloadURL=https://nextcloud.armada.do/acdl/vr506_dominicana_2_0.zip?v=2' \
  http://127.0.0.1:8772/track/vr506_dominicana_2_0/metadata
cat /srv/assetto-corsa/assetto/content/tracks/vr506_dominicana_2_0/ui/meta_data.json
"
```

### D. Reiniciar acServer (necesario para regenerar checksum)
```bash
ssh vps-preprod "
docker restart assetto-corsa-server
sleep 10
# Arrancar evento vía SM
curl -s -c /tmp/sm-cookie.txt -o /dev/null -d 'Username=admin&Password=colador' http://127.0.0.1:8772/login
curl -s -b /tmp/sm-cookie.txt http://127.0.0.1:8772/custom/load/371cd0f4-3e56-416f-8e1f-235d2b9b336f
sleep 5
docker logs assetto-corsa-server --since 10s | grep -E 'Starting Server|Loaded previous'
"
```

### E. Verificar
```bash
ssh vps-preprod "
ss -ltnp | grep -E '8082|8773|9600'
curl -s http://127.0.0.1:8773/api/details | jq -r '.content.track.url'
curl -sI 'https://nextcloud.armada.do/acdl/vr506_dominicana_2_0.zip?v=2' | grep -i content-length
"
```
Debe salir: `content-length: 146221589` y la URL con `?v=2`.

---

## 6. Puntos críticos (lecciones aprendidas)

1. **Checksum del acServer se computa UNA VEZ al arrancar** — los ciclos LOOP_MODE no recargan el track. Si cambias archivos en disco, **reinicia el contenedor** (o `docker restart assetto-corsa-server` + arrancar evento vía SM).

2. **Cloudflare cachea el zip** (TTL 4h). Si actualizas el zip, usa cache-bust `?v=N` en DownloadURL o purga CF (`POST /zones/:id/purge_cache` con token de cuenta).

3. **CM install no borra archivos viejos** — si el usuario tenía la versión rota instalada (con vao-patch, Config.ini, etc.), debe borrar la carpeta del track en su cliente antes de reinstalar.

4. **vao-patch NO va en el zip** — está diseñado para setup stub, no para kn5 completo. Excluir con `zip -d` o `-x '*/vao-patch*'`.

5. **models_circu.ini original = 137 B** (MODEL_0 + MODEL_1). El stub roto era 55 B (solo MODEL_0). El checksum usa este archivo + surfaces.ini.

---

## 7. Próximos pasos pendientes (tras confirmar que entra bien)

- [ ] `GET /custom/loop/371cd0f4-3e56-416f-8e1f-235d2b9b336f` — activar auto-loop
- [ ] Branding `logow` / `OBJ83_SUB1` (sin tocar texturas de señales)

---

## 8. Referencias rápidas

| Recurso | Comando / URL |
|---|---|
| SSH VPS | `ssh vps-preprod` (puerto 1333, root, pass `verganza`) |
| Track folder | `/srv/assetto-corsa/assetto/content/tracks/vr506_dominicana_2_0/` |
| Backups | `/srv/assetto-corsa/backups/vr506-20261110/` |
| Zip Caddy | `/var/lib/docker/volumes/nextcloud-stack_caddy_data/_data/acdl/` |
| SM UI | `https://assetto.armada.do` (admin / `colador`) |
| CM Wrapper API | `http://127.0.0.1:8773/api/details` |
| Logs acServer | `docker logs assetto-corsa-server` |
| Caddyfile | `/opt/nextcloud-stack/Caddyfile` |
| CHANGELOG | `~/armada-sync/CHANGELOG.md` (entrada 2026-11-13 21:11 EST) |