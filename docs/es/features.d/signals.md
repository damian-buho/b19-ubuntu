<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Gestión elegante de señales

- El PID 1 es `tini -g`, que recoge los procesos zombi y reenvía señales a todo el grupo de procesos.
- Un conjunto configurable de señales Unix (TERM, INT, HUP, USR1, USR2, etc.) se captura y reenvía al proceso principal del servicio.
- `docker stop` termina limpiamente el servicio sin procesos huérfanos ni pérdida de señales.
