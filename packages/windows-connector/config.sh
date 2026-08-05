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
PACKAGE_GIT_BRANCH="dlpx/pr/vimleshmishra/716aac3d-399f-43c7-9b80-c373ab6f7218"

function prepare() {
	logmust install_pkgs \
		openjdk-17-jdk-headless
}

#
# windows-connector is only rebuilt when its version (project.ext.connectorVersion
# in appliance/host/windows/build.gradle) is bumped. If that version has already
# been built and uploaded to Artifactory, we just download the existing installer
# instead of rebuilding. Otherwise we build it and upload the result to Artifactory
# so future builds of the same version can reuse it. The upload uses the BLACKBOX_USERNAME/
# BLACKBOX_PASSWORD credential exposed by the linux_pkg_build_package.groovy pipeline
# (devops-gate) - the same 'blackbox' credential already used to publish DCT's Artifactory
# artifacts in api_gw_services_build_publish_post_push.groovy.
#
function build() {
	CONNECTOR_DIR="${WORKDIR}/repo/appliance/server/connector"
	INSTALLER_DIR="${WORKDIR}/repo/appliance/host/windows"

	local version
	version=$(grep "project.ext.connectorVersion" "$INSTALLER_DIR/build.gradle" |
		sed -E "s/.*'([^']+)'.*/\1/")
	local artifactory_dir="http://artifactory.delphix.com/artifactory/third-party-local/windows-connector/$version"
	local deb_name="windows-connector_${version}_all.deb"

	if wget --spider -q "$artifactory_dir/$deb_name"; then
		echo "windows-connector $version already built; downloading pre-built installer from Artifactory"
		logmust cd "$WORKDIR/artifacts"
		logmust fetch_file_from_artifactory "$artifactory_dir/$deb_name"
	else
		echo "windows-connector $version not found in Artifactory; building from source"
		logmust cd "$CONNECTOR_DIR"
		logmust sudo ../../gradlew build
		logmust cd "$INSTALLER_DIR"
		logmust sudo ../../gradlew createDebPackage
		logmust cp ./build/distributions/*.deb "$WORKDIR/artifacts/$deb_name"

		if [[ -z "$BLACKBOX_USERNAME" || -z "$BLACKBOX_PASSWORD" ]]; then
			echo "WARNING: BLACKBOX_USERNAME/BLACKBOX_PASSWORD not set - skipping Artifactory upload." \
				"Upload $WORKDIR/artifacts/$deb_name to $artifactory_dir/ manually so future builds can reuse it."
		else
			echo "Uploading $deb_name to $artifactory_dir/"
			local http_code
			http_code=$(curl -s -o /dev/stderr -w "%{http_code}" \
				-u "${BLACKBOX_USERNAME}:${BLACKBOX_PASSWORD}" \
				-T "$WORKDIR/artifacts/$deb_name" "$artifactory_dir/$deb_name")
			echo "Artifactory upload HTTP status: $http_code"
			if [[ "$http_code" != 2* ]]; then
				echo "WARNING: upload did not return a 2xx status (see curl output above)"
			fi
		fi
	fi
}
