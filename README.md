<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
SPDX-License-Identifier: MIT
pf-cli-managed: yes
-->

[Español](docs/es/README.md) · [Українська](docs/uk/README.md)

# B19/Ubuntu

Community-maintained Ubuntu base image for the B19 fleet

[![Stand with Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://damian-buho.github.io/support-ukraine/) [![License](https://img.shields.io/static/v1?label=license&message=MIT&color=4c1&style=flat-square)](LICENSE) ![Commit style](https://img.shields.io/static/v1?label=commits&message=conventional&color=blue&style=flat-square) ![Workflow](https://img.shields.io/static/v1?label=workflow&message=git-flow&color=blue&style=flat-square) ![Versioning](https://img.shields.io/static/v1?label=versioning&message=semantic&color=blue&style=flat-square) [![PRs welcome](https://img.shields.io/static/v1?label=PRs&message=welcome&color=4c1&style=flat-square)](CONTRIBUTING.md) [![Citation](https://img.shields.io/static/v1?label=citation&message=cff&color=blue&style=flat-square)](CITATION.cff) [![REUSE compliance](https://api.reuse.software/badge/codeberg.org/b19/ubuntu)](https://api.reuse.software/info/codeberg.org/b19/ubuntu)

![Project status](https://img.shields.io/static/v1?label=status&message=maintained&color=1d63ed&style=flat-square) [![Last commit](https://img.shields.io/gitea/last-commit/b19/ubuntu?gitea_url=https://codeberg.org&style=flat-square)](https://codeberg.org/b19/ubuntu)

[![Build status on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/published.yaml/badge.svg)](https://kiota.ch/b19/ubuntu/actions)

## Features

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

See [FEATURES.md](FEATURES.md) for the full list.

## What this provides

- **Container image** `ghcr.io/damian-buho/b19/ubuntu/resolute:latest`
- **Container image** `ghcr.io/damian-buho/b19/ubuntu/noble:latest`
- **Container image** `docker.io/damianbuho/b19-ubuntu-resolute:latest`
- **Container image** `docker.io/damianbuho/b19-ubuntu-noble:latest`

## Supported platforms

`linux/amd64`, `linux/arm64`, `linux/riscv64`

## Installation

Pull the published container image:

### Pull from GHCR

```sh
docker pull ghcr.io/damian-buho/b19/ubuntu/resolute:latest
docker pull ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### Pull from DockerHub

```sh
docker pull docker.io/damianbuho/b19-ubuntu-resolute:latest
docker pull docker.io/damianbuho/b19-ubuntu-noble:latest
```

If the registries above are unreachable, pull from the origin instead:

### Pull from Kiota

```sh
docker pull kiota.ch/b19/ubuntu/resolute:latest
docker pull kiota.ch/b19/ubuntu/noble:latest
```

## Usage

Build on top of this image:

### From GHCR

```dockerfile
FROM ghcr.io/damian-buho/b19/ubuntu/resolute:latest
FROM ghcr.io/damian-buho/b19/ubuntu/noble:latest
```

### From DockerHub

```dockerfile
FROM docker.io/damianbuho/b19-ubuntu-resolute:latest
FROM docker.io/damianbuho/b19-ubuntu-noble:latest
```

For the recommended multi-stage pattern and the build-hook system (build.d), scaffold a derivative with `b19/scripts/scaffold.sh` from [m6e/b19](https://kiota.ch/m6e/b19).

## Building

- [Makefile reference](docs/MAKEFILE.md)

Pipeline entry points:

- `make analyze` — Run the heavy analysis sweep (mutation testing, benchmarks)
- `make audited` — Re-scan the pinned dependencies and published artifacts for new vulnerabilities
- `make check-outdated` — Report every pinned dependency that lags upstream
- `make ready-to-publish` — Run the pseudo-CI pipeline locally — build, test and scan, without publishing

Run `make` with no arguments for the default target; run `make help` to list every target.

For the local dev loop, `make dev-container` brings up the dev-container.

## Documentation

- [b19-exec](docs/b19-exec.md)
- [b19-fetch](docs/b19-fetch.md)
- [b19-log](docs/b19-log.md)
- [b19-run](docs/b19-run.md)
- [bootstrap.d — Run-Once Initialization System](docs/bootstrap.d.md)
- [build.d — Build Hook System](docs/build.d.md)
- [B19 Deps System](docs/dependencies.md)
- [entrypoint.d — Container Startup System](docs/entrypoint.d.md)
- [Environment Variables](docs/environment.md)
- [healthcheck.d — Container Health Monitoring System](docs/healthcheck.d.md)
- [b19-i18n — Internationalization](docs/i18n.md)
- [Offgrid Mode and Cache Switches](docs/offgrid.md)
- [Jinja2 Templating (minijinja)](docs/templating.md)
- [test.d — Container Test Framework](docs/test.d.md)

## Policies

- [How to contribute](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Getting support](SUPPORT.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## Links

### Project

- [Projectfile Specification](https://projectfile.org)
- [B19/Ubuntu on Codeberg](https://codeberg.org/b19/ubuntu)
- [B19/Ubuntu on GitHub](https://github.com/damian-buho/b19-ubuntu)
- [B19/Ubuntu on kiota.ch](https://kiota.ch/b19/ubuntu)
- [Issues on Codeberg](https://codeberg.org/b19/ubuntu/issues)
- [Issues on GitHub](https://github.com/damian-buho/b19-ubuntu/issues)

### Other

- [From author](https://dbuho.me)

## License

This project is licensed under MIT — see the [LICENSE](LICENSE) file for details.

*Generated from projectfile ([learn how](https://projectfile.org/how-to/readme))*
