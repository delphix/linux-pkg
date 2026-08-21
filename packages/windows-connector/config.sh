#!/usr/bin/env bash
#
# Copyright 2025, 2026 Delphix
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

function prepare() {
	logmust install_pkgs \
		openjdk-17-jdk-headless
}

#
# Rebuilding windows-connector is expensive, so skip it unless connectorDebVersion
# (bumped whenever the connector source changes; independent of connectorVersion,
# which is bumped once per release) has no matching artifact yet. Reuses the same
# "latest" artifact lookup every package already uses for its build dependencies;
# fails soft (falls through to a real build) if nothing is found there.
#
function build() {
	CONNECTOR_DIR="${WORKDIR}/repo/appliance/server/connector"
	INSTALLER_DIR="${WORKDIR}/repo/appliance/host/windows"

	local version
	version=$(grep "project.ext.connectorDebVersion" "$INSTALLER_DIR/build.gradle" |
		sed -E "s/.*'([^']+)'.*/\1/")
	local deb_name="windows-connector_${version}_all.deb"

	# Subshell so a missing "latest" pointer (get_package_dependency_s3_url
	# calls die/exit) only aborts this lookup, not the whole build.
	local latest_s3_url
	latest_s3_url=$(
		get_package_dependency_s3_url "windows-connector" 1>&2
		printf '%s' "$_RET"
	)

	if [[ -n "$latest_s3_url" ]]; then
		local bucket="${latest_s3_url#s3://}"
		bucket="${bucket%%/*}"
		local key="${latest_s3_url#s3://"$bucket"/}"

		if aws s3api head-object --bucket "$bucket" --key "$key/$deb_name" >/dev/null 2>&1; then
			echo "windows-connector $version already built (latest); nothing to do"
			#
			# Marker file, not a special exit code: the Jenkins pipeline checks for
			# this file's existence to set a NOT_BUILT result instead of relying on
			# a distinguished exit code from this stage.
			#
			touch "$WORKDIR/artifacts/.build_skipped"
			return 0
		fi
	fi

	echo "No reusable artifact found for windows-connector $version; building from source"
	logmust cd "$CONNECTOR_DIR"
	logmust sudo ../../gradlew build
	logmust cd "$INSTALLER_DIR"
	logmust sudo ../../gradlew createDebPackage
	logmust sudo mv ./build/distributions/*.deb "$WORKDIR/artifacts/"
}
