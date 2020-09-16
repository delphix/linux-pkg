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
# shellcheck disable=SC2034

#
# This file defines a default config for a package and is sourced by
# lib/common.sh->load_package_config() before sourcing the config.sh
# for the specified package. Any hooks and variables defined here can
# be overriden.
#

function fetch() {
	logmust fetch_repo_from_git
}

function merge_with_upstream() {
	logmust merge_with_upstream_default
}

#
# The functions below are specific for the Linux kernel packages
# and contain the majority of their common code.
#
function kernel_prepare() {
	logmust install_pkgs \
		equivs \
		devscripts \
		kernel-wedge
}

#
# The configuration disabled below is specifically for uses
# of ${debian_rules_args}. Quoting the specific variable
# results in incorrect behavior and thus we disable that
# check.
#
# shellcheck disable=SC2086
function kernel_build() {
	local platform="$1"
	#
	# Note: Extra arguments can overwrite default arguments.
	#       For example in this function we default skipdbg
	#       to false, but if we pass "skipdbg=true" as an
	#       extra argument we will be overwriting this value
	#       to true. This is because when a variable's value
	#       is declared multiple times when invoking the
	#       debian/rules command, the rightmost declaration
	#       is the one that is actually used.
	#
	local debian_rules_extra_args="$2"

	logmust cd "$WORKDIR/repo"

	#
	# We generate the default control file from Canonical
	# so we can capture the ABI number (abinum) from
	# Canonical's kernel - (see comment that follows for
	# the reason and the relevant code for the logic).
	#
	logmust debian/rules debian/control

	#
	# We overwrite the default abinum build variable with our
	# version strings and at the same time retain the original
	# abinum from Canonical by appending it at the end.
	#
	# We chose to mutate the abinum field as it is the least
	# invasive for Ubuntu's build logic (e.g. most of the other
	# variables actually interact with logic in the build). At
	# the same time the abinum variable is part of the fields
	# that we care about (e.g. package name, linux image file
	# name, etc..).
	#
	# We still retain the original abinum by appending it at
	# the end of the new one to maintain the mapping between
	# Canonical's releases and our releases.
	#
	local canonical_abinum delphix_abinum kernel_release kernel_version
	canonical_abinum=$(fakeroot debian/rules printenv | grep -E '^abinum ' | cut -d= -f2 | tr -d '[:space:]')
	delphix_abinum="dlpx-$(date -u +"%Y%m%dt%H%M%S")-$(git rev-parse --short HEAD)-${canonical_abinum}"
	kernel_release=$(fakeroot debian/rules printenv | grep -E '^release ' | cut -d= -f2 | tr -d '[:space:]')

	#
	# We record the kernel version into a file. This field is consumed
	# by other kernel packages, such as zfs, during their build.
	#
	kernel_version="${kernel_release}-${delphix_abinum}-${platform}"
	echo "$kernel_version" >"$WORKDIR/artifacts/KERNEL_VERSION"

	#
	# skipdbg=false
	#   We need debug info for our debugging tools to work.
	#   Don't skip them.
	# uefi_signed=false
	#   This variable defaults to true but since we don't have
	#   any intention and logic to provide signatures for now
	#   we set it to false to avoid any misconfigurations down
	#   the line.
	#
	local debian_rules_args="skipdbg=false uefi_signed=false disable_d_i=true flavours=$platform abinum=${delphix_abinum} ${debian_rules_extra_args}"

	#
	# Clean up everything generated so far and recreate the
	# final control file with the arguments that we want.
	#
	logmust fakeroot debian/rules clean ${debian_rules_args}

	#
	# Print the environment configuration solely for
	# debugging purposes.
	#
	logmust fakeroot debian/rules printenv ${debian_rules_args}

	#
	# The default value of the tool argument for mk-build-deps
	# is the following:
	# "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends"
	#
	# We append --yes to it to disable interactivity by apt-get
	# and allow for automation.
	#
	local build_deps_tool="apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes"
	logmust sudo mk-build-deps --install debian/control --tool "${build_deps_tool}"

	logmust fakeroot debian/rules "binary" ${debian_rules_args}

	logmust cd "$WORKDIR"
	logmust mv ./*deb "artifacts/"

	#
	# Make sure that we recorded the kernel version properly by checking
	# one of the .debs produced
	#
	logmust test -f "artifacts/linux-image-${kernel_version}_"*.deb
}

#
# Syncing our kernel with the right upstream Canonical repo is not as
# straighforward as the other packages in linux-pkg.
#
# The Ubuntu developers maintain the timeline of the mainline kernel
# (kernel.org) in their git history. When it is time to use a new
# mainline version, they fork a new branch and then cherry-pick all their
# Ubuntu-specific generic patches on top of that and create their base
# tag. Then on top of that they cherry-pick their platform-specific
# patches (e.g. azure, aws, etc..) and create separate tags for each
# platform. This whole process is repeated for every bump in the kernel
# version (both mainline and ubuntu-specific).
#
# We want to track and sync our changes every time Canonical bumps
# their kernel version for the kernels that are used by the Delphix
# Engine that we release in order to stay up to date and lower our
# maintainance burden. As a result we do the following:
#
# * We have one kernel repo per platform.
# * Each of this repos is an Ubuntu kernel repo with our specific
#   patches on top.
# * The vanilla Ubuntu kernel and our patches are divided by a single
#   placeholder commit with the description "@@DELPHIX_PATCHSET_START@@".
# * Whenever the Ubuntu kernel version is bumped, we detect that
#   change and use the new Ubuntu version as our base and cherry-pick
#   the placeholder commit followed by our patches on top of it.
#
function kernel_update_upstream() {
	local platform="$1"

	check_env UPSTREAM_GIT_URL
	logmust cd "$WORKDIR/repo"

	#
	# checkout our local branch that tracks upstream.
	#
	logmust git checkout -q upstream-HEAD

	#
	# declare third-party upstream repository.
	#
	logmust git remote add upstream "$UPSTREAM_GIT_URL"

	#
	# We get the kernel version and the ABI number from
	# $_RET that is set from `get_kernel_from_platform()`.
	# Example:
	#
	#   $_RET -> 5.3.0-53-generic
	#
	#   `cut -d '-' -f 1` of that -> 5.3.0
	#   `cut -d '-' -f 3` of that -> 53
	#
	# We need the kernel version and ABI number to figure
	# out the latest upstream tag to sync with.
	#
	local kernel_version abinum
	logmust get_kernel_version_for_platform_from_apt "${platform}"
	kernel_version=$(echo "$_RET" | cut -d '-' -f 1)
	abinum=$(echo "$_RET" | cut -d '-' -f 2)

	#
	# For each supported platform we will try to find the
	# latest upstream tag to sync based on the kernel
	# version and the ABI num that we got above.
	#
	# Note that "generic" (used mainly ESX) is a special
	# case as we are currently using the HWE kernel image.
	#
	local tag_prefix
	if [[ "${platform}" == generic ]] &&
		[[ "$UBUNTU_DISTRIBUTION" == bionic ]]; then
		tag_prefix="Ubuntu-hwe-${kernel_version}-${abinum}"
	elif [[ "${platform}" == aws ]] ||
		[[ "${platform}" == azure ]] ||
		[[ "${platform}" == gcp ]] ||
		[[ "${platform}" == oracle ]]; then

		local kvers_major kvers_minor short_kvers
		kvers_major=$(echo "${kernel_version}" | cut -d '.' -f 1)
		kvers_minor=$(echo "${kernel_version}" | cut -d '.' -f 2)
		short_kvers="${kvers_major}.${kvers_minor}"

		tag_prefix="Ubuntu-${platform}-${short_kvers}-${kernel_version}-${abinum}"
	else
		die "assertion: unexpected platform: ${platform}"
	fi
	echo "note: upstream tag prefix used: ${tag_prefix}"

	#
	# Query for upstream tag info based on the prefix that we've
	# assembled.
	#
	# = Why the `tail -n 1` part?
	#
	# Using `git ls-remote` and `grep` with the tag's prefix alone
	# may sometimes return two (and theoretically more?) results
	# due to Ubuntu's "point releases". Point releases are specific
	# to LTS releases and more info about them can be found in the
	# links below:
	# [1] https://wiki.ubuntu.com/LTS
	# [2] https://wiki.ubuntu.com/PointReleaseProcess
	#
	# Example:
	# ```
	# $ git ls-remote --tags upstream | grep Ubuntu-oracle-5.3-5.3.0-1015
	# df8fd7d8802d59   refs/tags/Ubuntu-oracle-5.3-5.3.0-1015.16_18.04.1
	# 0fe5cd29e90a5e   refs/tags/Ubuntu-oracle-5.3-5.3.0-1015.16_18.04.2
	# ```
	#
	# We most probably want the latest point release of a specific
	# kernel thus we add `tail -n 1` in the pipeline below.
	#
	local upstream_tag_info
	upstream_tag_info=$(git ls-remote --tags --ref upstream | grep "${tag_prefix}" | tail -n 1)
	[[ -z "${upstream_tag_info}" ]] && die "could not find upstream tag for tag prefix: ${tag_prefix}"

	local upstream_tag
	upstream_tag=$(echo "${upstream_tag_info}" | awk -F / '{print $3}')
	[[ -z "${upstream_tag}" ]] && die "could not extract upstream tag name from the tag info"

	logmust git fetch upstream "+refs/tags/${upstream_tag}:refs/tags/${upstream_tag}"

	local upstream_tag_commit
	upstream_tag_commit="$(git rev-parse "refs/tags/${upstream_tag}")" ||
		die "couldn't get commit of tag ${upstream_tag}"
	echo "note: upstream tag: ${upstream_tag}, commit ${upstream_tag_commit}"

	#
	# Check if the commit of the latest tag from upstream matches
	# what we have cached in our repository at upstreams/<branch>,
	# which we fetch to upstream-HEAD.
	#
	local local_upstream_commit
	local_upstream_commit=$(git rev-parse upstream-HEAD)
	[[ -z "${local_upstream_commit}" ]] && die "could not find upstream-HEAD's commit"
	echo "note: upstreams/${DEFAULT_GIT_BRANCH} commit: ${local_upstream_commit}"

	if [[ "${upstream_tag_commit}" == "${local_upstream_commit}" ]]; then
		echo "NOTE: upstream for $PACKAGE is already up-to-date."
	else
		logmust git reset --hard "refs/tags/${upstream_tag}"
		echo "NOTE: upstream updated to refs/tags/${upstream_tag}"

		#
		# Store name of upstream tag so that we can push it to our
		# repository for reference purposes.
		#
		echo "refs/tags/${upstream_tag}" >"$WORKDIR/upstream-tag" ||
			die "failed to write to $WORKDIR/upstream-tag"

		logmust touch "$WORKDIR/upstream-updated"
	fi

	logmust cd "$WORKDIR"
}

#
# This merges local changes in repo-HEAD with upstream changes in upstream-HEAD.
# As opposed to the default merge function merge_with_upstream_default(), this
# uses git cherry-pick to rebase our changes on top of the upstream changes.
#
function kernel_merge_with_upstream() {
	local repo_ref="refs/heads/repo-HEAD"
	local upstream_ref="refs/heads/upstream-HEAD"

	logmust cd "$WORKDIR/repo"

	check_git_ref "$upstream_ref" "$repo_ref"

	if git merge-base --is-ancestor "$upstream_ref" "$repo_ref"; then
		echo "NOTE: $PACKAGE is already up-to-date with upstream."
		return 0
	fi

	#
	# Ensure that there is a commit marking the start of
	# the Delphix set of patches. Then get the hash of
	# the commit right before it.
	#
	local dlpx_patch_end dlpx_patch_start current_ubuntu_commit
	dlpx_patch_start=$(git log --pretty=oneline repo-HEAD | grep @@DELPHIX_PATCHSET_START@@ | awk '{ print $1 }')
	[[ -z "${dlpx_patch_start}" ]] && die "could not find DELPHIX_PATCHSET_START"
	[[ $(wc -l <<<"${dlpx_patch_start}") != 1 ]] && die "multiple DELPHIX_PATCHSET_START commits - ${dlpx_patch_start}"
	current_ubuntu_commit=$(git rev-parse "${dlpx_patch_start}"^)
	[[ -z "${current_ubuntu_commit}" ]] && die "could not find commit before DELPHIX_PATCHSET_START"
	dlpx_patch_end=$(git rev-parse repo-HEAD)
	[[ -z "${dlpx_patch_end}" ]] && die "could not find repo-HEAD's head commit"

	#
	# We rebase all the Delphix commits on top of the new upstream-HEAD
	# by using git cherry-pick. Note that we also save the previous
	# tip of the active branch to repo-HEAD-saved as this reference will be
	# checked later by push-merge.sh.
	#

	logmust git branch repo-HEAD-saved repo-HEAD
	logmust git branch -D repo-HEAD
	logmust git checkout -q -b repo-HEAD upstream-HEAD

	# shellcheck disable=SC2086
	logmust git cherry-pick ${dlpx_patch_start}^..${dlpx_patch_end}

	logmust touch "$WORKDIR/repo-updated"
}

function post_build_checks() {

	# This function checks for SKIP_COPYRIGHTS_CHECK flag
	# in config.sh file of each package. If the flag is
	# present and is set to 'true', the check will be skipped.
	# The license information for the platform packages are
	# generated based on Ubuntu package convention and are
	# picked from copyright file in debian package. As a
	# part of the check we look for existance of the file in
	# each package.
	if [[ "$SKIP_COPYRIGHTS_CHECK" != true ]]; then
		cd "$WORKDIR/artifacts" || return

		set -o pipefail
		for deb in *.deb; do
			echo "Running: dpkg-deb -c $deb | grep '/usr/share/doc/' | grep copyright"
			dpkg-deb -c "$deb" | grep '/usr/share/doc/' | grep copyright || die "copyright file missing for package $deb"
		done
		set +o pipefail
	fi
}
