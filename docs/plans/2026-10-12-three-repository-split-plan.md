# Three-repository split plan

Date: 2026-10-12 (Europe/Istanbul). Status: executed on 2026-10-12 on the owner's instruction, except the steps listed under "Execution record" at the end. The body below is the plan as approved.

Scope, from the owner's request: turn `/Users/cbs/Github/spacepane` into a workspace folder that holds three independent git repositories, so that the macOS app can be open-sourced while the website stays private. The owner deleted the GitHub repository `canburaks/spacepane` on 2026-10-12 and will redeploy the website on Netlify by hand.

```
/Users/cbs/Github/spacepane/        workspace: a small local git repository; the three children are ignored
  AGENTS.md  README.md  mani.yaml  spacepane.code-workspace  .gitignore  .claude/launch.json
  spacepane/                        the macOS app        -> canburaks/spacepane (private until the owner publishes it)
  spacepane-web/                    the website          -> canburaks/spacepane-web (private, permanently)
  spacepane-cad-source/             the OCCT source mirror -> canburaks/spacepane-cad-source (public, exists)
```

## How this plan was produced

Four read-only research agents (Sonnet 5.5) ran in parallel and the lead integrated their reports: a cross-repository coupling audit, a publication audit of the git history, a survey of multi-repository tools, and a brief on Turborepo/Nx, the ShadCN Blocks licence and the OCCT repository layout. Claims are marked verified by command or file (V), inferred (I) or an owner statement (O).

Checked directly by the lead on 2026-10-12:

- `gh repo view canburaks/spacepane` no longer resolves; `canburaks/spacepane-cad-source` is public with one commit and the tag `1.0.0`; `canburaks/spacepane-web` does not exist. (V)
- The local `.git` is now the only copy of this repository's history: 10 commits, with `claude/app-store-listing` and `claude/open-source-offer` both merged into `main`. One worktree, no stash. (V)
- 72 tracked files are modified and 7 paths are untracked. The untracked paths include two 39 MB videos under `docs/release/store-listing/app-preview/` and a 1.0 GB `script/store-preview/` (its `node_modules` is ignored). (V)
- Deleting the GitHub repository also deleted its pull requests and its Actions secrets and variables (`PREV_ASC_ISSUER_ID`, `PREV_ASC_KEY_ID`, `PREV_ASC_PRIVATE_KEY`, `PREV_DEVELOPMENT_TEAM`). (I, from how GitHub deletes a repository)
- No tracked script, workflow, configuration file or the Xcode project contains an absolute `/Users/cbs` path, so the app tree can move one level down without edits to build inputs. (V)

## Decisions already made

- Three repositories, not two. The mirror is a generated export of `script/package_cad_source_offer.py`; it is already public and referenced by the About text, `Configuration/Branding.xcconfig`, the website and the store listing, and counsel is reviewing that structure. (O for the layout; V for the references)
- The tool for the workspace is `mani` (one committable `mani.yaml`; `mani sync` clones, `mani exec` and `mani run` act on all three). Turborepo and Nx manage tasks inside one repository and do not fit. `brew info mani` resolves 0.32.1 on this Mac; it is not installed yet. (V)
- The app and the website start from fresh history. Every commit that touched `web/` or `Website/` also touched app files, and `web/src` holds components adapted from ShadCN Blocks, whose licence forbids publishing components or derivatives in a public repository. The old history is archived locally and never pushed. (V for the commits; the licence was read through a summarising fetch, so confirm the wording on the live page)
- In the website repository the Next.js app is the repository root and the static reference becomes `Website/` inside it. Netlify's base directory is then the repository root.

## Decisions the owner still has to make

