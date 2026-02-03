#!/usr/bin/env bash
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

#
# This file is a reference config.sh to use when adding a new package.
#

#
# Git URL for where your package is to be found
#
DEFAULT_PACKAGE_GIT_URL="https://github.com/tonynguien/bcc.git"

#
# If you are adding a third-package from an upstream git project, uncomment
# and fill the two lines below.
#
UPSTREAM_GIT_URL=https://github.com/iovisor/bcc.git
UPSTREAM_GIT_BRANCH=master

#
# If you are adding a third-party package based on an existing Ubuntu package,
# find the source package and fill the line below. Hint: the source package
# name is either the same as the package or will appear under "Source:" when
# running "apt show <package>"
#
#UPSTREAM_SOURCE_PACKAGE=bpfcc

#
# Install build dependencies for the package.
# (Optional function)
#
function prepare() {
	#
	# Useful helper functions:
	#
	#logmust install_pkgs build-dep-pkg1 build-dep-pkg2 ...
	#logmust install_build_deps_from_control_file
	# For Noble Numbat (24.04)
	# sudo apt install -y zip bison build-essential cmake flex git libedit-dev \
	# libllvm18 llvm-18-dev libclang-18-dev python3 zlib1g-dev libelf-dev libfl-dev python3-setuptools \
	# liblzma-dev libdebuginfod-dev arping netperf iperf libpolly-18-dev
	
	echo 'Install build dependencies'
	logmust install_pkgs zip bison build-essential cmake flex git libedit-dev \
	  libllvm18 llvm-18-dev libclang-18-dev python3 zlib1g-dev libelf-dev libfl-dev python3-setuptools \
	  liblzma-dev libdebuginfod-dev arping netperf iperf libpolly-18-dev dh-python debhelper python3-pyroute2
}

#
# Build the package.
# (Mandatory function)
#
function build() {
	#
	# This is the default functions to build the package:
	#
	#git clone https://github.com/iovisor/bcc.git
#mkdir bcc/build; cd bcc/build
#cmake ..
#make
#sudo make install
#cmake -DPYTHON_CMD=python3 .. # build python3 binding
#pushd src/python/
#make
#sudo make install
#popd
#
	echo "Remove bcc-lua"	
	logmust grep -RIl "usr/bin/bcc-lua" workdir/repo/debian | xargs -r rm -f
	logmust dpkg_buildpackage_default
}

#
# Hook to fetch upstream package changes and merge into our tree.
# (Optional function, only applies to third-party packages)
#
function update_upstream() {
	#
	# Useful helper functions:
	#
	#logmust update_upstream_from_source_package
	#logmust update_upstream_from_git
	echo 'update_upstream() - insert code here'
}
