#!/bin/bash
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
DEFAULT_PACKAGE_GIT_URL="https://gitlab.delphix.com/os-platform/gdb-python.git"
DEFAULT_PACKAGE_VERSION=1.0.0

function prepare() {
	logmust install_pkgs \
		autoconf \
		automake \
		bison \
		flex \
		git \
		liblzo2-dev \
		libmpfr-dev \
		libsnappy1v5 \
		libtool \
		pkg-config \
		python3-distutils \
		python3-future \
		python3-pyelftools \
		python3.6-dev \
		texinfo \
		zlib1g-dev
}

function build() {
	logmust dpkg_buildpackage_default
}
