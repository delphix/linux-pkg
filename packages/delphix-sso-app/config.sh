#!/usr/bin/env bash
#
# Copyright 2019, 2020 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/saml-app.git"
PACKAGE_DEPENDENCIES="adoptopenjdk"

function prepare() {
	logmust install_pkgs "$DEPDIR"/adoptopenjdk/*.deb
}

function build() {
	local java_home
	java_home=$(cat "$DEPDIR/adoptopenjdk/JDK_PATH") ||
		die "Failed to read $DEPDIR/adoptopenjdk/JDK_PATH"
	logmust cd "$WORKDIR/repo"
	logmust sudo ./gradlew "-Dorg.gradle.java.home=$java_home" distDeb
	logmust sudo mv ./build/distributions/*deb "$WORKDIR/artifacts/"
}
