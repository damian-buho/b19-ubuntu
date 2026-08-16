# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

# M6E MAKEFILE T3

# Image naming (series-specific)

M6E_CONTAINER_NAME    = $(subst /,-,$(NAMESPACE))-$(PROJECT)-$(B19_UBUNTU_SERIES)
M6E_IMAGE_BASENAME    = $(NAMESPACE)/$(PROJECT)/$(B19_UBUNTU_SERIES)

# Generated make-target reference lives with the rest of the documentation
M6E_DOCS_PATH         = docs/how-to

# Rules
all: .makefile/core/initialize.mk

.makefile/core/initialize.mk:
	git submodule update --init --recursive
	$(MAKE) bootstrap

-include .makefile/core/initialize.mk
