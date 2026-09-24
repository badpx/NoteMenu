#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Build, Developer ID sign, notarize, and package NotesMate for direct distribution.

Required environment variables:
  VERSION                   Release version, for example 1.0 or 1.2.3
  BUILD_NUMBER              Positive integer build number
  DEVELOPER_ID_APPLICATION  Exact Developer ID Application identity or SHA-1 hash
  NOTARY_PROFILE            notarytool Keychain profile name

The Apple Team ID is read from the installed signing identity.

Output: dist/v<app-version>/NotesMate-v<app-version>-macos.dmg,
        SHA256SUMS, SOURCE_COMMIT, and BUILD_NUMBER.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ $# -ne 0 ]]; then usage >&2; exit 2; fi

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
requested_version="${VERSION:-}"
requested_build="${BUILD_NUMBER:-}"
identity="${DEVELOPER_ID_APPLICATION:-}"
notary_profile="${NOTARY_PROFILE:-}"

[[ $requested_version =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] \
    || die 'set VERSION to a numeric release version such as 1.0 or 1.2.3'
[[ $requested_build =~ ^[1-9][0-9]*$ ]] \
    || die 'set BUILD_NUMBER to a positive integer'
[[ -n $identity ]] || die 'set DEVELOPER_ID_APPLICATION to your Developer ID Application identity'
[[ -n $notary_profile ]] || die 'set NOTARY_PROFILE to a stored notarytool Keychain profile'

for tool in git xcodebuild xcrun security codesign spctl ditto hdiutil plutil shasum tee; do require "$tool"; done
git -C "$repo_root" diff --quiet && git -C "$repo_root" diff --cached --quiet \
    || die 'commit tracked changes before building a release'
[[ -z $(git -C "$repo_root" ls-files --others --exclude-standard) ]] \
    || die 'commit or remove untracked files before building a release'
source_commit="$(git -C "$repo_root" rev-parse --verify HEAD)"

if [[ $identity =~ ^[[:xdigit:]]{40}$ ]]; then
    identity_line="$(security find-identity -v -p codesigning | grep -i -F "$identity" | grep -F 'Developer ID Application:' | head -n 1 || true)"
else
    identity_line="$(security find-identity -v -p codesigning | grep -F "\"$identity\"" | grep -F 'Developer ID Application:' | head -n 1 || true)"
fi
[[ -n $identity_line ]] || die 'the specified Developer ID Application identity is not available in the Keychain'
team_suffix_re='\(([A-Z0-9]{10})\)"?$'
team_only_re='Developer ID Application: ([A-Z0-9]{10})"?$'
if [[ $identity_line =~ $team_suffix_re || $identity_line =~ $team_only_re ]]; then
    team_id="${BASH_REMATCH[1]}"
else
    die 'cannot read the 10-character Team ID from the Developer ID Application identity'
fi

mkdir -p "$repo_root/build"
work_dir="$(mktemp -d "$repo_root/build/release-work.XXXXXX")"
archive_path="$work_dir/NotesMate.xcarchive"
export_path="$work_dir/export"

printf 'Archiving source commit %s\n' "$source_commit"
xcodebuild -project "$repo_root/NoteMenu.xcodeproj" \
    -scheme NotesMate -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work_dir/DerivedData" -archivePath "$archive_path" \
    "DEVELOPMENT_TEAM=$team_id" 'CODE_SIGN_STYLE=Manual' \
    "CODE_SIGN_IDENTITY=$identity" 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' \
    "MARKETING_VERSION=$requested_version" "CURRENT_PROJECT_VERSION=$requested_build" \
    'ENABLE_HARDENED_RUNTIME=YES' 'OTHER_CODE_SIGN_FLAGS=--options=runtime --timestamp' \
    archive 2>&1 | tee "$work_dir/archive.log"

