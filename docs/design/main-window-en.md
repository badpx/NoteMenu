# NoteMenu English UI — Light & Dark

English versions of the approved light V2 and dark V1 designs. Both boards show the same two states: **Ready to write** and **Writing**. Layout, typography hierarchy, toolbar order, state styling, and the actual NoteMenu app icon remain consistent with the Chinese versions.

## Deliverables

- [Light appearance](main-window-light-en-v2.png)
- [Dark appearance](main-window-dark-en-v2.png)
- [Shared generation prompt](main-window-en-prompt.txt)

Generated with the built-in image_gen tool, using the approved Chinese boards as references. Each call adds an instruction to retain the reference's light or dark appearance. These are design artifacts, not an application localization implementation.

## Copy

| Location | English |
|---|---|
| Board subtitle | Capture a thought. Keep it in Notes. |
| Empty-state label | Ready to write |
| Editing-state label | Writing |
| Editor placeholder | What's on your mind? |
| Sample heading | Give ideas a place |
| Sample paragraph | Save a thought. Come back to it later. |
| First bullet | Capture ideas without losing focus |
| Second bullet | Save them directly to Apple Notes |
| Sample destination folder | Meetings |
| Board design notes | A quiet writing space / A considered toolbar / Yellow, with purpose |

The example folder name “Meetings” is presentation content. In the application, display the user's actual Apple Notes folder name without translating it. Likewise, the English sample note does not imply translation of user content.

## Interaction copy for implementation

| Control / state | English |
|---|---|
| Pin / unpin | Keep on Top / Unpin |
| Close | Close |
| Paragraph menu | Paragraph Style |
| Inline formatting menu | Text Style |
| Bulleted / numbered list | Bulleted List / Numbered List |
| Insert image | Add Image |
| Folder selector | Choose Save Folder |
| Save tooltip | Save to Notes (⌘ + Enter) |
| Saving | Saving… |
| Save success | Saved to Apple Notes |

Keep icon-only toolbar buttons and reveal labels through tooltips and accessibility. Preserve the compact folder control and show its full name on hover when truncated. Visual dimensions and colors follow the existing [light](main-window-v1.md) and [dark](main-window-dark-v1.md) specifications.

## Control-state revision

Formatting and folder controls have transparent backgrounds at rest. Hover alone shows a pale yellow fill (dark amber in dark mode). Selected list and Pin controls use only the golden foreground. The text style control always reads **Aa**, regardless of language. The latest boards show Aa hovered and the bullet control selected as two independent states.
