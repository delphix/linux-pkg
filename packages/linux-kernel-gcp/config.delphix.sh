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
DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/linux-kernel-gcp.git"

UPSTREAM_GIT_URL="https://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-gcp/+git/bionic"
# Note: UPSTREAM_GIT_BRANCH is not used here
UPSTREAM_GIT_BRANCH="none"

#
# Force push required when syncing with upstream because we perform a rebase.
#
FORCE_PUSH_ON_UPDATE=true

function prepare() {
	logmust kernel_prepare
}

function build() {
	logmust kernel_build "gcp"
}

function update_upstream() {
	logmust kernel_update_upstream "gcp"
}

function merge_with_upstream() {
	logmust kernel_merge_with_upstream
}
