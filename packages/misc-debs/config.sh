#!/usr/bin/env bash
#
# Copyright 2021, 2023 Delphix
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
SKIP_COPYRIGHTS_CHECK=true

#
# IMPORTANT NOTE
# --------------
#
# Debian packages (debs) that are not built from source by linux-pkg can be
# added to this "meta-package". As a general rule, pre-built debs should only
# be added here when they have been fetched from a trusted third-party
# package archive.
#
# Here are some valid reasons for adding new debs here:
# - There are bugs with a recent version of a package provided by Ubuntu and
#   we want to pin an older version of that package.
# - Ubuntu provides a version of a package that is too old, and the package's
#   maintainers provide a more recent version of the package. Note that in this
#   case, you may also look into adding the maintainer's archive to the
#   linux-package-mirror PPAs list.
#
# To add a new deb here, upload that deb to the linux-pkg/misc-debs directory
# in artifcatory and note the deb's SHA256. Be explicit on where this deb
# was fetched from and why it was added to this list.
#
# When removing debs from this list, you should not remove them from artifactory
# as they would used when rebuilding older releases.
#

function fetch() {
	logmust cd "$WORKDIR/artifacts"

	local debs=(
		# mount-s3 (Mountpoint for Amazon S3) v1.22.3 — FUSE driver for mounting S3 buckets.
		# mount-s3 has no apt repository; fetched from AWS S3 and uploaded to Artifactory.
		# Source: https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
		# Required by HM-5952 (Hyperscale Snowflake connector S3 staging mounts). DLPXECO-13872.
		"mount-s3_1.22.3_amd64.deb 259a793b1233258b35ce5ce902df177393542fd76dd2a606f07e800e28591df6"
		#
		# python3.12 3.12.3-1ubuntu0.15 - Ubuntu USN-8509-1 (Python vulnerabilities).
		# Pin the fixed python3.12 binaries into the release appliance to remediate:
		#   CVE-2026-6100 (DLPX-97878), CVE-2025-69534 (DLPX-97875),
		#   CVE-2026-4786 (DLPX-97873), CVE-2026-4224 (DLPX-97869),
		#   CVE-2026-3644 (DLPX-97865).
		# Fetched from the Ubuntu 24.04 LTS (noble) noble-security/noble-updates archive.
		"libpython3.12-minimal_3.12.3-1ubuntu0.15_amd64.deb 5d16abf75f5a517c7e68dfbe888ddb40aa95d3b4445b1c223ec5ea23d2b01051"
		"libpython3.12-stdlib_3.12.3-1ubuntu0.15_amd64.deb 47c3b48809d392570e827cb3cdeacdf750af39fc36619c83337e28cbffea791c"
		"libpython3.12t64_3.12.3-1ubuntu0.15_amd64.deb 403683f2f773455bfac9ef0c830facbdb6801f616436054dad691ccfd00b4a30"
		"python3.12_3.12.3-1ubuntu0.15_amd64.deb d02d1769ca198be054f74fab22dc46299b4994c9c00bfdd6352938402e5eed1f"
		"python3.12-minimal_3.12.3-1ubuntu0.15_amd64.deb 487383dc2a895e0a767d820e0e55f2ab7d6ebe4dccd3d2c0b81f00ee11bb1152"
	)

	local url="http://artifactory.delphix.com/artifactory/linux-pkg/misc-debs"

	echo "Fetched debs:" >BUILD_INFO
	local entry
	for entry in "${debs[@]}"; do
		local deb sha256
		deb=$(echo "$entry" | awk '{print $1}')
		sha256=$(echo "$entry" | awk '{print $2}')
		[[ -n "$deb" && -n "$sha256" ]] || die "Invalid entry '$entry'"

		logmust fetch_file_from_artifactory "$url/$deb" "$sha256"

		echo "$entry" >>BUILD_INFO
	done
}

function build() {
	return
	# Nothing to do, all the logic is done in fetch().
}
