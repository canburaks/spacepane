# Expansion research: everyday, hobby and personal-data files

Researched 2026-10-13 (Europe/Istanbul). Angle: files that people outside work meet in Finder as a blank icon (students, teachers, hobbyists, gamers, musicians, athletes, families) and that SpacePane could preview with its existing native presentations. One of eleven parallel angle reports; the lead merges them.

## Method and limits

- **Competitor check.** I read [the 2026-10-05 competitor landscape](../2026-10-05-competitor-landscape.md). I opened Unfold's [published list of 262 extensions](https://unfold.tools) and checked 22 hobby suffixes against it: none appears. LookQuick's page says only "1000+ extensions" and publishes no list, so its coverage of these types is **unknown**, not absent. I ran 20+ iTunes Search API queries (`https://itunes.apple.com/search?term=...&entity=macSoftware&limit=12&country=us`; terms such as "embroidery quick look", "pgn viewer", "whatsapp chat export viewer", "anki quick look", "gedcom viewer", "musicxml viewer", "fit file viewer garmin", "minecraft schematic viewer", "scratch sb3 quick look") and web searches of the form "<format> quick look mac". The iTunes API returns apps, not their extensions, so a hit means "an app exists", not "it ships a Quick Look extension". I tested no competitor.
- **Local checks (verified on this Mac, macOS 27.2).** I created empty files for 50 suffixes and read `kMDItemContentType` with `mdls`, read Apple Chess.app's `Info.plist`, and tested which system fonts carry chess glyphs through CoreText. A `dyn.*` result means no installed app declares the suffix (this Mac has many developer apps installed, so a typical Mac is at least as bare).
- **Evidence labels.** *Verified* = I opened the source or ran the check. *Reported* = appeared only in a web-search result summary that I did not open. *Vendor claim* = the maker's own page. *Inference* = my own reasoning or background knowledge, not checked in this session. Anything with no label is verified.
- **Limits.** WebSearch is US-only and returns summaries, so audience numbers are secondary and often conflicting; I give ranges and say so. I measured no Mac share for any hobby. I downloaded no sample files and parsed nothing. Depth was uneven: candidates 1 to 11 got real research; candidates 12 to 17 and the "not researched" rows at the end got little.

## Key findings

