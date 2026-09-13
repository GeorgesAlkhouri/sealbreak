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
  archive)
    # Separate derived data ensures CodeQL sees an actual device Release compilation.
    xcodebuild "${common[@]}" -configuration Release \
      -destination 'generic/platform=iOS' -sdk iphoneos \
      -derivedDataPath build/Device -archivePath build/Sealbreak.xcarchive archive
    ;;
  *) echo 'Usage: build.sh simulator|archive' >&2; exit 2 ;;
esac
