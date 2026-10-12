# 017 — Package, certificate, disk-image and torrent inspection

Date: 2026-10-05. Status: implemented locally with package, renderer, pipeline and adversarial-corpus evidence; Finder routing, thumbnails, VoiceOver, native-speaker review and signed-host behavior are unverified. Validation is recorded in [the packages report](../validation/packages-2026-10-05.md). This is the `packages` workstream of [the competitor parity program](025-competitor-parity-program.md).

Amended 2026-10-06 by [decision 027](027-best-in-class-quality-program.md) (Q-13, owner decision D17a): the summary formats open on Summary as this record says, and decision 014's "Files is the initial mode when available" carries the exception. Authored in a cloud session without a compiler; the Mac verification is queued in [the pending queue](../validation/pending-mac-verification.md).

## Scope

Eight independently switchable logical types, each a summary presentation written by `SummaryWriter` (so concealment ranges are generated with the text) and shown in Summary mode through one localized `SummaryLabelSet`. Where the file has a file list, the summary carries the standard listing `entries` array (`path`, `type`, `bytes`, optional `modified`), so the Files and Tree modes of the listings workstream apply without a change here.

| Format ID | Type (system or imported) | Suffixes | Group | Thumbnail |
|---|---|---|---|---|
| `package.application` | system `com.apple.application-bundle` (a directory) | `app` | Containers | `content` (icon) |
| `package.ios-app` | system `com.apple.itunes.ipa` | `ipa` | Containers | `content` (icon) |
| `package.android` | imported `org.webmeister.spacepane.type.apk` and `.aab` (both conform to `public.zip-archive`) | `apk`, `aab` | Containers | `generic` |
| `config.provisioning-profile` | system `com.apple.mobileprovision`, `com.apple.provisionprofile` | `mobileprovision`, `provisionprofile` | Containers | `generic` |
| `security.certificate` | system `public.x509-certificate` | `cer`, `crt`, `der`, `pem` | Containers | `generic` |
| `package.installer` | system `com.apple.installer-package-archive` | `pkg` | Containers | `generic` |
| `disk.image` | system `com.apple.disk-image-udif` | `dmg` | Containers | `generic` |
| `data.torrent` | imported `org.bittorrent.torrent` (conforms to `public.data`; recorded as a system type until 2026-10-06, when the hosted macOS runner showed the identifier is declared only by third-party apps) | `torrent` | Containers | `generic` |

Provisioning profiles and certificates are in the Structured group; the other six, including torrents (whose summary is a file listing), are in Containers. At integration the companion model check was changed to derive the Structured group's membership from the catalog instead of pinning its original thirteen members.

On the development Mac (macOS 27.2) `.apk` and `.aab` resolve to dynamic types, so both use app-selected imported declarations like the SRT/NFO precedent in [009](009-first-expansion-formats.md). A file named `x.app` resolves to `com.apple.application-file`, not the directory bundle type; classification therefore uses the suffix first, and the adapter declines a non-directory `.app`. Credentials, certificates, profiles and environment-like files stay `generic` for thumbnails: their content must never be drawn. No type claims `public.data`, `public.item` or `public.content`.

## Shared-contract changes

All additive; no existing format's behavior changes.

- **One new preview mode, `Icon`** (`NativePreviewMode.icon`, localized title, `PackageIconView` registered through `SafeModeViewRegistry`). It appears only when the presentation carries a `PreviewImage` of role `.icon`. Summary stays the initial mode. The ebooks workstream's Pages mode must filter on image role, or an application would offer both.
- **Two status-line notices** through `PresentationNotices`: signatures are shown as stored and not verified, and notarization is not checked (applications, installers, profiles); certificates are shown as stored and trust and revocation are not checked.
- **`XARArchiveReader`**, extracted from `XIPListingAdapter`, is the one XAR reader for XIP and installer packages. XIP output is unchanged; its existing tests pass untouched. It also reports the table of contents' file tree and the certificates of its signature element.
- **`SummaryFields`** and `PackageSummary` (family-local helpers) bound text, list sizes and listing capacity. The listing capacity keeps a large archive inside the node and line budgets by marking the listing partial rather than failing the whole preview (the shared `listingDocument` throws `tooManyNodes` above roughly 2,800 entries at the default budget).

## Format decisions

