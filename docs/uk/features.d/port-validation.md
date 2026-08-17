<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Перевірка портів

- Усі змінні середовища `*PORT*` перевіряються під час запуску за списком заборонених портів WHATWG і за привілейованими портами (\<1024).
- Завчасно ловить хибні налаштування на кшталт `HTTP_PORT=22`, перш ніж служба непомітно впаде.
- Можна вимкнути під час виконання без перебудови образу.

<!-- textlint-enable -->
