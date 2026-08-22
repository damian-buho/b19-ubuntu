# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

ARG B19_FD_IMAGE=registry.invalid/b19/fd:latest
ARG B19_MINIJINJA_IMAGE=registry.invalid/b19/minijinja:latest
ARG B19_UBUNTU_HASH=sha256:f3d28607ddd78734bb7f71f117f3c6706c666b8b76cbff7c9ff6e5718d46ff64
ARG BASE_ARCH=amd64

FROM --platform=${BASE_ARCH} ${B19_FD_IMAGE} AS b19-fd
FROM --platform=${BASE_ARCH} ${B19_MINIJINJA_IMAGE} AS b19-minijinja

FROM ubuntu@${B19_UBUNTU_HASH} AS final

ARG B19_CACHE_PATH=/var/cache/b19
ARG B19_COLOR
ARG B19_FETCH_DOCKER_CACHE=Y
ARG B19_FETCH_LOCAL_CACHE=Y
ARG B19_GID=1000
ARG B19_GROUP=ubuntu
ARG B19_HOME="/app"
ARG B19_LOCALES="en_US.UTF-8 uk_UA.UTF-8 es_ES.UTF-8"
ARG B19_OFFGRID_MODE=N
ARG B19_SSH_SCAN_HOSTS="codeberg.org github.com gitlab.com bitbucket.org"
ARG B19_TEMP_PATH="/tmp"
ARG B19_UBUNTU_MIRROR_AMD64=http://archive.ubuntu.com/ubuntu/
ARG B19_UBUNTU_MIRROR_ARM64=http://ports.ubuntu.com/ubuntu-ports
ARG B19_UBUNTU_MIRROR_RISCV64=http://ports.ubuntu.com/ubuntu-ports
ARG B19_UBUNTU_SERIES
ARG B19_UID=1000
ARG B19_USER=ubuntu
ARG B19_VERBOSITY
ARG M6E_AI=N
ARG M6E_APT_CACHE_HOST
ARG M6E_APT_CACHE_PORT
ARG M6E_NAMESPACE
ARG M6E_NEAR_CACHE_HOST
ARG M6E_PROJECT
ARG M6E_VERSION
ARG TARGETARCH

ARG B19_BIN_PATH=${B19_HOME}/bin

ENV XDG_CACHE_HOME=${B19_HOME}/.cache       \
    XDG_CONFIG_HOME=${B19_HOME}/.config     \
    XDG_DATA_HOME=${B19_HOME}/data          \
    XDG_STATE_HOME=${B19_HOME}/.state

