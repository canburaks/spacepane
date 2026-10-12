# Direct file-drop validation

Date: 2026-10-04 (Europe/Istanbul). Contract: [direct-file-drop decision](../decisions/006-direct-file-drop.md).

## Implementation

Try Preview now displays a localized drop strip above the content. Its label determines height with a minimum of 52 points, allowing translated instructions to expand. A narrow AppKit representable handles drag entry/update/exit/drop and clears callbacks when dismantled. Open File and Command-O retain the existing attached picker path. No new app window or scene was added.

The helper rejects multiple items, mixed file/text items, web links, remote authorities and malformed/ambiguous URLs. Candidate hover uses item/type metadata only. Actual drop reads an NSURL with the file-only pasteboard option, preserves the native URL, and invokes `PreviewSession.open` without a suspended loader. File access, format enablement, missing/unsupported outcomes, budgets, redaction and cancellation remain owned by the existing pipeline. Invalid drops do not call the session or erase loaded content.

## Verified evidence

Environment: the same Apple silicon/macOS 27.2/Xcode 27.0 host as [installed-host validation](installed-host-2026-10-04.md), with a macOS 15 deployment target.

| Check | Result |
|---|---|
| Test-first URL-ingress check | Before implementation, the single-file candidate assertion failed; the implemented helper passes |
| Private pasteboard: native local URL | Preserves a Unicode URL for a nonexistent file without requiring file reads or path reconstruction |
| Private pasteboard: deferred URL provider | Hover accepts the metadata without invoking its data callback |
| Private pasteboard: multiple/mixed/text items | Rejects them without silently selecting the first item |
| Private pasteboard: malformed/nonlocal input | Rejects web URLs, remote authority, relative/malformed file URL, query and fragment cases |
| `./script/build_and_run.sh --test` | 90 package tests, four existing companion-model checks and three new file-drop check groups pass |
| `./script/build_and_run.sh --verify` | Signed companion and both embedded extensions build; strict signature checks and companion launch pass |
| `./script/build_and_run.sh --check` | Project/catalog/resource checks pass, including 107 localization keys |
| Signed companion observation | Drop instruction and Open File are visible in Try Preview and its accessibility tree, inside `companion.main` |
| Keyboard alternative | Command-O opened the attached picker; fresh JSON Lines displayed with synthetic token concealed and Unicode preserved |

Tests create randomly named private pasteboards and release them afterward. They do not inspect or change the general clipboard, user preferences or user documents.

## Open checks

- A real Finder-to-sandbox drag was not completed in this run. Native URL handling and helper tests do not prove that system file-access grants reach this signed app.
- Live drag hit-testing, copy-operation mask, rejected/cancelled drag feedback and teardown are reviewed in source but not verified by the private-pasteboard checks. No end-to-end drag pass is claimed.
- Full VoiceOver/focus behavior, translated rejection text and macOS 15 runtime remain open. The observed accessible instruction does not establish announcement of changing feedback.
- Native pasteboard URL decoding can synchronously consult the drag source. It lies outside parser budgets and has no app-enforced hard deadline; only metadata-only hover is established by the deferred-provider check.
- The existing Customization tool-service crash remains independent of this ingress change.
