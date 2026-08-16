<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Sistema de arranque conectable (entrypoint.d)

- Cada arranque de contenedor pasa por una secuencia de hooks numerados: configuración de señales, carga de secretos, detección de CPU, validación de puertos, renderizado de plantillas, bootstrap y arranque del servicio.
- Los comandos ad hoc (`docker run img command`) saltan automáticamente parte de la cadena de arranque y se ejecutan directamente.
- Tanto los hooks individuales como el entrypoint completo pueden omitirse en runtime mediante variables de entorno, sin reconstruir la imagen.
- Las imágenes derivadas sobrescriben un único hook (slot 5000) para lanzar su servicio; todo lo demás se hereda.

<!-- textlint-enable -->
