# Recording snapshot references

Add the `record-snapshots` label to an open PR targeting `main` to record its
snapshot images in CI. The requester must have repository write access, and the
PR branch must belong to this repository. Remove and reapply the label to retry
a failed run; a successful run removes it automatically.

The workflow uses Point-Free SnapshotTesting, Xcode 26.6, and an iPhone 17
Simulator running iOS 26.5 on `macos-26`. Keep these settings aligned with the
hosted iOS tests in `.github/workflows/ci.yml` when updating the toolchain.

Both passes run the entire `SealbreakAppModuleTests` target, including its
non-snapshot tests. Additional snapshot test classes in that target are included
automatically; the workflow has no list of individual classes to maintain.
Recording refreshes all selected references. Only new or changed PNGs are
committed, and existing image changes also need visual review.

The recording pass deliberately reports snapshot failures. The workflow then
restores the original accessibility text references and runs the same suite
again with recording disabled. Only a successful verification makes the PNGs
eligible for publication. Missing recording support or a moved PR head aborts
the update.

A separate job uses `actions/checkout` and standard Git commands to commit only
PNGs under `Tests/SealbreakAppModuleTests/__Snapshots__` to the same PR, following
[GitHub's documented pattern](https://github.com/actions/checkout#push-a-commit-to-a-pr-using-the-built-in-token).
It skips the commit when images are unchanged. A normal push rejects concurrent
branch changes. The job requests the existing CI and dependency checks for the
new commit and links the results from the PR.

Review the PNG changes in GitHub's **Files changed** image viewer before merging.
The recording and verification `.xcresult` bundles are downloadable from the
workflow run for seven days and can be opened in Xcode. Recording produces
candidate references; passing verification does not replace visual review.

## Test integration

Snapshot tests in `SealbreakAppModuleTests` must store their reference images
under `Tests/SealbreakAppModuleTests/__Snapshots__` and allow Point-Free's
`SNAPSHOT_TESTING_RECORD` environment setting while defaulting to `.never`.
Keep the configuration in a shared test helper or XCTest base class so that
additional snapshot classes use the same recording behavior. For the tests
introduced by PR #104, replace the unconditional `.never` override in
`invokeTest()` with:

```swift
let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
    .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:)) ?? .never
withSnapshotTesting(record: record) { super.invokeTest() }
```

The workflow passes this built-in setting through Xcode's `TEST_RUNNER_` prefix:
`all` for recording and `never` for verification. No custom image renderer,
comparator, or image tolerance is added by this workflow. The helper integration
and reference images belong in the PR that introduces the snapshot tests.
Tests that also assert accessibility text must include their reviewed `.txt`
references in that PR; this workflow only publishes image references. Image-only
suites do not require any text reference files.

## Trust boundary

The recording job has read-only repository access, no persisted checkout
credentials, and no supplied repository secrets. The publishing job starts on
a fresh runner, executes no PR scripts, and accepts only the verified PNG
artifact from the same workflow attempt. It checks that the PR is still open at
the recorded SHA before committing.

This affects threat-model boundary TB5 and control M11: CI gains an explicit
path for updating test references. The workflow uses only GitHub-maintained
actions pinned to full commit SHAs and the runner's Git client; no third-party
commit action receives the write token. Image updates remain subject to PR
review. Application behavior and share-handling controls are unchanged.

The workflow is modeled in [snapshot-recording.puml](snapshot-recording.puml).
