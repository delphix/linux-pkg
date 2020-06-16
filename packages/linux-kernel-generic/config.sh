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
DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/linux-kernel-generic.git"

UPSTREAM_GIT_URL="https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/bionic"
UPSTREAM_GIT_BRANCH="@PLACEHOLDER-WORKAROUND@"

function prepare() {
	kernel_prepare
}

function build() {
	#
	# flavours=generic
	#   By default the generic kernel variant from Canonical
	#   builds both the generic and the low-latency kernel.
	#   We don't care about the latter.
	#
	kernel_build "generic" "flavours=generic"
}

function update_upstream() {
	kernel_update_upstream "generic"
}
