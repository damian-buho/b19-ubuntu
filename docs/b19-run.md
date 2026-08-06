<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19-run

Execute a command with progress indicator, buffered output, and success/failure reporting.

## Usage

```bash
b19-run <tag> <message> -- <command> [args...]
```

The `--` separator is a convention for readability and is consumed automatically.

## Behavior

1. Executes command directly via `"$@"` with proper argument handling
1. On success: prints "TAG message… success (0.234s)" (info/debug only); discards the buffered output **unless the verbosity level is `info`** (see below)
1. On failure: prints "TAG message… failure (exit code N, 0.234s)" + buffered output (all verbosity levels)

In debug mode (`B19_VERBOSITY=debug`), output streams directly to stderr instead of buffering.

### Reveal on success

Hiding green output keeps a terminal/`make` sheet short, but the verbose view can
afford the full log — and exit-0 *warnings* (e.g. yamllint line-length, deprecations)
would otherwise be lost. This is now folded into the verbosity level:

- **`info`** — dump the buffered output on success too (the verbose view).
- **`debug`** — already streams live, so reveal is a no-op.
- **`error`/`warn`** — quiet success (the classic view).

> Under `m6e-run` the container is forced to `debug`, so b19-run streams and this
> reveal path is not reached — it applies to the **standalone / build-hook** case
> where b19-run is the sole runner.

## Environment

| Variable                   | Default | Effect                                                               |
| -------------------------- | ------- | -------------------------------------------------------------------- |
| `B19_VERBOSITY`            | `warn`  | Controls output: see table below                                     |
| `B19_RUN_TIMING_PRECISION` | `3`     | Decimal places in elapsed time (`0`=s, `3`=ms, `6`=µs)               |
| `B19_RUN_TIMEOUT`          | (unset) | If set to `<seconds>`, wraps the command in `timeout(1)`. See below. |
| `STAGE`                    | (unset) | If set, prepended as a stage label                                   |

### Wall-clock guard (`B19_RUN_TIMEOUT`)

Optional ceiling, **off by default**. Build and compile callers (Erlang, LLVM,
Scala, GCC, …) run legitimately long, so a blanket bound there would be wrong.
Lint and validation runners set `B19_RUN_TIMEOUT=<seconds>` so a **wedged tool
dies loudly instead of hanging the whole tool-execution chain** (command.d →
entrypoint → `m6e-run` → `make`), which has no timeout of its own.

When the bound is reached, `timeout(1)` sends `SIGTERM`, then `SIGKILL` after a
5s grace period, and exits `124` — reported by b19-run as a normal failure
(exit code 124). When unset, behavior is unchanged (no `timeout` is spawned).

### Verbosity levels

| Level   | Progress + success | Failure                  |
| ------- | ------------------ | ------------------------ |
| `error` | suppressed         | plain text (no colors)   |
| `warn`  | suppressed         | colored, with TAG prefix |
| `info`  | shown              | colored, with TAG prefix |
| `debug` | shown; live output | colored, with TAG prefix |

## Exit Code

Returns the exit code of the executed command. If `B19_RUN_TIMEOUT` is set and
the bound is exceeded, the exit code is `124` (from `timeout(1)`).

## Examples

```bash
# Simple command
b19-run "APT" "Installing curl" -- apt-get install -y curl

# Command with variables
b19-run "BUILD" "Compile ${PROJECT}" -- make -j"${NUMPROCS}"

# Command needing shell features (pipes, redirections)
b19-run "SETUP" "Generate config" -- sh -c 'envsubst < input.tpl > output.conf'

# Run with debug output
B19_VERBOSITY=debug b19-run "TEST" "Running tests" -- make test
```
