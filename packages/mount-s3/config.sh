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

#
# mount-s3 (Mountpoint for Amazon S3) — FUSE driver for mounting S3 buckets.
#
# mount-s3 has no apt repository; Amazon only distributes it as a direct .deb
# download from S3. The .deb has been uploaded to Artifactory for reproducible
# builds. Required by HM-5952 for the Hyperscale Snowflake connector to mount
# S3 staging areas at /mnt/hyperscale.
#
# Source: https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
# OSRB tracking: DLPXECO-13872
#

DEFAULT_PACKAGE_GIT_URL=none
SKIP_COPYRIGHTS_CHECK=true

_DEB="mount-s3_1.22.3_amd64.deb"
_DEB_SHA256="259a793b1233258b35ce5ce902df177393542fd76dd2a606f07e800e28591df6"

function fetch() {
	logmust cd "$WORKDIR/artifacts"

	local url="http://artifactory.delphix.com/artifactory/linux-pkg/mount-s3/$_DEB"
	logmust fetch_file_from_artifactory "$url" "$_DEB_SHA256"

	echo "Fetched: $_DEB ($_DEB_SHA256)" >BUILD_INFO
}

function build() {
	# Nothing to do — the deb is fetched directly in fetch().
	return
}
