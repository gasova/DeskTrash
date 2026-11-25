# DeskTrash

A Trash can on the macOS desktop.

DeskTrash is a small native Swift app that puts a Trash icon on your desktop, the way classic Mac OS had it. It sits above the desktop icons and below every window, on all Spaces.

## Features

- **Drop to trash**: drag files or folders onto the icon to move them to the Trash.
- **Open**: double-click to open the Trash in Finder.
- **Empty/full icon**: the icon reflects whether the Trash has anything in it.
- **Context menu**: right-click for Open, Empty Trash, Launch at Login and Quit.
- **Movable**: drag the icon anywhere; its position is remembered.

Everything goes through Finder, so Put Back, external volumes and the Empty Trash warning behave exactly like the Trash in the Dock.

## Requirements

- macOS 13 or later
- Xcode command line tools (`xcode-select --install`)

## Build

```
git clone https://github.com/<your-username>/DeskTrash.git
cd DeskTrash
bash build.sh
open DeskTrash.app
```

`build.sh` compiles `main.swift`, creates `DeskTrash.app` and signs it ad hoc. There is no Xcode project.

Move `DeskTrash.app` to `/Applications` before turning on Launch at Login.

## Permissions

On first use macOS asks whether DeskTrash may control Finder. Allow it; the app cannot work without it. You can change this later in System Settings > Privacy & Security > Automation.

## Notes

- DeskTrash has no Dock icon or menu bar item. Quit it from the right-click menu.
- The Trash state is checked every 5 seconds, so the icon can lag slightly behind changes made elsewhere.
- The Trash in the Dock is not removed; macOS does not allow that. Turn on Dock auto-hide if you want it out of sight.
- The app is not sandboxed, so it cannot be distributed through the Mac App Store.
