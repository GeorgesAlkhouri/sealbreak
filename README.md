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
  <a href="https://sealbreak.app/beta">
    <img src="design/readme/join-beta.svg" width="560" alt="Join the Sealbreak public beta on TestFlight">
  </a>
</p>

<table align="center">
  <tr>
    <th align="center">Set up once</th>
    <th align="center">Approve with Face ID</th>
    <th align="center">Check the result</th>
  </tr>
  <tr>
    <td align="center">
      <img src="design/readme/screenshots/framed/protect-your-share.webp" width="250" alt="Sealbreak setup with a Shamir share added and the Protect with Face ID button.">
    </td>
    <td align="center">
      <img src="design/readme/screenshots/framed/sealed.webp" width="250" alt="Sealbreak showing a sealed OpenBao server and the Unseal with Face ID button.">
    </td>
    <td align="center">
      <img src="design/readme/screenshots/framed/unsealed.webp" width="250" alt="Sealbreak showing an unsealed OpenBao server and the Check status button.">
    </td>
  </tr>
</table>

Sealbreak is a small iOS app for securely storing a Shamir unseal share for OpenBao or HashiCorp Vault on your iPhone and submitting it only after explicit Face ID authorization.

## How it works

Configure your OpenBao server and import an unseal share once. When OpenBao needs to be unsealed, open Sealbreak and tap **Unseal**.

Sealbreak confirms that it is communicating with the configured server before requesting Face ID. Only after successful authorization is the device-bound share released and submitted. The app then checks OpenBao again to confirm the resulting state.

## Security

Sealbreak treats the unseal share as sensitive key material rather than a regular app credential. It remains bound to the device and protected by Face ID, without cloud synchronization or an export path.

Security assumptions, design decisions, and known risks are documented openly in the project's [threat model](THREAT_MODEL.md). It provides the basis for reviewing the security of Sealbreak as the project evolves.


## License

Sealbreak is distributed under the [GNU General Public License version 3](LICENSE) (GPL-3.0-only). Its additional Apple App Store distribution permission is in [COPYING.iOS](COPYING.iOS). This does not replace the GPL or grant rights over separately licensed third-party components.

Third-party license and attribution information is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Commercial licensing

Code for which the maintainer has sufficient rights may also be offered under separate commercial or proprietary license terms, including in a closed-source Sealbreak Premium product. The open-source Sealbreak version remains available under GPLv3, and third-party licenses still apply.

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Harmony Contributor License Agreements](docs/legal/CLA-INDIVIDUAL.md) before submitting code. The project requires additional licensing rights from contributors to support both GPLv3 and proprietary distribution.
