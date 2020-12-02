#!/bin/bash
#
# Copyright 2019, 2020 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/make-jpkg.git"
# Note we auto-detect version in build()

UPSTREAM_GIT_URL=https://salsa.debian.org/java-team/java-package.git
UPSTREAM_GIT_BRANCH=master

function build() {
	# Auto-detect version from upstream.
	# Make sure it is a base version, without revision.
	logmust cd "$WORKDIR/repo"
	PACKAGE_VERSION=$(dpkg-parsechangelog --show-field Version)
	if [[ "$PACKAGE_VERSION" == *-* ]]; then
		die "Bad package version '$PACKAGE_VERSION': should not contain '-'"
	fi

	logmust dpkg_buildpackage_default
}

function update_upstream() {
	logmust update_upstream_from_git
}
