# Changelog

Notable changes to Ocomenu. `release.sh` publishes the section for the version being released as
its release notes, and stops if that section is missing or empty — so before releasing, rename
`Unreleased` to `[x.y.z] - YYYY-MM-DD` and commit.

Versions up to v0.1.0 predate this file; their history is in `git log`.

## [Unreleased]

### Fixed

- Built-in items are found by identifier or keyboard shortcut anywhere in Finder's menu bar,
  so they work when Finder runs in languages other than English and Japanese.
- Shell script items report a non-zero exit or a signal, with the end of their stderr, instead
  of failing silently.

### Internal

- The build verifies the SHA-256 of the Sparkle archive it downloads.
- The release script runs the self test, and refuses a dirty working tree, a commit that is not
  on origin/main, an existing tag, a version the built app does not carry, or a missing
  changelog section.
- Releases stop instead of falling back to an ad-hoc signature when the signing certificate is
  missing.
