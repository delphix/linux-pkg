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

export _RET
export _RET_LIST
export DEBIAN_FRONTEND=noninteractive

export SUPPORTED_KERNEL_FLAVORS="generic aws gcp azure oracle"

#
# Used when fetching artifacts for external dependencies. Can be overridden
# for testing purposes to use jenkins-ops.<developer> instead.
#
export JENKINS_OPS_DIR="${JENKINS_OPS_DIR:-jenkins-ops}"

export UBUNTU_DISTRIBUTION="bionic"

#
# We currently support getting the linux kernel from 3 different sources:
#  1. "delphix": building it from code
#  2. "archive": dowloading from apt
#  3. "prebuilt": pre-built kernel stored in artifactory
#
export DEFAULT_LINUX_KERNEL_PACKAGE_SOURCE="delphix"

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
	echo -e "${FMT_BOLD}${FMT_RED}Error: $*${FMT_NF}" >&2
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
	[[ "$LOGGING" == "false" ]] || echo Running: "$@" >&2
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

#
# Determine DEFAULT_GIT_BRANCH. If it is unset, default to the branch set in
# branch.config.
#
function determine_default_git_branch() {

	[[ -n "$DEFAULT_GIT_BRANCH" ]] && return

	echo "DEFAULT_GIT_BRANCH is not set."
	if ! source "$TOP/branch.config" 2>/dev/null; then
		die "No branch.config file found in repo root."
	fi

	if [[ -z "$DEFAULT_GIT_BRANCH" ]]; then
		die "$DEFAULT_GIT_BRANCH parameter was not sourced" \
			"from branch.config. Ensure branch.config is" \
			"properly formatted with e.g." \
			"DEFAULT_GIT_BRANCH='<upstream-product-branch>'"
	fi

	echo "Defaulting DEFAULT_GIT_BRANCH to branch" \
		"$DEFAULT_GIT_BRANCH set in branch.config."

	export DEFAULT_GIT_BRANCH
}

