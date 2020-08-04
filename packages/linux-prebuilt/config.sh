#!/bin/bash
#
# Copyright 2020 Delphix
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

DEFAULT_PACKAGE_GIT_URL=none

function _verify_kernel_version() {
	local requested="$1"
	local expected="$2"

	if [[ "$requested" != "$expected" ]]; then
		die "This package expects kernel '$expected' but the build" \
			"is requesting version '$requested'."
	fi
}

#
# Note: the linux-prebuilt package was created explicitly for the Delphix
# Appliance version 6.0.3.0. However, this fix could also apply to some later
# versions of the product as long as we keep the linux-package-mirror frozen.
# See https://github.com/delphix/linux-pkg/pull/96 for more context.
#
# It goes into details for why we do this.
#
function fetch() {
	local pkg_generic="linux-modules-5.3.0-53-generic_5.3.0-53.dx2_amd64.deb"
	local kvers_generic="5.3.0-53-generic"
	local pkg_aws="linux-modules-5.3.0-1019-aws_5.3.0-1019.dx2_amd64.deb"
	local kvers_aws="5.3.0-1019-aws"
	local pkg_azure="linux-modules-5.3.0-1022-azure_5.3.0-1022.dx2_amd64.deb"
	local kvers_azure="5.3.0-1022-azure"
	local pkg_gcp="linux-modules-5.3.0-1020-gcp_5.3.0-1020.dx2_amd64.deb"
	local kvers_gcp="5.3.0-1020-gcp"
	local pkg_oracle="linux-modules-5.3.0-1018-oracle_5.3.0-1018.dx2_amd64.deb"
	local kvers_oracle="5.3.0-1018-oracle"
	local url="http://artifactory.delphix.com/artifactory"
	url="$url/linux-pkg/linux-prebuilt/6.0.3.0/dx2"

	logmust cd "$WORKDIR/artifacts"

	logmust determine_target_kernels
	check_env KERNEL_VERSIONS

	#
	# Make sure that the target kernel versions match the versions of the
	# prebuilt kernel packages, otherwise the prebuilt packages will be
	# ignored by appliance-build.
	#
	local kvers
	for kvers in $KERNEL_VERSIONS; do
		case "$kvers" in
		*-generic) _verify_kernel_version "$kvers" "$kvers_generic" ;;
		*-aws) _verify_kernel_version "$kvers" "$kvers_aws" ;;
		*-azure) _verify_kernel_version "$kvers" "$kvers_azure" ;;
		*-gcp) _verify_kernel_version "$kvers" "$kvers_gcp" ;;
		*-oracle) _verify_kernel_version "$kvers" "$kvers_oracle" ;;
		esac
	done

	logmust wget -nv "$url/$pkg_generic"
	logmust wget -nv "$url/$pkg_aws"
	logmust wget -nv "$url/$pkg_azure"
	logmust wget -nv "$url/$pkg_gcp"
	logmust wget -nv "$url/$pkg_oracle"
}

function build() {
	return
	# Nothing to do. The packages are pre-built.
}
