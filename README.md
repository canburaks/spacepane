# SpacePane

A native macOS 15+ Quick Look app. Preparation for Mac App Store publication started on 2026-10-10; build 1.0.0 (1) was uploaded to App Store Connect the same day and nothing has been submitted for review (see the [publication plan](docs/plans/2026-10-10-app-store-publication-plan.md)). The product is named SpacePane ([spacepane.com](https://spacepane.com)); the repository, Xcode project and targets keep the earlier working name Prev as technical names. The implementation now registers 81 logical file types (76 until 2026-10-13, when the two CAD entries left the catalog, and 74 until 2026-10-14, when [decision 030](docs/decisions/030-safety-lens-3-models-add-ons-and-packages.md) added model files, add-ons and Python wheels; see below), with native source/outline/Markdown views, bounded container and SQLite inspection, and MIDI controls. The [competitor parity program](docs/decisions/025-competitor-parity-program.md) added archives (RAR, 7z, bzip2, xz), markup documents, native Mermaid and draw.io diagrams, application packages and certificates, columnar, scientific and geographic data, many more languages and caption formats, ebooks and comics, meshes, content thumbnails, live reload and color schemes; see [its validation](docs/validation/parity-program-2026-10-05.md). Finder routing and release acceptance remain separate gates.

**Version 1.0 ships without STEP and IGES.** On 2026-10-13 the owner decided to cut them from 1.0 ([decision 028](docs/decisions/028-no-cad-in-version-1.md)); the build setting `PREV_INCLUDE_CAD` (`Configuration/Base.xcconfig`, NO for 1.0) keeps the CAD helper, its XPC service and the OCCT notices out of the product, and the two catalog entries are kept in `Configuration/CADFormatCatalogEntries.json`. The CAD sources stay in the repository, and the STL, OBJ, PLY and 3MF mesh previews are unaffected. The next two paragraphs describe the CAD implementation that stays in the repository for a later version.

IGES (`.igs`, `.iges`) and STEP (`.step`, `.stp`) have native 3D previews in builds that include CAD with rotate, pan, zoom, fit/reset and standard views. **Both are off by default** because CAD import uses additional time and memory. Enable each in File Types → Media. Import runs locally in a bounded, disposable helper; ordinary previews do not start it, and CAD thumbnails remain generic. The supplied IGES example and synthetic STEP/IGES boxes rendered (before the 1.0 cut) in signed Finder Quick Look on the tested Apple silicon host, with the companion stopped. Wider platform coverage remains a separate gate. See [CAD architecture](docs/decisions/006-opt-in-cad-previews.md) and [validation](docs/validation/cad-previews-2026-10-04.md).

For a build that includes CAD (`PREV_INCLUDE_CAD = YES`, not the 1.0 setting), full build modes prepare the pinned CAD helper automatically (CMake is required; the first build downloads official OCCT source). Before building directly in Xcode, run `python3 script/build_cad_worker.py --architecture arm64`; prepare `x86_64` as well for universal builds. The app performs no runtime downloads. [Dependency terms and source/relinking release obligations](docs/dependencies/occt.md) remain a release gate for any build that includes CAD; 1.0 has none.

The Theme page's live preview has a menu of every supported file type, each with a built-in synthetic sample read through the normal pipeline, so any preview can be seen with the current appearance. The Theme page provides system/light/dark/high-contrast preview themes, font family and attributes, spacing, ligatures, tabs, wrapping and optional logical line numbers, with a live native sample. Semantic syntax colors and token emphasis are applied after secret concealment. Named profiles and bounded inert JSON theme import/export stay in the same window. Source highlighting is lexical; complete language grammars are not claimed.

General, File Types, Theme and About share one main window with a fixed sidebar. Command-comma selects File Types; Command-1 through Command-4 select the four pages in order. About and Help commands select About. The sidebar reports where settings are saved and how many file types are enabled; it does not claim that Finder uses this provider. See [the redesign record](docs/decisions/010-companion-sidebar-redesign.md).

**Developer Mode** (General, off by default) adds Try Preview to the sidebar, with Open File, Command-O and Command-5.

In Developer Mode, Try Preview includes an area for dropping one local file, using the same pipeline as Open File. Multiple items and web links are rejected without replacing the current preview. Native URL-ingress checks pass; real signed Finder drag grants and complete interaction/accessibility coverage remain to be verified in the [drop validation record](docs/validation/direct-file-drop.md).

Text files whose name has no extension, such as `zprofile`, `hosts` or `Makefile`, are previewed too: macOS types them all as `public.data`, which only the preview extension declares. Binary content is never shown as text, files marked executable are not covered, and these files keep their system icons. See [the decision](docs/decisions/011-extensionless-files.md).

Finder chooses the provider independently for each type. On the tested host, fresh JSON previews worked while the companion was stopped; YAML, Markdown and ZIP also worked after native companion quit ([interaction evidence](docs/validation/interaction-continuation-2026-10-04.md)); JSON Lines displayed a generic preview and plain text used another provider. The current thumbnail provider has now been independently observed through the modern thumbnail generator, including with the companion stopped; broader Finder thumbnail surfaces remain unverified. See the [current expansion and host evidence](docs/validation/parallel-expansion-2026-10-04.md); parser support and concealment inside this app do not control another provider's output.

The [latest 22-format Finder matrix](docs/validation/finder-matrix-2026-10-04.md) records 18 app presentations and four routing exceptions on this host. A rebuilt-extension follow-up verified silent MIDI transport and XML CDATA/processing-instruction concealment; audible sound quality and broader platform coverage remain open.

See [PLAN.md](PLAN.md) for checked progress and remaining features, [AGENTS.md](AGENTS.md) for architecture rules, [CHANGELOGS.md](CHANGELOGS.md) for changes, and [platform validation](docs/validation/platform-spike.md) for tested behavior and limitations.

## Development

The repository uses an Xcode companion app with embedded preview and thumbnail extensions, a private sandboxed CAD XPC service inside the preview extension (only in builds that include CAD; not in 1.0), and a local Swift package for reusable domain contracts, parsing, preferences and rendering. The compiler must support Swift 6.2 or later; language mode is Swift 6. The CAD worker separately builds the pinned OCCT native dependency; vendor types stay outside Swift domain contracts.

Use the project-local entrypoint:

```sh
./script/build_and_run.sh --help
./script/build_and_run.sh --check
./script/build_and_run.sh --test
./script/build_and_run.sh --check-compiler
```

`--check` validates configuration, registration metadata and localized format arguments, including focused validator regressions. `--test` runs the Swift package tests (a parallel pass, then five wall-clock tests in three named suites serially, with a compiled-inventory count guard), the isolated companion-model, settings, live-reload and appearance-interaction checks, the private-pasteboard drop checks, an independent-process SQLite lock/read-only check, and the deterministic all-format adversarial corpus. `--check-compiler` builds the package and type-checks app/extension source with the available macOS SDK. These checks do not install extensions or prove Finder invocation.

Measure the optimized core pipeline with temporary synthetic files:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/benchmark_release_pipeline.py
```

The benchmark records separate first-request/new-process and warm distributions,
process RSS, expected outcomes and no-source-mutation checks. Raw samples go under
ignored `.build/performance/`; this does not measure Finder startup or native drawing.
See [the measured baseline](docs/validation/release-pipeline-benchmark-2026-10-04.md).

Measure the native renderer separately, and verify the built app's localized resources:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/benchmark_release_native_renderer.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 script/check_bundle_localizations.py --app .build/xcode/Build/Products/Debug/SpacePane.app
```

The [native benchmark](docs/validation/security-performance-2026-10-04.md) includes AppKit layout/drawing, mode changes and restyling. The [renderer optimization follow-up](docs/validation/native-renderer-performance-2026-10-04.md) records substantial outline/mode-switch gains; initial text/JSON/source paths still exceed the provisional total useful-content target. The bundle checker validates 33 explicit language-selection cases in all three signed artifacts; it does not establish effective Finder language or translation quality.

Generate synthetic files for repeatable host checks with `python3 script/generate_host_fixtures.py`. It prints a newly owned directory; `python3 script/check_host_fixtures.py <SwiftPM-bin-directory> <printed-directory>` checks the pipeline and unchanged bytes. Use Finder manually to assess routing: [the 22-format matrix](docs/validation/finder-matrix-2026-10-04.md) records observed outcomes and limits.

With Command Line Tools, you can also build or launch a local **companion-only prototype**:

```sh
./script/build_and_run.sh --build-companion
./script/build_and_run.sh --run-companion
```

This stages `dist/PrevPrototype.app` with private settings and ad hoc signing. It has **no sandbox/App Group entitlements and no embedded Quick Look extensions**; use it to try the companion UI, not to validate Finder or Store distribution. The normal Run action still uses the signed Xcode workflow below.

The checked-in `Prev.xcodeproj` and shared `Prev` scheme are the source of truth. The stale project generator was retired after a Mac dependency inventory; edit the project directly and run the project/signing validators when its graph changes.

Full bundle builds require full Xcode. Select it for the command with `DEVELOPER_DIR` if necessary; no global developer-directory change is required. To compile unsigned bundles:

```sh
./script/build_and_run.sh --build-unsigned
```

To run a signed development build, copy `Configuration/Local.xcconfig.example` to the ignored `Configuration/Local.xcconfig`, fill in your development team and actual bundle/App Group identifiers, and configure the corresponding signing capabilities. The checked-in `invalid.example` identifiers are compilation placeholders. Then use:

```sh
./script/build_and_run.sh
```

The Codex Run action invokes this same script. Optional `--debug`, `--logs`, `--telemetry` and `--verify` modes support local diagnosis. No App Store credentials belong in the repository.

To prepare a Mac App Store upload, archive the signed Release app (Apple silicon only) and check it for upload problems:

```sh
./script/build_and_run.sh --archive
```

Then validate and distribute the archive from Xcode Organizer. Review notes, App Store Connect answers and the remaining release gates are in [docs/release/app-store-submission.md](docs/release/app-store-submission.md). The app icon is rendered from `Configuration/AppIcon.svg` by `xcrun swift script/generate_app_icon.swift`; rerun it after changing the mark.

After a signed install, enable the extensions in System Settings and verify representative files in Finder. macOS chooses the provider for each type. A successful companion preview or compiler check is not evidence that Finder selected this app.

## Product boundaries

- Format adapters are injected into the core; host code and renderers do not select concrete parsers.
- File-type choices apply before content parsing, including fallback paths. Catalog-driven individual/group/all controls preserve independent choices; group actions include rows hidden by search.
- JSON Lines (`.jsonl`, `.ndjson`) provides validated, concealed source. It accepts UTF-8 without BOM, LF/CRLF and an optional final newline; malformed/blank records are wholly concealed while other valid records remain browsable. Record mapping is disabled when concealment collapses source lines.
- Processing is local, read-only and bounded. Likely-secret concealment is conservative and heuristic; previews are not a guarantee of detecting every secret.
- Thumbnails draw only concealed pipeline output or validated document images, for formats whose policy allows it and only while the content-thumbnail switch is on; sensitive formats keep a generic glyph ([decision 022](docs/decisions/022-content-thumbnails.md)). No document scripts or remote content run.
- Display branding is replaceable. Preferences and technical identities remain independent of the visible name.
- Appearance-only changes restyle loaded safe text without rereading its source. Reset Appearance preserves file-type choices; saved schemas 1–5 migrate strictly to schema 6, retaining earlier fields and defaulting only new ones.
- App-authored UI text uses localized resources. Fourteen selected languages have complete draft resource coverage; native-speaker review and real Finder language behavior remain release gates.

## Contributing a format

Follow [the format extension workflow](docs/decisions/001-format-extensibility.md). Add a focused adapter, catalog/registration entry and fixtures. Reuse shared budgets, privacy policy and presentations; a normal format addition should not change host or orchestration logic. Update plan checkboxes only for verified deliverables and record changes in the changelog.

## Localization resources

Edit canonical English resources and per-language inputs under `tools/localization/translations/`, then run:

```sh
python3 tools/merge_localizations.py
python3 tools/generate_localization.py
python3 tools/validate_localization.py
```

The generated `.strings` and `.stringsdict` files support the Command Line Tools build and are never edited independently. Plural keys are written as one form per category in the translation inputs (`tools/localization/README.md`), generated into `.stringsdict` resources and read through `PreviewStrings.count`; the validator checks every language's categories. New keys from a parallel workstream arrive through an additions file under `tools/localization/additions/` (`tools/add_localizations.py`). Branding metadata has its own catalog in `Configuration/Metadata.xcstrings`; imported file-type descriptions reuse the format localization catalog through the same build-time generator. The selected language set and draft-review boundary are documented in [the language decision](docs/decisions/008-languages-and-appearance-transfer.md). Complete key coverage does not replace native-speaker or host/UI review.

## Shared-settings configuration errors

A signed build can still contain compile-only identifiers. Setting a development team in Xcode does not replace `PREVIEW_BASE_BUNDLE_IDENTIFIER` or `APP_GROUP_IDENTIFIER`. An extension built with `group.invalid.*` deliberately declines to load content; opening the companion alone cannot fix that configuration.

Use the ignored `Configuration/Local.xcconfig` to configure the same App Group for the companion and both extensions, then run `./script/build_and_run.sh --verify`. For this macOS-only app, a group prefixed with the signing team's identifier is supported without a provisioning profile; `group.*` identifiers require the applicable provisioning setup. See [Apple's container guidance](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). Technical identifiers must remain stable when display branding changes.

After rebuilding, close and reopen Quick Look or select another file to create a fresh request. Existing previews may retain earlier content. The [signed-settings validation record](docs/validation/shared-settings-configuration.md) documents the diagnosed placeholder build, local configuration and actual Finder checks. Do not reset system Quick Look caches or weaken settings validation to hide this failure.
