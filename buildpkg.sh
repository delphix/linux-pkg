#!/usr/bin/env bash
#
# Copyright 2018, 2021 Delphix
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
ORIGINAL_ARGS=("$@")

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0") [-ch] [-g pkg_git_url]"
	echo "         [-b pkg_git_branch] [-r pkg_revision]"
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
	echo "    -r  override default revision for package."
	echo "    -h  display this message and exit."
	echo "    -l  use locally-built dependencies instead of s3 versions."
	echo "    -S  start an interactive shell in the build container."
	echo ""
	exit 2
}

unset PARAM_PACKAGE_GIT_URL
unset PARAM_PACKAGE_GIT_BRANCH
unset PARAM_PACKAGE_REVISION

do_checkstyle=false
open_shell=false
source="s3"
while getopts ':b:cg:hlr:S' c; do
	case "$c" in
	g) export PARAM_PACKAGE_GIT_URL="$OPTARG" ;;
	b) export PARAM_PACKAGE_GIT_BRANCH="$OPTARG" ;;
	r) export PARAM_PACKAGE_REVISION="$OPTARG" ;;
	c) do_checkstyle=true ;;
	h) usage >&2 ;;
	l) source="local" ;;
	S) open_shell=true ;;
	*) usage "illegal option -- $OPTARG" >&2 ;;
	esac
done
shift $((OPTIND - 1))
[[ $# -lt 1 ]] && usage "package argument missing" >&2
[[ $# -gt 1 ]] && usage "too many arguments" >&2
PACKAGE=$1

#
# Checked here rather than after the re-exec so that a mistyped package name
# fails immediately, instead of after bootstrapping a container image and
# provisioning it, which is minutes of work for a name that was never going to
# resolve. Checked again inside the container by load_package_config().
#
logmust check_package_exists "$PACKAGE"

#
# Whether this package's build needs the host's docker socket bound in has to be
# known before the container is started; see package_needs_docker().
#
logmust package_needs_docker "$PACKAGE"
export PACKAGE_NEEDS_DOCKER="$_RET"

if $open_shell; then
	logmust load_package_config "$PACKAGE"
	logmust container_shell
fi

#
# Deliberately not logmust: this script's arguments can carry a credential
# ('-g https://<token>@github.com/...'), and logmust would echo them verbatim
# into the build log. container_reexec() logs its own command line with any such
# URL masked, the way git_fetch_helper() and push_to_remote() do (lib/common.sh),
# and it exits with the container's status rather than returning a failure for
# logmust to catch.
#
container_reexec "./$(basename "$0")" "${ORIGINAL_ARGS[@]}"
logmust check_running_system
logmust run_setup_if_needed

check_env DEFAULT_GIT_BRANCH

#
# DEFAULT_REVISION & DEFAULT_GIT_BRANCH will be set if called from buildlist.sh.
# If the script is called manually, we set it here.
#
DEFAULT_REVISION="${DEFAULT_REVISION:-$(delphix_revision)}"

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
stage fetch_dependencies $source

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
