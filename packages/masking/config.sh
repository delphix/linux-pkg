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

DEFAULT_PACKAGE_GIT_URL="https://gitlab.delphix.com/masking/dms-core-gate.git"
PACKAGE_DEPENDENCIES="adoptopenjdk"

function prepare() {
	logmust install_pkgs "$DEPDIR"/adoptopenjdk/*.deb
}

function build() {
	export JAVA_HOME
	JAVA_HOME=$(cat "$DEPDIR/adoptopenjdk/JDK_PATH") ||
		die "Failed to read $DEPDIR/adoptopenjdk/JDK_PATH"

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
		'{ "dms-core-gate" : { "git-hash" : $h, "date": $d }}' \
		>"$WORKDIR/artifacts/metadata.json"

	logmust ./gradlew --no-daemon --stacktrace \
		-Porg.gradle.configureondemand=false \
		-PenvironmentName=linuxappliance \
		clean \
		generateLicenseReport \
		:dist:distDeb \
		:dist:distLicenseReport

	logmust rsync -av dist/build/distributions/ "$WORKDIR/artifacts/"
	logmust cp -v \
		dist/build/reports/dependency-license/* "$WORKDIR/artifacts/"
}
