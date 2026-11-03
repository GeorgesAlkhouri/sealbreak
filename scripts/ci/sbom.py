#!/usr/bin/env python3
"""Build the CycloneDX SBOM of a release IPA from the resolved Swift packages.

The script fails when a checkout is missing, is not at its resolved revision, or
has a license it does not recognize, so an incomplete SBOM cannot reach a release.
Packages excluded in license_plist.yml are not shipped in the app and get the
scope "excluded".
"""

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import uuid

LICENSE_FILE = re.compile(r"(?i)^(license|licence|copying)(\.\w+)?$")

# First match wins, so the exception comes before plain Apache 2.0.
LICENSES = (
    (re.compile(r"Runtime Library Exception"), "Apache-2.0 WITH Swift-exception"),
    (re.compile(r"Apache License\s+Version 2\.0"), "Apache-2.0"),
    (re.compile(r"Permission is hereby granted, free of charge"), "MIT"),
)


def license_expression(checkout):
    """Return the SPDX expression of a checkout, or None when it is not recognized."""
    paths = [p for p in sorted(checkout.iterdir()) if LICENSE_FILE.match(p.name)]
    text = "\n".join(path.read_text() for path in paths)
    return next((spdx for pattern, spdx in LICENSES if pattern.search(text)), None)


def checkout_revision(checkout):
    return subprocess.run(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    ).stdout.strip()


def component(pin, excluded, checkouts, errors):
    location = pin["location"].rstrip("/").removesuffix(".git")
    name = location.rsplit("/", 1)[-1]
    state = pin["state"]
    version, revision = state.get("version"), state["revision"]
    checkout = checkouts / name

    if not checkout.is_dir():
        errors.append(f"{name} has no checkout in {checkouts}.")
        return None
    if checkout_revision(checkout) != revision:
        errors.append(f"{name} is not checked out at its resolved revision {revision}.")
    spdx = license_expression(checkout)
    if spdx is None:
        errors.append(f"{name} has no recognized license.")

    purl = f"pkg:swift/{location.removeprefix('https://')}@{version or revision}"
    return {
        "bom-ref": purl,
        "type": "library",
        "name": name,
        "version": version or revision,
        "scope": "excluded" if name in excluded else "required",
        "purl": purl,
        "licenses": [{"expression": spdx}],
        "externalReferences": [{"type": "vcs", "url": location, "comment": revision}],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for name in ("ipa", "resolved", "config", "checkouts", "gemfile-lock", "output"):
        parser.add_argument(f"--{name}", type=pathlib.Path, required=True)
    for name in ("version", "build-number", "commit", "repository", "xcode-version"):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()
    errors = []

    excluded = set(re.findall(r"(?m)^\s*-\s*name:\s*(\S+)\s*$", args.config.read_text()))
    pins = json.loads(args.resolved.read_text())["pins"]
    components = [component(pin, excluded, args.checkouts, errors) for pin in pins]

    fastlane = re.search(r"(?m)^    fastlane \((\S+)\)$", args.gemfile_lock.read_text())
    if fastlane is None:
        errors.append(f"{args.gemfile_lock} does not pin fastlane.")
    if errors:
        for error in errors:
            print(f"::error title=SBOM::{error}")
        return 1

    digest = hashlib.sha256(args.ipa.read_bytes()).hexdigest()
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        # Derived from the IPA, so rebuilding the SBOM of one IPA keeps its identity.
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, 'sha256:' + digest)}",
        "version": 1,
        "metadata": {
            "component": {
                "bom-ref": "sealbreak",
                "type": "application",
                "name": "Sealbreak",
                "version": f"{args.version}+{args.build_number}",
                "hashes": [{"alg": "SHA-256", "content": digest}],
                "externalReferences": [
                    {
                        "type": "vcs",
                        "url": args.repository,
                        "comment": args.commit,
                    }
                ],
            },
        },
        "components": sorted(components, key=lambda item: item["name"]),
        "formulation": [
            {
                "bom-ref": "release-build",
                "components": [
                    {"type": "application", "name": "Xcode", "version": args.xcode_version},
                    {"type": "application", "name": "fastlane", "version": fastlane[1]},
                ],
            }
        ],
    }
    args.output.write_text(json.dumps(bom, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
