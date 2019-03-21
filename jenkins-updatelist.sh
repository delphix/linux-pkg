#!/bin/bash
#
# Copyright 2019 Delphix
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
	echo "Usage: $(basename "$0")"
	echo ""
	echo "  This is a wrapper script that is meant to be called from"
	echo "  Jenkins. It consumes and processes environment variables"
	echo "  passed from Jenkins and call 'updatelist.sh <UPDATE_LIST>'."
	echo ""
	exit 2
}

[[ $# -eq 0 ]] || usage "takes no arguments." >&2

#
# Validate the list of packages to update and make sure the GIT_DRY_RUN
# environment variable is passed.
#
check_env UPDATE_LIST GIT_DRY_RUN
logmust get_package_list_file "update" "$UPDATE_LIST"

if [[ "$GIT_DRY_RUN" == "false" ]]; then
	dry_run=''
else
	dry_run='-n'
fi

logmust cd "$TOP"
logmust ./setup.sh
logmust ./updatelist.sh $dry_run "$UPDATE_LIST"
