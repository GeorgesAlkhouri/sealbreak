# Sealbreak

Minimal iOS prototype for manually unsealing an OpenBao Shamir seal with a device-bound share protected by Face ID.

> Prototype only. Start with disposable test shares. The security baseline is documented in [THREAT_MODEL.md](THREAT_MODEL.md).

## Build on an iPhone

1. Open `Sealbreak.xcodeproj` with Xcode 16 or newer.
2. Select the **Sealbreak** target and open **Signing & Capabilities**.
3. Keep automatic signing enabled and choose your Apple development team. The current identifier is `com.georgesalkhouri.sealbreak.prototype`; keep your chosen bundle identifier stable after importing shares.
4. Connect an iPhone with Face ID and a device passcode, select it as the run destination, and press **Run**.

Deployment target is iOS 17. The application has no external dependencies. A separate Swift package runs host model tests without changing the iOS target.

## Continuous integration

GitHub Actions runs SwiftFormat, SwiftLint, model tests with coverage, a complete Simulator Debug build, an unsigned device Release archive for CodeQL, and a SonarQube Cloud quality gate. Renovate handles dependency updates. Repository and account configuration such as the Sonar token and branch rules stays outside the codebase; missing required gates fail closed.

Run the model tests locally with `swift test`. They do not replace Face ID/Keychain tests on a physical iPhone.

## MVP behavior

The app stores one Shamir share together with its authoritative server target in iOS Keychain using `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`. Each sensitive action uses a fresh Face ID authorization. There is no app passcode fallback, cloud sync, broker, passkey mode, background unseal, automatic retry, or share export.

Only two OpenBao endpoints are used:

- `GET /v1/sys/seal-status`
- `POST /v1/sys/unseal`

The server profile accepts one direct HTTPS origin such as `https://bao.example.com:8200`. Redirects are blocked. Normal iOS certificate-chain and hostname validation is used and cannot be bypassed from the app. Use a stable per-node endpoint rather than a load balancer that distributes unseal shares between nodes.

Before sending a share the app performs a fresh status check, requires Face ID, reads the protected record, verifies the protected target binding, and submits exactly one share. It then performs another status check before reporting the result. Ambiguous network failures are never automatically retried.

## Recovery and key lifecycle

Keep an independent recovery copy outside this iPhone. Face ID re-enrollment, passcode removal, device loss, or Keychain inaccessibility can make the stored share unusable. Replacing the local share does **not** perform OpenBao rekeying. Removing local data does **not** invalidate a copy that has already leaked elsewhere.

See [THREAT_MODEL.md](THREAT_MODEL.md) for the threat analysis, risk assessment, trust boundaries, and controls.