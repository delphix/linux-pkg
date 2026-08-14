#!/usr/bin/env bash
#
# Copyright 2026 Delphix
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
# TODO(CP-13600): points at a personal dev repo while this is prototyped --
# the author has no delphix/ org repo-creation rights. Swap to
# https://github.com/delphix/delphix-syft.git once that repo exists.
#
DEFAULT_PACKAGE_GIT_URL="https://github.com/justsanjeev/delphix-syft.git"

function build() {
	logmust mkdir -p "$WORKDIR/repo"
	logmust dpkg_buildpackage_default
}
