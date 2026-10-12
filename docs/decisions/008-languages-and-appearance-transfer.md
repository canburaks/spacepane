# 008 — Selected languages and inert appearance transfer

Accepted from the user's explicit language answers on 2026-10-04.

## Language contract

Development language is English. Selected additional languages: Turkish, German,
French, Simplified Chinese, Japanese, Hindi, Kurmanji in Latin script, Russian,
Indonesian, Bengali, Hausa, Portuguese and Spanish. “Hindu” and “Bangladesh” were
interpreted as Hindi and Bengali in the user-facing clarification. Chinese script,
Kurdish variety and Hausa were explicitly confirmed. Portuguese/Spanish use generic
language resources until a specific regional variation is requested/reviewed.

`tools/localization/languages.json` records exact resource tags. Translation inputs
are versioned dictionaries; the merge tool requires exact key coverage and compatible
format placeholders before writing either canonical catalog. Generated `.strings`
files support SwiftPM/CLT builds; app and both extensions receive localized branding
and imported-type metadata at build time. Brand placeholders remain replaceable.

Translations begin as implementation drafts. Native-speaker, text-expansion,
VoiceOver and actual Finder-host checks are release gates, not implied by 100% key
coverage. The hosting process chooses its effective language. Storefront pricing,
file encoding, source strings/paths and language selection remain independent.

## Appearance transfer

Schema 5 retains strict migrations from schemas 1–4 and adds semantic syntax styling
and bounded named profiles. Export/import contains only inert appearance data:
theme, typography and token traits. It cannot change enabled file types, install
code, load external resources or carry preview content. Unknown fields and malformed
values fail closed. Files are bounded before decoding.

Transfer uses the existing singleton window's native system file sheets. The
companion needs `com.apple.security.files.user-selected.read-write` for a user-chosen
export destination; the preview and thumbnail extensions do not receive that
capability. Read-only source handling is still enforced by their actual reader
implementations, not inferred solely from an entitlement. No Settings scene,
document scene or detached preview window is introduced.
