<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Хуки інтерактивної shell (shell.d)

- Сеанси `docker exec bash` автоматично завантажують Docker-секрети та будь-які власні хуки, додані похідними образами.
- Хуки зливаються через накладання шарів Docker, тож успадковане та проєктне налаштування shell співіснують.

<!-- textlint-enable -->
