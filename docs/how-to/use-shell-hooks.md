<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Enhance interactive shells

`docker exec -it <container> bash` sessions automatically source every `*.sh` in `/shell.d` — secrets load, and anything downstream images add (aliases, PATH tweaks, tool initializers) applies to your debugging shell. The pitch: [interactive shell hooks](../features.d/shell-hooks.md).

## When to use

- Debugging inside a running container with the same environment the service sees.
- Shipping conveniences for operators: prompt setup, kubectl completions, project-specific aliases.

## Quick start

```bash
# .container/user/shell.d/020-aliases.sh
alias logs='b19-log info "SHELL" "use docker logs instead"'
```

```bash
docker exec -it <container> bash   # your hooks are already sourced
```

## How it works

During the foundation build, `post/650-setup-shell-hooks.sh` appends a block to `/etc/bash.bashrc` — the Debian/Ubuntu system-wide interactive rc:

```bash
# b19: source shell.d hooks for interactive shells
if [ "${B19_SHELL_ENABLED}" != "false" ] && [ -d "${B19_SHELL_PATH}" ]; then
  for _b19_sh in "${B19_SHELL_PATH}"/*.sh; do
    [ -e "${_b19_sh}" ] || continue
    # shellcheck disable=SC1090
    . "${_b19_sh}"
  done
  unset _b19_sh
fi
```

Differences from the other [runners](use-runner-family.md): this one uses a plain glob (alphabetical order, not numeric sort) and integrates at bashrc level, not via a driver tool. Hooks are sourced, so a failing hook can disturb the loop — keep them defensive.

The base image ships one hook: `010-load-secrets.sh`, whose whole body is `. b19-load-secrets` — interactive sessions get the same secret-derived environment the service has. Downstream hooks land via the standard `COPY .container/user/ /` and merge by layer overlay.

Non-interactive `docker exec <container> <cmd>` does **not** trigger bashrc — that is what [b19-exec-with-secrets](use-secrets.md) is for.

## Configuration

| Variable            | Default    | Effect                                   |
| ------------------- | ---------- | ---------------------------------------- |
| `B19_SHELL_PATH`    | `/shell.d` | Directory sourced by bash.bashrc         |
| `B19_SHELL_ENABLED` | `true`     | `false` disables both install and source |

## See also

- [Load secrets](use-secrets.md) — what the base hook provides
- [Use the runner family](use-runner-family.md) — the seven driven runners
