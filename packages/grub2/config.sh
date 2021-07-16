#!/bin/bash
#
# Copyright 2020 Delphix
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# shellcheck disable=SC2034

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/grub2"
PACKAGE_DEPENDENCIES="zfs"

UPSTREAM_GIT_URL=https://git.launchpad.net/ubuntu/+source/grub2
UPSTREAM_GIT_BRANCH=applied/ubuntu/focal-updates

SKIP_COPYRIGHTS_CHECK=true

#
# Install build dependencies for the package.
#
function prepare() {
	# Install libzfs which is required to build grub
	logmust install_pkgs "$DEPDIR"/zfs/{libnvpair1linux,libuutil1linux,libzfs2linux,libzpool2linux,libzfslinux-dev}_*.deb
	logmust install_build_deps_from_control_file
}

#
# Build the package.
#
function build() {
	logmust dpkg_buildpackage_default
}

#
# Hook to fetch upstream package changes and merge into our tree.
#
function update_upstream() {
	logmust update_upstream_from_git
}
