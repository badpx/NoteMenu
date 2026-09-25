#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || { echo 'usage: create-dmg.sh APP VERSION OUTPUT_DMG' >&2; exit 2; }
app="$1"
version="$2"
output="$3"
[[ -d $app ]] || { echo "missing app: $app" >&2; exit 1; }
[[ $version =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "invalid version: $version" >&2; exit 1; }
[[ ! -e $output ]] || { echo "output already exists: $output" >&2; exit 1; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
background="$script_dir/../assets/dmg-background.png"
[[ -f $background ]] || { echo "missing DMG background: $background" >&2; exit 1; }

output_dir="$(cd -- "$(dirname -- "$output")" && pwd)"
output="$output_dir/$(basename -- "$output")"
work_dir="$(mktemp -d "$output_dir/dmg-layout.XXXXXX")"
mount_dir="$work_dir/mount"
image="$work_dir/writable.dmg"
mounted=false
cleanup() {
    if [[ $mounted == true ]]; then
        if ! hdiutil detach "$mount_dir" >/dev/null; then
            echo "could not detach temporary DMG at $mount_dir" >&2
            return
        fi
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

app_kb="$(du -sk "$app" | awk '{print $1}')"
image_mb="$(( (app_kb + 1023) / 1024 + 64 ))"
hdiutil create -size "${image_mb}m" -fs HFS+ -volname "NotesMate $version" \
    -type UDIF "$image" >/dev/null
mkdir "$mount_dir"
hdiutil attach -readwrite -noverify -noautoopen \
    -mountpoint "$mount_dir" "$image" >/dev/null
mounted=true

ditto "$app" "$mount_dir/NotesMate.app"
ln -s /Applications "$mount_dir/Applications"
mkdir "$mount_dir/.background"
cp "$background" "$mount_dir/.background/background.png"
osascript "$script_dir/create-dmg.applescript" "$mount_dir"
[[ -f $mount_dir/.DS_Store ]] || { echo 'Finder did not save the DMG layout' >&2; exit 1; }
sync
hdiutil detach "$mount_dir" >/dev/null
mounted=false

hdiutil convert "$image" -format UDZO -o "$output" >/dev/null
hdiutil verify "$output" >/dev/null
