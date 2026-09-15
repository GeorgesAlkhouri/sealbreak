#!/usr/bin/env python3
"""Convert llvm-cov's line counts for Models.swift to Sonar generic coverage.

Only the host-tested file gets coverage. Untested iOS sources remain in Sonar's
scope; this report must not be advertised as whole-app coverage.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def convert(text: str) -> ET.Element:
    root = ET.Element("coverage", version="1")
    file = ET.SubElement(root, "file", path="Sealbreak/Models.swift")
    lines = {}
    for row in text.splitlines():
        match = re.match(r"^\s*(\d+)\|\s*(\d+(?:\.\d+)?(?:[kMGT])?)\|", row)
        if not match:
            continue  # Comments, blank counts and headers are not executable lines.
        number = int(match[1])
        covered = float(match[2].rstrip("kMGT")) > 0
        if number <= 0 or number in lines:
            raise ValueError("Expected one coverage listing for Models.swift, with unique positive line numbers")
        lines[number] = covered
    if not lines:
        raise ValueError("No executable lines found; refusing to upload empty coverage")
    for number, covered in sorted(lines.items()):
        ET.SubElement(file, "lineToCover", lineNumber=str(number), covered=str(covered).lower())
    return root


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: coverage.py coverage.txt coverage.xml")
    try:
        root = convert(Path(sys.argv[1]).read_text())
        ET.indent(root)
        ET.ElementTree(root).write(sys.argv[2], encoding="utf-8", xml_declaration=True)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
