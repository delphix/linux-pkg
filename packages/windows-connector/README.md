# windows-connector: manual build/publish process

Unlike most linux-pkg packages, `windows-connector`'s `post-push` Jenkins job does
**not** auto-trigger on every push to `dlpx-app-gate`. It must be triggered manually.

## Why

`windows-connector` changes are infrequent, and the connector source lives in
`dlpx-app-gate` (a repo with heavy, unrelated traffic) rather than in `linux-pkg`
itself. Auto-triggering on every push meant most builds were pure rebuild churn
with no source change, and any real build-health regression showed up
indistinguishably from that noise. Rather than add machinery to tell the two
apart, the trigger is removed and a human decides when to build and publish.

## How the trigger is disabled

`config.sh` sets:

```bash
DEFAULT_PACKAGE_GIT_URL="none"
```

This is read by the shared Job DSL (`devops-gate/jenkins/jobs/linux_pkg_build_package.groovy`)
to disable `post-push`'s push trigger — no devops-gate change was needed for this.
The job's own auto-generated description reflects it: "Triggers are disabled for
this job, so it must be run manually."

Source is still fetched from the real `dlpx-app-gate` repo. Since
`DEFAULT_PACKAGE_GIT_URL="none"` would otherwise make `PACKAGE_GIT_URL` resolve
to `"none"` too, `config.sh` overrides the `fetch()` hook to hardcode the real
URL directly instead of relying on that variable:

```bash
function fetch() {
	PACKAGE_GIT_URL="https://github.com/delphix/dlpx-app-gate.git"
	logmust fetch_repo_from_git
}
```

## Making a connector change and bumping the version

1. Make your change under `appliance/server/connector` or
   `appliance/host/windows` in `dlpx-app-gate`.
2. Bump `project.ext.connectorDebVersion` in
   `appliance/host/windows/build.gradle` — this is the deb packaging version,
   independent of `connectorVersion` (bumped once per release).
3. Merge your `dlpx-app-gate` PR to `develop`.

## Testing before merging to develop

Use `git-ab-pre-push -b windows-connector` from your local `dlpx-app-gate`
checkout. It builds the package (including uncommitted local changes, via an
auto-snapshotted throwaway branch) and chains through combine-packages,
appliance-build, and integration tests — entirely isolated to
`dev-de-images`/`pre-push`-scoped paths. It never touches production
`snapshot-de-images`/`post-push`/`latest`.

## Publishing a new `latest` after merging

Once your change is merged to `develop`, manually trigger the real `post-push`
job so the new artifact gets published to develop's `latest`:

`linux-pkg/develop/build-package/windows-connector/post-push` — click **Build Now**.

## By design

`GIT_HASH`/`BUILD_INFO` published alongside the artifact record the exact
commit that produced it, so package contents can always be mapped back to the
source that generated them. Since builds are now manual, that recorded commit
will lag current `develop` HEAD until someone triggers another build — that's
the intended behavior of build-time provenance tracking, not a defect, and is
unchanged by whether the trigger is automatic or manual.