| # | Decision | Default used by this plan | Blocks |
|---|---|---|---|
| D1 | Licence of the app. There is no root `LICENSE`; `Native/CADWorker/LICENSE` is MIT. | None. MIT or Apache-2.0 are the simplest; GPL-3.0 keeps others from shipping store clones but needs a contributor agreement before accepting outside code. | Making `spacepane` public only |
| D2 | Author name and email on the new initial commits. The old history used `34249966+canburaks@users.noreply.github.com`. | The address the owner names; GitHub's no-reply address if none is given. | First commit in each repository |
| D3 | The two candidate preview videos (39 MB each) and the nine chosen screenshots (15 MB). | Videos stay out of git; screenshots are committed. | App initial commit |
| D4 | A remote for the workspace repository. | None; it stays local. | Nothing |
| D5 | The Apple Team ID and bundle identifiers that `.github/workflows/*.yml` carry as fallbacks. | Leave them; a signed app already discloses both. | Making `spacepane` public only |

## What moves where

| Today | After |
|---|---|
| `web/**` (629 tracked files, plus ignored `node_modules/`, `.next/`) | `spacepane-web/**`, as the repository root |
| `Website/**` (17 tracked files) | `spacepane-web/Website/**` |
| `Website/assets/img/icon.svg` | also copied to `spacepane/Configuration/AppIcon.svg`, the app's own icon source |
| `.claude/launch.json` (every entry serves the website) | `spacepane-web/.claude/launch.json` with repository-relative paths, and a workspace copy with `spacepane-web/` prefixes |
| Every other tracked path, and the untracked store tooling | `spacepane/**`, relative paths unchanged |
| Ignored local state: `.appstoreconnect/`, `.build/`, `dist/`, `Configuration/Local.xcconfig`, `xcuserdata/` | moves with the app; never committed |
| `/Users/cbs/Github/spacepane-cad-source` | `/Users/cbs/Github/spacepane/spacepane-cad-source`, with its `.git` and remote intact |
| `.git` (the old history) | `/Users/cbs/Github/spacepane-pre-split-backup/` only |

## Phase 0 — Freeze and back up

Nothing here is destructive. No later phase starts until every step passes.

1. Close Xcode, stop every preview server and confirm no other agent session is working in the folder.
2. Commit the 72 modified files and the small untracked sources on the old `main`, so the archive holds the current state. Leave the videos and `script/store-preview/` untracked.
3. Make a full copy, including ignored files: `cp -cR /Users/cbs/Github/spacepane /Users/cbs/Github/spacepane-pre-split-backup`. On APFS this is a clone and takes no extra space. This copy is the rollback and the archive of the old history.
4. Verify the copy: `git -C ../spacepane-pre-split-backup status` is clean and `git log --oneline | wc -l` matches; `Configuration/Local.xcconfig` and `.appstoreconnect/` are present in it.
5. Confirm `/Users/cbs/Github/prev` still has its private remote; it holds the history before 2026-10-10.

## Phase 1 — Restructure on disk (lead, sequential)

Filesystem moves only, with explicit names and no globs.

1. Copy `Website/assets/img/icon.svg` to `Configuration/AppIcon.svg`.
2. `mv web spacepane-web`, then `mv Website spacepane-web/Website`, then move `.claude/launch.json` to `spacepane-web/.claude/launch.json`.
3. Remove the old `.git` from this folder. It survives in the Phase 0 copy; check that copy again first.
4. Create `spacepane/` and move into it, by name: `.appstoreconnect`, `.build`, `.codex`, `.github`, `.gitignore`, `AGENTS.md`, `Apps`, `CHANGELOGS.md`, `Configuration`, `Extensions`, `Fixtures`, `Native`, `PLAN.md`, `Packages`, `Prev.xcodeproj`, `README.md`, `Tests`, `ThirdPartyNotices`, `dist`, `docs`, `script`, `tools`.
5. `mv /Users/cbs/Github/spacepane-cad-source` into this folder.
6. The folder now holds exactly `spacepane/`, `spacepane-web/` and `spacepane-cad-source/`.

Phases 2, 3 and 4 touch disjoint repositories and can run as three parallel agents; the lead owns Phase 5, the verification and every push.

## Phase 2 — The app repository (`spacepane/`)

