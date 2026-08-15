<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Conmutadores de funcionalidades para todos los subsistemas

- Cada subsistema mayor (entrypoint, healthchecks, bootstrap, tests, secrets, validación de puertos, i18n, shell hooks) puede desactivarse en runtime mediante variables de entorno.
- Los hooks individuales del entrypoint y del bootstrap pueden omitirse por nombre sin desactivar el subsistema entero.
- No hace falta reconstruir la imagen: los conmutadores son solo de runtime.
