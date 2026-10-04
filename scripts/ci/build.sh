#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
common=(-project Sealbreak.xcodeproj -scheme Sealbreak
  -disableAutomaticPackageResolution
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
  COMPILER_INDEX_STORE_ENABLE=NO
  -skipMacroValidation)
case "${1:-}" in
  simulator)
    xcodebuild "${common[@]}" -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/Simulator \
      SWIFT_EMIT_LOC_STRINGS=YES \
      build
    ;;
  codeql)
    xcodebuild "${common[@]}" -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/CodeQL \
      COMPILATION_CACHE_ENABLE_CACHING=NO \
      SWIFT_ENABLE_COMPILE_CACHE=NO \
      SWIFT_USE_INTEGRATED_DRIVER=NO \
      build
    ;;
  *) echo 'Usage: build.sh {simulator|codeql}' >&2; exit 2 ;;
esac
