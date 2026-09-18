<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
SPDX-License-Identifier: MIT
pf-cli-managed: yes
-->

[Español](docs/es/README.md) · [Українська](docs/uk/README.md)

# B19 / Ubuntu

Community-maintained Ubuntu base image for the B19 fleet

[![Stand with Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://damian-buho.github.io/support-ukraine/) [![Projectfile inside](https://badges.kiota.ch/static/v1?label=projectfile&message=inside&labelColor=0d0d0d&color=8c6723&style=flat-square)](https://projectfile.org) [![License](https://badges.kiota.ch/static/v1?label=license&message=MIT&color=1e5913&style=flat-square)](LICENSE) [![Commit style](https://badges.kiota.ch/static/v1?label=commits&message=conventional%20v1.0.0&color=1877aa&style=flat-square)](https://www.conventionalcommits.org/en/v1.0.0/) ![Workflow](https://badges.kiota.ch/static/v1?label=workflow&message=git-flow&color=1877aa&style=flat-square) [![Versioning](https://badges.kiota.ch/static/v1?label=versioning&message=semantic%20v2.0.0&color=1877aa&style=flat-square)](https://semver.org/) [![PRs welcome](https://badges.kiota.ch/static/v1?label=PRs&message=welcome&color=1e5913&style=flat-square)](CONTRIBUTING.md) [![Citation](https://badges.kiota.ch/static/v1?label=citation&message=cff&color=1877aa&style=flat-square)](CITATION.cff) [![REUSE compliance](https://api.reuse.software/badge/codeberg.org/b19/ubuntu)](https://api.reuse.software/info/codeberg.org/b19/ubuntu)

![Project status](https://badges.kiota.ch/static/v1?label=status&message=maintained&color=1d63ed&style=flat-square) [![Last commit on kiota.ch](https://badges.kiota.ch/gitea/last-commit/b19/ubuntu?gitea_url=https://kiota.ch&label=last%20commit%20on%20kiota.ch&style=flat-square)](https://kiota.ch/b19/ubuntu) [![Last commit on Codeberg](https://badges.kiota.ch/gitea/last-commit/b19/ubuntu?gitea_url=https://codeberg.org&label=last%20commit%20on%20Codeberg&style=flat-square)](https://codeberg.org/b19/ubuntu) [![Last commit on GitHub](https://badges.kiota.ch/github/last-commit/damian-buho/b19-ubuntu?label=last%20commit%20on%20GitHub&style=flat-square)](https://github.com/damian-buho/b19-ubuntu)

[![Publish pipeline on GitHub](https://github.com/damian-buho/b19-ubuntu/actions/workflows/published.yaml/badge.svg?style=flat-square)](https://github.com/damian-buho/b19-ubuntu/actions) [![Vulnerability audit on GitHub](https://github.com/damian-buho/b19-ubuntu/actions/workflows/audited.yaml/badge.svg?style=flat-square)](https://github.com/damian-buho/b19-ubuntu/actions) [![Dependency freshness on GitHub](https://github.com/damian-buho/b19-ubuntu/actions/workflows/check-outdated.yaml/badge.svg?style=flat-square)](https://github.com/damian-buho/b19-ubuntu/actions) [![Analysis sweep on GitHub](https://github.com/damian-buho/b19-ubuntu/actions/workflows/analyze.yaml/badge.svg?style=flat-square)](https://github.com/damian-buho/b19-ubuntu/actions)

[![Publish pipeline on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/published.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Vulnerability audit on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/audited.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Dependency freshness on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/check-outdated.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions) [![Analysis sweep on kiota.ch](https://kiota.ch/b19/ubuntu/badges/workflows/analyze.yaml/badge.svg?style=flat-square)](https://kiota.ch/b19/ubuntu/actions)

## Features

- Persistent APT cache across builds
- Service process management with log routing (b19-exec)
- Cached artifact downloads with integrity verification
- Timed command execution with failure reporting (b19-run)
- Run-once initialization (bootstrap.d)
- Modular build hooks (build.d)
- Automatic CPU count detection
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
- Docker secrets auto-loading
- Interactive shell hooks
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

- `linux/amd64`
- `linux/arm64`
- `linux/riscv64`

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

Stable releases also publish `X.Y.Z`, `X.Y` and `X` tags — pull the precision you want to pin.

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

- [Makefile reference](docs/how-to/MAKEFILE.md)

Run `make` with no arguments for the default target; run `make help` to list every target.

For the local dev loop, `make dev-container` brings up the dev-container.

Pipeline entry points:

- `make analyze` — Run the heavy analysis sweep (mutation testing, benchmarks)
- `make audited` — Re-scan the pinned dependencies and published artifacts for new vulnerabilities
- `make check-outdated` — Report every pinned dependency that lags upstream
- `make ready-to-publish` — Run the pseudo-CI pipeline locally — build, test and scan, without publishing

## Documentation

- [Configure the image environment](docs/how-to/configure-environment.md)
- [Use the APT cache](docs/how-to/use-apt-cache.md)
- [Manage long-running processes with b19-exec](docs/how-to/use-b19-exec.md)
- [Download files with b19-fetch](docs/how-to/use-b19-fetch.md)
- [Log with b19-log](docs/how-to/use-b19-log.md)
- [Run commands with b19-run](docs/how-to/use-b19-run.md)
- [Initialize state once with bootstrap.d](docs/how-to/use-bootstrap.d.md)
- [Build images with build.d hooks](docs/how-to/use-build.d.md)
- [Use NUMPROCS CPU detection](docs/how-to/use-cpu-detection.md)
- [Declare dependencies](docs/how-to/use-dependencies.md)
- [Start containers with entrypoint.d](docs/how-to/use-entrypoint.d.md)
- [Write healthchecks](docs/how-to/use-healthcheck.d.md)
- [Translate strings with b19-i18n](docs/how-to/use-i18n.md)
- [Track image lineage](docs/how-to/use-lineage.md)
- [Run as a non-root user](docs/how-to/use-non-root.md)
- [Run offgrid builds](docs/how-to/use-offgrid.md)
- [Ship files with overlays](docs/how-to/use-overlays.md)
- [Build on the pinned base](docs/how-to/use-pinned-base.md)
- [Validate ports](docs/how-to/use-port-validation.md)
- [Use the runner family](docs/how-to/use-runner-family.md)
- [Load secrets](docs/how-to/use-secrets.md)
- [Enhance interactive shells](docs/how-to/use-shell-hooks.md)
- [Handle signals gracefully](docs/how-to/use-signals.md)
- [Render templates with minijinja](docs/how-to/use-templating.md)
- [Test images with test.d](docs/how-to/use-test.d.md)
- [Use the tools](docs/how-to/use-tools.md)
- [Use the XDG paths](docs/how-to/use-xdg-paths.md)

## Policies

- [How to contribute](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Getting support](SUPPORT.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [AI and LLM Policy](AI_POLICY.md)

## Links

- [Projectfile Specification](https://projectfile.org)

## License

This project is licensed under MIT — see the [LICENSE](LICENSE) file for details.
