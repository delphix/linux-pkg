#!/bin/bash
#
# Copyright 2021 Delphix
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

	#
	# Note about the debs being fetched:
	# - td-agent was built by the "td-agent" linux-pkg package, but it
	#   now fails to build due to broken third party dependencies. See
	#   DLPX-69338 and DLPX-68211.
	# - unzip was added as a temporary workaround to DLPX-73555.
	#
	local debs=(
		"td-agent_3.5.0-delphix-2019.09.18.20_amd64.deb 84dfa2436039ff2a6312484bd7295ebaf570b5f59f100380b57e68b4800855c4"
		"unzip_6.0-21ubuntu1_amd64.deb d46069c369ce88c8dd91c52abb8de8d6053606748ef18b3b9bc290fdd8ad2953"
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
