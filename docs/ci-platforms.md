# iOS support and CI baselines

Sealbreak supports the current iOS major release and the previous major release. The minimum deployment target is therefore advanced once per iOS major release, not for minor or patch releases.

The current support window is iOS 26 and iOS 27, with `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.

## Integration baselines

The real OpenBao and Vault integration tests run on both supported iOS generations.

| Support lane | Runner | Xcode | iOS runtime | Simulator |
| --- | --- | --- | --- | --- |
| Previous | `macos-26` | 26.6 | 26.5 | iPhone 17 |
| Current | `xcode-27` | 27.0 | 27.0 | iPhone 18 Pro |

CI selects the preinstalled Xcode directly through `DEVELOPER_DIR`. No third-party Xcode setup action or runtime download is required.

The integration script receives exact CoreSimulator runtime and device type identifiers. It fails before creating a simulator when the configured Xcode path, runtime, or device type is no longer available on the selected GitHub runner.

## Updating the baselines

Patch releases within a pinned Xcode minor line do not require a repository change when GitHub keeps the same major/minor alias. Minor Xcode or iOS runtime updates are deliberate CI baseline changes and should be reviewed in a pull request after confirming the combination is installed on the selected runner.

When a new iOS major release becomes the supported current generation:

1. Move the support window forward by one major release.
2. Raise `IPHONEOS_DEPLOYMENT_TARGET` to the new previous major release.
3. Replace the previous/current entries in the integration matrix with runner-provided Xcode, runtime, and device combinations.
4. Run both OpenBao and Vault integration tests on both support lanes before merging.

For example, moving from iOS 26/27 to iOS 27/28 raises the deployment target from 26.0 to 27.0 and replaces the two CI platform entries accordingly.
