# Release licensing checklist

Apply this checklist separately to the GPLv3 open-source release, Apple TestFlight/App Store distribution, and any future proprietary Sealbreak Premium product. A repository license file alone does not establish distribution compliance.

## Source and copyright

- [ ] Verify who holds copyright in the app code, including material introduced before the CLA was adopted.
- [ ] Verify that every relevant rights holder has authorized the App Store exception or another sufficient licensing arrangement.
- [ ] Confirm that all new copyright-bearing contributions have recorded, valid CLA acceptance. The CLA is not retroactive.
- [ ] Keep the unmodified GPLv3 license, the additional App Store permission and required notices with the relevant distribution.
- [ ] Publish complete corresponding source for the precise shipped GPL release, including applicable build instructions and license text, in a channel not subject to restrictive App Store terms.

## Apple distribution

- [ ] Review the Apple Developer Program terms and App Store license requirements for the intended release.
- [ ] Validate coverage of TestFlight separately where relevant; do not assume an App Store exception resolves every TestFlight restriction.
- [ ] Check the standard or custom End User License Agreement in App Store Connect against GPL permissions and Apple's required minimum terms.
- [ ] Confirm the appropriate copyright holders have authorized the exception as applied to the distributed release.

## Third-party components

- [ ] Confirm CI regenerated `THIRD_PARTY_NOTICES.md` from the release toolchain's resolved package sources and that its contents match the checked-in file.
- [ ] Resolve the exact release build dependency graph with the release Xcode version. With Swift 6.3, IssueReporting is provided by `xctest-dynamic-overlay` 1.13.1; newer manifests/toolchains use the separate `swift-issue-reporting` package. Do not combine resolutions from different toolchains.
- [ ] Distinguish shipped/runtime code from build-time tools, macros and tests. Do not treat all Package.resolved entries as shipped runtime code.
- [ ] Check each shipped component's actual license, copyright and notice files at the resolved revision, including transitive components and bundled assets.
- [ ] Include all notices and full license texts required by those licenses in the distributed product, in addition to the GitHub repository.
- [ ] Check attribution and trademark conditions for OpenBao, Vault and any other branding separately.
- [ ] Re-evaluate the third-party set and license compatibility for the proprietary Premium build. The Sealbreak CLA does not grant rights over third-party dependencies.
- [ ] If Free and Premium share an App Store binary, evaluate the license of the entire distributed binary. Do not assume that putting premium code in a private repository makes that code exempt from GPL obligations in a GPL-distributed combined work.
- [ ] Keep the software bill of materials (SBOM) separate from the human-readable copyright and licensing notices.

## Notice generation

The existing iOS CI job runs LicensePlist from a SHA-256-verified portable download after resolving the Xcode lockfile. Renovate tracks the adjacent version and checksum in `ci.yml` together using its `github-release-attachments` datasource; tool updates follow the existing seven-day release-age and automerge rules. LicensePlist reads the downloaded package sources locally, excludes the test and host-tool packages listed in `license_plist.yml`, and combines the original software license texts with `docs/licenses/third-party-notices-header.md`. The complete `THIRD_PARTY_NOTICES.md` is uploaded as a CI artifact. There is no separate generator script or license workflow.

For Renovate PRs in this repository, a separate job commits changed notices to the same PR branch and requests CI and dependency review for the new commit. `CI / ready` rejects the older revision while its notices differ. For other PRs, commit the generated artifact when CI reports notice drift. Identical output causes no commit or additional CI run.

Edit the header for asset attributions or additional notices and review exclusions when dependencies change. LicensePlist reads a package's license file; separate upstream `NOTICE` or other attribution files still need review and, where required, inclusion in the manual header. The generated file must still be bundled and made available in the app before distribution. Generation does not establish which code is present in an archived release, produce an SBOM, or constitute legal clearance.

## Release evidence

- [ ] Record release tag and commit, source URL, package revisions and the notices delivered to users.
- [ ] Confirm the actual App Store/TestFlight binary matches the recorded source and notices.
- [ ] Obtain legal review before declaring the GPL/App Store/CLA combination cleared.

## Sources of the approach

- [Nextcloud iOS App Store exception](https://github.com/nextcloud/ios/blob/master/COPYING.iOS)
- [Harmony Contributor Agreements (Individual and Entity, Option Five)](https://www.harmonyagreements.org/agreements)
- [Apple: custom end-user license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement)
- [Apple: minimum end-user license terms](https://www.apple.com/legal/internet-services/itunes/dev/minterms/)