**Applications (`.app`).** A URL adapter with the directory policy, like the folder adapter. It opens `Contents/Info.plist` (or a root `Info.plist` for shallow bundles), the first 4 KiB of the executable named by `CFBundleExecutable` and one `.icns`, each by descriptor-relative `openat` with `O_NOFOLLOW`; a symlink inside the bundle can never lead outside it, FIFOs and devices are never opened, and every read draws on the request's input allowance. The Mach-O header gives thin or universal layout and the architecture names (`arm64`, `arm64e`, `x86_64`, ...). The code signature is read through `SecStaticCodeCreateWithPath` and `SecCodeCopySigningInformation(kSecCSSigningInformation)`: identifier, team identifier, certificate subject names, hardened-runtime flag (code-directory flag `0x10000`), App Sandbox entitlement presence, entitlement keys with their bounded values (values under credential-looking keys concealed), ad hoc versus signed, and unsigned (Security can succeed with only the main executable for unsigned code, so a missing identifier means unsigned). `SecStaticCodeCheckValidity` is never called: no resource is hashed, no trust is evaluated, nothing is checked for revocation and notarization is not queried, and the summary says so (`signatureVerified: false`, `notarizationChecked: false`). A Security failure, which can happen inside the Quick Look sandbox, is reported as "not available". Only a PNG representation of an `.icns` is extracted; asset-catalog icons (`Assets.car`) are a private format and are skipped. The bundle size is a bounded, non-following walk (25,000 items, depth 32, 35% of the request deadline) flagged partial when it stops.

**iOS archives (`.ipa`).** The shared bounded ZIP reader lists the archive; only three members are ever read: `Payload/<name>.app/Info.plist`, `embedded.mobileprovision` (same parser as profiles) and one icon PNG chosen from `CFBundleIconFiles`, the primary icon set or the asset-catalog icon name, largest first, tried three times, and only if ImageIO accepts it. Apple's size-optimized `CgBI` PNGs that ImageIO declines are omitted. A broken profile or icon omits that part, not the preview. URL scheme names and usage-description prose are not shown, only counts and key names.

