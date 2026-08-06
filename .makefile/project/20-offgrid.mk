# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

APT_LISTS_HOST_PATH  ?= /var/lib/apt/lists
APT_LISTS_FETCH_DIR  := .fetch/apt-lists

#@ Fetch | Copy host APT package lists for offgrid builds
copy-apt-lists:
	mkdir -p $(APT_LISTS_FETCH_DIR)
	cp -rp $(APT_LISTS_HOST_PATH)/. $(APT_LISTS_FETCH_DIR)/

#@ Fetch | Remove copied APT lists
copy-apt-lists-clean:
	rm -rf $(APT_LISTS_FETCH_DIR)
