#!/usr/bin/env python3
"""Check the App Store texts in fastlane/metadata against the App Store Connect limits.

Every locale folder is checked, so new localizations are covered without changes here.
Texts are counted without surrounding whitespace, because the repository requires a
trailing newline in every file. A missing optional file is skipped; name.txt is required.
"""

import argparse
import pathlib
import re
import sys

LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotional_text": 170,
    "description": 4000,
    "release_notes": 4000,
}

# Folders in fastlane/metadata that hold no localized store texts.
NON_LOCALE_FOLDERS = {"review_information", "trade_representative_contact_information"}


def read(path):
    return path.read_text(encoding="utf-8").strip() if path.is_file() else None


def keyword_errors(keywords, name, subtitle):
    """Return problems with the keyword list that App Store Connect accepts silently."""
    errors = []
    if re.search(r"\s", keywords):
        errors.append("keywords must be separated by commas without spaces")
    terms = [term.strip().lower() for term in keywords.split(",")]
    if any(not term for term in terms):
        errors.append("keywords contain an empty entry")
    duplicates = sorted({term for term in terms if terms.count(term) > 1})
    if duplicates:
        errors.append(f"keywords repeat {', '.join(duplicates)}")
    # Words in the name and subtitle are already indexed, so repeating them wastes characters.
    indexed = set(re.findall(r"[a-z0-9]+", f"{name} {subtitle or ''}".lower()))
    repeated = sorted(set(terms) & indexed)
    if repeated:
        errors.append(f"keywords repeat words from the name or subtitle: {', '.join(repeated)}")
    return errors


def check_locale(folder):
    texts = {key: read(folder / f"{key}.txt") for key in LIMITS}
    rows, errors = [], []
    if texts["name"] is None:
        errors.append(f"{folder.name}: name.txt is missing")
    for key, limit in LIMITS.items():
        text = texts[key]
        if text is None:
            continue
        rows.append((folder.name, key, len(text), limit))
        if not text:
            errors.append(f"{folder.name}/{key}.txt is empty")
        elif len(text) > limit:
            errors.append(f"{folder.name}/{key}.txt has {len(text)} characters, the limit is {limit}")
    if texts["keywords"] and texts["name"] is not None:
        problems = keyword_errors(texts["keywords"], texts["name"], texts["subtitle"])
        errors += [f"{folder.name}: {problem}" for problem in problems]
    return rows, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--metadata", type=pathlib.Path, default=pathlib.Path("fastlane/metadata"))
    args = parser.parse_args()

    locales = []
    if args.metadata.is_dir():
        locales = sorted(
            path
            for path in args.metadata.iterdir()
            if path.is_dir() and path.name not in NON_LOCALE_FOLDERS
        )
    if not locales:
        sys.exit(f"No locale folders found in {args.metadata}")

    rows, errors = [], []
    for folder in locales:
        locale_rows, locale_errors = check_locale(folder)
        rows += locale_rows
        errors += locale_errors

    for locale, key, count, limit in rows:
        print(f"{locale:<8} {key:<17} {count:>5} / {limit}")
    sys.stdout.flush()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
