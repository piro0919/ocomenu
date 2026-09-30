# Ocomenu

**Replace Finder's right-click menu with one you design — hide what you never use, add what you need.**

Ocomenu (*oh-koh-menu*, from **O**riginal **CO**ntext **MENU**) lets you remove the items Apple
puts in Finder's context menu — Open in New Tab, Get Info, Rename, Compress, Duplicate, Make
Alias, Quick Look, Copy, Share… — which no setting and no Finder extension can remove. You can
also reorder them and add your own items.

## Why this is different

Every other context-menu tool for Finder is built on Finder Sync extensions. Those can only
*add* items; Finder's own items stay. Ocomenu doesn't modify Finder's menu at all. It catches
the right-click before Finder sees it and shows its own menu instead, so it decides every line.

- Built-in items still behave exactly like Finder's: choosing one presses the same command in
  Finder's menu bar
- Nothing is injected into Finder and System Integrity Protection stays on
- Hold **⌘** while right-clicking to get Finder's original menu at any time

## What you can add

- **Run a shell script** — the selected paths are passed as `"$@"`
- **Open with an app** of your choice
- **Copy or move to a folder** — name clashes get " 2" appended, like Finder does

## Requirements

- macOS 14 or later on Apple silicon
- **Accessibility** permission, to catch the right-click and read what is under the pointer
- **Automation** permission for Finder, asked for the first time a custom item runs

Right after installing, the menu shows every built-in item in Finder's order, so nothing
disappears until you uncheck it in Settings.

## Building

Xcode is not needed; the Command Line Tools are enough.

```bash
./build.sh
open Ocomenu.app
./Ocomenu.app/Contents/MacOS/Ocomenu --selftest
```

## License

MIT
