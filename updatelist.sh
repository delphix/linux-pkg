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

#
# This script first updates a list of third-party packages with upstream
# by running "buildpkg.sh -u" on each package. If updates can be merged
# cleanly and the resulting package builds, the merge is pushed to the
# package's repository (denoted by DEFAULT_PACKAGE_GIT_URL in its config.sh).
#

TOP="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$TOP/lib/common.sh"

logmust check_running_system

function exit_hook() {
	echo_error "Script has exited unexpectedly."
	FAILURE=true

	if [[ -z "$STATUS_DIR" ]] || [[ ! -d "$STATUS_DIR" ]]; then
		echo_error "Script failed during the setup phase."
		return
	fi

	report_status_all
}

function record_failure() {
	FAILURE=true
	if $stop_on_failure; then
		echo_error "Stopping on failure."
		trap - EXIT

		report_status_all
		exit 1
	fi
}

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") [-hns] <list>"
	echo ""
	echo "This script attempts to update all the packages in"
	echo "package-lists/update/<list>.pkgs."
	echo ""
	echo "    -n  dry-run. Pass the dry-run flag to git push (git push -n)."
	echo "    -r  release. Update packages for a release branch."
	echo "    -s  stop on failure. By default script continues when update"
	echo "        for a package fails."
	echo "    -h  display this message and exit."
	echo ""
	exit 2
}

release=false
dry_run=false
stop_on_failure=false
while getopts ':hnrs' c; do
	case "$c" in
	r) release=true ;;
	s) stop_on_failure=true ;;
	n) dry_run=true ;;
	h) usage >&2 ;;
	*) usage "illegal option -- $OPTARG" >&2 ;;
	esac