# hadolint ignore=DL3064 # security theater
ENV B19_BENCHMARK_ENABLED=true                                                    \
    B19_BENCHMARK_PATH=/benchmark.d                                               \
    B19_BENCHMARK_RESULTS_PATH="/tmp/benchmark.d"                                 \
    B19_BIN_PATH="${B19_BIN_PATH}"                                                \
    B19_BOOTSTRAP_ENABLED=true                                                    \
    B19_BOOTSTRAP_LOCK_PATH=${XDG_DATA_HOME}/.bootstrap                           \
    B19_BOOTSTRAP_PATH=/bootstrap.d                                               \
    B19_BUILD_ALWAYS_ENABLED=true                                                 \
    B19_BUILD_PATH=/build.d                                                       \
    B19_CACHE_PATH="${B19_CACHE_PATH}"                                            \
    B19_COMMAND_PATH=/command.d                                                   \
    B19_DEPS_PATH=/deps                                                           \
    B19_DOCKER_GID=995                                                            \
    B19_DOWNLOAD_DISK_CACHE=64m                                                   \
    B19_DOWNLOAD_MAX_TRIES=4                                                      \
    B19_DOWNLOAD_PATH=${B19_CACHE_PATH}/download                                  \
    B19_DOWNLOAD_RETRY_WAIT=16                                                    \
    B19_ENTRYPOINT_PATH=/entrypoint.d                                             \
    B19_FETCH_DOCKER_CACHE=${B19_FETCH_DOCKER_CACHE}                              \
    B19_FETCH_LOCAL_CACHE=${B19_FETCH_LOCAL_CACHE}                                \
    B19_GID="${B19_GID}"                                                          \
    B19_GROUP="${B19_GROUP}"                                                      \
    B19_HEALTH_CACHE_MIN_SPACE_KB=32768                                           \
    B19_HEALTH_CURL_TIMEOUT=8                                                     \
    B19_HEALTH_ENABLED=true                                                       \
    B19_HEALTH_HOME_MIN_SPACE_KB=32768                                            \
    B19_HEALTH_NETWORK_URL="https://www.w3.org https://www.google.com"            \
    B19_HEALTH_PATH=/healthcheck.d                                                \
    B19_HEALTH_PING_TARGETS="9.9.9.9 1.1.1.1 8.8.8.8"                             \
    B19_HEALTH_REACH_PORT_SAFE=443                                                \
    B19_HEALTH_TEMP_MIN_SPACE_KB=32768                                            \
    B19_HOME="${B19_HOME}"                                                        \
    B19_I18N_ENABLED=true                                                         \
    B19_IMMUTABLE=N                                                               \
    B19_LINEAGE_FILE=${B19_HOME}/.lineage                                         \
    B19_LOCALES=${B19_LOCALES}                                                    \
    B19_OFFGRID_MODE=${B19_OFFGRID_MODE}                                          \
    B19_OVERLAYS_PATH=/overlays/                                                  \
    B19_PORT_CHECK_ENABLED=true                                                   \
    B19_PREFIX=/usr/local                                                         \
    B19_REPORTD_FAT_FILES_AMOUNT=64                                               \
    B19_RUNTIME_MODE=docker-compose                                               \
    B19_SECRETS_ENABLED=true                                                      \
    B19_SECRETS_PATH="/run/secrets"                                               \
    B19_SHELL_ENABLED=true                                                        \
    B19_SHELL_PATH="/shell.d"                                                     \
    B19_TEMP_PATH="${B19_TEMP_PATH}"                                              \
    B19_TEST_ENABLED=true                                                         \
    B19_TEST_PATH=/test.d                                                         \
    B19_TEST_RESULTS_PATH="${B19_TEMP_PATH}/test.d"                               \
    B19_TEST_TIMEOUT=60                                                           \
    B19_TOOLS_PATH=/tools.d                                                       \
    B19_UBUNTU_SERIES=${B19_UBUNTU_SERIES}                                        \
    B19_UID="${B19_UID}"                                                          \
    B19_USER="${B19_USER}"                                                        \
    DEBIAN_FRONTEND=noninteractive                                                \
    DO_NOT_TRACK=1                                                                \
    ENVIRONMENT=production                                                        \
    LANG=C.UTF-8                                                                  \
    PARALLEL_HOME="${B19_TEMP_PATH}"                                              \
    PATH="${B19_HOME}/.local/bin:${B19_BIN_PATH}:/tools.d:/command.d:${PATH}"     \
    TERM=xterm-256color                                                           \
    TMPDIR="${B19_TEMP_PATH}"                                                     \
    TZ=UTC                                                                        \
    USER=${B19_USER}

USER 0

WORKDIR ${B19_HOME}

COPY --from=b19-fd          /usr/local/bin/fd.${TARGETARCH}                 /usr/local/bin/fd
COPY --from=b19-minijinja   /usr/local/bin/minijinja-cli.${TARGETARCH}      /usr/local/bin/minijinja-cli

COPY --chown="${B19_UID}:${B19_GID}"                             .container/foundation/  /

RUN --mount=type=bind,from=fetch,source=.,target=/fetch                                                         \
    --mount=type=cache,target=${B19_DOWNLOAD_PATH},sharing=shared,uid=${B19_UID},gid=${B19_GID}                 \
    --mount=type=cache,id=apt-cache-${B19_UBUNTU_SERIES}-${TARGETARCH},target=/var/cache/apt,sharing=shared     \
    --mount=type=cache,id=apt-lists-${B19_UBUNTU_SERIES}-${TARGETARCH},target=/var/lib/apt,sharing=shared       \
    --mount=type=tmpfs,target=${B19_TEMP_PATH}                                                                  \
    build-stage foundation

# hadolint ignore=DL3066 # B19_UID comes from the root
USER ${B19_UID}

COPY --chown="${B19_UID}:${B19_GID}"                             .container/user/        /

RUN --mount=type=bind,from=fetch,source=.,target=/fetch                                             \
    --mount=type=cache,target=${B19_DOWNLOAD_PATH},sharing=shared,uid=${B19_UID},gid=${B19_GID}     \
    --mount=type=tmpfs,target=${B19_TEMP_PATH}                                                      \
    build-stage user

ENV B19_VERBOSITY=warn

ENTRYPOINT      ["/usr/bin/tini", "-g", "--", "entrypoint.d"]
HEALTHCHECK --start-period=15s --start-interval=5s CMD ["healthcheck.d"]
# Don't use CMD ["sleep", "infinity"] here
