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
# Package builds run inside a container whose root filesystem is bootstrapped
# from the Ubuntu suite named by UBUNTU_DISTRIBUTION. This decouples the suite
# being built from the suite the build host runs, which is what allows a
# buildserver running one LTS release to build packages for the next one.
#

#
# Home directory of the user that resources/Dockerfile.build-container creates,
# which is what $HOME resolves to inside the build container. The host user's
# home is a different path and is not mounted, so anything that has to be
# reachable through '~' inside the container has to land here.
#
CONTAINER_HOME="/home/delphix"

#
# Name of the image used to build packages for the current suite.
# Sets _RET.
#
function container_image_tag() {
	check_env UBUNTU_DISTRIBUTION
	_RET="linux-pkg-build:${UBUNTU_DISTRIBUTION}"
}

#
# File that resources/Dockerfile.build-container bakes into the build image, and
# whose presence is what identifies a process as running inside that container.
#
# The image is asked rather than the environment because this answer decides real
# work, not just cosmetics: setup.sh reads it to choose between preparing a
# container image and configuring the system it is running on directly. An
# environment variable would let anything on the host claim to be in a container
# just by setting it, and a host that made that claim would get its own
# /etc/apt/sources.list rewritten and build packages installed onto it -- exactly
# what check_host_is_disposable() below exists to prevent. A file baked into the
# image cannot be produced by setting a variable, and forging it needs root on
# the host.
#
CONTAINER_MARKER_FILE="/etc/linux-pkg-build-container"

#
# True when the current process is already running inside the build container.
#
function running_in_container() {
	[[ -f "$CONTAINER_MARKER_FILE" ]]
}

#
# Refuse to treat this host as disposable unless it is a Delphix buildserver
# image, which is what every real build host is. Guards every path that is about
# to bootstrap a container image or, on the LINUX_PKG_NO_CONTAINER escape hatch,
# run the equivalent setup directly: both do the same irreversible things to
# whatever host runs them (sudo ln -s into /usr/share/debootstrap/scripts, sudo
# mkdir -p under /var/lib, debootstrap, sudo rm -rf, and on the escape hatch,
# rewriting /etc/apt/sources.list and installing packages).
#
# A Delphix image can state what it is, so it is asked directly. Inferring this
# from AWS instance metadata would not work: metadata answers on every AWS
# instance, a developer's own cloud workstation included, so it cannot
# distinguish a buildserver from the machines this is meant to protect. The
# variant can. Both values come from delphix-platform, which ships these two
# commands, and 'internal-buildserver' is the variant its own provisioning uses
# for the buildserver image.
#
# Honors DISABLE_SYSTEM_CHECK, which any host that is not a buildserver image
# needs, a plain Ubuntu AWS instance included.
#
function check_host_is_disposable() {
	local platform variant

	if [[ "$DISABLE_SYSTEM_CHECK" == "true" ]]; then
		return 0
	fi

	#
	# Absence of the commands means this is not a Delphix image at all, which is
	# reported separately from being the wrong one: the two call for different
	# corrections, and 'command not found' from the assignments below would say
	# neither.
	#
	if ! command -v get-appliance-platform >/dev/null ||
		! command -v get-appliance-variant >/dev/null; then
		die "This host is not a Delphix appliance image" \
			"(get-appliance-platform and get-appliance-variant are not" \
			"present); refusing to bootstrap a container image on it. Clone" \
			"the dlpx-internal-buildserver-develop group on DCoA, or set" \
			"DISABLE_SYSTEM_CHECK=true to override, at your own risk."
	fi

	platform=$(get-appliance-platform) ||
		die "Could not determine this host's appliance platform."
	variant=$(get-appliance-variant) ||
		die "Could not determine this host's appliance variant."

	if [[ "$platform" != "aws" ]] || [[ "$variant" != "internal-buildserver" ]]; then
		die "This is a Delphix '$platform'/'$variant' image, not an" \
			"aws/internal-buildserver one; refusing to bootstrap a container" \
			"image on it. Set DISABLE_SYSTEM_CHECK=true to override, at your" \
			"own risk."
	fi
}

