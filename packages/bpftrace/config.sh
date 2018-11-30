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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/bpftrace.git"
DEFAULT_PACKAGE_VERSION=1.0.0

UPSTREAM_GIT_URL="https://github.com/iovisor/bpftrace"
UPSTREAM_GIT_BRANCH="master"

function prepare() {

	#
	# Due to a bug in Ubuntu's version of Clang we need to fetch the packages
	# from the official llvm PPA.
	# See https://github.com/iovisor/bpftrace/issues/76.
	#
	logmust bash -c "wget -q -O - https://apt.llvm.org/llvm-snapshot.gpg.key |
		sudo apt-key add -"

	cat >/tmp/bpftrace-sources.list <<-EOF
		# from https://apt.llvm.org/:
		deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic main
		deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic main
		# 5.0
		deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-5.0 main
		deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic-5.0 main
	EOF

	logmust sudo mv /tmp/bpftrace-sources.list /etc/apt/sources.list.d/
	logmust sudo apt-get update

	logmust install_pkgs \
		bison \
		cmake \
		flex \
		g++ \
		libelf-dev \
		zlib1g-dev \
		libfl-dev \
		clang-5.0 \
		libclang-5.0-dev \
		libclang-common-5.0-dev \
		libclang1-5.0 \
		libllvm5.0 \
		llvm-5.0 \
		llvm-5.0-dev \
		llvm-5.0-runtime
}

function build() {
	logmust dpkg_buildpackage_default
	logmust store_git_info
}

function update_upstream() {
	logmust update_upstream_from_git
}
