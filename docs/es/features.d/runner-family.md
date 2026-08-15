<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Familia unificada de runners del ciclo de vida

- Ocho runners de hooks numerados cubren el ciclo de vida completo del contenedor: arranque, healthchecks, tests, bootstrap, hooks de compilación, benchmarks, reports y sesiones de shell.
- Todos los runners comparten el mismo patrón: deja caer un script numerado en un directorio y se autodescubre y ejecuta.
- Los scripts de distintas capas de imagen se mezclan: los hooks upstream y los derivados coexisten sin conflicto.
- Cada runner tiene semántica de fallo a medida: abortar ante error (entrypoint, bootstrap), continuar y contar fallos (healthchecks, tests), tener siempre éxito (reports).
