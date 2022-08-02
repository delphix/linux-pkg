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

_tarfile="OpenJDK8U-jdk_x64_linux_hotspot_8u342b07.tar.gz"
_tarfile_sha256="8252c0e11d542ea0f9ce6b8f147d1a2bea4a17e9fc299da270288f5a4f35b1f3"
_jdk_path="/usr/lib/jvm/adoptopenjdk-java8-jdk-amd64"

function prepare() {
	logmust install_pkgs "$DEPDIR"/make-jpkg/*.deb
}

function fetch() {
	logmust cd "$WORKDIR/"

	local url="http://artifactory.delphix.com/artifactory/java-binaries/linux/jdk/8/$_tarfile"

	logmust fetch_file_from_artifactory "$url" "$_tarfile_sha256"
}

function build() {
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
