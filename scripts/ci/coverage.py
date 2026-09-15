#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path
from xml.etree.ElementTree import Element, ElementTree, SubElement


def parse_lcov(path: Path) -> dict[str, dict[int, int]]:
    files: dict[str, dict[int, int]] = {}
    current: str | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("SF:"):
            source = Path(raw[3:])
            parts = source.parts
            try:
                index = parts.index("Sealbreak")
                current = "/".join(parts[index:])
            except ValueError:
                current = None
            if current is not None:
                files.setdefault(current, {})
        elif raw.startswith("DA:") and current is not None:
            line, count, *_ = raw[3:].split(",")
            files[current][int(line)] = int(count)
        elif raw == "end_of_record":
            current = None
    return files


def main() -> int:
    if len(sys.argv) < 4:
        raise SystemExit("usage: coverage.py INPUT.lcov OUTPUT.xml SOURCE [SOURCE ...]")

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    requested = sys.argv[3:]
    coverage = parse_lcov(input_path)

    root = Element("coverage", {"version": "1"})
    total = 0
    covered = 0
    uncovered: list[str] = []

    for source in requested:
        lines = coverage.get(source)
        if not lines:
            print(f"coverage error: no executable lines found for {source}", file=sys.stderr)
            return 1
        file_node = SubElement(root, "file", {"path": source})
        for line_number in sorted(lines):
            hit = lines[line_number] > 0
            total += 1
            covered += int(hit)
            if not hit:
                uncovered.append(f"{source}:{line_number}")
            SubElement(
                file_node,
                "lineToCover",
                {"lineNumber": str(line_number), "covered": str(hit).lower()},
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    ElementTree(root).write(output_path, encoding="utf-8", xml_declaration=True)

    percentage = 100.0 * covered / total
    print(f"behavior coverage: {covered}/{total} lines = {percentage:.2f}%")
    if uncovered:
        for location in uncovered:
            print(f"coverage uncovered: {location}", file=sys.stderr)
        print(f"coverage error: {len(uncovered)} behavior line(s) are not covered", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
