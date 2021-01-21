#!/bin/bash
#
# Copyright 2019, 2020 Delphix
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

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/zfs.git"
DEFAULT_PACKAGE_VERSION="0.8.0"
PACKAGE_DEPENDENCIES="@linux-kernel"

UPSTREAM_GIT_URL="https://github.com/zfsonlinux/zfs.git"
UPSTREAM_GIT_BRANCH="master"

function prepare() {
	logmust install_pkgs \
		alien \
		autoconf \
		autogen \
		autotools-dev \
		build-essential \
		debhelper \
		devscripts \
		dh-autoreconf \
		dh-python \
		dkms \
		fakeroot \
		gawk \
		ksh \
		libattr1-dev \
		libblkid-dev \
		libelf-dev \
		libselinux-dev \
		libselinux1-dev \
		libssl-dev \
		libtool \
		libudev-dev \
		lsb-release \
		lsscsi \
		parted \
		po-debconf \
		python3 \
		uuid-dev \
		zlib1g-dev
	logmust install_kernel_headers
}

function checkstyle() {
	logmust cd "$WORKDIR/repo"
	logmust sh autogen.sh
	logmust ./configure --with-config=user
	logmust install_pkgs flake8 mandoc
	logmust make codecheck
	logmust git reset --hard HEAD
	logmust git clean -qdxf
}

function build() {
	logmust cd "$WORKDIR/repo"

	#
	# Logic in ZFS doesn't play well if there is a dash in the package
	# revision. We replace - by +.
	#
	if [[ "$PACKAGE_REVISION" == *-* ]]; then
		local old_revision="$PACKAGE_REVISION"
		logmust eval "PACKAGE_REVISION=$(tr '-' '+' <<<"$PACKAGE_REVISION")"
		echo_bold "PACKAGE_REVISION changed to '$PACKAGE_REVISION'" \
			"from '$old_revision' as ZFS build doesn't support" \
			"dashes in package revision."
	fi

	#
	# ZFS encodes its version in the kernel module, which is accessible
	# in /sys/module/zfs/version. The version is set by modifying the META
	# file.
	#
	local hash
	logmust eval hash="$(git rev-parse --short HEAD)"
	logmust sed -i "s/^Version:.*/Version:      $PACKAGE_VERSION/" META ||
		die "failed to set version"
	logmust sed -i "s/^Release:.*/Release:      $PACKAGE_REVISION-$hash/" \
		META || die "failed to set version"
	logmust set_changelog

	#
	# Build the userland packages. This must be done before building the
	# kernel modules.
	#
	echo_bold "Building ZFS userland"
	logmust dpkg-buildpackage -b -uc -us

	logmust cd "$WORKDIR"
	logmust mkdir "all-packages"
	logmust cp ./*.deb "all-packages/"

	#
	# We will create tarballs of packages built for each platform so that
	# it is easier to deploy them manually by extracting the archive and
	# running 'apt-get install ./*.deb'.
	# Note that we remove zfs-dkms and zfs-dracut from the tarball as we
	# do not install those packages on the appliance.
	#
	logmust mkdir "userland-packages"
	logmust mv ./*.deb "userland-packages/"
	logmust rm "userland-packages"/zfs-dkms*.deb
	logmust rm "userland-packages"/zfs-dracut*.deb

	#
	# Backup the build repository so that it can be restored before
	# building modules for each kernel.
	#
	logmust cp -r repo repo-backup

	#
	# Build modules for each kernel. KVERS, KSRC, and KOBJ must be defined
	# for ZFS to be built against a specific version of the kernel. The
	# command for building the kernel modules is documented in ZFS's
	# debian/README.source file.
	#
	logmust determine_target_kernels
	check_env KERNEL_VERSIONS
	export KVERS
	for KVERS in $KERNEL_VERSIONS; do
		#
		# Restore partially built repository from backup
		#
		logmust cd "$WORKDIR"
		logmust rm -rf "$WORKDIR/repo"
		logmust cp -r "$WORKDIR/repo-backup" "$WORKDIR/repo"
		logmust cd "$WORKDIR/repo"

		#
		# Build the kernel modules
		#
		echo_bold "Building ZFS modules for kernel $KVERS"
		export KSRC="/usr/src/linux-headers-$KVERS"
		export KOBJ="/usr/src/linux-headers-$KVERS"
		logmust fakeroot debian/rules override_dh_binary-modules

		#
		# Backup new packages and create tarball for this platform.
		#
		logmust cd "$WORKDIR"
		logmust cp ./*.deb "all-packages/"
		logmust rm -rf "platform-packages"
		logmust cp -r "userland-packages" "platform-packages"
		logmust mv ./*.deb "platform-packages/"
		logmust cd "platform-packages"
		logmust tar zcf "$WORKDIR/artifacts/zfs-packages-${KVERS}.tar.gz" \
			./*.deb
	done
	logmust cd "$WORKDIR"
	logmust mv "all-packages/"*.deb "artifacts/"
}

function update_upstream() {
	logmust update_upstream_from_git
}
