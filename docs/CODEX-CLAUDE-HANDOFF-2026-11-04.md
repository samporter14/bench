# Capsid performance and quality-of-life implementation — Claude handoff

## Checkout and scope

- Working checkout: `/Users/posamuel/Downloads/capsid-review-fixes-2026-11-04`
- Branch: `codex/capsid-performance-qol-2026-11-04`
- Starting commit: `f36abe87bdf2ea61abdc60fe0d9b5327889b1715` (Capsid 1.1.4, build 61).
- Origin: `https://github.com/samporter14/bench.git`.
- Original checkout: `/Users/posamuel/Documents/Default Project/bench`. The implementation work is in the separate checkout above.
- Sam requested implementation of the November 4 performance/QoL review and a handoff explaining the work. This is app UI, performance, and file-management work.
- Release version and build number have not been bumped. Installation, publishing, and release packaging are separate from this implementation.

## Shelf search

`ShelfTextIndex.swift` now builds an unpublished working text index and publishes batches at the existing 250 ms interval, including a final flush before declaring indexing finished. Changed file paths accompany each batch, including removed text.

`ShelfModel.swift` uses cancellable background workers for nonempty searches over collections of at least 80 items. It can publish metadata matches first. A generation check prevents superseded query/scope/index results from reaching the UI. Once a complete match set exists, subsequent text batches reevaluate only items whose prose files changed; pending changes survive canceled workers. The unread-file count reuses computed matches. Unchanged search results do not trigger redundant redraws or reset selection.

The existing per-file bounds remain: read at most 1 MiB and retain at most 200,000 characters. There is no new aggregate index-memory cap; this work does not claim a measured RAM or CPU reduction on Sam's real library.

## Decoding and native reading

- `ArtifactReader.swift`: artifact JSON/base64 parsing runs off the main actor, with cancellation checked before returning the result.
- `ReferenceModel.swift`: reference-answer Markdown rendering is asynchronous and cached. A late render is accepted only when the current answer ID and text still match. `ReferenceWindow.swift` shows a preparation state and can copy raw text while rendering finishes.
- `ReferenceFind.swift`: per-window, case-/accent-insensitive Find with next/previous, wrapping, a match count, cancellation, and a maximum of 10,000 stored matches. The counter indicates when it is capped.
- Command-F routes to the active reference reader, or to the existing web-page Find otherwise. Command-G and Shift-Command-G move through native reader matches. Find follows the visible answer/document; hidden, removed, and empty-page transitions detach the old text view.
- Scope: the reference reader's answer and Markdown-document views. The independent Shelf document card has not gained a separate Find bar.

## Papers

- Multi-selected Shelf items can be added in displayed order to contiguous panel labels in one paper. Selection notes are skipped with a count shown in the sheet. The sheet previews labels and warns about occupied destinations.
- A batch is one write and one undoable change. Panel labels cannot silently roll past Z into another figure.
- `PaperModel.swift` maintains up to 50 undo steps per paper for panel changes, replacements, swaps, relabeling, and removal. Redo is cleared after a new edit. History is in memory for this window session.
- Undo/Redo use the same serialized disk writes and external-edit checks as ordinary changes. They refuse to overwrite a PAPER.md changed elsewhere; source files on the Shelf remain intact.
- Buttons and Command-Z/Shift-Command-Z work on the Papers page. Editable text fields retain normal text-editing undo behavior; sheets do not receive paper-history shortcuts.

## Search Answers

Quick Open (Command-Shift-O) now offers **Search Answers…**. The user chooses a project and explicitly starts a phrase search. Matches include a snippet and open the reference reader at the matching history row.

`AnswerSearch.swift` searches at most 50 recent listed sessions, six pages of up to 50 history rows per session, and returns at most 200 matches. It reads whole truncated turns when possible, uses the existing typing-aware ReadingGate, and cancels obsolete searches when the query/project changes or the sheet closes. Interrupted reads terminate the progress state. Missing reads or exhausted limits are labeled as potentially incomplete results.

