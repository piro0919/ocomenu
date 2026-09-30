# CLAUDE.md (Ocomenu)

How to work in this repository. The behaviour itself is documented elsewhere — do not
restate it here.

## Where the truth lives

- **[SPEC.md](SPEC.md)** — what was decided and why, including what the 2026-09-30 prototype
  proved about Finder's accessibility tree. Open questions stay under 保留.
  Change the text here before changing the implementation, not after
- **[README.md](README.md)** — the outward description: what the app does and how to build it
- **[build.sh](build.sh) / [release.sh](release.sh)** — the comments inside the scripts are the
  procedure. Do not write a second copy of it in prose

The layout follows Wacchi (`/Users/piro/Repository/wacchi`), which follows Konechi. The signing
setup follows Hawky, because Ocomenu also needs Accessibility. When something here is missing,
look there first.

## Language

Commit messages, PR titles and bodies, the README, docs, and release notes are written in
English. This file is part of that.

**Comments in the source, SPEC.md, and the explanations inside the shell scripts stay in
Japanese.** That is what the existing code does. Do not translate them.

## Building

Xcode is not needed. The `swiftc` that ships with the Command Line Tools is enough.

```bash
./build.sh          # produces Ocomenu.app; fetches Sparkle into Vendor/ if missing
open Ocomenu.app
./Ocomenu.app/Contents/MacOS/Ocomenu --selftest
```

- `Vendor/` is not tracked. If it disappears, `build.sh` fetches it again
- The version is passed in through `OCOMENU_VERSION`. Local builds stay at `0.0.0`
- A new source file must also be added to the file list in `build.sh`
- The landing page is a pnpm workspace under `lp/`, modelled on Wacchi's for the plumbing only;
  its look is deliberately different (see SPEC.md). Use `pnpm lp:dev` and `pnpm lp:build`. CI runs
  its lint, typecheck and build on Linux
- Builds are signed with the local "Okigae Dev" certificate when it exists. An ad-hoc signature
  changes on every build and macOS drops the Accessibility permission each time. CI has no
  certificate and falls back to ad-hoc, which is fine there

## Testing against the real Finder

The self-test covers the decisions and the stored layout only. Anything that touches Finder has
to be tried in Finder, in all five places the prototype covered: list, icon, column and gallery
views, and the desktop. A change that works in one view has not been shown to work in the others.

- Quit the running copy by PID before launching a new build. Two copies both tap the mouse
- While a copy is running, control-click in Finder never reaches Finder. Say so before asking
  the user to try something, and stop the copy when the test is over
- Do not log clicks outside Finder. A log of every click in every app reads as a keylogger, and
  the auto-mode classifier refuses to read it back

Finder's accessibility tree can be read without clicking anything. Walk the windows of the
Finder application element and print role, `AXIdentifier`, `AXSelected` and `AXURL`; that is how
the view identifiers (`ListView`, `IconView`, `ColumnView`, `GalleryView`) and the menu bar
identifiers (`_NS:715` and friends) were found.

## Releasing

`./release.sh <version>` builds, makes the DMG, signs the update feed, and pushes to GitHub
Releases in one pass.

- **The signing key lives in the login keychain and is shared with Konechi, Nonja, Okigae,
  Gocci, Hawky and Wacchi. Lose it and already-installed copies can never be updated again**
- `generate_appcast` stops when it sees two archives of the same version. Keep the zip and the
  DMG in separate directories
- On 2026-09-30 the first release failed at the very end: `gh release create` with assets got
  HTTP 500 three times, each time leaving an empty draft behind (all systems were reported
  operational). Creating a bare draft worked. What got v0.1.0 out: delete the empty drafts
  by id, create one draft, upload each file to `uploads.github.com/.../releases/<id>/assets`,
  then `PATCH` the release with `draft=false`. Deleted drafts can keep showing up in the list
  for a while, so check by id rather than by count
