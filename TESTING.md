# Capsid — live test log

Capsid was called Bench until 0.6.0, so the entries before it say Bench.

The checklist from DESIGN.md. ✅ is seen working live, ⏳ is not tried yet
(listed with why), and ❌ is broken.

## 2026-09-28, first launch (Bench 0.1.0, Claude Science 0.1.54)

- ✅ **Signs in on first launch.** The daemon was already running, a nonce
  link was loaded, and the projects, sidebar and composer showed.
- ✅ **No Safari tab opened** at launch (nothing in Bench can reach Safari
  except the Browser window's "Open in Safari" button, per a code review of
  Routing.swift).
- ✅ **Find (⌘F).** The bar appears and highlights matches ("ready"). Caveat:
  it took keystrokes the user was typing into the page. Opening it should
  only happen on ⌘F, which it does; but check that closing it returns focus
  to the page.
- ✅ **Idle cost.** The Bench process is at 0.0% CPU and 49 MB with the
  window open. The page itself runs in WebKit's helper processes.
- ✅ **The user is working in it** (a session typed and sent in Bench).
- ⏳ **Waiting on Sam** (these touch real data or need his permission
  prompts):
  - file upload (single, multiple, folder)
  - dragging files into the page
  - downloads
  - microphone (the macOS prompt)
  - connector OAuth pop-up
  - pop-out windows
  - HTML preview
  - confirm dialogs (e.g. deleting a test session)
- ⏳ **Lab panel, needs-input card and finished card:** need a session that
  works, then waits or finishes.
- ⏳ **Claude Science desktop notifications:** need its desktop
  notifications switched on in its own settings.
- ⏳ **External link to the in-app Browser window, zoom, back/forward, and
  closing and reopening the window:** not tried while the user was typing.

## 2026-09-28, second round (toolbar, scenes settings, usage, context)

- ✅ **Toolbar:** it's on the right, with no back/forward.
- ✅ **Scenes split button:** the flask is clay when on (a baked-colour NSImage,
  because the toolbar templates symbols).
- ✅ **Usage remaining:** "5h 57% left" in the toolbar. The popover shows the
  current session at 57% and the week at 68% left with reset times, then the
  activity tiles and the year graph. The `/api/usage` reply is `{ok, data}`
  and is now unwrapped.
- ✅ **Context ring:** it showed "8%" in a session and is hidden on the
  dashboard.
- ✅ **Settings → Scenes:**
  - the size picker and glass preview well;
  - clay glass chips with counts;
  - glass search;
  - the 474-scene grid, where the hovered cell lifts to glass and plays.
  Sam: "looks good".
- ⏳ **The scenes panel at Small/Medium/Large, the needs-input card and the
  finished card:** these need a live session.
- ⏳ **Waiting on Sam:** file upload (a dialog was open during testing, with
  no report yet), downloads, microphone, connector OAuth, pop-outs, previews
  and external links.

## 2026-09-28, third round (usage countdown, readout capsule)

- ✅ **Usage remaining shows the reset countdown:** "54% left · resets in
  27m", then "53% left · resets in 19m" a few minutes later. The old "5h"
  prefix read as five hours to go.
- ✅ **One readout capsule:** the ring and usage share one glass capsule,
  split by a hairline, level with the Scenes button, and neither touches
  the capsule's edge. Sam: "looks good!"
- ❌ **Sign-in after a restart, intermittent:** one restart came up on
  Claude Science's "Sign in" screen instead of signing in on its own (the
  usage read got a 401), and Sam signed in by hand. The next restart signed
  in on its own. Cause not found yet.
- ⏳ **The redone context popover** (header and Refresh, one glass card): not
  seen yet.
- ⏳ **The readout capsule at the 900 pt minimum width** while the Lab
  capsule shows: not checked.

## 2026-09-29, a second Mac (Bench 0.1.0 from the GitHub release)

- ✅ **Download, install and Claude Science in the window** work on Sam's
  other MacBook.
- ❌ **No scenes panel and no needs-input cards there.** Both come from
  reading Claude Science's session database, and Bench dropped that read's
  errors silently. 0.1.1 shows the problem in the Scenes menu and Settings,
  and `Bench --diagnose` prints each step (CLI, daemon, database, schema
  columns, the reads). On this Mac every step passes (Claude Science 0.1.54).
  Waiting on the other Mac's output.
