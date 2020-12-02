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
	echo "  Push code that was previously merged. sync-with-upstream.sh must"
	echo "  already have been run. Before pushing the merge, it will first"
	echo "  check that the target branch has not been modified since the merge"
	echo "  was performed, and fail if it did."
	echo ""
	echo "  As a safety check, DRYRUN environment variable must be set to"
	echo "  'false'."
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

if [[ "$DRYRUN" != 'false' ]]; then
	die "DRYRUN environment variable must be set to 'false'."
fi

logmust check_package_exists "$PACKAGE"

DEFAULT_REVISION="${DEFAULT_REVISION:-$(default_revision)}"
logmust determine_default_git_branch
logmust load_package_config "$PACKAGE"

if [[ ! -d "$WORKDIR/repo" ]]; then
	die "$WORKDIR/repo doesn't exist, have you run sync-with-upstream for" \
		"package $PACKAGE?"
fi
logmust cd "$WORKDIR/repo"

#
# Check that the target branch has not been modified in the meanwhile.
# This is especially important for repositories that have
# FORCE_PUSH_ON_UPDATE set to true, such as the linux kernel. The file
# WORKDIR/merge-commit-outdated will be created if that is the case to let
# the caller know this is the reason the push failed.
#
set -o pipefail
echo "Running: git rev-parse refs/heads/repo-HEAD-saved"
saved_ref=$(git rev-parse refs/heads/repo-HEAD-saved) ||
	die "Failed to read local ref refs/heads/repo-HEAD-saved"
echo "Running: git ls-remote $DEFAULT_PACKAGE_GIT_URL refs/heads/$DEFAULT_GIT_BRANCH"
remote_ref=$(git ls-remote "$DEFAULT_PACKAGE_GIT_URL" "refs/heads/$DEFAULT_GIT_BRANCH" |
	awk '{print $1}') ||
	die "Failed to read remote ref refs/heads/$DEFAULT_GIT_BRANCH"
set +o pipefail

if [[ "$saved_ref" != "$remote_ref" ]]; then
	touch "$WORKDIR/merge-commit-outdated"
	die "Remote branch $DEFAULT_GIT_BRANCH was modified while merge" \
		"testing was being performed. Previous hash: $saved_ref," \
		"new hash: $remote_ref. Not pushing merge."
fi

force_push="${FORCE_PUSH_ON_UPDATE:-false}"
logmust push_to_remote "refs/heads/repo-HEAD" \
	"refs/heads/$DEFAULT_GIT_BRANCH" "$force_push"

echo_success "Merge pushed successfully for package $PACKAGE to remote" \
	"branch $DEFAULT_GIT_BRANCH"
