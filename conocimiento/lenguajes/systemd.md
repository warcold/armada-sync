# systemd — doc viva del ecosistema

> **Verificado**: 2026-10-27 (live: `systemctl --version` → 255)
> **Docs oficiales**: https://www.freedesktop.org/wiki/Software/systemd/ + `man systemd.unit`

## Versiones en uso

- systemd 255 (Ubuntu, host victoria) — ~20 units del stack
- User units en kalimete (`systemctl --user`, ej. kalimete-ptt)

## Patrones que usamos

- `Restart=always` + `StartLimitBurst=5/120s` en servicios críticos
- Drop-ins (`/etc/systemd/system/<svc>.service.d/*.conf`) para OOMScoreAdjust, reserve-vram — NUNKA editar el unit original si hay drop-in
- Timers con `Persistent=true` (armada-sync, crons de broadcast)
- `User=victoria` (no root) en todo lo que puede
- `loginctl enable-linger victoria` para user-services tras reboot (gateway openshell)

## Gotchas descubiertos (lecciones)

- **Units oneshot NUNCA con `After=multi-user.target`** — la cadena puede estar bloqueada (plymouth) y el unit nunca corre. — (CHANGELOG 2026-10-26)
- **plymouth-quit-wait deadlockea boots headless de esta imagen** — masked permanente (`plymouth-quit-wait` + `plymouth-start`). Ante systemctl colgado: `systemctl list-jobs` primero. — (CHANGELOG 2026-10-26)
- **`systemctl --user` en kalimete requiere sesión/linger** — kalimete-ptt corre como user unit; verificar `is-active` con `--user`. — (proyecto kalimete-ptt)
- **RuntimeWatchdogSec=180 en system.conf** — SBSA GWDT: kernel freeze → reboot automático en 3 min. NO cubre cortes de luz. — (AGENTS.md §4)
- **OOMScoreAdjust por drop-in** (-500 infra, -750 ssh) — el OOM killer ataca sacrificables primero. Verificar con `systemctl show`. — (CHANGELOG 2026-09-20)

## Regla de actualización

systemd del sistema: no tocar versiones. Units nuevos: drop-ins para overrides,
`daemon-reload` tras editar, y verificar con `systemctl is-active` + E2E.
