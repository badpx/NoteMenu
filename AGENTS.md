# NotesMate repository guidance

- Every new user-facing UI string must be translated in the same change into all 15 languages supported by `EditorLanguage.supported`. Add the key and translation to every `NotesMate/Localization/*.lproj/Localizable.strings` file, including accessibility text, menu items, alerts, and tips. Keep the localization completeness test passing.
- Before editing, deleting, or reverting an existing working-tree change that you did not introduce, ask the user for confirmation. This also applies to changes the user makes while a task is in progress; if authorship is unclear, preserve the change and ask first.
