<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Log with b19-log

`b19-log` is the logger every other b19 tool routes through: level-filtered, tag-prefixed, color-aware lines on stderr. One `B19_VERBOSITY` knob therefore silences or reveals the whole image, from build hooks to the running service. The pitch: [structured logging](../features.d/logging.md).

## When to use

- Any script shipped in a b19 image: user-facing output goes through `b19-log`, never a bare `echo`.
- Wrapping noisy third-party output (APT, cURL, compilers) into one tagged stream that respects the verbosity threshold.

## Quick start

```bash
b19-log good "SETUP" "Configuration loaded"
b19-log warn "DB" "Connection pool running low"
apt-get install -y curl 2>&1 | b19-log info "APT"
```

## How it works

```bash
b19-log <level> <tag> [message...]
echo "message" | b19-log <level> <tag>
```

Called without a message argument, the tool reads stdin line by line — the pipe form above is the idiomatic way to capture a command’s output.

### Levels

| Level | Aliases   | Priority | Color                                  |
| ----- | --------- | -------- | -------------------------------------- |
| error |           | 40       | red                                    |
| warn  |           | 30       | yellow                                 |
| info  | bad, good | 20       | dim (info), yellow (bad), green (good) |
| note  | debug     | 10       | blue (note), dim (debug)               |

Messages below the `B19_VERBOSITY` threshold are silently discarded. The `bad`/`good` aliases are the readable way to flag success and failure lines inside the `info` band.

### Output format

All output goes to stderr, so stdout stays clean for data. A set `STAGE` variable is prepended as a label (`BUILD`, `ENTRY`, …), which is how build hooks and entrypoint hooks identify their phase:

```text
 STAGE   tag       message (colored)
```

With colour disabled (`NO_COLOR=1`, which is what a capture sets) the level has
nowhere to show, so it is printed as its own column instead — otherwise a warn
and an info read identically in `reports/*.log`:

```text
 WARN    ENTRY.D       the message
```

Piped input keeps the bare shape: those lines are the wrapped process’s own
output, not a b19 log record.

## Configuration

| Variable        | Default | Effect                                                  |
| --------------- | ------- | ------------------------------------------------------- |
| `B19_VERBOSITY` | `warn`  | Threshold: error (40), warn (30), info (20), debug (10) |
| `STAGE`         | (unset) | Prepended as a stage label when set                     |

The full variable index lives in [configure-environment](configure-environment.md).

## Recipes

```bash
# Tag an error worth failing on later
b19-log error "APP" "Failed to bind to port 8080"

# Fold a whole tool run into one tag
make test 2>&1 | b19-log note "TEST"

# Use inside a build hook (STAGE is set by the runner)
b19-log info "FETCH" "Downloading toolchain"
```

## See also

- [Run commands with b19-run](use-b19-run.md) — timed wrapper reporting through this logger
- [Manage long-running processes with b19-exec](use-b19-exec.md) — routes a service’s stdout/stderr through it
- [Configure the image environment](configure-environment.md) — every `B19_*` variable
