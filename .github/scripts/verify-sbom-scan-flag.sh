#!/bin/bash -ex

set -o pipefail

cd "$(git rev-parse --show-toplevel)"

#
# Every package must explicitly set SBOM_DEEP_SCAN to "true" or "false" in
# its config.sh -- see docs on generate_sbom() in lib/common.sh. There is
# no default: a package that hasn't been classified yet must fail CI
# rather than silently ship without a CycloneDX sidecar or without an
# explicit decision that it doesn't need one.
#
unclassified=$(./query-packages.sh list -o name,sbom-deep-scan all |
	awk -F'\t' '$2 == "none" { print $1 }')

if [[ -n "$unclassified" ]]; then
	echo "The following packages have not set SBOM_DEEP_SCAN (\"true\" or" \
		"\"false\") in their config.sh:"
	echo "$unclassified"
	echo
	echo "Set it to \"true\" for 1st-party packages, so that the" \
		"third-party components they package internally (jars, npm" \
		"modules, Rust crates, ...) are included in the product's" \
		"aggregate SBOM."
	echo "Set it to \"false\" for 3rd-party forks of Debian packages, and" \
		"for packages that are not included in a shipping product:" \
		"those are already covered as a flat pkg:deb component by" \
		"appliance-build's image-level scan, so a deep scan here would" \
		"add nothing."
	exit 1
fi

echo "All packages have classified SBOM_DEEP_SCAN"