done
shift $((OPTIND - 1))
[[ $# -ne 1 ]] && usage "takes exactly one argument." >&2

pkg_list="$1"
logmust get_package_list_file "update" "$pkg_list"
pkg_list_file="$_RET"

trap exit_hook EXIT
FAILURE=false

$dry_run && echo "This is a dry-run, updates will NOT be pushed to remotes."

logmust query_git_credentials

logmust cd "$TOP"

logmust make clean
STATUS_DIR="$TOP/update-status"
logmust mkdir "$STATUS_DIR"

function report_status() {
	local pkg
	local status

	if $FAILURE; then
		status="${FMT_RED}FAILURE${FMT_NF}"
	else
		status="${FMT_GREEN}SUCCESS${FMT_NF}"
	fi

	echo ""
	echo -e "${FMT_BOLD}Status Report: $status"

	#
	# Return if there is nothing to report
	#
	[[ -f "$STATUS_DIR/upstream-pushed" ]] ||
		[[ -f "$STATUS_DIR/merge-pushed" ]] ||
		[[ -f "$STATUS_DIR/update-failed" ]] ||
		[[ -f "$STATUS_DIR/unexpected-failure" ]] ||
		return

	echo_bold "___________________________________________"

	if $dry_run; then
		echo_bold "NOTE: This is a dry-run, updates are NOT pushed."
		echo ""
	fi

	if [[ -f "$STATUS_DIR/upstream-pushed" ]]; then
		echo -e "${FMT_GREEN}Upstream updated for following" \
			"packages:${FMT_NF}"
		while read -r pkg; do
			echo -e "${FMT_GREEN}    $pkg${FMT_NF}"
		done <"$STATUS_DIR/upstream-pushed"
		echo ""
	fi

	if [[ -f "$STATUS_DIR/merge-pushed" ]]; then
		echo -e "${FMT_GREEN}Merged following packages with" \
			"upstream:${FMT_NF}"
		while read -r pkg; do
			echo -e "${FMT_GREEN}    $pkg${FMT_NF}"
		done <"$STATUS_DIR/merge-pushed"
		echo ""
	fi

	if [[ -f "$STATUS_DIR/update-failed" ]]; then
		echo -e "${FMT_RED}Failed to update following packages:" \
			"${FMT_NF}"
		while read -r pkg; do
			echo -e "${FMT_RED}    $pkg${FMT_NF}"
		done <"$STATUS_DIR/update-failed"
		echo ""
	fi

	if [[ -f "$STATUS_DIR/unexpected-failure" ]]; then
		echo -e "${FMT_RED}Unexpected failure when updating following" \
			"packages:${FMT_NF}"
		while read -r pkg; do
			echo -e "${FMT_RED}    $pkg${FMT_NF}"
		done <"$STATUS_DIR/unexpected-failure"
		echo ""
	fi

	echo_bold "___________________________________________"
	echo ""
}

function report_status_all() {
	report_status
	without_colors report_status >"$STATUS_DIR/report"
}

#
# This script will attempt to update every package. It will continue running
# for all the packages even if update fails for a package.
#
# The steps for updating each package are the following:
#  1) Run "buildpkg.sh -u <pkg>" to update upstream, then attempt merge and
#     build. If everything succeeded buildpkg.sh will return success. If only
#     some parts succeeded, buildpkg.sh will record status in the package's
#     WORKDIR.
#  2) If upstream was updated, push the update to the package repository.
#  3) If a merge with upstream was necessary and we succesfully performed it,
#     push the merge to the package repository.
#

if [[ -n "$UPDATE_PACKAGE_NAME" ]]; then
	echo_bold "Updating only package '$UPDATE_PACKAGE_NAME' as" \
		"UPDATE_PACKAGE_NAME is set"
	logmust check_package_exists "$UPDATE_PACKAGE_NAME"
	PACKAGES=("$UPDATE_PACKAGE_NAME")
	echo_bold "auto-mege-blacklist.pkgs is ignored"
	NO_MERGE_PACKAGES=()
else
	logmust read_package_list "$pkg_list_file"
	PACKAGES=("${_RET_LIST[@]}")
	logmust read_package_list "$TOP/package-lists/auto-merge-blacklist.pkgs"
	NO_MERGE_PACKAGES=("${_RET_LIST[@]}")
fi

for pkg in "${PACKAGES[@]}"; do
	echo ""
	echo_bold "Updating package $pkg."

	logmust load_package_config "$pkg"

	#
	# If the "-r" option is specified, this indicates that we're
	# updating packages for a specific release. For releases, we
	# only want to update packages that are pulling from Ubuntu's
	# source packages. Thus, we skip any packages here, that do not
	# update from a source package.
	#
	$release && [[ -z "$UPSTREAM_SOURCE_PACKAGE" ]] && continue

	WORKDIR="$TOP/packages/$pkg/tmp"
	unexpected_failure=false

	flags=""
	for no_merge_pkg in "${NO_MERGE_PACKAGES[@]}"; do
		if [[ "$pkg" == "$no_merge_pkg" ]]; then
			echo_bold "Auto-merge disabled for $pkg as package" \
				"is in auto-merge-blacklist.pkgs"
			flags="-M"
		fi
	done

	echo "Running: ./buildpkg.sh $flags -u $pkg"
	if ./buildpkg.sh -u $flags "$pkg"; then
		buildpkg_success=true
	else
		if [[ -f "$WORKDIR/updating-upstream" ]]; then
			echo_error "Failed to update upstream for $pkg"
		elif [[ -f "$WORKDIR/merging" ]]; then
			echo_error "Failed merge with upstream for $pkg"
		elif [[ -f "$WORKDIR/building" ]]; then
			echo_error "Failed build of $pkg after merge"
		else
			die "Unexpected failure of buildpkg.sh for $pkg"
		fi

		echo_error "buildpkg.sh failed."
		echo "$pkg" >>"$STATUS_DIR/update-failed"
		buildpkg_success=false
		record_failure
	fi

	if [[ -f "$WORKDIR/upstream-updated" ]]; then
		#
		# We push to upstream if it was updated, even if the merge with
		# our repo or the build has failed. This way developers can
		# manually perform the merge without having to update upstream
		# themselves.
		#
		$dry_run && flags="-n" || flags=""
		echo "Running: ./push-updates.sh -u -y $flags $pkg"
		if ./push-updates.sh -u -y $flags "$pkg"; then
			echo "$pkg" >>"$STATUS_DIR/upstream-pushed"
		else
			echo_error "Failed to push upstream changes for $pkg."
			unexpected_failure=true
			record_failure
		fi
	fi

	if ! $unexpected_failure && [[ -f "$WORKDIR/repo-updated" ]]; then
		# sanity check
		$buildpkg_success ||
			die "Repo should not be updated when buildpkg.sh failed"

		$dry_run && flags="-n" || flags=""
		echo "Running ./push-updates.sh -m -y $flags $pkg"
		if ./push-updates.sh -m -y $flags "$pkg"; then
			echo "$pkg" >>"$STATUS_DIR/merge-pushed"
		else
			echo_error "Failed to push merge for $pkg."
			unexpected_failure=true
			record_failure
		fi
	fi

	if $unexpected_failure; then
		echo "$pkg" >>"$STATUS_DIR/unexpected-failure"
	fi
	echo_bold "===================================================================="
done

trap - EXIT

report_status_all

$FAILURE && exit 1 || exit 0
