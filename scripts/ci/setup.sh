#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/ci/versions.env
export DEVELOPER_DIR="/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Pinned Xcode ${XCODE_VERSION} is not installed on this runner. Update the runner/toolchain together; no silent fallback." >&2
  exit 1
fi
xcodebuild -version
xcrun swift --version
# Select an installed Xcode only; never download an Apple toolchain in a PR.
printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "${GITHUB_ENV:?GitHub Actions environment is required}"

# Exact Mint version; no unversioned Homebrew install. This runner has no user secrets.
tools="${RUNNER_TEMP:?}/sealbreak-tools"
mkdir -p "$tools"
git clone --depth 1 --branch "$MINT_VERSION" https://github.com/yonaskolb/Mint.git "$tools/Mint"
xcrun swift build --package-path "$tools/Mint" --configuration release --product mint
bin=$(xcrun swift build --package-path "$tools/Mint" --configuration release --show-bin-path)
printf '%s\n' "$bin" >> "$GITHUB_PATH"
# Isolate tool builds from app source, coverage and any future release signing job.
printf 'MINT_PATH=%s\n' "$tools/mint" >> "$GITHUB_ENV"
