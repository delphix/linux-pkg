# SBOM Per-Package Sidecar Generation — Design

- **Date:** 2026-09-08
- **Jira:** [DLPX-98872](https://perforce.atlassian.net/browse/DLPX-98872)
- **Epic:** [CP-13455](https://perforce.atlassian.net/browse/CP-13455) — CycloneDX SBOM for Delphix engine product images
- **Implements:** Phase 2 (CP-13465) of `appliance-build`'s
  `docs/specs/2026-06-23-sbom-generation-implementation-plan.md`
- **Companion to (in the `appliance-build` repo):** `docs/specs/2026-06-15-sbom-generation-design.md`
  (CP-13456, the overall design) and `docs/specs/2026-08-13-syft-cyclonedx-cli-provisioning-design.md`
  (CP-13600, how `syft`/`cyclonedx-cli` get onto a build host)
- **Implemented in:** this change (DLPX-98872) — see *Implementation* below.

## Builds on: Phase 1 (already implemented)

Phase 1 — the `appliance-build` per-image base scan (CP-13464) — and its `syft`/
`cyclonedx-cli` provisioning prerequisite (CP-13600) are implemented, each with an open PR:

| Repo | PR | What it does |
|---|---|---|
| `syft` | [#1](https://github.com/delphix/syft/pull/1) | Packaging repo for `delphix-syft` (fetches the pinned upstream release binary) |
| `cyclonedx-cli` | [#1](https://github.com/delphix/cyclonedx-cli/pull/1) | Packaging repo for `delphix-cyclonedx-cli` (same pattern) |
| `linux-pkg` | [#414](https://github.com/delphix/linux-pkg/pull/414) | Adds `packages/syft/`, `packages/cyclonedx-cli/`, listed in `package-lists/build/main.pkgs` (this branch is rebased on top of it) |
| `appliance-build` | [#892](https://github.com/delphix/appliance-build/pull/892) | Installs both `.deb`s onto the build host in `build-ancillary-repository.sh`; new `95-generate-sbom.binary` hook runs `syft scan dir:binary --select-catalogers dpkg` + `cyclonedx-cli validate` to emit `<variant>-<platform>.cdx.json` |
| `devops-gate` | [#4717](https://github.com/delphix/devops-gate/pull/4717) | `appliance_build_stage0.groovy` best-effort-fetches and archives the per-image `.cdx.json` |

Net effect: `syft` and `cyclonedx-cli` are already real, buildable `linux-pkg` packages,
already on every build host's `PATH` (build-host-only tooling — never shipped in the image),
and every image already gets a flat, dpkg-only base SBOM. **Phase 2 has no new tooling
dependency to add** — it only needs to *invoke* `syft`, which is already available.

## Problem

The Phase 1 base scan lists every installed `.deb` as a flat `pkg:deb` component. That is
correct and sufficient for 3rd-party Debian packages, but wrong for Delphix's own
first-party packages: `masking`, `virtualization`, `delphix-sso-app`, `containerized-masking`,
`windows-connector`, `zfs`, `ptools`, and `delphix-rust` all bundle third-party components
across ecosystems (jars, npm, wheels, Rust crates) that `dpkg` cannot see — dpkg only knows
the files *it* placed, not what's vendored inside a jar or statically linked into a Rust
binary. Those components are invisible to a vulnerability scanner today.

Per the original design's key decision, this composition must be captured **upstream, in
`linux-pkg`**, at build time, where the package's own build artifacts are present — not
reconstructed later from a stripped, compiled `.deb`.

## Design and implementation

All of the following is implemented in this change, entirely within `linux-pkg` — no other
repo needs to change for Phase 2 (see *S3 upload* below for why).

### 1. `SBOM_DEEP_SCAN` — per-package opt-in flag

Mirrors the existing `MEND_SCAN_APPLICABLE` convention: a plain variable set in a package's
`config.sh`. Unlike `MEND_SCAN_APPLICABLE` (opt-in only, unset elsewhere), this flag is a real
tri-state — "must deep-scan" / "explicitly doesn't need it" / "nobody has classified this
yet" — enforced by the CI lint in §3, so **every** package's `config.sh` now has an explicit
`SBOM_DEEP_SCAN="true"` or `SBOM_DEEP_SCAN="false"` (see §5).

```bash
# packages/<pkg>/config.sh
SBOM_DEEP_SCAN="true"
```

### 2. `query-packages.sh` — surface the field

`query-packages.sh` has a closed, hardcoded field enum — no generic "query any config.sh
variable" mechanism exists. Two edits:

- `ALL_OUTPUT_FIELDS`: appended `sbom-deep-scan`.
- `print_package()`'s `case "$field"` block, alongside the `mend-scan)` arm:
  ```bash
  sbom-deep-scan) outarray+=("${SBOM_DEEP_SCAN:-none}") ;;
  ```

`-o`'s comma-delimited parsing and validation against `ALL_OUTPUT_FIELDS` then works for the
new field automatically. `./query-packages.sh list -o name,sbom-deep-scan all` is the
mechanism both the CI lint (§3) and `appliance-build`'s future Phase 3 consumer use to find
flagged packages.

### 3. CI lint — every package must be classified

No existing precedent to extend — `MEND_SCAN_APPLICABLE` is opt-in with zero enforcement
anywhere in `linux-pkg`. New script `.github/scripts/verify-sbom-scan-flag.sh`, wired as a
`verify-sbom-scan-flag` job in `.github/workflows/main.yml` alongside the existing
`verify-query-packages*` jobs:

```bash
unclassified=$(./query-packages.sh list -o name,sbom-deep-scan all |
	awk -F'\t' '$2 == "none" { print $1 }')
if [[ -n "$unclassified" ]]; then
	echo "The following packages have not set SBOM_DEEP_SCAN (\"true\" or" \
		"\"false\") in their config.sh:"
	echo "$unclassified"
	exit 1
fi
```

The one-time classification of all 40 packages (§5) lands in the same change, so this lint
never lands red.

### 4. `generate_sbom()` — sidecar generation

Modeled on `store_build_info()` — a default stage function in `lib/common.sh` that packages
don't need to override, gated on the new flag:

```bash
# lib/common.sh
function generate_sbom() {
	if [[ "$SBOM_DEEP_SCAN" != "true" ]]; then
		return 0
	fi

	local debs=("$WORKDIR/artifacts/"*.deb)
	if [[ ! -e "${debs[0]}" ]]; then
		die "SBOM_DEEP_SCAN is set but no .deb was found in" \
			"'$WORKDIR/artifacts'"
	fi

	check_env DEPDIR
	logmust install_pkgs "$DEPDIR"/syft/*.deb "$DEPDIR"/cyclonedx-cli/*.deb

	# One sidecar per .deb, not per package: a package that emits more
	# than one .deb (e.g. "zfs" splits into zfs-dkms, zfsutils-linux,
	# etc.) gets one <deb-filename>.deb.cdx.json per .deb -- a strict
	# 1:1 mapping, no merging across a package's .deb(s).
	local deb
	for deb in "${debs[@]}"; do
		local sbom_file deb_version
		sbom_file="$WORKDIR/artifacts/$(basename "$deb").cdx.json"
		deb_version="$(dpkg-deb -f "$deb" Version)"
		SYFT_FILE_METADATA_SELECTION=none logmust syft scan "$deb" \
			--source-name "$PACKAGE" \
			--source-version "$deb_version" \
			-o "cyclonedx-json@1.6=$sbom_file"

		logmust cyclonedx-cli validate \
			--input-file "$sbom_file" \
			--input-format json \
			--input-version v1_6 \
			--fail-on-errors
	done
}
```

Wired into `buildpkg.sh` as a new stage between the two that already bracket this point:

```bash
logmust cd "$WORKDIR"
stage store_build_info
logmust cd "$WORKDIR"
stage generate_sbom        # <-- new
logmust cd "$WORKDIR"
stage post_build_checks
```

`stage` silently skips undefined hooks, so this is inert for every package until
`generate_sbom` is defined — defining it once in `lib/common.sh`, gated internally on the
flag, means no package needs its own override for the baseline case (only per-ecosystem
overrides, out of scope for Phase 2, would override the function in a package's `config.sh`,
the same way packages already override `build()`).

**Resolved — multiple `.deb`s per package:** a reviewer flagged that the original
merge-into-one-sidecar approach (below, kept here for history) doesn't give a clean 1:1
mapping between a `.deb` and its BOM. Changed to: one `<deb-filename>.deb.cdx.json` per
`.deb`, no merge, no `cyclonedx-cli merge` step at all — each `.deb`'s sidecar is fully
independent and filename-matched to it. This is a real divergence from the top-level
design doc (CP-13456), which called for "one package-level SBOM... associated with all
of that package's debs via `COMPONENTS`" — that assumption didn't survive review. Phase 3
(`appliance-build`'s consumer, not yet built) will need to associate each `.deb` with its
own sidecar directly by filename, not go through a package-level indirection.

*(For reference, the approach this replaced: scan each `.deb` into its own document, then
`cyclonedx-cli merge --output-version v1_6` them into a single `<package>.cdx.json`. Two
real bugs were found and fixed while that was still in place, both still relevant to the
current code since they're not specific to the merge step: `syft`/`cyclonedx-cli` need to
be installed from `$DEPDIR` before use — see §4's `install_pkgs` line — and Syft's default
file-metadata component needs suppressing via `SYFT_FILE_METADATA_SELECTION=none`.)*

**Resolved — Syft's `.deb`-scan support:** confirmed working against the real `syft`/
`cyclonedx-cli` binaries via an actual pre-push build (`delphix-sso-app`, `delphix-rust`) —
`syft scan <deb-path>` scans a standalone `.deb` file directly, no extraction needed.

### 5. Package classification

Per the original design's "does this package bundle third-party composition" criterion (not
strictly "is it 1st-party" — see the `zfs` case), `SBOM_DEEP_SCAN="true"` is set for:

| Package | Why |
|---|---|
| `masking` | Java/Gradle app bundling jars + npm frontend |
| `virtualization` | Java/Gradle app bundling jars + npm frontend |
| `delphix-sso-app` | Java/Gradle app |
| `containerized-masking` | Java/Gradle app |
| `windows-connector` | Java/Gradle app |
| `zfs` | OpenZFS fork bundling Delphix's Rust object agent (crates invisible to dpkg) |
| `ptools` | Rust |
| `delphix-rust` | Rust |

The remaining 32 packages (kernel packages, `misc-debs`, `syft`/`cyclonedx-cli` themselves,
etc.) get `SBOM_DEEP_SCAN="false"` — plain 3rd-party forks or single-ecosystem tools already
fully represented by the Phase 1 flat `pkg:deb` component. `delphix-go` is a judgment call:
the top-level design's Tooling section separately calls out a possible Go override
(`cyclonedx-gomod`); defaulted to `"false"` here (baseline Syft-on-deb has a Go
binary-build-info cataloger that may already cover it) — revisit under Phase 4's evaluation
if gaps are found.

### S3 upload — no new plumbing needed

Confirmed by reading `devops-gate/jenkins/jobs/pipelines/linux_pkg_build_package.groovy`'s
`Publish` stage: it runs `aws s3 sync --delete --only-show-errors . ${env.S3_PACKAGE_PATH}`
from inside `dir("linux-pkg/workdir/artifacts")` — i.e., it uploads **the entire artifacts
directory verbatim**, whatever stages before it dropped there (`store_build_info`'s
`GIT_HASH`/`BUILD_INFO` files, the built `.deb`(s), etc.). `generate_sbom()` writing
`<package>.cdx.json` into that same directory is automatically picked up by this existing
sync — **no `devops-gate` change required for Phase 2**, unlike Phase 1 which needed a new
fetch step in `appliance_build_stage0.groovy` because that pipeline wasn't already pulling
per-package artifact directories at all.

## Architecture diagram

```
+---------------------------------------------------------------------------+
| linux-pkg package build (buildpkg.sh)                                     |
|                                                                            |
|   stage build              --> $WORKDIR/artifacts/*.deb                   |
|   stage store_build_info   --> GIT_HASH, BUILD_INFO, ...                  |
|   stage generate_sbom      --> [only if SBOM_DEEP_SCAN="true"]            |
|                                   for each .deb:                          |
|                                     syft scan <deb> -o cyclonedx-json@1.6  |
|                                     --> <deb-filename>.deb.cdx.json        |
|                                     cyclonedx-cli validate --fail-on-errors|
|                                   (strict 1:1 .deb <-> BOM, no merging)    |
|   stage post_build_checks                                                 |
+------------------------------------+--------------------------------------+
                                     |
                                     |  devops-gate Publish stage:
                                     |  aws s3 sync (whole artifacts/ dir,
                                     |  unmodified from Phase 1)
                                     v
+---------------------------------------------------------------------------+
| S3: combined-packages/packages/<pkg>/                                     |
|       <deb-filename>.deb                                                  |
|       <deb-filename>.deb.cdx.json   <-- NEW: one per .deb, same prefix    |
|       GIT_HASH, BUILD_INFO, ...  (unchanged)                              |
+---------------------------------------------------------------------------+
                                     |
                                     |  (Phase 3, not in scope here:
                                     |   appliance-build fetches each .deb's
                                     |   own sidecar by filename match)
                                     v
                              [out of scope for Phase 2]
```

## Out of scope for Phase 2

- Per-ecosystem overrides (`cargo-cyclonedx` for Rust, `cyclonedx-gradle-plugin` for
  Java) — Phase 4's evaluation decides if the Syft-on-deb baseline here is good enough
  first.
- `appliance-build` fetching/merging these sidecars into the per-image document — that's
  Phase 3 (CP-13466), which explicitly depends on this phase completing.
- DCT/Hyperscale sidecars — deferred in the top-level design, not filed as a story yet.
- The `devops-gate` publishing switch (CSV → CycloneDX) — unrelated to sidecar generation.

## Implementation status

- [x] `SBOM_DEEP_SCAN` classification added to all 40 packages' `config.sh` (§5).
- [x] `sbom-deep-scan` field added to `query-packages.sh` (§2).
- [x] `generate_sbom()` added to `lib/common.sh` and wired as `stage generate_sbom` in
      `buildpkg.sh` (§4), producing a strict 1:1 `.deb` → `.cdx.json` mapping (§4).
- [x] CI lint added (§3), landed in the same change as the classification pass.
- [x] Verified locally: `verify-sbom-scan-flag.sh` and the existing
      `verify-query-packages.sh` both pass; `shellcheck`/`shfmt` clean on every touched file.
- [x] Verified against a real build host: `delphix-sso-app` (single-`.deb`) and
      `delphix-rust` (multi-`.deb`) pre-push builds both produce valid, schema-checked
      CycloneDX 1.6 sidecars in S3, correctly named per `.deb`.
- [x] Confirmed compliant with reviewer feedback: `syft`, `cyclonedx-cli`, and all
      `linux-kernel-*` packages are `SBOM_DEEP_SCAN="false"` (no SBOM generated for
      build-host tooling or 3rd-party kernel forks), and the `.deb` ↔ `.cdx.json` mapping
      is now strictly 1:1 with a shared filename prefix.

## Bugs found and fixed during real-build testing

Not caught by CI — only surfaced by actually running builds:

1. **`syft`/`cyclonedx-cli` command not found.** Nothing installed them into the
   `linux-pkg` build container (Phase 1 only solved this for the `appliance-build` host).
   Fixed by declaring them as `PACKAGE_DEPENDENCIES` on all 8 flagged packages and
   installing from `$DEPDIR` in `generate_sbom()`.
2. **Blank `--source-version`.** `$PACKAGE_VERSION` doesn't reliably survive to the
   `generate_sbom` stage for packages that don't set it themselves (unlike
   `syft`/`cyclonedx-cli`'s own `config.sh`). Fixed by reading the version back out of the
   built `.deb` via `dpkg-deb -f "$deb" Version`.
3. **Stray Syft "file" component**, carrying file hashes and an absolute build-workspace
   path, polluting the sidecar. Fixed with `SYFT_FILE_METADATA_SELECTION=none`, matching
   `appliance-build`'s `95-generate-sbom.binary` hook.
4. **`cyclonedx-cli merge` defaulted to spec version 1.7**, failing the subsequent
   `--input-version v1_6` validate call. Moot now that merging was removed entirely per
   the 1:1-mapping change above, but the same lesson applies to any future
   `cyclonedx-cli` invocation: pin `--output-version` explicitly, don't rely on its
   default.

## Follow-ups

1. Phase 3 (`appliance-build`'s consumer) needs to key off the 1:1 `.deb` ↔ `.cdx.json`
   filename mapping established here, not a package-level `COMPONENTS` indirection.
2. File as sub-tasks of DLPX-98872.