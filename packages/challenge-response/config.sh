#!/bin/bash
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

DEFAULT_PACKAGE_GIT_URL="https://gitlab.delphix.com/os-platform/linux-dlpx-pkgs.git"
DEFAULT_PACKAGE_VERSION="1.0.0"

function prepare() {
	logmust install_pkgs \
		libpam0g-dev \
		libssl-dev \
		uuid-dev
}

function build() {
	logmust cd "$WORKDIR/repo/challenge_response"
	logmust make package
	logmust mv ./x86_64/*.deb "$WORKDIR/artifacts/"
}
