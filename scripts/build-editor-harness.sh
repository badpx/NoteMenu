#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/NotesMateEditorHarness.app"
mkdir -p "$bundle/Contents/MacOS"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find NotesMate/Editor NotesMate/Notes -name '*.swift' -type f | sort)
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/notesmate-module-cache" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "${sources[@]}" NotesMate/Views/RichTextEditor.swift NotesMate/Views/NoteEditorView.swift NotesMate/PanelController.swift \
    Tests/ManualHarness/main.swift -o "$bundle/Contents/MacOS/NotesMateEditorHarness"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.notesmate.editor-harness</string>
<key>CFBundleExecutable</key><string>NotesMateEditorHarness</string>
<key>CFBundleName</key><string>NotesMate Editor Harness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$bundle/Contents/Resources"
xcrun actool NotesMate/Resources/Assets.xcassets --compile "$bundle/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.0 --target-device mac
cp -R NotesMate/Localization/*.lproj "$bundle/Contents/Resources/"
codesign --force --sign - "$bundle"
echo "$bundle"
