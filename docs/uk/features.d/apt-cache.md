<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Постійний APT-кеш між збираннями

- Кеші пакетів та індексів APT зберігаються між збираннями через кеш-монтування BuildKit із ключем за серією Ubuntu та архітектурою.
- Повторні збирання використовують уже завантажені пакети замість нового завантаження.
- Необов’язковий LAN-проксі кешування APT, вмикається змінною `M6E_APT_CACHE_HOST`.

<!-- textlint-enable -->