#
# Verify the host can build and run the build container. Note that none of these
# prerequisites reference an Ubuntu codename; that independence is the point.
#
function container_check_host_prereqs() {
	command -v docker >/dev/null ||
		die "docker is not installed; it is required to build packages."
	docker info >/dev/null 2>&1 ||
		die "Cannot talk to the docker daemon. Is it running, and is $USER in the docker group?"
	command -v debootstrap >/dev/null ||
		die "debootstrap is not installed; run 'sudo apt-get install debootstrap'."
	sudo -n true 2>/dev/null ||
		die "Passwordless sudo is required to bootstrap the build container's root filesystem."
}

#
# Bootstrap a root filesystem for UBUNTU_DISTRIBUTION from the primary package
# mirror and import it as a docker image, then layer on the few things the build
# needs before setup.sh can run inside: sudo, CA certificates, and a user whose
# uid and gid match the invoking user so that artifacts written to the
# bind-mounted checkout are owned correctly on the host.
#
function container_build_base_image() {
	check_env TOP UBUNTU_DISTRIBUTION
	local tag rootfs tarball mirror script_dir build_root_dir mount_opts
	local dockerfile dockerfile_sha
	local built_mirror built_uid built_gid built_dockerfile_sha

	logmust container_image_tag
	tag="$_RET"

	logmust resolve_mirror_urls
	mirror="$_RET_MIRROR_MAIN"

	dockerfile="$TOP/resources/Dockerfile.build-container"
	dockerfile_sha=$(sha256sum "$dockerfile" | cut -d' ' -f1) ||
		die "Could not hash $dockerfile"

	#
	# The image is a cache, and its tag alone does not identify what is in it.
	# Three things it is keyed on are recorded as labels when it is built, and a
	# difference in any of them has to force a rebuild:
	#
	# - The mirror snapshot its rootfs was bootstrapped from. apt is repointed at
	#   the resolved snapshot on every build, so an image kept past a snapshot
	#   advance builds new code against a frozen debootstrap toolchain, which is
	#   exactly the drift this container was introduced to eliminate, just from
	#   the other side.
	# - The uid and gid it was built for. Those are baked into the image's
	#   /etc/passwd, and the container runs --user <uid>:<gid>, so a second user
	#   on a shared buildserver reusing the first user's image runs as a uid
	#   with no passwd entry, and sudo fails with "you do not exist in the
	#   passwd database".
	# - The Dockerfile that produced it, by content hash. Docker's own layer cache
	#   cannot help here, because this check returns before docker build is ever
	#   reached, so an edit to the Dockerfile would otherwise leave every existing
	#   image indefinitely stale. What makes that more than untidiness is
	#   CONTAINER_MARKER_FILE: the Dockerfile is what puts it in the image, and
	#   running_in_container() is false without it, so an image predating it would
	#   send the in-container setup.sh down the host path, to bootstrap a
	#   container from inside one and fail in check_host_is_disposable() with a
	#   message about the wrong machine entirely.
	#
	if [[ "$LINUX_PKG_REBUILD_IMAGE" != "true" ]] &&
		docker image inspect "$tag" >/dev/null 2>&1; then
		built_mirror=$(docker image inspect --format \
			'{{index .Config.Labels "com.delphix.linux-pkg.mirror-main"}}' "$tag")
		built_uid=$(docker image inspect --format \
			'{{index .Config.Labels "com.delphix.linux-pkg.uid"}}' "$tag")
		built_gid=$(docker image inspect --format \
			'{{index .Config.Labels "com.delphix.linux-pkg.gid"}}' "$tag")
		built_dockerfile_sha=$(docker image inspect --format \
			'{{index .Config.Labels "com.delphix.linux-pkg.dockerfile-sha256"}}' "$tag")

		if [[ "$built_mirror" == "$mirror" ]] &&
			[[ "$built_uid" == "$(id -u)" ]] &&
			[[ "$built_gid" == "$(id -g)" ]] &&
			[[ "$built_dockerfile_sha" == "$dockerfile_sha" ]]; then
			echo "Image $tag already exists and matches the current mirror" \
				"snapshot, user and Dockerfile; skipping bootstrap. Set" \
				"LINUX_PKG_REBUILD_IMAGE=true to force a rebuild."
			return 0
		fi

		echo_bold "Rebuilding image $tag: it was built for mirror" \
			"'${built_mirror:-unknown}', uid/gid" \
			"'${built_uid:-unknown}:${built_gid:-unknown}' and Dockerfile" \
			"'${built_dockerfile_sha:-unknown}', but this build needs mirror" \
			"'$mirror', uid/gid '$(id -u):$(id -g)' and Dockerfile" \
			"'$dockerfile_sha'."
	fi

	#
	# Fail with a specific message when the suite is absent from the mirror,
	# since during an LTS upgrade that means the mirror sync has not completed
	# yet rather than that anything is broken. Checked before the suite ever
	# touches /usr/share below, so a typo can't leave a permanent root-owned
	# symlink behind.
	#
	if ! curl -fsS -o /dev/null "$mirror/dists/$UBUNTU_DISTRIBUTION/Release"; then
		die "Suite '$UBUNTU_DISTRIBUTION' is not present in the package mirror" \
			"at $mirror. If this is a new Ubuntu release, the mirror sync for" \
			"it has not completed; see the linux_package_mirror_sync job."
	fi

	#
	# debootstrap looks up a per-suite script, and ships nothing for a suite
	# released after the version installed here, so an older host cannot
	# bootstrap a newer suite until it is given one. The symlink is that script.
	#
	# It points at 'gutsy' because that is the newest Ubuntu suite debootstrap
	# carries a real script for: Ubuntu 7.10 was the last release to need its
	# own bootstrap logic, and every release since has been compatible with it,
	# so debootstrap ships each new suite as a symlink to gutsy rather than a new
	# script. Every Ubuntu suite present in a current debootstrap is such a
	# symlink (lunar, mantic and noble in 1.0.134ubuntu1), which means this is
	# not an approximation of what the suite needs; it is the same script the
	# distro itself would have shipped for it.
	#
	script_dir="/usr/share/debootstrap/scripts"
	if [[ ! -e "$script_dir/$UBUNTU_DISTRIBUTION" ]]; then
		echo "Teaching debootstrap about $UBUNTU_DISTRIBUTION."
		logmust sudo ln -s gutsy "$script_dir/$UBUNTU_DISTRIBUTION"
	fi

	#
	# The rootfs and its tarball are a few hundred megabytes each -- the imported
	# base images measure 258 MB for noble and 284 MB for resolute -- and both
	# are untracked, so they are kept out of the checkout, which is bind-mounted
	# wholesale into the container. Overridable because debootstrap refuses to
	# install into a target mounted nodev or noexec, and on the buildserver this
	# was developed against, /tmp and /var/tmp are both mounted that way, which
	# rules out the obvious default; whether that holds for every Delphix
	# buildserver was not checked, which is why the two checks below test the
	# directory actually in use rather than assuming anything about it.
	#
	build_root_dir="${LINUX_PKG_BUILD_ROOT_DIR:-/var/lib/linux-pkg}"
	logmust sudo mkdir -p "$build_root_dir"

	mount_opts=",$(findmnt -no OPTIONS --target "$build_root_dir"),"
	if [[ "$mount_opts" == *,nodev,* ]]; then
		die "$build_root_dir is mounted 'nodev', which debootstrap refuses" \
			"to install into. Set LINUX_PKG_BUILD_ROOT_DIR to a directory" \
			"on a filesystem without that option."
	fi
	if [[ "$mount_opts" == *,noexec,* ]]; then
		die "$build_root_dir is mounted 'noexec', which debootstrap refuses" \
			"to install into. Set LINUX_PKG_BUILD_ROOT_DIR to a directory" \
			"on a filesystem without that option."
	fi

	rootfs="$build_root_dir/build-root-$UBUNTU_DISTRIBUTION"
	tarball="${rootfs}.tar"
	logmust sudo rm -rf "$rootfs"
	logmust sudo debootstrap --variant=buildd \
		--keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg \
		"$UBUNTU_DISTRIBUTION" "$rootfs" "$mirror"

	#
	# Note that tar is not piped into docker import here. logmust dies on
	# failure and a piped logmust would die inside a subshell, which would
	# lose the error, so the tarball goes to disk and each step is checked.
	#
	logmust sudo tar -C "$rootfs" -cf "$tarball" .
	logmust docker import "$tarball" "${tag}-base"
	logmust sudo rm -f "$tarball"
	logmust sudo rm -rf "$rootfs"

	#
	# The labels are what the cache check above reads back; see the comment
	# there for why each one invalidates the image.
	#
	logmust docker build -t "$tag" \
		--build-arg "BASE=${tag}-base" \
		--build-arg "UID=$(id -u)" \
		--build-arg "GID=$(id -g)" \
		--label "com.delphix.linux-pkg.mirror-main=$mirror" \
		--label "com.delphix.linux-pkg.uid=$(id -u)" \
		--label "com.delphix.linux-pkg.gid=$(id -g)" \
		--label "com.delphix.linux-pkg.dockerfile-sha256=$dockerfile_sha" \
		-f "$dockerfile" "$TOP/resources"
}

