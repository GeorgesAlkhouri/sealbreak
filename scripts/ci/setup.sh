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
printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "${GITHUB_ENV:?GitHub Actions environment is required}"

# The security job only needs Xcode; avoid installing lint/format tools there.
if [[ "${1:-}" == "xcode-only" ]]; then
  exit 0
fi

# Cacheable, version-pinned quality tools. No user or production secrets are stored here.
tools="$HOME/.cache/sealbreak-tools"
mint_path="$HOME/.cache/sealbreak-mint"
mkdir -p "$tools" "$mint_path"

mint_repo="$tools/Mint"
mint_bin="$mint_repo/.build/release/mint"
if [[ ! -x "$mint_bin" ]]; then
  rm -rf "$mint_repo"
  git clone --depth 1 --branch "$MINT_VERSION" https://github.com/yonaskolb/Mint.git "$mint_repo"
  xcrun swift build --package-path "$mint_repo" --configuration release --product mint
fi

printf '%s\n' "$(dirname "$mint_bin")" >> "$GITHUB_PATH"
printf 'MINT_PATH=%s\n' "$mint_path" >> "$GITHUB_ENV"