function is_release_branch() {
	check_env DEFAULT_GIT_BRANCH
	[[ "$DEFAULT_GIT_BRANCH" == release/* ]]
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

	local hooks="
	prepare
	fetch
	build
	checkstyle
	update_upstream
	merge_with_upstream
	"

	for hook in $hooks; do
		unset "$hook"
	done

	local vars="
	PACKAGE_GIT_URL
	PACKAGE_GIT_BRANCH
	PACKAGE_VERSION
	PACKAGE_REVISION
	DEFAULT_PACKAGE_GIT_URL
	PACKAGE_DEPENDENCIES
	UPSTREAM_SOURCE_PACKAGE
	UPSTREAM_GIT_URL
	UPSTREAM_GIT_BRANCH
	WORKDIR
	PKGDIR
	PACKAGE_PREFIX
	FORCE_PUSH_ON_UPDATE
	SKIP_COPYRIGHTS_CHECK
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

	local dependency
	local deps_array=()
	for dependency in $PACKAGE_DEPENDENCIES; do
		#
		# Check for special value @linux-kernel which resolves to
		# all flavors of linux kernel packages.
		#
		if [[ $dependency == '@linux-kernel' ]]; then
			logmust list_linux_kernel_packages
			deps_array+=("${_RET_LIST[@]}")
			continue
		fi
		(check_package_exists "$dependency") ||
			die "Invalid package dependency '$dependency'"
		deps_array+=("$dependency")
	done
	PACKAGE_DEPENDENCIES="${deps_array[*]}"

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
#   PACKAGE_GIT_URL, PACKAGE_GIT_BRANCH, PACKAGE_REVISION
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
	fi

	if [[ -z "$PACKAGE_GIT_BRANCH" ]]; then
		PACKAGE_GIT_BRANCH="$DEFAULT_GIT_BRANCH"
		echo "PACKAGE_GIT_BRANCH set to value of DEFAULT_GIT_BRANCH"
	fi

	var="${PACKAGE_PREFIX}_REVISION"
	if [[ -n "$PARAM_PACKAGE_REVISION" ]]; then
		PACKAGE_REVISION="$PARAM_PACKAGE_REVISION"
		echo "PACKAGE_REVISION passed from '-r'"
	elif [[ -n "${!var}" ]]; then
		PACKAGE_REVISION="${!var}"
		echo "PACKAGE_REVISION set to value of ${var}"
	fi

	if [[ -z "$PACKAGE_REVISION" ]]; then
		PACKAGE_REVISION="$DEFAULT_REVISION"
		echo "PACKAGE_REVISION set to value of DEFAULT_REVISION"
	fi

	export PACKAGE_GIT_URL
	export PACKAGE_GIT_BRANCH
	export PACKAGE_REVISION

	echo_bold "------------------------------------------------------------"
	echo_bold "PACKAGE_GIT_URL:      $PACKAGE_GIT_URL"
	echo_bold "PACKAGE_GIT_BRANCH:   $PACKAGE_GIT_BRANCH"
	echo_bold "PACKAGE_REVISION:     $PACKAGE_REVISION"
	echo_bold "------------------------------------------------------------"
}

function create_workdir() {
	check_env WORKDIR
	logmust sudo rm -rf "$WORKDIR"
	logmust mkdir "$WORKDIR"
	logmust rm -f "$TOP/workdir"
	logmust ln -s "$WORKDIR" "$TOP/workdir"
}

#
# apt install packages.
#
function install_pkgs() {
	for attempt in {1..3}; do
		echo "Running: sudo env DEBIAN_FRONTEND=noninteractive " \
			"apt-get install -y --allow-downgrades $*"

		#
		# We use the "--allow-downgrades" for the case of a
		# package needing to install the "unzip" debian package
		# that we build via the "misc-debs" linux-pkg package.
		# The "misc-debs" based "unzip" package may have an
		# older version than what's already installed on the
		# system, so we need to "--allow-downgrades" in order to
		# install that specific package; further, that specific
		# package is required to build the "virtualization"
		# debian packages.
		#
		sudo env DEBIAN_FRONTEND=noninteractive apt-get install \
			-y --allow-downgrades "$@" && return

		echo "apt-get install failed, retrying."
		sleep 10
	done
	die "apt-get install failed after $attempt attempts"
}

#
# Install build dependencies listed in the debian/control file of the package.
#
function install_build_deps_from_control_file() {
	logmust pushd "$WORKDIR/repo"
	logmust sudo env DEBIAN_FRONTEND=noninteractive mk-build-deps --install \
		--tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' \
		debian/control
	logmust popd
}

#
# Returns a list of all known packages in _RET_LIST.
#
function list_all_packages() {
	local pkg

	_RET_LIST=()

	for pkg in "$TOP/packages/"*; do
		pkg=$(basename "$pkg")
		if [[ -f "$TOP/packages/$pkg/config.sh" ]]; then
			_RET_LIST+=("$pkg")
		fi
	done
}

#
# Read a new-line separated list from a file, removing extra whitespace
# and comments. Return items in _RET_LIST.
#
function read_list() {
	local file="$1"

	local item
	local line

	_RET_LIST=()

	[[ -f "$file" ]] || die "Not a file: $file"

	while read -r line; do
		# trim whitespace
		item=$(echo "$line" | tr -d '[:space:]')
		[[ -z "$item" ]] && continue
		# ignore comments
		[[ ${item:0:1} == "#" ]] && continue
		_RET_LIST+=("$item")
	done <"$file" || die "Failed to read list: $file"
}

#
# Read a package-list file and return listed packages in _RET_LIST.
#
function read_package_list() {
	local file="$1"

	local pkg

	logmust read_list "$file"
	for pkg in "${_RET_LIST[@]}"; do
		check_package_exists "$pkg"
	done
}

#
# List all target kernel packages. By default, it returns all the kernel
# flavors supported and built by linux-pkg, however this can be overridden
# via TARGET_KERNEL_FLAVORS, which can be useful when testing changes against
# a specific, or even mainline kernel.
#
function list_linux_kernel_packages() {
	local kernel

	_RET_LIST=()
	if [[ -n "$TARGET_KERNEL_FLAVORS" ]]; then
		for kernel in $TARGET_KERNEL_FLAVORS; do
			(check_package_exists "linux-kernel-$kernel") ||
				die "Invalid entry '$kernel' in TARGET_KERNEL_FLAVORS"
			_RET_LIST+=("linux-kernel-$kernel")
		done
	else
		for kernel in $SUPPORTED_KERNEL_FLAVORS; do
			check_package_exists "linux-kernel-$kernel"
			_RET_LIST+=("linux-kernel-$kernel")
		done
	fi
	return 0
}

function install_shfmt() {
	if [[ ! -f /usr/local/bin/shfmt ]]; then
		logmust sudo wget -nv -O /usr/local/bin/shfmt \
			https://github.com/mvdan/sh/releases/download/v2.4.0/shfmt_v2.4.0_linux_amd64
		logmust sudo chmod +x /usr/local/bin/shfmt
	fi
	echo "shfmt version $(shfmt -version) is installed."
}

#
# Install kernel headers packages for all target kernels.
# The kernel packages are fetched from S3.
#
function install_kernel_headers() {
	logmust determine_target_kernels
	check_env KERNEL_VERSIONS DEPDIR

	logmust list_linux_kernel_packages
	# Note: linux packages returned in _RET_LIST

	#
	# On some platforms there are 2 headers packages and both must be
	# installed. Here's an example on AWS:
	#  - linux-headers-5.3.0-1030-aws_5.3.0-1030.32~18.04.1_amd64.deb
	#  - linux-aws-5.3-headers-5.3.0-1030_5.3.0-1030.32~18.04.1_all.deb
	#
	local pkg
	for pkg in "${_RET_LIST[@]}"; do
		logmust install_pkgs "$DEPDIR/$pkg/"*-headers-*.deb
	done

	#
	# Verify that headers are installed for all kernel versions
	# stored in KERNEL_VERSIONS
	#
	local kernel
	for kernel in $KERNEL_VERSIONS; do
		logmust dpkg-query -l "linux-headers-$kernel" >/dev/null
	done
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

function determine_dependencies_base_url() {
	[[ -n "$DEPENDENCIES_BASE_URL" ]] && return

	check_env DEFAULT_GIT_BRANCH

	#
	# The location of package artifacts depends on whether a release tag
	# or a development branch is being built.
	#
	if is_release_branch; then
		local version="${DEFAULT_GIT_BRANCH#release/}"
		local url="s3://release-de-images/internal-artifacts/$version"
		local suv
		suv="$(aws s3 ls "$url/" | awk '{print $2}' | tr -d '/' | sort -V | tail -n 1)"
		[[ -n "$suv" ]] || die "No artifacts found at $url"
		DEPENDENCIES_BASE_URL="$url/$suv/input-artifacts/combined-packages/packages"
	else
		DEPENDENCIES_BASE_URL="s3://snapshot-de-images/builds/$JENKINS_OPS_DIR/devops-gate/master/linux-pkg/$DEFAULT_GIT_BRANCH/build-package"
	fi

	#
	# Make sure the dependencies directory actually exists
	#
	logmust aws s3 ls "$DEPENDENCIES_BASE_URL"

	export DEPENDENCIES_BASE_URL
}

function get_package_dependency_s3_url() {
	local dep="$1"

	logmust determine_dependencies_base_url

	#
	# The base url can be either pointing to:
	# 1. Input artifacts from a previously built Delphix Appliance, or
	# 2. A build-package/<package> directory that stores many builds of the
	#    same package and a "latest" link that points to the latest build
	#    for that package.
	# In case 1 the artifacts are right there under the base url, whereas
	# in case 2 we first need to dereference the "latest" link.
	#
	# The user can provide their own DEPENDENCIES_BASE_URL based on a
	# previous Delphix Appliance build or have it determined automatically
	# by determine_dependencies_base_url() based on the product branch
	# being built.
	#
	if [[ "$DEPENDENCIES_BASE_URL" == */build-package ]]; then
		local s3url="$DEPENDENCIES_BASE_URL/$dep/post-push"
		(logmust aws s3 cp --only-show-errors "$s3url/latest" .) ||
			die "Artifacts for dependency '$dep' missing." \
				"Dependency must be built first."
		logmust cat latest
		local bucket="${DEPENDENCIES_BASE_URL#s3://}"
		bucket=${bucket%%/*}
		s3url="s3://$bucket/$(cat latest)"
		logmust rm latest
		_RET="$s3url"
	else
		_RET="$DEPENDENCIES_BASE_URL/$dep"
	fi
}

#
# Fetch artifacts from S3 for all packages listed in PACKAGE_DEPENDENCIES which
# is defined in the package's config.
#
function fetch_dependencies() {
	export DEPDIR="$WORKDIR/dependencies"
	logmust mkdir "$DEPDIR"
	logmust cd "$DEPDIR"

	if [[ -z "$PACKAGE_DEPENDENCIES" ]]; then
		echo "Package has no linux-pkg dependencies to fetch."
		return
	fi

	local dep s3urlvar s3url
	for dep in $PACKAGE_DEPENDENCIES; do
		echo "Fetching artifacts for dependency '$dep' ..."
		get_package_prefix "$dep"
		s3urlvar="${_RET}_S3_URL"
		if [[ -n "${!s3urlvar}" ]]; then
			s3url="${!s3urlvar}"
			echo "S3 URL of package dependency '$dep' provided" \
				"externally"
			echo "$s3urlvar=$s3url"
		else
			logmust get_package_dependency_s3_url "$dep"
			s3url="$_RET"
		fi
		[[ "$s3url" != */ ]] && s3url="$s3url/"
		logmust mkdir "$dep"
		logmust aws s3 ls "$s3url"
		logmust aws s3 cp --only-show-errors --recursive "$s3url" "$dep/"
		echo_bold "Fetched artifacts for '$dep' from $s3url"
		PACKAGE_DEPENDENCIES_METADATA="${PACKAGE_DEPENDENCIES_METADATA}$dep: $s3url\\n"
	done
}

