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
# shellcheck disable=SC2034

DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/omnibus-td-agent.git"

# We're customizing td-agent version 3.3.0
DEFAULT_PACKAGE_VERSION=3.3.0

UPSTREAM_GIT_URL=https://github.com/treasure-data/omnibus-td-agent.git
UPSTREAM_GIT_BRANCH=master

function prepare() {
	#
	# Build pre-requisites (ruby2.5, bundler and binstubs)
	#
	logmust install_pkgs ruby2.5 bundler
}

function build() {
	logmust cd "$WORKDIR/repo"
	# Ensure all required gems are installed
	logmust bundle install --binstubs
	# Download dependent gems using downloader
	logmust bin/gem_downloader core_gems.rb
	logmust bin/gem_downloader delphix_plugin_gems.rb
	# Create directories needed by the build and add permission
	logmust sudo mkdir -p /opt/td-agent /var/cache/omnibus
	logmust sudo chown ubuntu /opt/td-agent
	logmust sudo chown ubuntu /var/cache/omnibus
	# now kick off the build
	logmust bin/omnibus build td-agent3
	# copy to artifacts
	logmust cp "$WORKDIR"/repo/pkg/*.deb "$WORKDIR/artifacts/"
	logmust store_git_info
}

function update_upstream() {
	logmust update_upstream_from_git
}
