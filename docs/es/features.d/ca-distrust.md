<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Autoridades de certificación comprometidas desconfiadas antes que upstream

- Los certificados listados por huella SHA-256 se eliminan del almacén de confianza del sistema durante la construcción, antes de que la distribución publique su propia corrección.
- Una sola lista sirve a todo el linaje de imágenes, y `b19-ca-distrust bundle` recorta con ella cualquier paquete PEM incluido.
- Incluye la desconfianza de los intermedios de eMudhra cuyas claves privadas pueden recuperarse (octubre de 2026), junto con sus firmas cruzadas y raíces.
- Las imágenes derivadas añaden huellas con una variable o un archivo, y `B19_CA_DISTRUST_ENABLED=false` desactiva el recorte. [Guía](../how-to/use-ca-distrust.md)

<!-- textlint-enable -->