This is a bounded on-demand search, not a persistent full-history index. It inherits the existing `fetchProjectSessions` eligibility rules: root sessions with task summaries, no hidden/upload/concierge sessions, and no archived projects. It searches Claude's answer text and user-facing tool notes, not arbitrary attachment content. Nothing is indexed on disk.

## Animation policy

- Working specimens use 15 fps in Low Power Mode unless the new Settings → Specimens option **Keep full frame rate in Low Power Mode** is enabled. The normal frame rate remains 30 fps.
- Reduce Motion builds only the single waiting-animation still that is actually displayed, rather than a complete animated loop.
- Existing idle hold behavior remains. No battery-life claim has been measured.

## Large-file transfers

`Remote/ArtifactFile.swift` adds a file-backed save path, integrated into Keep, Shelf add, individual Results save, and Save All. Small downloads retain their existing in-memory path; known large files go directly to disk, and an inaccurate listed size can fall back when the small reader reaches its cap.

- Authentication stays in the existing WebKit session. JavaScript pulls from the response stream with backpressure; the bridge carries at most 256 KiB per chunk. Native decoding, hashing, and temporary-file writes run on a dedicated actor.
- Saves have a 512 MiB per-file limit and five-minute transfer timeout. Browser stream chunks above 4 MiB are refused. Preview, Quick Look, and clipboard paths keep the 8 MiB cap; text previews keep their smaller cap.
- Transfers are pinned to daemon origin, version, nonce, and current byte offset. Redirects, unexpected response URLs, changed sequence state, and mismatched unencoded Content-Length are refused. A page reload after progress fails instead of restarting byte zero into an existing file.
- The existing queue retains priority, deduplication, cancellation, and bounded concurrency. File-backed and preview requests have separate keys. Keep/Results display throttled byte progress and cancellation/retry controls.
- The private temporary directory/file uses permissions 0700/0600. Deduplicated consumers share the spool; it is deleted after its last owner releases it. Failure/cancellation cleans partial spools. Final content is staged beside the destination and published with rename. Exclusive saves use `RENAME_EXCL` rather than requiring hard-link support.
- Keep records actual byte count and streaming SHA-256. Its previous policy is preserved: a mismatch against the daemon checksum is recorded and reported, not silently treated as verified. Missing expected checksums are not independent verification.
- Large legend files are saved in full, while only a bounded prefix is read for preview.

The native writer and actual JavaScript pull/abort scripts have synthetic-file/fake-fetch tests. Live authenticated end-to-end validation remains necessary before release.

## Validation status

Final combined result: **461 tests in 66 suites passed** (7.167 seconds of test execution), with exit status 0. The app and complete test target compiled successfully. All 18 new transfer tests passed. `git diff --check` also passed. Eight existing macOS-service-dependent tests were explicitly excluded as documented below; this is not a full-suite pass.

The implementation and this handoff are committed on the local branch above. They have not been pushed, merged into the original checkout, installed, or released. No source changes were made after the successful validation run; only this handoff was finalized.

```sh
cd /Users/posamuel/Downloads/capsid-review-fixes-2026-11-04
CLANG_MODULE_CACHE_PATH=/tmp/capsid-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/capsid-module-cache \
swift test --disable-sandbox --jobs 4 \
  --filter '^BenchTests[.](ReaderSearchTests|AnswerSearchLimitsTests|ShelfText[^/]*Tests|ShelfUnreadTests|ShelfFilesStillToReadTests|ShelfStillReadingModelTests|PaperModelTests|SpecimenHold[^/]*Tests|ReferenceModelTests|ArtifactFile[^/]*Tests|ArtifactPathTests|ArtifactCodecTests|ArtifactReadTests|Keep[^/]*Tests|ShelfTransfersTests|ShelfCancellationTests|ShelfSaveAllTests|ShelfSavedFilesTests|ResultsShelfTests|ShelfAddTests|ShelfFailureTests|ShelfOneAtATimeTests|ShelfVersionsTests|ShelfClaudeLegend[^/]*Tests)/' \
  --skip 'aFigureIsReadOnceAndAFailedOneNotAgain|aDragTakesItsContentTypeFromTheExtension|aDragFetchesNothingUntilItIsDropped|aThumbnailIsNotReadAgainWhileItsBytesAreBeingDecoded|closingTheWindowLetsTheDecodedThumbnailsGoAndOpeningReadsThemAgain|thumbnailsOnlyForImagesOnlyWebPAndOnce|unrelatedShelfUpdatesDecodeNothingAndTouchNoThumbnail|aFailedThumbnailIsTriedAgainWhenTheWindowOpensAgain'
```