#
# Fetch package repository into $WORKDIR/repo
#
function fetch_repo_from_git() {
	check_env PACKAGE_GIT_URL PACKAGE_GIT_BRANCH DEFAULT_GIT_BRANCH

	logmust mkdir "$WORKDIR/repo"
	logmust cd "$WORKDIR/repo"
	logmust git init

	#
	# If we are updating the package, we need to fetch both the
	# main branch and the upstream branch with their histories.
	# Otherwise just get the latest commit of the main branch.
	#
	if [[ "$DO_UPDATE_PACKAGE" == "true" ]]; then
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+$PACKAGE_GIT_BRANCH:repo-HEAD"
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+upstreams/$DEFAULT_GIT_BRANCH:upstream-HEAD"
		logmust git show-ref repo-HEAD
		logmust git show-ref upstream-HEAD
	else
		logmust git fetch --no-tags "$PACKAGE_GIT_URL" \
			"+$PACKAGE_GIT_BRANCH:repo-HEAD" --depth=1
		logmust git show-ref repo-HEAD
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

#
# Fetches branch upstreams/<branch> from our default repository into local
# upstream-HEAD branch, then attempts to update it with changes from
# the source package UPSTREAM_SOURCE_PACKAGE, fetched from apt.
#
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
		logmust git show-ref upstream-HEAD

		logmust touch "$WORKDIR/upstream-updated"
	fi

	logmust cd "$WORKDIR"
}

