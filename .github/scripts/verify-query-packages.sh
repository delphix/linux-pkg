#!/bin/bash -ex
# shellcheck disable=SC2012

set -o pipefail

cd "$(git rev-parse --show-toplevel)"

# Make sure a basic command doesn't print anything to stderr
test -z "$(./query-packages.sh single -o name,git-url zfs 2>&1 >/dev/null)"

# Expect: "zfs	https://github.com/delphix/zfs.git"
read -r -a fields <<<"$(./query-packages.sh single -o name,git-url zfs 2>&1)"
test ${#fields[@]} -eq 2
test "${fields[0]}" == 'zfs'
test "${fields[1]}" == 'https://github.com/delphix/zfs.git'

# Expect: "https://github.com/delphix/zfs.git	zfs"
read -r -a fields <<<"$(./query-packages.sh single -o git-url,name zfs 2>&1)"
test ${#fields[@]} -eq 2
test "${fields[0]}" == 'https://github.com/delphix/zfs.git'
test "${fields[1]}" == 'zfs'

# Expect: "zfs"
read -r -a fields <<<"$(./query-packages.sh single zfs 2>&1)"
test ${#fields[@]} -eq 1
test "${fields[0]}" == 'zfs'

# Expect: "https://github.com/delphix/zfs.git"
read -r -a fields <<<"$(./query-packages.sh single -o git-url zfs 2>&1)"
test ${#fields[@]} -eq 1
test "${fields[0]}" == 'https://github.com/delphix/zfs.git'

# Expect: "bpftrace	bcc	true	https://github.com/delphix/bpftrace.git"
read -r -a fields <<<"$(./query-packages.sh single -o name,dependencies,can-update,git-url bpftrace 2>&1)"
test ${#fields[@]} -eq 4
test "${fields[0]}" == 'bpftrace'
test "${fields[1]}" == 'bcc'
test "${fields[2]}" == 'true'
test "${fields[3]}" == 'https://github.com/delphix/bpftrace.git'

# Expect that "list all" outputs all directory names under packages/
diff <(ls -1 packages | sort) <(./query-packages.sh list all 2>&1 | sort)

# Expect that outputing dependencies & git-url for all packages works and that the output
# length corresponds to the number of packages.
test "$(ls -1 packages | wc -l)" -eq \
	"$(./query-packages.sh list -o name,dependencies,can-update,git-url all 2>&1 | wc -l)"

# Check that all package lists under package-lists\ can be loaded and that each
# line of the output of the command actually refers to a package.
find package-lists -name '*.pkgs' | while read -r list; do
	list="${list#package-lists/}"
	./query-packages.sh list "$list" 2>&1 | (
		cd packages
		xargs ls
	) >/dev/null
done

# Check that querying the built-in "appliance" list works
./query-packages.sh list appliance >/dev/null

# Check that querying lists used by the Delphix build works.
./query-packages.sh list build/main.pkgs >/dev/null
./query-packages.sh list build/kernel-modules.pkgs >/dev/null
./query-packages.sh list linux-kernel >/dev/null
./query-packages.sh list update/main.pkgs >/dev/null

# Check that overriding TARGET_KERNEL_FLAVORS changes which kernel packages are
# returned.
test "$(./query-packages.sh list linux-kernel | wc -l | awk '{print $1}')" -gt 1
test "$(TARGET_KERNEL_FLAVORS=generic ./query-packages.sh list linux-kernel)" == "linux-kernel-generic"

# Check that when a package has multiple dependencies they are printed in the
# expected format.
test "$(TARGET_KERNEL_FLAVORS="generic aws" ./query-packages.sh single -o dependencies zfs)" == \
	"linux-kernel-generic,linux-kernel-aws"

# Check that the output from the appliance list contains zfs and
# delphix-platform packages. Note, we explicitly do not use grep -q here as it
# exits as soon as a match is found and that causes a broken pipe error as
# query-packages attempts to write more output.
./query-packages.sh list appliance | grep zfs >/dev/null
./query-packages.sh list appliance | grep delphix-platform >/dev/null

# Check that executing query-packages works from another directory.
# This redoes the "list all" test from above
cd packages
diff <(ls -1 | sort) <(../query-packages.sh list all 2>&1 | sort)
