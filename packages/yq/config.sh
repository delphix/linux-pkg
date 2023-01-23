#!/usr/bin/env bash
#
# Copyright 2023 Delphix
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

DEFAULT_PACKAGE_GIT_URL="none"

case $(dpkg-architecture -q DEB_HOST_ARCH 2>/dev/null || echo "none") in
amd64)
	_binfile="yq_linux_amd64"
	_tarfile="yq_linux_amd64.tar.gz"
	_tarfile_sha256="2e07c9b81699a6823dafc36a9c01aef5025179c069fedd42b1c6983545386771"
	;;
*) ;;

esac

function prepare() {
	logmust install_pkgs equivs
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

	local url="https://artifactory.delphix.com/artifactory/linux-pkg/yq/$_tarfile"

	logmust fetch_file_from_artifactory "$url" "$_tarfile_sha256"
}

function build() {
	if [[ -z "$_tarfile" ]]; then
		echo "Invalid architecture detected" >&2
		exit 1
	fi

	logmust cd "$WORKDIR/"
	logmust tar -xvf "$_tarfile"
	logmust mv "$_binfile" yq
	logmust equivs-build ../package.ctl
	logmust mv ./*deb "$WORKDIR/artifacts/"
}
