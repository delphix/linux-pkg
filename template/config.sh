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

#
# This file is a reference config.sh to use when adding a new package.
#

#
# Git URL for where your package is to be found
#
DEFAULT_PACKAGE_GIT_URL="https://example.com/my-package-repository.git"

#
# A version for the package must be provided in DEFAULT_PACKAGE_VERSION.
# For an original Delphix package, the value for the version is not important,
# so you can set it to anything (e.g. 1.0.0).
# For a third-party package, this should match the version of the upstream
# package. Note that an alternative is to leave DEFAULT_PACKAGE_VERSION
# undefined and to programatically obtain PACKAGE_VERSION from the package's
# source code.
#
#DEFAULT_PACKAGE_VERSION=1.0.0

#
# If you are adding a third-package from an upstream git project, uncomment
# and fill the two lines below.
#
#UPSTREAM_GIT_URL=https://example.com/awesome-third-party-package.git
#UPSTREAM_GIT_BRANCH=master

#
# If you are adding a third-party package based on an existing Ubuntu package,
# find the source package and fill the line below. Hint: the source package
# name is either the same as the package or will appear under "Source:" when
# running "apt show <package>"
#
#UPSTREAM_SOURCE_PACKAGE=awesome-third-party-package

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
	echo 'insert code here'
}

#
# Build the package.
# (Mandatory function)
#
function build() {
	#
	# This is the default functions to build the package:
	#
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
	echo 'insert code here'
}
