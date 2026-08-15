<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Detección automática del número de CPUs (NUMPROCS)

- Las CPUs disponibles se detectan automáticamente con la downward API de Kubernetes, cgroups v2 o `nproc` como respaldo.
- El recuento detectado está disponible como `NUMPROCS` durante toda la compilación y el runtime, y se usa para compilación paralela, renderizado de plantillas y ejecución de tests.
- Elimina los recuentos de jobs hardcodeados y garantiza un paralelismo consistente entre Docker, Kubernetes y CI.
