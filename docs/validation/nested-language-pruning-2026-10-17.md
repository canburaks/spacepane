# Draft languages in the nested resource bundle, and the privacy-manifest reasons (2026-10-17)

Findings 16 and 21 of [the rejection-risk review](../reviews/2026-10-17-app-store-rejection-risk.md). Mac, Xcode 27.1, macOS 27.2, signed archive of 1.1.0 (5) built from this branch; compared with the submitted archive `.build/archive/SpacePane-1.1.0-build5.xcarchive`. Nothing was installed, enabled in Finder or uploaded.

## Finding 16: what the build 5 archive does

Build 5 carries 45 `.lproj` folders: `en` at the top of the app and of each extension (3), and 14 languages in each of the three copies of `PreviewCore_PreviewRenderers.bundle` (42). The repository records that the 13 drafts stay unreachable because macOS resolves a nested bundle's language through the host (observed on 2026-10-12). That holds for the companion and does not hold for the extensions.

Probe (a scratch Swift program, not in the repository): copy one shipped host from the archive to a temporary folder, put the probe inside it as `Contents/MacOS/probe` so that `Bundle.main` is that host, launch it with `-AppleLanguages "(de)"` or `"(tr)"`, and ask the nested bundle for `about.acknowledgements.body` with no language preferences, which is what `PreviewStrings.text` does.

| Host (main bundle) | `Bundle.main.localizations` | system language `tr` | system language `de` |
|---|---|---|---|
| `SpacePane.app` | `en` | English | English |
| `PrevPreviewExtension.appex` | `en` | **Turkish** (`3B model önizlemeleri…`) | **German** (`3D-Modellvorschauen verwenden…`) |
| `PrevThumbnailExtension.appex` | `en` | **Turkish** | **German** |

So in build 5 a Mac whose system language is one of the 13 draft languages is expected to show draft translations in Finder previews while the companion and the store page stay English. This is a simulation: it stages a copy of each host and sets the language by launch argument, and it is not a Quick Look process started by Finder. The 2026-10-12 observation presumably used the companion as host; the extensions behave differently. Treat build 5 as exposed until a Finder run under a German or Turkish system language says otherwise.

## What changed

| Piece | Where |
|---|---|
| `script/prune_resource_languages.py` removes every `.lproj` outside `shipped` in `tools/localization/languages.json` from the named nested bundle; refuses a bundle that would lose the development language | 21 tests in `script/test_prune_resource_languages.py` |
| A "Prune draft languages" run-script phase in `Prev`, `PrevPreviewExtension` and `PrevThumbnailExtension`, after the resources are copied and before signing | `Prev.xcodeproj/project.pbxproj`; wiring tests in the same test file |
| `script/prune-outputs.xcfilelist` declares the 39 paths the phase deletes, so `ENABLE_USER_SCRIPT_SANDBOXING = YES` stays | checked against the draft folders by a test |
| `script/check_release_archive.py` fails an archive whose nested bundle carries a non-shipped `.lproj` (it noted them before) | 5 cases in `script/test_check_release_archive.py` |
| `script/check_bundle_localizations.py` and `Tests/Integration/LocalizedBundleChecks.swift` add the no-preference lookup, staged as each host, once per chosen language | run against both archives below |

Why the outputs are a file list and not the bundle: the resource copy already produces `PreviewCore_PreviewRenderers.bundle`, and declaring it again fails with "Multiple commands produce". The sandbox allows a script to write only to declared outputs. That was seen directly: a first version that declared a stamp file failed with "Operation not permitted" once DerivedData lived inside the repository. (Under `/tmp` the sandbox rules never matched, because Xcode passes the `/tmp` symlink path; a build there proves nothing.) The drafts stay in the repository and in the SwiftPM package; the unpruned intermediate `Products/…/PreviewCore_PreviewRenderers.bundle` is not shipped.

## Archive comparison

`find <app> -name '*.lproj'`: 45 before, 6 after.

