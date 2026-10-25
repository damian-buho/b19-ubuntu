<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

<!-- textlint-disable terminology,common-misspellings -->

# Плавна обробка сигналів

- PID 1 — це `tini -g`, який прибирає процеси-зомбі та переспрямовує сигнали всій групі процесів.
- Налаштовуваний набір Unix-сигналів (TERM, INT, HUP, USR1, USR2 тощо) перехоплюється та переспрямовується кожному процесу служби, і вони зупиняються у зворотному до запуску порядку.
- `docker stop` чисто завершує службу без осиротілих процесів і втрачених сигналів.

<!-- textlint-enable -->
