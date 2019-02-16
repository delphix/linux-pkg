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
# This file is a reference config.sh to use when adding a new package.
#

#
# Git URL for where your package is to be found
#
DEFAULT_PACKAGE_GIT_URL="https://github.com/delphix/omnibus-td-agent.git"

#
# A version for the package must be provided in DEFAULT_PACKAGE_VERSION.
# For an original Delphix package, the value for the version is not important,
# so you can set it to anything (e.g. 1.0.0).
# For a third-party package, this should match the version of the upstream
# package. Note that an alternative is to leave DEFAULT_PACKAGE_VERSION
# undefined and to programatically obtain PACKAGE_VERSION from the package's
# source code.
#
# We're customizing td-agent version 3.3.0
DEFAULT_PACKAGE_VERSION=3.3.0

#
# If you are adding a third-package from an upstream git project, uncomment
# and fill the two lines below.
#
UPSTREAM_GIT_URL=https://github.com/treasure-data/omnibus-td-agent.git
UPSTREAM_GIT_BRANCH=master

#
# If you are adding a third-party package based on an existing Ubuntu package,
# find the source package and fill the line below. Hint: the source package
# name is either the same as the package or will appear under "Source:" when
# running "apt show <package>"
#
#UPSTREAM_SOURCE_PACKAGE=awesome-third-party-package

#
# Install build dependencies for the package.
# (Optional function)
#
function prepare() {
	#
	# Build pre-requisites (ruby2.5, bundler and binstubs)
	#
	logmust install_pkgs ruby2.5 bundler
}

#
# Build the package.
# (Mandatory function)
#
function build() {
	#
	# Download dependent gems
	#
	logmust cd "$WORKDIR/repo"
	# Ensure all required gems are installed
	logmust bundle install --binstubs
	# Download dependent gems using downloader
	logmust bin/gem_downloader core_gems.rb
	logmust bin/gem_downloader delphix_plugin_gems.rb
	# Create required directory and add permission
	logmust sudo mkdir -p /opt/td-agent /var/cache/omnibus
	logmust sudo chown ubuntu /opt/td-agent
	logmust sudo chown ubuntu /var/cache/omnibus
	# now kick off the build
	logmust bin/omnibus build td-agent3
	# copy to artifacts
	logmust cp "$WORKDIR"/repo/pkg/*.deb "$WORKDIR/artifacts/"
	logmust store_git_info
}

#
# Hook to fetch upstream package changes and merge into our tree.
# (Optional function, only applies to third-party packages)
#
function update_upstream() {
	logmust update_upstream_from_git
}
