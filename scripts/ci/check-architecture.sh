#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

core_sources=Sources/SealbreakCore
if [[ ! -d "$core_sources" ]]; then
  echo "Core source directory is missing: $core_sources" >&2
  exit 1
fi

source_files=()
while IFS= read -r -d '' source_file; do
  source_files+=("$source_file")
done < <(find "$core_sources" -type f -name '*.swift' -print0)

if [[ "${#source_files[@]}" -eq 0 ]]; then
  echo "No Core production Swift sources were found." >&2
  exit 1
fi

# Include attributed and scoped imports as well as ordinary module imports.
forbidden_import='^[[:space:]]*((@[[:alpha:]_][[:alnum:]_]*|public|package|internal|fileprivate|private)[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|typealias|func|let|var)[[:space:]]+)?(UIKit|SwiftUI|SealbreakAppModule)([[:space:].;]|$)'
status=0
grep -En "$forbidden_import" "${source_files[@]}" || status=$?
if [[ "$status" -eq 0 ]]; then
  echo "Core must not directly import UIKit, SwiftUI or SealbreakAppModule." >&2
  exit 1
fi
if [[ "$status" -ne 1 ]]; then
  exit "$status"
fi

echo "Core architecture imports are valid (${#source_files[@]} sources)."
