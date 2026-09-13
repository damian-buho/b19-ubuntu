<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
SPDX-License-Identifier: MIT
pf-cli-managed: yes
-->

<!-- textlint-disable terminology,common-misspellings -->

[English](../../README.md) · [Українська](../uk/README.md)

# B19 / Ubuntu

Imagen base Ubuntu mantenida por la comunidad para la flota B19

[![Stand with Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://damian-buho.github.io/support-ukraine/) [![Projectfile inside](https://badges.kiota.ch/static/v1?label=projectfile&message=inside&labelColor=0d0d0d&color=8c6723&style=flat-square)](https://projectfile.org) [![License](https://badges.kiota.ch/static/v1?label=license&message=MIT&color=1e5913&style=flat-square)](LICENSE) ![Commit style](https://badges.kiota.ch/static/v1?label=commits&message=conventional&color=1877aa&style=flat-square) ![Workflow](https://badges.kiota.ch/static/v1?label=workflow&message=git-flow&color=1877aa&style=flat-square) ![Versioning](https://badges.kiota.ch/static/v1?label=versioning&message=semantic&color=1877aa&style=flat-square) [![PRs welcome](https://badges.kiota.ch/static/v1?label=PRs&message=welcome&color=1e5913&style=flat-square)](CONTRIBUTING.md) [![Citation](https://badges.kiota.ch/static/v1?label=citation&message=cff&color=1877aa&style=flat-square)](CITATION.cff) [![REUSE compliance](https://api.reuse.software/badge/codeberg.org/b19/ubuntu)](https://api.reuse.software/info/codeberg.org/b19/ubuntu)

![Project status](https://badges.kiota.ch/static/v1?label=status&message=maintained&color=1d63ed&style=flat-square) [![Last commit on kiota.ch](https://badges.kiota.ch/gitea/last-commit/b19/ubuntu?gitea_url=https://kiota.ch&style=flat-square)](https://kiota.ch/b19/ubuntu)

[![Publish pipeline on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/published.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Vulnerability audit on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/audited.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Dependency freshness on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/check-outdated.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Analysis sweep on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/analyze.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions)

## Características

- Caché APT persistente entre compilaciones
- Gestión de procesos de servicio con enrutado de logs (b19-exec)
- Descargas de artefactos con caché y verificación de integridad (b19-fetch)
- Ejecución de comandos temporizada con informe de fallos (b19-run)
- Inicialización de una sola vez (bootstrap.d)
- Hooks de compilación modulares (build.d)
- Detección automática del número de CPUs (NUMPROCS)
- Gestión declarativa de dependencias (b19-deps)
- Sistema de arranque conectable (entrypoint.d)
- Conmutadores de funcionalidades para todos los subsistemas
- Monitorización de estado integrada (healthcheck.d)
- Salida de shell multilingüe (b19-i18n)
- Seguimiento del linaje de la imagen
- Logging estructurado con filtro por nivel (b19-log)
- Contenedor sin privilegios de root por defecto
- Soporte de compilación y runtime aislados de internet (air-gapped/offline)
- Inyección de overlays en runtime
- Imagen base reproducible (fijada por digest)
- Validación de puertos
- Familia unificada de runners del ciclo de vida
- Autocarga de secretos de Docker (secrets)
- Hooks de shell interactivo (shell.d)
- Gestión elegante de señales
- Plantillas de configuración Jinja2 (minijinja-cli)
- Framework de tests integrado (test.d)
- Herramientas de utilidad preinstaladas
- Rutas XDG Base Directory

Consulta [FEATURES.md](FEATURES.md) para ver la lista completa.

## Qué entrega este proyecto

- **Imagen de contenedor** `ghcr.io/damian-buho/b19/ubuntu/resolute:latest`
- **Imagen de contenedor** `ghcr.io/damian-buho/b19/ubuntu/noble:latest`
- **Imagen de contenedor** `docker.io/damianbuho/b19-ubuntu-resolute:latest`
- **Imagen de contenedor** `docker.io/damianbuho/b19-ubuntu-noble:latest`

## Plataformas admitidas

- `linux/amd64`
- `linux/arm64`
- `linux/riscv64`

## Instalación

Descarga la imagen de contenedor publicada:

### Descargar de GHCR

```sh
docker pull ghcr.io/damian-buho/b19/ubuntu/resolute:latest
docker pull ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### Descargar de DockerHub

```sh
docker pull docker.io/damianbuho/b19-ubuntu-resolute:latest
docker pull docker.io/damianbuho/b19-ubuntu-noble:latest
```

Las versiones estables también publican las etiquetas `X.Y.Z`, `X.Y` y `X`: descarga el nivel de precisión que quieras fijar.

Si los registros anteriores no están disponibles, descarga desde el origen:

### Descargar de Kiota

```sh
docker pull kiota.ch/b19/ubuntu/resolute:latest
docker pull kiota.ch/b19/ubuntu/noble:latest
```

## Uso

Construye sobre esta imagen:

### Desde GHCR

```dockerfile
FROM ghcr.io/damian-buho/b19/ubuntu/resolute:latest
FROM ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### Desde DockerHub

```dockerfile
FROM docker.io/damianbuho/b19-ubuntu-resolute:latest
FROM docker.io/damianbuho/b19-ubuntu-noble:latest
```

Para el patrón multietapa recomendado y el sistema de hooks de compilación (build.d), genera un derivado con `b19/scripts/scaffold.sh` de [m6e/b19](https://kiota.ch/m6e/b19).

## Compilación

- [Referencia del Makefile](../how-to/MAKEFILE.md)

Ejecuta `make` sin argumentos para el destino predeterminado; ejecuta `make help` para listar todos los destinos.

Para el bucle de desarrollo local, `make dev-container` levanta el dev-container.

Puntos de entrada de la canalización:

- `make analyze` — Run the heavy analysis sweep (mutation testing, benchmarks)
- `make audited` — Re-scan the pinned dependencies and published artifacts for new vulnerabilities
- `make check-outdated` — Report every pinned dependency that lags upstream
- `make ready-to-publish` — Run the pseudo-CI pipeline locally — build, test and scan, without publishing

## Documentación

- [Configure the image environment](../how-to/configure-environment.md)
- [Use the APT cache](../how-to/use-apt-cache.md)
- [Manage long-running processes with b19-exec](../how-to/use-b19-exec.md)
- [Download files with b19-fetch](../how-to/use-b19-fetch.md)
- [Log with b19-log](../how-to/use-b19-log.md)
- [Run commands with b19-run](../how-to/use-b19-run.md)
- [Initialize state once with bootstrap.d](../how-to/use-bootstrap.d.md)
- [Build images with build.d hooks](../how-to/use-build.d.md)
- [Use NUMPROCS CPU detection](../how-to/use-cpu-detection.md)
- [Declare dependencies](../how-to/use-dependencies.md)
- [Start containers with entrypoint.d](../how-to/use-entrypoint.d.md)
- [Write healthchecks](../how-to/use-healthcheck.d.md)
- [Translate strings with b19-i18n](../how-to/use-i18n.md)
- [Track image lineage](../how-to/use-lineage.md)
- [Run as a non-root user](../how-to/use-non-root.md)
- [Run offgrid builds](../how-to/use-offgrid.md)
- [Ship files with overlays](../how-to/use-overlays.md)
- [Build on the pinned base](../how-to/use-pinned-base.md)
- [Validate ports](../how-to/use-port-validation.md)
- [Use the runner family](../how-to/use-runner-family.md)
- [Load secrets](../how-to/use-secrets.md)
- [Enhance interactive shells](../how-to/use-shell-hooks.md)
- [Handle signals gracefully](../how-to/use-signals.md)
- [Render templates with minijinja](../how-to/use-templating.md)
- [Test images with test.d](../how-to/use-test.d.md)
- [Use the tools](../how-to/use-tools.md)
- [Use the XDG paths](../how-to/use-xdg-paths.md)

## Políticas

- [Cómo contribuir](CONTRIBUTING.md)
- [Política de seguridad](SECURITY.md)
- [Cómo obtener ayuda](SUPPORT.md)
- [Código de conducta](CODE_OF_CONDUCT.md)
- [Política sobre IA y LLM](AI_POLICY.md)

## Enlaces

- [Especificación de Projectfile](https://projectfile.org)

## Licencia

Este proyecto se publica bajo la licencia MIT — consulta el archivo [LICENSE](LICENSE) para más detalles.

<!-- textlint-enable -->
