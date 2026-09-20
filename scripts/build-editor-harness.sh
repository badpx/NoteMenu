#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/NoteMenuEditorHarness.app"
mkdir -p "$bundle/Contents/MacOS"
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find NoteMenu/Editor NoteMenu/Notes -name '*.swift' -type f | sort)
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/notemenu-module-cache" -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    "${sources[@]}" NoteMenu/Views/RichTextEditor.swift NoteMenu/Views/NoteEditorView.swift NoteMenu/PanelController.swift \
    Tests/ManualHarness/main.swift -o "$bundle/Contents/MacOS/NoteMenuEditorHarness"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.notemenu.editor-harness</string>
<key>CFBundleExecutable</key><string>NoteMenuEditorHarness</string>
<key>CFBundleName</key><string>NoteMenu Editor Harness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
echo "$bundle"
