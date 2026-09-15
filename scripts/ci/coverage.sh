#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

rm -rf build/coverage
mkdir -p build/coverage

swift test --enable-code-coverage -Xswiftc -warnings-as-errors

profile="$(find .build -name default.profdata -type f -print -quit)"
binary="$(find .build -type f -path '*SealbreakCorePackageTests.xctest/Contents/MacOS/SealbreakCorePackageTests' -print -quit)"
if [[ -z "$binary" ]]; then
  binary="$(find .build -type f -name 'SealbreakCorePackageTests' -perm -111 -print -quit)"
fi

if [[ -z "$profile" || -z "$binary" ]]; then
  echo '::error::Unable to locate SwiftPM coverage profile or test binary.'
  exit 1
fi

xcrun llvm-cov export \
  "$binary" \
  -instr-profile "$profile" \
  -format=lcov \
  > build/coverage/coverage.lcov

python3 scripts/ci/coverage.py \
  build/coverage/coverage.lcov \
  build/coverage/sonar.xml \
  Sealbreak/AppModel.swift \
  Sealbreak/Models.swift
