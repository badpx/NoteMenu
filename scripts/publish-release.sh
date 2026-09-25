#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Publish a previously built and notarized NotesMate DMG to GitHub Releases.

Usage: scripts/publish-release.sh v<app-version> [--draft]

After validating the DMG, create an annotated tag at the build's source commit
if needed, push it to origin, and create the GitHub Release. Existing local or
remote tags must point to that commit. Set RELEASE_NOTES_FILE to use custom
notes; otherwise GitHub generates release notes.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 2; }
tag="$1"
[[ $tag =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]] || { usage >&2; exit 2; }
[[ $# -eq 1 || ${2:-} == --draft ]] || { usage >&2; exit 2; }

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
for tool in git gh hdiutil codesign xcrun spctl shasum; do require "$tool"; done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$repo_root" diff --quiet && git -C "$repo_root" diff --cached --quiet \
    || die 'commit tracked changes before publishing'
[[ -z $(git -C "$repo_root" ls-files --others --exclude-standard) ]] \
    || die 'commit or remove untracked files before publishing'

version="${tag#v}"
release_dir="$repo_root/dist/$tag"
asset="$release_dir/NotesMate-$tag-macos.dmg"
[[ -f $asset && -f $release_dir/SHA256SUMS && -f $release_dir/SOURCE_COMMIT && -f $release_dir/BUILD_NUMBER ]] \
    || die "missing build output in $release_dir; run scripts/build-release.sh first"
(cd "$release_dir" && shasum -a 256 -c SHA256SUMS) || die 'release asset checksum mismatch'

built_commit="$(< "$release_dir/SOURCE_COMMIT")"
[[ $built_commit =~ ^[0-9a-f]{40}$ ]] || die 'invalid SOURCE_COMMIT'
git -C "$repo_root" cat-file -e "$built_commit^{commit}" \
    || die 'the commit used for this build is not available locally'
local_tag_exists=false
if git -C "$repo_root" show-ref --verify --quiet "refs/tags/$tag"; then
    local_tag_exists=true
    tag_commit="$(git -C "$repo_root" rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null)" \
        || die "local tag $tag does not point to a commit"
    [[ $tag_commit == "$built_commit" ]] || die "local tag $tag points to a different commit"
fi

remote_refs="$(git -C "$repo_root" ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")" \
    || die 'cannot inspect tags on origin'
remote_tag_exists=false
remote_tag_object="$(awk -v tag="$tag" '$2 == "refs/tags/" tag { print $1 }' <<< "$remote_refs")"
if [[ -n $remote_tag_object ]]; then
    remote_tag_exists=true
fi
remote_commit="$(awk -v tag="$tag" '$2 == "refs/tags/" tag "^{}" { print $1; found=1 } END { if (!found) exit 1 }' <<< "$remote_refs" || true)"
if [[ $remote_tag_exists == true ]]; then
    [[ -n $remote_commit ]] || remote_commit="$remote_tag_object"
    [[ $remote_commit == "$built_commit" ]] || die "origin tag $tag points to a different commit"
fi

codesign --verify --strict --verbose=2 "$asset"
image_signature="$(codesign -dv --verbose=4 "$asset" 2>&1)"
grep -Fq 'Authority=Developer ID Application:' <<< "$image_signature" \
    || die 'DMG is not Developer ID Application signed'
grep -Fq 'Identifier=com.badpxx.notesmate.disk-image' <<< "$image_signature" \
    || die 'DMG has an unexpected signing identifier'
if [[ $image_signature =~ TeamIdentifier=([A-Z0-9]{10}) ]]; then
    image_team="${BASH_REMATCH[1]}"
else
    die 'DMG has no valid Team ID'
fi
grep -Fq 'Timestamp=' <<< "$image_signature" \
    || die 'DMG lacks a secure signing timestamp'
hdiutil verify "$asset"
xcrun stapler validate "$asset"
spctl --assess --type open --context context:primary-signature --verbose=2 "$asset"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/notesmate-publish.XXXXXX")"
mount_dir="$temp_dir/mount"
mkdir "$mount_dir"
mounted=false
cleanup() {
    if [[ $mounted == true ]]; then hdiutil detach "$mount_dir" >/dev/null || true; fi
    rm -rf -- "$temp_dir"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_dir" "$asset" >/dev/null
mounted=true
app="$mount_dir/NotesMate.app"
[[ -d $app ]] || die 'DMG does not contain NotesMate.app at its root'
[[ -L $mount_dir/Applications && $(readlink "$mount_dir/Applications") == /Applications ]] \
    || die 'DMG is missing the Applications shortcut'
[[ -f $mount_dir/.background/background.png && -f $mount_dir/.DS_Store ]] \
    || die 'DMG is missing the Finder installation layout'
info="$app/Contents/Info.plist"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
[[ $app_version == "$version" && $bundle_id == com.badpxx.notesmate ]] \
    || die 'DMG app version or bundle ID does not match this release'
[[ $app_build == "$(< "$release_dir/BUILD_NUMBER")" ]] \
    || die 'DMG app build number does not match BUILD_NUMBER metadata'
codesign --verify --deep --strict --verbose=2 "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
grep -Fq 'Authority=Developer ID Application:' <<< "$signature" \
    || die 'DMG app is not Developer ID Application signed'
grep -Fq "TeamIdentifier=$image_team" <<< "$signature" \
    || die 'DMG app and image have different Team IDs'
grep -Eq 'flags=.*runtime' <<< "$signature" \
    || die 'DMG app does not have Hardened Runtime enabled'
grep -Fq 'Timestamp=' <<< "$signature" \
    || die 'DMG app lacks a secure signing timestamp'
hdiutil detach "$mount_dir" >/dev/null
mounted=false

notes_args=(--generate-notes)
if [[ -n ${RELEASE_NOTES_FILE:-} ]]; then
    [[ -f $RELEASE_NOTES_FILE ]] || die "release notes file not found: $RELEASE_NOTES_FILE"
    notes_args=(--notes-file "$RELEASE_NOTES_FILE")
fi
draft_args=()
if [[ ${2:-} == --draft ]]; then draft_args=(--draft); fi

gh auth status >/dev/null || die 'GitHub CLI is not authenticated'
if [[ $local_tag_exists == false ]]; then
    if [[ $remote_tag_exists == true ]]; then
        git -C "$repo_root" fetch --no-tags origin "refs/tags/$tag:refs/tags/$tag"
    else
        git -C "$repo_root" tag -a "$tag" "$built_commit" -m "NotesMate $version"
    fi
fi
if [[ $remote_tag_exists == false ]]; then
    git -C "$repo_root" push origin "refs/tags/$tag:refs/tags/$tag"
fi
published_refs="$(git -C "$repo_root" ls-remote --exit-code origin "refs/tags/$tag" "refs/tags/$tag^{}")" \
    || die "tag $tag is not present on origin after pushing"
published_commit="$(awk -v tag="$tag" '$2 == "refs/tags/" tag "^{}" { print $1; found=1 } END { if (!found) exit 1 }' <<< "$published_refs" || true)"
if [[ -z $published_commit ]]; then
    published_commit="$(awk -v tag="$tag" '$2 == "refs/tags/" tag { print $1 }' <<< "$published_refs")"
fi
[[ $published_commit == "$built_commit" ]] || die "origin tag $tag changed to a different commit"

gh release create "$tag" "$asset" "$release_dir/SHA256SUMS" \
    --verify-tag --title "NotesMate $version" "${notes_args[@]}" \
    ${draft_args[@]+"${draft_args[@]}"}
gh release view "$tag" --json url --jq .url
