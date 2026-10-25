<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Gestión de procesos de servicio con enrutado de logs (b19-exec)

- Los procesos de larga duración (demonios, servidores) tienen stdout y stderr enrutados automáticamente a través del logger estructurado.
- Cada señal llega al servicio exactamente una vez, así `docker stop` lo termina de forma elegante y se conservan sus últimas líneas de log.
- Los niveles de log de los flujos stdout y stderr se configuran de forma independiente.
- Varios demonios comparten un contenedor: cada línea lleva la etiqueta de su demonio, se detienen en orden inverso al de arranque y un demonio obligatorio que falla detiene el contenedor para que actúe la política de reinicio.
- El modo passthrough entrega el log propio del servicio al recolector byte a byte, así los parsers hechos para ese demonio siguen coincidiendo.

<!-- textlint-enable -->
