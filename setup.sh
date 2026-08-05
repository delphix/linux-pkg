#!/usr/bin/env bash
#
# Copyright 2018, 2025 Delphix
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

check_env DEFAULT_GIT_BRANCH DELPHIX_RELEASE_VERSION

#
# setup.sh has two jobs, selected by where it runs. On the host it prepares the
# host and builds the container image that package builds run inside. Inside that
# container it configures apt and installs the build tooling, which is what the
# rest of this file does. LINUX_PKG_NO_CONTAINER=true opts a caller out of the
# container entirely (see container_reexec()), so in that case this host-only
# branch must be skipped as well, or the escape hatch would bootstrap a container
# image it never uses and exit before installing the build tooling it does need.
#
# check_host_is_disposable must run for every non-container invocation, not just
# the one that goes on to bootstrap a container image: LINUX_PKG_NO_CONTAINER=true
# skips the block below entirely and falls through to the in-container body,
# which on a bare invocation of this script is not actually inside a container at
# all, and would rewrite this host's /etc/apt/sources.list and install packages
# onto it. Skipped only when already running_in_container, where the question of
# whether the host is disposable no longer applies.
#
if ! running_in_container; then
	logmust check_host_is_disposable
fi

#
# Swap is not arranged here. Package builds spike memory (a linux-kernel or a
# zfs object-agent link will), and the swap that absorbs it belongs to the build
# host: delphix-platform provisions 8G on /dev/nvme1n1 for the
# internal-buildserver variant, re-enabled on each clone's first boot. The host
# is required to be that variant, so it is always present.
#
if ! running_in_container && [[ "$LINUX_PKG_NO_CONTAINER" != "true" ]]; then
	logmust container_check_host_prereqs
	logmust container_build_base_image
	exit 0
fi

