#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_bundle="$PWD/build/NotesMateDesignPreview.app"
mkdir -p "$preview_bundle/Contents/MacOS" "$preview_bundle/Contents/Resources"
icon_app="$PWD/build/design-preview-app/Build/Products/Debug/NotesMate.app"
if [[ ! -f "$icon_app/Contents/Resources/Assets.car" || ! -f "$icon_app/Contents/Resources/AppIcon.icns" ]]; then
    if ! xcodebuild -project NotesMate.xcodeproj -scheme NotesMate -configuration Debug \
        -derivedDataPath build/design-preview-app CODE_SIGNING_ALLOWED=NO build \
        > build/design-preview-app-build.log 2>&1; then
        tail -n 40 build/design-preview-app-build.log >&2
        exit 1
    fi
fi
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(rg --files NotesMate/Editor NotesMate/Notes -g '*.swift' | sort)
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/notesmate-module-cache" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "${sources[@]}" NotesMate/Views/RichTextEditor.swift NotesMate/Views/NoteEditorView.swift \
    Tests/DesignPreview/main.swift -o "$preview_bundle/Contents/MacOS/NotesMateDesignPreview"
cat > "$preview_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.badpxx.notesmate.design-preview</string>
<key>CFBundleExecutable</key><string>NotesMateDesignPreview</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$icon_app/Contents/Resources/Assets.car" "$icon_app/Contents/Resources/AppIcon.icns" \
    "$preview_bundle/Contents/Resources/"
cp -R NotesMate/Localization/*.lproj "$preview_bundle/Contents/Resources/"
if [ "$#" -gt 0 ]; then
    "$preview_bundle/Contents/MacOS/NotesMateDesignPreview" "$@"
    exit
fi
for language in zh-Hans en; do
    for appearance in light dark; do
        "$preview_bundle/Contents/MacOS/NotesMateDesignPreview" "$language" "$appearance" 380
    done
done
"$preview_bundle/Contents/MacOS/NotesMateDesignPreview" en dark 360

# Render the real tip components in both languages/themes, plus wide-window placement.
for language in zh-Hans en; do
    for appearance in light dark; do
        "$preview_bundle/Contents/MacOS/NotesMateDesignPreview" "$language" "$appearance" 380 --tips
    done
done
"$preview_bundle/Contents/MacOS/NotesMateDesignPreview" en dark 360 --tips
"$preview_bundle/Contents/MacOS/NotesMateDesignPreview" zh-Hans light 720 --tips

"$preview_bundle/Contents/MacOS/NotesMateDesignPreview" zh-Hans light 380 --tips --verify-tips
