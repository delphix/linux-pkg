#!/bin/bash
#
# Copyright 2018 Delphix
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
	echo "  Jenkins. It calls either buildall.sh or buildpkg.sh depending"
	echo "  on the value of BUILD_ALL."
	echo ""
	exit 2
}

#
# BUILDER_CUSTOM_ENV is meant to be used to pass GIT_URL, GIT_BRANCH, VERSION
# and REVISION values for specific packages, by setting <PACKAGE>_<VAR>
# variables. See get_package_config_from_env() in lib/common.sh for more info.
#
# e.g.:
# CLOUD_INIT_GIT_BRANCH=feature-branch-1
# CONNSTAT_GIT_URL=github.com/connstat-developer/connstat.git
#
function parse_custom_env() {
	local allowed_vars=()
	local prefix
	local pkg

	#
	# Build a list of allowed custom environment variables
	#
	logmust cd "$TOP/packages/"
	for pkg in *; do
		get_package_prefix "$pkg"
		prefix="$_RET"
		for suffix in GIT_URL GIT_BRANCH VERSION REVISION; do
			allowed_vars+=("${prefix}_${suffix}")
		done
	done

	#
	# Parse each line in the custom env and check if it matches any of
	# the allowed variables.
	#
	local found
	while IFS= read -r line; do
		# trim whitespace
		line=$(echo "$line" | sed 's/^\s*//;s/\s*$//')
		[[ -z "$line" ]] && continue

		if [[ "$line" =~ ([^=]+)=.* ]]; then
			var="${BASH_REMATCH[1]}"
			found=false
			for allowed_var in "${allowed_vars[@]}"; do
				if [[ "$allowed_var" == "$var" ]]; then
					found=true
					break
				fi
			done
			$found || die "Parsing BUILDER_CUSTOM_ENV: '$var'" \
				"is not an allowed environment variable."
			logmust export "$line"
		else
			die "Parsing BUILDER_CUSTOM_ENV: invalid entry '$line'"
		fi
	done < <(printf '%s\n' "$BUILDER_CUSTOM_ENV")
}

[[ $# -eq 0 ]] || usage "takes no arguments." >&2

if [[ -n "$BUILDER_CUSTOM_ENV" ]]; then
	logmust parse_custom_env
fi

BUILD_ALL=${BUILD_ALL:-"true"}

if [[ -n "$SINGLE_PACKAGE_NAME" ]]; then
	logmust check_package_exists "$SINGLE_PACKAGE_NAME"
	#
	# The following env parameters are propagated from jenkins:
	#
	#   SINGLE_PACKAGE_GIT_URL, SINGLE_PACKAGE_GIT_BRANCH,
	#   SINGLE_PACKAGE_VERSION, SINGLE_PACKAGE_REVISION
	#
	# We make sure those variables are applied to package
	# SINGLE_PACKAGE_NAME by copying values of SINGLE_PACKAGE_<VAR> into
	# <prefix>_<VAR>. See comment for parse_custom_env() above.
	#
	logmust get_package_prefix "$SINGLE_PACKAGE_NAME"
	prefix="$_RET"
	echo_bold "Setting ${prefix}_ variables since" \
		"SINGLE_PACKAGE_NAME=$SINGLE_PACKAGE_NAME ..."
	if [[ -n "$SINGLE_PACKAGE_GIT_URL" ]]; then
		var="${prefix}_GIT_URL"
		logmust export "${var}=$SINGLE_PACKAGE_GIT_URL"
	fi
	if [[ -n "$SINGLE_PACKAGE_GIT_BRANCH" ]]; then
		var="${prefix}_GIT_BRANCH"
		logmust export "${var}=$SINGLE_PACKAGE_GIT_BRANCH"
	fi
	if [[ -n "$SINGLE_PACKAGE_VERSION" ]]; then
		var="${prefix}_VERSION"
		logmust export "${var}=$SINGLE_PACKAGE_VERSION"
	fi
	if [[ -n "$SINGLE_PACKAGE_REVISION" ]]; then
		var="${prefix}_REVISION"
		logmust export "${var}=$SINGLE_PACKAGE_REVISION"
	fi
fi

logmust cd "$TOP"

#
# If BUILD_ALL is false, then only build package SINGLE_PACKAGE_NAME,
# otherwise build all pacakges.
#
if [[ "$BUILD_ALL" == "false" ]]; then
	[[ -n "$SINGLE_PACKAGE_NAME" ]] || die "SINGLE_PACKAGE_NAME must be" \
		"set when BUILD_ALL=false"

	build_flags=""
	if [[ "$CHECKSTYLE" == "true" ]]; then
		build_flags="${build_flags} -c"
	fi

	echo_bold "BUILD_ALL=FALSE so only building one package!"
	logmust make clean
	# shellcheck disable=SC2086
	logmust ./buildpkg.sh $build_flags "$SINGLE_PACKAGE_NAME"
	# Jenkins expects artifacts to be in topmost directory
	logmust mkdir artifacts
	logmust mv "packages/$SINGLE_PACKAGE_NAME/tmp/artifacts"/* artifacts/
elif [[ "$BUILD_ALL" == "true" ]]; then
	echo_bold "BUILD_ALL=TRUE so building all packages!"
	logmust ./buildall.sh
else
	die "'$BUILD_ALL' is an invalid value for BUILD_ALL." \
		"Expecting true/false"
fi
