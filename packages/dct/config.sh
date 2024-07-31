#!/usr/bin/env bash
#
# Copyright 2024 Delphix
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
# DCT builds use this URL for storing their artifacts, so we have it hardcoded here.
#
DCT_S3_DIR="s3://snapshot-de-images"
DCT_LATEST_PREFIX="builds/jenkins-ops/dct/develop/post-push/latest"

function fetch() {
	logmust aws s3 cp "$DCT_S3_DIR/$DCT_LATEST_PREFIX" .

	DCT_PACKAGE_PREFIX=$(cat latest)
	logmust rm -f latest

	logmust cd artifacts
	logmust aws s3 sync "$DCT_S3_DIR/$DCT_PACKAGE_PREFIX" .
	logmust sha256sum -c SHA256SUMS
}

function build() {
	return
	# Nothing to do, all the logic is done in fetch().
}
