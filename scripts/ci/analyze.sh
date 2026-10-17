#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

output=build/SwiftLintAnalyze
pins=Sealbreak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
pins_before="$(shasum "$pins")"
mkdir -p "$output"

build_with_log() {
  local log="$1"
  shift
  echo "Building with $1; log: $log"
  "$@" > "$log" 2>&1 || { tail -n 60 "$log"; return 1; }
}

# Swift-version-specific manifests can add dependencies to the macOS test graph.
# The ignored SwiftPM lockfile starts with the canonical Xcode pins.
cp "$pins" Package.resolved
build_with_log "$output/package-resolve.log" \
  swift package --build-path "$output/SwiftPM" resolve --skip-update
swift package --build-path "$output/SwiftPM" clean
build_with_log "$output/package-build.log" \
  swift build --build-path "$output/SwiftPM" --force-resolved-versions \
  --product SealbreakPackageTests -v

build_with_log "$output/ios-build.log" \
  xcodebuild clean build-for-testing -project Sealbreak.xcodeproj -scheme Sealbreak \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output/DerivedData" \
  -clonedSourcePackagesDirPath build/Simulator/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  COMPILER_INDEX_STORE_ENABLE=NO SWIFT_EMIT_LOC_STRINGS=NO
[[ "$(shasum "$pins")" == "$pins_before" ]] || {
  echo 'Xcode changed Package.resolved; review dependency resolution.' >&2
  exit 1
}

# SwiftLint chooses the first invocation for a shared file: prefer iOS arguments.
# SwiftLint 0.65.1 leaves Xcode's escaped macro-plugin separators untouched.
sed 's/\\#/#/g' "$output/ios-build.log" "$output/package-build.log" > "$output/build.log"
swiftlint analyze --config .swiftlint.yml --strict \
  --compiler-log-path "$output/build.log" 2>&1 | tee "$output/analyze.log"

# SourceKit may emit errors without a failing SwiftLint exit code.
if grep -Eq '(^|: )(error|warning):' "$output/analyze.log"; then
  exit 1
fi
expected="$(find Sealbreak Sources Tests -type f -name '*.swift' | wc -l | tr -d '[:space:]')"
if ! grep -Eq "Done analyzing!.* in $expected files[.]" "$output/analyze.log"; then
  echo "Incomplete analysis: expected $expected app and test files." >&2
  exit 1
fi