#
# Variables that cross into the build container. This is an allowlist rather
# than a pass-through of the environment, so that the boundary's contract stays
# visible and a missing variable fails loudly instead of silently.
#
# DRYRUN and the PUSH_GIT_* credentials belong here even though no build reads
# them: sync-with-upstream.sh and push-merge.sh re-exec into the container too,
# and both check DRYRUN (and, through push_to_remote(), the credentials) after
# the re-exec, so without these the auto-update jobs that drive them would die
# on every invocation no matter what the host set.
#
# Only variables cross this boundary, never files, so anything naming a path
# needs a bind mount as well; see SECRET_DB_JUMP_BOX_PRIVATE_KEY and ~/.aws
# below.
#
CONTAINER_ENV_ALLOWLIST="
DEFAULT_GIT_BRANCH
DEFAULT_REVISION
DELPHIX_RELEASE_VERSION
DELPHIX_SIGNATURE_VERSION
DELPHIX_SIGNATURE_URL
DELPHIX_SIGNATURE_TOKEN
DELPHIX_PACKAGE_MIRROR_MAIN
DELPHIX_PACKAGE_MIRROR_SECONDARY
DEPENDENCIES_BASE_URL
JENKINS_OPS_DIR
TARGET_KERNEL_FLAVORS
UBUNTU_DISTRIBUTION
FETCH_GIT_TOKEN
DRYRUN
PUSH_GIT_TOKEN
PUSH_GIT_USER
PUSH_GIT_PASSWORD
"