**Android packages (`.apk`) and App Bundles (`.aab`).** Two manifest readers of our own feed one summary. An APK keeps compiled binary XML: string pool in UTF-8 or UTF-16, optional resource-id map (used when a packer stripped an attribute's name string), element chunks and typed attribute values. A bundle keeps aapt2's protobuf `XmlNode` under `base/manifest/AndroidManifest.xml`: a bounded wire-format reader checks every varint and length against the remaining input and reads only element names, attribute names and text values (compiled items, source positions and namespace declarations are skipped; an attribute value over 4 KiB is dropped, not fatal). The format is chosen by the manifest's first bytes, never by the suffix, and a manifest of neither kind is unsupported. Package name, version code and name, minimum, target and compile SDK, permissions (deduplicated, 512 stored, 64 shown), component counts and the debuggable flag. Resource references (such as a label) are not resolved because the resource table is never read. Metadata elements are not extracted, since they commonly carry API keys.

**Provisioning profiles.** `CMSDecoderCreate` / `CMSDecoderUpdateMessage` / `CMSDecoderFinalizeMessage` / `CMSDecoderCopyContent` reach the plist; the signer status is never requested, so no validity is claimed. Unsigned XML or binary plists are accepted as they are. The summary shows name, UUID, App ID name, team, platforms, dates, an expired flag against an injected clock, a profile kind derived from the contents (development, ad hoc, enterprise, distribution), entitlements with credential-looking values concealed, the number of provisioned devices (identifiers are never shown) and the subject names of embedded certificates (never their bytes).

**Certificates.** DER or PEM through `SecCertificateCreateWithData`; subject and issuer names, serial number, validity dates and expired flag, public key algorithm and size, subject alternative names (`SecCertificateCopyValues`) and SHA-256 and SHA-1 fingerprints over the exact DER (CryptoKit). PEM blocks are located by label; a private-key block of any kind (`PRIVATE KEY`, `RSA`, `EC`, `DSA`, `ENCRYPTED`, `OPENSSH`, PGP armor) is counted and its label recorded and its body is **never base64-decoded, parsed, summarized or copied**; a file that holds only a key still previews, as "private keys (contents hidden)". Trust, chain building and revocation are never evaluated.

**Installer packages (`.pkg`).** The XAR table of contents becomes the listing. `Distribution` (title, product version, minimum OS, host architectures, component references) and each component's `PackageInfo` (identifier, version, install location, size, file count, script file names from `<scripts>`) are the only members read. Payload, bill of materials and script contents are never read or shown. Signing certificates in the table of contents are shown by subject name only, with `signatureVerified: false`. Bundle-style (directory) packages are not flat archives and are declined by the shared reader as "not a regular file".

**Disk images (`.dmg`).** UDIF only: the 512-byte `koly` trailer (version, flags, data-fork length, segment count, sector count) and the XML property list it points to for each partition's name, size and compression methods. Partition data is never read or decompressed and nothing is mounted. Encrypted images (`encrcdsa`, `cdsaencr`) report `encryptedContent`. Images without a UDIF trailer (raw, sparse) are unsupported. A partition table larger than the read allowance is omitted and the summary is flagged partial.

**Torrents.** A strict bencode reader of its own: canonical integers within `Int64`, lengths checked against the remaining input, no duplicate keys, no trailing data, bounded depth and node count. Name, layout, file listing (version 1 `files`/`length`, version 2 `file tree`, padding files skipped), total size, piece length and count, private flag, creation date, creator, comment, the version 1 info-hash (SHA-1 over the exact bytes of the `info` value) and the version 2 hash (SHA-256) when `meta version` is 2. Announce and web-seed URLs are reduced to scheme, host and port because paths and queries carry private per-user passkeys; a comment or creator string that looks credentialed (keywords, or a URL with a query or user information) is concealed whole. Nothing is contacted.

## Privacy

Every summary is concealed at the same stage as every other format: assignment-like text, listed paths, names and credential-looking entitlement values are covered by `SummaryWriter` ranges and the shared filter's value patterns. Derived views read only the concealed text. Specific guarantees, each with tests:

- Private-key material never appears in any representation, including sensitive ranges, copy text and summary fields.
- Provisioned device identifiers, certificate bytes, tracker paths and passkeys, script and payload contents, URL scheme names and usage-description prose are never extracted.
- The only `PreviewImage` produced is an application icon, which is document content and carries no text this app interprets.
- No format adds a thumbnail that draws content except the two icon formats, which depend on the thumbnails workstream and its `content` policy.

## Safety and limits

All adapters begin with a cancellation and deadline check before any input access, charge reads to the cumulative input allowance, and use typed failures. Default budget (1 MiB input, 20,000 nodes, 2 s):

| Input | Limit |
|---|---|
| Application | Info.plist 1 MiB; executable header 4 KiB; icon file 2 MiB and PNG 256 KiB, 2,048 px; walk 25,000 items; every read counts against the input allowance |
| IPA / APK / AAB | The shared ZIP reader's entry and directory limits; Info.plist 1 MiB, profile 256 KiB, icon PNG 256 KiB; Android manifest 2 MiB, depth 64, nodes from the request budget; listing capacity about 2,165 entries at the default budget |
| Profile | Decoded content within the input budget; plist validated by the shared bounded plist path first; 16 certificates, 64 entitlement keys, three levels of nesting |
| Certificate | 64 PEM blocks, 32 certificates, 96 KiB per DER certificate, 64 alternative names |
| Installer | Table of contents within the metadata cap (2 MiB) and its nodes within the request budget; Distribution 512 KiB; 32 PackageInfo members of 256 KiB; 8 signing certificates |
| Disk image | Partition table 768 KiB and what remains of the allowance; 128 partitions; 100,000 block runs per partition |
| Torrent | Whole file within the input budget; depth 32; 250,000 nodes; 18-digit integers; 32 trackers |

Foundation's property-list and XML parsers never see input that the shared bounded checks have not accepted (entities and document types are refused). Nothing here extracts to disk, follows a link out of its container, executes a script, loads a referenced resource or opens the network.

## System frameworks

Newly imported by `PreviewFormats`, all part of the macOS SDK and extension-safe: **Security** (`SecStaticCode`, `SecCertificate`, `CMSDecoder`), **CryptoKit** (SHA-1, SHA-256) and **ImageIO** (icon validation; `PreviewRenderers` also uses it for bounded icon decoding). No package dependency, no new target and no entitlement. Inside the Quick Look sandbox the Security signing calls may be denied, in which case the signature section reads "not available"; this has not been observed in a signed host.

## Not promised

- Finder routing, preview or thumbnail invocation for any of these types, including `.app` directories, which a Quick Look host may not hand to a third-party extension, and `.apk`, which has no system type.
- That a signature, profile, certificate or package is valid, trusted, current, unrevoked, notarized or safe.
- Large applications: the shared reader charges every central-directory record and local header to the 1 MiB allowance, so an IPA, APK or AAB with more than roughly 3,000 members reports "too large" rather than a partial summary. A larger budget or a tolerant mode in `ZIPArchiveReader` would lift this; it belongs to the lead.
- Asset-catalog icons, resource-table label strings, per-module summaries of a bundle (only the base module's manifest is read), `.p12`/`.pfx`, `.mpkg`, sparse images and encrypted images.
- Contents of scripts, payloads, partitions, `Assets.car` or any file inside a package.

## Consequences

Eight formats were added by adapters, catalog entries, registrations, one label set and fixtures, plus the small additive presentation capability above. The localization additions are 128 keys (112 typed `preview.package.*` and the icon mode title, 16 catalog names and descriptions) in all 14 languages as drafts pending native-speaker review.
