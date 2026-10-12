# Extension-free files validation — 2026-10-04

Decision: [files without an extension](../decisions/011-extensionless-files.md). Environment: Apple silicon, macOS 27.2, Xcode 27.0, signed Debug build of `SpacePane.app` (bundle identifier unchanged). Dates use Europe/Istanbul.

## Cause

| File | Type reported by macOS |
|---|---|
| `zprofile`, `.zprofile`, `/etc/zprofile`, `/etc/hosts`, a 300-byte binary `blob` | `public.data` |
| `runme` (same text, executable bit set) | `public.unix-executable` |
| `Local.xcconfig.example` (unknown suffix) | a dynamic `dyn.…` type |

The preview extension did not declare `public.data` and the catalog had no format for it, so Finder showed the generic icon and the pipeline returned "unsupported".

## Automated checks

| Check | Result |
|---|---|
| `./script/build_and_run.sh --check` | Project graph with 31 catalog formats; `public.data` present only in the preview manifest; 359 localization keys in 14 locales; 31 appearance samples |
| `./script/build_and_run.sh --test` | 464 package tests in 39 suites, 11 companion model checks, file-drop, SQLite, appearance and adversarial checks passed |
| `script/check_host_fixtures.py` on a fresh 31-format fixture set | Every fixture parsed, sources unchanged |

New tests cover: exact root-type classification and its suffix guard; root types never matching by conformance (PNG, PDF, movie, executable, archive, an unknown suffix); filename aliases for shell and build files; one catalog owner of `public.data` with no thumbnail; text shown and a synthetic secret concealed; a script styled as source; a shell profile following the Source Code switch; five binary inputs reported as binary content; UTF-8 and UTF-16 marks decoded and reported; an empty file; the type's own switch stopping before any read; and an unknown suffix staying unsupported.

## Observed in Finder

| File | Finder Quick Look (Space) |
|---|---|
| `zprofile` | SpacePane read-only preview with shell highlighting |
| `notes` (plain text) | SpacePane read-only plain text; the Finder preview column showed the same |
| `blob` (binary) | SpacePane message that the content is binary and cannot be shown as text |
| `again.json` (control) | SpacePane Source/Outline preview |

Not observed: `.zprofile` and other dotfiles in Finder, files on other volumes or in iCloud, a competing provider that declares `public.data`, thumbnails (none are registered), other macOS versions and Intel.

## Stale registrations found on this host

Before any fix could be seen, Finder was launching an older copy of the extension. Three copies with the same identifier were registered:

1. `~/Library/Developer/Xcode/DerivedData/Prev-…/Build/Products/Debug/Prev.app` — version 0.1.0, built before the rename and the redesign. macOS had selected this one.
2. An archive intermediate under `.build/xcode-archive/…/SpacePane.app` whose files no longer existed.
3. The current `.build/xcode/Build/Products/Debug/SpacePane.app`.

Copies 1 and 2 were unregistered with `pluginkit -r`, and the current build's two extensions were re-announced with `pluginkit -a`. Only then did Finder use the current build. No file was deleted, Finder was not restarted and no Quick Look cache was reset. Copy 1 can be registered again with `pluginkit -a` on its `.appex` paths, and Xcode or LaunchServices may register it again by itself while `Prev.app` remains in DerivedData.

During testing the extension process was terminated once while a Quick Look panel was open; that panel showed the system's "extension failed" notice until it was reopened. This was caused by the test, not by a file.
