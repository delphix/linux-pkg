#!/usr/bin/env bash
#
# Copyright 2018, 2022 Delphix
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

case $(dpkg-architecture -q DEB_HOST_ARCH 2>/dev/null || echo "none") in
amd64)
	_tarfile="OpenJDK8U-jdk_x64_linux_hotspot_8u345b01.tar.gz"
	_tarfile_sha256="ed6c9db3719895584fb1fd69fc79c29240977675f26631911c5a1dbce07b7d58"
	_jdk_path="/usr/lib/jvm/adoptopenjdk-java8-jdk-amd64"
	;;
arm64)
	_tarfile="OpenJDK8U-jdk_aarch64_linux_hotspot_8u345b01.tar.gz"
	_tarfile_sha256="c1965fb24dded7d7944e2da36cd902adf3b7b1d327aaa21ea507cff00a5a0090"
	_jdk_path="/usr/lib/jvm/adoptopenjdk-java8-jdk-arm64"
	;;
*) ;;

esac

function prepare() {
	logmust install_pkgs "$DEPDIR"/make-jpkg/*.deb
}

function fetch() {
	# We exit here rather than above in the architecture detection logic
	# to deal with the fact that this file can, during test runs, be
	# sourced on platforms where builds are not happening. list-packages
	# sources the file to gather information about the package, and this
	# is performed on jenkins and macos during test runs. Having the exit
	# occur above causes those runs to fail.
	if [[ -z "$_tarfile" ]]; then
		echo "Invalid architecture detected" >&2
		exit 1
	fi
	logmust cd "$WORKDIR/"

	local url="http://artifactory.delphix.com/artifactory/java-binaries/linux/jdk/8/$_tarfile"

	logmust fetch_file_from_artifactory "$url" "$_tarfile_sha256"
}

function build() {
	if [[ -z "$_tarfile" ]]; then
		echo "Invalid architecture detected" >&2
		exit 1
	fi
	logmust cd "$WORKDIR/"

	logmust env DEB_BUILD_OPTIONS=nostrip fakeroot make-jpkg "$_tarfile" <<<y

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
	logmust bash -c "echo $_jdk_path >'$WORKDIR/artifacts/JDK_PATH'"

	echo "Tar file: $_tarfile" >"$WORKDIR/artifacts/BUILD_INFO"
}
