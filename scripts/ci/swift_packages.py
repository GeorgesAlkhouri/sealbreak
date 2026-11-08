"""Read Swift package names and the LicensePlist exclude list for the CI scripts."""

import re

# The exclude list ends at the next top-level key. Comment lines do not end it.
EXCLUDE_BLOCK = re.compile(r"(?ms)^exclude:[ \t]*\n(.*?)(?=^[^\s#]|\Z)")
EXCLUDED_NAME = re.compile(r"(?m)^\s*-\s*name:\s*(\S+)\s*$")


def package_name(location):
    """Return the name SwiftPM gives the checkout of a package location."""
    return location.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")


def excluded_names(config):
    """Return the package names in the exclude list of a license_plist.yml file.

    Only plain names are supported. Entries under other keys, such as manual, are ignored.
    """
    block = EXCLUDE_BLOCK.search(config.read_text())
    return set(EXCLUDED_NAME.findall(block[1])) if block else set()
