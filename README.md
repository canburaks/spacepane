# SpacePane

SpacePane adds Quick Look previews for the files your Mac can't show yet. Select a file in Finder, press Space, and see what is really inside. Everything happens on your Mac: files are only read, and nothing inside them is run.

Website: [spacepane.com](https://spacepane.com)

## Features

<table>
<tr>
<td width="50%"><img src="docs/release/store-listing/screenshots/02-secrets-concealed.png" alt="A settings file in Quick Look with its password and token concealed"></td>
<td width="50%"><img src="docs/release/store-listing/screenshots/03-notebooks.png" alt="A Jupyter notebook rendered in Quick Look with its saved output"></td>
</tr>
<tr>
<td><b>Likely secrets concealed.</b> Passwords, tokens and keys are hidden, even in the source view, and the preview says how many were hidden.</td>
<td><b>Notebooks, shown but never run.</b> Jupyter notebooks render with their cells and saved output.</td>
</tr>
<tr>
<td><img src="docs/release/store-listing/screenshots/05-archives.png" alt="A ZIP archive's contents listed as a tree in Quick Look"></td>
<td><img src="docs/release/store-listing/screenshots/06-markdown.png" alt="A Markdown file rendered in Quick Look with a table of contents"></td>
</tr>
<tr>
<td><b>Archives without extracting.</b> ZIP, TAR, 7z, RAR, app bundles, installers and disk images list their contents with sizes and dates.</td>
<td><b>Markdown and code.</b> Markdown renders with a table of contents; source code, logs and other markup are shown natively.</td>
</tr>
<tr>
<td><img src="docs/release/store-listing/screenshots/09-theme.png" alt="The companion app's Theme page with color schemes and a live preview"></td>
<td valign="top">
<b>Your colors and fonts.</b> The companion app's Theme page changes colors, fonts and spacing, with a live sample. Its File Types page turns each file type on or off.
<br><br>
<b>Also:</b> JSON, YAML, TOML, XML, property lists, CSV, Parquet, SQLite, certificates, MIDI, 3D meshes and more. Safety Lens points out hidden characters, risky archive entries and what a script or package would do.
</td>
</tr>
</table>

macOS decides which installed app previews each file type; SpacePane cannot override it.

## Build locally

Requires macOS with full Xcode (Swift 6.2 or later), Python 3 and an Apple Developer team for signing.

```sh
cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
# Fill in DEVELOPMENT_TEAM, PREVIEW_BASE_BUNDLE_IDENTIFIER and APP_GROUP_IDENTIFIER
./script/build_and_run.sh
```

The script builds, signs and launches the companion app. If `xcode-select` points at the Command Line Tools, first run `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run the tests with `./script/build_and_run.sh --test`.
