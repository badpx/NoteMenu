on run arguments
    set mountPath to item 1 of arguments
    set diskFolder to (POSIX file mountPath) as alias

    tell application "Finder"
        open diskFolder
        set diskWindow to container window of diskFolder
        set current view of diskWindow to icon view
        set toolbar visible of diskWindow to false
        set statusbar visible of diskWindow to false
        set pathbar visible of diskWindow to false
        set bounds of diskWindow to {100, 100, 820, 540}

        set viewOptions to icon view options of diskWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to (POSIX file (mountPath & "/.background/background.png")) as alias

        set position of item "NotesMate.app" of diskFolder to {170, 204}
        set position of item "Applications" of diskFolder to {550, 204}
        update diskFolder without registering applications
        delay 2
        close diskWindow
    end tell
end run
