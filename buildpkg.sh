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

TOP="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$TOP/lib/common.sh"

logmust check_running_system

function merge_with_upstream() {
	local upstream_ref="refs/heads/upstream-HEAD"

	logmust cd "$WORKDIR/repo"
	check_git_ref "$upstream_ref" "refs/heads/repo-HEAD"

	logmust git checkout -q repo-HEAD

	if git merge-base --is-ancestor "$upstream_ref" HEAD; then
		echo "NOTE: $PACKAGE is already up-to-date with upstream."
		return 0
	fi

	echo "Running: git merge --no-edit $upstream_ref"
	if git merge --no-edit --no-stat "$upstream_ref"; then
		echo "git merge succeeded"
		logmust touch "$WORKDIR/repo-updated"
		return 0
	else
		echo "git merge failed"
		logmust git merge --abort
		return 1
	fi
}

#
# Inititalize Delphix git repository from a source package.
#
function inititalize_from_upstream_source_package() {
	check_env UPSTREAM_SOURCE_PACKAGE

	#
	# Fetch the source package into source/
	#
	logmust mkdir "$WORKDIR/source"
	logmust cd "$WORKDIR/source"
	logmust apt-get source "$UPSTREAM_SOURCE_PACKAGE"

	#
	# Create initial repository from the package source.
	# Both repo-HEAD and upstream-HEAD point to the same commit.
	#
	logmust cd "$WORKDIR"
	logmust mv source/"$UPSTREAM_SOURCE_PACKAGE"*/ repo
	logmust cd "$WORKDIR/repo"
	logmust git init
	logmust git checkout -b repo-HEAD
	logmust git add -f .
	logmust generate_commit_message_from_dsc
	logmust git commit -F "$WORKDIR/commit-message"
	logmust git branch upstream-HEAD

	logmust touch "$WORKDIR/upstream-updated"
	logmust touch "$WORKDIR/repo-updated"
}

#
# Inititalize Delphix git repository from an upstream git repository.
#
function inititalize_from_upstream_git() {
	check_env UPSTREAM_GIT_URL UPSTREAM_GIT_BRANCH

	logmust mkdir "$WORKDIR/repo"
	logmust cd "$WORKDIR/repo"
	logmust git init
	logmust git remote add upstream "$UPSTREAM_GIT_URL"
	logmust git fetch upstream "$UPSTREAM_GIT_BRANCH"

	logmust git branch repo-HEAD FETCH_HEAD
	logmust git branch upstream-HEAD FETCH_HEAD

	logmust git checkout -q repo-HEAD

	logmust touch "$WORKDIR/upstream-updated"
	logmust touch "$WORKDIR/repo-updated"
}

function inititalize_from_upstream() {
	if [[ -n "$UPSTREAM_GIT_URL" ]]; then
		logmust inititalize_from_upstream_git
	elif [[ -n "$UPSTREAM_SOURCE_PACKAGE" ]]; then
		logmust inititalize_from_upstream_source_package
	else
		die "$PACKAGE/config.sh must contain either" \
			"UPSTREAM_SOURCE_PACKAGE or UPSTREAM_GIT_URL/BRANCH."
	fi
}

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") [-i | -u [-M]] [-ch] [-g pkg_git_url]"
	echo "         [-b pkg_git_branch] [-v pkg_version] [-r pkg_revision]"
	echo "         package"
	echo ""
	echo "  This script builds a package based on its config.sh. If '-u'"
	echo "  is provided it will first attempt to merge the package with"
	echo "  upstream. If no options are provided it will fetch the package"
	echo "  source from the master branch of the url defined in config.sh"
	echo "  and then build it."
	echo "  Options:"
	echo ""
	echo "    -i  Create initial repo from an upstream git repo or"
	echo "        source package. Conflicts with -u."
	echo "    -u  Update upstream branch and merge main branch with"
	echo "        upstream. Build only if main branch has changed."
	echo "        Conflicts with -i."
	echo "    -M  When passed with -u, only update upstream branch and"
	echo "        never attempt to build."
	echo "    -c  Call the checkstyle hook after fetching package."
	echo "    -g  override default git url for the package."
	echo "    -b  override default git branch for the package."
	echo "    -v  override default version for package."
	echo "    -r  override default revision for package."
	echo "    -h  display this message and exit."
	echo ""
	exit 2
}

