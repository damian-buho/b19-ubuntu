<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Soporte de compilación y runtime aislados de internet (air-gapped/offline)

- Una única variable de entorno (`B19_OFFGRID_MODE=Y`) corta todo acceso a internet en tiempo de compilación y en runtime.
- En compilación: se bloquean las descargas, se saltan las actualizaciones de APT y se saltan los keyscans de SSH. Todos los artefactos deben provenir de los niveles de caché.
- En runtime: las comprobaciones de estado de red se saltan automáticamente con resultado saludable, así los contenedores permanecen en verde en redes aisladas.
- Las listas de paquetes APT pueden capturarse como snapshot e inyectarse para compilaciones de imagen totalmente offline.
- Los servicios de LAN (proxies de caché, registros) siguen siendo accesibles: offgrid bloquea internet, no toda la red.

<!-- textlint-enable -->
