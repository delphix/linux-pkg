#!/bin/bash
#
# Copyright 2019 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://gitlab.delphix.com/app/saml-app.git"
JDK_PATH_FILE="$TOP/packages/adoptopenjdk/tmp/artifacts/JDK_PATH"
PACKAGE_DEPENDENCIES="adoptopenjdk"

function prepare() {
	java_package_exists=$(dpkg-query --show adoptopenjdk-java8-jdk >/dev/null 2>&1)
	if [[ ! $java_package_exists && ! -f $JDK_PATH_FILE ]]; then
		echo_bold "java8 not installed. Building package 'adoptopenjdk' first."
		logmust "$TOP/buildpkg.sh" adoptopenjdk
	fi
}

function build() {
	local java_home
	java_home=$(cat "$JDK_PATH_FILE")
	logmust cd "$WORKDIR/repo"
	logmust sudo ./gradlew "-Dorg.gradle.java.home=$java_home" distDeb
	logmust sudo mv ./build/distributions/*deb "$WORKDIR/artifacts/"
}
