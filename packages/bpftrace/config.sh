#!/bin/bash
#
# Copyright 2018, 2020 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/bpftrace.git"
DEFAULT_PACKAGE_VERSION=1.0.0
PACKAGE_DEPENDENCIES="bcc"

UPSTREAM_GIT_URL="https://github.com/iovisor/bpftrace.git"
UPSTREAM_GIT_BRANCH="master"

function prepare() {
	logmust install_pkgs "$DEPDIR"/bcc/libbcc_*.deb
	logmust install_build_deps_from_control_file
}

function build() {
	logmust dpkg_buildpackage_default
}

function update_upstream() {
	logmust update_upstream_from_git
}
