#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p reports
# No code changes are made by CI.
# SwiftFormat 0.62.x parses --lint as a flag for the preceding input set.
mint run --silent nicklockwood/SwiftFormat swiftformat Sealbreak Tests Package.swift --lint
mint run --silent realm/SwiftLint swiftlint lint --strict --reporter json > reports/swiftlint.json
python3 - <<'PY'
import json
from pathlib import Path
root = Path.cwd().resolve()
p = Path('reports/swiftlint.json')
issues = json.loads(p.read_text())
for issue in issues:
    issue['file'] = Path(issue['file']).resolve().relative_to(root).as_posix()
p.write_text(json.dumps(issues, indent=2) + '\n')
PY
plutil -lint Sealbreak/Info.plist Sealbreak/PrivacyInfo.xcprivacy Sealbreak.xcodeproj/project.pbxproj
git diff --check
git diff-tree --check HEAD
# The package compiles the actual Models.swift source, not a duplicate implementation.
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
bin=$(swift build --show-bin-path)
xcrun llvm-cov show \
  "$bin/SealbreakCorePackageTests.xctest/Contents/MacOS/SealbreakCorePackageTests" \
  -instr-profile="$bin/codecov/default.profdata" \
  -show-line-counts=true -use-color=false \
  "$PWD/Sealbreak/Models.swift" > reports/coverage.txt
python3 scripts/ci/coverage.py reports/coverage.txt reports/coverage.xml
