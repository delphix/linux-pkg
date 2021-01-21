#!/bin/bash
#
# Copyright 2018, 2020 Delphix
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

logmust determine_default_git_branch

#
# Update the sources.list file to point to our internal package mirror. If no
# mirror url is passed in, then the latest mirror snapshot is used.
#
configure_apt_sources() {
	local package_mirror_url
	local primary_url="$DELPHIX_PACKAGE_MIRROR_MAIN"
	local secondary_url="$DELPHIX_PACKAGE_MIRROR_SECONDARY"

	if [[ -z "$primary_url" ]] || [[ -z "$secondary_url" ]]; then
		local latest_url="http://linux-package-mirror.delphix.com/"
		if is_release_branch; then
			package_mirror_url="${latest_url}${DEFAULT_GIT_BRANCH}"
		else
			latest_url+="${DEFAULT_GIT_BRANCH}/latest/"
			package_mirror_url=$(curl -LfSs -o /dev/null -w '%{url_effective}' \
				"$latest_url" || die "Could not curl $latest_url")
			# Remove trailing slash, if present.
			package_mirror_url="${package_mirror_url%/}"
		fi
		[[ -z "$primary_url" ]] && primary_url="${package_mirror_url}/ubuntu"
		[[ -z "$secondary_url" ]] && secondary_url="${package_mirror_url}/ppas"
	fi

	#
	# Store the package mirror in a file so that it can be added to a
	# package build's metadata via store_build_info().
	#
	echo "$primary_url" >"$TOP/PACKAGE_MIRROR_URL_MAIN"
	echo "$secondary_url" >"$TOP/PACKAGE_MIRROR_URL_SECONDARY"

	#
	# Remove other sources in sources.list.d if they are present.
	#
	[[ -d /etc/apt/sources.list.d ]] && (
		logmust sudo rm -rf /etc/apt/sources.list.d ||
			die "Could not remove /etc/apt/sources.list.d"
	)

	sudo bash -c "cat <<-EOF >/etc/apt/sources.list
		deb ${primary_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse

		deb ${secondary_url} ${UBUNTU_DISTRIBUTION} main multiverse universe
		deb ${secondary_url} ${UBUNTU_DISTRIBUTION}-updates main multiverse universe
		EOF" || die "/etc/apt/sources.list could not be updated"

	logmust sudo apt-key add "$TOP/resources/delphix-secondary-mirror.key"
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

#
# Starting with kernel 5.4, gcc 7 can no longer compile kernel modules, so
# install gcc 8
# https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1849348
#
logmust install_gcc8

logmust git config --global user.email "eng@delphix.com"
logmust git config --global user.name "Delphix Engineering"
