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

- [ ] Resolve the exact release build dependency graph from the Xcode and Swift Package Manager lockfiles.
- [ ] Distinguish shipped/runtime code from build-time tools, macros and tests. Do not treat all Package.resolved entries as shipped runtime code.
- [ ] Check each shipped component's actual license, copyright and notice files at the resolved revision, including transitive components and bundled assets.
- [ ] Include all notices and full license texts required by those licenses in the distributed product, in addition to the GitHub repository.
- [ ] Check attribution and trademark conditions for OpenBao, Vault and any other branding separately.
- [ ] Re-evaluate the third-party set and license compatibility for the proprietary Premium build. The Sealbreak CLA does not grant rights over third-party dependencies.
- [ ] If Free and Premium share an App Store binary, evaluate the license of the entire distributed binary. Do not assume that putting premium code in a private repository makes that code exempt from GPL obligations in a GPL-distributed combined work.
- [ ] Keep the software bill of materials (SBOM) separate from the human-readable copyright and licensing notices.

## Release evidence

- [ ] Record release tag and commit, source URL, package revisions and the notices delivered to users.
- [ ] Confirm the actual App Store/TestFlight binary matches the recorded source and notices.
- [ ] Obtain legal review before declaring the GPL/App Store/CLA combination cleared.

## Sources of the approach

- [Nextcloud iOS App Store exception](https://github.com/nextcloud/ios/blob/master/COPYING.iOS)
- [Harmony Contributor Agreements (Individual and Entity, Option Five)](https://www.harmonyagreements.org/agreements)
- [Apple: custom end-user license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement)
- [Apple: minimum end-user license terms](https://www.apple.com/legal/internet-services/itunes/dev/minterms/)
