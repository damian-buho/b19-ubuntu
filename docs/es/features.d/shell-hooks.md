<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Hooks de shell interactivo (shell.d)

- Las sesiones `docker exec bash` cargan automáticamente los secretos de Docker y cualquier hook personalizado añadido por las imágenes derivadas.
- Los hooks se mezclan vía superposición de capas de Docker, así que la configuración de shell heredada y la específica del proyecto coexisten.

<!-- textlint-enable -->
