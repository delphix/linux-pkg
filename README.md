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
    * [Package Hooks](#package-hooks)
    * [Package Environment Variables](#package-environment-variables)
    * [Package WORKDIR](#package-workdir)
1. [Adding New Packages](#adding-new-packages)
    * [Third-party package](#third-party-package)
    * [In-house package](#in-house-package)
1. [Testing your changes](#testing-your-changes)
1. [Versions and Branches](#versions-and-branches)
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

### Step 2. Clone this repository

Clone this repository on the build VM.

```
git clone https://github.com/delphix/linux-pkg.git
cd linux-pkg
```

### Step 3. Build all the packages

All you need to do is run `make`. This will run [setup.sh](#setupsh) followed
by [buildall.sh](#buildallsh) and build all the packages in the
[buildall package list](./package-lists/buildall.pkgs).

Packages will be stored in directory `artifacts/`.

## Project Summary

There are two main tasks that are performed by this framework: building all the
required packages so that they can be later included in
[appliance-build](https://github.com/delphix/appliance-build), and keeping each
package up-to-date with its upstream project by updating the appropriate git
branches.

### Building packages

This task is relatively straight forward. Every package that needs to be built
is built and a metapackage is created to make sure that third-party packages
built by this framework will be installed over packages provided by Ubuntu.
You can see section [Scripts > buildall.sh](#buildallsh) below for more details.

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
Ubuntu source package. If changes are detected, we update **upstreams/master**.

The second step is to check if the **master** branch is up-to-date with
**upstreams/master**. If it is already up-to-date, then we are done. If not,
then we attempt merging **upstreams/master** into **master**.

If the merge is successful, then we attempt building the **master** branch. The
merge is considered failed if the build fails, which means that the **master**
branch of the main repository will not be updated.

Note that any updates are pushed independently to the **upstreams/master** and
**master** branches of the Delphix repository for the package.

Although for now we only support auto-updating the **master** branch, the
framework is designed so that other branches could also be auto-updated.

For additional details, you can see section
[Scripts > updateall.sh](#updateallsh) below.

## Scripts

A set of scripts were created in this repository to allow easily building and
updating packages both manually and through automation (e.g. Jenkins).

### setup.sh

Installs dependencies for the build framework. Needs to be run once to configure
the system, before any other scripts.

### buildpkg.sh

Builds a single package. Package name must match a directory under
[packages/](./packages).

```
./buildpkg.sh <package>
```

The build will look at `packages/<package>/config.sh` for instructions on where
to fetch the package from and how build it. The build will be performed in
`packages/<package>/tmp/`, and build artifacts for this package will be stored
in the `artifacts` sub-directory.

`buildpkg.sh` includes additional options. The most common of them is `-u`,
which will update the package with upstream. See section
[Updating Package](#updating-package) for more info.

### buildall.sh

Builds "all" the packages and the metapackage. It actually scans
[package-lists/buildall.pkgs](./package-lists/buildall.pkgs) and builds the
packages listed there by invoking `buildpkg.sh` on each one of them. Once they
are all built, it builds the metapackage, which scans
[package-lists/metapackage.pkgs](./package-lists/metapackage.pkgs) and creates a
dependency on the exact version of the package built. The metapackge is used to
make sure that the packages that are being built by this job are going to be
favored over stock Ubuntu packages, regardless of their version and revision
numbers.

`buildall.sh` was designed to be called by automation, as such it can be
configured by passing various environment variables. See section
[Environment Variables](#environment-variables) for more details.

This job will stop if a package fails to build.

### jenkins-build.sh

This is a wrapper script around `buildall.sh` and `buildpkg.sh` and was designed
to be called by Jenkins. Any environment variables that are passed to
`jenkins-build.sh` are propagated to the child script. In addition,
`jenkins-build.sh` interprets environment variables specified in section
[Environment variables specific to jenkins-build](#environment-variables-specific-to-jenkins-build).

### updateall.sh

Updates all the packages listed in
[package-lists/updateall.pkgs](./package-lists/updateall.pkgs). Here are the
steps for updating one package:

1. Run `buildpkg.sh -u <package>`. This will attempt to update the
   **upstreams/master** branch, and then attempt to merge **upstreams/master**
   into **master**. If changes are detected on **master**, then the package will
   be built. If a package is listed in
   [package-lists/auto-merge-blacklist.pkgs](./package-lists/auto-merge-blacklist.pkgs),
   then `-M` will be passed to `buildpkg.sh` and we will not attempt updating
   **master**.

1. If changes are detected for **upstreams/master** or **master**, push them to
   the default repository for the package (e.g. `github.com/delphix/<package>`).
   This is done by invoking `push-updates.sh` for each branch. Note that
   **upstreams/master** will be updated even if merge with **master** failed,
   allowing developers to later perform the merge manually.

Each package is processed independently, so a failure to update one package
doesn't affect the update of other packages. A report is generated at the end.

`updateall.sh` was designed to be called by automation, as such it can be
configured by passing various environment variables. See section
[Environment Variables](#environment-variables) for more details.

### push-updates.sh

This script pushes branch updates to the default repository for the package. It
should be called after running `buildpkg.sh -u <package>`. The script should be
invoked with:

```
./push-update.sh -u|-m <package>
```

Running it with `-u` will update **upstreams/master** and running it with `-m`
will update **master**.

Note that credentials for a user that has permissions to push to the target
repository must be passed. Passing the `-n` option does a dry-run, meaning that
the target repository won't be updated (`-n` will be passed to `git push`).

## Environment Variables

There's a set of environment variables that can be set to modify the operation
of some of the scripts defined above.

* **DISABLE_SYSTEM_CHECK**: Set to "true" to disable the check that makes sure
  we are running on an Ubuntu Bionic (18.04) system in AWS. Affects all scripts.

* **DRY_RUN**: Set to "true" to prevent `updateall.sh` from updating production
  package repositories. `updateall.sh` will invoke `push-updates.sh` with `-n`.

* **PUSH_GIT_USER, PUSH_GIT_PASSWORD**: Set to the git credentials used to push
  updates to package repositories. Affects `updateall.sh` and `push-updates.sh`.

* **DEFAULT_REVISION**: Default revision to use for packages that do not have a
  revision defined. If not set, it will be auto-generated from the timestamp.
  Applies to `buildpkg.sh` and `buildall.sh`.

* **DEFAULT_BRANCH**: Default git branch to use when fetching a package that
  does not have a branch explicitly defined. If not set, it will default to
  "master". Applies to `buildpkg.sh` and `buildall.sh`.

* **CHECKSTYLE**: Applies to `buildall.sh`. Passes `-c` to `buildpkg.sh` when
  `CHECKSTYLE` is "true" to execute the `checkstyle` hook when building a package.
  See [Package Definition](#package-definition) section for more details about
  the hook.

* **TARGET_PLATFORMS**: Some packages build kernel modules. This specifies which
  kernel versions to build those packages for and accepts a space-separated list
  of values. If the value is a platform, such as "aws" or "generic", then it
  will auto-determine the default kernel version for the provided platform. If
  `TARGET_PLATFORMS` is unset or "default", then it will build for all supported
  platforms.

* **UPDATE_PACKAGE_NAME**: Applies to `updateall.sh` only. If this variable is
  set then `updateall.sh` only updates the package specified by this variable.

* **{PACKAGE}_GIT_URL, {PACKAGE}_GIT_BRANCH, {PACKAGE}_VERSION,
  {PACKAGE}_REVISION**: Can be used to override defaults for a given package.
  `{PACKAGE}` is the package name in upper case with `-` converted to `_`. For
  instance `CLOUD_INIT_GIT_BRANCH=feature1` would set the branch to fetch
  package `cloud-init` from to `feature1`. This is useful when running
  `buildall.sh` to override defaults for multiple packages. Applies to both
  `buildall.sh` and `buildpkg.sh`.

### Environment variables specific to jenkins-build

* **BUILD_ALL**: Applies to `jenkins-build.sh` to determine which script to
  call. By default, or when "true", it calls `buildall.sh`, otherwise it
  calls `buildpkg.sh`. When `BUILD_ALL` is not "true", environment variable
  `SINGLE_PACKAGE_NAME` must be set.

* **SINGLE_PACKAGE_NAME**: When running `jenkins-build.sh`, this is required if
  `BUILD_ALL` is "false" and specifies which package to build. Note that if
  `BUILD_ALL` is "true", then all the packages will be built but other
  `SINGLE_PACKAGE_{*}` parameters mentioned below are used to override the
  defaults for the package.

* **SINGLE_PACKAGE_GIT_URL, SINGLE_PACKAGE_GIT_BRANCH, SINGLE_PACKAGE_VERSION,
  SINGLE_PACKAGE_REVISION**: Applies to `jenkins-build.sh` only. Those are
  equivalent to the `{PACKAGE}_{*}` variables described previously but apply to
  the package passed in `SINGLE_PACKAGE_NAME`. They are added for convenience
  when using Jenkins.

* **CUSTOM_BUILDER_ENV**: Applies to `jenkins-build.sh` only. This is a
  multi-line field that takes one `{PACKAGE}_{*}=value` entry per line and is
  parsed by `jenkins-build.sh` to set the specified `{PACKAGE}_{*}` environment
  variables. This can be used to set any number of `{PACKAGE}_{*}` variables
  from Jenkins.

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
  `https://` URL.

* **DEFAULT_PACKAGE_GIT_BRANCH**: (Optional) Default git branch to use when
  fetching from or pushing to `DEFAULT_PACKAGE_GIT_URL`. If unset, it defaults
  to the value of the environment variable `DEFAULT_BRANCH`, which itself
  defaults to "master".

* **DEFAULT_PACKAGE_VERSION**: (Mandatory) The version of the package is set to
  this value when it is built. **Note:** If this field is not set, then you
  should provide a mechanism in the [build](#build) hook to auto-determine the
  version from the source code.

* **DEFAULT_PACKAGE_REVISION**: (Optional) The revision of the package is set to
  this value when it is built (note that the full version of a package is
  "_VERSION-REVISION_"). If unset, it defaults to value of environment variable
  DEFAULT_REVISION.

* **UPSTREAM_SOURCE_PACKAGE**: (Optional) Third-party packages that have an
  [update_upstream](#update-upstream) hook and are updated from an Ubuntu source
  package should set this to the name of the source package.

* **UPSTREAM_GIT_URL, UPSTREAM_GIT_BRANCH**: (Optional) Third-party packages
  that have an [update_upstream](#update-upstream) hook and are updated from a
  git repository should set this to the upstream git url and branch.

### Package hooks

This is a list of hooks that can be defined for a package. Those are simply bash
functions that are called by `buildpkg.sh`.

#### Prepare

The `prepare()` hook is optional. It is called before calling the build hook and
normally installs the build dependencies for the package.

#### Fetch

The `fetch()` hook is optional, as a default is provided and should be used. It
is called when fetching the source code of the package to build or to update.
The repository is cloned into `packages/<package>/tmp/repo` and checked out as
branch **repo-HEAD**.

#### Build

The `build()` hook is mandatory. It is responsible for building the package and
storing the build products into `packages/<package>/tmp/artifacts/`.

#### Checkstyle

The `checkstyle()` hook is optional. It is called before building the package if
`-c` is provided to `buildpkg.sh`.

#### Update Upstream

The `update_upstream()` hook should only be defined for third party packages
that need to be auto-updated. It is responsible for fetching the latest upstream
source code into branch **upstream-HEAD** of our fetched repository in
`packages/<package>/tmp/repo`. Note that any changes should be rebased on top of
the **upstreams/master** branch. If changes are detected, file
`packages/<package>/tmp/upstream-updated` should be created.

After the `update_upstream()` hook is called, and if changes are detected,
`buildpkg.sh` will proceed to merge the **upstream-HEAD** branch into
**repo-HEAD** and build the resulting code.

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
`linux-pkg/packages/<package>/tmp/`, referred to as `WORKDIR`.

The following sub-directories are created in `WORKDIR`:

* **repo**: where the repository is fetched and built.

* **artifacts**: where the build artifacts are stored.

* **source**: where the source package is fetched when updating upstream from
  a source package.

The following files are used as status indicators in `WORKDIR`:

* **building**: created when package is being built, deleted on success.

* **updating-upstream**: created when updating upstream branch, deleted on
  success.

* **merging**: created when package is being merged with upstream branch,
  deleted on success.

* **upstream-updated**: created if **upstream-HEAD** has updates that should
  be pushed.

* **repo-updated**: created if **repo-HEAD** has updates that should be pushed,
  following a merge.

Finally, when building a package, build info should be stored in the
**build_info** file under `WORKDIR`. To store some default git info,
`store_git_info()` can be called. **build_info** files for each package are
consumed by the [metapackage](./metapackage) when running
[buildall.sh](#buildallsh).

## Adding new packages

When considering adding a new package, the workflow will depend on whether the
package is a [third-party package](#third-party-package) or
[in-house package](#in-house-package).

**Note For Delphix Employees**:
If you are thinking of adding a new package to this framework, you should first
read the
[Delphix Open-Source Policy](https://docs.delphix.com/cto/ip-strategy/outbound-open-source).

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

You can fetch the upstream source code by running:

```
./buildpkg.sh -i <package>
```

This will automatically fetch the code into `packages/<package>/tmp/repo` and
initialize it as a git repository.

#### Step 4. Create a developer repository

The next steps will require you to provide a git repository for your local
version of the package. For development purposes you should create an empty
repository on github, and then put the url into `config.sh`. Note that the URL
should start with `https://`.

e.g.

```
DEFAULT_PACKAGE_GIT_URL="https://github.com/<developer>/<package>"
```

Note that the branch will default to **master** unless
`DEFAULT_PACKAGE_GIT_BRANCH` is also provided.

#### Step 5. Push to your developer repository

Next step is to push the upstream code to the newly created repository using the
`push-update.sh` script. The script will need to be called twice: once for the
**upstreams/master** branch and once for the **master** branch. It will also
prompt you for your git credentials.

```
./push-updates -u <package>
./push-updates -m <package>
```

#### Step 6. Build the package

In this step you'll need to define a few hooks in `config.sh`. In the hooks you
can leverage convenience functions provided by [lib/common.sh](./lib/common.sh).

To build the package you'll most likely need to install some build
dependencies. If that is the case, you should add a [prepare()](#prepare) hook
that will install those build dependencies. For an Ubuntu source package, those
dependencies can be installed by calling `install_source_package_build_deps()`.
For other packages, you can usually find the build dependencies in the project's
README. It is recommended to use the `install_pkgs()` function to install
packages.

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
recommended), you'll need to add the [update_upstream()](#update-upstream) hook
to `config.sh`. You should use the following functions provided by
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

#### Add package to package-lists

* Add the new package to
  [package-lists/buildall.pkgs](./package-lists/buildall.pkgs) so that it is
  built by `buildall.sh`.

* If this is a third-party package that is to be auto-updated by `updateall.sh`,
  it should also be added to
  [package-lists/updateall.pkgs](./package-lists/updateall.pkgs).

* If this is a third-party package that is also provided by Ubuntu, it must be
  added to [package-lists/metapackage.pkgs](./package-lists/metapackage.pkgs) to
  make sure that it is installed instead of the stock Ubuntu package.

* To make sure that the new package is included in the Delphix Appliance by
  appliance-build, it should be added as a dependency to an existing package
  such as `delphix-platform` or `delphix-virtualization`.

#### Make the package official

**Note**: this step only applies to Delphix.

Once your new package builds and has been tested in the product, the next step
is to create an official repository for it.

1. First, you should read
   [Delphix Open-Source Policy](https://docs.delphix.com/cto/ip-strategy/outbound-open-source)
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

### Testing changes to a package

TODO

Temporary instructions available
[here](https://docs.google.com/document/d/1pD0AusWAIbqXalx-B5nhrrHBfMme6wHvJG9c7O_wqb4/view).

### Testing changes to linux-pkg

TODO

Temporary instructions available
[here](https://docs.google.com/document/d/1pD0AusWAIbqXalx-B5nhrrHBfMme6wHvJG9c7O_wqb4/view).

## Versions and Branches

The framework is designed in a way to allow easy integration with the Delphix
release process. The idea is that both the package build artifacts (`.debs`)
and package source code should be available for each Delphix release. This
should hold for both in-house and third-party packages.

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
branch or tag should then be passed to the build in the `DEFAULT_BRANCH`
environment variable.

### Future work

When building packages for an older version of the Delphix Appliance, the build
image will need to be picked accordingly. We are currently using
`bootstrap-18-04`, but this will not be the case anymore once we switch to a
newer Ubuntu distribution.

Regarding auto-update of third-party packages, we'll most likely want to enable
support for other branches than master, especially _stage_ ones. This way we'd
be able to automatically pull in security updates for our third-party packages
that track Ubuntu source packages.

This means that we will also need integration with our Ubuntu package mirrors.
The auto-update process will need to track the proper archive when fetching
source packages.

## Statement of Support

This software is provided as-is, without warranty of any kind or
commercial support through Delphix. See the associated license for
additional details. Questions, issues, feature requests, and
contributions should be directed to the community as outlined in the
[Delphix Community Guidelines](http://delphix.github.io/community-guidelines.html).

## License

This is code is licensed under the Apache License 2.0. Full license is available
[here](./LICENSE).
