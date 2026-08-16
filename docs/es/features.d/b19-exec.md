<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Gestión de procesos de servicio con enrutado de logs (b19-exec)

- Los procesos de larga duración (demonios, servidores) tienen stdout y stderr enrutados automáticamente a través del logger estructurado.
- Se hace seguimiento del PID del servicio para el reenvío de señales: Docker stop termina de forma elegante el proceso principal.
- Los niveles de log de los flujos stdout y stderr se configuran de forma independiente.
- El código de salida del servicio se captura y queda disponible para los hooks posteriores.

<!-- textlint-enable -->
