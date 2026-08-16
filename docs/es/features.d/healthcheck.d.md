<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Monitorización de estado integrada (healthcheck.d)

- Healthcheck nativo de Docker declarado en la imagen base y heredado por todas las imágenes derivadas sin configuración extra.
- Siete comprobaciones de estado por defecto: espacio en disco de los directorios home, caché y temporales; conectividad HTTPS, resolución DNS, ping ICMP; y escribibilidad del sistema de archivos.
- Las comprobaciones de red son tolerantes a fallos: el éxito en cualquier objetivo cuenta como aprobado.
- Todas las comprobaciones de red se omiten automáticamente en modo offgrid; todas pueden desactivarse en runtime.
- Las imágenes derivadas añaden comprobaciones específicas del servicio (endpoints HTTP, conexiones a base de datos, vida del proceso) dejando caer scripts en un directorio.

<!-- textlint-enable -->
