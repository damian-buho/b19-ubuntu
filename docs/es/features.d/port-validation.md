<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Validación de puertos

- Todas las variables de entorno `*PORT*` se validan al arrancar contra la lista de puertos prohibidos de WHATWG y contra los puertos privilegiados (\<1024).
- Detecta temprano configuraciones erróneas como `PORT=0` o `PORT=22`, antes de que el servicio falle en silencio.
- Puede desactivarse en runtime sin reconstruir la imagen.
