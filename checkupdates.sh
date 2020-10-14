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
	echo "  This script checks if upstream updates are available for the"
	echo "  target package. It returns succesfully whether or not there are"
	echo "  updates available. If either the upstream can be updated or the"
	echo "  active branch can be merged with a previously updated upstream"
	echo "  then the file workdir/update-available will be created."
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

#
# If the script is called manually, we set it here.
#
DEFAULT_REVISION="${DEFAULT_REVISION:-$(default_revision)}"
logmust determine_default_git_branch

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
logmust is_merge_needed
merge_needed="$_RET"
$merge_needed && echo "Merge with upstream is needed."

echo ""

if [[ -f "$WORKDIR/upstream-updated" ]] || $merge_needed; then
	logmust touch "$WORKDIR/update-available"
	echo_success "Package $PACKAGE has updates available."
else
	echo_bold "Package $PACKAGE is already up-to-date."
fi
