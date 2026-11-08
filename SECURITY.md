# Security Policy

## Reporting a vulnerability

Please do not report security issues in public GitHub issues.

Report them privately through [GitHub private vulnerability reporting](https://github.com/GeorgesAlkhouri/sealbreak/security/advisories/new). If you cannot use GitHub, email [security@sealbreak.app](mailto:security@sealbreak.app).

Please include the Sealbreak version, the iOS version, and the steps to reproduce.

Sealbreak is maintained by one person, who will reply as soon as possible. Once a fix is released, the issue is published as a GitHub security advisory. You are credited unless you prefer not to be.

## Supported versions

Fixes ship in the next App Store release. Older versions are not patched.

## Scope

In scope: the Sealbreak iOS app and its release pipeline (signing, SBOM, attestations) in this repository.

Out of scope: vulnerabilities in OpenBao or HashiCorp Vault themselves. Please report those to [OpenBao](https://github.com/openbao/openbao/security/policy) or [HashiCorp](mailto:security@hashicorp.com).

Known risks and accepted trade-offs are documented in the [threat model](THREAT_MODEL.md). Please check it before reporting.

Only test against servers you own, and never include a real unseal share in a report.
