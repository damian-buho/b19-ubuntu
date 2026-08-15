<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Inyección de overlays en runtime

- Se pueden inyectar archivos de configuración o datos al arrancar el contenedor estableciendo en `B19_OVERLAY` el nombre de un directorio.
- El contenido del overlay se copia recursivamente a la raíz del contenedor, sobrescribiendo los archivos existentes; no hace falta reconstruir la imagen.
- Se omite en modo inmutable, impidiendo la modificación en runtime de imágenes bloqueadas para producción.