`--disable-sandbox` disables SwiftPM's nested build sandbox; the managed workspace sandbox remains in force. The module-cache paths allow compilation without writing to the user's protected cache directories. Eight existing reference/Results thumbnail, type-resolution, and file-provider tests are explicitly excluded after reproducing the macOS service failures described below. No new feature test is excluded. These skips belong to this environment's validation command; they are not disabled in the test sources.

New transfer coverage comprises six native writer tests, eight tests of the actual JavaScript stream/abort scripts with fake fetch, and four disk/model integration tests. This includes downloads above 8 MiB, incremental hashing, actual/declarative length limits, origin/offset checks, state loss, cancellation cleanup and late replies, Save All no-overwrite naming, Keep mismatch disclosure, and unknown-size fallback. Reader/search/Papers regression tests cover stale task results, full truncated-answer searches, search limits, unchanged-result redraws, preserved multi-selection, Find target transitions, and reversible batches with external-edit protection.

An earlier full-suite attempt encountered unavailable macOS services in this environment: a valid generated PNG reported `UTType("public.png")?.conforms(to: .image) == false`. Existing thumbnail/compare tests failed; a thumbnail fixture force-unwrapped the failed decode and terminated the run. Pasteboard and sandbox-extension tests also failed. A local-socket probe returned `Operation not permitted`. Repeat the full suite and live-session checks in a normal macOS development session; this handoff does not claim a full-suite pass.

## Manual verification before release

1. On a logged-in local Claude Science instance, exercise an artifact above 8 MiB through Keep, individual Results save, and Save All. Verify the saved byte count and SHA-256, provenance identity, cancellation, retry, and duplicate-name behavior. Also verify small previews/clipboard paths retain their original limits.
2. Open a large reference answer, navigate away during rendering, then return. Find should follow the visible answer/document, including empty documents and figure-only replies. Verify Command-F, Command-G, Shift-Command-G, and normal Copy.
3. Search a Shelf with hundreds of text items while typing a new query and changing project. Edit/delete an indexed file externally, refresh, and verify both new matches and removed matches without selection flicker.
4. Select multiple figures, Add to Paper starting at a chosen panel, then Undo and Redo. Verify replacement warnings and text-field Undo. Edit PAPER.md externally and verify a subsequent Undo reports the conflict rather than overwriting it.
5. Search Answers in a project with older sessions and long truncated answers. Confirm the result opens the correct reply, canceled searches cannot overwrite newer results, and the incomplete-result message is clear.
6. Toggle macOS Low Power Mode, the full-frame-rate preference, and Reduce Motion. Verify still/animated transitions in the main window and floating panel.

## Picking up the work

Work directly in the checkout and branch above, or fetch its branch into the original repository after checking for unrelated local changes:

```sh
cd '/Users/posamuel/Documents/Default Project/bench'
git status --short
git fetch /Users/posamuel/Downloads/capsid-review-fixes-2026-11-04 codex/capsid-performance-qol-2026-11-04
git log --oneline HEAD..FETCH_HEAD
git diff --stat HEAD...FETCH_HEAD
```

Review and merge/cherry-pick the fetched commit according to the original checkout's current branch and any newer work. Do not reset or overwrite local changes. The checked-out release script is `Scripts/build-app.sh`; consult its options and rerun the relevant tests in an ordinary macOS development session before packaging/installing.
