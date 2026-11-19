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
SBOM_DEEP_SCAN="false"
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

		# USN-8974-1 (DLPX-100305): backport pcre2 10.42-4ubuntu2.2 to the
		# release-track appliance. Fixes CVE-2026-89161, -86145, -103111. Fetched
		# from the Delphix develop apt mirror (noble-updates/noble-security), which already
		# carries this fix.
		"libpcre2-8-0_10.42-4ubuntu2.2_amd64.deb f41da7cb7e979d6b037ea92650c72ec8ec532ec3c93aa8d5b997207de56695ea"

		# USN-8974-1 (DLPX-100305), follow-up: libpcre2-dev and its sibling libraries
		# must move to 10.42-4ubuntu2.2 together with libpcre2-8-0. libpcre2-dev is
		# pulled in by libselinux-dev and requires libpcre2-8-0, -16-0, -32-0 and
		# -posix3 at its own version, so with only libpcre2-8-0 bumped the build
		# dependency install fails with "held broken packages". Fetched from the
		# Delphix develop apt mirror (noble-updates/noble-security).
		"libpcre2-dev_10.42-4ubuntu2.2_amd64.deb 572714fe3fbe1b49ffb4c5a483223c663a51948e0d8590add1620917326f3d21"
		"libpcre2-16-0_10.42-4ubuntu2.2_amd64.deb a6365e17d88d5fb6223fe2b8cb4c8c65425aeac056e1a212a0151c95e83edf38"
		"libpcre2-32-0_10.42-4ubuntu2.2_amd64.deb 8415cabfaad4fce8633538d93f81f22ee1cef7b74dd7b323741424d17b10d898"
		"libpcre2-posix3_10.42-4ubuntu2.2_amd64.deb 90e4f67c2ce096716520ce190d7ae642714ddf692947bbe66e26272ace3cdf8d"

		# USN-8969-1 (DLPX-100314): backport bind9 1:9.18.39-0ubuntu0.24.04.9 to the
		# release-track appliance. Fixes CVE-2026-94300, -96888, -19630, -97313. Fetched
		# from the Delphix develop apt mirror (noble-updates/noble-security), which already
		# carries this fix.
		"bind9-host_1%3a9.18.39-0ubuntu0.24.04.9_amd64.deb 6230d7e1f6d7a5b356fc1dde8afb3e65574a760ffec4c51018dcfad79a1bc98e"
		"bind9-dnsutils_1%3a9.18.39-0ubuntu0.24.04.9_amd64.deb edb46901460a673ebb73c8d6742a2c0243fee673dff70a53f6ade420ba260f09"
		"bind9-libs_1%3a9.18.39-0ubuntu0.24.04.9_amd64.deb 8398995816db0090f7320717b6fade84f4c7ea353a04282fd4b29d1183b5b2b9"

		# DLPX-101047: backport openjdk-17 17.0.21.1+2-1~24.04.1 to the
		# patch-track appliance. Fixes CVE-2026-114938 ("Java4Shell"). Fetched
		# from the Ubuntu noble-security archive (published 2026-11-18; not yet
		# in the Delphix develop apt mirror snapshot).
		"openjdk-17-jdk-headless_17.0.21.1+2-1~24.04.1_amd64.deb 288c75d61943a1d7284868fae125118aa4b25c31294f090e209f4b0c614f2719"
		"openjdk-17-jre-headless_17.0.21.1+2-1~24.04.1_amd64.deb e7c01b78a2cbbafbb2f7ca9e03b85b4553db2c090ccb3175d8aff00ea47a2d63"

		# USN pending (DLPX-101075, "nginx2root"): backport nginx 1.24.0-2ubuntu7.20 to
		# the patch-track appliance. Fixes CVE-2026-123007, -123634, -123633, -113425.
		# Fetched from the Ubuntu noble-security archive (not yet in the Delphix
		# develop apt mirror snapshot).
		"nginx_1.24.0-2ubuntu7.20_amd64.deb 5076b4e1737d6fe9eddbd0dae4b8bd478f96fb88dad2bfd537de27bdc696e406"
		"nginx-common_1.24.0-2ubuntu7.20_all.deb 5362868fb4499e0547e9daa8a623eb5f59ea8477742f389157e952c689dde301"

		# USN-8996-1 (DLPX-101071): backport apt 2.8.4ubuntu0.1 to the
		# patch-track appliance. Fixes CVE-2026-109518. Fetched from the Delphix
		# develop apt mirror (noble-updates/noble-security), which already carries
		# this fix.
		"apt_2.8.4ubuntu0.1_amd64.deb ad2ea7f107f250ba88b0bfdba31812a341e3247589647aa2b03b9dc4e8abf8ed"
		"libapt-pkg6.0t64_2.8.4ubuntu0.1_amd64.deb a50f3e68a793f90b05f44a4b5f2f59f3ec7687e39b5d8bbd1da44c84671fa3d6"

		# USN-9065-1 (DLPX-101074): backport glibc 2.39-0ubuntu8.12 to the
		# patch-track appliance. Fixes CVE-2026-18374, -84243, -8674, -86805,
		# -89092, -95818, -97399. Fetched from the Delphix develop apt mirror
		# (noble-updates/noble-security), which already carries this fix.
		"libc6_2.39-0ubuntu8.12_amd64.deb d821b41fc59cb4978ecd53bc83e5c964ac15d305c8d2ac4c8a35aebe55010fb9"
		"nscd_2.39-0ubuntu8.12_amd64.deb 2b627b3e867f5c5b0affbcef1310ee41a77c978685049084beb837b4b57ba945"
		"locales_2.39-0ubuntu8.12_all.deb 0047f997c3799818514d1d08fece7cf2614a61e5505678bcf0c9558587a85d1d"
		"libc-bin_2.39-0ubuntu8.12_amd64.deb 22f0393621e72ed1b53d228ee332180269182b5445761c7d7b74f5cba75a1dd6"
		"libc6-dev_2.39-0ubuntu8.12_amd64.deb d81dd6dc9d515762cc93f338efa6219252acf3e2e87b5b89dd7dc517741e6eed"
		"libc-dev-bin_2.39-0ubuntu8.12_amd64.deb 74ac21dab2a0a6524a2cf9de623adf1bb1f7d9b672e6b0f70adec0c40452bae3"
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