1. **The brand-fit pattern is "files that are private or a liability by nature".** Password-manager exports, chat exports, health exports, family trees and streaming histories all invite typed findings, concealment, "no content in thumbnails" and a plain-words summary. No competitor in the landscape document claims a file-level finding such as "this file holds 312 logins in readable form" (inference from vendor claims; untested). This is the one angle where SpacePane's shipped Safety Lens is a reason to buy, not table stakes.
2. **Two visual headlines can replace the cut STEP/IGES story.** Minecraft structures (`.litematic`, `.schem`, `.nbt`) reuse the shipped Metal mesh renderer, and chess games (`.pgn`) get a native board. Neither is offered by any Quick Look app I found; Minecraft has only browser tools ([Shulkr](https://www.shulkr.com/minecraft-schematic-viewer), a vendor page).
3. **macOS gives almost none of these a previewer.** 44 of the 50 suffixes tested resolve to `dyn.*` types; the other six are `.pgn`, `.gpx` (`com.topografix.gpx`), `.m3u`, `.pls` (public playlist types), `.exp` and `.abc`. `.pgn` is `com.apple.chess.pgn`, declared by Apple's Chess.app as conforming to plain text, and the app bundle contains no Quick Look extension or `PlugIns` folder. Two suffixes collide with unrelated system types: `.exp` (Melco embroidery) is `com.apple.symbol-export`, and `.abc` (ABC music notation) is `public.alembic`. A suffix-based registration cannot win those two; only content sniffing inside a provider that already receives them could.
4. **One new presentation would carry six insight layers.** A bounded bar and strip chart (messages per month, hours per year, QSOs per band, surnames, blocks by count) serves chats, personal-data exports, ham logs, genealogy, Scratch and activity files. A second, a small board/grid view, carries chess, Go and crosswords. Embroidery needs only a coloured polyline plot, close to the shipped offline geographic plot.
5. **Licence traps are real and specific.** Garmin's FIT SDK is under a proprietary "FIT Protocol License Agreement" (not open source), so Garmin `.fit` is parked. Verovio, the obvious engraving library, is LGPL, so it is out. Anki's modern packages need zstd, which is "BSD OR GPLv2" (take the BSD option). Bravura (SIL OFL 1.1), pyembroidery (MIT), lichess's opening table (CC0) and GEDCOM 7 (Apache-2.0) are all usable.
6. **Audience numbers are platform numbers, not file-handling-Mac-user numbers.** Chess.com (reported 250 million members), Minecraft (reported 350 million copies sold), Scratch (reported 100+ million registered) and Ancestry (3.6 million subscribers in a 2020 press release) say nothing about how many people keep `.pgn`, `.litematic`, `.sb3` or `.ged` files on a Mac. The only candidate with direct evidence of willingness to pay for a Finder fix is embroidery: $17.99, $24 (vendor claim), about $39 to $45, against one free incumbent.
7. **Routing caveat.** macOS sends each type to one provider. Candidates on unique suffixes (`.1pux`, `.litematic`, `.apkg`, `.sb3`, `.ged`, `.puz`, `.pes`) are likely to reach SpacePane. Candidates that live inside `.txt`, `.csv` or `.json` (WhatsApp `.txt`, password CSVs, Kindle clippings) compete with Apple's own previewers or with other apps, so I rank their ZIP or sniffing variants higher.
8. **Suggested order.** Ship the cheap Safety Lens items first (credential-export guard, personal-data recogniser), then chess, then Minecraft (the largest visual payoff and the largest effort), then Anki, GEDCOM, chats and embroidery as the second wave.

## Ranked candidates

Effort: S = days, M = 1 to 2 weeks, L = several weeks. "Native" = what macOS does today (local check on macOS 27.2 unless marked).

| # | Candidate (suffixes) | Audience (size evidence) | macOS native today | Quick Look competitor coverage | Route + licence | Reuses which presentation | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **Credential-export guard**: `.1pux`, Bitwarden `.json`/`.zip`, password-manager `.csv`, OTP-app backups, recovery-phrase text (detect only) | Every password-manager user at migration time; not sizeable. 1Password and Bitwarden both tell users to delete exports (see section 1) | `.1pux` is `dyn.*`; CSV goes to Apple's table preview (inference); JSON is text | None claims a file-level warning; QuickLook Pro and QuickestLook mask secrets in config files only (vendor claims) | ZIP + JSON reader, CSV header signatures; no dependency | Findings banner, summary facts, existing delimited concealment, sync-folder warning | S | **Lead with** |
| 2 | **Chess and Go game records**: `.pgn`, `.fen`/`.epd`, `.sgf` | Chess.com reported 250 M members; Lichess over 4 M active (forum, Jan 2023). PGN-downloading minority unknown | `.pgn` = `com.apple.chess.pgn` (plain text); no Quick Look extension in Chess.app. `.fen`, `.sgf` are `dyn.*` | None found; absent from Unfold's list | Own parser from the PGN standard; lichess opening table CC0; pieces from system fonts | New small board view + move list (outline/table) + text | M | **Lead with** |
| 3 | **Minecraft builds and worlds**: `.litematic`, `.schem`, `.nbt`, `.mcstructure`, `.mcworld`/`.mcpack`/`.mrpack`, `level.dat` | Reported 350 M copies, about 212 M monthly players, r/Minecraftbuilds about 1.3 M, Litematica 16.2 M Modrinth downloads | All `dyn.*` | None for Quick Look; browser viewers only (Shulkr, vendor claim) | Own NBT + gzip (system zlib); format docs public; no dependency | **Shipped Metal mesh renderer** (voxel mesher is new) + facts + material table | M (litematic, schem, nbt) to L (Bedrock, polish) | **Lead with** |
| 4 | **Chat exports**: WhatsApp `.zip`/`_chat.txt`, Telegram `result.json` | WhatsApp is among the largest apps (no figure verified); export users are a minority | `.zip` has no preview; `.txt` goes to Apple text | None found | Own parser; date formats vary by phone locale | Conversation view (new, simple), bar strip, findings | M | **Add** |
| 5 | **Anki decks**: `.apkg`, `.colpkg` | r/Anki reported 144 k to 320 k (conflicting); AnkiDroid reported 10 M+ downloads (community post) | Both `dyn.*` | None found | ZIP + zstd + SQLite + protobuf; zstd is BSD OR GPLv2 | Table, outline (decks), images, bar strip, SQLite reader | M | **Add** |
| 6 | **Family trees**: `.ged`/`.gedcom`, GEDZIP (`.gdz`) | Ancestry 3.6 M subscribers (2020 press); r/Genealogy reported 170 k to 259 k | `.ged`, `.gedcom`, `.gdz` are `dyn.*` | None found (old Mac apps only) | Own line parser; GEDCOM 7.0 spec is Apache-2.0 | Outline, table, native Diagram, findings | M | **Add** |
| 7 | **Embroidery**: `.pes`, `.dst`, `.jef`, `.exp`, `.vp3`, `.xxx`, `.hus` | Paid competitors at $17.99, $24 (vendor), about $39 to $45; free StitchBuddy | All `dyn.*` except `.exp` (collides with `com.apple.symbol-export`) | StitchBuddy (free, preview + thumbnails), MyEmbroids, ThreadView, Embrilliance Thumbnailer | Port of formats documented in pyembroidery (MIT) | Coloured polyline plot (like the geographic plot) + facts table | M | **Add** |
| 8 | **Personal-data exports**: Apple Health `export.zip`, Spotify extended streaming history, Takeout and Instagram archives | Apple Health exports commonly 1 to 5 GB (reported); Spotify export is a user right | ZIP lists nothing meaningful; JSON/XML are text | None found | ZIP central directory + bounded stream of `export.xml`; JSON arrays; no dependency | Summary facts, bar strip, offline route plot (workout GPX), findings | M (S for the ZIP recogniser alone) | **Add** (Health) / Niche (rest) |
| 9 | **Activity files**: TCX and GPX charts + laps, Zwift `.zwo`, `.erg`/`.mrc` | Zwift yearly concurrency peak 41,680 in Jan 2026 (reported); Strava/Garmin scale not measured | `.gpx` is `com.topografix.gpx`; `.tcx`, `.zwo`, `.erg`, `.mrc` are `dyn.*` | GPX Preview ($1.99) does GPX/KML/KMZ/TCX on a map (per landscape doc) | XML; no dependency | Shipped offline plot + new elevation/HR/power chart + laps table | S to M | **Add** |
| 10 | **Music scores**: `.mxl`, `.musicxml`, `.mscz`/`.mscx` | Not quantified | `.mxl`, `.musicxml`, `.mscz`, `.mscx` are `dyn.*` | None found; absent from Unfold's list | ZIP + XML; Bravura (OFL-1.1) only if engraving; Verovio is LGPL (out) | Facts + piano roll (shared with the MIDI proposal) + optional staff view | M (facts, roll) / L (engraving) | **Add** (facts) / stretch (engraving) |
| 11 | **Scratch projects**: `.sb3`, `.sprite3` | Scratch: more than 100 M registered (reported, foundation reports) | `.sb3` is `dyn.*` | None found | ZIP + JSON; format on the Scratch Wiki (CC BY-SA 4.0) | Outline (scripts), images (costumes), bar strip, findings | S to M | **Add** |
| 12 | **Crosswords**: `.puz`, `.ipuz` | Mac solvers exist (Black Ink is a paid Mac app); size unknown | `.puz`, `.ipuz` are `dyn.*` | None found | Own parser; puzpy (MIT) documents `.puz` | Board/grid view + clue list | S to M | Niche |
| 13 | **Guitar Pro and chord sheets**: `.gp`, `.gpx`, `.gp5`, ChordPro `.cho` | Not quantified | All `dyn.*` | None found | `.gp` = ZIP + XML (partly reported); `.gp5` binary documented by the community | Monospaced tab view, text, facts | M | Niche |
| 14 | **Ham radio logs**: ADIF `.adi`/`.adif`, Cabrillo | ARRL says the 3 M worldwide figure dates from 2000; 1.75 M (2021) may be closer | `.adi`, `.adif` are `dyn.*` | None found | Own parser; ADIF 3.1.7 (2026-03-22) | Table, bar strip, offline plot of grid squares | S to M | Niche |
| 15 | **Kindle clippings**: `My Clippings.txt` | Not quantified | Apple text | None found | Own parser; community-documented | Outline (books), text | S | Niche |
| 16 | **Garmin `.fit`** | Very large (Garmin, Wahoo, Zwift all write FIT) | `dyn.*` | Possibly some apps (iTunes: "FIT File Explorer", "Route Viewer"); Quick Look claim not checked | **Proprietary FIT Protocol License Agreement** | Would reuse the activity charts | M + legal | **Rule out until cleared** |
| 17 | **PICO-8 `.p8`** | Not quantified | `.p8` is `dyn.*`; `.p8.png` is already a viewable PNG | None found | Own parser; manual documents the format | Image (sprite sheet) + source text | S | Rule out (tiny) |

## 1. Credential-export guard

**What the preview shows.**
- A summary header such as "1Password unencrypted export, format version 3: 2 vaults, 312 items, 41 attachments". Only counts, never item titles or values.
- A `warning` finding: "This file holds N logins with their passwords in readable form. Delete it once the import has finished." If the file sits in a sync folder, the already shipped sync-folder warning escalates it.
- Item names stay concealed even in the table view; the thumbnail is a fixed warning glyph.
- Cheap extra detections that fit the same finding family (all my inference, each needs fixtures): Bitwarden plaintext JSON (the help page lists ".json (plaintext)" and ".csv (plaintext)" exports and says to delete the file immediately after use); browser and manager CSVs recognised by header row (Chrome-style `name,url,username,password`); OTP-app JSON backups that carry shared secrets; wallet keystore JSON; and a text file that is exactly 12, 15, 18, 21 or 24 words from the BIP-39 list (detection only, never shown).

**Demand evidence.**
- 1Password's own support page says the 1PUX export is a ZIP with `export.attributes`, `export.data` and a `files` folder, that it is unencrypted, and that users should delete it after the transfer (reported through a search summary of [support.1password.com/1pux-format](https://support.1password.com/1pux-format/)).
- Bitwarden documents plaintext CSV/JSON exports and the delete-after-use advice (verified: [bitwarden.com/help/export-your-data](https://bitwarden.com/help/export-your-data/)).
- Audience size cannot be measured; the moment of need (switching managers, backing up) is universal among password-manager users.

**Route.**
- Shared bounded ZIP reader plus JSON for `.1pux` and Bitwarden ZIP/JSON; header-row signatures for CSV. No dependency, no licence question.
- `CredentialFilePrivacyRanges` (`.netrc`, `.pgpass`) and `DelimitedPrivacyPlanner` already conceal password columns by header, so the new part is the file-level classification and its finding.
- One new `PreviewFindingKind` per [decision 012](../../decisions/012-safety-findings.md) (a one-line shared-contract change) plus strings in every app language.

**Safety and privacy.** This candidate is the privacy feature. Counts only; no titles; no thumbnail content; no "reveal" for recovery phrases.

**Risks and unknowns.**
- Apple's own CSV previewer may win routing for `.csv` (the landscape document records that QuickLook Pro defers CSV to Apple's preview). The `.1pux`, ZIP and JSON variants have no system competitor. Test with the real provider-selection flow.
- False positives on CSV headers; keep the finding at `caution` unless the header signature is exact.
- Format drift: 1PUX has no complete public specification (reported in the 1Password community thread), so tolerate unknown fields.
- Wording must not read as a data-loss scare in the App Review listing. Avoid store copy that promises to "detect all passwords".

## 2. Chess and Go game records

**What the preview shows.**
- **Header:** players, ratings, event, site, date, result, ECO code and opening name, time control.
- **Board:** a native drawn 8x8 board with the pieces as text glyphs. I verified that both **Apple Symbols** and **Menlo** carry all twelve U+2654 to U+265F glyphs on this Mac, so no piece artwork, and no licence question about piece sets, is needed.
- **Move list:** two columns with move numbers, comments, numeric annotation glyphs and nested variations as an outline. Left and right arrow keys step through plies; the board follows.
- **Multi-game files:** a sortable table of games (players, result, event, date, opening) with the selected game on the board. Large databases are read as a bounded head with an honest "first N games" count.
- **FEN/EPD:** a single position with side to move, castling and en-passant facts and material balance.
- **Insight layer (inference):** lichess and chess.com analysis exports embed `[%eval ...]` and `[%clk ...]` comments inside PGN braces; if present, draw an evaluation graph and a time-per-move strip with no engine involved. The shared bar and strip chart serves this.
- **SGF (stretch):** the same board component draws a Go board with stones after move N; the SGF text format is simple.

**Demand evidence.**
- Chess.com reported 250 million members in early 2026 and over 20 million games per day (secondary: [voxbooster](https://voxbooster.com/blog/online-chess-statistics-2026), [TechCrunch](https://techcrunch.com/?p=2998565), as summarised by search); Lichess's last official figure is over 4 million active users in January 2023 ([forum post](https://lichess.org/forum/redirect/post/q6Iu5Wkl), reported). These are platform sizes; the number who download PGNs (club players, coaches, ChessBase users, students saving annotated games) is a small fraction and unmeasured.
- Quick Look gap, verified: `.pgn` resolves to `com.apple.chess.pgn`, declared by Apple's Chess.app as conforming to `public.utf8-plain-text`; the app has no `PlugIns` or `Library` folder, so Finder shows raw text (inference for the final step). `.fen` and `.sgf` are `dyn.*`. No PGN or SGF suffix is in Unfold's 262-extension list. A web search for a PGN Quick Look board found nothing.

**Route.**
- Own parser from the [PGN standard](https://www.saremba.de/chessgml/standards/pgn/pgn-complete.htm) (no licence statement at the top of the page; it is a community standard, and implementing a parser from it is ordinary practice). Move text needs SAN resolution, which needs a small legal-move generator to disambiguate (about 400 lines). Do not port python-chess (I believe GPL; not checked).
- Opening names from the [lichess chess-openings table](https://github.com/lichess-org/chess-openings): CC0-1.0, TSV with `eco`, `name`, `pgn`; verified.
- Bounds: games per file, plies per game, variation depth, comment length, line length (the standard caps import lines at 255 characters); strictly streaming, cancellable between games. Lichess's public dumps are `.pgn.zst` and enormous; do not register `.zst`.

**Safety and privacy.** Little for the Safety Lens: hidden-Unicode and secret checks run on headers and comments as for any text. Thumbnails can draw the final or starting position safely.

**Risks and unknowns.**
- Registering `com.apple.chess.pgn` (an Apple type) is allowed by supported-type lists but needs a routing test: macOS may prefer its text previewer.
- Whether arrow keys reach the preview view inside the Quick Look panel (instead of moving Finder's selection) needs a Finder-hosted test; the shipped MIDI transport is the nearest precedent. Provide on-screen step buttons as the fallback.
- Messy real-world PGN (missing results, broken SAN, `;` comments, huge variations) requires a forgiving parser with a visible "N moves could not be read" note.
- Audience is real but not large; this is a delight feature, not a volume driver.

## 3. Minecraft builds and worlds

**What the preview shows.**
- **3D model** of the structure in the shipped Metal viewer: voxels converted to a face-culled mesh, coloured from a small colour table that SpacePane writes itself (flat colours per block family; no Mojang textures, so no asset licence issue, though Mojang's brand guidelines should be checked before store copy mentions the game).
- **Material list:** blocks by count, with "12 stacks + 40" arithmetic that builders use when gathering resources. This is the single most useful fact in a schematic and no static viewer gives it in Finder.
- **Facts:** dimensions, region count (Litematica files hold several named regions), total and non-air blocks, `DataVersion` mapped to a game version, author and description fields.
- **Layer scrubber** (stretch): slider through Y levels.
- **Modpack and pack archives:** `.mrpack` (Modrinth) and `.mcpack`/`.mcworld` are ZIPs; show the manifest, mod list and version facts through the existing ZIP listing.
- **World facts:** `level.dat` (gzip NBT) gives name, game mode, version, last played; region files (`.mca`) are a stretch for a top-down map.

**Demand evidence.**
- Minecraft: reported 350 million copies sold and about 212 million monthly players in early 2026 ([voxbooster](https://voxbooster.com/blog/minecraft-statistics-2026), [levvvel](https://levvvel.com/statistics/minecraft/); secondary). r/Minecraftbuilds about 1.3 million members ([GummySearch listing](https://gummysearch.com/r/Minecraftbuilds), June 2026). Litematica 16.2 million Modrinth downloads ([GDLauncher listing](https://gdlauncher.com/mods/modrinth/litematica), reported).
- Quick Look gap: all of `.litematic`, `.schem`, `.nbt`, `.mcstructure`, `.mcworld` are `dyn.*` locally. Search found only browser viewers ([Shulkr](https://www.shulkr.com/minecraft-schematic-viewer), vendor claim, runs locally in a browser) and an abandoned MCEdit. Not in Unfold's list.
- Mac share of Minecraft players is **not measured**; Java Edition runs on macOS. Bedrock files (`.mcstructure`, `.mcworld`) reach a Mac by AirDrop or cloud (inference).

**Route.**
- NBT is a small public binary tree format (tags 0 to 12 plus long arrays). Own parser, depth and size capped; gzip through system zlib/Compression with an inflate-output cap (for example 256 MiB).
- `.schem`: [Sponge Schematic Specification](https://github.com/SpongePowered/Schematic-Specification) (current version 3; v2 widely used; the page I fetched states no licence, so treat it as documentation and check the repository's LICENSE before quoting). `.litematic`: regions with palettes and bit-packed long arrays (documented by the community in [litemapy's format page](https://litemapy.readthedocs.io/en/latest/litematics.html), reported; I did not confirm packing rules). `.nbt` structure blocks and Bedrock `.mcstructure` (little-endian NBT) are simpler.
- Mesher: face culling plus greedy merging; caps such as 20 million blocks and 2 million faces; beyond that show a top-down heightmap and say so.
- Fixtures must be synthetic; do not bundle anyone's build.

**Safety and privacy.**
- Typed finding "contains N command blocks" (they are tile entities in the file; this is inference, verify on fixtures). Nothing is executed.
- Sign and book text is user content: count it, run the existing hidden-character check, show it only in a text list.
- Mesh thumbnails stay generic under decision 024 unless the thumbnail policy changes.

**Risks and unknowns.**
- Largest effort in the list (voxel mesher, colour table, three schematic dialects). Do `.litematic` and `.schem` first; they cover the community that shares builds.
- Block-state palettes change with every Minecraft version; unknown ids need a graceful hash colour.
- Brand wording: avoid implying endorsement by Mojang or Microsoft.

## 4. Chat exports

**What the preview shows.**
- A conversation view: bubbles by participant, date separators, system lines styled quietly, media placeholders (images from the ZIP drawn small when the archive carries them, bounded).
- Summary: participants, message count, first and last date, busiest day, messages-per-month strip, count of attachments by kind.
- Findings (optional, inference): shared 2FA-style codes and likely secrets are concealed by the existing token scanner; "Copy Concealed Text" already exists.

**Demand evidence.** WhatsApp export is a user feature: a ZIP with `_chat.txt` plus media, one chat at a time, deleted messages omitted ([dev.to guide](https://dev.to/chattopdf/whatsapp-chat-export-complete-guide-iphone-android-zip-pdf-2026-10lo), reported). The iTunes search for "whatsapp chat export viewer" returned only exporter and sender apps (FreeChat, ChatMate, ChatShare at $3.99, Messages Export Pro), not previewers; an app called Msg Viewer Pro ($4.99) also surfaced and looks like an unrelated Outlook `.msg` viewer (inference from its name). Size of the export-using Mac audience is unknown.

**Route.**
- Own parser. The format varies by exporting phone: the [WhatsR package](https://cran.r-universe.dev/WhatsR/doc/manual.html) states that the phone's time format and operating-system settings change the timestamp layout and system messages (reported). iOS commonly writes `[date, time] Name: text`, Android `date, time - Name: text` (inference). Day/month order is ambiguous when both fields are 12 or less; resolve by scanning the whole file for a value above 12, then fall back and say so.
- Multi-line messages continue until the next timestamp; strip invisible directional marks.
- Telegram Desktop's JSON export (`messages` array, per-message `from`, `date`, text possibly split into entities) is a second parser (inference, unverified). Discord and Slack exports are stretch.
- No dependency. Cap messages (for example 200,000), line length and media decoding; ZIP via the shared reader.

**Safety and privacy.** These files are other people's private words. Thumbnails stay a generic chat glyph; nothing is logged or cached; findings counts only. State in the listing that the file never leaves the Mac.

**Risks and unknowns.**
- The plain `.txt` route competes with Apple's text previewer; the ZIP route (the iOS default when media is attached) is cleaner. Android's text-only export would depend on the plain-text provider being SpacePane.
- A reported WhatsApp cap of 40,000 messages per export (same dev.to source, unverified) is irrelevant to parsing but explains truncated chats.
- Perception risk: "an app that reads chats". The local-only story is strong but the copy must be careful.

## 5. Anki decks and collections

**What the preview shows.**
- Deck tree with card counts, note types and their field names, tags, and a table of sample cards (front, back) with HTML stripped and cloze markers shown as "[...]".
- Media inventory: count, bytes, a few bounded image thumbnails.
- Whether scheduling data is included (a `.colpkg` or an `.apkg` exported with scheduling), and for collections a review-history heatmap from the review log (inference: the table is `revlog`).
- Use case: someone downloads a shared deck from AnkiWeb or AnkiHub and wants to know what is inside before importing.

**Demand evidence.**
- r/Anki: reported at 136 k to 144 k in 2024 comments, 198 k by a tracker, 320 k+ by a blog (conflicting; [search summary](https://gummysearch.com/r/Anki/)). The community's medical-school offshoot r/medicalschoolanki is reported at 160 k to 193 k. AnkiDroid is described in a community forum post as having 10 million downloads and about 3 million active users ([thread](https://forums.ankiweb.net/t/anki-downloads-statistics/28788), reported; not official).
- Quick Look gap: both suffixes `dyn.*`; none of the Quick Look apps in the landscape document or Unfold's list claim them; iTunes searches returned only flashcard apps.

**Route.**
- Container: a ZIP whose members are stored without compression (verified by [Eiko Wagenknecht's write-up](https://eikowagenknecht.com/posts/understanding-the-anki-apkg-format/), updated 2025-07-09): `meta` (protobuf, one version field; 3 = latest), `media` (protobuf map of names to numbered files), numbered media files, `collection.anki21b` (the SQLite database compressed with **zstd**, introduced in Anki 2.1.50, April 2022), and a dummy `collection.anki2`. Older packages hold `collection.anki2`/`collection.anki21` as plain SQLite. The Anki manual confirms a "support older Anki versions" export switch that produces the legacy layout ([docs](https://docs.ankiweb.net/exporting.html)).
- zstd: Apple's Compression framework does not offer zstd (inference; I recall LZFSE, LZ4, zlib, LZMA and Brotli only; verify against the SDK). The reference decoder is [zstd](https://github.com/facebook/zstd), "dual-licensed under BSD OR GPLv2" (README, verified); take the BSD option and ship a decompress-only subset with a pinned version, a named security owner, and an output cap against decompression bombs.
- The decompressed bytes must be opened as a read-only SQLite database, ideally from memory (`sqlite3_deserialize`; whether the system SQLite enables it is unverified) or from a temp file in the extension's container. The schema has 12 tables in the latest format and configuration stored as protobuf blobs (verified in the write-up above). Gotcha from my memory, unverified: Anki indexes use a custom `unicase` collation, so queries can fail with "no such collation sequence" unless a collation of that name is registered.
- Anki's maintainers say `.apkg` files "were not intended to be read/written by software other than Anki" (forum thread, reported), so expect format drift; parse defensively and show "unknown newer format" instead of guessing.

**Safety and privacy.** Decks are the user's study material; usually not sensitive. Thumbnails: first card's front, concealed by the normal pipeline.

**Risks and unknowns.** New dependency (zstd); large collections (hundreds of MB) need a head-only approach, which the stored ZIP layout allows; media files are untrusted images and audio (list audio, do not play).

## 6. Family trees (GEDCOM)

**What the preview shows.**
- Header facts: source program, GEDCOM version, character set, counts of people, families, sources, media; earliest and latest year; most common surnames and places as bars.
- People table (name, sex, born, died, place, parents) and an outline of families.
- A native **Diagram** of ancestors or descendants of the first listed person, to a bounded depth.
- **Living-persons guard:** a person with no death or burial event and a birth less than about 110 years ago (or no dates) is treated as possibly living; the header says "N people may be living", their names are concealed by default ("Living (private)") and Copy Concealed Text honours it. Genealogists routinely privatise living people before sharing (inference; the rule of thumb and cut-off years need a decision and a visible setting).

**Demand evidence.**
- Ancestry: more than 3.6 million subscribers in Blackstone's December 2020 release ([press release](https://www.blackstone.com/press-releases/article/blackstone-completes-acquisition-of-ancestry-leading-online-family-history-business-for-4-7-billion/), reported); a later profile says over 3 million with revenue above $1.3 billion in 2024 (reported, unsourced). r/Genealogy: 170 k to 259 k (trackers disagree). GEDCOM is the universal export; a real file of about 145,000 people appears in a Gramps forum ([thread](https://gramps.discourse.group/t/very-large-gedcom-import-really-happy/8544), reported).
- Quick Look gap: `.ged`, `.gedcom`, `.gdz` are `dyn.*` locally; web search found only older Mac apps (GEDitCOM, GedScape, which lists OS X 10.9) and no Quick Look generator. Not in Unfold's list.

**Route.**
- Line-based format: `level [@id@] TAG value`, continuation via `CONC`/`CONT`. Own parser, flat memory, caps on records and lines.
- **Licence:** the [GEDCOM 7.0 specification](https://gedcom.io/specifications/FamilySearchGEDCOMv7.html) says it is licensed under Apache 2.0 and that derivative works must carry its NOTICE (verified). Most files in the wild are 5.5.1; I did not verify that spec's licence. Implementing a parser from the structure is ordinary; do not copy the specification text, and carry the NOTICE if tag definitions are copied.
- Encoding: UTF-8/UTF-16 are easy; legacy **ANSEL** needs a small mapping table (inference) or a clear "unsupported character set" fallback. GEDZIP (a ZIP with the tree plus media, defined in chapter 4 of the 7.0 spec) uses the shared ZIP reader.

**Safety and privacy.** This is where the Safety Lens is most natural: names, birth dates and places of living relatives are personal data. New finding kind (living persons) and concealment; thumbnails show only counts and a tree shape, never names.

**Risks and unknowns.** Cut-off logic is a judgment call and must be explained, not hidden. Multi-million-line files need streaming. Date grammar (approximate, ranges, other calendars) is large; show the raw text when a date is not understood.

## 7. Embroidery designs

**What the preview shows.**
- **Stitch plot:** the design drawn as thread-coloured polylines, jumps as faint dotted lines, on a plain ground.
- **Facts:** stitch count, colour changes, trims and jumps, width and height in millimetres and inches, thread list in order with per-colour stitch counts, and a machine-time estimate at a typical speed (inference; label it as an estimate).
- **Hoop fit:** a common-hoop-size check (list of sizes needs a source; inference).
- DST and EXP carry no colour data, so colour is cycled from a default palette and the view says so.

**Demand evidence (strongest in this report).**
- [StitchBuddy](https://apps.apple.com/us/app/stitchbuddy/id1167912393) (Matthias Arndt): free; the App Store text says it displays embroidery files in the Finder and Mail "with Preview / Thumbnail support", reads JEF/JEF+/JPX/SEW, PES/PEC, EXP, DST and VP3/KSM/PCS (vendor claim, version 3.9.1 on 2026-10-04).
- [MyEmbroids](https://apps.apple.com/us/app/myembroids/id1359931085): $17.99, Mac-only, lists JEF, PES, PEC, VP3, DST, XXX, EXP, HUS, VIP with real-time preview (reported).
- ThreadView: $24 one time, previews DST/PES/JEF/EXP with a Finder thumbnail extension (vendor page, reported; I could not reach the site directly).
- [Embrilliance Thumbnailer](https://embrilliance.com/product/thumbnailer): $39.00, discounted from $44.95 until 2026-10-17 (verified); its page says `.EXP` cannot be shown as thumbnails on macOS "due to Apple changes".
- Four paid or free products exist for exactly the "PES is a blank icon on a Mac" gap. That proves willingness to pay, and also shows a free incumbent. The number of Mac embroiderers was not found.

**Route.**
- [pyembroidery](https://github.com/EmbroidePy/pyembroidery) is **MIT** (verified) and documents 40+ read formats including `.pes .dst .exp .jef .vp3 .hus .xxx .pec .sew .jpx .ksm .pcs`. Port the readers by hand to Swift (MIT permits it with the notice; palette tables are facts).
- Complexity: DST (3-byte records), EXP, JEF: simple. PES/PEC: moderate (several PES versions). VP3, XXX: moderate. HUS: needs an obsolete compression scheme (pyembroidery notes this); skip at first.
- Bounds: stitch count cap (for example 2 million), coordinate range, colour table size.

**Safety and privacy.** Nothing sensitive; thumbnails can safely draw the design.

**Risks and unknowns.** Free incumbent. Buyer overlap with SpacePane's developer-oriented buyers is small, so this is an additive niche, best marketed on its own screenshot. `.exp` collides with an Apple system type, so the Melco format may never reach SpacePane through suffix routing.

## 8. Personal-data exports (Apple Health, Spotify, Takeout, Instagram)

**What the preview shows.**
- **Recogniser:** for any ZIP or TGZ, match well-known top-level names and show a plain-words header ("Instagram data download, JSON, requested by account X", or just "Google Takeout, 3 products"). Only the central directory is read, so it is cheap and exact on sizes and file counts.
- **Apple Health `export.zip`:** record-type counts, date span and device sources from a bounded stream of `export.xml`; workout count and an offline plot of any chosen route from `workout-routes/*.gpx`; ECG file count. Because the XML can exceed 5 GB (reported by a [data-engineering tutorial](https://dev.to/beck_moulton/crushing-5gb-of-xml-building-a-blazing-fast-apple-health-parser-with-rust-and-clickhouse-117e)), the summary must be labelled "from the first N MB".
- **Spotify extended streaming history:** the ZIP of `Streaming_History_Audio_*.json` files becomes top artists and tracks by hours, hours per year and per hour of day (a Wrapped for your own file). Fields verified by search summary: `ts`, `ms_played`, `master_metadata_track_name`, `master_metadata_album_artist_name`, plus `ip_addr_decrypted`, `user_agent_decrypted`, `incognito_mode` ([Spotify support](https://support.spotify.com/br-en/article/understanding-your-data/), reported).

**Demand evidence.** Apple Health exports are commonly 1 to 5 GB (reported, MacPowerUsers forum and the tutorial above). Spotify says a full history can take up to 30 days to arrive (reported), which is why people keep the ZIP. Google Takeout archives come as ZIP or TGZ in 1 to 50 GB parts; Instagram offers JSON or HTML (reported; [guide](https://pirg.org/resources/how-to-request-and-download-instagram-data/)). No size of the Mac audience for any of them.

**Route.** Shared ZIP reader; a bounded streaming XML tokenizer for the Health file (never a DOM); JSON arrays for Spotify; GPX reader and plot already exist. No dependency. Signatures for Instagram and Takeout folder names change over time, so keep the recogniser table small, versioned, and generic on failure (inference).

**Safety and privacy.** High value here: findings such as "includes precise GPS routes", "includes ECG recordings", "includes IP addresses (N distinct)" and "includes private-session plays" tell people what they hold. Thumbnails stay generic. Do not show message bodies from Instagram or other exports in the first version.

**Risks and unknowns.** Fragile folder signatures; huge inputs; and a perception risk if Health data is shown with too much confidence from a sample. Start with the recogniser and Health summary; leave Spotify charts until the shared bar chart exists.

## 9. Activity files (TCX, GPX, Zwift workouts)

**What the preview shows.**
- For GPX and TCX: the shipped offline track plot plus an elevation profile, pace or speed line, heart-rate and power strips, and a laps table.
- For Zwift `.zwo`: a power-profile bar chart coloured by zone, drawn from the workout's segments. The format is XML with `Warmup`, `SteadyState`, `IntervalsT` and `Cooldown` elements, durations in seconds and power as a fraction of FTP (reported from search; [intervals.icu thread](https://forum.intervals.icu/t/zwo-workout-import-textevent/89392) and Zwift forum posts). `.erg` and `.mrc` are simple text tables used by trainers (inference).

**Demand evidence.** Zwift's 2026 yearly concurrent peak was 41,680 riders, below 2021's 49,114 (reported from [The 5krunner](https://the5krunner.com/2026/01/23/peak-zwift-2026-indoor-cycling-trends/)); total user counts were old (550 k accounts, January 2018, wiki). Strava and Garmin Connect scale was not measured. `.tcx`, `.zwo`, `.erg` and `.mrc` are `dyn.*` locally; GPX is claimed by `com.topografix.gpx`. Competitor: GPX Preview ($1.99) puts GPX, KML, KMZ and TCX on a map (landscape document); nothing found draws elevation, HR and power charts or workout profiles in Quick Look.

**Route.** XML only; no dependency. The TCX schema is public Garmin XML; no distribution issue because nothing is bundled. Needs the new chart presentation.

**Safety and privacy.** Activity files carry exact start and end positions, often a home or workplace. One file cannot show a repeated start point, so use a plain "this file contains precise GPS positions" finding, and keep thumbnails generic: a track outline would reveal the route.

**Risks and unknowns.** Overlap with GPX Preview for the map part; value is in the charts. Keep expectations small: this is an enrichment, not a new audience.

## 10. Music scores (MusicXML, MXL, MuseScore)

**What the preview shows, by effort.**
1. **Facts card (S to M):** title, composer, parts and instruments, key, time signature, tempo, measure count, lyrics line, chord symbols line. From MusicXML or the MuseScore XML.
2. **Piano roll per part (M):** note events from the score, which shares code with the already proposed MIDI piano roll.
3. **Staff view of the first measures (L):** Bravura glyphs on drawn staves.
4. **Thumbnail for `.mscz` (S):** the MuseScore 3 handbook says an `.mscz` is a ZIP containing the `.mscx` score, images and a thumbnail ([handbook](https://handbook.musescore.org/3/advanced-topics/file-formats), verified; the page covers version 3 only, so check whether MuseScore 4 files embed one).

**Honest assessment of engraving.** The minimal credible staff view per part needs clefs, key and time signatures, note head placement, accidentals, stems and beams, ties, rests, ledger lines, bar lines and system breaking. Chords with several voices and slur collisions are the hard cases. I estimate three to five weeks to look trustworthy on piano and single-line parts; I have no measurement. The ready-made libraries do not fit: **Verovio is LGPL-3.0** ([repository](https://github.com/rism-digital/verovio), verified), the same class of problem as Open CASCADE; web engravers are JavaScript and banned. The font is not the issue: **Bravura is OFL-1.1** ([repository](https://github.com/steinbergmedia/bravura), verified), so embedding it is permitted.

**Demand evidence.** None quantified. `.mxl`, `.musicxml`, `.mscz`, `.mscx` are `dyn.*` locally; the files are absent from Unfold's list; no Quick Look app was found. I found no audience number for MuseScore or MusicXML users and will not invent one.

**Route.** `.mxl` is a ZIP with `META-INF/container.xml` pointing at the score ([W3C compressed MXL tutorial](https://www.w3.org/2021/06/musicxml40/tutorial/compressed-mxl-files), reported); `.mscz` is a ZIP; both use the shared reader and a bounded XML parser. MusicXML 4.0 is a W3C Community Group specification; I did not verify its licence terms. ABC notation is a stretch for the facts card only: `.abc` collides with Apple's `public.alembic` locally.

**Safety and privacy.** Nothing special; scores can be copyrighted but SpacePane bundles nothing.

**Risks and unknowns.** Recommend shipping levels 1, 2 and 4 and treating level 3 as a separate decision with a time-box and a go/no-go on quality.

## 11. Scratch projects

**What the preview shows.**
- Stage and sprites with costume thumbnails, block counts by category (a bar), script count, variables and lists, and the extensions used.
- A script outline in plain words ("when green flag clicked, forever, move 10 steps") from the block tree, using the outline presentation.
- Findings (inference): cloud variables (network-backed), extensions that contact online services (translate, text-to-speech) or use the camera, and hidden characters in sprite or variable names. The project is never run.

**Demand evidence.** Scratch reported more than 100 million registered users in 2021 and again in its 2023 report, and a 2024 report says it welcomed 21.5 million new users and reached 140 million children ([2024 report](https://annualreport.scratchfoundation.org/pdf/Scratch-Report_2024.pdf), reported). School Mac use and teacher workflows (students submit `.sb3` files) are inference; the live statistics page rendered no numbers when fetched. `.sb3` is `dyn.*` locally; no Quick Look app found.

**Route.** `.sb3` is a ZIP with `project.json` and MD5-named asset files; `project.json` has `targets`, `monitors`, `extensions`, `meta`, and each block carries `opcode`, `next`, `parent`, `inputs` ([Scratch Wiki](https://en.scratch-wiki.info/wiki/Scratch_File_Format), CC BY-SA 4.0, verified). Parse from the wiki's description; write our own opcode-to-words table rather than copying a repository's. Costumes are SVG or PNG; SVG rasterisation without WebKit needs a check against the system image stack (unknown).

**Safety and privacy.** A school-safety angle: students' projects can be skimmed without running them; sprites may embed photographs, so thumbnails stay generic.

**Risks and unknowns.** Small win per project; the value is a teacher's skim. Effort S for facts, M with the script outline.

## 12. Crosswords (`.puz`, `.ipuz`)

- **View:** the numbered grid with black squares, the Across and Down clue lists, title, author, copyright and notes. **Spoiler shield:** the solution is hidden by default (grid shows blank squares) with an explicit "show solution" toggle. `.puz` files also hold the player's in-progress entries; scrambled puzzles show "solution locked". The thumbnail is the empty grid.
- **Evidence:** Across Lite's `.puz` dates from 1996 and is the format of published puzzles; the [puzpy](https://github.com/alexdej/puzpy) library is **MIT** (verified) and links an archived copy of the binary spec; a Rust parser also exists (reported). Black Ink is a paid Mac solver (reported), so Mac solvers exist; audience size not found. `.puz` and `.ipuz` are `dyn.*` locally; no Quick Look app found.
- **Route:** own parser (header with magic string, checksums, solution and state grids, then null-terminated strings for title, author, copyright, clues, notes; layout from memory, check against the spec). `.ipuz` is JSON. No dependency.
- **Risk:** charming and small. Verdict Niche; cheap enough to ride on the board component if chess ships.

## 13. Guitar Pro and chord sheets

- **View:** a monospaced tab for each track (six lines with fret numbers, bar lines, techniques as letters), tuning, tempo, track list and lyrics. Tab is much cheaper than staff notation because it is text, not engraving.
- **Evidence:** `.gp` is the Guitar Pro 7 and later format, `.gpx` the version 6 format, and `.gp5/.gp4/.gp3` earlier versions ([fileinfo](https://fileinfo.com/extension/gp), reported); one tool's documentation describes `.gp` as GPIF XML (reported), and my belief that it sits in a ZIP as `Content/score.gpif` is unverified. Guitar Pro 8 runs on macOS 10.13+ ([vendor support](https://support.guitar-pro.com/hc/en-us/articles/19189896773789-GP8-Download-Guitar-Pro-8-Tablature-Editor-Software), reported). Ultimate Guitar lists roughly 1.1 million tabs (vendor claim), but those live on its site, not as files. All suffixes `dyn.*` locally; no Quick Look app found.
- **Route:** `.gp` via ZIP + XML is feasible. `.gp5` and earlier are binary and documented only by community reverse engineering; the common parsers are LGPL or GPL (PyGuitarPro is LGPL, TuxGuitar GPL; both from memory), so write from the byte layout, not from their code. `.gpx` uses a custom container with its own compression (memory).
- **Risk:** transcriptions are copyrighted; SpacePane bundles none. Effort M per dialect. Verdict Niche. ChordPro (`.cho`) is a plain-text format that could get a chords-above-lyrics view cheaply (not researched).

## 14. Ham radio logs (ADIF, Cabrillo)

- **View:** QSO table (date, time, call, band, mode, report, grid), counts by band and mode, unique callsigns, and an offline plot of the Maidenhead grid squares (a grid-to-coordinates conversion is plain arithmetic). Cabrillo shows the contest header and claimed score.
- **Evidence:** ADIF is maintained at [adif.org](https://adif.org/317/ADIF_317.htm), latest 3.1.7 dated 2026-03-22 (reported from search); records are `<FIELD:length>value ... <eor>`, with an XML sibling (ADX). Ham numbers are murky: the ARRL says the "3 million" figure dates from 2000 and that 1.75 million in 2021 may be closer ([ARRL](https://www.arrl.org/news/view/data-on-number-of-radio-amateurs-worldwide-needs-updating), reported); US licences about 711,000 per one blog (unverified). `.adi` and `.adif` are `dyn.*` locally; no Quick Look app found.
- **Route:** own parser, no dependency; country-from-prefix tables are a separate data question (skip).
- **Safety:** a log reveals the operator's station grid and times; show but never thumbnail content. Mac share of hams: not found. Verdict Niche, cheap.

## 15. Kindle clippings

- **View:** books with highlight counts, then quote cards sorted by location, with notes marked; copy as Markdown.
- **Evidence:** the file is `My Clippings.txt`, entries separated by a line of `==========`, each with a title and author line, a metadata line ("Your Highlight on page 42 | location 645-646 | Added on ..."), a blank line and the text. Parsers split on the separator and match the metadata line; localisation breaks fixed strings, notes may lack a page, duplicates accumulate ([gist](https://gist.github.com/stared/ce732ef27d97d559b34d7e294481f1b0), [ClippyKindle](https://clippy-kindle.readthedocs.io/en/latest/_modules/ClippyKindle.html), reported; no official Amazon specification found). Audience unquantified; Apple's text previewer handles the `.txt` extension today.
- **Route:** detect by exact file name and separator; own parser; no dependency. Effort S. Verdict Niche, ride-along.

## 16. Garmin `.fit`: parked on licensing

- **Demand is real:** FIT is the native format of Garmin, Wahoo and Zwift activity files; Garmin's [developer page](https://developer.garmin.com/fit/overview/) lists SDKs for C, C++, C#, Java, JavaScript, Objective-C, Python and Swift. `.fit` is `dyn.*` locally. iTunes shows free apps "FIT File Explorer" and "Route Viewer: GPX FIT TCX KML"; I did not check whether either ships a Quick Look extension.
- **Licence, verified from the Garmin Swift SDK's `LICENSE.txt`:** the "Flexible and Interoperable Data Transfer (FIT) Protocol License Agreement" is not an open-source licence. It defines the licensed technology as the SDK "that includes documentation describing the FIT protocol and related source code files", grants a non-transferable, non-sublicensable right "for Licensee's internal business purposes", forbids distributing it, bars distribution under any licence that requires source disclosure, and calls the technology Garmin's Confidential Information ([LICENSE.txt](https://raw.githubusercontent.com/garmin/fit-swift-sdk/main/LICENSE.txt)). Whether an independent parser built from the public protocol page is a "derivative" is not answered by the text. Third-party Rust code illustrates the caution: the BSD-3 `rustyfit` crate keeps Garmin's `Profile.xlsx` and test files under the FIT licence (reported from its README, [docs.rs](https://docs.rs/crate/rustyfit/0.8.0/source/README.md)). A Garmin forum answer says bundling the compiled Java SDK in an app is allowed (reported; not authoritative).
- **Recommendation:** do not ship FIT until the owner gets a written answer from Garmin or counsel. A TCX/GPX-first strategy (section 9) covers the same sport audience without the question. This is the same shape of problem as the Open CASCADE decision.

## 17. PICO-8 `.p8`

A `.p8` is text (`__lua__`, `__gfx__`, `__map__`, `__sfx__` sections; reported from the [PICO-8 wiki](https://pico-8.fandom.com/wiki/P8PNGFileFormat?oldid=2075) and the [manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html)). A sprite-sheet picture plus highlighted Lua would be delightful, but no audience figure was found, and a `.p8.png` cart is already a valid PNG showing the cartridge label, so Finder already previews it. Verdict: rule out for now; revisit only as a free ride-along on the image presentation.

## Ruled out and why

| Candidate | Reason |
|---|---|
| Garmin `.fit` | Proprietary FIT licence (section 16). Revisit only with written clearance. |
| Verovio or any ready-made engraver | Verovio is LGPL-3.0; the others found are JavaScript. Native minimal staff view or nothing (section 10). |
| Console ROM headers and save files, DOOM WAD, Quake PAK/BSP | Asset-copyright and legal caution in the brief; no demand evidence gathered. Not researched. |
| Running anything: PICO-8 carts, Ren'Py, RPG Maker, Scratch scripts, Twine, macros | Violates the "never execute" rule; text forms already preview as source. |
| Steam `.acf`/`.vdf`, Tabletop Simulator saves, Foundry/Roll20 exports, Cooklang `.cook` | Plain text or JSON; existing text, JSON and YAML previews already cover them and no distinctive native visual was identified. Cooklang `.cook` is `dyn.*` but tiny (no evidence gathered). |
| PICO-8 `.p8.png` | Already a viewable PNG in Finder (section 17). |
| `.m3u`, `.pls`, `.xspf` playlists | `public.m3u-playlist` and `public.pls-playlist` exist natively; a track table cannot check sibling files, so value is low. Rekordbox XML, Traktor NML and Serato crates were not researched. |
| Crypto wallet and seed files | Fold into the credential guard as detect-and-warn only; never display. |
| H5P, SCORM, Moodle `.mbz`, GeoGebra `.ggb` | Not researched beyond knowing they are ZIP + XML/JSON packages. SCORM and H5P embed JavaScript content, so a preview could only list the manifest, which the existing ZIP listing already gives. Revisit only as an education bundle. |
| StepMania/osu!/Clone Hero charts, UltraStar, `.kar` | Not researched. `.kar` (MIDI with lyric events) might be a free lyric line on the shipped MIDI preview (inference). |
| IGC glider logs, dive logs (UDDF, Subsurface), NMEA, sailing | Not researched. They would reuse the offline plot and charts if evidence of demand appears. |
| Recipes (Paprika, Mela, MealMaster, schema.org JSON-LD) | Not researched; no Quick Look evidence either way. |
| Telegram, Discord, Slack, Signal exports | Only Telegram JSON is in scope as a second chat parser; the rest wait on the first one. |

## Sources

Competitor and landscape
- [SpacePane competitor landscape, 2026-10-05](../2026-10-05-competitor-landscape.md)
- [Unfold supported extensions (262)](https://unfold.tools); [LookQuick](https://inspirationull.com/LookQuick) (no list published)
- iTunes Search API: `https://itunes.apple.com/search?term=...&entity=macSoftware&limit=12&country=us`; lookup of [StitchBuddy](https://apps.apple.com/us/app/stitchbuddy/id1167912393)

Embroidery
- [pyembroidery (MIT)](https://github.com/EmbroidePy/pyembroidery); [Embrilliance Thumbnailer](https://embrilliance.com/product/thumbnailer); [MyEmbroids](https://apps.apple.com/us/app/myembroids/id1359931085) (price per search summary); ThreadView at `threadview.69-62-66-51.sslip.io` (vendor page, reported only)

Chess, Go, crossword
- [PGN standard](https://www.saremba.de/chessgml/standards/pgn/pgn-complete.htm); [lichess chess-openings (CC0)](https://github.com/lichess-org/chess-openings); [Chess.com statistics (secondary)](https://voxbooster.com/blog/online-chess-statistics-2026); [Lichess users forum post](https://lichess.org/forum/redirect/post/q6Iu5Wkl); [puzpy (MIT)](https://github.com/alexdej/puzpy)
- Local: Apple Chess.app `Info.plist` (`/System/Applications/Chess.app/Contents/Info.plist`) and CoreText glyph check (Apple Symbols, Menlo)

Minecraft
- [Sponge Schematic Specification](https://github.com/SpongePowered/Schematic-Specification); [litemapy format notes](https://litemapy.readthedocs.io/en/latest/litematics.html); [Shulkr](https://www.shulkr.com/minecraft-schematic-viewer); [Minecraft statistics (secondary)](https://voxbooster.com/blog/minecraft-statistics-2026); [r/Minecraftbuilds listing](https://gummysearch.com/r/Minecraftbuilds); [Litematica on Modrinth (GDLauncher listing)](https://gdlauncher.com/mods/modrinth/litematica)

Education and personal data
- [Anki exporting](https://docs.ankiweb.net/exporting.html); [Understanding the Anki APKG format](https://eikowagenknecht.com/posts/understanding-the-anki-apkg-format/); [zstd (BSD OR GPLv2)](https://github.com/facebook/zstd); [AnkiWeb forum: user counts](https://forums.ankiweb.net/t/anki-downloads-statistics/28788); [r/Anki listing](https://gummysearch.com/r/Anki/)
- [Scratch file format (Scratch Wiki, CC BY-SA 4.0)](https://en.scratch-wiki.info/wiki/Scratch_File_Format); [Scratch Report 2024](https://annualreport.scratchfoundation.org/pdf/Scratch-Report_2024.pdf)
- [GEDCOM 7.0 specification (Apache-2.0)](https://gedcom.io/specifications/FamilySearchGEDCOMv7.html); [Blackstone/Ancestry release](https://www.blackstone.com/press-releases/article/blackstone-completes-acquisition-of-ancestry-leading-online-family-history-business-for-4-7-billion/)
- [1Password unencrypted export format](https://support.1password.com/1pux-format/); [Bitwarden export](https://bitwarden.com/help/export-your-data/)
- [WhatsApp export guide](https://dev.to/chattopdf/whatsapp-chat-export-complete-guide-iphone-android-zip-pdf-2026-10lo); [WhatsR package notes on timestamp variation](https://cran.r-universe.dev/WhatsR/doc/manual.html)
- [Apple Health export size discussion](https://dev.to/beck_moulton/crushing-5gb-of-xml-building-a-blazing-fast-apple-health-parser-with-rust-and-clickhouse-117e); [Spotify: understanding your data](https://support.spotify.com/br-en/article/understanding-your-data/); [Instagram data download guide](https://pirg.org/resources/how-to-request-and-download-instagram-data/)
- [Kindle clippings parser gist](https://gist.github.com/stared/ce732ef27d97d559b34d7e294481f1b0)

Music and sport
- [MuseScore file formats (v3 handbook)](https://handbook.musescore.org/3/advanced-topics/file-formats); [W3C compressed MXL](https://www.w3.org/2021/06/musicxml40/tutorial/compressed-mxl-files); [Bravura (OFL-1.1)](https://github.com/steinbergmedia/bravura); [Verovio (LGPL-3.0)](https://github.com/rism-digital/verovio); [Guitar Pro 8 support](https://support.guitar-pro.com/hc/en-us/articles/19189896773789-GP8-Download-Guitar-Pro-8-Tablature-Editor-Software)
- [Garmin FIT overview](https://developer.garmin.com/fit/overview/); [FIT Protocol License Agreement (Swift SDK LICENSE.txt)](https://raw.githubusercontent.com/garmin/fit-swift-sdk/main/LICENSE.txt); [rustyfit README](https://docs.rs/crate/rustyfit/0.8.0/source/README.md)
- [Zwift peak concurrency](https://the5krunner.com/2026/01/23/peak-zwift-2026-indoor-cycling-trends/); [intervals.icu ZWO thread](https://forum.intervals.icu/t/zwo-workout-import-textevent/89392)
- [ADIF 3.1.7](https://adif.org/317/ADIF_317.htm); [ARRL: worldwide amateur counts](https://www.arrl.org/news/view/data-on-number-of-radio-amateurs-worldwide-needs-updating)
- [PICO-8 file format wiki](https://pico-8.fandom.com/wiki/P8PNGFileFormat?oldid=2075); [PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html)
