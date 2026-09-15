# Sealbreak CI and release policy

This document describes the repository-side continuous integration baseline. Repository/account settings that cannot be committed are called out separately so that a green workflow is not confused with complete external configuration.

## Pull requests and `main`

The `CI` workflow runs for pull requests targeting `main`, pushes to `main`, and manual dispatches. Pull-request runs use concurrency cancellation so an obsolete commit does not keep consuming macOS runners after a newer commit is pushed.

`CI / verify` runs on `macos-26`, selects the Xcode version pinned in `scripts/ci/versions.env`, restores the cache for Mint and the Swift quality tools, and then executes the repository checks in `scripts/ci/check.sh`. The job runs SwiftFormat in lint-only mode, SwiftLint with strict failure behavior, validates Apple property-list files, checks Git whitespace, runs the Swift package model tests with warnings treated as errors, and emits the model coverage report consumed by SonarQube Cloud. It then compiles the complete iOS application in Debug configuration for a generic Simulator destination. The Simulator build is unsigned and is not an installable release artifact.

`CI / security` runs CodeQL for Swift in manual build mode. It compiles an unsigned device Release archive so CodeQL analyzes the app code in a device Release configuration. On pushes to `main`, that already-verified unsigned archive is retained as a short-lived build artifact. It is deliberately not signed, exported, or published as an IPA.

`CI / sonar` runs only after `CI / verify`. It downloads the verified SwiftLint and coverage reports and sends them to SonarQube Cloud. Fork pull requests are rejected by this job because repository secrets are intentionally unavailable to untrusted forks. The workflow does not use `pull_request_target` as a workaround.

`CI / ready` is the aggregate branch-protection gate. It requires actual success from verify, security, and Sonar. A skipped, cancelled, or failed dependency therefore does not silently produce a successful aggregate gate.

## Tool and action pinning

GitHub Actions are pinned to full commit SHAs. Renovate tracks the associated action releases and proposes digest updates. `scripts/ci/versions.env` pins the Xcode and Mint versions used by CI; `Mintfile` pins SwiftLint and SwiftFormat. Renovate is configured to track all of those version sources.

The CI setup deliberately fails if the pinned Xcode application is not present on the selected runner image. There is no automatic fallback to an arbitrary Xcode version because a silent toolchain change makes a security-sensitive build harder to reproduce and audit.

## SonarQube Cloud

The repository contains `sonar-project.properties` with non-secret project metadata and the quality-gate wait policy. The only GitHub repository secret required by the workflow is:

- `SONAR_TOKEN`: a SonarQube Cloud token with permission to analyze `GeorgesAlkhouri_sealbreak`.

The workflow treats the quality gate as blocking. The Sonar configuration consumes SwiftLint JSON and generic coverage XML produced by the verified macOS job. The current coverage intentionally covers only the host-tested `Models.swift`; untested iOS UI, networking, and Keychain code stays in Sonar's source scope rather than being excluded to inflate the percentage.

The CI never prints or stores the Sonar token as an artifact. Contributors from forks can run all secret-free verification and security checks, but a maintainer must move a reviewed change to a trusted branch before the Sonar gate can run with repository secrets.

## Renovate

`renovate.json` is repository configuration only. Renovate itself must still be installed and authorized for the GitHub repository. It is configured for a weekly maintenance window, groups ordinary GitHub Action updates and Swift quality-tool updates, and requires dashboard approval for major versions and Xcode changes.

Renovate must not receive application runtime secrets, OpenBao shares, Apple signing certificates, or the Sonar token. Its required repository access is dependency-maintenance access only.

## Required branch rules

The repository includes `.github/rulesets/main.json` as a reviewable import template. GitHub repository rules are not activated by committing that file. Import or reproduce the template in **Settings → Rules → Rulesets** for `main`.

The intended minimum is:

- pull requests required before merge,
- stale approvals dismissed when new commits are pushed,
- conversations resolved before merge,
- force pushes and branch deletion blocked,
- required status check: `CI / ready`,
- CodeQL code-scanning result required for Swift at `high_or_higher` severity.

The status-check integration ID in the template is intentionally left unset so GitHub can resolve the repository's actual Actions integration during import/configuration.

## Signing and release

The current workflow does not possess Apple signing credentials. CI sets `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, and clears `DEVELOPMENT_TEAM` for automated builds. This is intentional for the prototype.

A future signed release workflow should be separate from pull-request CI and should run from a protected environment. At minimum it should use short-lived or tightly scoped App Store Connect credentials, a dedicated signing certificate/profile strategy, explicit environment approval, and immutable source revision selection. Do not put signing secrets in pull-request workflows.

## Local checks

The model tests can be run with:

```sh
swift test
```

The complete CI quality path additionally requires the tool versions described above. CI is the authoritative execution environment for those pinned checks. Physical-device Face ID and Keychain behavior is not covered by the host tests and must still be validated on an iPhone before treating a prototype build as operationally ready.
