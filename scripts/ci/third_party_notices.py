#!/usr/bin/env python3
"""Build THIRD_PARTY_NOTICES.md from the LicensePlist output and the manual header.

The script fails when a resolved Swift package that is not excluded in
license_plist.yml has no section in the LicensePlist output. LicensePlist
silently skips packages that are not hosted on github.com, so its own
--fail-if-missing-license flag does not catch them. Only plain package names
are supported in the exclude list.

NOTICE files are appended to the license text of their package, because
LicensePlist reads only LICENSE files and Apache 2.0 requires NOTICE contents
to be passed on.
"""

import argparse
import json
import pathlib
import re
import sys

# LicensePlist writes "## [name (version)](source)" for each package. License texts may contain
# their own "## " lines, such as the Runtime Library Exception in swift-collections.
HEADING = re.compile(r"(?m)^## (?P<heading>\[.+\]\((?P<source>https://github\.com/[^)\s]+)\))$\n?")


def repository(url):
    """Return 'owner/name' in lowercase for a GitHub repository URL, or None."""
    match = re.fullmatch(r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?", url.strip())
    return f"{match[1]}/{match[2]}".lower() if match else None


def fenced(text):
    """Keep license text verbatim, so its own headings and markup stay plain text."""
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    fence = "`" * max(3, longest + 1)
    return f"{fence}text\n{text}\n{fence}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for name in ("header", "libraries", "resolved", "config", "checkouts", "output"):
        parser.add_argument(f"--{name}", type=pathlib.Path, required=True)
    args = parser.parse_args()
    errors = []

    excluded = set(re.findall(r"(?m)^\s*-\s*name:\s*(\S+)\s*$", args.config.read_text()))
    expected = {}
    for pin in json.loads(args.resolved.read_text())["pins"]:
        location = pin["location"]
        name = re.sub(r"\.git$", "", location.rstrip("/").rsplit("/", 1)[-1])
        if name in excluded:
            continue
        repo = repository(location)
        if repo is None:
            errors.append(
                f"{location} is not hosted on github.com, so LicensePlist skips it. Add its notice "
                "to docs/licenses/third-party-notices-header.md and exclude it in license_plist.yml."
            )
        else:
            expected[repo] = name

    libraries = args.libraries.read_text()
    headings = list(HEADING.finditer(libraries))
    sections = []
    found = set()
    for index, match in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(libraries)
        repo = repository(match["source"])
        found.add(repo)
        texts = [libraries[match.end() : end].strip("\n")]
        checkout = args.checkouts / expected[repo] if repo in expected else None
        if checkout is not None and checkout.is_dir():
            for path in sorted(checkout.iterdir()):
                if path.is_file() and path.name.upper().startswith("NOTICE"):
                    texts.append(path.read_text().strip("\n"))
        license_text = "\n\n".join(texts)
        sections.append(f"### {match['heading']}\n\n{fenced(license_text)}")

    missing = sorted(set(expected) - found)
    if missing:
        errors.append("LicensePlist produced no notice for: " + ", ".join(missing))
    if errors:
        for error in errors:
            print(f"::error title=Third-party notices::{error}")
        return 1

    # The comment names the header file as the place to edit; it does not belong in the output.
    head = re.sub(r"\A<!--.*?-->\n", "", args.header.read_text(), flags=re.S)
    args.output.write_text(f"{head}\n" + "\n\n".join(sections) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
