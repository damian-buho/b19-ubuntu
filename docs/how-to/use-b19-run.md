<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Run commands with b19-run

`b19-run` wraps any command with timing, buffered output and success/failure reporting: green stays one line long, failures always show their output. It is the standard way build hooks and CI steps invoke tools. The pitch: [timed command execution with failure reporting](../features.d/b19-run.md).

## When to use

- Build hooks, test scripts and CI steps where a successful tool should be one line and a failing tool must explain itself.
- Anything that can wedge: pair it with `B19_RUN_TIMEOUT` so a hung tool dies loudly.

## Quick start

```bash
b19-run "APT" "Installing curl" -- apt-get install -y curl
b19-run "BUILD" "Compile ${PROJECT}" -- make -j"${NUMPROCS}"
B19_VERBOSITY=debug b19-run "TEST" "Running tests" -- make test
```

## How it works

```bash
b19-run <tag> <message> -- <command> [args...]
```

The `--` separator is a readability convention and is consumed automatically. The command runs via `"$@"`, so arguments pass through untouched.

1. On success: prints `TAG message… success (0.234s)` and discards the buffered output.
1. On failure: prints `TAG message… failure (exit code N, 0.234s)` followed by the buffered output — at every verbosity level.

### Reveal on success

Hiding green output keeps a `make` sheet short, but exit-0 *warnings* (line-length lints, deprecations) would be lost with it. The reveal is therefore folded into the verbosity level:

- `info` — dumps the buffered output on success too (the verbose view).
- `debug` — streams live instead of buffering, so reveal is a no-op.
- `error`/`warn` — quiet success (the classic view).

> Under `m6e-run` the container runs at `debug`, so b19-run streams live and the reveal path is not reached — it applies to the standalone / build-hook case where b19-run is the sole runner.

### Wall-clock guard (`B19_RUN_TIMEOUT`)

Optional ceiling, off by default: build and compile callers (Erlang, LLVM, Scala, GCC, …) run legitimately long, and a blanket bound there would be wrong. Lint and validation runners set `B19_RUN_TIMEOUT=<seconds>` so a wedged tool dies loudly instead of hanging the whole tool-execution chain (command.d → entrypoint → `m6e-run` → `make`), which has no timeout of its own.

When the bound is reached, `timeout(1)` sends `SIGTERM`, then `SIGKILL` after a 5s grace period, and exits `124` — reported by b19-run as a normal failure. When unset, no `timeout` is spawned.

## Configuration

| Variable                   | Default | Effect                                                    |
| -------------------------- | ------- | --------------------------------------------------------- |
| `B19_VERBOSITY`            | `warn`  | Controls progress/success output (table below)            |
| `B19_RUN_TIMING_PRECISION` | `3`     | Decimal places in elapsed time (`0`=s, `3`=ms, `6`=µs)    |
| `B19_RUN_TIMEOUT`          | (unset) | Wraps the command in `timeout(1)` after this many seconds |
| `STAGE`                    | (unset) | Prepended as a stage label when set                       |

### Verbosity levels

| Level   | Progress + success | Failure                  |
| ------- | ------------------ | ------------------------ |
| `error` | suppressed         | plain text (no colors)   |
| `warn`  | suppressed         | colored, with TAG prefix |
| `info`  | shown              | colored, with TAG prefix |
| `debug` | shown; live output | colored, with TAG prefix |

The exit code is the command’s own — or `124` when the wall-clock guard fired. The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```bash
# Command needing shell features (pipes, redirections)
b19-run "SETUP" "Generate config" -- sh -c 'envsubst < input.tpl > output.conf'

# Lint runner with a wall-clock guard
B19_RUN_TIMEOUT=120 b19-run "LINT" "Linting shell scripts" -- shellcheck scripts/*.sh
```

## See also

- [Log with b19-log](use-b19-log.md) — the reporter these lines flow through
- [Manage long-running processes with b19-exec](use-b19-exec.md) — for daemons, not one-shot commands
