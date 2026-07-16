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

source "$PWD/lib/common.sh"

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/dlpx-app-gate.git"
PACKAGE_DEPENDENCIES="crypt-blowfish host-jdks"
MEND_SCAN_APPLICABLE="true"

function prepare() {
	logmust read_list "$WORKDIR/repo/appliance/packaging/build-dependencies"
	logmust install_pkgs "${_RET_LIST[@]}"

	logmust install_pkgs \
		openjdk-17-jdk-headless \
		"$DEPDIR"/crypt-blowfish/*.deb \
		"$DEPDIR"/host-jdks/*.deb
}

#
# Optional validation hook: when PVM_GIT_URL/PVM_GIT_BRANCH are both set, build
# password_vault_manager from that ref, publish it to the local Maven repo, and
# point the appliance build's ivy resolution at it (see the
# third.party.local.maven.root property in dlpx-app-gate's
# appliance/ant/ivysettings.xml) instead of whatever version is pinned in
# appliance/gradle.properties. No-op (and no behavior change) when unset.
#
function build_local_password_vault_manager_jar() {
	logmust mkdir "$WORKDIR/pvm"
	logmust mkdir "$WORKDIR/pvm/repo"
	logmust cd "$WORKDIR/pvm/repo"
	logmust git init
	logmust git_fetch_helper "$PVM_GIT_URL" --no-tags "+$PVM_GIT_BRANCH:pvm-HEAD" --depth=1
	logmust git checkout pvm-HEAD

	#
	# Skip test/dxosTest here -- they already ran as part of
	# password-vault-manager-precommit-tests earlier in the pvm_precheckin flow. This step only
	# needs to produce and publish the jar.
	#
	logmust ./gradlew --no-daemon --stacktrace -x test -x dxosTest publishToMavenLocal

	PVM_LOCAL_VERSION="$(grep '^version=' gradle.properties | cut -d= -f2)"
	export PVM_LOCAL_VERSION
	echo_bold "Built password_vault_manager version ${PVM_LOCAL_VERSION} from" \
		"${PVM_GIT_URL} (${PVM_GIT_BRANCH}) and published it to the local Maven repo" \
		"(~/.m2/repository)."
}

function build() {
	export JAVA_HOME
	JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64/"

	export LANG
	LANG=en_US.UTF-8

	if [[ -n "$PVM_GIT_URL" && -n "$PVM_GIT_BRANCH" ]]; then
		logmust build_local_password_vault_manager_jar
	fi

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

	local args=()

	set_secret_build_args
	args+=("${_SECRET_BUILD_ARGS[@]}")

	args+=("-Dbuild.branch=$DEFAULT_GIT_BRANCH")

	args+=("-Ddockerize=true")
	args+=("-DbuildJni=true")

	if [[ -n "$DELPHIX_RELEASE_VERSION" ]]; then
		args+=("-DhotfixGenDlpxVersion=$DELPHIX_RELEASE_VERSION")
	fi

	if [[ -n "$PVM_LOCAL_VERSION" ]]; then
		args+=("-Dthird.party.local.maven.root=file://$HOME/.m2/repository")
		export ORG_GRADLE_PROJECT_passwordVaultManagerVer="$PVM_LOCAL_VERSION"
		echo_bold "Using LOCALLY-BUILT password_vault_manager ${PVM_LOCAL_VERSION} for this build" \
			"-- NOT fetched from Artifactory. ivy will resolve" \
			"com.delphix.vault:password-vault-manager:${PVM_LOCAL_VERSION} from the local Maven repo" \
			"(~/.m2/repository) instead."
	else
		echo "PVM_GIT_URL/PVM_GIT_BRANCH not set: password-vault-manager will be fetched from" \
			"Artifactory as usual, using the version pinned in appliance/gradle.properties."
	fi

	logmust ant "${args[@]}" all-secrets package

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
