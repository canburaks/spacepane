# Finder format matrix — 2026-10-04

## Method and scope

On Apple M5 Pro / macOS 27.2 (26B5091g), generated 22 synthetic fixtures with
`script/generate_host_fixtures.py` into the unique ignored directory
`.build/host-validation/matrix-s4hd8ww8`. The companion was quit normally and
`pgrep -x Prev` returned no process throughout the Finder sweep. Each fixture
was selected in Finder and opened with Space using native UI automation.
No provider preferences, shared Quick Look caches or Finder processes were reset.

The active preview process was PID 36009, from the previously signed development
artifact under `~/Library/Developer/Xcode/DerivedData/Prev-bosallybkatpeoahvdcemrlwmrbk/Build/Products/Debug/Prev.app`.
Its extension uses the agreed technical identity. The canonical `.build/xcode`
artifact was rebuilt separately during this pass; Finder observations below do
**not** prove Finder loaded the newest XML/cancellation fixes. They establish
routing and existing renderer behavior of the observed installed artifact.

`script/check_host_fixtures.py` uses the production pipeline to independently
check all 22 fixtures, safe output and source-file hashes. Resolved types below
come from Foundation URL content-type resource values, not filename assumptions.
Every row passed the pipeline check. All fixtures are synthetic; the only secret
marker is intentionally disposable. MIDI contains a five-second timeline and a
zero-volume controller event, with no note events.

## Space-bar observations

“Prev” identifies the app-specific controls and presentation, correlated with the
running configured extension process. It is not a guarantee for all suffixes,
Finder surfaces, OS versions or competing-provider installations.

| Logical type | Declared types | Resolved fixture type | Observed Space-bar outcome |
|---|---|---|---|
| `text.plain` | `public.plain-text` | `public.plain-text` | Other provider; raw synthetic assignment visible |
| `text.source-code` | `public.source-code` | `public.swift-source` | Other provider; raw synthetic assignment visible |
| `data.json` | `public.json` | `public.json` | Prev concealed source |
| `data.json-lines` | `org.jsonlines.jsonl`, `public.ndjson` | `com.quicklookpro.file.jsonl` | Generic icon/metadata; no Prev content |
| `data.yaml` | `org.yaml.yaml`, `public.yaml` | `public.yaml` | Prev concealed source; structured view unavailable |
| `data.toml` | `org.toml.toml`, `public.toml` | `public.toml` | Prev concealed source |
| `config.environment` | `com.canburaksofyalioglu.filepreview.type.environment` | `public.data` | Generic icon/metadata; no Prev content |
| `config.package-json` | `public.json` | `public.json` | Prev concealed source; Outline/Summary controls present |
| `text.markdown` | `net.daringfireball.markdown` | `net.daringfireball.markdown` | Prev concealed source |
| `text.diff` | `org.gnu.diff`, `public.patch-file` | `public.patch-file` | Prev concealed source |
| `data.xml` | `public.xml` | `public.xml` | Prev concealed source |
| `data.property-list` | `com.apple.property-list`, `com.apple.binary-property-list` | `com.apple.property-list` | Prev concealed source |
| `config.strings` | `com.canburaksofyalioglu.filepreview.type.strings`, `com.apple.xcode.strings-text` | `com.apple.xcode.strings-text` | Prev concealed source |
| `config.strings-dictionary` | `com.canburaksofyalioglu.filepreview.type.strings-dictionary`, `com.apple.xcode.strings-dictionary` | `com.apple.xcode.strings-dictionary` | Prev concealed source |
| `data.opml` | `org.opml.opml` | `org.opml.opml` | Prev source/summary |
| `database.sqlite` | `org.sqlite.sqlite` | `org.sqlite.sqlite` | Prev summary; one table, bounded rows, concealment notice |
| `archive.zip` | `public.zip-archive` | `public.zip-archive` | Prev source/summary |
| `archive.tar` | `public.tar-archive` | `public.tar-archive` | Prev source/summary |
| `archive.gzip` | `org.gnu.gnu-zip-archive` | `org.gnu.gnu-zip-archive` | Prev concealed source |
| `archive.xip` | `com.apple.xip-archive` | `com.apple.xip-archive` | Prev summary; signature explicitly unverified |
| `container.folder` | `public.folder` | `public.folder` | Prev summary; one immediate child, no recursion |
| `audio.midi` | `public.midi-audio` | `public.midi-audio` | Prev summary; initial failure repaired; rebuilt host Play/Pause/scrub/end verified below |

