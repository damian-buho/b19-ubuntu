<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Compromised certificate authorities distrusted ahead of upstream

- Certificates listed by SHA-256 fingerprint are removed from the system trust store at build time, before the distribution ships its own fix.
- One list serves the whole image lineage: each runtime’s own store is cut from it as well.
- Ships distrusting the eMudhra intermediates whose private keys can be recovered (October 2026), together with their cross-signs and roots.
- Downstream images add fingerprints with one variable or one file, and `B19_CA_DISTRUST_ENABLED=false` turns the cut off. [How-to](how-to/use-ca-distrust.md)
