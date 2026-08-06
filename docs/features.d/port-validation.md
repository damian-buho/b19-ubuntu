<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Port validation

- All `*PORT*` environment variables are validated at startup against the WHATWG blocklist of forbidden ports and privileged ports (\<1024).
- Catches misconfigurations like `PORT=0` or `PORT=22` early, before the service fails silently.
- Can be disabled at runtime without rebuilding the image.
