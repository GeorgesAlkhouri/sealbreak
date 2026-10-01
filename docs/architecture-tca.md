# TCA architecture

Sealbreak uses The Composable Architecture (TCA) for application and feature state, side effects, dependency injection, cancellation, navigation/presentation state, and reducer testing.

## Why TCA

Sealbreak has a small UI surface but a security-sensitive state machine: seal-server status checks, Face ID, device-bound Keychain access, target binding, share submission, post-submit verification, privacy interruption, setup, recovery, and destructive local-data removal. Centralizing these transitions in reducers prevents views from becoming orchestration objects and makes effects explicit and testable.

## Feature hierarchy

```text
AppFeature
├── PrivacyFeature
├── WelcomeFeature?
├── SetupFeature?
└── HomeFeature?
    ├── ServerDetailsFeature?
    └── ReplaceShareFeature?
```

`AppFeature` is the composition root. It loads the non-secret display profile and selects Welcome, Setup, or Home. `PrivacyFeature` translates scene/capture changes into explicit reducer actions. Home owns operational state and TCA presentation state. Setup and share replacement own their respective workflows.

## Dependency boundary

The local `Sealbreak` package contains two products with disjoint default source directories:

- `SealbreakCore` in `Sources/SealbreakCore` owns reducers, domain models, localized feedback and presentation state, plus host-testable network, Keychain, profile-storage and DNSSEC infrastructure.
- `SealbreakAppModule` in `Sources/SealbreakAppModule` owns SwiftUI views, the Papercut design system, app view helpers and `Infrastructure/Live` iOS adapters. It consumes Core through package access.

The [component model](architecture-modules.puml) records the dependency direction: the Xcode host imports AppModule, AppModule imports Core, and both package targets use the single TCA dependency declared in `Package.swift`. Core has no direct UIKit, SwiftUI or AppModule imports. CI is responsible for enforcing this boundary against the actual Core production sources.

Reducers depend only on `SealbreakClient` in `Sources/SealbreakCore/Dependencies`. Core owns its `DependencyKey` conformance, with both `liveValue` and `testValue` set to the existing fail-closed `unimplemented` value. An omitted live injection therefore cannot accidentally access network, Keychain or biometrics.

`SealbreakRootView` is the sole public app-facing API. It creates and retains `StoreOf<AppFeature>` and explicitly injects `SealbreakClient.live`, supplied by `Sources/SealbreakAppModule/Infrastructure/Live/LiveSealbreakClient.swift`. The Xcode bootstrap stores this root view once as a property, preserving the original Store lifetime. The live adapters retain the existing controller singleton and adapt:

- `SealServerClient` for bounded HTTPS requests with redirects/cookies/cache disabled.
- `KeychainStore` for device-only biometric protected Shamir-share storage.
- `ProfileStore` for non-secret display metadata.
- `LAContext`, `UIApplication`, and scene-capture traits for biometric authorization and foreground/protected-data/screen-capture checks.

Assets, localizations, `Info.plist` and the privacy manifest remain owned by the Xcode app bundle under `Sealbreak/`; package code continues using the existing app-bundle lookups. There is no package resource bundle.

`SealbreakCoreTests` remains under `Tests/SealbreakCoreTests` and uses `@testable import SealbreakCore`. The Xcode integration test target also links and imports Core with `@testable`, rather than compiling duplicate infrastructure sources. Debug testability is enabled; no public Core API is exposed merely for tests. Test doubles such as `ClientSpy` remain under `Tests/` and are injected through `TestStore` overrides. Low-level infrastructure does not import feature reducers.

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

TCA is pinned exactly to **1.26.2** in the single `Package.swift`. Sealbreak uses Swift tools 6.1, Swift language mode 5, and package deployment floors of iOS 26 / macOS 13. The committed Xcode workspace `Package.resolved` remains the canonical pin set; the generated root CLI copy is ignored.

## Views

SwiftUI views render scoped stores and send actions. They do not call the configured seal server, Keychain, Face ID, or persistence APIs directly. Reusable visual components and the Papercut design system remain framework-independent SwiftUI views.
