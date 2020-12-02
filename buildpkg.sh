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

TOP="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$TOP/lib/common.sh"

logmust check_running_system

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") [-ch] [-g pkg_git_url]"
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
	echo "    -g  override default git url for the package."
	echo "    -b  override default git branch for the package."
	echo "    -c  also run package's checkstyle hook."
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

do_checkstyle=false
while getopts ':b:cg:hr:v:' c; do
	case "$c" in
	g) export PARAM_PACKAGE_GIT_URL="$OPTARG" ;;
	b) export PARAM_PACKAGE_GIT_BRANCH="$OPTARG" ;;
	v) export PARAM_PACKAGE_VERSION="$OPTARG" ;;
	r) export PARAM_PACKAGE_REVISION="$OPTARG" ;;
	c) do_checkstyle=true ;;
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
logmust create_workdir
logmust mkdir "$WORKDIR/artifacts"

logmust cd "$WORKDIR"
stage fetch

logmust cd "$WORKDIR"
stage fetch_dependencies

logmust cd "$WORKDIR"
stage prepare

if $do_checkstyle; then
	logmust cd "$WORKDIR"
	stage checkstyle
fi

logmust cd "$WORKDIR"
stage build

logmust cd "$WORKDIR"
stage store_build_info

logmust cd "$WORKDIR"
stage post_build_checks

echo_success "Package $PACKAGE has been built successfully."
echo "Build products are in $WORKDIR/artifacts"
echo ""
