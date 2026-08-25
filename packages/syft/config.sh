#!/usr/bin/env bash
#
# Copyright 2026 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/syft.git"

function build() {
	logmust mkdir -p "$WORKDIR/repo"

	#
	# Instead of relying on linux-pkg to assign a default version like 1.0.0, set the
	# version of the delphix-syft package to the pinned Syft version. This is done so
	# that "dpkg -l delphix-syft" on a build host can tell you which Syft actually
	# produced a given CycloneDX SBOM.
	#
	PACKAGE_VERSION="$(tr -d '\n' <"$WORKDIR/repo/SYFT_VERSION")"
	[[ -n "$PACKAGE_VERSION" ]] || die "Failed to retrieve package version"

	logmust dpkg_buildpackage_default
}
