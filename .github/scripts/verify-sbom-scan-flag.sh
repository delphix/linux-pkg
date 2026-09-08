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
	exit 1
fi

echo "All packages have classified SBOM_DEEP_SCAN"
