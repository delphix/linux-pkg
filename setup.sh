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

#
# Update the sources.list file to point to our internal package mirror. If no
# mirror url is passed in, then the latest mirror snapshot is used.
#
configure_apt_sources() {
	local package_mirror_url=''
	if [[ -n "$DELPHIX_PACKAGE_MIRROR_MAIN" ]]; then
		package_mirror_url="$DELPHIX_PACKAGE_MIRROR_MAIN"
	else
		local latest_url="http://linux-package-mirror.delphix.com/"
		latest_url+="${DEFAULT_GIT_BRANCH}/latest/"
		package_mirror_url=$(curl -LfSs -o /dev/null -w '%{url_effective}' \
			"$latest_url" || die "Could not curl $latest_url")

		package_mirror_url+="ubuntu"
	fi

	#
	# Remove other sources in sources.list.d if they are present.
	#
	[[ -d /etc/apt/sources.list.d ]] && (
		logmust sudo rm -rf /etc/apt/sources.list.d ||
			die "Could not remove /etc/apt/sources.list.d"
	)

	sudo bash -c "cat <<-EOF >/etc/apt/sources.list
deb ${package_mirror_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse
deb-src ${package_mirror_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse

deb ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse
deb-src ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse

deb ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse
deb-src ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse

deb ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse
deb-src ${package_mirror_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse
EOF" || die "/etc/apt/sources.list could not be updated"
}

logmust check_running_system
logmust configure_apt_sources
logmust sudo apt-get update

#
# - debhelper is used to build most Debian packages. It is required by
#   the dpkg_buildpackage_default() command.
# - devscripts provides dch, which is used to automatically generate and update
#   changelog entries. It is required by the dpkg_buildpackage_default()
#   command.
# - equivs is used by the mk-build-deps utility which is used to install
#   build dependencies from a control file.
# - install_shfmt and shellcheck are needed for - make check - to be able to
#   make sure style checks are fine.
#
logmust install_pkgs \
	debhelper \
	devscripts \
	equivs \
	shellcheck

logmust install_shfmt

logmust git config --global user.email "eng@delphix.com"
logmust git config --global user.name "Delphix Engineering"