#
# Fetches branch upstreams/<branch> from our default repository into local
# upstream-HEAD branch, then attempts to update it with changes from
# the remote repository specified by UPSTREAM_GIT_URL and UPSTREAM_GIT_BRANCH.
#
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
		logmust git show-ref upstream-HEAD

		logmust touch "$WORKDIR/upstream-updated"
	fi

	logmust cd "$WORKDIR"
}

#
# Returns true if upstreams/<branch> needs to be merged into <branch> for the
# active package, where <branch> is the branch being updated, i.e.
# DEFAULT_GIT_BRANCH.
#
function is_merge_needed() {
	local repo_ref="refs/heads/repo-HEAD"
	local upstream_ref="refs/heads/upstream-HEAD"

	logmust pushd "$WORKDIR/repo"
	check_git_ref "$upstream_ref" "$repo_ref"

	if git merge-base --is-ancestor "$upstream_ref" "$repo_ref"; then
		echo "Upstream is already merged into repo-HEAD"
		_RET=false
	else
		_RET=true
	fi
	logmust popd
}

#
# Default function for merging upstreams/<branch> into <branch>, where <branch>
# is the branch being updated, i.e. DEFAULT_GIT_BRANCH. Note that this function
# does not actually look at the upstream repository itself, but relies on
# local branches repo-HEAD and upstream-HEAD to be present.
#
# If merge was needed, file $WORKDIR/repo-updated is created and previous tip
# of <branch> is saved in repo-HEAD-saved. The repo-updated file lets the
# caller (typically Jenkins) know if a merge was necessary. The repo-HEAD-saved
# ref should be compared to the remote branch when it is time to push the
# merge; if they differ it means that the remote branch was modified and
# so the merge should be aborted -- this can happen if a PR was merged by a
# developer while auto-update was running.
#
function merge_with_upstream_default() {
	local repo_ref="refs/heads/repo-HEAD"
	local upstream_ref="refs/heads/upstream-HEAD"

	logmust cd "$WORKDIR/repo"
	check_git_ref "$upstream_ref" "$repo_ref"

	logmust git checkout -q repo-HEAD

	if git merge-base --is-ancestor "$upstream_ref" HEAD; then
		echo "NOTE: $PACKAGE is already up-to-date with upstream."
		return 0
	fi

	#
	# Do a backup of the repo-HEAD branch so that it can be compared to the
	# remote when time comes to do a push.
	#
	logmust git branch repo-HEAD-saved

	logmust git merge --no-edit --no-stat "$upstream_ref"
	logmust git show-ref repo-HEAD
	logmust touch "$WORKDIR/repo-updated"
}

