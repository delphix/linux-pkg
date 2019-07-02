#!/bin/bash
#
# Copyright 2018, 2019 Delphix
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

#
# This script first builds a list of packages by running buildpkg.sh on each
# package, and then generates a build-info package. All the build products are
# stored in the ./artifacts directory. Valid package lists are stored in
# package-lists/build/
#

TOP="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$TOP/lib/common.sh"

logmust check_running_system

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") <list>"
	echo ""
	echo "  This script fetches and builds all the packages defined in"
	echo "  package-lists/build/<list>.pkgs."
	echo ""
	exit 2
}

[[ $# -eq 1 ]] || usage "takes exactly one argument." >&2

pkg_list="$1"
logmust get_package_list_file "build" "$pkg_list"
pkg_list_file="$_RET"

logmust cd "$TOP"
logmust make clean
logmust mkdir artifacts
logmust mkdir artifacts/cache

#
# Auto-generate the default revision for all the packages. It will be the
# default used if the revision is not set explicitly anywhere else.
#
export DEFAULT_REVISION="${DEFAULT_REVISION:-$(default_revision)}"
#
# Default branch to checkout when fetching source code for packages. Note that
# this can be overriden by per-package settings.
#
export DEFAULT_GIT_BRANCH="${DEFAULT_GIT_BRANCH:-master}"

#
# A list of target platform or versions to build modules for can be passed in
# TARGET_PLATFORMS. Convert values like "aws" into actual kernel
# versions and store them into KERNEL_VERSIONS.
#
logmust determine_target_kernels
export KERNEL_VERSIONS

build_flags=""
if [[ "$CHECKSTYLE" == "true" ]]; then
	build_flags="${build_flags} -c"
fi

#
# Get the list of packages to build.
#
logmust read_package_list "$pkg_list_file"
PACKAGES=("${_RET_LIST[@]}")

for pkg in "${PACKAGES[@]}"; do
	# shellcheck disable=SC2086
	logmust ./buildpkg.sh $build_flags "$pkg"
done

logmust build-info-pkg/build-package.sh "$pkg_list"
logmust cp build-info-pkg/artifacts/* artifacts/

for pkg in "${PACKAGES[@]}"; do
	logmust cp "packages/$pkg/tmp/artifacts"/* artifacts/

	#
	# Cache each package's artifacts in a separate directory so that they
	# can be easily retrieved by future linux-pkg builds. Note that those
	# artifacts are not consumed by appliance-build.
	#
	logmust mkdir -p "artifacts/cache/$pkg/artifacts"
	logmust cp "packages/$pkg/tmp/artifacts"/* \
		"artifacts/cache/$pkg/artifacts/"
	if [[ -f "packages/$pkg/tmp/build_info" ]]; then
		logmust cp "packages/$pkg/tmp/build_info" \
			"artifacts/cache/$pkg/"
	fi
done

echo_success "Packages have been built successfully."
