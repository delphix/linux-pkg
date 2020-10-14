#!/bin/bash
#
# Copyright 2020 Delphix
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

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") <package>"
	echo ""
	echo "  Update the upstreams branch for the package and attempt to merge"
	echo "  active branch with the upstream. If merge succeeds, push result"
	echo "  to branch projects/auto-update/<branch>/merging."
	echo ""
	echo "  This script requires the DRYRUN environment variable to be set to"
	echo "  either 'true' or 'false', else it will refuse to push anything"
	echo "  upstream. If DRYRUN is set to true, the upstreams/<branch> branch"
	echo "  will not be pushed and the resulting merge will be pushed to"
	echo "  projects/auto-update/<branch>/merging-dryrun instead."
	echo ""
	echo "    -h  display this message and exit."
	echo ""
	exit 2
}

while getopts ':h' c; do
	case "$c" in
	h) usage >&2 ;;
	*) usage "illegal option -- $OPTARG" >&2 ;;
	esac
done
shift $((OPTIND - 1))
[[ $# -lt 1 ]] && usage "package argument missing" >&2
[[ $# -gt 1 ]] && usage "too many arguments" >&2
PACKAGE=$1

logmust check_package_exists "$PACKAGE"

logmust determine_default_git_branch

merging_ref="refs/heads/projects/auto-update/$DEFAULT_GIT_BRANCH/merging"
if [[ "$DRYRUN" == 'true' ]]; then
	merging_ref="${merging_ref}-dryrun"
elif [[ "$DRYRUN" != 'false' ]]; then
	die "DRYRUN environment variable must be set to 'true' or 'false'."
fi

logmust load_package_config "$PACKAGE"
logmust create_workdir

#
# Set DO_UPDATE_PACKAGE to true so that the fetch stage fetches both the
# target branch as well as the upstream branch.
#
export DO_UPDATE_PACKAGE=true
logmust cd "$WORKDIR"
stage fetch

stage update_upstream
force_push="${FORCE_PUSH_ON_UPDATE:-false}"

if [[ -f "$WORKDIR/upstream-updated" ]]; then
	if $DRYRUN; then
		echo_success "Upstream updated for package $PACKAGE" \
			"but not pushed because this is a dry-run."
	else
		logmust push_to_remote "refs/heads/upstream-HEAD" \
			"refs/heads/upstreams/$DEFAULT_GIT_BRANCH" "$force_push"

		if [[ -f "$WORKDIR/upstream-tag" ]]; then
			echo "Note: also pushing tag from upstream."
			upstream_tag="$(cat "$WORKDIR/upstream-tag")"
			[[ -z "$upstream_tag" ]] &&
				die "tag missing in $WORKDIR/upstream-tag"
			logmust push_to_remote "$upstream_tag" \
				"$upstream_tag" false
		fi

		echo_success "Upstream updated for package $PACKAGE."
	fi
fi

logmust cd "$WORKDIR/repo"

stage merge_with_upstream
if [[ -f "$WORKDIR/repo-updated" ]]; then
	logmust push_to_remote "refs/heads/repo-HEAD" "$merging_ref" true
	echo_success "Pushed merge commit of package $PACKAGE to ref" \
		"$merging_ref of $DEFAULT_PACKAGE_GIT_URL for testing."
else
	echo_bold "Package is already up-to-date."
fi