Edits, all outside Swift modules except one script:

1. `script/check_static.py:519-566`: remove `website_step` and its `Step("website data", ...)` registration. The three `node web/...` commands it runs no longer have a target.
2. `script/test_check_static.py`: remove `"website data"` from the step list (line 936) and the `website` workstream from the ownership expectations (lines 257, 370 and 406).
3. `tools/ownership.json:288-293`: remove the `website` workstream. Keep `.claude/**` in the lead's list.
4. `script/generate_app_icon.swift:5,13` and `README.md:93`: read `Configuration/AppIcon.svg`. Confirm the file is not inside an Xcode synchronized group, so it is not bundled.
5. Untracked store tooling: `script/store-preview/design/render.mjs:21` loads Playwright from `web/node_modules`, and `script/store-preview/remotion/scripts/make-assets.mjs:23` copies `web/public/images/icon.svg`. Point the first at `SPACEPANE_WEB_REPO` (default `../spacepane-web`) and the second at `Configuration/AppIcon.svg`.
6. `AGENTS.md` line 15: replace the website paragraph. It should say that the website is the private sibling repository `spacepane-web`, that nothing in this repository may depend on it or copy from it, and that four paths are a contract the website's sync script reads: `Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json`, `Packages/PreviewCore/Sources/PreviewRenderers/Resources/<language>.lproj/Localizable.strings`, `tools/localization/languages.json` and `docs/validation/host-matrix.json`.
7. `PLAN.md` lines 552-556: point the open website items at `spacepane-web`, and replace "move the icon source to `web/public/images/icon.svg`" with the completed move to `Configuration/AppIcon.svg`.
8. `.gitignore`: add the preview videos per D3. Leave historical records under `docs/` unchanged; they describe the layout that existed when they were written.
9. Add the root `LICENSE` and a licence section in `README.md` once D1 is answered.
10. Add a `CHANGELOGS.md` entry for the split.

Then:

11. Remove only the caches that embed the old path: `.build/xcode`, `.build/validation` and `Packages/PreviewCore/.build`. Keep `.build/archive`, `.build/export` and `.build/store-screenshots`; they hold the uploaded build's archive and the raw captures.
12. Validate on this Mac: `./script/build_and_run.sh --check-static`, `python3 script/test_check_static.py`, `python3 script/package_cad_source_offer.py --check`, `xcrun swift script/generate_app_icon.swift --check`, `./script/build_and_run.sh --check` and `--test`.
13. `git init -b main`, set the author per D2, and make one initial commit. Before committing, check `git status --short --ignored` so that no key, `Local.xcconfig` or video is staged.
14. Create `canburaks/spacepane` as a private repository and push. Re-create the four Actions secrets and variables. `package.yml` runs on `pull_request`; confirm that no job on that trigger reads a secret before the repository becomes public.
15. Making the repository public is a separate step on the owner's explicit instruction, after D1 and D5 and a review of the pushed tree on GitHub.

## Phase 3 — The website repository (`spacepane-web/`)

