<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Автоматичне визначення кількості CPU (NUMPROCS)

- Доступні CPU визначаються автоматично через downward API Kubernetes, cgroups v2 або резервний `nproc`.
- Виявлена кількість доступна як `NUMPROCS` протягом усього збирання та виконання й використовується для паралельної компіляції, рендерингу шаблонів і запуску тестів.
- Усуває зашиті кількості завдань і гарантує однаковий паралелізм у Docker, Kubernetes і CI.
