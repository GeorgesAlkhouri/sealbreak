#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

catalog="Sealbreak/Resources/Localizable.xcstrings"
info_catalog="Sealbreak/Resources/InfoPlist.xcstrings"
derived_data="build/Localization"
tmp_dir="$(mktemp -d)"
synced_catalog="$tmp_dir/Localizable.xcstrings"

trap 'rm -rf "$tmp_dir"' EXIT

test -f "$catalog"
test -f "$info_catalog"

rm -rf "$derived_data"

echo "==> Building Sealbreak to emit .stringsdata"
xcodebuild \
  -project Sealbreak.xcodeproj \
  -scheme Sealbreak \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  COMPILER_INDEX_STORE_ENABLE=NO \
  SWIFT_EMIT_LOC_STRINGS=YES \
  -skipMacroValidation \
  build

search_root="$derived_data/Build/Intermediates.noindex"
stringsdata=()
while IFS= read -r file; do
  stringsdata+=("$file")
done < <(
  find "$search_root" \
    -type f \
    -path '*/Sealbreak.build/Objects-normal/*' \
    -name '*.stringsdata' \
    | sort
)

if ((${#stringsdata[@]} == 0)); then
  echo "::error title=Localization extraction failed::No Sealbreak .stringsdata files were produced."
  exit 1
fi

echo "==> Syncing ${#stringsdata[@]} extracted string files"
cp "$catalog" "$synced_catalog"

sync_args=()
for file in "${stringsdata[@]}"; do
  sync_args+=(--stringsdata "$file")
done
xcrun xcstringstool sync "$synced_catalog" "${sync_args[@]}"

if ! diff -u "$catalog" "$synced_catalog"; then
  echo "::error title=Localization catalog out of sync::Build in Xcode or sync Localizable.xcstrings and commit the generated changes."
  exit 1
fi

echo "==> Validating String Catalogs"
for source_catalog in "$catalog" "$info_catalog"; do
  output_dir="$tmp_dir/compiled/$(basename "$source_catalog" .xcstrings)"
  mkdir -p "$output_dir"
  xcrun xcstringstool compile "$source_catalog" --output-directory "$output_dir" >/dev/null
done

echo "String catalogs are in sync."
