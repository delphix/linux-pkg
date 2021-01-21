# Linux Package Framework

This framework is used for building customized third-party packages and public
Delphix packages for the Ubuntu-based Delphix Appliance. It also has the
functionality to automatically sync third-party packages with the upstream
projects.

## Table of Contents

1. [System Requirements](#system-requirements)
1. [Getting Started](#getting-started)
1. [Project Summary](#project-summary)
1. [Scripts](#scripts)
1. [Environment Variables](#environment-variables)
1. [Package Definition](#package-definition)
    * [Package Variables](#package-variables)
    * [Package Hooks](#package-stages-and-hooks)
    * [Package Environment Variables](#package-environment-variables)
    * [Package WORKDIR](#package-workdir)
1. [Adding New Packages](#adding-new-packages)
    * [Third-party package](#third-party-package)
    * [In-house package](#in-house-package)
1. [Testing your changes](#testing-your-changes)
1. [Package Lists](#package-lists)
1. [Versions and Branches](#versions-and-branches)
1. [Contributing](#contributing)
1. [Statement of Support](#statement-of-support)
1. [License](#license)

## System Requirements

This framework is intended to be run on an Ubuntu 18.04 system with some basic
developer packages installed, such as git, and passwordless sudo enabled. Note
that it will automatically install various build-dependencies on the system, so
as a safety precaution it is currently restricted to only run on an AWS instance
to prevent developers accidentally running it on their personal machines. To
bypass the safety check, you can run the following command before running any
script:

```
export DISABLE_SYSTEM_CHECK=true
```

## Getting Started

This quick tutorial shows how to build the packages managed by this framework.

### Step 1. Create build VM

You need a system that meets the requirements above. For Delphix developers, you
should clone the `bootstrap-18-04` group on DCoA.

### Step 2. Clone this repository and run the setup script

Clone this repository on the build VM.

```
git clone https://github.com/delphix/linux-pkg.git
```

Run the setup script. It only needs to be run once after cloning the VM.

```
cd linux-pkg
./setup.sh
```

### Step 3. Build a package

We can now build an arbitrary package. Any package in the
[packages directory](./packages) would do. Let's pick `cloud-init` as an
example:

```
./buildpkg.sh cloud-init
```

Build artifacts will be stored in directory
`packages/cloud-init/tmp/artifacts/`.

## Project Summary

There are two main tasks that are performed by this framework: building
packages and keeping each package up-to-date with its upstream project by
updating the appropriate git branches.

### Building packages

This task is relatively straight forward. What linux-pkg calls a "package" is
really a project (usually a git project) that has a build recipe and that
produces one or more debian packages and some other metadata files.

See [Scripts > updatelist.sh](#buildpkgsh) below.

### Updating third-party packages

The idea behind this task is to reduce the amount of effort required to
maintain third-party packages and keep them up-to-date. Note that this task
does not apply to packages created and maintained by Delphix, but only to
third-party packages that Delphix modifies. Instead of following a
[more conventional approach](http://packaging.ubuntu.com/html/patches-to-packages.html)
of using tarballs and patches with all its drawbacks,
we've decided to leverage the advantages offered by revision control. As such,
we've adopted a well defined branching model for each third-party package.

First of all, we have a Delphix repository on github for each third-party
package that we build. Each repository has at least 2 branches: **master** and
**upstreams/master**. The **master** branch of the package is the one we build,
and contains Delphix changes. The **upstreams/master** branch is used to track
the upstream version of the package. For packages that are not provided by
Ubuntu but are available on git, the **upstreams/master** branch usually just
tracks the **master** branch of the project. For packages that are provided by
Ubuntu, the **upstreams/master** branch instead tracks the source package that
is maintained by Ubuntu (i.e. the branch contains the files obtained from
`apt-get source <source-package>`). This offers the advantage of using a version
of the package tuned to work with our Ubuntu distribution.

When updating a package, we first check if the **upstreams/master** branch is
up-to-date, by fetching the latest version of the upstream git repository or the
Ubuntu source package. If changes are detected, we update the
**upstreams/master** branch and push the changes to GitHub.

The second step is to check if the **master** branch is up-to-date with
**upstreams/master**. If it is already up-to-date, then we are done. If not,
then we attempt merging **upstreams/master** into **master**.

If the merge is successful, then we push the changes to a staging branch on
GitHub, called **projects/auto-update/master/merging**. The intent is for
a different system to fetch those changes, build them, and then launch tests.

See [Scripts > sync-with-upstream.sh](#sync-with-upstreamsh) below.

Once the merge has been tested, [Scripts > push-merge.sh](#push-mergesh) is
called on the original VM to push the changes to the **master** branch on
GitHub.

Note that the example above targets the **master** branch, but the same
workflow could apply to other branches, like **6.0/stage**, although it is
not currently in use.

## Scripts

A set of scripts were created in this repository to allow easily building and
updating packages both manually and through automation (e.g. Jenkins).

### query-packages.sh

This script can be called on most unix-based systems to query metadata on the
packages built by linux-pkg. This script does not install anything on the
system, so it can be run anywhere without any side effects.

### setup.sh

Installs dependencies for the build framework. Needs to be run once to configure
the system, before any other scripts (except query-packages.sh).

### buildpkg.sh

Builds a single package. Package name must match a directory under
[packages/](./packages).

```
./buildpkg.sh <package>
```

The build will look at `packages/<package>/config.sh` for instructions on where
to fetch the package from and how to build it. The build will be performed in
`packages/<package>/tmp/`, and build artifacts for this package will be stored
in the `artifacts` sub-directory.

Note that if the build of the package depends on build artifacts from another
linux-pkg package, those will be fetched from a predetermined S3 location.

### checkupdates.sh

Usage:
```
./checkupdates.sh <package>
```

This checks if a package has updates in the upstream project that haven't been
pulled into the **upstreams/master** branch, or if the **upstreams/master**
branch has commits that haven't been merged into the **master** branch.

If updates are available, the file `<WORKDIR>/update-available` will be created.

The intention of this script is to inform the caller whether an update job
should be called for the given package.

### sync-with-upstream.sh

Usage:
```
./sync-with-upstream.sh <package>
```

This script has 2 tasks:
1. Check if the upstream project has updates that are not pulled into the
**upstreams/master** branch of the package, and if so then update that branch
and push changes to GitHub.
2. Merge **upstreams/master** into **master** and push the changes to a staging
branch on GitHub, called **projects/auto-update/master/merging**. Another
system should use that branch to build the package, and then run the appropriate
integration tests.

After testing has been completed, `push-merge.sh <package>` should be called on
the same system to push the merge to the **master** branch.

Note that the DRYRUN environment variable must be set when running this script.
If DRYRUN is set to "true", then changes are not pushed to GitHub in step 1,
and staged changes are pushed to **projects/auto-update/master/merging-dryrun**
in step 2 instead of the non-dryrun branch. The intention is that when testing
changes to the logic we want to be able to run most of the logic, but without
affecting the production branches.

### push-merge.sh

Usage:
```
./push-merge.sh <package>
```

This must be called on a system that has previously called
`sync-with-upstream.sh` for the same package. It will push the merge that was
previously prepared by `sync-with-upstream.sh` to the production **master**
branch, after checking that the **master** branch hasn't been modified since
`sync-with-upstream.sh` was called.

Like for `sync-with-upstream.sh`, the DRYRUN environment variable must be set
to run this script. However, the script will fail unless DRYRUN is set to
"false" given that there is not much that can be tested in dry-run mode.

## Environment Variables

There's a set of environment variables that can be set to modify the operation
of some of the scripts defined above.

* **DISABLE_SYSTEM_CHECK**: Set to "true" to disable the check that makes sure
  we are running on the appropriate Ubuntu distribution in AWS.
  Affects all scripts.

* **DRYRUN**: Must be set to either "true" of "false" when running script
  [sync-with-upstream.sh](#sync-with-upstreamsh), and to "false" when running
  script [push-merge.sh](#push-mergesh).

* **PUSH_GIT_USER, PUSH_GIT_PASSWORD**: Set to the git credentials used to push
  updates to package repositories. Affects scripts
  [sync-with-upstream.sh](#sync-with-upstreamsh) and
  [push-merge.sh](#push-mergesh).

* **DEFAULT_REVISION**: Default revision to use for packages that do not have a
  revision defined. If not set, it will be auto-generated from the timestamp.
  Applies to [buildpkg.sh](#buildpkgsh).

* **DEFAULT_GIT_BRANCH**: The product branch that is being built or updated is
  typically stored in the file `branch.config`, however it can be overridden via
  DEFAULT_GIT_BRANCH. It can either be set to a development branch, such as
  "master" or "6.0/stage", or a release tag, such as "release/6.0.6.0".
  The product branch is used in multiple instances. When
  running [setup.sh](#setupsh), it will determine what linux-package-mirror
  link to use when fetching packages from apt (although those links can be
  overridden via DELPHIX_PACKAGE_MIRROR_MAIN and
  DELPHIX_PACKAGE_MIRROR_SECONDARY). When running [buildpkg.sh](#buildpkgsh),
  it will determine which branch to fetch from the package's repository, unless
  it is overridden via `-b`; if the package has build-dependencies on other
  linux-pkg packages, those dependencies will be fetched from an S3 url that is
  versioned based on the product branch (although the package dependencies
  URLs can be overridden via package_S3_URL variables). Finally, when running
  [sync-with-upstream.sh](#sync-with-upstreamsh) or
  [push-merge.sh](#push-mergesh) it defines what branch of the package is
  being updated.

* **TARGET_KERNEL_FLAVOURS**: Some packages have build dependencies on the
  linux kernel. Those packages have `PACKAGE_DEPENDENCIES="@linux-kernel"` in
  their `config.sh`. By default, those packages are built for all the supported
  kernel flavours (see SUPPORTED_KERNEL_FLAVORS in `common.sh`), however it is
  possible to restrict which kernel flavours those packages are built for.

* **package_GIT_URL, package_GIT_BRANCH, package_VERSION,
  package_REVISION**: Can be used to override defaults for a given package.
  `package` is the package name in upper case with `-` converted to `_`. For
  instance `CLOUD_INIT_GIT_BRANCH=feature1` would set the branch to fetch
  package `cloud-init` from to `feature1`. This is useful when running
  `buildlist.sh` to override defaults for multiple packages. Applies to both
  `buildlist.sh` and `buildpkg.sh`.

* **package_S3_URL**: Similar to the package_VAR variables above. This is used
  to override the default S3 location for where package build-dependencies are
  fetched for a given linux-pkg package. For instance, if you are building
  bpftrace, which has `PACKAGE_DEPENDENCIES="bcc"` in its config, the
  `fetch_dependencies()` stage in the build will fetch the latest build
  artifacts of the bcc package from a predetermined S3 location. If you pass
  `BCC_S3_URL=s3://path/to/custom/bcc/artifacts` then those artifacts will be
  fetched insteasd.

* **DELPHIX_PACKAGE_MIRROR_MAIN, DELPHIX_PACKAGE_MIRROR_SECONDARY**: When
  the [setup.sh](#setupsh) script is run, it will configure the apt sources
  to point to versioned delphix mirrors of the Ubuntu archive (MAIN mirror)
  and of some auxiliary archives (SECONDARY mirror). Delphix has many snapshots
  of those mirrors at different points in time, and if you want to use a custom
  snapshot, you can pass it in those environment variables.

* **JENKINS_OPS_DIR**: When fetching artifacts from other linux-pkg packages
  that are marked as dependencies of a package, by default we look for a
  specific S3 path that contains production package artifacts generated by
  post-push jobs of the ops Jenkins agent. The production ops Jenkins agent
  stores artifacts in the special `jenkins-ops` sub-directory. When using
  a developer ops Jenkins agent, it stores build artifacts in a different S3
  sub-directory: `jenkins-ops.<developer>`. By setting JENKINS_OPS_DIR to that
  sub-directory you can instruct linux-pkg to fetch artifacts of build
  dependencies produced by the developer Jenkins instance instead of the
  production one.

* **DEPENDENCIES_BASE_URL**: When fetching artifacts from other linux-pkg
  packages that are marked as dependencies of a package, we look for a
  specific s3 path based on what product branch or version we are building for,
  which is defined by DEFAULT_GIT_BRANCH. If DEPENDENCIES_BASE_URL is left
  unset, then the path will be determined automatically. DEPENDENCIES_BASE_URL
  is most useful when set to the input-artifacts of a previous appliance-build
  run, i.e. "s3://.../input-artifacts/combined-packages/packages".

## Package Definition

For each package built by this framework, there must be a file named
`packages/<package>/config.sh`. It defines some default variables and various
hooks for building the package. When `buildpkg.sh` is invoked for building a
package, it calls `load_package_config()`, which sources the appropriate
`config.sh` file and then executes the various hooks defined for the package.
The bash library `lib/common.sh` contains various functions that can be called
from the hooks or the various scripts.

### Package Variables

Here is a list of variables that can be defined for a package:

* **DEFAULT_PACKAGE_GIT_URL**: (Mandatory) Git repository to fetch the package
  source code from. This is also the repository that is used when pushing
  changes with the `push-updates.sh` script. Note that this must be an
  `https://` URL. One exception is if the source of the package being built
  isn't fetched from git. In this case, set this to "none".

* **PACKAGE_DEPENDENCIES**: (Optional) If the build of this package requires
  fetching artifacts from other linux-pkg packages, those should be specified
  in PACKAGE_DEPENDENCIES, as a space-separated list. The dependencies will
  be fetched in the `fetch_dependencies()` step into `<WORKDIR>/<dep>/` where
  "dep" is the dependency's name. A special value can be passed for packages
  that target all the supported flavours of the linux-kernel: `@linux-kernel`.

* **DEFAULT_PACKAGE_GIT_BRANCH**: (DEPRECATED) Default git branch to use when
  fetching from or pushing to `DEFAULT_PACKAGE_GIT_URL`. This should be
  typically left unset. The branch to fetch the package from defaults
  to the value of the environment variable `DEFAULT_BRANCH`, which itself
  defaults to "master".
  WARNING: do not set this parameter unless you know exactly what you are doing,
  as our current versioning convention is to use DEFAULT_BRANCH for each
  package. This parameter may be removed in the future.

* **DEFAULT_PACKAGE_VERSION**: (Optional) The version of the package is set to
  this value when it is built. **Note:** If this field is not set, then you
  should provide a mechanism in the [build](#build-hook) hook to auto-determine
  the version from the source code.
  WARNING: This parameter will be removed in the near future, as we will rely on
  the changelog contained in the package's repository to get the package version
  in the future.

* **DEFAULT_PACKAGE_REVISION**: (Optional) The revision of the package is set to
  this value when it is built (note that the full version of a package is
  "_VERSION-REVISION_"). If unset, it defaults to value of environment variable
  DEFAULT_REVISION.
  WARNING: This parameter is currently unused and will be removed in the near
  future.

* **UPSTREAM_SOURCE_PACKAGE**: (Optional) Third-party packages that have an
  [update_upstream](#update-upstream-hook) hook and are updated from an Ubuntu
  source package should set this to the name of the source package.

* **UPSTREAM_GIT_URL, UPSTREAM_GIT_BRANCH**: (Optional) Third-party packages
  that have an [update_upstream](#update-upstream-hook) hook and are updated
  from a git repository should set this to the upstream git url and branch.

* **FORCE_PUSH_ON_UPDATE**: (Optional) This applies to some third-party packages
  that have an [update_upstream](#update-upstream-hook) hook. Most third-party
  packages are synced with upstream by performing a simple "git-merge" command,
  so when the merge is pushed it can be done with "git push". However some
  packages, like the linux-kernel ones, perform a rebase instead, and so the
  merge must be force-pushed instead. If you want to use force push to push
  an auto-merge, set FORCE_PUSH_ON_UPDATE to "true". Note that a safety check
  is always performed prior to doing the push to make that the target branch
  has not changed since the auto-merge commit was generated, however disabling
  force-push by default is an extra precaution.

* **SKIP_COPYRIGHTS_CHECK**: (Optional) By default, at the end of a package's
  build we check that each produced deb contains a copyright file, unless
  SKIP_COPYRIGHTS_CHECK is set to "true".

### Package stages and hooks

When operations are performed on a package by build or auto-update scripts,
such as [buildpkg.sh](#buildpkgsh) or
[sync-with-upstream.sh](#sync-with-upstreamsh), those operations are usually
split into high-level tasks called "stages". Some of those stages can be
modified or must be defined in a package's config file, so we refer to them
here as "hooks". Hooks that have a default definition are stored in
the `default-package-config.sh` file.

Other "stages" are not meant to be modified and aren't functionally different
from regular function calls, we want to give them more visibility in the build
process as they are deemed as important high-levels tasks, so they are called
via the `stage()` helper function.

#### Fetch (hook)

The `fetch()` hook is optional, as a default is provided and should be used. It
is called when fetching the source code of the package to build or to update.
The repository is cloned into `<WORKDIR>/repo` and checked out as
branch **repo-HEAD**. If we are performing a package update, then we also
fetch the **upstreams/master** branch into **upstream-HEAD**. The default
should only be overridden when not fetching the package source from git.

#### Prepare (hook)

The `prepare()` hook is optional. It is called before calling the build hook and
normally installs the build dependencies for the package.

#### Build (hook)

The `build()` hook is mandatory. It is responsible for building the package and
storing the build products into `packages/<package>/tmp/artifacts/`.

#### Update Upstream (hook)

The `update_upstream()` hook should only be defined for third party packages
that can be auto-updated. It is responsible for fetching the latest upstream
source code on top of branch **upstream-HEAD** of our fetched repository in
`<WORKDIR>/repo`. Note that any changes should be rebased on top of
the **upstreams/master** branch. If changes are detected, file
`<WORKDIR>/upstream-updated` should be created.

#### Merge With Upstream (hook)

The `merge_with_upstream()` hook is called after the `update_upstream()` hook
when a package is updated via [sync-with-upstream.sh](#sync-with-upstreamsh).
Whereas `update_upstream()` updates the **upstream-HEAD** branch,
`merge_with_upstream` then merges the **upstream-HEAD** branch into the
**repo-HEAD** branch. For most third-party packages this can be left unset as
the default will be used. For packages that have a more complex merge strategy,
such as the linux-kernel packages, this hook can be used.

#### Checkstyle (hook)

The `checkstyle()` hook is optional. It is called before building the package if
`-c` is provided to `buildpkg.sh`. Note that this hook isn't currently used by
our build automation and is more of a prototype for an idea.

#### Fetch Dependencies

`fetch_dependencies` is an immutable stage. It is called for fetching build
artifacts from other linux-pkg packages that are required for performing the
build. See the PACKAGE_DEPENDENCIES package variable for mroe info.

#### Store Build Info

`store_build_info()` is an immutable stage. It is called after the `build()`
stage. It is responsible for storing some build info / metadata, such as the
git hash used to perform the build. Some of the build info that is stored is
used by build automation, so care must be exercised when modifying it.

#### Post Build Checks

`post_build_checks()` is an immutable stage. It is responsible for performing
post-build checks that are common to all packages.

One of the checks verifies that each debian package produced has a copyright
file associated with it in the right location. This file is used elsewhere in
the product to generate the license information for the appliance. This check
can be skipped for a package by defining `SKIP_COPYRIGHTS_CHECK=true` in its
config file.

### Package environment variables

In addition to any variables defined by the package itself, a few environment
variables are set-up by the framework. Here is a quick list:

* **PACKAGE**: The name of the package being built.

* **PACKAGE_GIT_URL, PACKAGE_GIT_BRANCH, PACKAGE_VERSION, PACKAGE_REVISION**:
  Those variables are set by the framework depending on the corresponding
  `DEFAULT_{*}` variables defined in the package's `config.sh` and on other
  environment variables that are passed to the framework. For more details,
  refer to `get_package_config_from_env()` in [lib/config.sh](./lib/config.sh).

* **WORKDIR**: Directory where the package is fetched, built, etc. See
  [Package WORKDIR](#package-workdir).

* **KERNEL_VERSIONS**: Space separated list of kernel versions that the package
  should be built for. `determine_kernel_versions()` must be called before using
  this variable.

### Package WORKDIR

Each package is being fetched, built and updated in directory
`linux-pkg/packages/<package>/tmp/`, referred to as `WORKDIR`. Whenever a
script is called to operate a package, the WORKDIR directory is recreated and
a `linux-pkg/workdir` symlink is created that points to this WORKDIR.

The following sub-directories are created in `WORKDIR`:

* **repo**: where the repository is fetched and built.

* **artifacts**: where the build artifacts are stored.

* **source**: where the source package is fetched when updating upstream from
  a source package.

The following files are created in `WORKDIR`:

* **upstream_tag**: During a package's auto-update, we may wish to also push
  a tag fetched from the upstream repository for informational purposes. If so,
  the `upstream_tag` file should be created and contain the name of the tag
  that needs to be pushed.

The following files are used as status indicators in `WORKDIR`:

* **upstream-updated**: created if **upstream-HEAD** has updates that should
  be pushed.

* **repo-updated**: created if **repo-HEAD** has updates that should be pushed,
  following a merge.

## Adding new packages

When considering adding a new package, the workflow will depend on whether the
package is a [third-party package](#third-party-package) or
[in-house package](#in-house-package).

**Note:**:
If you are thinking of adding a new package to this framework, you should first
read the
[Delphix Open-Source Policy](https://docs.delphix.com/en/ip-strategy/outbound-open-source).

### Third-party package

#### Step 1. Pick a name for the package

If the package is already provided by Ubuntu, it's recommended to use the source
package as the package name. You can get the source package name for a given
package by running:

```
sudo apt update
sudo apt show <package name> | grep Source
```

It is possible that the source package is not provided and so the command above
will not return anything, in which case you can use `<package name>` as the name
of the package.

Once you've decided on a package name (we shall refer to it as `<package>`),
create a directory for it: `packages/<package>/`.

#### Step 2. Create stub for config.sh

Next step is to create a new file: `packages/<package>/config.sh`. You can copy
the template from [template/config.sh](./template/config.sh). To get started, all
we need to provide is info on where to fetch the upstream source code from.

If you are using an Ubuntu source package, you'll only need to specify the name
of the source package:

```
UPSTREAM_SOURCE_PACKAGE="<source package name>"
```

If the upstream source code is instead to be retrieved from a git repository,
then you need to provide the git details:

```
UPSTREAM_GIT_URL="<git url>"
UPSTREAM_GIT_BRANCH="<git branch>"
```

#### Step 3. Fetch the upstream source

Note that steps 3 to 5 are most useful when getting a third party package from
an Ubuntu source package. When the third party package is fetched from git,
you may simply fork the upstream repository and add an **upstreams/master**
branch that points to the **master** branch; you can then update
`DEFAULT_PACKAGE_GIT_URL` in config.sh to your forked git repository and skip
to step 6.

You can fetch the upstream source code from an Ubuntu source package by running:

```
cd packages/<package>/tmp/
mkdir source
cd source
apt-get source <upstream-source-package>
cd ..
mv source/"<upstream-source-package>"*/ repo
cd repo
git init
git checkout -b repo-HEAD
git add -f .
git commit -m '<insert commit message here>'
```
TODO: create a command that will run the steps above. It used to be done by
`buildpkg.sh -i`, but this logic has been removed.

#### Step 4. Create a developer repository

The next steps will require you to provide a git repository for your local
version of the package. For development purposes you should create an empty
repository on github, and then put the url into `config.sh`. Note that the URL
should start with `https://`.

e.g.

```
DEFAULT_PACKAGE_GIT_URL="https://github.com/<developer>/<package>"
```

#### Step 5. Push to your developer repository

Next step is to push the upstream code to the newly created repository to your
developer repository. You should push the initial commit to both the **master**
branch and the **upstreams/master** branch.

#### Step 6. Build the package

In this step you'll need to define a few hooks in `config.sh`. In the hooks you
can leverage convenience functions provided by [lib/common.sh](./lib/common.sh).

To build the package you'll most likely need to install some build
dependencies. If that is the case, you should add a [prepare()](#prepare) hook
that will install those build dependencies. For an Ubuntu source package, those
dependencies can be installed by calling
`install_build_deps_from_control_file()`.
For other packages, you can usually find the build dependencies in the project's
README. It is recommended to edit the `debian/control` file of the package
to list the required build dependencies, so that 
`install_build_deps_from_control_file()` can be used. Otherwise, you can also
use the `install_pkgs()` lib function to install packages.

Next step is to add a [build()](#build) hook. It is recommended to use the
`dpkg_buildpackage_default()` function.

Then you'll need to provide the version of the package. For packages created
from an Ubuntu source package, it is advised to use the same version as was set
in the source package. For other packages you can use any version you like (e.g.
`1.0.0`). The version must be provided with:

```
DEFAULT_PACKAGE_VERSION="<version>"
```

Note that if you are using an Ubuntu source package, you should now be ready to
build the package.

For a package that doesn't have a `debian` metadata directory already defined in
its source tree, you'll need to create it, and push the changes to the
**master** branch of your developer repository. See
[Common Steps > Creating debian metadirectory](#creating-debian-metadirectory)
for more details.

Once this is all ready, you can try building the package by running:

```
./buildpkg.sh <package>
```

#### Step 7. Make the package auto-updatable

If you want the package to be automatically updated with upstream (strongly
recommended), you'll need to add the [update_upstream()](#update-upstream-hook)
hook to `config.sh`. You should use the following functions provided by
[lib/common.sh](./lib/common.sh):

* `update_upstream_from_source_package()` if `UPSTREAM_SOURCE_PACKAGE` is set.

* `update_upstream_from_git()` if `UPSTREAM_GIT_URL` & `UPSTREAM_GIT_BRANCH` are
  set.

#### Step 8. Add package to package-lists

See [Common Steps > Add package to package-lists](#add-package-to-package-lists).

#### Step 9. Test your changes

See section [Testing Your Changes](#testing-your-changes).

#### Step 10. Make the package official

See [Common Steps > Make the package official](#make-the-package-official).

#### Step 11. Submit a Pull-Request for your changes to linux-pkg

### In-house package

Steps for adding an in-house package are slightly different than for a
third-party package.

This example assumes that the source code for the project is already present in
a git repository and contains a Makefile with instructions to compile the
project. If the `debian` metadata directory is not in the source tree, see
[Common Steps > Creating debian metadirectory](#creating-debian-metadirectory).

#### Step 1. Create config.sh

We will refer to the name you picked for your package as `<package>`. Make sure
the name doesn't conflict with an existing Ubuntu package.

You'll need to create a new directory: `packages/<package>/` and add a new
`config.sh` file in it. You can copy the template from
[template/config.sh](./template/config.sh).
In `config.sh`, you'll need to define two variables:

* `DEFAULT_PACKAGE_GIT_URL`: the `https://` git URL for the source code of the
  package.

* `DEFAULT_PACKAGE_VERSION`: the version of the package. If unsure, just
  use `1.0.0`.

e.g.:

```
DEFAULT_PACKAGE_GIT_URL="https://delphix.gitlab.com/<user>/<package>"
DEFAULT_PACKAGE_VERSION="1.0.0"
```

#### Step 2. Add package hooks

If your package needs some build dependencies, you'll want to add a
[prepare()](#prepare) hook to `config.sh` which will install those build
dependencies. It is recommended to use the `install_pkgs()` function provided by
[lib/common.sh](./lib/common.sh).
Next step is to add a [build()](#build) hook. It is recommended to use the
`dpkg_buildpackage_default()` function provided by
[lib/common.sh](./lib/common.sh).

Once those hooks are set-up, you can try building your package by running:

```
./buildpkg.sh <package>
```

#### Step 3. Make the package official

See [Common Steps > Make the package official](#make-the-package-official)

#### Step 4. Submit a Pull-Request for your changes to linux-pkg

### Common Steps

Those steps apply to both third-party and in-house packages.

#### Creating debian metadirectory

You can refer to the Debian Maintainer Guide
[here](https://www.debian.org/doc/manuals/maint-guide/dreq.en.html).
Note that packages built by gradle, such as the `delphix-sso-app`, do not
require a debian metadirectory.

#### Add package to package-lists

See the [Package Lists](#package-lists) section for more info.

#### Make the package official

Once your new package builds and has been tested in the product, the next step
is to create an official repository for it.

1. First, you should read
   [Delphix Open-Source Policy](https://docs.delphix.com/en/ip-strategy/outbound-open-source)
   if you haven't already, and provide the necessary info so that a
   `github.com/delphix/<package>` repository can be created for it. You'll need
   to push the **master** branch from your developer repository, as well as the
   **upstreams/master** branch if it is a third-party package. Note that if you
   have modified **master** (i.e. it diverges from **upstreams/master**), you
   should submit your changes for review before pushing them.

1. If this is a third-party package that is to be auto-updated by Delphix
   automation, you should also make sure the `github.com/delphix-devops-bot`
   user is added as a collaborator to the repository.

1. Update `DEFAULT_PACKAGE_GIT_URL` in `packages/<package>/config.sh` to the
   official repository.

## Testing your changes

### Testing changes to an existing package

If you are not making any changes to linux-pkg, only changes to a given
package managed by linux-pkg:

1. Run `git-ab-pre-push` from your package's repository.

TODO: complete section

### Testing changes to linux-pkg

TODO: complete section

## Package Lists

Package lists are basically just lists of packages defined in linux-pkg.
They are mainly consumed by the Jenkins build infrastructure by calling
the [./query-packages.sh](./query-packages.sh) utility. Jenkins needs to know
which packages to build and include for a given version of the Delphix
appliance.

Package lists are stored under [./package-lists](./package-lists), in two
sub-directories: `build` and `update`. The `build` directory contains packages
that are built and consumed by the Delphix Appliance, while the `update`
directory contains a list of packages that are automatically synced with
the upstream projects.

There are two physical `build` lists:

* `main.pkgs`: this is the default list for packages that are to be added to the
  Delphix Appliance.

* `kernel-modules.pkgs`: this list is similar to the `main` list but contains
  packages that have a dependency on the multiple flavours of the linux kernel
  that are supported by the Delphix Appliance.

There's also a virtual build list, called "linux-kernel", which lists all the
linux kernel packages built by linux-pkg (one for each supported flavour of
the linux kernel). You can list the contents of the virtual list by running:

```
./query-packages.sh list linux-kernel
```

There is a single `update` list called `main.pkgs`, which contains all the
packages that are auto-updated nightly by Jenkins. Note that zfs is not in
that list as it has a dedicated Jenkins job that tracks the upstream
repository and launches as soon as there are new changes.

Most third-party packages should have an `update_upstream()` hook defined and
be added to that list.

## Versions and Branches

The framework is designed in a way to allow easy integration with the Delphix
release process. The idea is that both the package build artifacts (`.deb`s
and `.ddeb`s) and package source code should be available for each Delphix
release. This should hold for both in-house and third-party packages.

Regarding the build artifacts, those should be taken care of by the existing
Delphix build artifacts storage policy, available
[here](https://docs.google.com/document/d/1-u_l9tLMQaYDOGlwfjhZf9O2pPcmOCVEoOWCi9CxM_A/view).
The relevant code for managing the build artifacts is outside of the scope of
this project and lies in the `devops-gate`.

Regarding the source code, we expect that each package repository and the
linux-pkg repository itself follows the Delphix branching policy outlined
[here](https://docs.delphix.com/pages/viewpage.action?spaceKey=RE&title=New+Branching+Mechanism).
When creating a new branch or release for the Delphix Appliance, an external
script should create the relevant branch or tag for each repository. The
branch or tag should then be passed to the build in the `DEFAULT_GIT_BRANCH`
environment variable.

### Future work

When building packages for an older version of the Delphix Appliance, the build
image will need to be picked accordingly. We are currently using
`bootstrap-18-04`, but this will not be the case anymore once we switch to a
newer Ubuntu distribution.

## Contributing

All contributors are required to sign the Delphix Contributor Agreement prior
to contributing code to an open source repository. This process is handled
automatically by [cla-assistant](https://cla-assistant.io/). Simply open a pull
request and a bot will automatically check to see if you have signed the latest
agreement. If not, you will be prompted to do so as part of the pull request
process.

This project operates under the [Delphix Code of
Conduct](https://delphix.github.io/code-of-conduct.html). By participating in
this project you agree to abide by its terms.

## Statement of Support

This software is provided as-is, without warranty of any kind or commercial
support through Delphix. See the associated license for additional details.
Questions, issues, feature requests, and contributions should be directed to
the community as outlined in the [Delphix Community
Guidelines](http://delphix.github.io/community-guidelines.html).

## License

This is code is licensed under the Apache License 2.0. Full license is available
[here](./LICENSE).