#
# Read one package's PACKAGE_NEEDS_DOCKER out of its config.sh, without loading
# the rest of its configuration. Sets _RET.
#
# container_run_args() has to know whether the host's docker socket needs binding
# in before the container is started, which is before load_package_config() runs:
# that runs inside the container, and deliberately, since it resets the hook
# namespace, resolves the package's dependencies and validates its config, none
# of which belongs in the host-side process. So read only this one variable here,
# with the config sourced in a subshell so nothing else it defines or sets can
# leak into the host-side shell, and its output discarded so a config that echoes
# does not interleave with the host's log. A config that cannot be sourced yields
# an empty value rather than an error; the in-container load_package_config()
# reports that properly, with all of its validation in place.
#
function package_needs_docker() {
	local pkg="$1"

	check_env TOP
	_RET=$(
		cd "$TOP" || exit 1
		source "packages/$pkg/config.sh" >/dev/null 2>&1
		echo "$PACKAGE_NEEDS_DOCKER"
	)
}

#
# Assemble the docker arguments for a build container. Sets _RET_LIST.
#
function container_run_args() {
	check_env TOP
	local tag var name

	logmust container_image_tag
	tag="$_RET"

	_RET_LIST=(
		"--init"
		"--network" "host"
		"--user" "$(id -u):$(id -g)"
		"-v" "$TOP:$TOP"
		"-w" "$TOP"
	)

	for var in $CONTAINER_ENV_ALLOWLIST; do
		[[ -n "${!var+x}" ]] && _RET_LIST+=("-e" "$var")
	done

	#
	# AWS credentials, secretDb settings, and the per-package overrides are
	# named by pattern rather than individually, since the latter are spelled
	# with the package's own name (CLOUD_INIT_GIT_BRANCH selects the branch for
	# cloud-init, and so on) and so cannot be enumerated here.
	#
	# Note that these are the per-package *inputs*, read by
	# get_package_config_from_env(). The PACKAGE_GIT_URL, PACKAGE_GIT_BRANCH and
	# PACKAGE_REVISION that function computes from them deliberately do not
	# cross: they are recomputed in the container, where
	# reset_package_config_variables() unsets them first anyway.
	#
	while IFS='=' read -r name _; do
		#
		# Skip what the allowlist already names, so that a variable matching
		# one of the patterns below (DEFAULT_GIT_BRANCH, DEFAULT_REVISION) is
		# not passed twice.
		#
		[[ "$CONTAINER_ENV_ALLOWLIST" == *$'\n'"$name"$'\n'* ]] && continue

		case "$name" in
		AWS_* | SECRET_DB_* | *_S3_URL | *_GIT_URL | *_GIT_BRANCH | *_REVISION)
			_RET_LIST+=("-e" "$name")
			;;
		esac
	done < <(env)

	#
	# SECRET_DB_JUMP_BOX_PRIVATE_KEY holds a path to an SSH key on the host, so
	# the path has to resolve inside the container as well. Docker's classic -v
	# syntax does not refuse a missing host source; it silently creates an empty,
	# root-owned directory there instead, so without this check a typo here would
	# mount an empty directory where the build expects an SSH key, and the failure
	# would surface confusingly deep inside the secretDb client rather than here.
	#
	if [[ -n "$SECRET_DB_JUMP_BOX_PRIVATE_KEY" ]]; then
		[[ -f "$SECRET_DB_JUMP_BOX_PRIVATE_KEY" ]] ||
			die "SECRET_DB_JUMP_BOX_PRIVATE_KEY=$SECRET_DB_JUMP_BOX_PRIVATE_KEY is not" \
				"a regular file; a docker bind mount would silently create an empty" \
				"directory there instead of the expected SSH key."
		_RET_LIST+=("-v"
			"${SECRET_DB_JUMP_BOX_PRIVATE_KEY}:${SECRET_DB_JUMP_BOX_PRIVATE_KEY}:ro")
	fi

	#
	# An AWS profile or credentials file only exists as a file, so
	# SECRET_DB_AWS_PROFILE crossing the boundary is not enough on its own, and
	# neither is anything else that resolves credentials that way: both
	# fetch_dependencies() and sign_modules()' key fetch need working AWS
	# credentials for most of the packages here. Bind-mounting the directory
	# read-only is preferred over asserting on env-var credentials because it
	# leaves both credential styles working, and read-only because the container
	# has no business rewriting the host's AWS configuration. Mounted at the
	# container user's home, not the host user's: only $TOP is mapped through at
	# its host path, and $HOME inside the container is the home of the user
	# resources/Dockerfile.build-container creates.
	#
	if [[ -d "$HOME/.aws" ]]; then
		_RET_LIST+=("-v" "$HOME/.aws:$CONTAINER_HOME/.aws:ro")
	fi

	if [[ "$PACKAGE_NEEDS_DOCKER" == "true" ]]; then
		[[ -S /var/run/docker.sock ]] ||
			die "PACKAGE_NEEDS_DOCKER is set but /var/run/docker.sock does not exist" \
				"on the host; a docker bind mount would silently create an empty" \
				"directory there instead of the socket."
		#
		# The socket is mode 660 root:docker, and docker does not propagate the
		# invoking user's supplementary groups, so a container started with
		# --user <uid>:<primary gid> gets EACCES on it even when the host user is
		# in the docker group. The image's /etc/group has no entry for that gid
		# either, so the grant has to come from --group-add, derived from the
		# socket itself rather than hardcoded: the docker group's gid differs
		# between hosts, and what matters is the group that owns this socket.
		#
		_RET_LIST+=("-v" "/var/run/docker.sock:/var/run/docker.sock")
		_RET_LIST+=("--group-add" "$(stat -c %g /var/run/docker.sock)")
	fi

	_RET_LIST+=("$tag")
}

