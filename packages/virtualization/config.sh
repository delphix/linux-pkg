#!/bin/bash
#
# Copyright 2021 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://gitlab.delphix.com/app/dlpx-app-gate.git"
PACKAGE_DEPENDENCIES="adoptopenjdk crypt-blowfish host-jdks misc-debs"

function prepare() {
	logmust read_list "$WORKDIR/repo/appliance/packaging/build-dependencies"
	logmust install_pkgs "${_RET_LIST[@]}"

	logmust install_pkgs \
		"$DEPDIR"/adoptopenjdk/*.deb \
		"$DEPDIR"/crypt-blowfish/*.deb \
		"$DEPDIR"/host-jdks/*.deb \
		"$DEPDIR"/misc-debs/unzip_6.0-21ubuntu1_amd64.deb
}

function build() {
	export JAVA_HOME
	JAVA_HOME=$(cat "$DEPDIR/adoptopenjdk/JDK_PATH") ||
		die "Failed to read $DEPDIR/adoptopenjdk/JDK_PATH"

	export LANG
	LANG=en_US.UTF-8

	logmust cd "$WORKDIR/repo"

	#
	# The "appliance-build-stage0" Jenkins job consumes this file,
	# along with various other files (e.g. licensing metadata).
	# Thus, if we don't generate it here, the Jenkins job that
	# builds the appliance will fail.
	#
	# shellcheck disable=SC2016
	logmust jq -n \
		--arg h "$(git rev-parse HEAD)" \
		--arg d "$(date --utc --iso-8601=seconds)" \
		'{ "dlpx-app-gate" : { "git-hash" : $h, "date": $d }}' \
		>"$WORKDIR/artifacts/metadata.json"

	#
	# Build the virtualization package
	#
	logmust cd "$WORKDIR/repo/appliance"
	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		logmust ant -Ddockerize=true -DbuildJni=true \
			-DhotfixGenDlpxVersion="$DELPHIX_RELEASE_VERSION" \
			all package
	else
		logmust ant -Ddockerize=true -DbuildJni=true all package
	fi

	#
	# Publish the virtualization package artifacts
	#
	logmust cd "$WORKDIR/repo/appliance"
	logmust rsync -av packaging/build/distributions/ "$WORKDIR/artifacts/"
	logmust rsync -av \
		bin/out/common/com.delphix.common/uem/tars \
		"$WORKDIR/artifacts/hostchecker2"
	logmust cp -v \
		server/api/build/api/json-schemas/delphix.json \
		"$WORKDIR/artifacts"
	logmust cp -v \
		dist/server/opt/delphix/client/etc/api.ini \
		"$WORKDIR/artifacts"
	logmust cp -v \
		packaging/build/reports/dependency-license/* \
		"$WORKDIR/artifacts/"

	#
	# Build the "toolkit-devkit" artifacts
	#
	logmust cd "$WORKDIR/repo/appliance/toolkit"
	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		logmust ant \
			-Dversion.number="$DELPHIX_RELEASE_VERSION" \
			toolkit-devkit
	else
		logmust ant \
			"-Dversion.number=$(date --utc +%Y-%m-%d-%H-%m)" \
			toolkit-devkit
	fi

	#
	# Publish the "toolkit-devkit" artifacts
	#
	logmust cd "$WORKDIR/repo/appliance"
	logmust mkdir -p "$WORKDIR/artifacts/hostchecker2"
	logmust cp -v toolkit/toolkit-devkit.tar "$WORKDIR/artifacts"
}
