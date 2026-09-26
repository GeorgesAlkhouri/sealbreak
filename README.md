<p align="center">
  <img src="design/figma/assets/brand/Shield.svg" width="96" alt="Sealbreak logo">
</p>

<h1 align="center">Sealbreak</h1>

<p align="center">
  <strong>Open-source iOS app to securely unseal OpenBao and HashiCorp Vault with Face ID.</strong>
</p>

<p align="center">
  <a href="https://sonarcloud.io/dashboard?id=GeorgesAlkhouri_sealbreak">
    <img src="https://sonarcloud.io/api/project_badges/measure?project=GeorgesAlkhouri_sealbreak&metric=alert_status" alt="SonarQube Cloud Quality Gate">
  </a>
  <a href="https://app.codecov.io/github/GeorgesAlkhouri/sealbreak">
    <img src="https://codecov.io/gh/GeorgesAlkhouri/sealbreak/graph/badge.svg" alt="Codecov">
  </a>
</p>

<p align="center">
  <a href="https://sealbreak.app">Website</a>
  ·
  <a href="THREAT_MODEL.md">Threat Model</a>
</p>

<p align="center">
  <img src="design/figma/screens/Papercut.svg" width="760" alt="Sealbreak paper-cut interface">
</p>

Sealbreak is a small iOS app for securely storing a Shamir unseal share for OpenBao or HashiCorp Vault on your iPhone and submitting it only after explicit Face ID authorization.

## How it works

Configure your OpenBao server and import an unseal share once. When OpenBao needs to be unsealed, open Sealbreak and tap **Unseal**.

Sealbreak confirms that it is communicating with the configured server before requesting Face ID. Only after successful authorization is the device-bound share released and submitted. The app then checks OpenBao again to confirm the resulting state.

## Security

Sealbreak treats the unseal share as sensitive key material rather than a regular app credential. It remains bound to the device and protected by Face ID, without cloud synchronization or an export path.

Security assumptions, design decisions, and known risks are documented openly in the project's [threat model](THREAT_MODEL.md). It provides the basis for reviewing the security of Sealbreak as the project evolves.

> Sealbreak is under active development. Use disposable test shares until a stable release is available.

## License

Sealbreak is licensed under the [GNU General Public License v3.0](LICENSE).
