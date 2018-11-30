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

TOP="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$TOP/lib/common.sh"

logmust check_running_system

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0")"
	echo ""
	echo "  This script fetches and builds all the packages defined in"
	echo "  packages-lists/buildall.pkgs, as well as the metapackage."
	echo ""
	exit 2
}

[[ $# -eq 0 ]] || usage "takes no arguments." >&2

logmust cd "$TOP"

logmust make clean
logmust mkdir artifacts

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
# Note that we do not build all the packages under the packages/ directory,
# but instead rely on the buildall.pkgs package list. This allows us to
# add new packages to the framework that aren't part of the buildall bundle.
#
logmust read_package_list "$TOP/package-lists/buildall.pkgs"
PACKAGES=("${_RET_LIST[@]}")

for pkg in "${PACKAGES[@]}"; do
	# shellcheck disable=SC2086
	logmust ./buildpkg.sh $build_flags "$pkg"
done

logmust pushd metapackage
export METAPACKAGE_VERSION="1.0.0-$DEFAULT_REVISION"
logmust make deb
logmust popd
logmust mv metapackage/artifacts/* artifacts/

for pkg in "${PACKAGES[@]}"; do
	logmust mv "packages/$pkg/tmp/artifacts"/* artifacts/
done
logmust cp metapackage/etc/delphix-extra-build-info artifacts/build-info

echo_success "Packages have been built successfully."
