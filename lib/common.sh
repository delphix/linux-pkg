#!/bin/bash
#
# Copyright 2018, 2019 Delphix
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

export _RET
export _RET_LIST
export DEBIAN_FRONTEND=noninteractive

# TODO: allow updating upstream for other branches than master
export REPO_UPSTREAM_BRANCH="upstreams/master"

export UBUNTU_DISTRIBUTION="bionic"

#
# Determine DEFAULT_GIT_BRANCH. If it is unset, default to the branch set in
# branch.config.
#
if [[ -z "$DEFAULT_GIT_BRANCH" ]]; then
	echo "DEFAULT_GIT_BRANCH is not set."
	if ! source "$TOP/branch.config" 2>/dev/null; then
		echo "No branch.config file found in repo root."
		exit 1
	fi

	if [[ -z "$DEFAULT_GIT_BRANCH" ]]; then
		echo "$DEFAULT_GIT_BRANCH parameter was not sourced from " \
			"branch.config. Ensure branch.config is properly formatted with " \
			"e.g. DEFAULT_GIT_BRANCH=\"<upstream-product-branch>\""
		exit 1
	fi

	echo "Defaulting DEFAULT_GIT_BRANCH to branch $DEFAULT_GIT_BRANCH set in" \
		"branch.config."

	export DEFAULT_GIT_BRANCH
fi

# shellcheck disable=SC2086
function enable_colors() {
	[[ -t 1 ]] && flags="" || flags="-T xterm"
	FMT_RED="$(tput $flags setaf 1)"
	FMT_GREEN="$(tput $flags setaf 2)"
	FMT_BOLD="$(tput $flags bold)"
	FMT_NF="$(tput $flags sgr0)"
	COLORS_ENABLED=true
}

function disable_colors() {
	FMT_RED=""
	FMT_GREEN=""
	FMT_BOLD=""
	FMT_NF=""
	COLORS_ENABLED=false
}

if [[ -t 1 ]] || [[ "$FORCE_COLORS" == "true" ]]; then
	enable_colors
else
	disable_colors
fi

function without_colors() {
	if [[ "$COLORS_ENABLED" == "true" ]]; then
		disable_colors
		"$@"
		enable_colors
	else
		"$@"
	fi
}

function echo_error() {
	echo -e "${FMT_BOLD}${FMT_RED}Error: $*${FMT_NF}"
}

function echo_success() {
	echo -e "${FMT_BOLD}${FMT_GREEN}Success: $*${FMT_NF}"
}

function echo_bold() {
	echo -e "${FMT_BOLD}$*${FMT_NF}"
}

