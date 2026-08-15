<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Hooks de compilación modulares (build.d)

- Toda la lógica de compilación de la imagen vive en scripts de shell numerados en lugar de comandos `RUN` inline en el Dockerfile.
- Los hooks se organizan en fases `pre/on/post` y se autodescubren por el nombre de etapa pasado a `build-stage`.
- El ámbito reservado `always/{pre,post}` enmarca cada etapa, se llame como se llame, de modo que la configuración transversal se escribe una vez en lugar de por etapa.
- Los hooks heredables se propagan a las imágenes derivadas automáticamente vía superposición de capas de Docker: las derivadas obtienen gratis la lógica de compilación del padre.
- Los hooks no heredables se limpian tras su ejecución para evitar que se filtren en etapas posteriores.
