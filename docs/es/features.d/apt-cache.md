<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Caché APT persistente entre compilaciones

- Las cachés de paquetes e índices de APT sobreviven entre compilaciones mediante montajes de caché de BuildKit, con clave por serie de Ubuntu y arquitectura.
- Las compilaciones repetidas reutilizan los paquetes descargados en lugar de volver a descargarlos.
- Proxy opcional de caché APT en LAN, se activa con `M6E_APT_CACHE_HOST`.

<!-- textlint-enable -->