#
# Update the sources.list file to point to our internal package mirror. If no
# mirror url is passed in, then the latest mirror snapshot is used.
#
function configure_apt_sources() {
	local primary_url
	local secondary_url
	local secondary_keyring

	secondary_keyring=/etc/apt/keyrings/delphix-secondary-mirror.gpg

	logmust resolve_mirror_urls
	primary_url="$_RET_MIRROR_MAIN"
	secondary_url="$_RET_MIRROR_SECONDARY"

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

	#
	# The secondary mirror's key, installed before the sources that reference it
	# so that the path on its source line resolves by the time apt reads it.
	#
	# The key is named with signed-by= on the one source line it belongs to, so it
	# can only ever validate that repository. Installing it globally instead would
	# give it authority over every source in this file, the primary Ubuntu mirror
	# lines below included, which is more than the secondary mirror needs; apt-key
	# is also absent from Ubuntu 26.04 ("resolute") and later. The key at rest is a
	# binary, dearmored OpenPGP keyring, which is what signed-by wants;
	# /etc/apt/keyrings may not exist in a freshly debootstrapped rootfs, hence
	# install -D.
	#
	logmust sudo install -D -o root -g root -m 0644 \
		"$TOP/resources/delphix-secondary-mirror.key" \
		"$secondary_keyring"

	#
	# Scoping the key above is pointless while a globally trusted copy of it sits
	# in trusted.gpg.d, so that path is cleared. It only ever holds one on the
	# LINUX_PKG_NO_CONTAINER escape hatch, where the host's own apt configuration
	# persists between runs; a container is bootstrapped fresh and never has it.
	#
	logmust sudo rm -f /etc/apt/trusted.gpg.d/delphix-secondary-mirror.gpg

	sudo bash -c "cat <<-EOF >/etc/apt/sources.list
		deb ${primary_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION} main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-updates main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-security main restricted universe multiverse

		deb ${primary_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse
		deb-src ${primary_url} ${UBUNTU_DISTRIBUTION}-backports main restricted universe multiverse

		deb [signed-by=${secondary_keyring}] ${secondary_url} ${UBUNTU_DISTRIBUTION} main multiverse universe stable
		EOF" || die "/etc/apt/sources.list could not be updated"
}

#
# Everything below rewrites this root filesystem's apt sources to the suite named
# by UBUNTU_DISTRIBUTION and installs from them, so the codename of the system it
# runs on has to match that suite. Inside the container it does by construction,
# and the check catches a stale or mismatched image. On the
# LINUX_PKG_NO_CONTAINER escape hatch there is no container and no such
# guarantee, and this is the only thing standing between, say, a jammy host and
# an apt configuration pointed at noble; the base setup.sh checked the same
# thing, in the same place, for the same reason.
#
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
# - fakeroot is required by dpkg-buildpackage (dpkg_buildpackage_default(), the
#   default build() implementation used by most packages) to fake root
#   ownership of package contents without actually running as root.
# - shellcheck, and install_shfmt below, provide the two tools - make check -
#   runs. Nothing inside the container runs it as part of a build, and the
#   repo's own style gate does not depend on this script either: the GitHub
#   workflow installs both itself (.github/scripts/install-shellcheck.sh and
#   install-shfmt.sh). They are here so that the style checks can be run against
#   the bind-mounted checkout from a container shell (./buildpkg.sh -S), on a
#   host whose own release may not even be the one being built.
# - jq is used to generate a JSON formatted metadata file by some packages.
# - git is used below to clone every package's repo in its fetch stage, and to
#   set the global user.email/user.name just after this install_pkgs call.
# - wget is used by install_shfmt() to fetch the shfmt binary.
# - python3-pip is used below to install awscli, which is not itself part of
#   this list: it has no installation candidate on noble ("E: Package
#   'awscli' has no installation candidate" against our mirror), since Ubuntu
#   distributes it via pip or snap from 24.04 onward instead of a deb.
# - bc is used by connstat's module/configure.sh to compute the
#   KERNEL_CENTEVERSION preprocessor value baked into its Makefile
#   (kcentevers=$(echo 100*$major+$minor | bc)); without it that command
#   substitution silently yields an empty value, which turns into an empty
#   -DKERNEL_CENTEVERSION= compiler flag and a cascade of unrelated-looking
#   syntax errors deep in connstat.c's version-gated #if blocks.
# - sbsigntool provides kmodsign, used by sign_modules() to sign kernel
#   modules for packages like connstat and zfs. Without it every module's
#   kmodsign call fails with "command not found", which aborts the build.
#   That used to pass silently and ship an unsigned .ko, because the signing
#   loop ran in a subshell where logmust's die had no effect on the caller
#   (DLPX-98274).
# - kmod provides modinfo, which sign_modules() also runs after kmodsign,
#   purely to log the signer's identity. It doesn't mutate the module, so
#   its absence doesn't affect the signature itself, but it is a logmust
#   call in the same loop, so a missing modinfo fails the build as well.
# None of build-essential/debhelper/devscripts/equivs/fakeroot/git/wget are
# part of debootstrap's --variant=buildd set, so they cannot be assumed
# present.
#
logmust install_pkgs \
	build-essential \
	debhelper \
	devscripts \
	equivs \
	fakeroot \
	git \
	rsync \
	shellcheck \
	wget \
	jq \
	python3-pip \
	bc \
	sbsigntool \
	kmod

#
# aws is used by fetch_dependencies() to pull a package's build-dependencies
# from S3. It is present on a real buildserver's host root (part of that
# host's own provisioning, outside this repo's control), but the container is
# a separate, debootstrapped rootfs that never gets it any other way. Installed
# here, in the in-container provisioning that runs on every build, rather than
# baked into resources/Dockerfile.build-container, so existing images keep
# working without a rebuild. Matches the precedent in appliance-build's own
# bootstrap (bootstrap/roles/appliance-build.bootstrap/tasks/main.yml), which
# installs it the same way for the same reason.
#
# Pinned to the version validated against this setup, unlike every apt package
# above: those are implicitly pinned through the branch's mirror snapshot, but
# PyPI has no equivalent, so an unpinned install would let a future awscli
# release change the toolchain with no corresponding repo change, and an older
# build could no longer be reproduced. Bump deliberately, not silently.
#
# Retried the same way install_pkgs() retries apt, because this is the one build
# input that does not come from the pinned mirror snapshot: it reaches PyPI over
# the internet on every build of every package, so a transient failure there
# would otherwise fail a build that has nothing wrong with it.
#
function install_awscli() {
	local attempt

	for attempt in {1..3}; do
		echo "Running: sudo pip3 install awscli==1.45.63 --break-system-packages"
		sudo pip3 install "awscli==1.45.63" --break-system-packages && return

		echo "pip3 install awscli failed, retrying."
		sleep 10
	done
	die "pip3 install awscli failed after $attempt attempts"
}

logmust install_awscli

logmust install_shfmt

logmust git config --global user.email "eng@delphix.com"
logmust git config --global user.name "Delphix Engineering"

logmust sudo touch /run/linux-pkg-setup
