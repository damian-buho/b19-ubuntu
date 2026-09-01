<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Monitorización de estado integrada (healthcheck.d)

- Healthcheck nativo de Docker heredado por todas las imágenes derivadas sin configuración extra.
- Las comprobaciones de salida son opcionales: un contenedor que nunca llega a internet no lleva ninguna comprobación que un tercero pueda hacer fallar, mientras que uno cuyo trabajo es internet se marca como no disponible en cuanto el exterior desaparece.
- Funciona igual sin conexión que en línea: las comprobaciones de salida se retiran automáticamente en modo offgrid.
- Añadir una comprobación es dejar caer un script en un directorio, no escribir configuración de Docker.

Consulte [use-healthcheck.d](../how-to/use-healthcheck.d.md) para la lista de comprobaciones, la numeración de slots y la configuración.

<!-- textlint-enable -->
