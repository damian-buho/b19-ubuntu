<!--
SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>

SPDX-License-Identifier: MIT
-->

# Distrust compromised certificate authorities

A certificate authority can turn untrustworthy faster than every trust store
ships a fix. b19 keeps one list of distrusted certificates, by SHA-256
fingerprint, and cuts each store in the image lineage from it at build time.

## The list

`b19-ca-distrust list` prints the effective set, one uppercase fingerprint per
line. It reads two sources:

- every `*.sha256` file under `/etc/b19/ca-distrust.d/`, one fingerprint per line, followed by an optional label; `#` starts a comment
- `B19_CA_DISTRUST`, fingerprints separated by spaces or commas

Colons and case do not matter, so a value copied from `openssl x509
-fingerprint -sha256` works as is. An entry that is not 64 hex digits is
ignored.

The shipped `emudhra-2026-10.sha256` lists the eMudhra intermediates whose
private keys can be recovered, their Sectigo cross-signs and the four roots they
chain to, as published in
[emudhra.we-have-a-problem.com](https://emudhra.we-have-a-problem.com).

## What gets cut

| Store                                       | Cut by                          | How                                                     |
| ------------------------------------------- | ------------------------------- | ------------------------------------------------------- |
| System bundle (`/etc/ssl/certs`)            | `b19-ca-distrust system`        | `!`-deselects the anchor in `/etc/ca-certificates.conf` |
| Any PEM bundle a runtime vendors            | `b19-ca-distrust bundle FILE…`  | rewrites the file without the matching certificates     |

Deselection survives every later `update-ca-certificates`, `--fresh`
included, and package upgrades keep a deselected entry deselected. The
`foundation` stage applies it, and the inheritable `base/post` and `root/post`
hooks apply it again in every downstream image, so fingerprints a child adds
reach the system store too. A store of its own, such as a vendored PEM bundle,
is cut from the same `list` by the image that ships it.

Only a certificate that is present can be removed. An intermediate in the list
is a no-op for a store of roots, so a store that cannot block intermediates
relies on the roots in the list.

## Add a fingerprint

In a downstream Dockerfile, before its `build-stage` run:

```dockerfile
ENV B19_CA_DISTRUST="AB12…EF90 1234…CDEF"
```

or ship a file in the image’s `.container/base/etc/b19/ca-distrust.d/`, which
keeps a label next to each fingerprint.

## Turn it off

`B19_CA_DISTRUST_ENABLED=false` makes `list` print nothing, so every cutter
leaves its store untouched. Set it before the `build-stage` that would cut;
a store cut in a parent image stays cut.

## Check it

`test.d/0200-b19-ca-distrust.sh` fails when the system bundle still carries a
listed fingerprint, and pins the bundle filter with throwaway certificates.
