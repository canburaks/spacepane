# SpacePane

SpacePane adds Quick Look previews for the files your Mac can't show yet. Select a file in Finder, press Space, and you see what is really inside, with likely secrets concealed. It also tells you what to check before you open, run or share a file. Everything happens on your Mac: files are only read, and nothing inside them is run.

Website: [spacepane.com](https://spacepane.com). "Prev" was the working name; it survives in the repository, Xcode project and target names.

## Status

| | |
|---|---|
| **Version 1.0** (build 3) | Submitted to App Review on 2026-10-13. 74 file types, English only, no STEP or IGES ([decision 028](docs/decisions/028-no-cad-in-version-1.md)). |
| **`main`** | 81 file types, with Safety Lens 2 and 3 ([decision 029](docs/decisions/029-safety-lens-2-what-a-file-will-do.md), [decision 030](docs/decisions/030-safety-lens-3-models-add-ons-and-packages.md)). Planned for an update after 1.0. |
| **Requires** | macOS 15 or later. The App Store build is for Apple silicon. |

Open work, including Finder checks, VoiceOver and native-speaker review of translations, is tracked in [PLAN.md](PLAN.md).

## What it does

- **Previews.**
  - **Text and code:** source code, logs, Markdown and other markup, subtitles, Jupyter notebooks, diffs, Mermaid and draw.io diagrams, and ebooks.
  - **Data:** JSON, YAML, TOML, XML, property lists, CSV and TSV with a column profile, Parquet, Avro, Arrow, NumPy, HAR and map data.
  - **Archives, apps and packages:** ZIP, TAR, gzip, 7z, RAR, app bundles, iOS and Android apps, installer packages, disk images and torrents.
  - **Other:** certificates, SQLite databases, MIDI and 3D meshes (STL, OBJ, PLY, 3MF).
- **Safety Lens.** Plain-language findings about what to check first:
  - hidden characters, including hidden text in instruction files for AI coding tools;
  - risky archive entries;
  - how many secrets were concealed, and on which lines;
  - notebooks that won't reproduce.

  On `main`, it also says what a file would do: a script, a VS Code task that runs when a folder opens, a launch agent, an AI model file, or an extension or package you are about to install.
- **Privacy by default.** Likely passwords, tokens and keys are concealed, even in the source view, and kept out of thumbnails. Concealment is a careful heuristic, not a guarantee.
- **Companion app.** One window with four pages:
  - **General:** settings, including the switch for content thumbnails.
  - **File Types:** a switch for every type.
  - **Theme:** colors, fonts and spacing, with a live sample of every type.
  - **About.**

  Developer Mode adds Try Preview, for opening any file directly.

macOS decides which installed app previews each file type, and SpacePane cannot override it. On macOS 27.2, for example, Apple's own previewers keep CSV and the STL, OBJ and PLY meshes.

## Repository layout

| Path | What is there |
|---|---|
| `Apps/PrevApp` | The companion app (SwiftUI) |
| `Extensions/` | The Quick Look preview and thumbnail extensions |
| `Packages/PreviewCore` | The Swift package that does the work: format catalog, pipeline, format readers, renderers, thumbnails and their tests |
| `Native/` | The STEP and IGES importer, kept for a later version; not part of 1.0 |
| `Configuration/` | Build settings, Info.plists and entitlements |
| `script/`, `tools/` | Build, checks, test fixtures and localization tools |
| `Tests/`, `Fixtures/` | Integration and performance checks, and sample files |
| `docs/` | Decisions, plans, validation records, release notes and research |

## Build and test

You need full Xcode with Swift 6.2 or later. If Command Line Tools are selected, point `DEVELOPER_DIR` at Xcode.

```sh
./script/build_and_run.sh --check-static    # quick checks; no Xcode needed
./script/build_and_run.sh --check           # project, manifests, catalog and strings
./script/build_and_run.sh --test            # package tests and companion model checks
./script/build_and_run.sh --check-compiler  # type-checks the app and extensions
```

**To run a signed development build:**
1. Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`.
2. Fill in your team and identifiers.
3. Run `./script/build_and_run.sh`. It builds, signs and launches the companion, which registers the extensions.

None of these checks proves that Finder uses SpacePane for a given type. Finder observations are recorded in [docs/validation](docs/validation/).

**For the App Store,** `./script/build_and_run.sh --archive` makes the signed Release archive. The release steps are in [docs/release/app-store-submission.md](docs/release/app-store-submission.md).

`./script/build_and_run.sh --help` lists every mode.

## Adding a file type

A new type normally needs only:
- a reader in `Packages/PreviewCore/Sources/PreviewFormats`;
- an entry in `FormatCatalog.json` and one registration line;
- an appearance sample (`script/generate_appearance_samples.py`);
- test fixtures;
- its strings.

Shared limits, concealment and presentations come for free. See [decision 001](docs/decisions/001-format-extensibility.md) and the architecture rules in [AGENTS.md](AGENTS.md).

## Translations

Draft translations exist for 14 languages: English, Turkish, German, French, Simplified Chinese, Japanese, Hindi, Kurmanji, Russian, Indonesian, Bengali, Hausa, Portuguese and Spanish. A language ships only after a native speaker reviews it, so version 1.0 is English only.

Add new strings through an additions file in `tools/localization/additions/`, then regenerate:

```sh
python3 tools/merge_localizations.py
python3 tools/generate_localization.py
python3 tools/validate_localization.py
```

See [tools/localization/README.md](tools/localization/README.md).

## If a preview shows nothing

The usual cause is a build that still has placeholder identifiers (`group.invalid.*`): the extension then declines to load content.

1. Set the same App Group for the app and both extensions in `Configuration/Local.xcconfig`.
2. Rebuild.
3. Run `./script/build_and_run.sh --verify`.
4. Close and reopen Quick Look.

Don't reset Quick Look's caches to hide the problem. Details are in [the settings validation record](docs/validation/shared-settings-configuration.md).

## Learn more

- [PLAN.md](PLAN.md): what is done and what is still open
- [CHANGELOGS.md](CHANGELOGS.md): dated history of every change
- [AGENTS.md](AGENTS.md): architecture and working rules
- [docs/decisions](docs/decisions/README.md): why things are the way they are
- [docs/validation](docs/validation/): what was tested, on which Mac, and its limits
