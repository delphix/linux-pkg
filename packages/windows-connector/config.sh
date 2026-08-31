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

#
# windows-connector's post-push job no longer auto-triggers on every
# dlpx-app-gate push (see README.md in this directory for why). Setting this
# to "none" tells the Job DSL to disable that job's push trigger; source is
# still fetched from the real repo via the fetch() override below, which
# doesn't depend on this variable.
#
DEFAULT_PACKAGE_GIT_URL="none"
SKIP_COPYRIGHTS_CHECK=true

function fetch() {
	PACKAGE_GIT_URL="https://github.com/delphix/dlpx-app-gate.git"
	logmust fetch_repo_from_git
}

function prepare() {
	logmust install_pkgs \
		openjdk-17-jdk-headless
}

function build() {
	CONNECTOR_DIR="${WORKDIR}/repo/appliance/server/connector"
	INSTALLER_DIR="${WORKDIR}/repo/appliance/host/windows"
	logmust cd "$CONNECTOR_DIR"
	logmust sudo ../../gradlew build
	logmust cd "$INSTALLER_DIR"
	logmust sudo ../../gradlew createDebPackage
	logmust sudo mv ./build/distributions/*deb "$WORKDIR/artifacts/"
}