Eighteen fixtures reached the app-specific presentation; four did not. `.txt`
and `.swift` visibly showed the raw synthetic assignment through another provider.
The app cannot guarantee concealment when macOS selects another provider.
`.env` resolved to `public.data`; broad ownership of that type is intentionally
not claimed. JSON Lines resolved to another installed product's identifier.

SQLite showed a read-only summary with one table and bounded row/cell metadata.
TAR/ZIP listed one entry. XIP listed CPIO contents without signature verification.
GZIP showed concealed decompressed text. OPML and property/localization resources
showed their safe source modes. This sweep does not establish every interactive
outline expansion or SQLite paging gesture. Previous Markdown rendered-mode and
ZIP expansion observations remain in the earlier continuation report.

## Playback and remaining host gates

MIDI's explicit Play action returned the localized “The macOS sound bank could
not be loaded.” state. Controls were visible and playback was not automatic.
At that stage playback, pause, scrubbing and audible output were **not**
validated; the rebuilt-artifact follow-up below supersedes the transport failure. The system resource exists on this host; file existence alone does not
establish sandbox access, Bundle lookup or AudioUnit initialization. The failure was diagnosed and retested as recorded below.

No per-format Finder thumbnail result is claimed here. Prior public
`QLThumbnailGenerator` invocation proved the configured thumbnail extension ran,
including while the companion was stopped; it did not validate every Finder
thumbnail surface or all 22 formats. Those checks, macOS 15 runtime, Intel,
competing providers, cold lifecycle and effective extension languages remain open.

The native automation occasionally rejected input after Quick Look changed its
window binding. Refreshing the app binding and observing fresh controls allowed
the sweep to continue. Failed actions were not counted as preview observations.
The independent Customization inspection-service crash remains a different tool
limitation, documented in the UI-quality report.

## Rebuilt-artifact follow-up

Both the canonical `.build/xcode` app and the registered DerivedData artifact were
rebuilt successfully from the final MIDI/XML/UI sources and strictly code-signature
verified. The previous preview process had exited naturally after closing Quick
Look; no process kill or cache reset was used. Finder then launched PID 46482 from
the rebuilt registered preview extension, while the companion remained stopped.

The old MIDI check opened an assumed system-bank file directly from the extension
sandbox, even though the Apple DLS graph had already initialized. The repair queries
`kMusicDeviceProperty_SoundBankURL` only as optional metadata on the actual unit,
with runtime support/size checks and Core Foundation ownership. Playback success
follows audio initialization/start/event results. The extension does not open the
bank file, accept a document-supplied bank, or gain any new entitlement.

For the same silent five-second fixture, actual Finder controls demonstrated:

- Play changed to Pause and advanced to approximately 0.32 seconds.
- Pause changed back to Play and held around 0.44 seconds.
- Setting the scrubber to 3 displayed `00:03 / 00:05`.
- Resume advanced beyond 3 seconds; natural completion reached 5 and restored Play.

This validates the repaired sandboxed transport lifecycle. It deliberately does
not verify audible note output, timbre quality, every MIDI format/event combination,
macOS 15 or other audio devices. Mock-device event tests and a separate real silent
audio-graph smoke check complement this observation.

A fresh XML regression fixture in `.build/host-validation/xml-regression-0lcalzhf`
contained synthetic assignments inside both a processing instruction and CDATA.
The rebuilt Finder extension visibly produced:

```xml
<?inert ••••?><root><![CDATA[••••]]><safe>visible</safe></root>
```

The source SHA-256 stayed unchanged. This is actual installed-host evidence for
the new XML fix, separate from the earlier 22-format sweep on the prior artifact.
The 22 original fixtures also passed the final pipeline/hash verifier; all file
bytes and file entries matched their creation manifest after the Finder sweep.
