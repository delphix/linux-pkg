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

#
# We currently support getting the linux kernel from 3 different sources:
#  1. Building it from code: see config.delphix.sh
#  2. Dowloading from apt: see config.archive.sh
#  3. Pre-built kernel stored in artifactory: see config.prebuilt.sh
#

linux_package_source="${LINUX_KERNEL_PACKAGE_SOURCE:-$DEFAULT_LINUX_KERNEL_PACKAGE_SOURCE}"
case "$linux_package_source" in
delphix | archive | prebuilt)
	logmust source "${BASH_SOURCE%/*}/config.${linux_package_source}.sh"
	;;
default)
	die "invalid linux-kernel package source '$linux_package_source'"
	;;
esac