1. Add `scripts/lib/app-repo.mjs`: the app checkout is `SPACEPANE_APP_REPO`, defaulting to `../spacepane`, with a clear error when it is absent. Use it in `scripts/sync-app-data.mjs:26`, `scripts/lib/host-matrix.mjs:17` and `scripts/host-matrix.test.mjs:165,173`.
2. `scripts/sync-static-privacy.mjs:15`: the page is now `Website/privacy.html` inside this repository; update the three messages that name the old paths.
3. `Website/tools/generate_formats.py:12-15`: read the catalog from the same app checkout and write to `Website/assets/data/formats.json` here.
4. `eslint.config.mjs`: add `Website/**` to `globalIgnores`, because `eslint` now sees the static site's scripts.
5. `netlify.toml`: update the comment; the base directory is the repository root. The build command, publish directory, Node version and plugin do not change.
6. `.claude/launch.json`: `Website` stays as is; drop `--prefix web` and `cd web`.
7. `AGENTS.md`: write real guidance, since the app's root file no longer governs this tree. Carry over the rules from the app's line 15 (read `README.md` and `DESIGN.md`, all copy from JSON in every language, `npm run data:sync`, `npm run visual:compare`) and add that this repository stays private because of the ShadCN Blocks licence. Update the comment at `next.config.ts:13` to match.
8. `README.md` and `DESIGN.md`: replace `../Website`, `../docs` and `../tools` with the new locations.
9. Validate: `npm run check` with the app as a sibling, then `npm run build`. Run `npm run visual:compare` against `Website/` served on port 4180.
10. `git init -b main`, author per D2, one initial commit, create `canburaks/spacepane-web` as private, push.
11. Owner, by hand: connect the Netlify site to `canburaks/spacepane-web` with an empty base directory. Relinking the existing site keeps the domain; a new site needs `spacepane.com` moved to it. Then check `/`, `/open-source`, the `/support.html` and `/privacy.html` redirects that the shipped app links to, and the 14 languages.

Not changed here: both `package-lock.json` and `pnpm-lock.yaml` stay tracked, as they were for the working deployment. Choosing one is a follow-up.

## Phase 4 — The source mirror (`spacepane-cad-source/`)

1. Delete the stray local `.DS_Store` files; `--check` reports them as files missing from `MANIFEST.sha256`.
2. Assemble a fresh bundle from the app repository with `script/package_cad_source_offer.py --output <empty directory>` and compare it with the mirror. Three files differ today: `script/build_cad_worker.py`, `script/embed_cad_worker.py` and `docs/dependencies/occt.md`.
3. Before publishing a refresh, establish which app commit build 1.0.0 (1) was archived from, because the mirror must match the shipped helper. Then choose the tag.
4. Commit and tag locally. Pushing to the public mirror happens on the owner's explicit instruction.

Follow-up, outside this plan: a workflow in the app repository that runs the packager and pushes to the mirror with a single-repository deploy key.

## Phase 5 — The workspace (this folder)

1. `brew install mani`.
2. `git init -b main` here, with a `.gitignore` listing `/spacepane/`, `/spacepane-web/`, `/spacepane-cad-source/` and `.DS_Store`.
3. `mani.yaml` (verify the task syntax against the installed version):

   ```yaml
   projects:
     spacepane:
       path: spacepane
       url: https://github.com/canburaks/spacepane.git
       tags: [app]
     spacepane-web:
       path: spacepane-web
       url: https://github.com/canburaks/spacepane-web.git
       tags: [web, private]
     spacepane-cad-source:
       path: spacepane-cad-source
       url: https://github.com/canburaks/spacepane-cad-source.git
       tags: [mirror]

   tasks:
     status:
       desc: Branch and working-tree state of every repository
       cmd: git status --short --branch
     app-static:
       desc: The app's static checks
       target: { projects: [spacepane] }
       cmd: ./script/build_and_run.sh --check-static
     web-check:
       desc: The website's data, locale, type and lint checks (reads ../spacepane)
       target: { projects: [spacepane-web] }
       cmd: npm run check
     mirror-check:
       desc: The mirror matches its manifest
       target: { projects: [spacepane-cad-source] }
       cmd: python3 ../spacepane/script/package_cad_source_offer.py --check .
   ```

4. `AGENTS.md`: the map of the three repositories and their visibility; the rule that nothing is copied from `spacepane-web` into a public repository; the rule that the mirror is generated and never edited by hand; the four-path data contract; and an instruction to read a child repository's own `AGENTS.md` before working in it. Do not add a workspace `CLAUDE.md`: one research report says it would stop the app's `AGENTS.md` from loading, and that is untested.
5. `spacepane.code-workspace` with the three folders, and `.claude/launch.json` with the website servers under `spacepane-web/`.
6. `README.md`: how to rebuild the workspace on a new machine (`mani sync`), and which files are local-only and must be restored by hand (`Configuration/Local.xcconfig`, the App Store Connect key).

