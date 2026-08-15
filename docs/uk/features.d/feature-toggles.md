<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Перемикачі функцій для всіх підсистем

- Кожну велику підсистему (entrypoint, healthchecks, bootstrap, тести, секрети, перевірку портів, i18n, shell-хуки) можна вимкнути під час виконання через змінні середовища.
- Окремі хуки entrypoint і bootstrap можна пропустити за ім’ям, не вимикаючи всю підсистему.
- Перебудова образу не потрібна — перемикачі діють лише в рантаймі.
