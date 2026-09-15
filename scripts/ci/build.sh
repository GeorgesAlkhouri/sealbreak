#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
common=(-project Sealbreak.xcodeproj -scheme Sealbreak
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
  COMPILER_INDEX_STORE_ENABLE=NO)
case "${1:-}" in
  simulator)
    xcodebuild "${common[@]}" -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator \
      -derivedDataPath build/Simulator build
    ;;
  codeql)
    xcodebuild "${common[@]}" -configuration Release \
      -destination 'generic/platform=iOS' -sdk iphoneos \
      -derivedDataPath build/CodeQL \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
      build
    ;;
  *) echo 'Usage: build.sh simulator|codeql' >&2; exit 2 ;;
esac
