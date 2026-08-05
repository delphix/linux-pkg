#!/usr/bin/env bash
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

#
# This package has the same Git URL as the 'masking' package. In general we
# probably don't want to have multiple packages with the same URL, since tools
# like git-ab-pre-push expect that there is a 1:1 correspondence between
# packages and URLs. However, this is OK in this case because git-ab-pre-push
# only works with packages that are included in the appliance, which this one
# isn't.
#

source "$PWD/lib/common.sh"

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/dms-core-gate.git"
#
# The gradle task below reaches :tools:docker:buildLocalDockerImage, which builds
# a docker image and so needs a docker daemon. The build container gets the
# host's daemon through its socket rather than running one of its own.
#
# Without the socket the failure misdirects: the gradle-docker plugin defaults to
# the unix socket only when one is present and otherwise falls back to TCP, so it
# reports 'Connect to http://127.0.0.1:2375 failed: Connection refused' rather
# than anything about a missing socket.
#
PACKAGE_NEEDS_DOCKER="true"
MEND_SCAN_APPLICABLE="true"
MEND_SCAN_IMAGES="'delphix-masking-proxy', 'delphix-masking-database', 'delphix-masking-app'"

SKIP_COPYRIGHTS_CHECK=true

function prepare() {
	#
	# Same list, from the same repo, that the 'masking' package installs.
	# Without it no JDK is present at all: the JAVA_HOME below names a java-8
	# path that only ever existed because the buildserver happened to have
	# one, and dms-core-gate's own gradlew wrapper resets JAVA_HOME to Java 17
	# only when it can find a 17 JDK to switch to. That wrapper is why
	# 'masking' builds with the identical stale JAVA_HOME, so installing the
	# same dependencies here fixes this package the same way rather than
	# introducing a second, different convention.
	#
	logmust read_list "$WORKDIR/repo/packaging/build-dependencies"
	logmust install_pkgs "${_RET_LIST[@]}"
}

function build() {
	export JAVA_HOME
	JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64/"

	logmust cd "$WORKDIR/repo"

	local args=()

	set_secret_build_args
	args+=("${_SECRET_BUILD_ARGS[@]}")

	args+=("-Porg.gradle.configureondemand=false")
	args+=("-PenvironmentName=linuxappliance")

	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		args+=("-PmaskingVer=$DELPHIX_RELEASE_VERSION")
	fi

	logmust ./gradlew --no-daemon --stacktrace \
		"${args[@]}" \
		:tools:docker:packageMaskingKubernetes

	logmust cp -v tools/docker/build/masking-kubernetes*.zip \
		"$WORKDIR/artifacts/"
}
