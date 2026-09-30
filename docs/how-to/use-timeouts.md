<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Bound every step with timeouts

Every step the image runs ends — by success, a loud failure, or a restart. Nothing waits forever on a hung tool, a stalled download or a service that never comes up. The pitch: [nothing hangs forever](../features.d/timeouts.md).

## When to use

- A bootstrap, test or CI step that can wedge on the network or on a dependency.
- A call that fails transiently (a registry login, a database that is still starting) and is safe to repeat.
- A long-running service that can end up alive but useless, where a restart is the cure.

## Quick start

```bash
# Retry a transient failure up to 5 times, then give up loudly
b19-run --retries 5 --backoff 2 "LOGIN" "Registry login" -- docker login "${REGISTRY}"

# Kill a command that runs longer than 2 minutes
b19-run --timeout 120 "LINT" "Linting shell scripts" -- shellcheck scripts/*.sh

# Restart a service after 3 failed health probes in a row
docker run -e B19_HEALTH_EXIT_AFTER=3 --restart unless-stopped my-image
```

## How it works

### Per-call: `b19-run` options

```bash
b19-run [--timeout S] [--retries N] [--backoff S] <tag> <message> -- <command> [args…]
```

Options go before the tag, so every existing call keeps working unchanged.

- `--timeout S` — wraps each attempt in `timeout(1)`: `SIGTERM`, then `SIGKILL` 5 s later, exit code `124`. Falls back to `B19_RUN_TIMEOUT`.
- `--retries N` — repeats a failed attempt up to N more times. One warning line per failed attempt names its exit code and the wait before the next.
- `--backoff S` — the first wait. Each wait doubles up to `B19_RUN_BACKOFF_MAX`, with up to half of it removed at random so parallel callers do not retry in step.

Retries are per call only, never an environment default: only the call site knows whether its command is safe to repeat.

A piped stdin is consumed by the first attempt, so a retried command must produce its own input: `b19-run --retries 2 … -- bash -c 'printf "%s" "${TOKEN}" | docker login … --password-stdin'`.

### Per-phase bounds

| Phase                     | Variable                  | Default | Bound                                                    |
| ------------------------- | ------------------------- | ------- | -------------------------------------------------------- |
| each `bootstrap.d` script | `B19_BOOTSTRAP_TIMEOUT`   | `3600`  | seconds per script                                       |
| each `test.d` script      | `B19_TEST_SCRIPT_TIMEOUT` | `600`   | seconds per script                                       |
| the one-shot command      | `B19_COMMAND_TIMEOUT`     | (empty) | seconds; empty keeps `docker run -it img bash` unbounded |

A phase that runs past its bound fails the container the same way a failing script does.

### Network stalls

`curl` (`~/.curlrc`) and `git` (`/etc/gitconfig`) abort a transfer that moves less than 1 byte/s for 300 s, and `curl` gives up on a connection after 30 s. A slow but moving download of any size still completes: the bound is on silence, not on duration.

Override per call (`curl --speed-time 900 …`, `git -c http.lowSpeedTime=900 …`) or replace the file in a derived image.

### Restart a stuck service

Compose and plain Docker never act on `unhealthy`. With `B19_HEALTH_EXIT_AFTER=N`, `healthcheck.d` counts consecutive failed probes and, at N, sends `TERM` to PID 1 so the container exits and its restart policy takes over.

- Probes during the first `B19_HEALTH_EXIT_GRACE` seconds after start never count, so a slow start is not a crash loop.
- A passing probe resets the count; a draining container never counts.
- A hung check counts too: `B19_HEALTH_CHECK_TIMEOUT` ends it inside Docker’s probe timeout.
- The readiness wait inside `test.d` never counts either.

## Configuration

| Variable                  | Default | Effect                                                           |
| ------------------------- | ------- | ---------------------------------------------------------------- |
| `B19_RUN_TIMEOUT`         | (unset) | Default `--timeout` for every `b19-run` call                     |
| `B19_RUN_BACKOFF_MAX`     | `60`    | Ceiling in seconds for one retry wait                            |
| `B19_BOOTSTRAP_TIMEOUT`   | `3600`  | Seconds each `bootstrap.d` script may run                        |
| `B19_TEST_SCRIPT_TIMEOUT` | `600`   | Seconds each `test.d` script may run                             |
| `B19_COMMAND_TIMEOUT`     | (empty) | Seconds the one-shot command may run; empty means unbounded      |
| `B19_HEALTH_EXIT_AFTER`   | (empty) | Consecutive failed probes before PID 1 gets `TERM`; empty is off |
| `B19_HEALTH_EXIT_GRACE`   | `90`    | Seconds after start during which failed probes do not count      |

## See also

- [Run commands with b19-run](use-b19-run.md) — the wrapper these options extend
- [Write healthchecks](use-healthcheck.d.md) — the probes the restart counts
- [Configure the image environment](configure-environment.md) — every variable in one index
