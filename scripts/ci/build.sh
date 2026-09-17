#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
common=(-project Sealbreak.xcodeproj -scheme Sealbreak
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
  COMPILER_INDEX_STORE_ENABLE=NO
  -skipMacroValidation)
case "${1:-}" in
  simulator)
    xcodebuild "${common[@]}" -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/Simulator \
      build
    ;;
  *) echo 'Usage: build.sh simulator' >&2; exit 2 ;;
esac
