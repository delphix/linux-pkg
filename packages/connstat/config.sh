#!/bin/bash
#
# Copyright 2018 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/connstat.git"
DEFAULT_PACKAGE_VERSION="1.0.0"

function prepare() {
	logmust install_pkgs \
		debhelper \
		dpkg-dev
	logmust install_kernel_headers
}

function build() {
	logmust determine_target_kernels
	check_env KERNEL_VERSIONS

	logmust cd "$WORKDIR/repo/module"
	export KVERS
	for KVERS in $KERNEL_VERSIONS; do
		echo_bold "Building connstat-module-$KVERS"
		logmust git clean -qdxf
		logmust ./configure.sh
		logmust set_changelog connstat
		logmust dpkg-buildpackage -b -us -uc
	done

	logmust cd "$WORKDIR/repo/usr"
	echo_bold "Building connstat-util"
	logmust git clean -qdxf
	logmust set_changelog connstat-util
	logmust dpkg-buildpackage -b -us -uc

	logmust cd "$WORKDIR/repo"
	logmust mv ./*.deb "$WORKDIR/artifacts/"

	logmust store_git_info
}
