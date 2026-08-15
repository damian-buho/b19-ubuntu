<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Відтворюваний базовий образ (зафіксований за digest)

- Базовий образ Ubuntu зафіксований за SHA-256-digest, а не за тегом, що гарантує детерміновані збирання.
- Підтримуються кілька серій Ubuntu (resolute, noble, необов’язкові: jammy, questing) на вибір під час збирання.
- Дзеркала APT налаштовуються окремо за архітектурою для LAN-дзеркал або ізольованих середовищ.
