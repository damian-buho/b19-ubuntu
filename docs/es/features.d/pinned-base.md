<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Imagen base reproducible (fijada por digest)

- La imagen base de Ubuntu está fijada por digest SHA-256, no por tag, lo que garantiza compilaciones deterministas.
- Admite varias series de Ubuntu (resolute, noble, opcionales: jammy, questing) seleccionables en tiempo de compilación.
- Los mirrors de APT son configurables por arquitectura para mirrors de LAN o entornos aislados.

<!-- textlint-enable -->