- 🔎 **Found it (0.1.1's `--diagnose` on the second Mac, macOS 27):** Claude
  Science 0.1.54 was running, and `~/.claude-science` held one org database
  of 3.1 MB with 0 sessions and 0 projects, while Sam has sessions there. So
  Bench read an empty database. 0.1.2 finds the database through the
  daemon's own `data_dir` (from `claude-science status`) and, among orgs,
  the one written most recently, and the report lists every data folder and
  org database with size, last write and session count.
- 🎯 **Real cause (a Claude on the second Mac, with 0.1.2's report):** the
  data folder was right (`~/.claude-science`, one org, 8 sessions), but every
  read returned 0 rows. macOS 27's `/usr/bin/sqlite3` is 3.54.0, where
  `-list` resets the separator set before it, so Bench's
  `-separator <US> -list` got "|"-joined rows and parsed nothing. Reproduced
  here with Homebrew's sqlite3 3.53.3 (`1|2` against `1<US>2`). 0.1.3 passes
  `-list` first; with 3.53.3 the report then reads 25 sessions and 7
  projects. The report also names the sqlite3 version, and `BENCH_SQLITE3`
  points Bench at another sqlite3 for tests. Waiting on the second Mac to
  confirm scenes and cards.
- ✅ **Confirmed on the second Mac (macOS 27, Bench 0.1.3):** Sam: "I think
  that fixed everything": scenes and cards now show there.

## 2026-09-29, Bench 0.1.4 (13 new scenes, activity since launch)

- ✅ **Batch L scenes (487 in all):** Prism, Faraday coil, Van de Graaff,
  Half-life, Gyroscope, Newton's rings, Separatory funnel, Büchner funnel,
  Flame test, Precipitate, pH rainbow, Immunofluorescence and Freezing
  cells. Each was checked on dark and light sheets at 48 and 16 pt; Faraday
  coil (read as a face), Gyroscope (a knot head-on) and pH rainbow (a comb)
  were redrawn once.
- ✅ **Activity graph starts at Claude Science's launch (June 30):** seen in
  `Bench --demo usage` (made-up history), with 14 columns of 14 pt squares,
  Sunday and Monday of launch week blank, "N sessions since June 30", and a
  600 pt wide popover in place of 780.

## 2026-09-29, Bench 0.1.5 (Appearance setting)

- ✅ **Settings → General → Appearance (Match Mac, Light, Dark; Match Mac by
  default):** with the Mac in Light, `--demo settings -appearance dark` came
  up dark with Dark selected. The saved settings were unchanged apart from
  the Settings window's position.

## 2026-09-29, Bench 0.1.6 (Specimens)

- ✅ **The grid follows the categories:** with only Chemistry on, the grid
  shows its 41 scenes, not all 487. The preview already played only what's
  on.
- ✅ **Preview light/dark switch (☀️/🌙 under the well):** the well draws on
  ivory or slate whatever the app's appearance, and starts on the app's.
- ✅ **"Scenes" is now "Specimens"** everywhere a user reads it: the Settings
  tab, the toolbar button and menu, search, the General toggles and the
  View menu. The README screenshot has been retaken.

## 2026-09-29, Bench 0.1.7 (live grid, light/dark grid, Choose specimens…)

- ✅ **"Choose specimens…" in the toolbar menu:** it now opens Settings through
  `SettingsWindow.open(tab:)`, a hidden SwiftUI host calling `openSettings`.
  The toolbar menu's own `openSettings` did nothing (Sam's report). The same
  path opened Settings in `--demo settings`. The click in the real menu is
  for Sam to confirm.
- ✅ **The grid plays live while on screen:** measured on the Specimens tab
  with all 487 on. The PlayedGlyph cells cost about 450 MB (130 MB with
  stills) and were replaced; `SceneLive` cells come to about 135 MB and
  about 11% of one core, and nothing once Settings closes.
- ✅ **The ☀️/🌙 switch covers the grid:** the grid sits on an ivory or slate
  board to match the well.

## 2026-09-29, Bench 0.1.8 (Specimens popover, sign-in recovery)

- ❌→✅ **Specimens dropdown:** reproduced on Sam's Bench with screen
  control. The menu showed Medium with every category ticked while the real
  settings were Small with Lab off; a click did toggle (Earth went off, and
  was put back) but the ticks never changed. It is replaced by a live glass
  popover. `--demo toolbar --open-options -sceneGroups '(chemistry,physics)'
  -sceneSize large` shows Large and exactly those two chips, "93 of 487 on".
- ✅ **SIGTERM quits like ⌘Q:** the log shows "Termination commencing /
  complete" for a demo copy sent `kill -TERM`.
- ⏳ **Sign-in recovery (`sessionLost` on an API 401):** built, but it only
  happens after an unlucky restart. It came up on the Sign in card again
  after the 0.1.7 install.

## 2026-09-29, Bench 0.1.9 (macOS 27 only)

- Sam's Mac is on macOS 27.0.1 now, and he wants Bench built for macOS 27
  exclusively. The minimum is 27.0 in Package.swift, Info.plist, actool and
  install.sh. The binary is minos 27.0 with SDK 27.0, and it builds with no
  warnings.
- ✅ Session reads on 27 (sqlite3 3.54.0): 25 recent sessions, 7 projects.

## 2026-09-29, Bench 0.1.10 (on macOS 27: chips that show on and off, whole-tab light/dark)

- ✅ **The popover works on Sam's real Bench (0.1.9, macOS 27),** clicked
  through with background accessibility presses. The options button opens
  it; Earth toggled off and back on (settings and "463 of 487 on" followed);
  "Choose specimens…" opened Settings → Specimens.
- ❌→✅ **On and off looked the same on macOS 27:** the glass tint barely
  showed, in the popover and in Settings. Chips now draw a clay ✓, fill and
  hairline when on, and grey text when off. The demo panel with 4 of 6 on
  reads at a glance, one line each.
- ✅ **The ☀️/🌙 switch sets the whole Specimens tab** (window scheme), with
  no boards.
- ✅ **On Sam's real Bench 0.1.10 (macOS 27), with background accessibility
  presses:** the options popover opens with all six chips named and toggles,
  "Choose specimens…" opens Settings, and 🌙 turns the whole Specimens tab
  (title bar, tabs, chips, grid) dark, with every chip clearly on.
- ❌ **The sign-in theory was wrong:** after the 0.1.10 install Bench came up
  on "Sign in". `sessionLost` ran at 15:09:31 ("An API read was refused;
  signing in again") and reloaded with a fresh `claude-science url` code,
  and Claude Science still showed Sign in. So the card is Claude Science's
  own sign-in after a restart, not Bench's local code. Next: ask Sam what
  clicking Sign in does (instant, a pop-up, a claude.ai page).

## 2026-09-29, Bench 0.1.11 (Settings in Solanum)

- ✅ **General and Specimens, redrawn to the Solanum design canvas.** Checked
  in `--demo settings` for both tabs in Ivory and Slate: mono section labels,
  hairline cards, a clay-tinted chip when on and a raised grey chip when off,
  the Ivory/Slate switch under the preview, the serif heading and wordmark.
  It builds with no warnings.
- ⚠️ A demo Settings window took keyboard focus while Sam was typing: the
  search field is focused when the tab opens. Don't open demo windows while
  Sam is typing.
- ✅ **Sam, on his installed 0.1.11:** "right now its lookin good".

## 2026-09-29, Bench 0.1.12 (Solanum icon, automatic Sign in)

- ✅ **Icon in Solanum's product family:** the fig tile, the mark's ring
  exactly, a flask at 9 units, one bubble escaped at (152, 9.93). The
  compiled .icns looks right at 256 px. Bench has been added to Solanum's
  icon table, its tile-fig token and its Logos.
- ✅ **Automatic Sign in, live:** Sam's Bench restarted into the 0.1.12
  install at 15:53:55. The first plan read was refused (401) at .900, Bench
  pressed Sign in at .912, and the plan read succeeded at 15:54:00. The page
  showed the projects and the toolbar the plan readout, with nothing to
  click.

## 2026-10-01, Bench 0.1.13 (Mac-native Settings, MIT)

- ✅ **Settings in the Mac's own controls**, at Sam's request ("more mac
  native, even if its not exactly our brand"), checked on screen with
  window captures of `--demo general`, `--demo specimens` and
  `--demo toolbar --open-options`, all `--quiet` and launched with
  `open -g -n`: the frontmost app stayed Sam's own throughout. General is a
  grouped form with every row and the Help section visible at 600 × 640;
  Specimens shows a checkbox per category, with counts, the segmented size
  and light/dark pickers, and the live grid; the toolbar options fit at
  400 pt.
- ⚠️ `--demo settings` (SwiftUI's own Settings window) still activates
  Bench even when quiet, through `openSettings`. Capture the pages with
  `--demo general` and `--demo specimens` instead.
- ✅ Builds with no warnings. `Solanum.swift` is gone; nothing used it.
- ✅ **Licence:** MIT, matching Nidus and the droplets repository the
  shared files come from.
- **Signing:** `build-app.sh` signs with "Solanum Code Signing" when the
  login keychain has it, else ad-hoc, as before. 0.1.13 went out ad-hoc.

## 2026-10-01, Bench 0.1.14 (signed with Solanum Code Signing)

- ✅ Sam made the "Solanum Code Signing" certificate in his login keychain
  (self-signed, code signing, 10 years). `build-app.sh` now signs with it:
  `codesign -d -r-` gives `identifier "local.sam.bench" and certificate root
  = H"1c84e9c2…"`, the same for two builds with different binaries, where
  ad-hoc gave a different `cdhash` every build. So the microphone and camera
  permissions Claude Science asks for should now survive updates: approve
  them once on 0.1.14, and they should hold on 0.1.15.
- ✅ The signed build runs (`--diagnose`), and `codesign -v` verifies it.

## 2026-10-02, Bench 0.1.15 (fixes from a code review)

A read-only review by Codex (findings kept outside the repo) found nine
issues; all nine held up when checked against the code, and all are fixed:

1. ✅ A session that failed mid-run vanished with no card: the engine now
   emits `.failed`, and the panel shows "Stopped with an error" with Open
   and Dismiss (`--demo failed`, captured on screen).
2. ✅ Cards counted down while queued, so a finish behind a question expired
   unseen: only the top card counts down now.
3. ✅ A line break in a session or project name split its database row and
   dropped the session: the query turns line breaks and the separator into
   spaces.
4. ✅ A failed read left the panel saying Working with a running clock: it
   now says "Not updating" with the time of the last good read
   (`--demo stale`, captured on screen).
5. ✅ A `status` reply without a `running` field counted as "not running",
   which could start a second daemon: only an explicit `"running": false`
   does now.
6. ✅ A waiting card kept its first reason (a question) when the session
   moved to plan approval: it updates in place, and a new kind of request
   returns after a dismissal.
7. ✅ A notification the page closed left its card behind: closes now remove
   it.
8. ✅ `install.sh` matched the app's path as a pattern over whole command
   lines (`pgrep -f`), so it could quit another copy: it compares the exact
   executable path now. Tested matching against the running Bench and a
   decoy path, and a full install into a scratch folder. Nidus's installer
   has the same fix.
9. ✅ A `bench://session` link that came before the daemon's port was known
   was built for port 8765 and dropped if the daemon used another: it moves
   to the real port.

`ScienceEngine.swift` is now Bench's own (`sync-shared.sh` keeps it). Not
yet checked live: a real failed session, and a real notification close.

## 2026-10-02, Bench 0.2.0 (activity list, Recent, separate settings, tests)

- ✅ **Tests:** `swift test` runs 18 tests in 5 suites, all made-up data
  (no daemon, no real database): the engine's transitions (failure, a new
  kind of request, a finish during a failed read), the card queue (a finish
  behind a question waits its turn; a waiting card updates; a dismissed
  request returns for a new kind; a failure stays until the session runs),
  stale reads, a page closing its notification, Recent keeping each event
  once, status parsing (only an explicit `running: false` means stopped),
  a two-line name in a real sqlite3 file, and a session link moving to the
  daemon's port.
- ✅ **Activity list:** captured on screen from `--demo toolbar
  --open-activity --quiet` (launched with `open -g -n`; the frontmost app
  stayed Sam's): Needs you with two waiting sessions and a failure, Working
  with two clocks, Recent below, scrolling.
- ✅ Builds with no warnings.
- Not yet checked live: the Dock menu, the new switches in Settings, the
  still specimen under Reduce Motion, and the activity list against real
  sessions.

## 2026-10-02, Bench 0.2.1 (the Dock menu always has something)

- ⚠️ Sam wasn't sure the Dock menu worked. It did: with `--demo toolbar
  --open-activity --quiet --log-dock-menu`, asking the app's delegate the way
  the Dock does returned all 11 items (the SwiftUI app delegate passes the
  request on). But on Sam's Mac nothing was working or waiting and Recent
  had just been emptied by the update, so Bench returned no menu, which looks
  broken.
- ✅ Now the menu says "Nothing working right now" when idle, and lists
  Latest (the five most recently active sessions) until Recent has
  something. 20 tests pass, two new: Latest's contents, and that the menu is
  never empty.
- Each Dock menu request logs its item count (`/usr/bin/log show --predicate
  'subsystem == "local.sam.bench" AND category == "app"'`; plain `log` is a
  zsh builtin).

## 2026-10-20, Capsid 0.9.3: thirteen specimens (541), phone follow-ups

0.9.2 was built and pushed but never published as a release; its changes
(next entry) ship in 0.9.3 with these.

- ✅ Installed from the release zip (`Bench.zip`, the same bytes to be
  published as v0.9.3), the way `install.sh` does it, since the release
  wasn't published yet: /Applications/Capsid.app is 0.9.3 (41), CDHash
  `494a7e3e…`, and running; phone access came back by itself.

**Thirteen specimens (541).** Kimwipe, Tally counter, Bench level,
Glassblowing, Eyewash station, Chloroplast movement, Neighbor exchange, Lumen
formation, Bone resorption, Proplatelets, Enucleation, Tunneling nanotube and
Centriole duplication: picked by Sam from a list of twenty, drawn by four
Sonnet agents in the specimen harness, six of them redrawn once after review
(a counter that read as a mug, an eyewash as a genie lamp, a chloroplast cell
as a domino, a bone pit as a jellyfish, an octagon as a stop sign, a
centriole as an upside-down T). Every loop closes (seam ≤ 0.0001), coverage
0.17–0.30 at 16 pt, under 0.1 ms a frame; notes checked against what's known
(Z358.1's 15-minute flush, phototropin avoidance, T1 transitions, pyrenocytes,
procentrioles). ✅ `LabScene`/notes tests pass; `Capsid --list-scenes` gives 541.

**Phone follow-ups** (DESIGN.md, Capsid on your phone).

- Cache budgets: 8 sessions and 1.5 M characters of session data, 4 files and
  768 K characters of text, least recently shown first; never the open screen,
  drafts or anything mid-read. History rows update by key.
- Reads stop with their screen: a scope per route aborts in-flight GETs and
  withdraws queued file reads when you leave or hide the page; writes and
  downloads are never aborted. The server hears a hang-up on read routes and
  cancels the work (the artifact read is aborted in the page by its nonce).
- The Dock menu's Latest refreshes on a rename, not only a new session.
- 36 JS and 7 Swift mutations caught; `embed-remote-web.py --check` passes.
- ⏳ Not seen: a real iPhone, and Tailscale Serve passing a phone's abort on.

Automated:

- ✅ `swift test`: **1,917 tests in 248 suites, all passing in one run**.

## 2026-10-20, Capsid 0.9.2: Codex's background-work, card and Settings changes; playback a second at a time

Codex's commit dc52caf (`codex/ui-performance-improvements`), reviewed here
and merged with two fixes (Sam approved all of it, the card redesign
included), plus the specimen player and database-watcher changes below. The
Codex commit carried Sam's personal address; it was re-committed under the
no-reply address and the branch deleted from GitHub.

**Playback a second at a time, and a quieter wait for the daemon** (droplet
commit c6d2713, synced; DESIGN.md, Efficiency).

- `PlayedGlyphView` draws and plays a second of frames at a time
  (`PlaybackPlan`, `ChunkedPlayback`: at most two chunks held, each its own
  keyframe animation on the rotation's clock, filling forward so no frame of
  the model shows between them). A restart draws only the chunk due now
  (about 6 ms, not a whole scene). `fps` is settable per view, default 30.
- Measured on a demo copy (screen locked, a test-only shim reporting the
  window visible): the footprint no longer swings (91–97 MB once settled,
  was 42–133 MB), the peak is about 30 MB lower, but the settled level is
  above the old average (77–82 MB); CPU the same within noise. What holds the
  ~57 MB of graphics memory is not known. Sam chose to keep it.
- `DatabaseWatcher`: while the log is missing it watches its folder and
  retries 2 s doubling to 60 s (about 64 looks an hour while the daemon is
  down, was 1,800), back to 2 s once it opens.
- 19 mutations: 15 failed a test, 3 crashed the test process, 1 survived (a
  defensive guard behind a race that can't be tested deterministically).
- ⏳ Not seen: playback on an unlocked screen after the change.
- ✅ `swift test` on the 0.9.2 branch (Codex's merge plus playback): **1,875 tests
  in 243 suites, all passing in one run**.

- Nidus task sharing has no heartbeat while disabled or unfocused. Identity
  changes coalesce, token-only updates do not rewrite the file, and a serial
  writer keeps disk work off the main actor. Generations prevent a late write
  from restoring context after sharing stops.
- Question, plan and error cards use a compact status header and the card's
  full 360 pt width. Questions/plans have three summary lines, errors two;
  existing actions remain, with a named accessibility Dismiss action.
- Removed phone thumbnails leave the intersection observer and withdraw
  queued thumbnail image loads and retries. Active transfers retain their slots
  until they finish, preserving the two-transfer limit. Embedded assets
  regenerated.
- Quick Open cancels obsolete database reads. SQLite deadlines include queue
  wait and retries; cancelled queued work never opens a connection. GETs have
  a 15-second page-side deadline, 8 MiB streamed limit and per-request abort.
  Context navigation cancels its previous read and rejects late generations.
- Settings keeps one width and caps its height to the owning screen. Compact
  Specimens has one scroll owner. Usage has its own accessibility label;
  Results removes empty search headings and offers a clear no-match state.
- ✅ Codex's own run: debug app/test build; 243 tests in 37 focused suites
  passed, including the new lifecycle tests and existing SQLite, Quick Open,
  plan/card and probe regressions. JavaScript syntax and generated-assets
  checks passed.
- ✅ Codex's temporary offscreen captures: compact Settings at 760 × 560 pt has
  one native scroll owner and reaches the last specimens. Action-card geometry
  checked in light/dark, including expanded plans and hover dismissal. Glass
  obscures offscreen bitmap captures, so card text/layout was also checked
  with a temporary plain-material copy. Capture helpers are not shipped.
- ✅ **A review here found no high-severity issue**, and two things to fix,
  both fixed in the merge (`SQLiteSource.swift`):
  - **M2.** A cancelled SQLite read dropped the shared connection before it
    checked for cancellation, so the search that replaced a cancelled Quick
    Open search opened the database again. A cancelled read now leaves the
    connection alone (any other failure still drops it). New test
    `aCancelledReadLeavesTheConnectionForTheNextRead` cancels a never-ending
    statement mid-run and expects the next read to reuse the connection
    (`openCount` stays 1). Mutation check: putting the `connection = nil` back
    before the cancellation check fails it on `openCount`.
  - **M3.** The change moved the reader from `queue.sync` to `queue.async`
    and a semaphore wait, so the caller's QoS no longer reached the reader's
    utility queue (a user-initiated search ran at utility). The block is now
    submitted with the caller's QoS and `.enforceQoS`. New test
    `aReadRunsAtItsCallersPriority` reads the QoS inside the block from the
    idle-close scheduler hook and expects user-initiated for a user-initiated
    caller. Mutation check: a plain `queue.async` runs at utility and fails
    it. The source file compared identical (`cmp`) after restoring.
- ✅ `swift test --jobs 2` on this Mac, with the merge and both fixes: 1,841
  tests in 238 suites, all passing (the review's 1,839 plus the two new
  ones; one run, two jobs, no stress loops). `Scripts/embed-remote-web.py
  --check` and `node --check RemoteWeb/app.js` pass; the embedded `app.js`
  hash (`5fb21ed6720d`) is the one in `RemoteWebApp.swift`.
- DESIGN.md had not been updated by the change; it now is (the card layouts
  and width, Settings sizing, the Nidus task file, `apiGET`, Quick Open and the
  SQLite reader, phone thumbnails, the Usage label, the Results empty state).
- ⏳ Live Liquid Glass appearance, display switching and an actual iPhone
  navigation session still need an interactive smoke check. No CPU or memory
  reduction was measured. Not released or installed.

## 2026-10-20, Capsid 0.9.1: the title bar shows the 5-hour limit

Sam: the usage in the title bar should be the 5-hour limit, not the week. It
showed whichever limit had the least left, so once the week had less left
than the 5-hour window, the week.

- Settings → Usage → Title bar shows: **5-hour limit** (the default now) or
  **Whichever is lowest** (as before). With the 5-hour limit, a limit under a
  fifth left (where its figure turns clay) with less left than the 5-hour
  window shows instead, so it can't run out unseen. No 5-hour limit in the
  answer: the lowest. One pure rule (`PlanUsageModel.shown`), 12 tests, 11
  mutations caught (two only after the tie test ran both orders).
- Only the toolbar label read `tightest`; notices, the usage pause and the
  phone judge each limit themselves and are unchanged.
- ✅ Quiet capture of Settings → Usage: the row and its ⓘ fit (page 316 pt).
- ✅ `swift test`: 1,804 tests in 229 suites, all passing.
- ✅ Released as v0.9.1 and installed with `install.sh`: 0.9.1 (39), CDHash
  `5943c674…`, the same as the download and the local build, and running;
  phone access back by itself. `titleBarUsage` unset, so the 5-hour default.

## 2026-10-20, Capsid 0.9.0: fifteen quality-of-life changes

Sam said "Do all" to the fifteen ideas in a brainstorm made from background
demo captures, a CPU sample of the installed app and the code. Six Sonnet
agents built them in waves of three (two build jobs each, no stress loops), on
their own branches, merged here. Made-up fixtures only; the live checks are
listed at the end.

- ✅ Released as v0.9.0 (`Bench.zip` with Capsid.app inside) and installed
  with the README's `install.sh` line, which quit the running copy:
  /Applications/Capsid.app is 0.9.0 (38), signed by Solanum Code Signing,
  CDHash `fa5d5c34…`, the same as the release's download and the local
  build, and running. Phone access came back by itself (loopback 47280,
  Serve's 8443 route).

**Efficiency** (DESIGN.md, Holding still; Efficiency).

- The installed 0.8.0 averaged 7.9% CPU (5.5–10.2%, 60 `top` samples) with a
  session working, footprint 114–257 MB. On a demo copy (no Claude Science
  page; the screen locked for most runs, so a test-only shim reported the
  panel visible) a Time Profiler pass put 58% of the playing cost in Core
  Animation converting each scene's sRGB frames for a Display P3 window. The
  panel is now an sRGB window: playing cost down 44% (2.12% to 1.18% in
  interleaved pairs), colours pixel-identical in captures.
- The specimen holds still after 10 minutes with no input (2 in Low Power
  Mode): 0.00% CPU and 23 MB flat while held. 14 tests, 11 mutations caught.
- ⏳ Not reproduced: the 7.9% itself. The demo has no web page, and the
  screen was locked. Re-measure on the installed app with a live screen.

**Visual polish.**

- `Theme.clayText` (#9C4221 / #E4927A) for words in clay, 15 sites; fills
  and tints stay clay (6.2:1 on ivory, was 3.0:1). `ClayTextTests` scan for
  words drawn in the fill.
- One time format (`TimeSpan`): "1h 28m" everywhere a span is written.
- Specimens tab: Categories under the controls, the light/dark switch under
  the preview. Pale grid tiles were live cells caught mid-fade; cells now
  draw their loop at full strength. Posters (the frame with the most ink,
  kept unless under 60% of the best) for stills under Reduce Motion: 21 of
  528 moved, 0.4 s for all, lazily.
- The card's Reply/Approve: `appearsActive` is already set; a capture can't
  show glass tint at all. ⏳ Look at a real card.

**Finding and resuming.**

- Quick Open searches the database by name and project for sessions beyond
  the 25 recent (bounded LIKE, 3–26 ms on a made-up 60,000-frame database),
  merged after the recent ones. 45 tests with the next item.
- Capsid reopens the session you had open, an opaque id pair in its own
  defaults, if the database still knows it; a `bench://` link at launch wins.
  A link arriving during sign-in is now parked instead of overwritten.
- ⏳ Not seen: the reopen after a real restart, and ⌘⇧O on a real database.

**Settings.**

- Settings → Alerts → While you present: the switch (not saved), a Focus
  row and Open Focus Settings… (`com.apple.Focus-Settings.extension`, read
  from the system's own extension).
- Descriptions cut to a line or two, the detail in an ⓘ popover; Alerts was
  already clipped at the bottom and now fits. Phone: Copy Link.
- ⏳ Not seen: the Focus-on wording, Copied, the Focus button opening.

**The activity list.**

- Needs you: longest wait first, Later underneath; the popover grows to the
  screen, with "N more" past that. Next Waiting Session (⌥⌘↓, File and Dock
  menus) cycles the asks. Hovering a row offers the card's own actions
  through one shared decision (`CardOffer`, `CardActions`). 21 mutations
  caught.
- ⏳ Not seen: ⌥⌘↓ with the page focused, live hover, a send from a row.

**Why it stopped.**

- The failure card shows the first line of `output_data.error` from the
  shallow frame read (the page's own source, from web-dist 0.1.67 and the
  daemon's strings), with Copy; behind the same setting as plans and
  questions on the card; never in notifications or on the phone. 37 + 3
  mutations caught.
- ⏳ Not seen: a real failure's text; the card's button row by capture (the
  screen was asleep).

Automated:

- ✅ `swift test`: **1,792 tests in 228 suites, all passing in one run** (202 more than 0.8.0).

## 2026-10-20, Capsid 0.8.0: quiet while presenting, drift checks, and four fixes

Five changes, each built by a Sonnet agent on its own branch and worktree,
reviewed and merged here. Made-up fixtures only; nothing below was tried in
the real app yet.

- ✅ Released as v0.8.0 (`Bench.zip` with Capsid.app inside) and installed
  with the README's `install.sh` line, which quit the running copy:
  /Applications/Capsid.app is 0.8.0 (37), signed by Solanum Code Signing,
  CDHash `7f4f2d51…`, the same as the release's download and the local
  build, and running. Phone access came back by itself (loopback 47280,
  Serve's 8443 route).

**Quiet while presenting** (DESIGN.md, Quiet while presenting).

- `PresentingMode` holds the two sources (a Focus filter, the menu switch);
  either makes Capsid quiet. 33 tests: the panel hides and comes back with
  what waited; finishes are held and come as one card worded "While you
  presented" (Nidus keeps "While you focused"; with both on, the hold lasts
  until the last ends); no chime, no Mac notification; timed cards don't run
  out unseen; demos start nothing. 22 mutations, all caught.
- The Focus filter (`QuietWhilePresentingFilter`, a `SetFocusFilterIntent`
  with one switch, default off, suggested on) needs App Intents metadata,
  which SwiftPM doesn't extract: `Scripts/appintents-metadata.sh`, ported
  from Nidus, runs in `build-app.sh` before signing. The release bundle's
  `Metadata.appintents` lists the filter.
- ⏳ Not seen: the filter in System Settings → Focus (a self-signed app may
  need to be in /Applications first), `perform()` running, the launch read
  of `current`. First thing to try: whether macOS launching Capsid to run the
  filter opens the main window over a presentation.

**Diagnostics notices Claude Science drift** (DESIGN.md, Diagnostics).

- `CompatInventory` lists everything Capsid depends on (page hooks, reads,
  writes, the command line, the database), and tests hold it to the code
  both ways, so a new dependency can't be added silently. It found a gap:
  Diagnostics checked 14 of the 18 `frames` columns the queries read.
- Diagnostics shows the Claude Science version against the one Capsid was
  last checked with (0.1.63), read-only probes of the page and the reads
  `apiGET` allows (never a write), and the last time a feature found
  something it expected missing. Two breadcrumbs were cut in review: a 401
  with no Sign in card is a designed branch, and a repeat within ten minutes
  isn't recorded again. 124 tests, 46 + 6 mutations, all caught.
- ⏳ Not seen: the probes against the real page.

**Notifications that outlived a quit** (DESIGN.md, Mac notifications).

- At the first read that worked and found sessions, delivered notifications
  are checked by the rule the running app uses (`SessionStanding.holds`):
  needs-input and error notifications whose reason has gone are taken back,
  the rest adopted; finishes stay. Nothing is sent. 29 tests through a fake
  `SystemCenter`; 22 mutations, all caught. The test waits on the check
  itself, not a sleep (10 runs in a row, and 10 under load).
- ⏳ Not seen: the live `SystemCenter` adapter (a thin pass-through, read in
  review).

**Time limits in Results** (DESIGN.md, Results).

- A read with no answer after 30 s frees its slot (it no longer pins one
  until the page answers), and its late answer is dropped. Saves run off the
  main actor with a limit of 15 s + 1 s per MiB; a folder that doesn't
  respond fails that save, and saves to it fail at once for 30 s (or until
  the stuck write returns) instead of queueing behind it. A late write never
  races another for a name. Seeded fuzzes (30 × 300, twice) and 9 mutations;
  one (dropping the planning-time name check alone) survives because the
  re-check catches it.
- `aDownloadThatLandedJustBeforeTheWindowClosedStartsNoWriteForTheDeadRun`
  was a race in the test, not the app: it now closes the window at a fixed
  point (1,500 of 1,500 under load, was 1 in 1,500 failing).
- Not fixed, documented: the existence check before a save still runs on the
  main actor.

**Three timing-sensitive suites made deterministic.**

- `LettingGoTests`, `RemoteServerLiveTests` and `RemotePhotoLiveTests` run
  on injected clocks (`SQLiteReader`'s `schedule:`, `RemoteServer`'s
  `sleep:`; defaults unchanged), plus one real-timer test each for the
  default wiring. In full runs under load these suites failed in 17 of 22
  runs before and in none of 34 after. 11 mutations, all caught.

Automated:

- ✅ `swift test`: **1,590 tests in 199 suites, all passing in one run** (214 more than 0.7.3).

## 2026-10-19, Capsid 0.7.3: phone setup sees a connected Tailscale; the task you're viewing, for Nidus

Two changes made in Codex chats, then reviewed here.

- ✅ Released as v0.7.3 (`Bench.zip` with Capsid.app inside) and installed
  with the README's `install.sh` line, which quit the running copy:
  /Applications/Capsid.app is 0.7.3 (36), signed by Solanum Code Signing,
  CDHash `3c83b493…`, the same as the release's download and the local
  build, and running. Phone access came back by itself: the new copy listens
  on loopback 47280 and Serve's 8443 route points at it.

**Phone setup detects connected Tailscale.**

- Fixed the real Tailscale runner to set `TAILSCALE_BE_CLI=1`. The macOS
  Tailscale executable otherwise chooses its GUI when Capsid is launched
  without a terminal environment, leaving Phone setup on Sign in even though
  Tailscale is connected. This is the override documented in
  https://tailscale.com/docs/reference/tailscale-cli?tab=macos.
- The new child-process regression (`TailscaleProcessRunnerTests`, which runs
  `/usr/bin/printenv`, never Tailscale) failed before the change and passed
  after it. `swift test --filter 'Tailscale|PhoneSetup|RemoteController'`
  passed 62 tests in 7 suites with `TAILSCALE_BE_CLI` unset in the test
  parent.
- ✅ Checked live on a local build (then still numbered 0.7.2): Phone setup
  completed its first five steps and showed the pairing QR code; Tailscale
  Serve contained only Capsid's HTTPS 8443 route to loopback 47280; the
  private HTTPS page returned 200 with title Capsid and a valid TLS
  certificate.
- ⏳ Pairing an iPhone: not done. A code read for Sam while he was away
  expired before he could use it, and the locked Mac couldn't show a new
  one. The page loading is not proof that pairing works.

**The task you're viewing, for Nidus** (DESIGN.md, The task you're viewing,
for Nidus). Off by default; Settings → General → Nidus.

- `NidusTaskSelection` tests: only an exact project/frame route on the
  daemon, with a matching session row, names a task; an overview, another
  project's route or another site doesn't; empty names publish nothing and
  long ones are cut to 240 characters with no newline.
- Fixed in review: a `--demo` copy's quit, or its Settings switch, deleted
  the running Capsid's file (`clear()` ran in any copy). Now only the copy
  that started publishing refreshes or removes it.
- ✅ Fixed in review: the new section pushed Help → Diagnostics below the
  General page's bottom edge (a quiet `--demo general` capture showed it cut
  off at 580). The page is now 634, and the capture shows every row with even
  margins.
- ⏳ Nidus showing the name live: not tried. Nidus's reader is uncommitted
  in its own checkout, and live testing stopped at Sam's request.

Automated, made-up fixtures only:

- ✅ `swift test`: **1,376 tests in 176 suites, all passing in one run**
  (3 more than 0.7.2: the Tailscale child process and two Nidus selection
  tests).

## 2026-10-17, Capsid 0.7.2: a review of 0.7.1, Close Other Tabs, nine specimens

0.7.1 was pushed but never released; 0.7.2 is the next release after 0.7.0.

- ✅ Released as v0.7.2 (`Bench.zip` with Capsid.app inside) and installed
  with the README's `install.sh` line, which quit the running copy:
  /Applications/Capsid.app is 0.7.2 (35), signed by Solanum Code Signing,
  CDHash `484fada9…`, the same as the release's download and the local
  build, and running.
It carries 0.7.1's six performance fixes, the fixes from a review of them,
Close Other Tabs and Close All Tabs (next entry), and nine new specimens.

**The review.** A Sonnet agent reviewed commit ba4103a in an isolated
checkout, with probe tests, a seeded fuzz of the transfer queue (80 seeds ×
3,000 steps: no double or missing resume, never more than two reads, every
table empty at rest) and of the shelf's lifecycle (40 × 600), and the real
reader script in Node against a slow local server. Nothing high. Fixed:

- **Medium: a permission request handled elsewhere lost its explanation.**
  `prune` released a `.closed` reply at once while its card was still up, so
  the card went back to Allow and Deny with no word of why. A reply is now
  also kept while its card is up (DESIGN.md, What is kept). This also
  corrects 0.7.1's TESTING line "no assertion removed": two card assertions
  were inverted then, and this one was wrong.
- **Low: a stale Save All cleared a new one's progress.** Saving spinners are
  counted per holder and a run releases only what it marked; a run the window
  closed on before it started does nothing.
- **Low: a cached copy handed out after close.** Re-checked after the
  existence check's await.
- **Documented, not fixed:** a reader that never returns pins its slot; one
  serial writer for saved files has no time limit (DESIGN.md, Results).

Automated, made-up fixtures only:

- ✅ `swift test`: **1,373 tests in 174 suites, all passing in one run**.
  New since 0.7.1: `PageTabsTests` and `TabContextMenuTests` (56, next
  entry), `ShelfCloseAndReopenTests` and one more transfer test (7: the
  review's Save All scenario asserted on the whole `$batches`/`$saving`
  trail; a Save and a Save All on one file; a Save All closed before it
  started; a copy not handed over while its existence is checked; a
  download that landed just before close starting no write; a closed
  window's asker not ending the next window's spinner; a closed run's copy
  write not joined by the new window; a timed-out read not joined by the
  next asker), and the handled-elsewhere card test rewritten as above.
- ✅ Mutation checks, each reverted: the card rule (`.sent`/`.closed` kept
  while the card is up) and, from the fix agent, ten guards in the shelf and
  the queue (`timedOut`'s `live` reset, `endPreparing`'s generation check,
  `close()`'s `copyWrites` reset, `temporaryCopy`'s post-fetch and
  post-existence checks, `saveAll`'s registration check, `runSaveAll`'s top
  guard and marked-only release, the stale tail's batch reset, the counted
  spinner) were each caught.
- ✅ **Nine specimens (528)**, drawn by three Sonnet agents in the specimen
  harness (one fix round for four of them), registered with
  `add-specimens.py`: Epithelial extrusion, Myelin wrapping, Membrane
  repair, Lipid flip (cell); Laser capture, Crystal fishing, Paraffin
  embedding (bench); Ring-opening polymerization (chemistry); Archimedes
  screw (physics). Every one has 16 pt coverage 0.107–0.275, under 0.1 ms
  a frame, and a seam of 0.0003 or less. The droplet's `LabSceneOrderTests`
  and `LabScenesTests` pass (droplet commit ac14c34, local). `Capsid
  --list-scenes` lists 528. Preview: ~/Documents/Default
  Project/new-specimens-batch-P.gif.
- ✅ `swift build -c release --product Capsid`, phone assets in sync,
  `node --check`, `git diff --check`: clean.

Not checked live: the card keeping "It was already handled." with Open;
Save All after a quick reopen; the nine specimens in the panel and the
menu bar.

## 2026-10-17, after 0.7.1: Close Other Tabs / Close All Tabs (released in 0.7.2)

File → Close Other Tabs (⌥⌘W) and Close All Tabs, and the same three items in the
right-click menu of a tab in Claude Science's right-hand panel (DESIGN.md, Main window).
Built from the 0.1.63 web bundle's source, not from a running page. 56 new tests
(`PageTabsTests`, `TabContextMenuTests`, with `FakeTabDOM`), none of which loads a web
view, reaches the daemon or reads a real page.

- ✅ **The decision** (`benchTabsToClose`, run alone in JavaScriptCore): Others keeps the
  given id, first, last, middle or only; with no id it keeps the one shown tab, and
  refuses when none or two are shown; All closes every tab; an unknown kept id, another
  mode and a kept id that isn't a string close nothing; an empty strip has nothing to
  close; a repeated id is closed once.
- ✅ **The page script**, against a fake strip built in the test (`querySelector`,
  `querySelectorAll`, `closest`, `dataset`, `getAttribute`, `click`):
  - presses only `button[data-tab-close]` inside the strip's toolbar, never the same ids
    or buttons outside it, a block beside the toolbar, an "overflow" button or a "Close
    Files" button; ids with quotes and brackets are never put into selectors;
  - keeps the right tab, reads the strip again after every press (a fake page that makes
    new elements on every render), and waits for a tab that leaves a little later;
  - a tab that is still there (a pending question, or one that takes over 300 ms) stays,
    and the sweep stops there: it is counted with every tab not reached;
  - presses nothing, and says so, with no strip, no toolbar, two strips, or a tab to close
    without a close button (not even the earlier tabs' buttons); a tab to keep needs none;
  - refuses a kept tab that isn't in the strip, and Others with no shown tab.
  - The mutation check: with the script changed to look document-wide, to continue past a
    tab that stayed, to reuse the first read, or to skip the close-button check, the
    matching tests fail.
- ✅ **The answer** is checked again in Swift (negative, fractional, boolean, huge and
  missing counts are refused); one sweep at a time (a second request while one runs is
  dropped); the menu commands are on only for the main window with a ready page
  (`PageTabCommands.canClose`, and following the window and the page).
- ✅ **The right-click target**: the message is read (a non-empty string, at most 512 bytes,
  else no tab), heard only from the main web view's main frame on the daemon's origin, a tab
  is fresh for one second and taken once, a stale, missing or `null` tab adds no items, and
  the user script (in JavaScriptCore, with a fake handler) posts the tab for a click on a tab
  button, its other buttons or text in it, `null` anywhere else, nothing for a made-up event,
  and installs nothing off the daemon's page or without its handler.
- ✅ **The items** in an `NSMenu`: Close Tab, Close Other Tabs, Close All Tabs and a
  separator at the top, once only, each running its own request relative to the tab.
- ⏳ **Not verified; needs Sam, in the running app:**
  - **The real page and its markup.** Everything above is the 0.1.63 source read as text. The
    first real check is a session with three artifacts open: Close Other Tabs (⌥⌘W) on the
    middle one, then Close All Tabs.
  - **The discard question.** The bundle shows it is the page's own dialog, shown after the
    press and answered later, not a `confirm` (DESIGN.md says what that means for the sweep).
    Try it with a tab holding unsaved edits: the tab and those after it should stay, and the
    page should ask. Also, whether the strip really leaves the page with its last tab.
  - **The right-click menu in the app**: that the items show, at the top, for a tab and not
    for anything else, and what Close Other Tabs shows afterwards (the page picks the tab it
    shows when the shown one isn't the one kept).
  - **The order of the script message and the menu** (`willOpenMenu`). Reasoned from WebKit's
    single connection, not observed; a miss means no extra items, never the wrong tab.
  - **⌥⌘W in the app**, with the web view the first responder. The one clash that can't be
    ruled out from the repo: a standard File menu has Close (⌘W) with a hidden Option
    alternate, Close All (⌥⌘W), and SwiftUI's generated menu most likely carries it. These
    items sit in the group with Open Session… and Results…, above Close, so AppKit should
    reach them first while they are enabled, and fall through to Close All while they are
    dim. Where they sit against Close is also unseen.
  - The enabled state in the real menus, with a Browser window, Settings or Quick Open in front.

## 2026-10-17, Capsid 0.7.1: six performance fixes from a review

A review of 0.7.0 (Codex, with five probes on an isolated copy) found six
resource-lifecycle problems; all six are fixed here. Fixes 1, 2 and 4 were
built by an Opus agent and fix 6 by a Sonnet agent, each in a scratch copy of
`1e769b1`, then merged by hand (the thumbnail store's few lines applied onto
the rewritten shelf) and read through; fixes 3 and 5 were made here. DESIGN.md:
Results → Transfers, Cancellation, Disk, Thumbnails; Answering from the card →
From a Mac notification, What is kept.

1. **One limit for every Results read** (`ShelfTransfers`): lists,
   thumbnails, Quick Look, drag, Copy, Save and Save All share two slots;
   the same read is shared; what you asked for goes first, with promotion
   after eight starts; Quick Look withdraws the file it leaves.
2. **Cancellation that reaches the page**: each consumer withdraws alone; an
   unwanted read is cancelled and the page's fetch aborted by its nonce
   (`benchAbortRead`); a slot is held until the reader really returns;
   timers are owned and released; late answers land nowhere.
3. **Replies let go**: a reply is owned by its open window, a send, or a
   draft for a session still waiting; finished replies from the card's
   buttons or notifications, and what was read for a card that is gone, are
   released; a notification answer gets its own result.
4. **Disk off the main actor**: temporary copies and saved files go through
   actors, with a run identity so cleanup and late writes can't cross; launch
   cleanup runs off the main actor and before the first copy.
5. **Notification deadlines**: four seconds on every path (an injected
   clock); the card's shared read is never cancelled for it; the loser is
   cancelled; a notification waits for its own answer alone.
6. **Thumbnails**: decoded once with ImageIO off the main actor at 144 px at
   most, refused over 4096 × 4096 from the header, kept within 16 MiB by cost
   with LRU eviction, let go on close, and drawn by a view that watches only
   the thumbnail store.

Automated, with made-up fixtures, scratch folders and private pasteboards
only:

- ✅ `swift test`: **1,309 tests in 171 suites, all passing in one run**
  (was 1,234 in 163 at 0.7.0). Also `swift test --skip
  "LettingGoTests|RemoteServerLiveTests|RemotePhotoLiveTests"` (1,302 in
  168) and those three alone (7 in 3), as they are real-time and failed by
  turns earlier today under a load average up to 300. `--disable-sandbox`
  was not needed anywhere. New:
  - `ShelfTransfersTests` and its sibling suites (37): never more than two
    reads, foreground first, then Save All, lists, thumbnails; promotion;
    one read per version with every asker answered; a queued asker
    cancelled never starts; one of two askers cancelled keeps the read; the
    last cancelled cancels the reader and its slot is held until it returns;
    a timeout answers at once and holds the slot; cancellation before the
    start, after the end and at the timeout boundary; timers let go; close
    lets everyone go but a Save; not ready uses no slot; a mixed load with
    two Save All batches stays within two, across close and reopen; a late
    answer writes no copy; moving through Quick Look downloads only the last
    file, and leaving a file stops it unless a drop still wants it; a
    blocked disk write leaves the main actor free (copies and saved files
    run off the main thread); closing during a write leaves no copy and no
    folder; quick reopening keeps only the open run's copy, 0700/0600;
    write and read failures; launch cleanup goes first and keeps the new
    copy; the abort script in JavaScriptCore (with and without
    `AbortSignal.any`): an abort mid-fetch or mid-body is `cancelled` and
    removes its entry, other reads go on, an unknown nonce is a no-op, the
    deadline is still `unreadable`, and no nonce (the phone) files nothing.
  - `ShelfThumbnailsTests` (14) and five more in `ResultsShelfTests`: the
    budget and LRU eviction, a peek isn't a use, replacement accounting, a
    picture over the budget refused, a 16,384 × 16,384 PNG and 4097 × 4096
    refused from the header (4096 × 4096 decoded), 4000 × 3000 kept at
    144 × 108, EXIF orientation, a tiny image not enlarged, the same image
    decoded once in 50 asks, a decode after `removeAll()` keeping nothing;
    closing lets the pictures go; unrelated shelf updates (Save All
    progress, another session's list, Refresh) cause no decode, no read and
    no change from the store.
  - `ReplyLifetimeTests` (16): 300 direct approvals and 300 notification
    answers leave nothing kept; a direct approval is let go before its
    session ends; plan changes are let go when their window closes; a draft
    closed before the session ends is kept, then let go; Later and the card
    coming back keep the draft; a window closed while sending keeps the
    send, then lets go; an open window keeps its status; a failed or changed
    request stays while its session waits; what was read for a card goes
    with it; a stalled card read reaches the limit while the card still gets
    it later; a fast read cancels its timer; the limit cancels a private
    read and a late one changes nothing; a cancelled caller returns at once;
    the limit and the read racing answer once (100 times); an unrelated
    stalled session doesn't hold a notification answer.
  - Updated, with no assertion removed: the card tests whose replies are
    shown in a window now open one (`windowOpened`); those answered from the
    card's own buttons now assert that nothing is kept; the shelf tests read
    through the transfers and the actor-backed disk.
- ✅ Mutation checks, each reverted: no `prune` after a send, the limit
  cancelling the card's shared read, and the deadline not cancelling its
  loser were each caught (`ReplyLifetimeTests`). After the merge, freeing a
  slot when its last waiter leaves (14 failures in the transfer suites) and
  keeping the decoded thumbnails on close (4) were caught too. In their own
  copies the agents also caught dropping the removed-run check and letting
  the thumbnail "already known" check pass.
- ✅ `swift build -c release --product Capsid`: complete, no warnings.
- ✅ `python3 Scripts/embed-remote-web.py --check` (phone assets unchanged and
  in sync), `node --check` on RemoteWeb/app.js and sw.js, and `git diff
  --check`: clean.

Not measured: no CPU, energy, memory, latency or main-thread-stall figure
was taken, so none is claimed. Profiling a build on synthetic data isn't
possible as things stand: Results is off in demo mode, so it would need new
demo plumbing first. Left pending: idle with Results closed, repeated
open/close, rapid Quick Look navigation, a large shelf of thumbnails, Save
All to a slow folder, and repeated direct replies.

Not checked live (nothing was installed or launched):

- the abort reaching a real WKWebView fetch, `.defaultClient` keeping
  `benchArtifactReads` from the page, and WebKit's `AbortSignal.any`;
- Quick Look moving between files in the app, and the panel's begin/end;
- thumbnails drawn by `ShelfThumbnailView` (`Image(decorative:)`), and rows
  asking again after a reopen (`onChange(of: takenAt)`);
- launch cleanup at a real launch;
- the reply window's open/close reaching `windowOpened`/`windowClosed`, and
  a notification answer that fails opening its window.

## 2026-10-17, Capsid 0.7.0: more from the card, and the shelf's Quick Look, drag, copy and Save All

Built on the 2026-10-16 entry (DESIGN.md, Lab → Answering from the card;
Results). Sending results to Plaque is still held back.

- ✅ Released as v0.7.0 (`Bench.zip` with Capsid.app inside) and installed
  with the README's `install.sh` line: /Applications/Capsid.app is 0.7.0
  (33), signed by Solanum Code Signing, CDHash `47a787c6…`, the same as the
  release's download and the local build, and running.

- **More from the card.**
  - Every needs-input card but a plan's reads its session once, in full
    (the frame, its last turns and the head of its permission requests),
    so the card can show a permission request, and the window what Claude
    said last.
  - The reply window: ⌘1–⌘9 choose, ⌘↩ sends, Esc closes; once sent with
    more waiting, Next steps to the next session.
  - Permission requests on the card, under the phone's own table said for
    the Mac: Allow Once for a read-only tool, Review (the code in the
    window) for code, Deny where a no is plain, Open for the rest. From the
    daemon's code: an allow without a scope records no grant, so it is once.
  - Request changes… on a plan's card: what to change, sent as a message
    with no `plan_mode` after a fresh check of the plan's version. From the
    daemon's code: a message to a waiting plan is a change request, and the
    plan stays unapproved until Approve. The phone's own message to a
    waiting plan is still refused.
  - A question's Mac notification offers its answers (one question, one
    answer, four choices at most, names shown), checked as the window's.
  - The Finished card has **Results**, which opens the shelf on that
    session. It shows no count of files: nothing is read when a session
    finishes.
- **The results shelf, more** (built by a sub-agent in a scratch copy, then
  merged and read through here):
  - Preview is now the real Quick Look panel (Space, arrow keys between
    files) on a private temporary copy, replacing the in-memory preview.
  - Drag a file out (fetched only on the drop), Copy (image, text, PDF),
    and Save All… of a session, with the last folder remembered per project.
  - Temporary copies are 0700/0600, in the user's temporary folder, deleted
    when the window closes and at launch.

Automated, with made-up fixtures only:

- ✅ `swift test`: 1,234 tests in 163 suites (was 1,146 in 151). In full runs
  today three real-time suites failed by turns (`LettingGoTests`,
  `RemoteServerLiveTests`' 120-requests-in-half-a-second budget test,
  `RemotePhotoLiveTests`) while the Mac's load average was 15–93 (Codex in
  ChatGPT, media analysis, Spotlight). Every other test passed in one run
  (1,227 in 160 suites); the three passed on their own at lower load, and the
  budget test failed the same way on a copy without any of today's changes.
  New:
  - `CardRepliesTests` and friends (33):
    - the plan-change write: exactly a message with no `plan_mode`, and
      refused out of shape; the request's checks (trim, 4,000, references,
      version, a lower-case uuid v4);
    - `RemoteDecide.planFeedback`: only the version shown, only while it
      waits and isn't approved, a project needed; the daemon's replies;
    - through `RemoteSessions`: the Mac's plan change written with phone
      actions off, and the phone's own message to a waiting plan still
      refused, with no new phone route;
    - the Mac's permission table equal to the phone's for every kind and
      shape, every sentence said for the Mac, none mentioning a phone;
    - the card's read: a request at the head of the queue, the root's own
      question first, every wait but a plan's read, what Claude said last;
    - the window's keys (`ReplyKeys`);
    - the replier: a read-only tool allowed once from the card and the card
      gone, one send per press; what the table doesn't offer never sent; a
      changed request shown instead; handled elsewhere closed; a failure
      saying try again and a refusal saying why for the Mac; a request that
      stops waiting; what Claude said carried;
    - plan changes: not read for the card but sent from it; the same words
      keeping their intent id across a retry, new words a new one; a plan
      that changed or stopped waiting sending no more, the words kept; a
      reference never sent;
    - Next: the other cards but a plan's, in order; a card not on top read
      when the window steps to it;
    - a notification's answer sent through the same check, and one before
      the page is up kept for the window;
    - `NotificationAnswerTests`: which questions get answers (one question,
      one answer, at most four choices, names shown), the notification
      saying the question, its copy of the answers checked again on the way
      back, and buttons and Reply… making the window's answer (not past
      1,000 characters, not blank).
  - The shelf (56 new, the in-memory preview's test removed):
    - `ResultsShelfTests`: Quick Look's copy (one per version and reused,
      the folder layout and 0700/0600, same-named files apart, an awkward
      name made safe); over-cap files never downloaded; each failure's
      sentence on the row; a second press while loading doing nothing;
      close deleting the copies and writing nothing mid-download; launch
      cleanup; drag (nothing read until the drop, through a real
      `NSItemProvider` load, sharing Quick Look's copy, two drops fetching
      once, over-cap carrying nothing, the content type from the extension);
      the panel's file list; browsing making no temporary folder.
    - `ShelfCopyTests` (7): the pure decision by kind and bytes (UTF-8, a
      byte-order mark, PDF, image, kinds not offered); Copy through the
      shelf; the write into a private named pasteboard.
    - `ShelfSaveAllTests` (14): names against the folder and within the
      batch, without case; two at a time with the progress line moving;
      over-cap skipped; failures counted, never named; one batch at a time;
      each file recorded with no Saved card; closing leaving no partial
      files (on a real folder); the folder remembered per project by id,
      across shelves, forgotten when gone, and not after a failed save.
    - `ShelfFocusTests` (7): the session listed, opened and read; found by
      taking the snapshot again; put at the top; an older one; a stale list
      read again; the page not up; close clearing it.
    - `ShelfFileNameTests` (3) and `ShelfTemporaryCopiesTests` (8).
- ✅ Mutation checks, each reverted: the Mac's table allowing everything
  (73 failures), `plan_mode: false` in a plan change, no version check
  before a plan change, and the replier skipping the table: each caught.
  In the shelf, dropping the 8 MB check on a listing's size (12 failures)
  or on the bytes (19) was caught. Dropping Save All's own "window closed"
  check before a write was not: a closed window cancels the batch's reads,
  which then come back as nothing, so no write follows either way. The
  check stays as a second guard, untested on its own.
- ✅ Off-screen renders (made-up data, no window on screen): the reply
  window as a question with what Claude said and its keys, a permission
  request with its code, sent with Next, and a plan change, light and dark;
  the shelf with Save All's row and summary (it draws only inside a window
  that is never shown). The card's Liquid Glass doesn't draw off-screen.

Not checked live (Capsid wasn't launched, and nothing reached a real page or
daemon). Check the first two of each first:

- a plan change reaching Claude Science and the plan coming back revised
  and waiting (the daemon's code says so; not seen) — try it in Example
  project;
- Allow Once and Deny reaching a real request, and Review's code box;
- a question's notification with its buttons and Reply…, from Notification
  Center and the lock screen, and a launch from one;
- the window's keys (⌘1–⌘9, ⌘↩, Esc) and Next in the app;
- the card's new lines and buttons (Request changes…, the permission rows,
  Finished's Results) at the panel's width;
- `.onDrag` inside the list (it may fight the list's own row drag), and the
  dropped file's name and extension in Finder;
- Space opening Quick Look from a file row inside its session's disclosure,
  the arrow keys moving between files, HTML and SVG without scripts;
- Copy's results pasted in other apps; the open and save panels starting in
  the remembered folder; "Saving 3 of 7…" and Reveal in Finder; the window
  scrolling to the focused session;
- the temporary folder's permissions and its cleanup on a real launch.

## 2026-10-16, after 0.6.0: answering from the card, and the results shelf (released in 0.7.0)

Two features, built on what Capsid on your phone already had (DESIGN.md,
Lab → Answering from the card; Results). Sending results to
Plaque was held back for now.

- **A question answered from its card.**
  - The card shows the question and how it's answered, with Reply, Open
    and Later.
  - Reply opens a small window beside the panel, never on its own.
  - Answers go through `RemoteSessions.respond`, the actions' own core
    beneath the phone's gates. It reads the session afresh and checks the
    question is still the one shown, so the Mac's answers work with
    Capsid on your phone off.
  - The answer is built by the phone's rule and checked by
    `RemoteActionRequest.checkedAnswer`, the check `parse` now shares.
- **The results shelf.**
  - Opened from File → Results… (⇧⌘R) or the toolbar's tray.
  - It reads through the page's artifact reader with the phone's own size
    and kind checks (`ArtifactGate`, now shared with the phone's routes).
  - Recent sessions are taken when it opens, with the 8 newest read then.
    Older sessions come from a new database page query
    (`fetchRecentSessions`), on request.
  - Reads go two at a time, within a time limit, and stop when the window
    closes.
  - Previews stay in memory, and only Save writes a file.
  - The artifact reader now tells a 404/410 (`missing`) apart from other
    failures; the phone's routes still answer it 503.

Automated, with made-up fixtures only:

- ✅ `swift test`: 1,146 tests in 151 suites, all passing. New:
  - `QuestionAnswersTests`:
    - the answer rule for one choice, Other replacing the choice, several
      in the options' order plus typed text, several but only typed, and a
      question with no choices;
    - completeness and the 1,000-character cap;
    - that `checkedAnswer` refuses what `parse` refuses.
  - `QuestionCardStateTests`: which requests the card answers (the root's
    own waiting question only), and what the card says of it.
  - `QuestionReplierTests`:
    - one read per card, with the setting off or for a plan reading
      nothing;
    - unsupported requests, and a failed read tried again after 15 s;
    - the destination shown;
    - an unfinished answer sending nothing;
    - one send per press, with the card going once sent;
    - a new question replacing the draft, and the same request keeping it;
    - answered elsewhere;
    - a re-read that fails after "changed" claiming nothing, keeping the
      draft and Send;
    - a failure keeping the draft, and Send trying again;
    - the session stopping waiting;
    - the draft kept when the window closes, and after Later.
  - `NativeReplyCoreTests`, through `RemoteSessions` itself:
    - with phone actions off, the phone's route answers 403 while the
      Mac's reply is written;
    - the request is read again just before sending, so a replaced or
      resolved question writes nothing;
    - the replier end to end with the phone off;
    - a Mac and a phone answer at once take turns, and only one is written.
  - `ResultsShelfTests`:
    - coverage, grouping and the coverage sentence;
    - two reads at a time;
    - not connected;
    - reopening keeping fresh results, and Refresh;
    - each failure's state, and Try Again;
    - a malformed list (the reader's own check) unreadable;
    - a read that never answers running out of time, with the late answer
      ignored;
    - closing stopping reads, with late answers landing nowhere;
    - older sessions a page at a time, only when asked, with a failed page
      retried from where it failed;
    - a page's cursor and each session's link;
    - Open Conversation;
    - thumbnails only for images, only WebP, and once;
    - each kind's preview, or why not, with never a read for HTML, SVG,
      notebooks or a PDF over 8 MB;
    - Save writing only where chosen, keeping to the caps, and reporting a
      failed write;
    - a second Save while one runs doing nothing;
    - a failed thumbnail tried again when the window opens again;
    - a moved saved copy forgotten;
    - browsing never writing to the disk.
  - `ShelfDisclosureTests`: a session opened to load stays open when its
    results arrive. A review caught it snapping shut; the rule is now a
    value with tests. Rows read with results are open until closed by hand,
    and a search opens them all.
  - `BrowseSQLTests.recentSessionsSpanProjectsAndPage`: the new query
    across projects, with sub-agents, sessions without a summary and
    archived projects left out, the cursor, and a bad cursor reading
    nothing.
  - `RemoteArtifactsTests`:
    - a 404 or 410 is `missing` for every read (and a list's), not
      `unreadable`;
    - the phone's text route still answers it 503;
    - the other statuses are still unreadable.
- ✅ Mutation checks, each reverted:
  - letting the shelf read eight at a time fails `readsGoTwoAtATime`;
  - dropping its closed-window check fails
    `closingStopsTheReadsAndLateAnswersLandNowhere`.
- ✅ Off-screen renders (made-up data, no window on screen) of the reply
  window, light and dark, editing and failed, and the shelf, light and dark,
  with each kind of session state. The floating card's Liquid Glass doesn't
  draw off-screen, so the card was not seen.

Not checked live (Capsid wasn't launched, and nothing reached a real page or
daemon):

- the question card and the reply window in the app: the window's
  placement beside the panel, its keyboard focus, and that the panel still
  never takes the keyboard (`--demo card` shows the card with a made-up
  question);
- a real answer reaching Claude Science through the reply window;
- the results shelf against real sessions and files: the reads, thumbnails,
  previews (PDFKit, markdown), Save, Open and Reveal in Finder, the menu item
  and the toolbar button.

## 2026-10-15, Capsid 0.6.0 (Bench is renamed Capsid)

Bench is now Capsid (DESIGN.md, Naming). Every name a person reads changed,
and so did the binary and the app bundle. The bundle id, the data folder, the
phone's cookie, header, routes and storage keys, the code's own names, the
GitHub repository, `install.sh`'s address and the release file `Bench.zip`
kept the old name, so settings, paired phones and the update from Bench carry
over.

- `Package.swift` gains a product, `Capsid`, built from the unchanged `Bench`
  target, and `Scripts/build-app.sh` builds it into `build/Capsid.app`.
  Info.plist: CFBundleName, CFBundleDisplayName and CFBundleExecutable are
  Capsid; version 0.6.0 (32).
- The menus, window titles, Settings, the welcome, alerts, the update card and
  sentences, notifications, accessibility labels, help text, the diagnostics
  report, the demo's output and the phone app (its title, Home Screen name and
  every sentence) say Capsid. `RemoteWebApp.swift` was regenerated.
- `install.sh` installs /Applications/Capsid.app. It quits a running Bench or
  Capsid there, and removes /Applications/Bench.app once Capsid is in place.
  A zip that still holds Bench.app (every release before 0.6.0) installs as
  before. `UpdateRules.installDirectory` is /Applications/Capsid.app, and the
  update check's User-Agent is `Capsid/<version>`.
- A new icon, in Solanum's one-colour colourway (DESIGN.md, Resources):
  - **Design:** a Clay tile with, in Slate, the Solanum ring and escaped dot,
    kept pixel for pixel from Bench's glyph, round an icosahedral capsid.
  - **Phone:** its Home Screen icon is drawn from the same glyph on the same
    Clay (`RemoteIcon.clay`).
  - **README:** `docs/icon.png` is the new icon.
  - **Previewed** at 512, 128, 64 and 32 px; the capsid stays readable at
    32.

Automated, with made-up fixtures only:

- ✅ `swift build`, and `swift build --product Capsid`, whose binary is named
  Capsid.
- ✅ `swift test`: 1,094 tests in 145 suites, all passing, `LettingGoTests`'
  timing test included. Expected strings that mirror renamed ones were
  updated: the update card, the install sentence, the User-Agent and the
  `canInstall` paths (`UpdateCheckTests`); "Actions are off in Capsid's
  Settings", "Capsid can't read this session" and "The code has characters
  Capsid can't show safely" (`RemoteActionsTests`, `RemotePermissionsTests`,
  `RemotePermissionsFlowTests`, `RemotePhotosFlowTests`, `RemotePhase2Tests`,
  and the served session in `PhonePauseTests`); and Settings → Phone's
  sentences when the switch can't serve (`PhoneSetupTests`).
- ✅ `node --check RemoteWeb/app.js` and `RemoteWeb/sw.js`.
  `Scripts/embed-remote-web.py` regenerated `RemoteWebApp.swift`, with its own
  node check of the stripped JS, and `--check` passes.
- ✅ `Scripts/build-app.sh`: `build/Capsid.app` has CFBundleName Capsid, the
  executable `Contents/MacOS/Capsid`, bundle id `local.sam.bench`, 0.6.0 (32),
  and is signed with Solanum Code Signing; `codesign --verify --strict`
  passes.
- ✅ `zsh -n install.sh`, and its process match run on made-up `ps` lines: only
  /Applications/Bench.app/Contents/MacOS/Bench and
  /Applications/Capsid.app/Contents/MacOS/Capsid are picked, never a copy
  elsewhere. The script itself wasn't run.

Released and installed, in this order:

- ✅ The new `install.sh` reached `main` (and raw.githubusercontent.com) before
  the v0.6.0 release, whose `Bench.zip` holds Capsid.app at its top level.
- ✅ `install.sh` from GitHub, run end to end into a scratch folder
  (`BENCH_INSTALL_DIR`, so nothing in /Applications was touched or opened),
  with a stand-in Bench.app there. It downloaded the live release, installed
  Capsid 0.6.0, and removed the stand-in. The CDHash is the build's.
- ✅ On Sam's Mac:
  - Bench 0.5.3 was quit, Capsid.app was put in /Applications, Bench.app was
    removed, and Capsid was opened in the background.
  - It runs as `Capsid` with the same CDHash as the release.
  - The phone switch carried over: "Remote listening on loopback port
    47280", with the paired devices in the unchanged data folder.
  - The first plan-usage read got a 401 while the page was still signing in.
    The next, 4.6 s later, worked.

Not checked live:

- Bench 0.5.3's own updater taking this release: the update card's Install
  Update. install.sh is what it runs, and that is checked above.
- macOS keeping its permissions (microphone, notifications) across the
  rename, and a Dock icon pinned to Bench.app.
- A phone paired as Bench after the update: still paired, and its Home
  Screen icon still named Bench. Tailscale was off on the Mac.

## 2026-10-15, Bench 0.5.3 (the usage pause, per session; review fixes)

A source review of 98f54a2 found four problems in the 0.5.2 pause. Each was
checked against the code first, then fixed:

1. A used-up Opus or Sonnet week paused every working session, whatever its
   model. Bench has no model per session (it is chosen per message, in a body
   Bench never reads). Claude Science's own page (its UI code in Bench's
   WebKit cache, JS bodies only) takes a pause as over once a read shows none
   of `five_hour`, `seven_day` and `seven_day_oauth_apps` used up, so it
   ignores the model weeks too. Now only the 5-hour and weekly limits can
   pause a session, and each session has its own pause.
2. A quiet root with sub-agents still working read as paused: the pause
   looked at the root's `updated_at`. The poll now also returns its own order
   key, the tree's latest write (`activeAt`), and the pause uses that.
3. Extra usage at 99.5–99.99 % rounded to 100 and counted as used up. It now
   keeps its unrounded `reached`, as the limits already did.
4. The phone showed the Mac's sentence, in the Mac's time zone. It now says
   the time from `until`, in its own zone and on its own calendar day.

The authoritative signal (`frame_activity` / `usage_limit_paused`) is still
socket-only, with no HTTP route, so the pause is still inferred (DESIGN.md,
Usage pause, "What it can't tell").

Automated, with made-up fixtures only:

- ✅ `swift test`: 1,094 tests, all passing in the last full run. In two
  earlier full runs, `LettingGoTests`' idle-close timing test failed. It
  sleeps for real against a 1.5 s window, and the Mac's load average was
  17–20 on 10 cores; it passed 3 of 3 runs on its own. That code was not
  touched here. New or rewritten:
  - **`UsagePauseTests`.** Only the 5-hour and weekly limits hold; a used-up
    model week holds no session. The plan's payload is parsed at 99.49, 99.5,
    99.6, 99.99, 100 and 100.4 %, and extra usage at the same figures, off,
    unsaid and without a figure. A session is held only once quiet across its
    whole tree, on a read after its last write. A quiet root with a helper
    still writing is not held, nor is a session without a measured tree. One
    session can be held while another works. Room is believed only 75 s
    after the pause began. The sentence is checked in two time zones.
  - **The watcher, through its own observing and scheduling.** It runs with
    an injected clock, schedule and inputs, and no sleeps. It enters a pause,
    and a renewed write ends it. The limit starting over ends it without a
    read, and extra usage switched on ends it. Failed reads keep it for two
    minutes, then drop it. A second session stays working.
  - **`SessionsPollTests`.** In a made-up database, a session's `activeMs` is
    its whole tree's latest write: helpers, a helper's helper and a hidden
    one, under all three ways of picking. The root's own `updatedMs` is
    unchanged. The poll's equivalence checks ignore the new field.
  - **`PhonePauseTests`.** These run the embedded `/app.js` in
    JavaScriptCore with a small fake DOM, fake timers and a fake `fetch`
    (`PhoneAppHarness`). They follow the open session from running to
    paused, with no live-text requests for 30 s, "Paused · usage limit", its
    resume time and no "Working for", then back to running, where live text
    is asked for again. A session working beside a paused one keeps its live
    text. The Now list's banner, still row and live row are checked. Resume
    times are checked in Detroit, Tokyo and London, including Tokyo already
    on the next day. Absent or bad times, and past ones, are covered, and
    the Mac's own sentence never shows.
  - **Mutation checks, each reverted afterwards.** Dropping the phone's
    per-session live-text check fails `PhonePauseTests`. In one run together,
    using the root's `updatedAt` instead of `activeAt` failed three
    `UsagePauseTests`, and rounding extra usage before the used-up test
    failed the extra-usage parsing test.
- ✅ `node --check RemoteWeb/app.js`; `Scripts/embed-remote-web.py` regenerated
  `RemoteWebApp.swift`, with its own node check of the stripped JS, and
  `--check` passes.

Not checked live (Bench wasn't launched, and nothing reached a real daemon,
plan or phone):

- a real used-up limit, on the Mac's panel, menu bar, capsule or activity
  list, or on a phone;
- the phone app on a real iPhone or iPad in another time zone;
- `--demo remote -demoUsagePause YES`, which now holds every made-up working
  session.

## 2026-10-14, Bench 0.5.2 (a usage-limit pause is not "working")

- Sam's report: with a usage limit hit mid-session, Claude Science says
  "Sending messages is paused" but Bench's specimen kept playing.
- ✅ Read from Claude Science's UI code (Bench's WebKit cache, JS bodies
  only): the pause is a `frame_activity` phase, `usage_limit_paused`, sent only
  over its page's socket and checked against `/api/usage`. Bench now reads it
  as running sessions quiet for 20 s plus a used-up limit with no extra usage.
- ✅ `swift test`: 1,064 tests, with `UsagePauseTests` (quiet versus writing,
  rounded-to-100 versus used up, a window already started over, extra usage,
  two limits, the sentence, and `/api/state`'s `pause` only while something
  runs).
- ✅ Phone, through `--demo remote -demoUsagePause YES` in headless Chrome:
  the Now banner, still rows saying "Paused", and the session screen's "Paused
  · usage limit" with when it resumes and no live card. It also caught two
  phone bugs: a session's own screen never treated `running` as working (no
  live dot or "Working for" clock), and the live card's padding rule also
  padded the working dot (32 × 24 px instead of 10 × 10).
- Not checked live: a real usage limit (the panel, menu bar and capsule on
  the Mac, drawn from the same model). Seen next time a limit runs out.

## 2026-10-14, Bench 0.5.1 (a Fable review's fixes, faster reads, 519 specimens)

- ✅ A read-only review by Claude Fable 5.1 (`Bench-review-0.5.0-fable.md`,
  outside the repo): 0 critical or high; 3 medium, 4 low and 1 info on
  security and correctness, and 2 medium, 4 low and 3 info on performance.
  Fixed:
  - Allow once only for code shown whole: the phone shows every line,
    wrapped, with invisible characters marked; the Mac withholds code holding
    a CR, zero-width, joiner, filler, tag or other invisible character, more
    than 60 lines or a line over 160 characters, and code whose `tool_id`
    another pending request shares.
  - Messages and new sessions refuse the upload format's reference prefixes,
    and only the photo flow may carry an attachment line.
  - A photo retry reuses its upload; a read in flight when an action lands
    is read again; a helper's question shows a card; photos decode once,
    at most 24 MP, always to sRGB; archived projects list no sessions.
  - Reads: one persistent read-only SQLite connection instead of a
    `sqlite3` process per read (up to 60 a minute while a session worked),
    and the sessions poll reads closely only its candidates. On made-up
    databases with the usual indexes: 15.5 / 31.2 / 52.8 ms before, 0.6 /
    1.0 / 1.5 ms after, at 500 / 3,000 / 8,000 sessions; the same rows as
    the 0.5.0 SQL on every layout tried. The connection lets go after 10 s
    idle, and a process watcher hears the daemon quit.
  - The panel isn't republished for token counts; the phone's history is
    cached 30 s and re-read only when the session changed; live polling
    eases to 3 s and 5 s while nothing changes; the app's files are cached
    by content hash; downloads encode in pieces.
- ✅ `swift test`: 1,056 tests in 138 suites.
- ✅ 12 new specimens (519): Gene-set enrichment, Bootstrap resampling, NMR
  spectrum, Targeted degrader, Allosteric switch, Collagen braid, FRAP
  recovery, Integrin activation, ATAC accessibility, RNase P, Azobenzene
  switch, Acoustic levitation (made in another session; preview GIF in
  `~/Documents/Default Project/new-specimens-batch-O.gif`).

## 2026-10-14, Bench 0.5.0 (permissions, live text, photos, icon badge)

- ✅ `swift test`: 972 tests in 129 suites, all made-up data. New: permission
  kinds (allow only for code and read-only tools, never a `scope`), the
  head-of-queue and helper parent-chain checks, the live-text projection
  (text only, the 4,000-character tail), photo checks and re-encoding (a
  rotated JPEG with GPS comes out upright with no EXIF), the attachment line's
  key order, the badge count in pushes, attachment lines read as files, and
  a parked permission read by its kind.
- ✅ Live, in Claude Science's **Example project** only, from a test device
  paired with a code from Settings and removed afterwards:
  - Live text: a 250-word reply grew on the phone's reads (449, 914, 1,350,
    1,850 characters), with "Working" and "Executing code" between.
  - A network request ("Wants to reach example.com"): Allow from the phone
    refused with the lasting-access sentence; Deny answered, and the session
    carried on and finished.
  - A photo (a 220 KB JPEG of a demo screenshot) sent to a session: uploaded,
    attached, and Claude described the picture correctly; the history shows
    it as a file chip whose thumbnail opens.
- Found live and fixed: a session waiting on a permission said "Asked you a
  question" (the status won over the request's kind), and the daemon's
  "[System] Attached file: …" note showed inside the message.
- Not checked live: Allow once (Sam's Claude Science already runs code
  without asking, so no request came), a helper agent's request, the badge on
  the iPhone's icon, a photo taken on the iPhone (HEIC, rotation), and the
  live card on the phone itself.

## 2026-10-13, Settings → Phone as a setup checklist (after 0.4.0)

- ✅ `swift test`: 738 tests in 97 suites. New: `PhoneSetupTests` (finding
  the phone in a made-up `status --json`: same user by id or login, iOS,
  iPadOS and android, offline still counts, tagged and other users' don't;
  every step's transition, Skip, a step that comes undone, Pair Another
  Device, the code only while "Pair your phone" is open, across every
  combination; the demo's steps) and the tab's 10 s look (status only, one
  at a time, nothing in a demo). The real CLI's key names (`Peer`, `OS`,
  `UserID`, `Online`, `User`) were checked against its output's structure
  only.
- ✅ Captured quietly, light: `--demo phone-settings --step 1` to `7`; dark
  (`-appearance dark`): step 4. Clay on the open step's button doesn't show
  in a quiet capture (the window is never key, so prominent buttons and
  switches draw grey).
- Not checked live: the ticks appearing by themselves against the real
  Tailscale (signing in, turning HTTPS on, the phone joining), Open
  Tailscale, and the look stopping when the tab is hidden.

## 2026-10-13, Bench 0.4.0 (Bench on your phone)

- ✅ `swift test`: 662 tests in 87 suites before the review (719 after), all
  made-up data. New suites cover
  the server's parser and checks, pairing, Tailscale's status and serve
  output, the session, history and artifact projections (their in-page
  JavaScript runs in JavaScriptCore against a fake `fetch`), the actions,
  browse SQL against a made-up database, Web Push (RFC 8291's worked example
  byte for byte, VAPID tokens verified), and the devices file.
- ✅ Live on the Mac's tailnet (`https://<node>:8443`): `/` 200 with the CSP,
  `/api/*` 401 without the cookie, `/sw.js` served, the Home Screen icon an
  opaque square. An iPhone paired from its Home Screen app, subscribed to
  notifications (Settings → Phone shows "Notifications on"), and Send a Test
  arrived on it through Apple's push service.
- ✅ Live in Claude Science's **Example project** only, from a test device
  paired over curl and removed afterwards:
  - listing projects and the project's sessions;
  - starting two sessions;
  - answering a question (Claude replied with the choice);
  - a message after it finished (sent), one while it worked (queued, then
    read) and the same message id again (not doubled);
  - a plan: a stale version refused ("changed"), the right one approved and
    run;
  - history: turns, the question with its answer, the plan, step lines
    ("Ran a command, saved artifacts") and file chips;
  - artifacts: a markdown note and a CSV through `/text`, a PNG's WebP
    thumbnail, and its download with `attachment` and `sandbox`.
- Found live and fixed: the daemon's older rows carry no `_ts`, so every
  older session read as "can't read this session"; a turn now shows without
  a time.
- Found live and fixed: the paired devices were in the Keychain, and Bench's
  self-signed build (no Team ID) made macOS ask for the password after every
  update, with Bench frozen waiting. They are a 0600 file now.
- ✅ A read-only Opus security review of Remote (other tailnet devices, a
  page in a browser on the Mac, other local processes, a hostile or stolen
  paired device, hostile session content): 0 critical or high, 1 medium, 8
  low, 1 info, all fixed (`swift test`: 719 tests in 95 suites). The medium:
  Serve's `--bg` mapping outlived Bench, so whatever took the loopback port
  next would get the phone's cookie. Checked live against the real
  Tailscale: quitting Bench removes its mapping ("No serve config", the
  address refuses connections) and launching puts it back in 2 s, with the
  iPhone still paired; the login is now kept as a SHA-256 hash.
- Not checked live: a push for a real event while away from the Mac, an
  8 MB download and saving it on the phone, the iPad layout on a real iPad,
  a daemon restart while the phone is open, the pairing lockout ladder and
  New Code, and the shared-address note with a second Serve site.

## 2026-10-12, Bench 0.3.6 (lock fix, review fixes, update check, welcome)

- ✅ `swift test`: 316 tests in 41 suites. New:
  - `DaemonRestartTests`: a waiting card outlives the daemon going away;
    starting while it's down is no burst.
  - The Nidus `away` focus file.
  - `UpdateCheckTests` (41): version compare, GitHub JSON, once per version,
    scheduling, no request with the switch off.
  - `WelcomeTests` (16): existing users by stored keys only, shown once,
    the page flow.
- ✅ Two read-only Opus reviews of b1f4360..e8c4e76: 0 critical or high,
  3 medium (2 the same) and 21 low. Fixed:
  - both mediums;
  - Show Now's notification;
  - ⌘⇧O scope and Caps Lock;
  - `no-store` on API reads;
  - the plan read retry;
  - clearing delivered notifications when names go off;
  - releasing held finishes when the hold goes off;
  - the Alerts height;
  - the iPhone claim (macOS doesn't send Mac notifications to an iPhone).
- Window captures failed this time ("could not create image from window"
  for every window): Screen Recording for the host app seems to have been
  reset. The welcome pages were checked from the agent's off-screen renders.
- Not checked live:
  - Install Update from /Applications (the detached script outliving Bench);
  - the welcome on a fresh install (`defaults delete local.sam.bench` on a
    test account);
  - the daemon-restart behaviour on a real restart;
  - Nidus `away` (needs Nidus's away-flag branch).

## 2026-10-10, Bench 0.3.5 (quick wins from a ChatGPT list)

- ✅ `swift test`: 256 tests in 33 suites, three runs in a row. New: step
  titles and the 8-step cap (`PlanStepTitleTests`, `PlanStepListTests`),
  snoozed reminders (`ReminderTests` +14), the sparkline and the learning /
  little-use lines (`UsageForecastTests` +16), the active page for menu
  commands (`WebPageTests`, 10). `recentKeepsEachEventOnceAndOutlivesItsCard`
  and its sibling now wait for the card to go instead of a fixed 200 ms,
  which a busy parallel run could outlast.
- ✅ Captured quietly: `--demo plan` (10 steps · feasibility: high, Show
  steps); `--demo toolbar --open-activity` (snoozed rows with "Reminds you at
  …" / "after your focus session" and the bell buttons); Settings → General,
  Panel, Alerts and Usage (`--demo general|panel-settings|alerts|usage-settings`).
- Process note: two agents in separate worktrees both used `git stash`,
  which every worktree of a repo shares, and popped each other's work. It
  was recovered byte for byte. Agents must never use `git stash` here.
- Not checked live: menu commands in a Browser or pop-up window and dimmed
  in Settings; Show steps opening on a real plan; the sparkline after real
  reads; Show Now / Cancel on a real reminder.

## 2026-10-06, Bench 0.3.4 (approve plans, usage forecast, field guide)

- ✅ `swift test`: 193 tests in 28 suites. New: `PlanApprovalTests` (58:
  frame and plan shapes, wrong types, a sub-agent waiting, the version
  changing at the press, every result code), `UsageForecastTests` (24) and
  `SpecimenGuideTests` (17, with the completeness test on: every specimen has
  a note).
- ✅ Captured quietly: `--demo plan` (the plan card: summary, steps and
  confidence, Approve / Open / Later); the panel with captions on; Settings
  → Specimens with the field-guide preview text.
- Notes: written per category, then fact-checked by two reviewers (41 fixes).
- Approving was built from reading Claude Science's own UI code (the June 30
  build in /Applications; the running daemon may be newer). It is gated on
  the response shapes at run time and falls back to Open.
- Not checked live: approving a real plan (needs a throwaway session whose
  plan Sam is happy to approve: card, Approve, Approved ✓; a plan revised
  before the press says it changed; after a daemon restart the CSRF retry);
  the forecast line after 15 minutes of use; the Topics menu; hover notes.

## 2026-10-05, Bench 0.3.3 (screen, +N more, Quick Open, Mac notifications)

- ✅ `swift test`: 94 tests in 16 suites. New: `QuickOpenTests` (15: empty
  query order, prefix > substring > fuzzy, diacritics and case, project
  matches, several words, no matches, duplicates) and `NotificationRuleTests`
  (28: each card kind, names hidden with nothing leaking, finishes only when
  asked and never while held, none for page notifications, none without
  permission, no sound when Bench chimes; the model's hooks: none on the
  first read, one per new wait, withdrawn when opened, dismissed or no
  longer waiting, a returning reminder sends again).
- ✅ Captured quietly: the panel's "+2 more ⌄" (`--demo working --several`);
  Settings → General → Screen ("Connect another display…" on one screen);
  the Mac notifications section (scrolled by setting the scroll bar's value
  through System Events, which moves no pointer).
- ⌘⇧O is caught by a local key monitor before the web view, since a page
  that binds it (claude.ai uses it for a new chat) would keep it from the
  menu.
- Not checked live: Quick Open's sheet (focus, ↑/↓, Return, Esc); the "+2
  more" menu opening and its items; a second display; the real permission
  prompt, a notification's banner, clicking one, and iPhone mirroring.

## 2026-10-05, Bench 0.3.2 (favourites)

- ✅ `swift test`: 50 tests in 13 suites. New: only favourites plays them
  whatever is on (a favourite switched off still plays; switching back plays
  what's on); no favourites, or only unknown names, plays what's on.
- ✅ Captured quietly with `-favoriteScenes (…)` and `-onlyFavoriteScenes
  YES/NO`: stars on the favourites' tiles; the Play picker; the ☆ filter
  segment (the four-segment row with text overflowed, so the favourites
  segment is a star and the search field 200 wide); while only favourites
  play, checks gone, non-favourites dimmed, categories greyed, "6
  favorites", "Playing your favorites".
- Not checked live: clicking a star (it is its own button over the cell's
  button) and the panel's Add to Favorites.

## 2026-10-05, Bench 0.3.1 (one by one, Later reminders, 20 specimens)

- ✅ `swift test`: 48 tests in 13 suites. New: `SpecimenChoiceTests` (a
  specimen in a category that is off comes on alone; a category's last
  specimen off turns the category off; mixed goes all on then all off; Play
  Only; the last specimen stays on; None; stored choices tidied) and
  `ReminderTests` (a put-off card returns after its time only while its
  session still waits; a new kind of request shows at once; after focus
  returns when Nidus focus ends; Dismiss is for good; a late click does
  nothing; opening clears it).
- ✅ Captured quietly (`open -g -n … --quiet`): Settings → Specimens with
  mixed categories ("Lab 125 of 127"), the All/On/Off filter and a section per
  category; the toolbar popover's mixed checkboxes; General → Corner; the
  working panel in the top-left corner (`-panelCorner topLeft`: window at
  x 4, just under the menu bar); the needs-input card with its Later split
  button.
- ✅ 20 new specimens (507): each drawn in a standalone harness that checks
  coverage at 16 pt, cost, and that the loop's last frame matches its first;
  then the droplet's `LabScenesTests` and `LabSceneOrderTests` (9 tests) and
  a render through `RenderPreviews.testLabScenes`. `Bench --list-scenes` says
  507; `--measure-sheets 88`: mean 3.4 ms per second of frames, none of the
  new ones among the dearest.
- ✅ Signed: `codesign -d -r-` shows the Solanum Code Signing root.
- Not checked live: clicking Later's menu on a real card (the panel's own
  tap-to-open sits behind it, as it does behind Open), the right-click menus
  on the panel and the grid, hover audition, and a real download failing.
  Check these on the first real card and in Settings.

## 2026-10-02, Bench 0.3.0 (heads-up notices, Nidus, menu bar specimen)

- ✅ `swift test`: 28 tests in 11 suites. New: plan cards once per window
  (a reset time a few seconds off is the same window), nothing below 90% or
  for the per-model weeks, a reset card only for a reset seen happening;
  context once per session; last week's totals and busiest day (which
  caught the weekday being named in the local time zone instead of the
  calendar's); focusing only while the file, Nidus running and `until`
  agree; held finishes with a page notification for the same finish.
- ✅ Captured quietly (`open -g -n … --quiet`, frontmost app unchanged):
  `--demo notice` (the plan card, "1 of 2" with the week behind it) and
  Settings → General's new switches and Heads-up section.
- ✅ Menu bar specimen: with `-showMenuBarSpecimen YES`, System Events lists
  the status item "Bench sessions"; with NO there is none. CPU while
  playing: 0.0–2% (`top`, six one-second samples), the same as off apart
  from one sample.
- Not checked live: a real plan crossing 90%, a real context at 85%, a new
  week's card, the specimen's ink on a dark and a light menu bar, and a real
  Nidus focus session holding a real finish (Nidus 0.1.5 publishes; test it
  with a session that blocks nothing of yours).

