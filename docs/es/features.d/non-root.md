<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Contenedor sin privilegios de root por defecto

- El contenedor se ejecuta como usuario sin privilegios de root (`ubuntu`, UID/GID 1000) con todos los archivos de runtime en propiedad de ese usuario.
- Una compilación en dos etapas separa la instalación del sistema a nivel root de la configuración del runtime a nivel de usuario.
- La identidad del usuario es configurable en tiempo de compilación.
