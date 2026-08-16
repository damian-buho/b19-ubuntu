<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# b19-log

Structured, level-filtered logging with color support.

## Usage

```bash
b19-log <level> <tag> [message...]
echo "message" | b19-log <level> <tag>
```

## Levels

| Level | Aliases   | Priority | Color                                  |
| ----- | --------- | -------- | -------------------------------------- |
| error |           | 40       | red                                    |
| warn  |           | 30       | yellow                                 |
| info  | bad, good | 20       | dim (info), yellow (bad), green (good) |
| note  | debug     | 10       | blue (note), dim (debug)               |

Messages below the `B19_VERBOSITY` threshold are silently discarded.

## Environment

| Variable        | Default | Effect                                                      |
| --------------- | ------- | ----------------------------------------------------------- |
| `B19_VERBOSITY` | `warn`  | Threshold: error (40), warn (30), info (20), debug (10)     |
| `STAGE`         | (unset) | If set, prepended as a stage label (e.g., `BUILD`, `ENTRY`) |

## Output Format

**Normal mode** (colors):

```text
 STAGE   tag       message (colored)
```

**Quiet mode** (`B19_VERBOSITY=error`):

```text
 STAGE  tag       message
```

All output goes to stderr.

## Stdin Support

When called without a message argument, reads from stdin line by line:

```bash
some-command 2>&1 | b19-log warn "MYTAG"
```

## Examples

```bash
# Simple message
b19-log good "SETUP" "Configuration loaded"

# Warning with tag
b19-log warn "DB" "Connection pool running low"

# Error
b19-log error "APP" "Failed to bind to port 8080"

# Pipe command output
apt-get install -y curl 2>&1 | b19-log info "APT"
```