#
# Check if git credentials are set for pushing update. If running in
# interactive mode, it will prompt the user for credentials if they are not
# provided in env.
#
function check_git_credentials_set() {
	if [[ -z "$PUSH_GIT_TOKEN" ]] && [[ -z "$PUSH_GIT_USER" || -z "$PUSH_GIT_PASSWORD" ]]; then
		if [[ -t 1 ]]; then
			if [[ "$DRYRUN" == "false" ]]; then
				echo_bold "WARNING: this is NOT a dry-run, you are pushing to" \
					"a production branch"
			fi
			echo "Please enter git token to push to remote ($DEFAULT_PACKAGE_GIT_URL)."
			read -r -s -p "Token: " PUSH_GIT_TOKEN
			export PUSH_GIT_TOKEN
		else
			die "PUSH_GIT_TOKEN or PUSH_GIT_USER & PUSH_GIT_PASSWORD must be set."
		fi
	fi
}

#
# Push a local ref to a remote ref of the default remote repository for the
# package.
#
function push_to_remote() {
	local local_ref="$1"
	local remote_ref="$2"
	local force="${3:-false}"

	local flags=""
	$force && flags="-f"

	logmust check_git_credentials_set

	check_env DEFAULT_PACKAGE_GIT_URL

	local git_url_with_creds
	local git_url_with_fake_creds

	if [[ -n "$PUSH_GIT_TOKEN" ]]; then
		git_url_with_creds="${DEFAULT_PACKAGE_GIT_URL/https:\/\//https:\/\/${PUSH_GIT_TOKEN}@}"
		git_url_with_fake_creds="${DEFAULT_PACKAGE_GIT_URL/https:\/\//https:\/\/${PUSH_GIT_TOKEN:0:4}******@}"
	elif [[ -n "$PUSH_GIT_USER" && -n "$PUSH_GIT_PASSWORD" ]]; then
		git_url_with_creds="${DEFAULT_PACKAGE_GIT_URL/https:\/\//https:\/\/${PUSH_GIT_USER}:${PUSH_GIT_PASSWORD}@}"
		git_url_with_fake_creds="${DEFAULT_PACKAGE_GIT_URL/https:\/\//https:\/\/${PUSH_GIT_USER}:******@}"
	else
		die "Either PUSH_GIT_TOKEN or PUSH_GIT_USER & PUSH_GIT_PASSWORD must be provided"
	fi

	logmust cd "$WORKDIR/repo"
	check_git_ref "$local_ref"

	echo "RUNNING: git push $flags $git_url_with_fake_creds $local_ref:$remote_ref"
	git push $flags "$git_url_with_creds" "$local_ref:$remote_ref" ||
		die "push failed"
}

