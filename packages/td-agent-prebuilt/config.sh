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

DEFAULT_PACKAGE_GIT_URL=none
SKIP_COPYRIGHTS_CHECK=true

function fetch() {
	logmust cd "$WORKDIR/artifacts"
	local package="td-agent_3.5.0-delphix-2019.09.18.20_amd64.deb"
	local url="http://artifactory.delphix.com/artifactory"

	logmust wget -nv "$url/linux-pkg/td-agent/$package" -O "$package"
}

function build() {
	return
	# Nothing to do. See the td-agent package config for the actual build.
}
