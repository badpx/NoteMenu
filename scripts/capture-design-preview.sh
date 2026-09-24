#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_bundle="$PWD/build/NoteMenuDesignPreview.app"
mkdir -p "$preview_bundle/Contents/MacOS" "$preview_bundle/Contents/Resources"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(rg --files NoteMenu/Editor NoteMenu/Notes -g '*.swift' | sort)
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/notemenu-module-cache" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "${sources[@]}" NoteMenu/Views/RichTextEditor.swift NoteMenu/Views/NoteEditorView.swift \
    Tests/DesignPreview/main.swift -o "$preview_bundle/Contents/MacOS/NoteMenuDesignPreview"
cat > "$preview_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.badpx.notemenu.design-preview</string>
<key>CFBundleExecutable</key><string>NoteMenuDesignPreview</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp build/debug-icon-composer/Build/Products/Debug/NoteMenu.app/Contents/Resources/{Assets.car,AppIcon.icns} "$preview_bundle/Contents/Resources/"
for language in zh-Hans en; do
    for appearance in light dark; do
        "$preview_bundle/Contents/MacOS/NoteMenuDesignPreview" "$language" "$appearance" 380
    done
done
"$preview_bundle/Contents/MacOS/NoteMenuDesignPreview" en dark 360
