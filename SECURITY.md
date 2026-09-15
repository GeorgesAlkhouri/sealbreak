# Prototype security notes

This prototype implements the design direction from [Issue #1](https://github.com/GeorgesAlkhouri/sealbreak/issues/1). It is not a production security approval and does not claim that the risk targets in the issue have been demonstrated on a real device.

## Implemented controls

| Issue control | Prototype behavior |
| --- | --- |
| M01 | Share and authoritative target live in one device-bound Keychain record using `WhenPasscodeSetThisDeviceOnly` and `biometryCurrentSet`; Keychain sync is disabled. |
| M02 | New `LAContext` for each sensitive operation, biometric-only policy, no stored authorization session and no app passcode fallback. |
| M03 | HTTPS-only profile, system certificate and hostname validation, TLS 1.2 minimum, all redirects blocked. |
| M04 | The target stored with the share is compared to the displayed profile immediately before submission. Target editing is not available while a share exists. |
| M05 | Preflight status, one app-level share submission, separate status verification, no automatic retry, no reset/migration/init/seal calls. |
| M06 | No analytics, request logging, share export or persistent URL cache. Server error bodies are never displayed. |
| M07 | Masked explicit input or paste only; no clipboard API reads or automated imports. |
| M08 | Share replacement updates the Keychain item in place. Replacement and local removal require fresh Face ID. |
| M09 | Independent recovery is explicitly required by the workflow and documentation; server-side rotation remains an operator procedure. |
| M10 | One stable per-node target; VPN, DNS, TLS proxy and server hardening remain deployment responsibilities. |
| M11 | No third-party libraries or build scripts. Signing-account and developer-workstation security remain outside the app. |
| M12 | Only coarse transient user messages; no persistent operator audit trail and no claim of server-verifiable human attribution. |

## Remaining high-value risks

A compromised iPhone runtime, debugger, malicious build, compromised update, or code execution inside the app process can read a share while it is legitimately used. Keychain protects the secret at rest; it cannot keep the Shamir share out of process memory while the app serializes and transmits it.

A legitimate OpenBao endpoint or TLS-terminating proxy that is already compromised receives the share after a completely valid Face ID authorization. Certificate validation and target binding authenticate the endpoint name and transport, not the integrity of the host.

A Shamir share is reusable. Face ID is local authorization, not a one-time proof verified by OpenBao. Deleting the app, removing local data, or losing the iPhone does not revoke a copied share. Suspected disclosure requires the appropriate OpenBao root-key/share rotation procedure for the deployed version.

For a 1-of-1 configuration, one stolen share is the full unseal quorum. For larger thresholds this app stores only its own share; it does not collect or coordinate the full quorum.

The import source, clipboard history, password manager, screenshots, other devices and independent recovery copies remain outside app control. Swift and networking frameworks can retain transient copies; guaranteed memory zeroization is not claimed.

## Before a valuable share is used

Validate the app on a physical iPhone and an isolated test OpenBao instance. Exercise Face ID denial and re-enrollment, passcode changes, local removal and replacement, target-profile tampering, invalid certificates, redirects, timeouts after submission, foreground/background transitions and recovery without the original phone. Inspect app, proxy and server diagnostics for accidental request-body disclosure.

Do not put real unseal shares, signing material, tokens or unredacted request bodies into public issues.
