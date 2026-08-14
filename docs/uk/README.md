<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
SPDX-License-Identifier: MIT
pf-cli-managed: yes
-->

<!-- textlint-disable terminology,common-misspellings -->

[English](../../README.md) · [Español](../es/README.md)

# B19/Ubuntu

Community-maintained Ubuntu base image for the B19 fleet

[![Stand with Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://damian-buho.github.io/support-ukraine/) [![License](https://img.shields.io/static/v1?label=license&message=MIT&color=4c1&style=flat-square)](LICENSE) ![Commit style](https://img.shields.io/static/v1?label=commits&message=conventional&color=blue&style=flat-square) ![Workflow](https://img.shields.io/static/v1?label=workflow&message=git-flow&color=blue&style=flat-square) ![Versioning](https://img.shields.io/static/v1?label=versioning&message=semantic&color=blue&style=flat-square) [![PRs welcome](https://img.shields.io/static/v1?label=PRs&message=welcome&color=4c1&style=flat-square)](CONTRIBUTING.md) [![Citation](https://img.shields.io/static/v1?label=citation&message=cff&color=blue&style=flat-square)](CITATION.cff) [![REUSE compliance](https://api.reuse.software/badge/codeberg.org/b19/ubuntu)](https://api.reuse.software/info/codeberg.org/b19/ubuntu)

![Project status](https://img.shields.io/static/v1?label=status&message=maintained&color=1d63ed&style=flat-square) [![Last commit](https://img.shields.io/gitea/last-commit/b19/ubuntu?gitea_url=https://codeberg.org&style=flat-square)](https://codeberg.org/b19/ubuntu)

[![Build status on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/published.yaml/badge.svg)](https://kiota.ch/b19/ubuntu/actions)

## Можливості

- Persistent APT cache across builds
- Service process management with log routing (b19-exec)
- Cached artifact downloads with integrity verification (b19-fetch)
- Timed command execution with failure reporting (b19-run)
- Run-once initialization (bootstrap.d)
- Modular build hooks (build.d)
- Automatic CPU count detection (NUMPROCS)
- Declarative dependency management (b19-deps)
- Pluggable startup system (entrypoint.d)
- Feature toggles for all subsystems
- Built-in health monitoring (healthcheck.d)
- Multilingual shell output (b19-i18n)
- Image lineage tracking
- Structured, level-filtered logging (b19-log)
- Non-root container by default
- Air-gapped / offline build and runtime support
- Runtime overlay injection
- Reproducible base image (pinned by digest)
- Port validation
- Unified lifecycle runner family
- Docker secrets auto-loading (secrets)
- Interactive shell hooks (shell.d)
- Graceful signal handling
- Jinja2 configuration templates (minijinja-cli)
- Built-in test framework (test.d)
- Pre-installed utility tools
- XDG Base Directory paths

Див. [FEATURES.md](../../FEATURES.md), щоб переглянути повний перелік.

## Що надає цей проєкт

- **Образ контейнера** `ghcr.io/damian-buho/b19/ubuntu/resolute:latest`
- **Образ контейнера** `ghcr.io/damian-buho/b19/ubuntu/noble:latest`
- **Образ контейнера** `docker.io/damianbuho/b19-ubuntu-resolute:latest`
- **Образ контейнера** `docker.io/damianbuho/b19-ubuntu-noble:latest`

## Підтримувані платформи

`linux/amd64`, `linux/arm64`, `linux/riscv64`

## Встановлення

Завантажте опублікований образ контейнера:

```sh
docker pull ghcr.io/damian-buho/b19/ubuntu/resolute:latest
```

Доступні варіанти: B19_UBUNTU_SERIES: resolute, noble

```sh
docker pull ghcr.io/damian-buho/b19/ubuntu/noble:latest
docker pull docker.io/damianbuho/b19-ubuntu-resolute:latest
docker pull docker.io/damianbuho/b19-ubuntu-noble:latest
```

Якщо наведені вище реєстри недоступні, завантажте з джерела:

```sh
docker pull kiota.ch/b19/ubuntu/resolute:latest
```

Доступні варіанти: B19_UBUNTU_SERIES: resolute, noble

```sh
docker pull kiota.ch/b19/ubuntu/noble:latest
```

## Використання

Побудуйте на основі цього образу:

```dockerfile
FROM ghcr.io/damian-buho/b19/ubuntu/resolute:latest
```

Доступні варіанти: B19_UBUNTU_SERIES: resolute, noble

```dockerfile
FROM ghcr.io/damian-buho/b19/ubuntu/noble:latest
FROM docker.io/damianbuho/b19-ubuntu-resolute:latest
FROM docker.io/damianbuho/b19-ubuntu-noble:latest
```

Для рекомендованого багатоетапного шаблону та системи хуків збірки (build.d) створіть похідний проєкт за допомогою `b19/scripts/scaffold.sh` з [m6e/b19](https://kiota.ch/m6e/b19).

## Збирання

- [Довідник із Makefile](../MAKEFILE.md)

Точки входу конвеєра:

- `make analyze` — Run the heavy analysis sweep (mutation testing, benchmarks)
- `make audited` — Re-scan the pinned dependencies and published artifacts for new vulnerabilities
- `make check-outdated` — Report every pinned dependency that lags upstream
- `make ready-to-publish` — Run the pseudo-CI pipeline locally — build, test and scan, without publishing

Виконайте `make` без аргументів для типової цілі; виконайте `make help`, щоб переглянути всі цілі.

Для локального циклу розробки `make dev-container` піднімає dev-container.

## Документація

- [b19-exec](../b19-exec.md)
- [b19-fetch](../b19-fetch.md)
- [b19-log](../b19-log.md)
- [b19-run](../b19-run.md)
- [bootstrap.d — Run-Once Initialization System](../bootstrap.d.md)
- [build.d — Build Hook System](../build.d.md)
- [B19 Deps System](../dependencies.md)
- [entrypoint.d — Container Startup System](../entrypoint.d.md)
- [Environment Variables](../environment.md)
- [healthcheck.d — Container Health Monitoring System](../healthcheck.d.md)
- [b19-i18n — Internationalization](../i18n.md)
- [Offgrid APT Audit](../offgrid-apt.md)
- [Offgrid Mode and Cache Switches](../offgrid.md)
- [Jinja2 Templating (minijinja)](../templating.md)
- [test.d — Container Test Framework](../test.d.md)

## Політики

- [Як зробити внесок](CONTRIBUTING.md)
- [Політика безпеки](SECURITY.md)
- [Як отримати підтримку](SUPPORT.md)
- [Кодекс поведінки](CODE_OF_CONDUCT.md)

## Посилання

### Проєкт

- [Специфікація Projectfile](https://projectfile.org)
- [B19/Ubuntu на Codeberg](https://codeberg.org/b19/ubuntu)
- [B19/Ubuntu на GitHub](https://github.com/damian-buho/b19-ubuntu)
- [B19/Ubuntu на kiota.ch](https://kiota.ch/b19/ubuntu)
- [Issues на Codeberg](https://codeberg.org/b19/ubuntu/issues)
- [Issues на GitHub](https://github.com/damian-buho/b19-ubuntu/issues)

### Інше

- [Від автора](https://dbuho.me)

## Ліцензія

Цей проєкт ліцензовано на умовах MIT — див. файл [LICENSE](LICENSE) для подробиць.

*Згенеровано з projectfile ([дізнатися як](https://projectfile.org/how-to/readme))*
<!-- textlint-enable -->
