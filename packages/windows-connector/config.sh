#!/usr/bin/env bash
#
# Copyright 2025 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/dlpx-app-gate.git"
SKIP_COPYRIGHTS_CHECK=true
PACKAGE_GIT_BRANCH="b0e62290fdc0a254af6212c823009670bcc2a911"

function build() {
	CONNECTOR_DIR="${WORKDIR}/repo/appliance/server/connector"
	INSTALLER_DIR="${WORKDIR}/repo/appliance/host/windows"
	logmust cd "$CONNECTOR_DIR"
	logmust sudo ../../gradlew build
	logmust cd "$INSTALLER_DIR"
	logmust sudo ../../gradlew createDebPackage
	logmust sudo mv ./build/distributions/*deb "$WORKDIR/artifacts/"
}
