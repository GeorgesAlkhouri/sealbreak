# TCA architecture

Sealbreak uses The Composable Architecture (TCA) for application and feature state, side effects, dependency injection, cancellation, navigation/presentation state, and reducer testing.

## Why TCA

Sealbreak has a small UI surface but a security-sensitive state machine: seal-server status checks, Face ID, device-bound Keychain access, target binding, share submission, post-submit verification, privacy interruption, setup, recovery, and destructive local-data removal. Centralizing these transitions in reducers prevents views from becoming orchestration objects and makes effects explicit and testable.

## Feature hierarchy

```text
AppFeature
├── PrivacyFeature
├── SetupFeature?
└── HomeFeature?
    ├── ServerDetailsFeature?
    └── ReplaceShareFeature?
```

`AppFeature` is the composition root. It loads the non-secret display profile and selects Setup or Home. `PrivacyFeature` translates scene/capture changes into explicit reducer actions. Home owns operational state and TCA presentation state. Setup and share replacement own their respective workflows.

## Dependency boundary

Reducers depend only on `SealbreakClient`, registered through TCA `DependencyValues`. The live dependency adapts the existing infrastructure:

- `SealServerClient` for bounded HTTPS requests with redirects/cookies/cache disabled.
- `KeychainStore` for device-only biometric protected Shamir-share storage.
- `ProfileStore` for non-secret display metadata.
- `LAContext` and foreground/protected-data/screen-capture checks for authorization.

The low-level infrastructure does not import feature reducers.

## Sensitive drafts

Shamir share text is deliberately **not** stored in long-lived TCA state. It remains local SwiftUI `@State` in the setup/replacement forms and is cleared when the app becomes non-active or screen capture starts. Only an explicit save action transfers the draft into a reducer effect, where mutable copies are cleared after use.

This is the intentional exception to global feature state: transient secrets have the narrowest possible lifetime and ownership.

## Unseal state machine

The Home reducer preserves the security ordering:

1. Check the configured target.
2. Require an initialized Shamir seal and a sealed node.
3. Require fresh Face ID before the protected share is read.
4. Verify the protected record is bound to the currently configured target.
5. Re-check foreground/protected-data/capture conditions.
6. Submit exactly one share; never retry automatically.
7. Verify seal status after submission.
8. If anything fails after submission begins, mark the final outcome as unknown and require a fresh status check before retry.

Privacy interruption cancels the reducer effect, invalidates the active biometric context, clears status, and dismisses sensitive presentation state.

## Dependency version

TCA is pinned to **1.26.1**, whose package manifest uses Swift tools 6.1 and supports iOS 16+ / macOS 13+. Pinning keeps dependency resolution reproducible for the repository's Xcode 26 CI environment.

## Views

SwiftUI views render scoped stores and send actions. They do not call the configured seal server, Keychain, Face ID, or persistence APIs directly. Reusable visual components and the Papercut design system remain framework-independent SwiftUI views.
