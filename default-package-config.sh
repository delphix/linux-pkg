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
# shellcheck disable=SC2034

#
# This file defines a default config for a package and is sourced by
# lib/common.sh->load_package_config() before sourcing the config.sh
# for the specified package. Any hooks and variables defined here can
# be overriden.
#

function fetch() {
	logmust fetch_repo_from_git
}

function store_build_info() {
	if [[ -d "$WORKDIR/repo/.git" ]]; then
		logmust store_git_info
	else
		echo "No build info available" >"$WORKDIR/build_info"
	fi
}

function post_build_checks() {

	# This function checks for SKIP_COPYRIGHTS_CHECK flag
	# in config.sh file of each package. If the flag is
	# present and is set to 'true', the check will be skipped.
	# The license information for the platform packages are
	# generated based on Ubuntu package convention and are
	# picked from copyright file under /debian folder. As a
	# part of the check we look for existance of the file in
	# each package.
	if [[ "$SKIP_COPYRIGHTS_CHECK" != true ]]; then
		echo "Start copyright check"
		file_count=$(find "$WORKDIR/repo" | grep 'debian/copyright' -c)

		if [[ ! $file_count -gt 0 ]]; then
			logmust die "Copyright file is missing in the package repository."
		fi
	fi
}