#
# Creates a new changelog entry for the package with the appropriate fields.
# If no changelog file exists, source package name can be passed in first arg.
#
function set_changelog() {
	check_env PACKAGE_REVISION
	local src_package="${1:-$PACKAGE}"

	#
	# If PACKAGE_VERSION hasn't been set already, then retrieve it from
	# The changelog file. If the changelog file doesn't exist, which
	# could be the case for in-house packages where we do not care about
	# the version, then default to "1.0.0".
	#
	if [[ -z "$PACKAGE_VERSION" ]]; then
		if [[ -f debian/changelog ]]; then
			PACKAGE_VERSION="$(logmust dpkg-parsechangelog -S Version | awk -F'-' '{print $1}')"
		else
			PACKAGE_VERSION=1.0.0
		fi
	fi

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

#
# Default dpkg_buildpackage function for building packages. Before running the
# build, it updates the version of the package in the changelog.
#
function dpkg_buildpackage_default() {
	logmust cd "$WORKDIR/repo"
	logmust set_changelog
	logmust dpkg-buildpackage -b -us -uc
	logmust cd "$WORKDIR/"
	logmust mv ./*deb artifacts/
}

#
# Returns the default (usually latest) kernel version for a given platform.
# Result is placed into _RET.
#
function get_kernel_version_for_platform_from_apt() {
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
# Given a kernel version, fetch all necessary linux kernel packages
# into WORKDIR/artifacts. Also store kernel version into KERNEL_VERSION.
#
function fetch_kernel_from_apt_for_version() {
	local kernel_version="$1"

	logmust cd "$WORKDIR/artifacts"
	logmust apt-get download \
		"linux-image-${kernel_version}" \
		"linux-image-${kernel_version}-dbgsym" \
		"linux-modules-${kernel_version}" \
		"linux-headers-${kernel_version}" \
		"linux-tools-${kernel_version}"

	#
	# For the azure kernel, we also want to get the linux-cloud-tools
	# package. Not that we cannot do this indiscriminately since some
	# kernel flavors do not come with a linux-cloud-tools package.
	#
	if [[ "$kernel_version" == *azure ]]; then
		logmust apt-get download "linux-cloud-tools-${kernel_version}"
	fi

	#
	# Fetch direct dependencies of the downloaded debs. Some of those
	# dependencies have a slightly different naming scheme than the other
	# kernel packages.
	#
	local deb dep deps
	for deb in *deb; do
		deps=$(dpkg-deb -f "$deb" Depends | tr -d ' ' | tr ',' ' ') ||
			die "failed to get dependencies for $deb"
		for dep in $deps; do
			case "$dep" in
			*-headers-* | *-tools-* | *-dbgsym)
				logmust apt-get download "$dep"
				;;
			esac
		done
	done

	echo "$kernel_version" >KERNEL_VERSION
}

#
# Find latest linux kernel available in apt for the given platform, and
# download all the necessary linux-kernel packages.
#
function fetch_kernel_from_apt_for_platform() {
	local platform="$1"

	local kernel_version
	logmust get_kernel_version_for_platform_from_apt "$platform"
	kernel_version="$_RET"

	logmust fetch_kernel_from_apt_for_version "$kernel_version"
}

#
# Fetch linux kernel packages from apt for the given kernel version. Also
# fetch the pre-built linux-modules package from artifactory. The pre-built
# package should have the same name as the one downloaded from apt but
# a higher revision number so that it will be picked over the default one
# downloaded from apt during the build of the appliance.
#
function fetch_kernel_from_artifactory() {
	local kernel_version="$1"
	local artifactory_deb="$2"

	logmust fetch_kernel_from_apt_for_version "$kernel_version"

	local url="http://artifactory.delphix.com/artifactory"
	url="$url/linux-pkg/linux-prebuilt/${artifactory_deb}"

	logmust cd "$WORKDIR/artifacts"
	fetch_file_from_artifactory "$url"
}

function fetch_file_from_artifactory() {
	local url="$1"
	local sha256_expected="$2"
	local file sha256_actual

	[[ -n "$url" ]] || die "url argument is missing."
	file="$(basename "$url")"

	logmust wget -nv "$url" -O "$file"

	if [[ -n "$sha256_expected" ]]; then
		sha256_actual="$(sha256sum "$file" | awk '{print $1}')"
		if [[ "$sha256_expected" != "$sha256_actual" ]]; then
			die "SHA256 mismatch. Expected: $sha256_expected," \
				"Actual: $sha256_actual"
		fi
	fi
}

#
# Determine which kernel versions to build modules for and store
# the value into KERNEL_VERSIONS, unless it is already set.
#
# We determine the target kernel versions based on the kernel package
# dependencies fetched through fetch_dependencies().
#
function determine_target_kernels() {
	if [[ -n "$KERNEL_VERSIONS" ]]; then
		echo_bold "Kernel versions to use to build modules:"
		echo_bold "  $KERNEL_VERSIONS"
		return 0
	fi

	[[ -n "$DEPDIR" ]] || die "determine_target_kernels() can only be" \
		"called after fetch_dependencies() stage has run."

	logmust list_linux_kernel_packages
	# note: list of kernel packages returned in _RET_LIST

	local pkg kernel
	for pkg in "${_RET_LIST[@]}"; do
		logmust test -d "$DEPDIR/$pkg"
		#
		# When Linux kernel packages are built, they must store the
		# kernel version into a file named 'KERNEL_VERSION'.
		#
		(logmust test -f "$DEPDIR/$pkg/KERNEL_VERSION") ||
			die "KERNEL_VERSION file missing from dependency '$pkg'"
		kernel="$(cat "$DEPDIR/$pkg/KERNEL_VERSION")"
		[[ -n "$kernel" ]] || die "invalid value '$kernel'" \
			"in $DEPDIR/$pkg/KERNEL_VERSION"
		KERNEL_VERSIONS="$KERNEL_VERSIONS $kernel"
		KERNEL_VERSIONS_METADATA="${KERNEL_VERSIONS_METADATA}${pkg}: ${kernel}\\n"
	done

	echo_bold "Kernel versions to use to build modules:"
	echo_bold "  $KERNEL_VERSIONS"
}

#
# Install gcc 8, and make it the default
#
function install_gcc8() {
	logmust install_pkgs gcc-8 g++-8
	logmust sudo update-alternatives --install /usr/bin/gcc gcc \
		/usr/bin/gcc-7 700 --slave /usr/bin/g++ g++ /usr/bin/g++-7
	logmust sudo update-alternatives --install /usr/bin/gcc gcc \
		/usr/bin/gcc-8 800 --slave /usr/bin/g++ g++ /usr/bin/g++-8
}

#
# Store git-related build info for the package after the build is done.
# Note that some of this metadata is used by the Jenkins build so be careful
# when modifying it.
#
function store_git_info() {
	logmust pushd "$WORKDIR/repo"
	local git_hash
	git_hash="$(git rev-parse HEAD)" || die "Failed retrieving git hash"
	echo "$git_hash" >"$WORKDIR/artifacts/GIT_HASH"

	cat <<-EOF >>"$WORKDIR/artifacts/BUILD_INFO"
		Git hash: $git_hash
		Git repo: $PACKAGE_GIT_URL
		Git branch: $PACKAGE_GIT_BRANCH
	EOF
	logmust popd
}

#
# Store build info metadata for the package after the build is done.
# Note that some of this metadata is used by the Jenkins build so be careful
# when modifying it.
#
function store_build_info() {
	if [[ -d "$WORKDIR/repo/.git" ]]; then
		logmust store_git_info
	fi

	if [[ -n "$KERNEL_VERSIONS_METADATA" ]]; then
		echo -ne "$KERNEL_VERSIONS_METADATA" >"$WORKDIR/artifacts/KERNEL_VERSIONS" ||
			die 'Failed to store kernel versions metadata'
	fi

	if [[ -n "$PACKAGE_DEPENDENCIES_METADATA" ]]; then
		echo -ne "$PACKAGE_DEPENDENCIES_METADATA" >"$WORKDIR/artifacts/PACKAGE_DEPENDENCIES" ||
			die 'Failed to store package dependencies metadata'
	fi

	if [[ -f "$TOP/PACKAGE_MIRROR_URL_MAIN" ]]; then
		logmust cp "$TOP/PACKAGE_MIRROR_URL_MAIN" "$WORKDIR/artifacts/"
	fi

	if [[ -f "$TOP/PACKAGE_MIRROR_URL_SECONDARY" ]]; then
		logmust cp "$TOP/PACKAGE_MIRROR_URL_SECONDARY" "$WORKDIR/artifacts/"
	fi
}