function die() {
	[[ $# -gt 0 ]] && echo_error "$*"
	exit 1
}

function logmust() {
	echo Running: "$@"
	"$@" || die "failed command '$*'"
}

#
# Check that we are running in AWS on an Ubuntu system of the appropriate
# distribution. This is not a strict requirement for the build to work but
# rather a safety measure to prevent developers from accidentally running the
# scripts on their work system and changing its configuration.
#
function check_running_system() {
	if [[ "$DISABLE_SYSTEM_CHECK" == "true" ]]; then
		echo "WARNING: System check disabled."
		return 0
	fi

	if ! (command -v lsb_release >/dev/null &&
		[[ $(lsb_release -cs) == "$UBUNTU_DISTRIBUTION" ]]); then
		die "Script can only be ran on an ubuntu-${UBUNTU_DISTRIBUTION} system."
	fi

	if ! curl "http://169.254.169.254/latest/meta-datas" \
		>/dev/null 2>&1; then
		die "Not running in AWS, are you sure you are on the" \
			"right system?"
	fi
}

function check_package_exists() {
	local pkg="$1"

	check_env TOP
	echo "$pkg" | grep -q '/' && die "Package name should not contain '/'"
	[[ -d "$TOP/packages/$pkg" ]] || die "Unknown package '$pkg'."
}

function check_env() {
	local var val required

	required=true
	for var in "$@"; do
		if [[ "$var" == "--" ]]; then
			required=false
			continue
		fi

		val="${!var}"
		if $required && [[ -z "$val" ]]; then
			die "check_env: $var must be non-empty"
		fi
	done
}

function check_git_ref() {
	local ref
	for ref in "$@"; do
		if ! git show-ref -q "$ref"; then
			die "git ref '$ref' not found"
		fi
	done
}

function query_git_credentials() {
	if [[ -n "$PUSH_GIT_USER" ]] && [[ -n "$PUSH_GIT_PASSWORD" ]]; then
		return 0
	fi

	if [[ ! -t 1 ]]; then
		die "PUSH_GIT_USER and PUSH_GIT_PASSWORD environment" \
			"variables must be set to a user that has" \
			"push permissions for the target repository."
	fi

	echo "Please enter git credentials for pushing to repository."
	read -r -p "User: " PUSH_GIT_USER
	read -r -s -p "Password: " PUSH_GIT_PASSWORD
	echo ""
	export PUSH_GIT_USER
	export PUSH_GIT_PASSWORD
}

#
# execute a hook from a package's config.sh
#
function stage() {
	typeset hook=$1

	check_env PACKAGE
	local stage_start=$SECONDS

	echo ""
	if type -t "$hook" >/dev/null; then
		echo_bold "PACKAGE $PACKAGE: STAGE $hook STARTED"
		logmust "$hook"
		echo_bold "PACKAGE $PACKAGE: STAGE $hook COMPLETED in" \
			"$((SECONDS - stage_start)) seconds"
	else
		echo_bold "PACKAGE $PACKAGE: SKIPPING UNDEFINED STAGE $hook"
	fi
	echo ""
}

function reset_package_config_variables() {
	local hook
	local var

	for hook in prepare fetch build checkstyle update_upstream; do
		unset "$hook"
	done

	local vars="
	PACKAGE_GIT_URL
	PACKAGE_GIT_BRANCH
	PACKAGE_GIT_VERSION
	PACKAGE_GIT_REVISION
	DEFAULT_PACKAGE_GIT_URL
	DEFAULT_PACKAGE_GIT_BRANCH
	DEFAULT_PACKAGE_GIT_VERSION
	DEFAULT_PACKAGE_GIT_REVISION
	UPSTREAM_SOURCE_PACKAGE
	UPSTREAM_GIT_URL
	UPSTREAM_GIT_BRANCH
	WORKDIR
	PKGDIR
	PACKAGE_PREFIX
	"

	for var in $vars; do
		unset "$var"
	done
}

function get_package_prefix() {
	local pkg="$1"
	local pkg_prefix

	#
	# We allow overriding package-specific configuration through
	# environment variables starting with <pkg_prefix> in
	# get_package_config_from_env(). We make sure that the names of new
	# packages can be converted to a valid <pkg_prefix>.
	#
	pkg_prefix="$(echo "$pkg" | tr - _ | tr '[:lower:]' '[:upper:]')"
	[[ "$pkg_prefix" =~ ^[A-Z][A-Z0-9_]*$ ]] ||
		die "Failed to convert package name '$pkg' to valid" \
			"prefix ($pkg_prefix)"
	_RET="$pkg_prefix"
}

#
# Loads configuration for building package passed in $1. High level tasks are:
#  1. Reset/Cleanup package configuration environment
#  2. Source default config for all packages: default-package-config.sh
#  3. Source default config for specific package: packages/PACKAGE/config.sh
#  4. Look at environment variables that can override default configs.
#  5. Validate config
#
function load_package_config() {
	export PACKAGE="$1"

	logmust check_package_exists "$PACKAGE"

	#
	# unset hooks and variables that are reserved for a package's config.
	#
	logmust reset_package_config_variables

	check_env TOP
	export PKGDIR="$TOP/packages/$PACKAGE"
	export WORKDIR="$PKGDIR/tmp"

	logmust source "$TOP/default-package-config.sh"
	logmust source "$PKGDIR/config.sh"

	#
	# A package's config.sh file can define default values for:
	#   GIT_URL, GIT_BRANCH, VERSION, REVISION.
	#
	# Those defaults can be overriden either by package-specific
	# environment variables or by parameters passed from command line.
	#
	logmust get_package_prefix "$PACKAGE"
	export PACKAGE_PREFIX="$_RET"
	logmust get_package_config_from_env

	#
	# Check that package configuration is valid
	#

	[[ -n "$DEFAULT_PACKAGE_GIT_URL" ]] ||
		die "$PACKAGE: DEFAULT_PACKAGE_GIT_URL is not defined. Set " \
			"it to 'none' if the source is not fetched from git"

	[[ "$DEFAULT_PACKAGE_GIT_URL" == https://* ]] ||
		[[ "$DEFAULT_PACKAGE_GIT_URL" == "none" ]] ||
		die "$PACKAGE: DEFAULT_PACKAGE_GIT_URL must begin with " \
			"https:// or be set to 'none'"

	#
	# Check for variables related to update_upstream() hook
	#
	local found=false
	if [[ -n "$UPSTREAM_GIT_URL" ]]; then
		[[ -n "$UPSTREAM_GIT_BRANCH" ]] ||
			die "$PACKAGE: UPSTREAM_GIT_BRANCH must also be" \
				"defined when UPSTREAM_GIT_URL is defined."
		found=true
	elif [[ -n "$UPSTREAM_GIT_BRANCH" ]]; then
		die "$PACKAGE: UPSTREAM_GIT_URL must also be defined when" \
			"UPSTREAM_GIT_BRANCH is defined."
	fi
	if [[ -n "$UPSTREAM_SOURCE_PACKAGE" ]]; then
		$found && die "$PACKAGE: UPSTREAM_SOURCE_PACKAGE and" \
			"UPSTREAM_GIT_URL are mutually exclusive."
		found=true
	fi
	if $found && ! type -t update_upstream >/dev/null; then
		die "$PACKAGE: update_upstream() hook must be defined when" \
			"either UPSTREAM_SOURCE_PACKAGE or UPSTREAM_GIT_URL" \
			"is set."
	fi

	#
	# Check that mandatory hooks are defined
	#
	for hook in fetch build; do
		type -t "$hook" >/dev/null ||
			die "$PACKAGE: Hook '$hook' missing."
	done
}

#
# Use different config sources to determine the values for:
#   PACKAGE_GIT_URL, PACKAGE_GIT_BRANCH, PACKAGE_VERSION, PACKAGE_REVISION
#
# The sources for the config, in decreasing order of priority, are:
#   1. Command line parameters passed to build script.
#   2. Package-specific environment variables {PACKAGE_PREFIX}_{SUFFIX}.
#      PACKAGE_PREFIX is the package's name in CAPS with '-' replaced by '_'.
#      E.g. CLOUD_INIT_GIT_URL sets PACKAGE_GIT_URL for package cloud-init.
#   3. DEFAULT_PACKAGE_{SUFFIX} variables defined in package's config.sh.
#   4. Global defaults for all packages, DEFAULT_{SUFFIX}.
#
# This function should be called after loading a package's config.sh.
#
function get_package_config_from_env() {
	local var
	check_env PACKAGE_PREFIX

	echo "get_package_config_from_env(): using prefix: ${PACKAGE_PREFIX}_"

	var="${PACKAGE_PREFIX}_GIT_URL"
	if [[ -n "$PARAM_PACKAGE_GIT_URL" ]]; then
		PACKAGE_GIT_URL="$PARAM_PACKAGE_GIT_URL"
		echo "PARAM_PACKAGE_GIT_URL passed from '-g'"
	elif [[ -n "${!var}" ]]; then
		PACKAGE_GIT_URL="${!var}"
		echo "PACKAGE_GIT_URL set to value of ${var}"
	elif [[ -n "$DEFAULT_PACKAGE_GIT_URL" ]]; then
		PACKAGE_GIT_URL="$DEFAULT_PACKAGE_GIT_URL"
		echo "PACKAGE_GIT_URL set to value of DEFAULT_PACKAGE_GIT_URL"
	fi

	var="${PACKAGE_PREFIX}_GIT_BRANCH"
	if [[ -n "$PARAM_PACKAGE_GIT_BRANCH" ]]; then
		PACKAGE_GIT_BRANCH="$PARAM_PACKAGE_GIT_BRANCH"
		echo "PARAM_PACKAGE_GIT_BRANCH passed from '-b'"
	elif [[ -n "${!var}" ]]; then
		PACKAGE_GIT_BRANCH="${!var}"
		echo "PACKAGE_GIT_BRANCH set to value of ${var}"
	elif [[ -n "$DEFAULT_PACKAGE_GIT_BRANCH" ]]; then
		PACKAGE_GIT_BRANCH="$DEFAULT_PACKAGE_GIT_BRANCH"
		echo "PACKAGE_GIT_BRANCH set to value of" \
			"DEFAULT_PACKAGE_GIT_BRANCH"
	fi

	if [[ -z "$PACKAGE_GIT_BRANCH" ]]; then
		PACKAGE_GIT_BRANCH="$DEFAULT_GIT_BRANCH"
		echo "PACKAGE_GIT_BRANCH set to value of DEFAULT_GIT_BRANCH"
	fi

	var="${PACKAGE_PREFIX}_VERSION"
	if [[ -n "$PARAM_PACKAGE_VERSION" ]]; then
		PACKAGE_VERSION="$PARAM_PACKAGE_VERSION"
		echo "PACKAGE_VERSION passed from '-v'"
	elif [[ -n "${!var}" ]]; then
		PACKAGE_VERSION="${!var}"
		echo "PACKAGE_VERSION set to value of ${var}"
	elif [[ -n "$DEFAULT_PACKAGE_VERSION" ]]; then
		PACKAGE_VERSION="$DEFAULT_PACKAGE_VERSION"
		echo "PACKAGE_VERSION set to value of DEFAULT_PACKAGE_VERSION"
	fi

	var="${PACKAGE_PREFIX}_REVISION"
	if [[ -n "$PARAM_PACKAGE_REVISION" ]]; then
		PACKAGE_REVISION="$PARAM_PACKAGE_REVISION"
		echo "PACKAGE_REVISION passed from '-r'"
	elif [[ -n "${!var}" ]]; then
		PACKAGE_REVISION="${!var}"
		echo "PACKAGE_REVISION set to value of ${var}"
	elif [[ -n "$DEFAULT_PACKAGE_REVISION" ]]; then
		PACKAGE_REVISION="$DEFAULT_PACKAGE_REVISION"
		echo "PACKAGE_REVISION set to value of DEFAULT_PACKAGE_REVISION"
	fi

	if [[ -z "$PACKAGE_REVISION" ]]; then
		PACKAGE_REVISION="$DEFAULT_REVISION"
		echo "PACKAGE_REVISION set to value of DEFAULT_REVISION"
	fi

	export PACKAGE_GIT_URL
	export PACKAGE_GIT_BRANCH
	export PACKAGE_VERSION
	export PACKAGE_REVISION

	echo_bold "------------------------------------------------------------"
	echo_bold "PACKAGE_GIT_URL:      $PACKAGE_GIT_URL"
	echo_bold "PACKAGE_GIT_BRANCH:   $PACKAGE_GIT_BRANCH"
	echo_bold "PACKAGE_VERSION:      $PACKAGE_VERSION"
	echo_bold "PACKAGE_REVISION:     $PACKAGE_REVISION"
	echo_bold "------------------------------------------------------------"
}

function install_pkgs() {
	for attempt in {1..3}; do
		echo "Running: sudo env DEBIAN_FRONTEND=noninteractive " \
			"apt-get install -y $*"
		sudo env DEBIAN_FRONTEND=noninteractive apt-get install \
			-y "$@" && return
		echo "apt-get install failed, retrying."
		sleep 10
	done
	die "apt-get install failed after $attempt attempts"
}

function install_build_deps_from_control_file() {
	logmust pushd "$WORKDIR/repo"
	logmust sudo env DEBIAN_FRONTEND=noninteractive mk-build-deps --install \
		--tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' \
		debian/control
	logmust popd
}

function read_package_list() {
	local file="$1"

	local pkg
	local line

	_RET_LIST=()

	while read -r line; do
		# trim whitespace
		pkg=$(echo "$line" | sed 's/^\s*//;s/\s*$//')
		[[ -z "$pkg" ]] && continue
		# ignore comments
		[[ ${pkg:0:1} == "#" ]] && continue
		check_package_exists "$pkg"
		_RET_LIST+=("$pkg")
	done <"$file" || die "Failed to read package list: $file"
}

function get_package_list_file() {
	local list_type="$1"
	local list_name="$2"

	if [[ "$list_type" != build ]] && [[ "$list_type" != update ]]; then
		die "Invalid list type '$list_type'"
	fi

	_RET="$TOP/package-lists/${list_type}/${list_name}.pkgs"
	if [[ ! -f "$_RET" ]]; then
		echo_error "Invalid $list_type package list '$list_name'"
		echo_error "See lists in $TOP/package-lists/${list_type}/."
		echo_error "Choose one of:"
		cd "$TOP/package-lists/${list_type}/" ||
			die "failed to cd to $TOP/package-lists/${list_type}/"
		for list in *.pkgs; do
			echo_error "    ${list%.pkgs}"
		done
		die
	fi
}

function install_shfmt() {
	if [[ ! -f /usr/local/bin/shfmt ]]; then
		logmust sudo wget -nv -O /usr/local/bin/shfmt \
			https://github.com/mvdan/sh/releases/download/v2.4.0/shfmt_v2.4.0_linux_amd64
		logmust sudo chmod +x /usr/local/bin/shfmt
	fi
	echo "shfmt version $(shfmt -version) is installed."
}

function install_kernel_headers() {
	logmust determine_target_kernels
	check_env KERNEL_VERSIONS

	local kernel
	local headers_pkgs=""

	for kernel in $KERNEL_VERSIONS; do
		headers_pkgs="$headers_pkgs linux-headers-$kernel"
	done

	# shellcheck disable=SC2086
	logmust install_pkgs $headers_pkgs
}

function default_revision() {
	#
	# We use "delphix" in the default revision to make it easy to find all
	# packages built by delphix installed on an appliance.
	#
	# We choose a timestamp as the second part since we want each package
	# built to have a unique value for its full version, as new packages
	# with the same full version as already installed ones would be skipped
	# during an upgrade.
	#
	# Note that having revision numbers increasing monotonically is a
	# requirement during regular upgrades. This is not a hard requirement for
	# Delphix Appliance upgrades, however we prefer keeping things in-line
	# with the established conventions.
	#
	echo "delphix-$(date '+%Y.%m.%d.%H')"
}

#
# Fetch package repository into $WORKDIR/repo
#
function fetch_repo_from_git() {
	check_env PACKAGE_GIT_URL PACKAGE_GIT_BRANCH

	logmust mkdir "$WORKDIR/repo"
	logmust cd "$WORKDIR/repo"
	logmust git init

	#
	# If we are updating the package, we need to fetch both the
	# main branch and the upstream branch with their histories.
	# Otherwise just get the latest commit of the main branch.
	#
	if $DO_UPDATE_PACKAGE; then
		check_env REPO_UPSTREAM_BRANCH
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+$PACKAGE_GIT_BRANCH:repo-HEAD"
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+$REPO_UPSTREAM_BRANCH:upstream-HEAD"
	else
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+$PACKAGE_GIT_BRANCH:repo-HEAD" --depth=1
	fi

	logmust git checkout repo-HEAD
}

function generate_commit_message_from_dsc() {
	local dsc
	shopt -s failglob
	dsc=$(echo "$WORKDIR/source/$UPSTREAM_SOURCE_PACKAGE"*.dsc)
	shopt -u failglob

	rm -f "$WORKDIR/commit-message"
	grep -E '^Version:' "$dsc" >"$WORKDIR/commit-message"
	echo "" >>"$WORKDIR/commit-message"
	cat "$dsc" >>"$WORKDIR/commit-message"
}

function update_upstream_from_source_package() {
	check_env PACKAGE_GIT_BRANCH UPSTREAM_SOURCE_PACKAGE

	#
	# Fetch the source package into source/
	#
	logmust mkdir "$WORKDIR/source"
	logmust cd "$WORKDIR/source"
	logmust apt-get source "$UPSTREAM_SOURCE_PACKAGE"

	#
	# Checkout the upstream branch from our repository, and delete all
	# files.
	#
	logmust cd "$WORKDIR/repo"
	logmust git checkout -q upstream-HEAD
	logmust git rm -qrf .
	logmust git clean -qfxd

	#
	# Deploy the files from the source package on top of our repo.
	#
	logmust cd "$WORKDIR"
	shopt -s dotglob failglob
	logmust mv source/"$UPSTREAM_SOURCE_PACKAGE"*/* repo/
	shopt -u dotglob failglob

	#
	# Check if there are any changes. If so then commit them, and put the
	# source package description as the commit message.
	#
	logmust cd "$WORKDIR/repo"
	logmust git add -f .
	if git diff --cached --quiet; then
		echo "NOTE: upstream for $PACKAGE is already up-to-date."
	else
		logmust generate_commit_message_from_dsc
		logmust git commit -F "$WORKDIR/commit-message"

		logmust touch "$WORKDIR/upstream-updated"
	fi

	logmust cd "$WORKDIR"
}

function update_upstream_from_git() {
	check_env UPSTREAM_GIT_URL UPSTREAM_GIT_BRANCH
	logmust cd "$WORKDIR/repo"

	#
	# checkout our local branch that tracks upstream.
	#
	logmust git checkout -q upstream-HEAD

	#
	# Fetch updates from third-party upstream repository.
	#
	logmust git remote add upstream "$UPSTREAM_GIT_URL"
	logmust git fetch upstream "$UPSTREAM_GIT_BRANCH"

	#
	# Compare third-party upstream repository to our local snapshot of the
	# upstream repository.
	#
	if git diff --quiet FETCH_HEAD upstream-HEAD; then
		echo "NOTE: upstream for $PACKAGE is already up-to-date."
	else
		#
		# Note we do --ff-only here which will fail if upstream has
		# been rebased. We always want this behaviour as a rebase
		# is not something that maintainers usually do and if they do
		# then we definitely want to be notified.
		#
		logmust git merge --no-edit --ff-only --no-stat FETCH_HEAD

		logmust touch "$WORKDIR/upstream-updated"
	fi

	logmust cd "$WORKDIR"
}

#
# Creates a new changelog entry for the package with the appropriate fields.
# If no changelog file exists, source package name can be passed in first arg.
#
function set_changelog() {
	check_env PACKAGE_VERSION PACKAGE_REVISION
	local src_package="${1:-$PACKAGE}"

	logmust export DEBEMAIL="Delphix Engineering <eng@delphix.com>"
	if [[ -f debian/changelog ]]; then
		# update existing changelog
		logmust dch -b -v "${PACKAGE_VERSION}-${PACKAGE_REVISION}" \
			"Automatically generated changelog entry."
	else
		# create new changelog
		logmust dch --create --package "$src_package" \
			-v "${PACKAGE_VERSION}-${PACKAGE_REVISION}" \
			"Automatically generated changelog entry."
	fi
}

function dpkg_buildpackage_default() {
	logmust cd "$WORKDIR/repo"
	logmust set_changelog
	logmust dpkg-buildpackage -b -us -uc
	logmust cd "$WORKDIR/"
	logmust mv ./*deb artifacts/
}

#
# Store some metadata about what was this package built from. When running
# buildlist.sh, build_info for all packages is ingested by the metapackage
# and installed into /lib/delphix-buildinfo/<package-list>.info.
#
function store_git_info() {
	logmust pushd "$WORKDIR/repo"
	echo "Git hash: $(git rev-parse HEAD)" >"$WORKDIR/build_info" ||
		die "storing git info failed"
	echo "Git repo: $PACKAGE_GIT_URL" >>"$WORKDIR/build_info"
	echo "Git branch: $PACKAGE_GIT_BRANCH" >>"$WORKDIR/build_info"
	logmust popd
}

#
# Returns the default (usually latest) kernel version for a given platform.
# Result is placed into _RET.
#
function get_kernel_for_platform() {
	local platform="$1"
	local package

	#
	# For each supported platform, Ubuntu provides a 'linux-image-PLATFORM'
	# meta-package. This meta-package has a dependency on the default linux
	# image for that particular platform. For instance, Ubuntu has a
	# meta-package for AWS called 'linux-image-aws', which depends on
	# package 'linux-image-4.15.0-1027-aws'. The latter is the linux image
	# for kernel version '4.15.0-1027-aws'. We use this depenency to figure
	# out the default kernel version for a given platform.
	#
	# The "generic" platform is a special case, since we want to use the
	# hwe kernel image instead of the regular generic image.
	#
	# Note that while the default kernel is usually also the latest
	# available, it is not always the case.
	#

	if [[ "$platform" == generic ]] &&
		[[ "$UBUNTU_DISTRIBUTION" == bionic ]]; then
		package=linux-image-generic-hwe-18.04
	else
		package="linux-image-${platform}"
	fi

	if [[ "$(apt-cache show --no-all-versions "$package" \
		2>/dev/null | grep Depends)" =~ linux-image-([^,]*-${platform}) ]]; then
		_RET=${BASH_REMATCH[1]}
		return 0
	else
		die "failed to determine default kernel version for platform" \
			"'${platform}'"
	fi
}

#
# Determine which kernel versions to build modules for and store
# the value into KERNEL_VERSIONS, unless it is already set.
#
# We determine the target kernel versions based on the value passed for
# TARGET_PLATFORMS. Here is a list of accepted values for TARGET_PLATFORMS:
#  a) <empty>: to build for all supported platforms
#  b) "aws gcp ...": to build for the default kernel version of those platforms.
#  c) "4.15.0-1010-aws ...": to build for specific kernel versions
#  d) mix of b) and c)
#
function determine_target_kernels() {
	if [[ -n "$KERNEL_VERSIONS" ]]; then
		echo "Kernel versions to use to build modules:"
		echo "  $KERNEL_VERSIONS"
		return 0
	fi

	local supported_platforms="generic aws gcp azure kvm"
	local platform

	if [[ -z "$TARGET_PLATFORMS" ]]; then
		echo "TARGET_PLATFORMS not set, defaulting to: $supported_platforms"
		TARGET_PLATFORMS="$supported_platforms"
	fi

	local kernel
	for kernel in $TARGET_PLATFORMS; do
		for platform in $supported_platforms; do
			if [[ "$kernel" == "$platform" ]]; then
				logmust get_kernel_for_platform "$platform"
				kernel="$_RET"
				break
			fi
		done
		#
		# Check that the target kernel is valid
		#
		apt-cache show "linux-image-${kernel}" >/dev/null 2>&1 ||
			die "Invalid target kernel '$kernel'"

		KERNEL_VERSIONS="$KERNEL_VERSIONS $kernel"
	done

	echo "Kernel versions to use to build modules:"
	echo "  $KERNEL_VERSIONS"
}
