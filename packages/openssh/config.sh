#!/usr/bin/env bash
#
# Copyright 2025 Delphix
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

SKIP_COPYRIGHTS_CHECKS=true
DEFAULT_PACKAGE_GIT_URL=none

function fetch() {
	logmust apt-get source openssh
}

function prepare() {
	logmust pushd openssh-9.6p1

	# Enable xtrace for postinst hook
	logmust sed -i '1c\/bin/bash -x' debian/openssh-server.postinst

	logmust sudo env DEBIAN_FRONTEND=noninteractive mk-build-deps --install \
		--tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' \
		debian/control

	logmust popd
}

function build() {
	logmust pushd openssh-9.6p1
	logmust set_changelog
	logmust dpkg-buildpackage -b -us -uc
	logmust mv ../*deb "$WORKDIR/artifacts"
	logmust popd
}
