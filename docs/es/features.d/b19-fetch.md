<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Descargas de artefactos con caché y verificación de integridad (b19-fetch)

- Todas las descargas externas pasan por una caché de tres niveles: directorio local `.fetch/`, caché persistente de BuildKit y luego upstream vía aria2c con hasta 16 conexiones.
- Verificación SHA-512 opcional en cada nivel; un hash que no coincide provoca caída al siguiente nivel en lugar de fallo.
- El modo offgrid bloquea todas las descargas por completo, fallando rápido con un error claro si se produce un fallo de caché.
- Admite un proxy de near-cache para compilaciones solo-LAN que pasan por un proxy de caché.
