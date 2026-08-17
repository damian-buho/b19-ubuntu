<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Use NUMPROCS CPU detection

The image detects how many CPUs it may actually use — Kubernetes quota, cgroups v2 limit, or raw `nproc` — and exports the answer as `NUMPROCS` for every build hook and runtime script. No hardcoded job counts; parallelism adapts from a laptop to a CI runner to a constrained pod. The pitch: [automatic CPU count detection](../features.d/cpu-detection.md).

## When to use

- Any parallel work: `make -j"${NUMPROCS}"`, `xargs -P "${NUMPROCS}"`, compile jobs, test shards.
- Containers with CPU quotas below the host core count — `nproc` would over-report and thrash.

## Quick start

```bash
# In any hook, build script or entrypoint script:
make -j"${NUMPROCS}"
```

Nothing to enable. At build time every root stage inherits `on/100-detect-cpu-count.i.sh`; at runtime the entrypoint hook `0200-set-cpu-count.sh` re-detects before your service starts — both are one-line wrappers around the `detect-cpu-count` tool.

## How it works

Detection priority, most authoritative first:

1. `/etc/podinfo/cpu_limit` — the Kubernetes downward API, when the cluster mounts it
1. `/sys/fs/cgroup/cpu.max` — cgroups v2 quota (`quota / period`, integer division, floored at 1)
1. `nproc` — when the cgroup file says `max` or is absent

Entrypoint hooks are sourced into one shell, so `NUMPROCS` exported at slot 0200 is visible to every later hook and to the service command. The result is logged at `debug` level only.

Two deliberate deviations:

- `b19-fetch` does not trust the inherited build-time value — it resets `NUMPROCS=$(nproc)` and feeds it to aria2c as `--max-concurrent-downloads`.
- `parallel-j2` defaults to 4 when the variable is unset (`xargs -P "${NUMPROCS:-4}"`).

There is no `B19_CPU_*` variable: `NUMPROCS` is the only knob. Quota truncation is intentional — a 1.5-CPU quota yields `NUMPROCS=1`.

## Recipes

```yaml
# Constrain the container; NUMPROCS follows automatically (cgroups v2)
deploy:
  resources:
    limits:
      cpus: "4.0"      # → NUMPROCS=4
```

```dockerfile
# Kubernetes: mount the downward API to feed branch 1
- name: podinfo
  mountPath: /etc/podinfo
```

## See also

- [Start containers with entrypoint.d](use-entrypoint.d.md) — where slot 0200 sits
- [Render templates with minijinja](use-templating.md) — the parallel renderer
- [Configure the image environment](configure-environment.md) — system-set variables
