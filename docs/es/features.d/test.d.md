<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Framework de tests integrado (test.d)

- Los tests se ejecutan dentro del contenedor en marcha vía `make test` o `docker exec`.
- Espera automáticamente a que pasen los healthchecks antes de ejecutar.
- Sin dependencia de ningún framework de tests: los tests son scripts de shell simples con códigos de salida.
- Admite plantillas Jinja2 en los tests, útil para afirmar en runtime valores fijados en compilación.
- Continúa ante fallos e informa del recuento total; nunca oculta resultados parciales.

<!-- textlint-enable -->
