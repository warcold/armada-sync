# Go — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `go version` → go1.26.6 linux/arm64)
> **Docs oficiales**: https://go.dev/doc/ + https://pkg.go.dev/

## Versiones en uso

- Go 1.26.6 ARM64 en `/usr/local/go` (host victoria) — compilación del blogwatcher
- Blogwatcher: v0.0.4 (source `github.com/Hyaxia/blogwatcher`), binario estático ARM64 13.9MB

## Patrones que usamos

- **Build estático sin CGO**: `CGO_ENABLED=0 go build -ldflags="-s -w" -o <bin> ./cmd/<app>` — binario portable ARM64 (corre en cualquier Linux ARM64 sin deps)
- `modernc.org/sqlite` (SQLite pure-Go sin CGO) — el blogwatcher lo usa; sin libsqlite del sistema
- `embed.FS` para frontends embebidos (phoneinfoga pattern)

## Gotchas descubiertos (lecciones)

- **Releases upstream solo linux-amd64 prebuilt** (blogwatcher) — en ARM64 hay que compilar desde source SIEMPRE. — (CHANGELOG 2026-08-16)
- **Go http client + proxy MITM**: para salir por el proxy L7 del sandbox hace falta `SSL_CERT_FILE=/etc/openshell-tls/ca-bundle.pem` (CA pinada del proxy) o la validación TLS falla. — (CHANGELOG 2026-08-16)
- **`go build` con `-trimpath`** si el binario va a distribuirse (paths reproducibles).

## Regla de actualización

Go toolchain: actualizar solo si un proyecto lo exige (verificar `go.mod`).
Binarios: rebuild + backup del viejo + E2E antes de reemplazar en producción.