Agent sessions keep opening at `/Users/cbs/Github/spacepane`, so the existing Claude project memory stays attached. A session opened inside a child repository gets a new, empty project memory.

## Verification before the plan counts as done

- Each child has its own `.git`, a clean `git status` and the expected remote; the workspace `git status` shows none of the children's files.
- App: the six commands in Phase 2 step 12 pass, and `git grep -n "web/\|Website/"` finds only historical records, `CHANGELOGS.md`, `PLAN.md` and the new `AGENTS.md` wording.
- App: `git log --all --name-only` lists no path under `web/` or `Website/`, and `git grep -il shadcnblocks` finds prose only.
- Website: `npm run check` and `npm run build` pass; the live site answers on every URL the shipped app links to.
- Mirror: `package_cad_source_offer.py --check` reports no problem.
- `mani run status --all` lists three repositories.

## Rollback

Until something is pushed, rollback is: delete `/Users/cbs/Github/spacepane`, rename `spacepane-pre-split-backup` back, and move `spacepane-cad-source` out again. After a push, the new GitHub repositories can be deleted; nothing in the plan rewrites or deletes the mirror's existing history. Keep the backup until the owner says it can go.

## Risks

- A push of the old history to a public remote would publish the website source. The fresh `git init` in Phase 2 removes that path; the old `.git` exists only in the backup.
- `canburaks/spacepane` documentation links to pull requests 1 and 2 are dead; new pull requests restart at 1.
- The website's data check no longer runs in the app's CI. A catalog or strings change that the website depends on is caught only when `npm run check` runs in `spacepane-web`, which `mani run web-check` makes one command.
- The icon now has three copies (app, `spacepane-web/public/images`, `spacepane-web/Website/assets/img`) kept in step by hand, one more than today.

## Execution record (2026-10-12)

Done:

- Phase 0: the pending work was committed on the old history (`8713a2a`) and the folder was cloned to `/Users/cbs/Github/spacepane-pre-split-backup`; the copy has the same 11 commits and the same file list, including `Configuration/Local.xcconfig` and the App Store Connect key folder.
- Phase 1: the moves ran as listed. The old `.git` was moved aside rather than deleted; it also exists in the backup.
- Phase 2: edits 1 to 8 and 10, the cache removal and the six validation commands (all pass; see the changelog entry of the same date). One initial commit, pushed to a new private `canburaks/spacepane`.
- Phase 3: edits 1 to 10 and the checks; `npm run check`, `npm run build`, the locale-detection test and the hydration test pass. One initial commit, pushed to a new private `canburaks/spacepane-web`.
- Phase 4: the mirror was refreshed from a fresh bundle, committed locally and tagged `1.0.0-build.1`. The changelog records that build 1.0.0 (1) was made from the tree of commit `e3ab9f3`, and the mirrored files are unchanged since that commit.
- Phase 5: `mani` 0.32.1 installed; the workspace repository holds `mani.yaml`, `AGENTS.md`, `README.md`, the editor workspace file and `.claude/launch.json`, with no remote.
- Owner defaults applied: commits use the GitHub no-reply address (D2); the two videos are ignored and the nine screenshots committed (D3); no workspace remote (D4); workflow identifiers unchanged (D5).

Not done, and why:

- No `LICENSE` (D1 is open), and `canburaks/spacepane` is not public.
- The mirror commit and tag are not pushed; that needs the owner's instruction. A release tarball with the OCCT archive for the new tag was not built.
- The four Actions secrets and variables were not re-created; the values are the owner's.
- Netlify was not touched; the owner reconnects the site by hand.
- `npm run visual:compare` ran and reports 21 of 22 sections different. The inputs are unchanged by the split (`src/` and `public/` are byte-identical to the backup and `Website/` differs only in an HTML comment), so this gap pre-dates it.
- `mani run` takes one task at a time; `mani run status` replaces the plan's `mani run status --all`.
