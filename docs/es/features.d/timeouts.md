<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Nada se cuelga para siempre

- Cada paso de arranque, prueba y comando puntual tiene un límite de tiempo, así que una herramienta bloqueada falla de forma visible en lugar de detener un despliegue o una ejecución de CI.
- Las descargas estancadas se abortan, mientras que las lentas de cualquier tamaño se completan.
- Una llamada inestable puede reintentarse con espera progresiva con una sola opción, sin escribir un bucle a mano.
- Un reinicio opcional convierte un servicio atascado en estado no saludable en un contenedor que la política de reinicio recupera.

Consulta [use-timeouts](../how-to/use-timeouts.md) para las opciones, los valores por defecto y cómo cambiarlos.

<!-- textlint-enable -->
