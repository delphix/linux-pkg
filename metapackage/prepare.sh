#!/bin/bash -e
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
# shellcheck disable=SC2016

TOP="$(git rev-parse --show-toplevel)"
source "$TOP/lib/common.sh"

METADIR="$TOP/metapackage/"

logmust read_package_list "$TOP/package-lists/buildall.pkgs"
ALL_PACKAGES=("${_RET_LIST[@]}")
logmust read_package_list "$TOP/package-lists/metapackage.pkgs"
DEPENDS_PACKAGES=("${_RET_LIST[@]}")

shopt -s failglob
for pkg in "${DEPENDS_PACKAGES[@]}"; do
	cd "$TOP/packages/${pkg}/tmp/artifacts" ||
		die "$TOP/packages/${pkg}/tmp/artifacts missing." \
			"Did you build package $pkg?"

	for deb in *.deb; do
		dpkg-deb --show --showformat='${Package} (=${Version}), ' "$deb"
	done
done | sed 's/, $//' >"$METADIR/depends"

logmust mkdir -p "$METADIR/etc"

INFO_FILE="$METADIR/etc/delphix-extra-build-info"
LINUX_PKG_HASH="$(git rev-parse HEAD)" || die "git rev-parse HEAD failed"

#
# LINUX_PKG_GIT_URL & LINUX_PKG_GIT_BRANCH are passed by Jenkins
#
cat <<-EOF >"$INFO_FILE"
	Linux-pkg Package Framework:
	Git hash: $LINUX_PKG_HASH
	Git repo: ${LINUX_PKG_GIT_URL:-unknown}
	Git branch: ${LINUX_PKG_GIT_BRANCH:-unknown}
EOF

echo "" >>"$INFO_FILE"

cd "$TOP/packages"
for pkg in "${ALL_PACKAGES[@]}"; do
	if [[ -f "${pkg}/tmp/build_info" ]]; then
		echo "Package $pkg:"
		cat "${pkg}/tmp/build_info"
		echo ""
	fi
done >>"$INFO_FILE"
