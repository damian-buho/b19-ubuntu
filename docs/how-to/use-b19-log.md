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

### JSON lines (`B19_LOG_FORMAT=json`)

For a log pipeline (Alloy, Loki, CrowdSec), every record becomes one JSON object
per line, still on stderr and still filtered by `B19_VERBOSITY`:

```json
{"time":"2026-10-23T18:48:19.022Z","level":"warn","stage":"ENTRY","tag":"DB","msg":"Connection pool running low"}
```

- `time` is UTC with milliseconds, whatever the locale’s decimal separator
- `level` is one of `error`, `warn`, `info`, `debug`: `good` and `bad` map to `info`, `note` to `debug`
- `stage` appears only when `STAGE` is set
- `msg` is escaped per RFC 8259: quotes, backslashes and every control byte (an ANSI `ESC` included) become escapes, other UTF-8 passes unchanged
- A piped line that already is a JSON object (`{…}`) is written unchanged, so a payload logging JSON is never encoded twice

The variable reaches every b19 tool and `b19-exec` payload through the environment, so one setting switches the whole container.

### Parsing a service’s own lines

Under `B19_LOG_FORMAT=json`, `b19-exec` sends each stream through `b19-log-format`, one long-lived `gojq` per stream. It tries each line in turn:

1. A JSON object: written unchanged when it carries `time` and `level`, otherwise it gains the missing ones. It never gains a `tag`.
1. An image rule: the first regular expression in `/log-formats.d/` that matches.
1. `key=value` pairs, when the whole line is pairs: each becomes a field, and the first spelling of a repeated key wins.
1. Anything else: `msg`, at the stream’s level.

A rule is one regular expression per line in any file under `.container/user/log-formats.d/`, with named groups as fields. Only a leading `#` starts a comment, so a rule may hold one. Go regular expressions have no lookaround or backreferences:

```text
^(?<upstream_time>[0-9/]+ [0-9:]+) \[(?<level>[a-z]+)\] [0-9]+#[0-9]+: (?<msg>.*)$
```

```json
{"level":"error","msg":"open() failed","raw":"2026/11/03 10:00:00 [crit] 12#12: open() failed","tag":"nginx","time":"2026-11-03T10:00:00.123Z","upstream_time":"2026/11/03 10:00:00"}
```

- `raw` holds the native line whenever `msg` differs from it, so a parser that needs the original still has it
- A `level` group normalises to `error`, `warn`, `info` or `debug`; an unknown spelling takes the stream’s level
- `time`, `tag`, `stage` and `raw` are always the formatter’s own: log content cannot set them
- A rule that fails is skipped, and a failing `gojq` hands the stream to `b19-log`, so a bad rule never stops a service
- The formatter reads line by line, so a multi-line traceback stays the image’s own job
- A slow formatter fills the pipe and blocks the service’s log writes: give a very chatty log, such as an access log, the service’s native JSON
- Test each rule against the service’s real output in `test.d`, or an upstream bump drifts past a hand-written sample

## Configuration

| Variable         | Default | Effect                                                          |
| ---------------- | ------- | --------------------------------------------------------------- |
| `B19_VERBOSITY`  | `warn`  | Threshold: error (40), warn (30), info (20), debug (10)         |
| `STAGE`          | (unset) | Prepended as a stage label when set                             |
| `B19_LOG_FORMAT` | `text`  | `json` writes one JSON object per line; anything else is `text` |

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
