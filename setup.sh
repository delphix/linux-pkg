#!/usr/bin/env bash
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

logmust check_running_system
check_env DEFAULT_GIT_BRANCH

#
# Update the sources.list file to point to our internal package mirror. If no
# mirror url is passed in, then the latest mirror snapshot is used.
#
function configure_apt_sources() {
	local package_mirror_url
	local primary_url="$DELPHIX_PACKAGE_MIRROR_MAIN"
	local secondary_url="$DELPHIX_PACKAGE_MIRROR_SECONDARY"

	if [[ -z "$primary_url" ]] || [[ -z "$secondary_url" ]]; then
		local latest_url="http://linux-package-mirror.delphix.com/"
		if is_release_branch; then
			package_mirror_url="${latest_url}${DEFAULT_GIT_BRANCH}"
		else
			latest_url+="6.0/stage/latest/"
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
## Note, this file is written by cloud-init on first boot of an instance
## modifications made here will not survive a re-bundle.
## if you wish to make changes you can:
## a.) add 'apt_preserve_sources_list: true' to /etc/cloud/cloud.cfg
##     or do the same in user-data
## b.) add sources in /etc/apt/sources.list.d
## c.) make changes to template file /etc/cloud/templates/sources.list.tmpl

# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to
# newer versions of the distribution.
deb http://archive.ubuntu.com/ubuntu jammy main restricted
# deb-src http://archive.ubuntu.com/ubuntu jammy main restricted

## Major bug fix updates produced after the final release of the
## distribution.
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted
# deb-src http://archive.ubuntu.com/ubuntu jammy-updates main restricted

## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team. Also, please note that software in universe WILL NOT receive any
## review or updates from the Ubuntu security team.
deb http://archive.ubuntu.com/ubuntu jammy universe
# deb-src http://archive.ubuntu.com/ubuntu jammy universe
deb http://archive.ubuntu.com/ubuntu jammy-updates universe
# deb-src http://archive.ubuntu.com/ubuntu jammy-updates universe

## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team, and may not be under a free licence. Please satisfy yourself as to
## your rights to use the software. Also, please note that software in
## multiverse WILL NOT receive any review or updates from the Ubuntu
## security team.
deb http://archive.ubuntu.com/ubuntu jammy multiverse
# deb-src http://archive.ubuntu.com/ubuntu jammy multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates multiverse
# deb-src http://archive.ubuntu.com/ubuntu jammy-updates multiverse

## N.B. software from this repository may not have been tested as
## extensively as that contained in the main release, although it includes
## newer versions of some applications which may provide useful features.
## Also, please note that software in backports WILL NOT receive any review
## or updates from the Ubuntu security team.
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
# deb-src http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse

## Uncomment the following two lines to add software from Canonical's
## 'partner' repository.
## This software is not part of Ubuntu, but is offered by Canonical and the
## respective vendors as a service to Ubuntu users.
# deb http://archive.canonical.com/ubuntu jammy partner
# deb-src http://archive.canonical.com/ubuntu jammy partner

deb http://security.ubuntu.com/ubuntu jammy-security main restricted
# deb-src http://security.ubuntu.com/ubuntu jammy-security main restricted
deb http://security.ubuntu.com/ubuntu jammy-security universe
# deb-src http://security.ubuntu.com/ubuntu jammy-security universe
deb http://security.ubuntu.com/ubuntu jammy-security multiverse
# deb-src http://security.ubuntu.com/ubuntu jammy-security multiverse
		EOF" || die "/etc/apt/sources.list could not be updated"

	logmust sudo apt-key add "$TOP/resources/delphix-secondary-mirror.key"
}

#
# Some packages require cause a spike in memory usage during the build, so
# we add a swap file to prevent the oom-killer from terminating the build.
#
function add_swap() {
	local rootfs
	local swapfile

	swapfile="/swapfile"
	rootfs=$(awk '$2 == "/" { print $3 }' /proc/self/mounts)

	#
	# If the root filesystem is ZFS, we assume we're running on a
	# Delphix based buildserver, and assume swap is already enabled;
	# the Delphix buildserver should enable swap for us.
	#
	if [[ "$rootfs" == "zfs" ]]; then
		return
	fi

	# Swap already enabled, nothing to do.
	if sudo swapon --show | grep -q "$swapfile"; then
		return
	fi

	logmust sudo fallocate -l 4G "$swapfile"
	logmust sudo chmod 600 "$swapfile"
	logmust sudo mkswap "$swapfile"
	logmust sudo swapon "$swapfile"
}

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
# - jq is used to generate a JSON formatted metadata file by some packages.
#
logmust install_pkgs \
	build-essential \
	debhelper \
	devscripts \
	equivs \
	rsync \
	shellcheck \
	jq

logmust install_shfmt

logmust add_swap

logmust git config --global user.email "eng@delphix.com"
logmust git config --global user.name "Delphix Engineering"

logmust sudo touch /run/linux-pkg-setup
