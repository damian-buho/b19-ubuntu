<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Compromised certificate authorities distrusted ahead of upstream

- Certificates listed by SHA-256 fingerprint are removed from the system trust store at build time, before the distribution ships its own fix.
- One list serves the whole image lineage, and `b19-ca-distrust bundle` cuts any vendored PEM bundle from it too.
- Ships distrusting the eMudhra intermediates whose private keys can be recovered (October 2026), together with their cross-signs and roots.
- Downstream images add fingerprints with one variable or one file, and `B19_CA_DISTRUST_ENABLED=false` turns the cut off. [How-to](how-to/use-ca-distrust.md)
