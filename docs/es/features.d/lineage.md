<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Seguimiento del linaje de la imagen

- Cada imagen registra sus metadatos de compilación (namespace, proyecto, versión, imagen base) en un archivo de linaje durante la compilación.
- Las imágenes derivadas encadenan el linaje de su padre, produciendo una cadena de procedencia completa desde la base hasta la actual.
- Al arrancar el contenedor se registra en el log toda la cadena de linaje, lo que facilita rastrear a partir de qué se construyó un contenedor en ejecución.

<!-- textlint-enable -->
