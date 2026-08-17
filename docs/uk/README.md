<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
SPDX-License-Identifier: MIT
pf-cli-managed: yes
-->

<!-- textlint-disable terminology,common-misspellings -->

[English](../../README.md) · [Español](../es/README.md)

# B19/Ubuntu

Базовий образ Ubuntu з підтримкою спільноти для флоту B19

[![Stand with Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://damian-buho.github.io/support-ukraine/) [![License](https://img.shields.io/static/v1?label=license&message=MIT&color=4c1&style=flat-square)](LICENSE) ![Commit style](https://img.shields.io/static/v1?label=commits&message=conventional&color=blue&style=flat-square) ![Workflow](https://img.shields.io/static/v1?label=workflow&message=git-flow&color=blue&style=flat-square) ![Versioning](https://img.shields.io/static/v1?label=versioning&message=semantic&color=blue&style=flat-square) [![PRs welcome](https://img.shields.io/static/v1?label=PRs&message=welcome&color=4c1&style=flat-square)](CONTRIBUTING.md) [![Citation](https://img.shields.io/static/v1?label=citation&message=cff&color=blue&style=flat-square)](CITATION.cff) [![REUSE compliance](https://api.reuse.software/badge/codeberg.org/b19/ubuntu)](https://api.reuse.software/info/codeberg.org/b19/ubuntu)

![Project status](https://img.shields.io/static/v1?label=status&message=maintained&color=1d63ed&style=flat-square) [![Last commit](https://img.shields.io/gitea/last-commit/b19/ubuntu?gitea_url=https://codeberg.org&style=flat-square)](https://codeberg.org/b19/ubuntu)

[![Build status on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/published.yaml/badge.svg)](https://kiota.ch/b19/ubuntu/actions)

## Можливості

- Постійний APT-кеш між збираннями
- Керування службовими процесами зі спрямуванням журналів (b19-exec)
- Кешовані завантаження артефактів із перевіркою цілісності (b19-fetch)
- Вимірюване виконання команд зі звітуванням про збої (b19-run)
- Одноразова ініціалізація (bootstrap.d)
- Модульні хуки збирання (build.d)
- Автоматичне визначення кількості CPU (NUMPROCS)
- Декларативне керування залежностями (b19-deps)
- Підключована система запуску (entrypoint.d)
- Перемикачі функцій для всіх підсистем
- Вбудований моніторинг стану (healthcheck.d)
- Багатомовний вивід shell (b19-i18n)
- Відстеження лініжу образу
- Структуроване журналування з фільтром за рівнем (b19-log)
- Контейнер без прав root за замовчуванням
- Підтримка ізольованих від інтернету (air-gapped/offline) збирання й виконання
- Ін’єкція оверлеїв під час виконання
- Відтворюваний базовий образ (зафіксований за digest)
- Перевірка портів
- Уніфіковане сімейство ранерів життєвого циклу
- Автозавантаження Docker-секретів (secrets)
- Хуки інтерактивної shell (shell.d)
- Плавна обробка сигналів
- Шаблони конфігурації Jinja2 (minijinja-cli)
- Вбудований тестовий фреймворк (test.d)
- Попередньо встановлені службові інструменти
- Шляхи XDG Base Directory

Див. [FEATURES.md](FEATURES.md), щоб переглянути повний перелік.

## Що надає цей проєкт

- **Образ контейнера** `ghcr.io/damian-buho/b19/ubuntu/resolute:latest`
- **Образ контейнера** `ghcr.io/damian-buho/b19/ubuntu/noble:latest`
- **Образ контейнера** `docker.io/damianbuho/b19-ubuntu-resolute:latest`
- **Образ контейнера** `docker.io/damianbuho/b19-ubuntu-noble:latest`

## Підтримувані платформи

`linux/amd64`, `linux/arm64`, `linux/riscv64`

## Встановлення

Завантажте опублікований образ контейнера:

### Завантажити з GHCR

```sh
docker pull ghcr.io/damian-buho/b19/ubuntu/resolute:latest
docker pull ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### Завантажити з DockerHub

```sh
docker pull docker.io/damianbuho/b19-ubuntu-resolute:latest
docker pull docker.io/damianbuho/b19-ubuntu-noble:latest
```

Якщо наведені вище реєстри недоступні, завантажте з джерела:

### Завантажити з Kiota

```sh
docker pull kiota.ch/b19/ubuntu/resolute:latest
docker pull kiota.ch/b19/ubuntu/noble:latest
```

## Використання

Побудуйте на основі цього образу:

### З GHCR

```dockerfile
FROM ghcr.io/damian-buho/b19/ubuntu/resolute:latest
FROM ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### З DockerHub

```dockerfile
FROM docker.io/damianbuho/b19-ubuntu-resolute:latest
FROM docker.io/damianbuho/b19-ubuntu-noble:latest
```

Для рекомендованого багатоетапного шаблону та системи хуків збірки (build.d) створіть похідний проєкт за допомогою `b19/scripts/scaffold.sh` з [m6e/b19](https://kiota.ch/m6e/b19).

## Збирання

- [Довідник із Makefile](../how-to/MAKEFILE.md)

Точки входу конвеєра:

- `make analyze` — Run the heavy analysis sweep (mutation testing, benchmarks)
- `make audited` — Re-scan the pinned dependencies and published artifacts for new vulnerabilities
- `make check-outdated` — Report every pinned dependency that lags upstream
- `make ready-to-publish` — Run the pseudo-CI pipeline locally — build, test and scan, without publishing

Виконайте `make` без аргументів для типової цілі; виконайте `make help`, щоб переглянути всі цілі.

Для локального циклу розробки `make dev-container` піднімає dev-container.

## Документація

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
