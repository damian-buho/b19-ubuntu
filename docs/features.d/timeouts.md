<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Nothing hangs forever

- Every startup, test and one-shot step has a time bound, so a wedged tool fails loudly instead of blocking a deploy or a CI run.
- Stalled downloads are aborted, while slow ones of any size still complete.
- A flaky call can be retried with backoff in one flag, without a hand-written loop.
- An opt-in restart turns a service stuck unhealthy into a container the restart policy recovers.

See [use-timeouts](../how-to/use-timeouts.md) for the options, defaults and overrides.