unset PARAM_PACKAGE_GIT_URL
unset PARAM_PACKAGE_GIT_BRANCH
unset PARAM_PACKAGE_VERSION
unset PARAM_PACKAGE_REVISION

export DO_UPDATE_PACKAGE=false

do_checkstyle=false
do_initialize=false
do_merge=true
while getopts ':b:cg:hik:Mr:uv:' c; do
	case "$c" in
	g) export PARAM_PACKAGE_GIT_URL="$OPTARG" ;;
	b) export PARAM_PACKAGE_GIT_BRANCH="$OPTARG" ;;
	v) export PARAM_PACKAGE_VERSION="$OPTARG" ;;
	r) export PARAM_PACKAGE_REVISION="$OPTARG" ;;
	k) export TARGET_PLATFORMS="$OPTARG" ;;
	c) do_checkstyle=true ;;
	i) do_initialize=true ;;
	u) DO_UPDATE_PACKAGE=true ;;
	M) do_merge=false ;;
	h) usage >&2 ;;
	*) usage "illegal option -- $OPTARG" >&2 ;;
	esac
done
shift $((OPTIND - 1))
[[ $# -lt 1 ]] && usage "package argument missing" >&2
[[ $# -gt 1 ]] && usage "too many arguments" >&2
PACKAGE=$1

$DO_UPDATE_PACKAGE && $do_initialize && usage "-i and -u are exclusive" >&2
! $do_merge && ! $DO_UPDATE_PACKAGE && usage "-M requires -u" >&2

logmust check_package_exists "$PACKAGE"

#
# DEFAULT_REVISION & DEFAULT_GIT_BRANCH will be set if called from buildlist.sh.
# If the script is called manually, we set it here.
#
DEFAULT_REVISION="${DEFAULT_REVISION:-$(default_revision)}"
logmust determine_default_git_branch

echo ""
echo_bold "===================================================================="
echo_bold "                     PACKAGE $PACKAGE"
echo_bold "===================================================================="
echo ""

logmust load_package_config "$PACKAGE"

logmust sudo rm -rf "$WORKDIR"
logmust mkdir "$WORKDIR"
logmust mkdir "$WORKDIR/artifacts"

if $do_initialize; then
	logmust inititalize_from_upstream
	echo_success "Repository initialized from upstream in $WORKDIR/repo"
	exit 0
fi

logmust cd "$WORKDIR"
stage fetch

if $DO_UPDATE_PACKAGE; then
	logmust cd "$WORKDIR"
	logmust touch "$WORKDIR/updating-upstream"
	type -t update_upstream >/dev/null ||
		die "$PACKAGE: Hook 'update_upstream()' not found!"
	stage update_upstream
	logmust rm "$WORKDIR/updating-upstream"

	if ! $do_merge; then
		echo_bold "Not attempting to merge with upstream since" \
			"-M is set."
		exit 0
	fi

	logmust touch "$WORKDIR/merging"
	logmust merge_with_upstream
	logmust rm "$WORKDIR/merging"
	if [[ ! -f "$WORKDIR/repo-updated" ]]; then
		echo_bold "Not building package $PACKAGE since we are doing" \
			"an update but the repo is already up-to-date"
		exit 0
	fi
fi

logmust cd "$WORKDIR"
stage prepare

logmust touch "$WORKDIR/building"
if $do_checkstyle; then
	logmust cd "$WORKDIR"
	stage checkstyle
fi
logmust cd "$WORKDIR"
stage build
logmust rm "$WORKDIR/building"

logmust cd "$WORKDIR"
stage store_build_info

echo_success "Package $PACKAGE has been built successfully."
echo "Build products are in $WORKDIR/artifacts"
echo ""

if $DO_UPDATE_PACKAGE; then
	echo_success "Auto-merge with upstream performed" \
		"successfully in $WORKDIR/repo"
fi
