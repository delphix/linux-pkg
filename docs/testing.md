# Testing linux-pkg

> **Maintaining this doc:** this covers how to test a change to `linux-pkg` itself, how CI for a
> `linux-pkg` package works, and how to use `linux-pkg` to build/validate a change made in one of
> the packages it orchestrates. Source of truth: `buildpkg.sh`, `lib/common.sh`
> (`get_package_config_from_env()`), `query-packages.sh`, `package-lists/`, `Makefile`,
> `.github/workflows/main.yml`. Update this doc when a tool, option, job, or package list changes
> shape, or when a new gotcha is found or an old one is fixed. Written for an automated reader
> (exact commands, preconditions, gotchas) — see the README's own
> [Testing your changes](../README.md#testing-your-changes) section for the human-oriented
> starting point this doc expands on.
>
> Last checked against commit `8884b96` (2026-10-19).

This is a separate doc from the README on purpose: the README is for a person getting oriented in
the repo; this doc is written for a reader — human or an automated bugfix pipeline — that is about
to act on a specific change and needs exact commands, preconditions, and pass/fail signals, not
prose.

## 1. Testing a change to linux-pkg itself

"A change to linux-pkg itself" means editing `linux-pkg`'s own code: `buildpkg.sh`,
`lib/common.sh`, `setup.sh`, `query-packages.sh`, a `packages/<pkg>/config.sh`, or anything else
in this repository — not a change to the upstream source a package builds.

### 1.1 Style/lint checks (automatic, no manual run usually needed)

`.github/workflows/main.yml` runs automatically on every push and PR to this repo, with no
action needed to start it:

- `check-shellcheck` — `make shellcheck` (shellcheck over every `*.sh` file, excluding SC1090/SC1091)
- `check-shfmt` — `make shfmtcheck` (fails if `shfmt -d` finds any file not already formatted)
- `verify-query-packages` (three variants: `ubuntu-latest`, `macos-latest`, and inside a
  `jenkins/jenkins` container) — runs `.github/scripts/verify-query-packages.sh`
- `verify-sbom-scan-flag` — runs `.github/scripts/verify-sbom-scan-flag.sh`

Run the first two locally before pushing:

```bash
make shellcheck
make shfmtcheck
# or both together:
make check
```

**Pass/fail signal:** `make shellcheck`/`shellcheck` prints findings and exits non-zero if any
file has a lint issue; `make shfmtcheck` (`! shfmt -d ... | grep .`) prints `shfmt -d`'s own diff
and exits non-zero on failure, and is silent on a clean pass.

**`make clean`** (`sudo rm -rf packages/*/tmp`, plus `artifacts`/`*.buildinfo`/`*.changes`/`*.deb`/
`update-status`) clears build state between runs — useful before a rebuild, but it deletes any
in-progress build output under `packages/*/tmp`, so don't run it if you still need that.

**Gotcha:** `shfmt`/`shellcheck` must be the same versions the GitHub Actions job installs
(`.github/scripts/install-shellcheck.sh`, `.github/scripts/install-shfmt.sh`) — a different local
version can disagree with CI's own verdict.

### 1.2 Building a specific package

This is also how you confirm a `linux-pkg`-side change (e.g. a `config.sh` edit, a `lib/common.sh`
change) didn't break a package's build. Requires a Delphix buildserver image (or
`DISABLE_SYSTEM_CHECK=true` set beforehand on a non-buildserver host — see the README's own
"System Requirements" section for the full precondition list: docker, `debootstrap`, passwordless
sudo).

```bash
./buildpkg.sh <package>
```

**Pass/fail signal:** ends with `Package <package> has been built successfully.` and build
artifacts under `packages/<package>/tmp/artifacts`; any stage failing aborts the script with a
non-zero exit and the failing stage's own output above it.

**Gotcha:** `./setup.sh` must have been run at least once per host (it bootstraps the build
container image and bootstraps `debootstrap` for the target Ubuntu suite) — `buildpkg.sh` calls
`run_setup_if_needed` itself, so this is usually transparent, but the first run on a fresh host
can take significantly longer while that setup happens.

### 1.3 Testing changes to an existing package (upstream source, not linux-pkg itself)

If you changed the upstream source of a package `linux-pkg` already builds (not `linux-pkg`'s own
code), opening or updating a pull request against that package's own repository automatically
builds and validates it — no command needed. This is not a git hook: it's a GitHub
webhook-triggered Jenkins check, reported on the PR as the `jenkinsci/build-package` status — see
[§2](#2-ci-for-a-linux-pkg-package) below for how it works.

`git ab-pre-push` is a separate, manual command for testing a full appliance build with your
package's change — see [§3.2](#32-manual-full-appliance-build-git-ab-pre-push-from-the-packages-own-repo)
below for when and how to run it; it is never something a push fires on its own.

### 1.4 Testing a newly-added package

If the package is new and not yet merged to `develop`, there is no Jenkins pre-push job for it
yet (see [§2](#2-ci-for-a-linux-pkg-package) below) — exercise it manually first. No `-g`/`-b`/`-r`
override is needed here: the `config.sh` you just added for the new package already defines its
own correct source.

```bash
./buildpkg.sh <package>
```

Once merged to `develop`, that package's own automatic PR check (§2) starts existing. This
specific case — validating `linux-pkg`'s own new-package addition, not a change to that package's
upstream source — is the one exception to
[§3.2](#32-manual-full-appliance-build-git-ab-pre-push-from-the-packages-own-repo)'s general rule: run
`git ab-pre-push -b <package>` from `linux-pkg` itself, since what's actually under test here is
`linux-pkg`'s own change (the new package entry), not the package's own upstream repo.

## 2. CI for a linux-pkg package

Each package already added to `/packages/` on `develop` gets an automatic PR check: opening or
updating a pull request against that package's own repository is a GitHub webhook event, not a
push-fired git hook — `devops-gate`'s
`github/<owner>/<repo>/linux-pkg-build-package/pre-push` job (defined in
`jenkins/jobs/github_linux_pkg_build_package_prepush.groovy`) listens for the PR's
`opened`/`synchronize` events, reports back as the `jenkinsci/build-package` GitHub status, resolves
which `linux-pkg` package the repo corresponds to (by matching the PR's repository URL against
`query-packages.sh list -o name,git-url appliance`), and fires the actual build via the
`build-package` job (`jenkins/jobs/linux_pkg_build_package.groovy`) with that package's git
URL/branch pointed at the PR. Nothing needs to be run manually for this — opening the PR is enough.
This doc only names the convention and what triggers it; `devops-gate`'s own testing doc is the
source of truth for either job's internals. (A separate, unrelated job,
`linux_pkg_combine_packages.groovy`'s `combine-packages`, is what §4 below describes — don't
conflate the two.)

What `linux-pkg` itself contributes to that CI:

- **`query-packages.sh`** — the catalog `devops-gate`'s Jenkins jobs read to know what to build and
  how to resolve a package from its repository:
  ```bash
  ./query-packages.sh list all                 # every known package
  ./query-packages.sh list appliance           # packages actually shipped into the appliance
  ./query-packages.sh list linux-kernel         # the kernel-flavor virtual list
  ./query-packages.sh single -o name,git-url,can-update <package>
  ```
- **`package-lists/`** — `build/main.pkgs` (the default shipped-package list) and
  `build/kernel-modules.pkgs` (packages depending on a specific kernel flavor — currently
  `connstat`, `delphix-kernel`, `zfs`).

**Gotcha:** a kernel-module package (`package-lists/build/kernel-modules.pkgs`: `connstat`,
`delphix-kernel`, `zfs`) always needs a separate VM to build/test against its target kernel
flavor — don't expect a generic build host to cover it.

## 3. linux-pkg's two-way role in "testing a change elsewhere"

`linux-pkg` orchestrates builds for a few dozen separate packages (`./query-packages.sh list all`
for every known package, `list appliance` for the subset actually shipped — the counts differ and
both drift over time, so this doc doesn't hardcode either), each backed by its own Delphix repo.
"Using this repo to test a change elsewhere" means: you changed one of those package repos, and
you want `linux-pkg` to build and validate that change as part of the combined appliance packages.

### 3.1 Direct override (manual, local)

`buildpkg.sh` can build a named package from an arbitrary git source instead of its pinned
default:

```bash
./buildpkg.sh -g <git-url> -b <branch> -r <revision> <package>
```

- `-g` overrides the package's git URL
- `-b` overrides the branch
- `-r` overrides the revision (commit/tag)

Example — build `cloud-init` from a personal fork's branch:

```bash
./buildpkg.sh -g https://github.com/<you>/cloud-init.git -b my-fix-branch cloud-init
```

This resolves through `lib/common.sh`'s `get_package_config_from_env()`, whose own documented
precedence (see the comment directly above that function) is: a `-g`/`-b`/`-r` command-line
parameter, then a package-specific environment variable
(`${PACKAGE_PREFIX}_GIT_URL`, e.g. `CLOUD_INIT_GIT_URL` for `cloud-init` — `PACKAGE_PREFIX` is the
package name upper-cased with `-` replaced by `_`), then — **for the git URL only** — the
package's own `config.sh` default (`DEFAULT_PACKAGE_GIT_URL`), then a global default. **The
branch and revision have no package-level `config.sh` default tier**: `-b`/`${PREFIX}_GIT_BRANCH`
falls straight through to the repo-wide `DEFAULT_GIT_BRANCH`, and `-r`/`${PREFIX}_REVISION` to
`DEFAULT_REVISION`, if neither override is set — there is no `DEFAULT_PACKAGE_GIT_BRANCH` or
`DEFAULT_PACKAGE_REVISION` anywhere in this repo, so setting one in a `config.sh` has no effect.

The command-line flags and the per-package environment variable are two entry points into this
same function's resolution, not two separate mechanisms — but they are two different priority
tiers, not the same one: `git ab-pre-push` (§3.2) populates the per-package environment variable
tier (e.g. `CLOUD_INIT_GIT_BRANCH`), never the `-g`/`-b`/`-r` command-line tier, which only a
direct, manual `buildpkg.sh` invocation sets.

**Pass/fail signal and gotcha:** identical to building any other package (§1.2) — the override
only changes which source is fetched, not how success/failure is reported.

### 3.2 Manual full-appliance build (`git ab-pre-push`, from the package's own repo)

`git ab-pre-push` is a separate, manual command — nothing fires it automatically; it is not the
mechanism behind §2's automatic per-package PR check. Run it when you want to build and test the
*whole appliance* with your package's change included, not just validate the package in isolation.

Run it from a package's own repository (not from `linux-pkg`) when the change is in that package's
own upstream source — see [§1.4](#14-testing-a-newly-added-package) for the one exception, where
the change under test is `linux-pkg`'s own new-package addition and `git ab-pre-push` runs from
`linux-pkg` instead. For an upstream-source change, `git ab-pre-push` resolves that repository to
its `linux-pkg` package name and fires `appliance-build-orchestrator-pre-push` with that package
pointed at your branch — by setting either `LINUX_PKG_GIT_URL`/`LINUX_PKG_GIT_BRANCH` (when run
from `linux-pkg` itself) or a `<package>: <ref>` line on that job's `PACKAGE_GIT_URLS`/
`PACKAGE_GIT_BRANCHES` parameters (when run from a package's own repo) — the manual equivalent of
§3.1's `buildpkg.sh` override, populating the same per-package environment-variable tier of
`get_package_config_from_env()` (e.g. `CLOUD_INIT_GIT_BRANCH`) that a manual export into that
variable would.

```bash
git ab-pre-push --no-tests --no-zfs-tests   # build only, skip the test suites
git ab-pre-push --test-upgrade-from <release>   # also test upgrade/migration from a given release
```

**Pass/fail signal:** the fired `appliance-build-orchestrator-pre-push` Jenkins build's own
result — this is a real, hours-scale CI run, not a local command with its own separate exit code.

**This resolution logic itself is `git-utils`' own code, not `linux-pkg`'s** — what `linux-pkg`
contributes to this flow is only the package registry it exposes (`config.sh`'s
`DEFAULT_PACKAGE_GIT_URL`, `query-packages.sh`, `package-lists/`), which is what that resolution
actually reads. For `git ab-pre-push`'s own full CLI usage and resolution behavior, see
`git-utils`'s own testing doc — this doc does not re-derive it.

### 3.3 What this doesn't cover

Any individual orchestrated package's own test suite (its unit tests, its own CI, its own
`dxosTest`/blackbox coverage) is that package's own repository's concern, documented in that
repository's own testing doc, not here — linux-pkg's own doc stops at the boundary of the
mechanism it actually provides (building/validating a package from an arbitrary source), not what
that package's own tests check once built.

## 4. Deploying a change to a test VM

### 4.1 Direct: a single package to a single VM (`git linux-pkg`, from `git-utils`)

For deploying one package's build to a VM directly, without going through the combined appliance
pipeline, `git-utils` provides `git linux-pkg` (usage text in `bin/git-linux-pkg`):

```bash
git linux-pkg build -m <build_machine> [-t <target_machine>] [<package>]
git linux-pkg deploy -m <build_machine> -t <target_machine> [<package>]
```

`build` pushes the repo you're running it from to `<build_machine>` (a DCenter VM from the
`bootstrap-18-04` group) and builds the named package there via `buildpkg.sh` — run from
`linux-pkg`, it uses that checkout's own code; run from a package's own repo, it builds that
package from the branch you're on. Passing `-t` also deploys the result immediately. `deploy`
alone installs a package already built on `<build_machine>` onto `<target_machine>` without
rebuilding.

**Preconditions:** `<build_machine>` must already exist as a DCenter VM from the `bootstrap-18-04`
group; `<target_machine>` is the engine/VM you want the package installed on.

**Pass/fail signal:** the command's own exit status and console output — this runs synchronously
against the two VMs, not a separate Jenkins build.

### 4.2 Combined: every shipped package, via appliance-build

`linux-pkg` doesn't deploy anything on its own here either — this path reaches a test VM through
`appliance-build`'s combined-packages pipeline: the `combine-packages` Jenkins job (defined in
`devops-gate`, driven by `linux-pkg`'s own `query-packages.sh`/`package-lists/` per §2) assembles
the latest build of every shipped package into a combined-packages artifact, which
`appliance-build` then consumes to produce an ISO/VM/upgrade image. See `appliance-build`'s own
testing doc for the pipeline's own build/deploy mechanics and how to get a VM from it — this doc
only names what `linux-pkg` hands off (the combined-packages artifact and which packages route
into it). `git ab-pre-push` (§3.2) exercises this same path for a single package's change as part
of a full appliance build.

**Gotcha:** a kernel-module package (same list as §2's gotcha: `connstat`, `delphix-kernel`,
`zfs`) reaching a VM through either path in this section still needs a VM matching its target
kernel flavor — that's a property of the package, not of which path got it there.
