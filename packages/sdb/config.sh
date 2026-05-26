#!/usr/bin/env bash
#
# Copyright 2019 Delphix
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
DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/sdb.git"

UPSTREAM_GIT_URL="https://github.com/sdimitro/sdb.git"
UPSTREAM_GIT_BRANCH="develop"

function prepare() {
	logmust install_build_deps_from_control_file
}

function build() {
	local scm_version
	scm_version=$(cd "$WORKDIR/repo" && python3 -m setuptools_scm 2>/dev/null) ||
		die "setuptools_scm version derivation failed"
	#
	# pyproject.toml sets local_scheme="no-local-version", so the value
	# is debian-version-safe. Pass it through as-is; linux-pkg's
	# set_changelog appends "-1delphix.<ts>" since PACKAGE_VERSION has
	# no "-", producing e.g. "0.6.0-1delphix.<ts>".
	#
	export PACKAGE_VERSION="${scm_version}"
	logmust dpkg_buildpackage_default
}

function update_upstream() {
	logmust update_upstream_from_git
}
