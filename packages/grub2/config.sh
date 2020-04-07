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

UPSTREAM_SOURCE_PACKAGE=grub2

#
# Install build dependencies for the package.
#
function prepare() {
	if ! dpkg-query --show libzfslinux-dev >/dev/null 2>&1; then
		echo_bold "libzfs not installed. Building package 'zfs' first."
		logmust "$TOP/buildpkg.sh" zfs
	fi

	logmust install_build_deps_from_control_file
	return
}

#
# Build the package.
#
function build() {
	logmust cd "$WORKDIR/repo"
	if [[ -z "$PACKAGE_VERSION" ]]; then
		logmust eval PACKAGE_VERSION="$(dpkg-parsechangelog -S Version | \
		    awk -F'-' '{print $1}')"
	fi
	logmust dpkg_buildpackage_default
}

#
# Hook to fetch upstream package changes and merge into our tree.
#
function update_upstream() {
	logmust update_upstream_from_source_package
	return
}
