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

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
TOP="$PWD"
source "$TOP/lib/common.sh"

ALL_OUTPUT_FIELDS=(name git-url dependencies can-update)

function usage() {
	local output_fields="${ALL_OUTPUT_FIELDS[*]}"
	(
		[[ $# != 0 ]] && (
			echo "$(basename "$0"): $*"
			echo
		)
		echo "Usage:"
		echo "    $(basename "$0") single [-o FIELDS] PACKAGE"
		echo "    $(basename "$0") list [-o FIELDS] LIST_FILE"
		echo ""
		echo "    Either display information about a single package"
		echo "    or a package list located under the package-lists"
		echo "    directory. You can also pass one of the following"
		echo "    special values to the list command:"
		echo "      all: displays all known packages"
		echo "      appliance: displays all packages used by appliance"
		echo "      linux-kernel: displays all linux kernel packages"
		echo ""
		echo "    -o  Comma delimited output fields."
		echo "        Possible values: ${output_fields// /, }."
		echo "        By default, only print package name."
		echo "    -h  Show this help."
	) >&2
	exit 2
}

function print_package() {
	local pkgname="$1"
	local outarray=()
	local deps_array=()
	#
	# Run this in a sub-shell so that functions and variables sourced from
	# load_package_config() are reset each time we load a new package.
	#
	(
		local field
		local dep
		load_package_config "$pkgname" >/dev/null
		for field in "${ACTIVE_OUTPUT_FIELDS[@]}"; do
			case "$field" in
			name) outarray+=("$pkgname") ;;
			git-url) outarray+=("${DEFAULT_PACKAGE_GIT_URL:-none}") ;;
			dependencies)
				for dep in $PACKAGE_DEPENDENCIES; do
					check_package_exists "$dep"
					deps_array+=("$dep")
				done
				if [[ ${#deps_array[@]} -eq 0 ]]; then
					outarray+=(none)
				else
					# comma-separated list of dependencies
					outarray+=("$(
						IFS=,
						echo "${deps_array[*]}"
					)")
				fi
				;;
			can-update)
				type -t "update_upstream" >/dev/null &&
					outarray+=(true) || outarray+=(false)
				;;
			esac
		done
		IFS=$'\t'
		echo "${outarray[*]}"
	) || die "Failed to print info for package '$pkgname'"
}

function query_list() {
	local list="$1"
	local dups

	# Package list is returned in _RET_LIST by the functions below.
	# Note that we should always redirect stdout to /dev/null when
	# calling lib/common.sh functions as they may generate unwanted
	# debug output.
	if [[ $list == all ]]; then
		list_all_packages >/dev/null
	elif [[ $list == appliance ]]; then
		# concatenate kernel and userland packages
		read_package_list "$TOP/package-lists/build/kernel-modules.pkgs" >/dev/null
		local kernel_list=("${_RET_LIST[@]}")
		list_linux_kernel_packages >/dev/null
		kernel_list+=("${_RET_LIST[@]}")
		read_package_list "$TOP/package-lists/build/main.pkgs" >/dev/null
		_RET_LIST+=("${kernel_list[@]}")
		# check that there are no duplicates
		dups=$(printf '%s\n' "${_RET_LIST[@]}" | sort | uniq -d)
		[[ -z $dups ]] || die "Some apliance packages appear in both" \
			"build/kernel.pkgs and build/userland.pkgs:\\n${dups}"
	elif [[ $list == linux-kernel ]]; then
		list_linux_kernel_packages >/dev/null
	else
		read_package_list "$TOP/package-lists/${list}" >/dev/null
	fi
}

function do_list() {
	local list="$1"
	local pkgname

	query_list "$list"
	for pkgname in "${_RET_LIST[@]}"; do
		print_package "$pkgname"
	done
}

function do_single() {
	local pkgname="$1"
	[[ -n $pkgname ]] || usage "missing argument for pkgname"

	check_package_exists "$pkgname" >/dev/null
	print_package "$pkgname"
}

case "$1" in
list) target=do_list ;;
single) target=do_single ;;
*) usage >&2 ;;
esac
shift

opt_o=""
while getopts ':ho:' c; do
	case "$c" in
	o)
		[[ -z $opt_o ]] || usage "-o appears more than once"
		opt_o="$OPTARG"
		;;
	h) usage ;;
	*) usage "illegal option -- $OPTARG" ;;
	esac
done
shift $((OPTIND - 1))

#
# Parse list of fields to output
#
if [[ -n $opt_o ]]; then
	ACTIVE_OUTPUT_FIELDS=()
	for field in $(echo "$opt_o" | tr ',' ' '); do
		for f in "${ALL_OUTPUT_FIELDS[@]}"; do
			[[ $f == "$field" ]] && break
		done
		if [[ $f == "$field" ]]; then
			ACTIVE_OUTPUT_FIELDS+=("$field")
		else
			usage "invalid output field '$field'"
		fi
	done
else
	# By default, only print package name
	ACTIVE_OUTPUT_FIELDS=(name)
fi

$target "$@"