#
# Start an interactive shell in a fresh build container, with the same mounts
# and environment a build would get. Used to reproduce a build environment
# without reconstructing the docker invocation by hand.
#
function container_shell() {
	local -a args tty_opts

	logmust check_host_is_disposable
	logmust container_check_host_prereqs
	logmust container_build_base_image
	logmust container_run_args
	args=("${_RET_LIST[@]}")

	#
	# -i is unconditional so a piped command list still works; -t is added
	# only when stdin is actually a terminal, since docker refuses -t when
	# it is not ("the input device is not a TTY"), which would otherwise
	# break this flag under a script or CI job feeding it commands.
	#
	tty_opts=("-i")
	[[ -t 0 ]] && tty_opts+=("-t")

	echo_bold "Starting a shell in the build container." \
		"The checkout is bind-mounted at $TOP."
	echo_bold "This container has NOT run setup.sh, so it has no build tooling" \
		"yet (no debhelper, no apt sources for $UBUNTU_DISTRIBUTION, no aws)." \
		"Run ./setup.sh inside it first if you need any of that."
	exec docker run --rm "${tty_opts[@]}" "${args[@]}" bash
}

#
# Re-run the calling script inside the build container and exit with its status.
# A no-op when already inside, or when the caller has opted out.
#
function container_reexec() {
	local script="$1"
	shift
	local name rc
	local -a args

	running_in_container && return 0
	logmust check_host_is_disposable
	if [[ "$LINUX_PKG_NO_CONTAINER" == "true" ]]; then
		echo_bold "LINUX_PKG_NO_CONTAINER is set; running on the host."
		return 0
	fi

	logmust container_check_host_prereqs
	logmust container_build_base_image
	logmust container_run_args
	args=("${_RET_LIST[@]}")

	name="linux-pkg-$(basename "${script%.sh}")"
	[[ -n "$PACKAGE" ]] && name="linux-pkg-$PACKAGE"

	#
	# Plain docker rather than logmust: a leftover container from a previous
	# failed run is expected, and logmust would die on the removal of one
	# that does not exist.
	#
	docker rm -f "$name" >/dev/null 2>&1 || true

	#
	# Not exec'ing here is deliberate: the failure path keeps the container
	# around for debugging, which requires a process left to make that
	# decision. The trap covers an aborted Jenkins job.
	#
	trap 'docker rm -f "$name" >/dev/null 2>&1; exit 130' INT TERM

	#
	# Credentials embedded in a URL are masked before the command line is
	# echoed, the same way push_to_remote() masks them (lib/common.sh): the
	# arguments are echoed verbatim otherwise, and '-g https://<token>@github.com/...'
	# would then land in a Jenkins console log. Only the URL shape is masked;
	# tokens passed by name (-e FETCH_GIT_TOKEN) never appear here to begin with.
	#
	echo_bold "Running in container:" \
		"$(sed -E 's#(https?://)[^/@[:space:]]+@#\1******@#g' \
			<<<"docker run --name $name ${args[*]} $script $*")"
	rc=0
	docker run --name "$name" "${args[@]}" "$script" "$@" || rc=$?
	trap - INT TERM

	if [[ $rc -eq 0 ]]; then
		docker rm -f "$name" >/dev/null ||
			die "Could not remove container '$name'"
	else
		echo_error "Build failed in container '$name', which has been left" \
			"in place for debugging. To inspect it:"
		echo_bold "  docker start -ai $name"
		echo_bold "  docker exec -it $name bash    # if it is running"
		echo_bold "Or to start a fresh container with the same mounts and" \
			"environment, then drive the build by hand from there. That" \
			"container starts without any build tooling, so run ./setup.sh" \
			"inside it first:"
		echo_bold "  ./buildpkg.sh -S ${PACKAGE:-<package>}"
	fi
	exit $rc
}
