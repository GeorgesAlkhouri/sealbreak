#!/usr/bin/env python3
"""Produce a license inventory for all Swift packages pinned by Xcode.

The inventory includes test and build dependencies. It is not a verified
list of components bundled into an App Store binary.
"""

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
RESOLVED = ROOT / "Sealbreak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
OUTPUT = ROOT / "build/licenses/swift-package-licenses.md"
LICENSE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "LICENCE", "COPYING")
GITHUB = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?")
REVISION = re.compile(r"[0-9a-fA-F]{40}")


def package_repo(location):
    match = GITHUB.fullmatch(location)
    if not match:
        raise ValueError(f"Unsupported package source (manual review required): {location}")
    return f"{match.group(1)}/{match.group(2)}"


def read_license(repo, revision):
    if not REVISION.fullmatch(revision):
        raise ValueError(f"Package {repo} is not pinned to a 40-character Git commit SHA")
    for filename in LICENSE_NAMES:
        url = f"https://raw.githubusercontent.com/{repo}/{revision}/{filename}"
        request = Request(url, headers={"User-Agent": "Sealbreak-Third-Party-Notices"})
        try:
            with urlopen(request, timeout=20) as response:
                source = response.read().decode("utf-8").replace("\r\n", "\n")
            if source.strip():
                return url, source.rstrip("\n")
        except HTTPError as error:
            if error.code == 404:
                continue
            raise RuntimeError(f"Unable to retrieve {url}: HTTP {error.code}") from error
        except (URLError, UnicodeDecodeError) as error:
            raise RuntimeError(f"Unable to retrieve {url}: {error}") from error
    raise RuntimeError(f"No standard license file found at pinned revision of {repo}")


def classify(source):
    heading = source[:250].lower()
    if "mit license" in heading:
        return "MIT"
    if "apache license" in heading and "version 2.0" in heading:
        return "Apache-2.0"
    return "Unclassified (needs manual review)"


def generate(pins):
    lines = [
        "# Swift Package Dependency License Inventory",
        "",
        "Generated from the exact Xcode Package.resolved revisions. This is an",
        "inventory of ALL pinned packages, including possible test-only, macro,",
        "and build-only dependencies. It does not prove these packages are",
        "distributed with the app or replace the required in-app notices.",
        "",
    ]
    seen = set()
    for pin in sorted(pins, key=lambda p: p["identity"]):
        name = pin["identity"]
        if name in seen:
            raise ValueError(f"Duplicate dependency identity: {name}")
        seen.add(name)
        repo = package_repo(pin["location"])
        version = pin["state"].get("version", pin["state"]["revision"][:12])
        url, content = read_license(repo, pin["state"]["revision"])
        lines.extend([
            f"## {name} ({version})",
            "",
            f"Repository: https://github.com/{repo}",
            "",
            f"License file at pinned revision: {url}",
            "",
            f"Classification: {classify(content)}",
            "",
            "### Original license text",
            "",
        ])
        for line in content.split("\n"):
            lines.append("    " + line if line else "")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    try:
        pins = json.loads(RESOLVED.read_text(encoding="utf-8"))["pins"]
        report = generate(pins)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
        print(f"Generated {args.output} from {len(pins)} locked Swift packages")
        return 0
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"License inventory generation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
