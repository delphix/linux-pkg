#!/bin/bash
#
# Copyright 2018 Delphix
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
PACKAGE_DEPENDENCIES="make-jpkg"

tarfile="OpenJDK8U-jdk_x64_linux_hotspot_8u262b10.tar.gz"
jdk_path="/usr/lib/jvm/adoptopenjdk-java8-jdk-amd64"

function prepare() {
	if ! ls "$TOP/packages/make-jpkg/tmp/artifacts/"*deb >/dev/null 2>&1; then
		echo_bold "custom java-package not installed. Building package 'make-jpkg' first."
		logmust "$TOP/buildpkg.sh" make-jpkg
	fi
}

function fetch() {
	logmust cd "$WORKDIR/"

	local url="http://artifactory.delphix.com/artifactory"

	logmust wget -nv "$url/java-binaries/linux/jdk/8/$tarfile" -O "$tarfile"
}

function build() {
	logmust cd "$WORKDIR/"

	logmust env DEB_BUILD_OPTIONS=nostrip fakeroot make-jpkg "$tarfile" <<<y

	logmust mv ./*deb "$WORKDIR/artifacts/"
	#
	# Store the install path of the JDK in a file so that the users of this
	# Java package know where to look. This is especially useful for
	# other linux-pkg packages that have a build dependency on this
	# particular version of Java, as they don't have to hardcode the
	# path in their build definition. This would also be useful if external
	# packages, such as the app-gate, decide to fetch and install Java from
	# the Linux-pkg bundle.
	#
	logmust bash -c "echo $jdk_path >'$WORKDIR/artifacts/JDK_PATH'"
	#
	# Install the Java package on this system so that other linux-pkg
	# packages can use it.
	#
	logmust install_pkgs "$WORKDIR/artifacts/"*.deb
}

function store_build_info() {
	echo "Tar file: $tarfile" >"$WORKDIR/build_info"
}