| Path inside `SpacePane.app` | build 5 | this branch |
|---|---|---|
| `Contents/Resources/en.lproj` | yes | yes |
| `Contents/Resources/PreviewCore_PreviewRenderers.bundle/Contents/Resources/*.lproj` | 14 (`bn de en es fr ha hi id ja ku-Latn pt ru tr zh-Hans`) | `en` |
| `…/PrevPreviewExtension.appex/Contents/Resources/en.lproj` and nested bundle | `en` + 14 | `en` + `en` |
| `…/PrevThumbnailExtension.appex/Contents/Resources/en.lproj` and nested bundle | `en` + 14 | `en` + `en` |
| `PrivacyInfo.xcprivacy` in the app and both extensions | 3 | 3 |
| Size of the app folder | 24,976 KB | 19,816 KB |

`codesign --verify --deep --strict` passes on the new app; the pruning ran before signing.

## Checks and results

| Check | Result |
|---|---|
| `python3 script/test_check_release_archive.py` | 127 tests OK (four nested-language cases and five manifest cases failed first, for the reasons in the test names) |
| `python3 script/test_prune_resource_languages.py` | 25 tests OK in the final tree (21 for the script, 4 for the project wiring) |
| `./script/build_and_run.sh --check-static` | OK, 24 passed, 1 skipped (tree-sitter is not installed) |
| `./script/build_and_run.sh --archive` | built and checked; `check_release_archive.py` passed: 3 Mach-O files, 3 sandboxed bundles, 3 privacy manifests, no CAD |
| `script/check_release_archive.py` on `.build/archive/Release.xcarchive` | passed |
| `script/check_bundle_localizations.py` on the new app | passed: 4 explicit cases and 14 no-preference cases, 3 hosts, 1,281 keys |
| the same script on the build 5 app | **fails**: preview host under system language `tr` returns Turkish |

The build 5 archive was not changed by any of this.

## Finding 21: the manifests

Thumbnail request path, read in `Packages/PreviewCore/Sources/PreviewThumbnails` and `Extensions/PrevThumbnailExtension`: `ThumbnailPolicyEvaluator.resolve` returns the glyph (`genericPolicy`) for every format whose catalog entry is not `thumbnail == .content` with a text presentation, which includes folders, archives and MIDI, before any adapter is built. The only reader of a modification time for display is `FolderScan.swift`, and the only reader of the system uptime is `NativeMIDIPlayback.swift`; no thumbnail request reaches either.

- `DDA9.1` is removed from the thumbnail manifest. The category stays, with `3B52.1` and `C617.1`, because the extension calls `lstat` and `fstat`.
- `35F9.1` stays. Apple's upload validation reads which APIs a binary references. The thumbnail executable references `systemUptime` (`strings` on the build 5 binary: one hit, in all three executables) because the renderer module is linked statically, so removing the category would invite ITMS-91053. This differs from the instruction to remove it; the manifest comment says why. Removing the reference needs a Swift change (move the MIDI clock out of the module the thumbnails link) and is not part of this branch.
- Apple's list was read again on 2026-10-17 from the page behind `…/nsprivacyaccessedapitype`: file timestamps `DDA9.1`, `C617.1`, `3B52.1`, `0A2A.1` (SDK wrappers only); boot time `35F9.1`, `8FFB.1`, `3D61.1`. Unchanged since 2026-10-06. There is **no** code for metadata of files an app finds for itself. The provider scan takes only `st_mode` and `st_size` (`lstat`, `fstat`) of application bundle files, so the companion keeps `3B52.1` and its comment names `QuickLookProviderScanner.swift` and the gap. Whether to keep the scan is the owner's call; the declaration is the closest one available, not an exact fit.
- Each manifest comment now names, per reason code, the Swift file that needs it; a test checks that the files exist and that the thumbnail declares no `DDA9.1`.

## Not done

- Nothing installed or run in Finder, so the pruning is established for the archive contents and for the staged-host simulation only, not for a Quick Look process. A run under a German system language on build 5 would confirm the probe; it is worth doing before relying on the table above.
- The build number is still 5. A resubmission needs a bump (the manifests session owns `Base.xcconfig`).
- `script/validate_project.py` does not check the new phases; `test_prune_resource_languages.py` does, for now.
