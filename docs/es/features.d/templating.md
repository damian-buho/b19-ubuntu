<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Plantillas de configuración Jinja2 (minijinja-cli)

- Renderizado de plantillas compatible con Jinja2 tanto en tiempo de compilación como al arrancar el contenedor.
- Deja caer un archivo `.j2` en cualquier parte del directorio de la aplicación; se descubre en tiempo de compilación y se renderiza en cada arranque con todas las variables de entorno disponibles.
- El renderizado en runtime es paralelo y automático: las imágenes derivadas lo obtienen sin configuración alguna.
- El modo inmutable (`B19_IMMUTABLE=Y`) congela el sistema de archivos en el estado de compilación, saltándose todo renderizado en runtime.
