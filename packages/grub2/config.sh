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
	logmust cd "$WORKDIR"

	local url="http://artifactory.delphix.com/artifactory/linux-pkg/misc-debs"
	local grub="grub-2.12-1ubuntu7.tar.gz"

	logmust fetch_file_from_artifactory "$url/grub-2.12-1ubuntu7.tar.gz" \
		"8d0fe5bee9380906be7006fcb069ef494f07c76f07e66ae7497cdb4e071955da"

	logmust tar -xvf "grub-2.12-1ubuntu7.tar.gz"
	logmust cp grub-2.12-1ubuntu7/* artifacts
}

function build() {
	return
	# Nothing to do, all the logic is done in fetch().
}
