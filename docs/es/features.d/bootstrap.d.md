<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Inicialización de una sola vez (bootstrap.d)

- Las tareas de configuración únicas (migraciones de base de datos, creación del usuario administrador, init de directorios) se ejecutan solo en el primer arranque del contenedor.
- Idempotencia automática: los scripts completados no vuelven a ejecutarse jamás, ni siquiera entre reinicios del contenedor.
- Los scripts fallidos se reintentan en el siguiente arranque; los exitosos quedan bloqueados.
- El estado puede resetearse limpiando un volumen, lo que dispara un re-bootstrap completo.
- Las imágenes derivadas añaden sus propios scripts de init dejándolos caer en un directorio.
