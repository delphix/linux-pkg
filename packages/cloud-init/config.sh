#!/usr/bin/env bash
#
# Copyright 2018, 2019 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/cloud-init.git"

UPSTREAM_SOURCE_PACKAGE=cloud-init

function prepare() {
	logmust install_build_deps_from_control_file
}

function checkstyle() {
	logmust cd "$WORKDIR/repo"
	logmust make style-check
}

function build() {
	#
	# We set this environment variable to coerce the "read-version"
	# script (part of the cloud-init repository) to behave correctly
	# (for us) when it's run as part of the cloud-init build system.
	#
	# Specifically, without this set, the cloud-init build system
	# will attempt to dynamically set the package version based on
	# the upstream git tags that it expects to exist. The problem
	# for us, is these upstream git tags don't exist when we do the
	# package build, and even if they did exist, our repository's
	# git history is completely unrelated to the upstream git
	# history, due to how we merge with Ubuntu (i.e. using Ubuntu's
	# source package, rather than a git repository).
	#
	# Thus, without this setting, the build will fail when it tries
	# to dynamically set the package version.
	#
	export TRAVIS_PULL_REQUEST_BRANCH="upstream/"

	logmust dpkg_buildpackage_default
}

function update_upstream() {
	logmust update_upstream_from_source_package
}
