<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Logging estructurado con filtro por nivel (b19-log)

- Toda la salida del contenedor pasa por un logger con niveles y cuatro umbrales: error, warn, info, debug.
- Los mensajes por debajo de la verbosidad configurada se descartan silenciosamente, manteniendo limpios los logs de producción.
- Los colores autodetectan el soporte del terminal y respetan `NO_COLOR=1`.
- Encauzable: la salida de comandos puede enrutarse a través del logger para aplicar filtrado por nivel y tags.
