# Direct-preview file drops

Date: 2026-10-04. This adds the planned explicit file-drop entrypoint without adding a window or another parser path.

## Contract

Try Preview has a localized drop strip above its content. Drop exactly one local file URL there; Open File and Command-O remain the keyboard-accessible alternatives. Existing preview content is retained when a drop is rejected. Directory, missing-byte, unsupported-format and disabled-format outcomes remain the existing pipeline's responsibility.

A small native AppKit target owns drag metadata and feedback. A separate helper accepts one pasteboard item with a file-URL representation and reads it using `NSPasteboard.readObjects(forClasses:options:)` with the file-URLs-only option. It passes the native URL directly to `PreviewSession.open`, preserving the normal file-access lifetime, budgets, classification, redaction and cancellation path.

Hover reads item count/type metadata only. It does not request file bytes, stat the path, materialize promised files or invoke format parsers. The actual drop performs a synchronous URL-only read. There is no delayed item-provider task that can replace a file opened later. Source file I/O stays in the existing worker pipeline; system pasteboard decoding is a separate platform operation, not a claim of hard preemption or a measured performance budget.

Reject multi-item drops, pasted path strings, web URLs, remote URL authorities and malformed/ambiguous URLs. Do not choose the first item silently, infer permissions from a string path, or reconstruct the URL. A local file path may still refer to a mounted volume or a file-provider placeholder; the normal authorized read determines availability. This feature does not introduce remote fetching or automatic downloads.

## Why a narrow AppKit adapter

The app already uses AppKit for native selectable previews. A focused drag destination lets this entrypoint inspect the complete native item list, reject mixed/multiple drops, and preserve URL-only synchronous ingestion. It adds no public plugin contract or new format adapter responsibility. See Apple's [file-URL pasteboard option](https://developer.apple.com/documentation/appkit/nspasteboard/readingoptionkey/urlreadingfileurlsonly) and [pasteboard object reading](https://developer.apple.com/documentation/appkit/nspasteboard/readobjects(forclasses:options:)).

## Evidence boundary

Private-pasteboard checks exercise the actual ingress helper without touching the general clipboard or user settings. They can establish URL filtering and metadata-only hover behavior. They do not establish a Finder-to-sandbox drag grant or complete VoiceOver behavior. That requires a real signed-app drag on the supported OS matrix; do not mark it passed from helper tests or a visible strip alone.
