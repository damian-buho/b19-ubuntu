<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Контейнер без прав root за замовчуванням

- Контейнер працює від користувача без прав root (`ubuntu`, UID/GID 1000), і всі робочі файли належать цьому користувачеві.
- Двоетапне збирання відокремлює системне встановлення від імені root від налаштування середовища виконання на рівні користувача.
- Ідентичність користувача налаштовується під час збирання.

<!-- textlint-enable -->
