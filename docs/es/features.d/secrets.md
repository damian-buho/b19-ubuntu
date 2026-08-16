<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Autocarga de secretos de Docker (secrets)

- Los archivos de secretos de Docker se autodescubren y convierten en variables de entorno al arrancar.
- Los nombres de archivo en notación de puntos se mapean a variables de entorno en mayúsculas (`b19.npm.registry_host` se convierte en `B19_NPM_REGISTRY_HOST`).
- Los secretos requeridos pueden declararse por nombre; el contenedor se niega a arrancar si falta alguno.
- Las variables de entorno existentes tienen precedencia sobre los valores derivados de secretos.
- Los secretos también están disponibles en sesiones de shell interactivas y en healthchecks.
- Los secretos no UTF-8/binarios (claves, blobs DER, tarballs comprimidos con gzip) **no** se exportan como variables de entorno: Bash los trunca en el primer NUL y los bytes sueltos hacen fallar a cualquier herramienta que lea el entorno como UTF-8 (p. ej., `minijinja --env`, usado para plantillar configuraciones). Permanecen en disco en `/run/secrets/<name>` para lecturas basadas en archivo — que, de todos modos, es la única forma correcta de consumir un secreto binario.

<!-- textlint-enable -->
