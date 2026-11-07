#!/usr/bin/env python3
"""Build the CycloneDX SBOM of a release IPA from the resolved Swift packages.

The script fails when a checkout is missing, is not at its resolved revision, or
has a license it does not recognize, so an incomplete SBOM cannot reach a release.
Packages excluded in license_plist.yml are not shipped in the app and get the
scope "excluded". Only source control packages are supported.

The lockfiles, the commit, the repository, and the Xcode version default to those
of this checkout and of the GitHub Actions run.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import uuid

from swift_packages import excluded_names, package_name

ROOT = pathlib.Path(__file__).resolve().parents[2]

LICENSE_FILE = re.compile(r"(?i)^(license|licence|copying)(\.\w+)?$")

# First match wins, so the exception comes before plain Apache 2.0.
LICENSES = (
    (re.compile(r"Runtime Library Exception"), "Apache-2.0 WITH Swift-exception"),
    (re.compile(r"Apache License\s+Version 2\.0"), "Apache-2.0"),
    (re.compile(r"Permission is hereby granted, free of charge"), "MIT"),
)


class CommandError(Exception):
    """A command could not run or exited with an error."""


def output_of(*command, env=None):
    """Return the standard output of a command, or raise CommandError with its error output."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or f"exit status {error.returncode}"
        raise CommandError(f"{shlex.join(command)}: {detail}") from error
    except OSError as error:
        raise CommandError(f"{shlex.join(command)}: {error}") from error
    return result.stdout.strip()


def license_expression(checkout):
    """Return the SPDX expression of a checkout, or None when it is not recognized."""
    paths = [p for p in sorted(checkout.iterdir()) if p.is_file() and LICENSE_FILE.match(p.name)]
    # Stray non-UTF-8 bytes, such as a Latin-1 copyright sign, must not hide the license text.
    text = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in paths)
    return next((spdx for pattern, spdx in LICENSES if pattern.search(text)), None)


def checkout_revision(checkout):
    """Return the revision checked out in a package checkout, or raise CommandError."""
    # Without the ceiling, a checkout that lost its .git directory would report the
    # revision of an enclosing repository instead of failing.
    env = {**os.environ, "GIT_CEILING_DIRECTORIES": str(checkout.resolve().parent)}
    return output_of("git", "-C", str(checkout), "rev-parse", "--verify", "HEAD", env=env)


def component(pin, excluded, checkouts, errors):
    if pin.get("kind") != "remoteSourceControl":
        errors.append(
            f"{pin['identity']} is a {pin.get('kind')} package. "
            "The SBOM supports only remote source control packages."
        )
        return None
    location = pin["location"].rstrip("/").removesuffix(".git")
    name = package_name(location)
    state = pin["state"]
    version, revision = state.get("version"), state["revision"]
    checkout = checkouts / name

    if not checkout.is_dir():
        errors.append(f"{name} has no checkout in {checkouts}.")
        return None
    try:
        head = checkout_revision(checkout)
    except CommandError as error:
        errors.append(f"The checked-out revision of {name} cannot be read. {error}")
    else:
        if head != revision:
            errors.append(f"{name} is checked out at {head}, not at its resolved revision {revision}.")
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
    for name in ("ipa", "checkouts", "output"):
        parser.add_argument(f"--{name}", type=pathlib.Path, required=True)
    for name in ("version", "build-number"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument(
        "--resolved",
        type=pathlib.Path,
        default=ROOT / "Sealbreak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    )
    parser.add_argument("--config", type=pathlib.Path, default=ROOT / "license_plist.yml")
    parser.add_argument("--gemfile-lock", type=pathlib.Path, default=ROOT / "Gemfile.lock")
    parser.add_argument("--commit", help="default: HEAD of this checkout")
    parser.add_argument("--repository", help="default: the repository of the GitHub Actions run")
    parser.add_argument("--xcode-version", help="default: the version of the selected Xcode")
    args = parser.parse_args()

    if args.repository is None:
        server, repository = os.environ.get("GITHUB_SERVER_URL"), os.environ.get("GITHUB_REPOSITORY")
        if not (server and repository):
            parser.error("--repository is required outside GitHub Actions")
        args.repository = f"{server}/{repository}"
    if args.commit is None:
        args.commit = output_of("git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD")
    if args.xcode_version is None:
        args.xcode_version = output_of("xcodebuild", "-version").splitlines()[0].split()[-1]

    errors = []
    excluded = excluded_names(args.config)
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
    try:
        sys.exit(main())
    except CommandError as error:
        print(f"::error title=SBOM::{error}")
        sys.exit(1)
