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

function usage() {
	[[ $# != 0 ]] && echo "$(basename "$0"): $*"
	echo "Usage: $(basename "$0")"
	echo ""
	echo "  This is a wrapper script that is meant to be called from"
	echo "  Jenkins. It consumes and processes environment variables"
	echo "  passed from Jenkins and call 'buildlist.sh <BUILD_LIST>'."
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
	# Build a list of allowed custom environment variables.
	#
	for pkg in "${PACKAGES[@]}"; do
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

#
# Validate the list of packages to build.
#
check_env BUILD_LIST
logmust get_package_list_file "build" "$BUILD_LIST"
pkg_list_file="$_RET"
logmust read_package_list "$pkg_list_file"
PACKAGES=("${_RET_LIST[@]}")

if [[ -n "$BUILDER_CUSTOM_ENV" ]]; then
	logmust parse_custom_env
fi

if [[ -n "$SINGLE_PACKAGE_NAME" ]]; then
	logmust check_package_exists "$SINGLE_PACKAGE_NAME"
	#
	# Make sure that the package is actually part of the BUILD_LIST.
	#
	found=false
	for pkg in "${PACKAGES[@]}"; do
		if [[ "$pkg" == "$SINGLE_PACKAGE_NAME" ]]; then
			found=true
			break
		fi
	done
	$found || die "Package SINGLE_PACKAGE_NAME=$SINGLE_PACKAGE_NAME is not" \
		"in package list '$BUILD_LIST'"

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
logmust ./setup.sh
logmust ./buildlist.sh "$BUILD_LIST"
