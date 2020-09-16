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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/delphix-platform.git"
DEFAULT_PACKAGE_VERSION="1.0.0"

function build() {
	logmust cd "$WORKDIR/repo"
	logmust ansible-playbook bootstrap/playbook.yml
	logmust ./scripts/docker-run.sh make packages \
		VERSION="$PACKAGE_VERSION-$PACKAGE_REVISION"
	logmust sudo chown -R "$USER:" artifacts
	logmust mv artifacts/*deb "$WORKDIR/artifacts/"
}