export_options="$work_dir/ExportOptions.plist"
plutil -create xml1 "$export_options"
plutil -insert method -string developer-id "$export_options"
plutil -insert destination -string export "$export_options"
plutil -insert signingStyle -string manual "$export_options"
plutil -insert signingCertificate -string "$identity" "$export_options"
plutil -insert teamID -string "$team_id" "$export_options"
plutil -lint "$export_options" >/dev/null

xcodebuild -exportArchive -archivePath "$archive_path" \
    -exportOptionsPlist "$export_options" -exportPath "$export_path" \
    2>&1 | tee "$work_dir/export.log"

app="$export_path/NotesMate.app"
[[ -d $app ]] || die "Xcode did not export NotesMate.app; inspect $work_dir/export.log"
info="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
[[ $version == "$requested_version" ]] || die "exported app version $version differs from VERSION=$requested_version"
[[ $build_number == "$requested_build" ]] || die "exported app build $build_number differs from BUILD_NUMBER=$requested_build"
[[ $bundle_id == com.badpxx.notesmate ]] || die "unexpected bundle ID: $bundle_id"

release_dir="$repo_root/dist/v$version"
[[ ! -e $release_dir ]] || die "release output already exists: $release_dir"

codesign --verify --deep --strict --verbose=2 "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
grep -Fq 'Authority=Developer ID Application:' <<< "$signature" \
    || die 'exported app is not signed with Developer ID Application'
grep -Fq "TeamIdentifier=$team_id" <<< "$signature" \
    || die 'exported app has the wrong Team ID'
grep -Eq 'flags=.*runtime' <<< "$signature" \
    || die 'exported app does not have Hardened Runtime enabled'
grep -Fq 'Timestamp=' <<< "$signature" \
    || die 'exported app lacks a secure signing timestamp'

image_root="$work_dir/dmg-root"
mkdir -p "$image_root"
ditto "$app" "$image_root/NotesMate.app"
ln -s /Applications "$image_root/Applications"
asset_name="NotesMate-v$version-macos.dmg"
asset_path="$work_dir/$asset_name"
hdiutil create -srcfolder "$image_root" -volname "NotesMate $version" \
    -format UDZO -ov "$asset_path"
hdiutil verify "$asset_path"
codesign --sign "$identity" --timestamp \
    --identifier com.badpxx.notesmate.disk-image "$asset_path"
codesign --verify --strict --verbose=2 "$asset_path"
image_signature="$(codesign -dv --verbose=4 "$asset_path" 2>&1)"
grep -Fq "TeamIdentifier=$team_id" <<< "$image_signature" \
    || die 'DMG has the wrong Team ID'

notary_result="$work_dir/notary-result.json"
submission_ok=true
if ! xcrun notarytool submit "$asset_path" --keychain-profile "$notary_profile" \
    --wait --timeout 1h --output-format json > "$notary_result"; then
    submission_ok=false
fi
notary_status="$(plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)"
if [[ $submission_ok != true || $notary_status != Accepted ]]; then
    submission_id="$(plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
    if [[ -n $submission_id ]]; then
        xcrun notarytool log "$submission_id" "$work_dir/notary-log.json" \
            --keychain-profile "$notary_profile" || true
    fi
    die "notarization status is ${notary_status:-unknown}; inspect $work_dir/notary-result.json and notary-log.json"
fi

xcrun stapler staple "$asset_path"
xcrun stapler validate "$asset_path"
hdiutil verify "$asset_path"
codesign --verify --strict --verbose=2 "$asset_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$asset_path"

mkdir -p "$release_dir"
mv "$asset_path" "$release_dir/$asset_name"
printf '%s\n' "$source_commit" > "$release_dir/SOURCE_COMMIT"
printf '%s\n' "$build_number" > "$release_dir/BUILD_NUMBER"
(cd "$release_dir" && shasum -a 256 "$asset_name" > SHA256SUMS)

printf '\nReady for distribution:\n  %s\n  %s\n' \
    "$release_dir/$asset_name" "$release_dir/SHA256SUMS"
printf 'Archive and signing logs: %s\n' "$work_dir"
