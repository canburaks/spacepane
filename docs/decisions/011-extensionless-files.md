# Files without an extension

Date: 2026-10-04. Status: accepted at the user's request; implemented and observed on one host. This record replaces the earlier rule that the product never claims `public.data`.

## Why the earlier rule had to change

macOS assigns the type `public.data` — exactly, not a subtype — to every regular file whose name has no extension, for example `zprofile`, `.zprofile`, `hosts` and `notes`. Quick Look matches an extension's declared types exactly. So Finder can only hand such a file to this product if the preview extension declares `public.data`. Without it the file showed the system's generic icon, and the pipeline reported the file as unsupported.

Exact matching also limits the claim: a PDF, an image or a file with an unknown suffix has its own identifier (a dynamic one for unknown suffixes) and is not routed by a `public.data` declaration.

## Decision

- Add one catalog format, `text.extensionless` ("Files Without an Extension"), with content type `public.data`, no suffixes and no file names. It has its own switch in File Types and is on by default.
- Only the **preview** extension declares `public.data`. The format's thumbnail policy is `none`, so the thumbnail extension does not register it and extension-free files keep their system icons.
- Classification treats a root type (`public.data`, `public.item`, `public.content`) as an identity only when it is the file's exact type and the name has no suffix. A root type is never a conformance ancestor, so opening an image or a document in the companion cannot fall into this format.
- The adapter receives bounded bytes and shows them only when they are text: valid UTF-8, or UTF-16 with a byte-order mark, containing no NUL and no binary control character. Anything else is reported as binary content and is never displayed. A script that names its interpreter on the first line is styled as source code; other text is plain. The normal budgets, cancellation and concealment apply.
- Well-known extension-free names — shell startup files such as `.zshrc`, `zprofile`, `.bash_profile` and `profile`, and build files such as `Makefile`, `Dockerfile` and `Gemfile` — are filename aliases of the existing Source Code format. They are highlighted and follow the Source Code switch. If Source Code is turned off, such a file shows the disabled state; the broader extension-free format does not render it.
- `validate_project.py` allows `public.data` for exactly one text format with no suffixes, no names and no thumbnails, and still rejects `public.item` and `public.content`.

## What this does not promise

- macOS still chooses the provider. If another installed app declares `public.data`, Finder may use it instead.
- Files that carry the executable bit are typed `public.unix-executable`, not `public.data`, and are not covered. Scripts without an extension that are marked executable therefore keep the system preview. Claiming that type would also route every command-line binary here.
- A binary file without an extension now shows this product's "binary content" message instead of the system's generic preview when Finder selects this provider. Turning the type off in File Types shows the disabled state for all such files; it does not hand them back to the system preview.
- No thumbnail is produced for these files.

## Validation

See [the validation record](../validation/extensionless-files-2026-10-04.md).
