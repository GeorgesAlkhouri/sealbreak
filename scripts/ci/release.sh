#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

version_file="VERSION"
archive_path="build/Release/Sealbreak.xcarchive"

usage() {
  echo "Usage: release.sh {next-version <patch|minor|major>|archive <version> <build-number>|verify <version> <build-number>}" >&2
  exit 2
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid semantic version: $version" >&2
    exit 2
  fi
}

next_version() {
  local release_type="$1"
  local current
  current="$(tr -d '[:space:]' < "$version_file")"
  validate_version "$current"

  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"

  case "$release_type" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      echo "Invalid release type: $release_type" >&2
      exit 2
      ;;
  esac

  printf '%d.%d.%d\n' "$major" "$minor" "$patch"
}

archive() {
  local version="$1"
  local build_number="$2"

  validate_version "$version"
  if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number: $build_number" >&2
    exit 2
  fi

  rm -rf "$archive_path"

  xcodebuild \
    -project Sealbreak.xcodeproj \
    -scheme Sealbreak \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM= \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -skipMacroValidation \
    archive
}

verify() {
  local expected_version="$1"
  local expected_build_number="$2"
  local info_plist="$archive_path/Products/Applications/Sealbreak.app/Info.plist"

  if [[ ! -f "$info_plist" ]]; then
    echo "Archive Info.plist not found: $info_plist" >&2
    exit 1
  fi

  local actual_version actual_build_number
  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
  actual_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"

  if [[ "$actual_version" != "$expected_version" ]]; then
    echo "Marketing version mismatch: expected $expected_version, got $actual_version" >&2
    exit 1
  fi

  if [[ "$actual_build_number" != "$expected_build_number" ]]; then
    echo "Build number mismatch: expected $expected_build_number, got $actual_build_number" >&2
    exit 1
  fi

  printf 'Archive version verified: %s (%s)\n' "$actual_version" "$actual_build_number"
}

case "${1:-}" in
  next-version)
    [[ $# -eq 2 ]] || usage
    next_version "$2"
    ;;
  archive)
    [[ $# -eq 3 ]] || usage
    archive "$2" "$3"
    ;;
  verify)
    [[ $# -eq 3 ]] || usage
    verify "$2" "$3"
    ;;
  *)
    usage
    ;;
esac
