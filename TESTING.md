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

## 2026-10-26, Show Where It Came From goes to the reply in the conversation (`g/show-source`, from main a37b3fb, Capsid 1.0.7)

Sam: "When I click Show Where It Came From I think it should take me to the results/attachments section of that exact reply
from Claude, not just the overall conversation." The button opened the reference reader; it now takes the main window to the
session in Claude Science's own page, scrolled to the reply with its Generated tray in view, and the reader is Open as
Reference in the ⋯ menus. What was read: Claude Science 0.1.70's web bundle (`web-dist/assets`, the only part of its folder
touched; no database, no auth, no daemon asked) to see how a page can go to one reply. What ran: the page script in
JavaScriptCore on a made-up conversation (a virtual list that loads earlier messages when scrolled up, placeholders, trays of
one, two and eight files, a folded-away start) with the timers on a virtual clock, and the same script in a real WebKit view
offscreen on a made-up page drawn as the bundle draws one. Nothing else: no daemon started or stopped, the app not launched,
no window shown (the WebKit view's window sits at -20,000), nothing in /Applications.

- ✅ **How the page lets one reach a reply: it doesn't, so the script scrolls** (DESIGN.md, Shelf → The way back, has the
  offsets). No address names a message (three routes, `location.hash` read nowhere); the page's own jump is a module-private
  dispatcher that only its compute chip and its "view in context" call; what its jumps and the reviewer's findings look for is
  `data-msg-idx`, an absolute index (the reveal listener adds the window's start and looks for exactly that number). The
  conversation is a virtual list that keeps the last 200 messages and loads 200 more on an upward scroll under 1800 pixels. So
  `SourceSeek.body` scrolls toward the number, waits out the placeholders, scrolls up at the top, and gives up after six seconds.
- ✅ **The reply and its tray** (`SourceSeekScriptTests`, 23 tests). A reply on the screen: `turn-found → tray-shown →
  card-marked`; one 1,000 messages back reached by loading earlier pages (5 or more loads, under 8 seconds of the page's
  time), with the page keeping the screen where it was after a load and without; one below the screen; placeholders that last
  longer than the script's pause; a whole turn shown from 7% down when it fits, the tray two-fifths down when the turn is
  taller than the screen, a turn with no tray with its reply a quarter down; the item's card found by its version, else by its
  name when exactly one card has it (a later draft of the same figure), never between two of one name; a card folded into
  "+3 more" is not opened (no click reaches the page's button) and the tray is outlined; the place is put back for a moment
  after the page moves it.
- ✅ **Giving up leaves the page as it was opened**: a message the page draws no element for, a start that can't be loaded (the
  first 1,000 messages folded away, loads that fail), no scroller at all (`no-scroller` within the wait): each ends with
  `turn-not-found` or `no-scroller` in a few seconds of the page's time, with the page back at the newest reply and nothing
  outlined. A user's wheel, touch, key or press (`isTrusted`) ends it at once and leaves the page where they put it; the same
  four events made by the page itself don't. A newer run replaces an older one.
- ✅ **Nothing of the page is changed**: after a run the tray's markup is what the page made (no attribute, class or style), the
  four listeners are off the document, no observer is left, and the script's token in its own world is cleared; the outline is the
  browser's animation. The page's words are guarded in the made-up page (reading a text node throws), so a script that read them
  would fail. Without `Element.animate` nothing is claimed drawn.
- ✅ **Which reply, and the window** (`ShowSourceTests`, 26 tests, all on fakes): the README's row as it stands (no look); with no
  row the newest reply that shows the version (asked for the one version, and from the file's time less a minute for a Find
  result); none found, unreadable, or a look past its twelve seconds: the newest reply and no more said; a note: no look; a row no
  history can have is no row; a version that is not an id never reaches the daemon or the page. A window on another page is taken
  to the session and the scroll waits for the page (up to 20 seconds; `not-ready` after); one already on it is not reloaded;
  a read-only Capsid opens Claude Science's app and stops; ids that make no address only bring the window forward; a page
  that went elsewhere during the look is not scrolled; a newer click replaces an older. The page's steps are passed word by
  word (anything else dropped, 12 at most) and `no-scroller` leaves a breadcrumb.
- ✅ **Open as Reference** (`ShelfMoreMenuTests`, `ShelfNoteMenuTests`, `ShelfDocumentReadingTests` and the wiring tests): in the
  detail card's ⋯ after Keep with Data and Code… and before Export Figure as PDF…, on a note's and a document's card too,
  in the grid card's menu right after Show Where It Came From, a VoiceOver action, off in a demo; the button and Find's Show
  Where It Came From go to the conversation, the item runs what the button used to. The three existing tests that held the
  menus' exact arrays were updated, and they are what fails when the item is dropped.
- ✅ **Compatibility inventory**: `CompatFeature.showSource` and seven hooks (the scroller, `[data-msg-idx]` and what its value
  counts, `[data-rs-index]`, the tray, the card, label and thumbnail it shares with the figure menu, the page's loading on an
  upward scroll, `Element.animate`); the script's selectors are held to the list both ways (`SourceSeek.body` joined the
  scripts checked, the two files joined the lists of files that read the markup and run a script in the page). `HistoryShowing.walk`
  and `readShowing` take a page count (24 for this, Keep's six unchanged, 50 at most).
- ✅ **Captures** (`SourceSeekSnapshotTests`, run with `CAPSID_SNAPSHOT_DIR`, 19 seconds): a made-up conversation in WebKit
  offscreen with the script in its own content world, light and dark. The steps, the tray on the screen, one animation, the
  tray's markup unchanged, no style on the card, and, for the reply with no files, the reply a quarter down, were checked
  in WebKit itself. In `shots-source/` beside the worktree: `source-landed-light.png`, `source-landed-dark.png` (a reply 54
  exchanges back with its two files and the picture's card outlined), `source-folded-light.png`, `source-folded-dark.png`
  (eight files, the one asked for folded into "+3 more", the tray outlined, five cards still there), `source-notray-light.png`,
  `source-notray-dark.png`. Timers in the offscreen view ran at full speed.
- ✅ **Mutation checks** (each break made, the named tests failed, the break undone). Script, 23 tests: `cardIn` always null: 10
  failed; no nudge at the top: 1 failed (the page that does not keep the screen where it was after a load; the ones that keep it
  pass, as they should: the jump to the top is itself an upward scroll that loads); the `isTrusted` guard dropped: 1 (the
  page's own events); the tray looked for in the whole scroller, not the turn: 13; the newer-run token dropped: 1; no put-back
  on giving up: 3; tray at 0.1 and not 0.4: 1; no re-aim while it settles: 1; "nothing drawn" taken for giving up, not waited
  out: 9. Swift: the look ignored: 3; a look made even with a row: 2; the window always reloaded: 1; a reply asked for with no
  row: 4; no Open as Reference in the menu: 3, in a note's menu: 1; Find back on the reference window: 1; the button back on the
  reader: 1; no breadcrumb: 1; no wait for the page: 11; the walk ignoring its page count: 1; the `[data-rs-index]` hook
  missing from the inventory: 1.
- ✅ **Whole suite:** `✔ Test run with 4524 tests in 581 suites passed after 36.837 seconds.` (`swift test --jobs 2`, one swift process
  at a time). The made-up DOM gained `removeEventListener`, so the figure menu's, the document tile's and the viewer's script
  tests ran again with it: they pass. No flake.
- ⏳ **Only a live click can confirm:** that the real page loads earlier messages when the script scrolls up (its handler was
  read, not run, and it hears a scroll event that goes up under 1800 pixels; the script's jump to the top and its nudge make
  one); how long a reply a few thousand messages back takes in the real page, and whether six seconds is enough; where the
  page's own "last seen" pill and its return anchor leave the scroll; what a session still streaming does when the script
  scrolls away from its end; a turn's real height and the tray's real place against the fractions above; the real card's
  address (a thumbnail whose address names the version, from the same hook the figure menu uses) and the outline over the page's
  own ring; a note's session opening at the newest reply; the main window coming forward from the Shelf window.

## 2026-10-26, three bugs that could lose a person's words (`g/fix-dataloss`, from main 8e35826, Capsid 1.0.7)

Codex's review of 1.0.7 found and reproduced three ways Capsid could lose words a person had typed or kept. Each was
reproduced first by a test that failed on the code as it was, then fixed, then the fix was broken on purpose and the test
failed again. Everything ran on made-up content: the phone's own script in JavaScriptCore against a made-up page, READMEs
as strings, and the legend editor on a temporary Kept folder with a disk whose reads a test can hold. No daemon touched, no
window shown, the app not launched, nothing in /Applications or the real Kept folder.

- ✅ **A successful phone send no longer erases the next draft and photo** (`RemoteWeb/app.js`, `PhoneComposerLifetimeTests`).
  Held: the session's read after a send, and a second message's post. Before the fix 7 of the 8 tests failed (the 8th, a
  send that could not be told, passed throughout, as it should). The words, the photo and the id that went are now cleared
  at the moment the composer opens, before the read; what is typed or picked after that, a second send started in the
  read, and words changed while the post was out, all survive.
- ✅ **Keep's Try Again keeps a person's bullets in the README** (`KeptReadme.updating`, `KeptReadmeOwnRowsTests`). All 11
  tests failed before the fix. Bullets ahead of, between and behind Capsid's rows, in both sections, with plain line ends,
  Windows line ends, and a byte order mark; a row going, changing, being new, nothing changing (byte for byte, twice); a row
  a person reworded; a section of their own bullets.
- ✅ **A late legend reload no longer overwrites words just typed** (`ShelfLegendEditor`, `ShelfLegendTests`). Typing during a
  held reload, away and back, a save asked for meanwhile, Claude's legend put in meanwhile, another app's change meanwhile (the
  conflict rule still applies at the save), a cancelled read, and a README that can't be read (still turns the field off).
  Eight of the ten failed before the fix (the tenth: a dropped read leaves a sentence the field was saying, such as a
  conflict, where Use Theirs is cancelled); the other two (a clean reload, a README that can't be read) are controls and
  passed throughout.
- ✅ **Mutation checks:** each fix was broken on purpose and its tests failed, then it was restored. The phone: the cleanup
  moved after the read (2 tests fail), the cleanup made unconditional (2 fail). The README: any "- " line taken for
  Capsid's (8 fail), a row never taken out (11 fail, six of them older tests). The legend: the stale-read check removed
  (5 fail), the cancelled-read check removed (1 fails).
- ✅ **Whole suite:** `✔ Test run with 4418 tests in 572 suites passed after 28.795 seconds.` (`swift test --jobs 2`).
  Before the last refinement above (one more test, 4417), two full runs each had a timing test fail while the Mac was
  busy with another build (load average 17): `LabInsightsGateTests.bothOfTheFailureCardsSwitchesMustBeOn` and
  `QueryCancellationTests.aCancelledReadLeavesTheConnectionForTheNextRead` in the first,
  `ReadingGateTests.cancellingTheCallerCancelsTheRead` in the second. The first two passed alone and the third run passed
  everything, so they are load flakes, not these changes.
- ⏳ **Only a live run can confirm:** the phone page in a real Safari (typing and picking a photo during a slow refresh on a
  slow Mac link, and that iOS leaves the field editable then); the Shelf's field under a real, slow README read (returning to an
  item and typing at once); Try Again on a README a person edited in an editor on Windows.

## 2026-10-26, the Shelf's search says when it is still reading (`g/search-hint`, from main 8e35826, Capsid 1.0.7)

Since 1.0.6 the search also reads inside notes, documents and kept legend files, off the main actor, finding more as each
file is read, so the first results of a search could look final when more matches were on the way. While files that
could match are still being read, one quiet line now says so, and the empty state no longer says "no matches" for good.
Everything ran offscreen on made-up notes and scratch folders: no window shown, nothing launched, installed, merged or
pushed, the real Kept folder and `~/.claude-science` untouched.

- ✅ **The whole suite**: `✔ Test run with 4416 tests in 575 suites passed` (27 new tests, 26 checks and one capture test that
  does nothing without `CAPSID_SNAPSHOT_DIR`). No test failed in either full run (the first, before the gone-file fix below,
  had 4415), so there is no flake to name; the machine was under load from two other agents' builds (load 7 to 11).
  One test is timing-sensitive by nature, `theLastChangeInAnIntervalIsPublishedWhenItIsUp`: three gated reads must all
  land inside one publishing interval, so its interval is 1.5 s (it was 0.8 s) and it takes that long; a machine that
  starved utility work for longer than that could fail it, and it would pass alone.
- ✅ **The line**: "Still reading 12 files; more may match." ("1 file" for one), 11 pt in the muted ink, one line, at the end
  of the chips row, in the room the row's spacer already leaves, so the grid does not move when it comes or goes and nothing
  animates. With less room (the narrowest window, counts in the hundreds) the same place says "Still reading; more may
  match." and then "More may match." (`ViewThatFits`; found in the first captures, where two digits cut the long form at
  620 points). VoiceOver gets one label without the count, "Still reading files; more may match.", and one low-priority
  announcement of the same words when the line appears (a hook on the model, as the toast's, so a test counts it); the
  count falling under the label says nothing more.
- ✅ **What it counts**: the prose files still to be read that **could** add to what the search finds: those of items in the
  chosen project that the search does not already find (by the card's words and the text read so far), each once. A rescan that
  finds nothing new names nothing (no flash every time the folders are read), a file read before and changed since is read
  again without a line, and a file that couldn't be read (a disk that didn't answer, gone, put away in iCloud) is not
  waited for. No search shows nothing, at once when it is cleared while reading goes on.
- ✅ **No match while reading**: the Find page, which is what a search of two letters or more shows when nothing is found,
  says "Nothing on your shelf matches “x” yet." (the full stop is what it said before), with the line at the end of the chips
  beside it. A one-letter search is too short for the sessions, so it gets the Shelf's own empty state, "Nothing matches “x”
  yet" with "Still reading 10 files; more may match." in place of "Search covers names, sessions, legends and Claude’s
  words."; the chips then leave their line out, so it is said once. Both go back to the old words when reading is done.
- ✅ **Throttle**: `ShelfTextIndex.unread` is published at once when it fills or empties (the line appears and goes
  without delay) and at most once in 250 ms between (`publishEvery`, the last change in an interval always follows), and
  the model counts again only then and when the search, the project or the shelf changes, never for each file read. Also
  changed: a file read that adds nothing to what is shown no longer redraws the window (the model compares the ids shown
  before and after); before, every file read sent a redraw, so 500 files meant 500 of them.
- ✅ **New tests** (`ShelfTextIndexTests.swift`, which has the fakes: `MadeFiles`, now with a `Steps` that lets reads
  through a few at a time): the words (plural, the label without a number, the shorter forms in order, the empty state's
  and the Find page's lines with and without "yet"); the count's rules (an item already found, by its card or by text
  already read, gains nothing; one project; no search or only blanks); the index's `unread` (counted when asked for, one
  fewer as each file finishes, the sequence of publications with a long interval is fill and empty and nothing between, the
  last change in an interval is published when it is up, a rescan publishes nothing, a new file is named until read, a file
  taken off the shelf is let go, a read that throws, a gone file and a put-away file are not waited for, and a note whose
  file is gone is looked at again on each rescan without the line coming up each time); and the model on
  real scratch folders with an index held by hand (nothing without a search, shown while searching with files unread and
  gone when reading finishes, the count following each file and VoiceOver told once, nothing left to read shows nothing,
  clearing the search takes it away at once and typing again says it again, the count by project and by items found, the
  empty state saying yet and then the final words, and the redraws for 30 files that add nothing against one that adds a match).
- ✅ **Mutation checks** (break it, see the test fail, restore it; twelve, all caught): a finished file no longer counted off
  (three tests); the initial count one short (eight); project scoping dropped (two); items already found still counted
  (three); the line ignoring whether there is a search (three); the empty state never saying yet (two); no throttle
  between publishes (three); every file read redrawing (one); VoiceOver told on every change (three); the last change in an
  interval dropped (one); the line going only after the interval (two); a gone file named again on each rescan (one). One guard is not mutation-tested because it cannot
  differ: clearing `pending` when the task ends, which every file has already done one by one; it is there so a file
  that somehow was not looked at can never keep the line up.
- ✅ **Offscreen captures**, light and dark, in `shots-hint/` beside the worktree (`ShelfReadingSnapshotTests`, through the
  window stand-in the other snapshot tests use, `NSHostingView.cacheDisplay`, not `ImageRenderer`): `shelf-reading-*` (two
  figures found by name and a note by its text, "Still reading 4 files; more may match." at the chips' end) and `-small-*`
  (620 × 480); `shelf-reading-done-*` (the same search when reading is done: the line gone, the notes wearing "in its text");
  `shelf-reading-empty-*` and `-small-*` (the Find page's "yet", the line beside the chips, with "Still reading; more may
  match." at 620); `shelf-reading-empty-done-*`; and `shelf-reading-empty-short-*` and `-small-*` (the one-letter search's
  own empty state). Refined after the first look: the long form was cut at 620 points with two digits, which is the
  fallback to shorter words; and the first capture had read only notes with nothing to find, which showed the line
  and no results, so it now reads six files and one note is found while the rest are still to come.
- ⏳ **Live, in a real window** (nothing here ran in one): that VoiceOver says the announcement once, quietly, while a
  search is being typed, and reads the label when the line is reached; the line on a real shelf of hundreds of notes, how
  long it stays and that its number falls steadily about four times a second without the window flickering; no flash on
  the periodic rescan; the line fitting or shortening as the window's edge is dragged across 620 points; the toolbar's
  look over the chips (the captures draw a stand-in for the title bar); and Increase Contrast and Reduce Transparency
  (the line is muted ink on the page, which they do not touch).

## 2026-10-26, five rare bugs from Codex's review of 1.0.7 (`g/fix-rare`, from main 8e35826, Capsid 1.0.7)

Codex's findings 4 to 8, the medium ones. Each was written first as a test that failed on 8e35826, then fixed, then
broken on purpose and put back. Everything ran on made-up sessions, a fake `URLProtocol`, fake writers and senders,
and offscreen drawing: no daemon touched, no window shown, the app not launched, nothing in /Applications.

- **Finding 4, a late Reference document.** Reproduced. Four tests failed before the fix: Back while the download is
  held and the late bytes land, another reply while it is held, a second document pressed while the first is read
  (the first's spinner stayed), and a first document whose drawing ends last (it replaced the second). After:
  each opening has its own number and is left behind by a newer document, Back, another reply or the window
  closing, with its read cancelled and its spinner gone; the same reply grown by a row keeps its document; the
  document keeps its reply's time and Copy with Source names that. Breaking the opening check, `closeDocument`'s
  abandon, the newer-opening abandon and the copy's own time each failed tests (3, 2, 2 and 1) and was put back.
- **Finding 5, an uncertain menu-bar start moved to Quick Start.** Reproduced: a start that came back "didn't go
  through, as far as Capsid can see", moved unchanged, retried under a new id. Now the hand-over carries the id and
  the request's signature and Quick Start's ledger adopts them. The same request keeps the id; an edit, or any
  request after one that worked, has a new one. Dropping the adopt, or the carrying, failed 1 and 2 of these tests.
- **Finding 6, a hand-over dropped while Quick Start sends.** Reproduced as the second request being in neither
  place after the popover closed and came back. Now Quick Start says whether it accepts (`accepts`), the controller
  returns that and, when it is no, does nothing, not even bringing the panel forward (that would resign and close the
  popover the words are in); the field clears only on acceptance. The line under the field says "Quick Start is
  sending; your words are kept here." (my wording; new demo step `kept`, offscreen picture checked in both themes:
  one muted line, no clipping); the words are there once more if the popover closes first. Four breaks (ignore the
  answer, always accept, no keep on reopen, no line) failed 2, 3, 1 and 1 tests.
- **Finding 7, delivery recovery.** Reproduced: after the message, a burst of tool rows leaves the last twelve rows
  with no turn, and recovery said "That didn't go through". Four tests failed before (a burst of tool rows for a
  message and for a plan change's words, twelve turns all after the send, the send's own millisecond and a turn
  with no time). A fifth, the reader's own projection of twelve tool rows, also failed but for the wrong reason
  (its fixture's queued message was already "unclear"); its fixture was corrected, and a break of the proof failed it
  for the right one. Now "didn't go through" needs a turn dated strictly before the send among the turns read;
  otherwise "Not sure that went through", the words kept, nothing resent. Eleven existing tests that expected
  "didn't go through" from sparse turns now carry a reply from before the send. Not covered: a message whose own words start with a marker the reader hides
  ("[System]" and the like) is never seen at all; nothing was changed for it.
- **Finding 8, bytes.** Reproduced for the stream's line and, with the fake, for `/models` held whole. Seven tests
  failed before: the line buffer itself, no line end at all after some words, a reasoning flood, a keepalive flood
  with a flood of lines that are not JSON, the cut where a stream limit falls, an oversized list that never ends,
  and an error status with a large body. Now a line is held to 4 MiB, the stream to 64 MiB counting every byte (a test
  can pass a small limit), the list is read to 4 MiB off the main actor (first run on the main actor took 31 s for
  4 MiB in a debug build; moved), and the transport is cancelled the moment one is crossed, the ask ending as the
  existing "ran too long" with the words that came. Removing the line cap, the stream count or the list cap each
  failed 2, 3 and 1 tests.
- **Full suite**, ordinary environment, two jobs: `✔ Test run with 4417 tests in 571 suites passed after 28.262
  seconds.` No test failed alone or under load; no flake seen.
- **Live checks still needed.** The menu-bar field with a real Quick Start mid-send (⌘↩ refused, the line, the
  popover staying, the words after a click-away and a reopen); a real ⌘↩ of an uncertain start into Quick Start;
  a real long Reference document pressed and then Earlier or another document; a real recovery of a message sent
  to a session that is busy (whether the daemon's rows carry `_ts`, which the proof reads); a real provider's list
  and a long streamed answer. Findings 1 to 3 are not in this branch.

## 2026-10-26, merging 1.0.7: Codex's branch with the right-pane fix

- ✅ **Codex's branch validated where its sandbox couldn't** (`g/codex-107` at 4225954, eight commits from 1.0.6).
  The full suite in the ordinary environment: 4,356 tests in 568 suites pass. That includes the thumbnail, image,
  pasteboard, preferences and file-watching tests that failed or crashed under Codex's sandbox, so those were the
  sandbox, not the code.
- ✅ **Reviewed:** the README (neutral wording, one new picture with made-up content only, no metadata), Keep's
  `source_row`, the folder-keyed Undo count, and the document card's captures in both themes and at the narrowest
  size.
  - Noted for later: `Shelf.removed` compares folder URLs where the old code compared paths. The scanner and a new
    folder build their URLs the same way (`KeptDisk.swift` 712–717 and 761), so they match today.
- ✅ **Merged with main**, which holds the right-pane fix (958bb95). The only conflict was this file. The combined
  suite is below.

## 2026-10-26, a picture open large in Claude Science's viewer gets Capsid's items (`g/rightpane-figure`, from main 87ea69b, Capsid 1.0.6)

Sam: right-clicking a picture open large in the right-hand viewer showed the page's own menu and none of Capsid's items, while
figures in the conversation worked. The log said `Figure menu: contextmenu → figure-none` there and `contextmenu → figure-beside →
version-ok → menu-matched → placed` in the conversation. Everything ran on a made-up page (JavaScriptCore), made-up sessions and
lists, and an offscreen WebKit view that is never shown for the captures: no daemon touched, no window shown, the app not launched,
`/Applications` and the running Capsid untouched, nothing read under `~/.claude-science` but the served bundle's `web-dist/assets`,
nothing installed, merged or pushed.

- ✅ **Why, read in the 0.1.70 bundle (not run).** The viewer is `ArtifactTile` (`ArtifactTile-DmtoiOPx.js`, `xo` at 29312 builds the
  picture's address, `getVersionUrl(v)?v=v`, and `case"image"` at 31165 hands it to `ImagePreview`) in the right-hand panel
  (`RightPaneTabContent-BZFM08bq.js`, `Ha` at 41290). `ImagePreview` (`ImagePreview-C0f3P6Gf.js`) draws the picture as a plain `<img>`
  (4144) inside react-zoom-pan-pinch's `div.react-transform-wrapper > div.react-transform-component` (3554), in a box the size of the
  picture with the annotation layer (`vFt` in `index-DhEuR7nq.js` at 2355338, `div.absolute.inset-0`) over it. **The library's stylesheet
  (`index.esm-D4jRnBIq.js` at 27938) gives every image in that wrapper `pointer-events: none`**, so the picture is never what a
  right-click lands on and never in `document.elementsFromPoint`. `closest("img")` found nothing, and `pictureBeside` (the picture in the
  stack, beside the layer: how an inline figure is found) had no picture in the stack. The menu is the same `oG` (`Artifact actions`,
  `index` 2266305), opened by `ImagePreview`'s own handler (2807, `OFt` at 2369542): Copy image, Save image, Download, Export Metadata, no
  red Delete. The address is `/api/artifacts/versions/<version>?v=<version>`, which `versionOf` already reads, and the `alt` is the
  file's name.
- ✅ **Real WebKit confirms the cause** (`theViewersMenuIsDrawnAndDrivenInARealPageWhenAsked`): with the library's one rule in the page,
  `document.elementsFromPoint` at the click has the layer first and not the picture. The fake page's older "tile" fixtures passed because
  their stack had the picture in it, which the viewer's never does.
- ✅ **The fix**: when a right-click is on no picture, link or tray card, the script finds the tile it is in (by its body or its header, as
  a file with no picture is) and takes the tile's one picture in a `.react-transform-component` (`figure-viewer`); from there it is as
  for any figure (version from the address, the menu waited for, the items placed). It takes nothing when there is no such picture or
  more than one. A file on the host's disk (the same wrapper in a `file-tile`, no preview region, no artifact) gets nothing.
- ✅ **Documents in the viewer, the second finding.** `ArtifactTile` draws its title span only when it is not in "slot chrome" mode
  (`!G && <span>`, 56789), and the panel's bindings are `slotChrome: true` (`index` 3289594). So a tile of the right-hand panel has no
  name in its header: the panel's tab strip (`qnn`, 3279391; `FPe` 3303209) has it. "The first span in the header" was therefore the
  version stepper's `v2` (version 2 or later) or nothing (version 1). That fits the trace Sam saw for a document in the viewer,
  `figure-document → menu-matched → placed` with no add confirmed: the click would have looked up a file called "v2". Now the title is
  the span that opens the header's first box and holds only text (the stepper, the buttons and the provenance breadcrumb never are), and
  a tile with none inside `[data-pane="right"]` is named by the shown tab (`data-shown`, or `aria-current` on its button; exactly one;
  the label is the button's last element). Steps `name-from-tab` and `tile-unnamed` say which.
- ✅ **Checked in the bundle after a review**: (1) the header is always drawn: `kt` would portal a slot-chrome tile's header
  elsewhere if `zt` had a provider, but `zt` is local to `ArtifactTile`, not exported, referenced four times in the chunk and
  never provided, so the fallback `<header>` (with its More actions button) is always there, which is also what Sam's document trace
  shows; the panel's `slotChrome: true` reaches the tile through the page's bindings (`ProjectControlPlane-ZzzhlAui.js`, 79870, spreads
  `arn`). (2) the annotation layer's markers (`g$t`) and popover (`Rae`) render buttons, divs and spans, no `<img>`, so a picture with
  annotations is still the tile's one picture (the "exactly one" rule would otherwise have fallen back to the file's newest version).
  (3) the tab strip (`qnn`) and `[data-pane="right"]` are drawn only in the split layout (`split-right`); in the single-column layout a
  document in the viewer has no name to be had and gets no items.
- ✅ **The log** now says what a name lookup found, one line, counts only: `Figure menu: name matched 1`, `name matched 2` (three, …),
  `name not found`, `files not read`.
- ✅ **Tests** (33 new, `ViewerFigureTests.swift`, the fake page's viewer and tab strip in `FakeFigurePage.swift`): a right-click on the
  layer, a marker in it, the box, the content, the wrapper, the root, the preview region, the header, the stepper and the More actions
  button each puts Capsid's group at the end of the viewer's menu, and a click on each of the four posts the action on the viewer's
  version (a different one from the page's others), name and `image`, and Swift runs each on that version; the stack under the click
  has no picture in it; an untrusted right-click and an untrusted click do nothing; a picture whose address names no version
  (`blob:`, or another origin) is found by the tab's name; no tab strip, two shown tabs, none, a blank or missing label, or a tile outside
  the panel adds nothing and traces `tile-unnamed`; a file on disk adds nothing; two pictures in the wrapper are not a viewer; a Markdown
  tile with a picture in it is its words, and the picture itself still its own version; the conversation's figures trace the same words
  as before; a tile of the panel is named by its tab and not by the stepper's "v2 (old)", cleaned like any name; a tile that shows its own
  name never reads the tab; the provenance breadcrumb is no name; a page that is not a session's gets no name; every step is a word Swift
  reads; the lookup's lines (found, none, two and three, one file at two versions, unreadable, Show in Results, no session) and that none
  holds the name. The inventory lists the new selectors (`.react-transform-component img`, `[data-pane="right"]`, and the tab strip's
  already-listed ones, now read for this too; the `span` selector is gone) and one test pins them. Two older tests changed: a tile with a
  blank name now traces `figure-none → tile-unnamed`, and the script reads three `textContent`s, not two.
- ✅ **Mutation checks** (each broken, run, restored with `cmp`): `viewerPicture` returning null fails 75 expectations in the viewer
  suite, and the WebKit test; the header's name read back to "the first span" fails the stepper, breadcrumb and no-name tests; the tab
  name returning "" fails the name-from-tab tests; `>= 1` for "exactly one" fails `twoPicturesInTheViewer…`; the picture taken from the
  wrapper with no tile round it fails `aFileOnTheHostsDisk…`.
- ✅ **Captures** in real WebKit (offscreen), light and dark: `viewer-menu-{light,dark}.png` (the viewer's menu with Capsid's four items
  at its end, the panel's tab strip above, the version stepper in the header) and `viewer-doc-menu-{light,dark}.png` (the same panel's
  tile of a Markdown file, named by its tab), in `bench-wt/shots-rightpane/`. The WebKit test also drives the click, the message and the
  page's own Escape closing the menu.
- ✅ **The whole suite**: 4,376 tests in 566 suites pass (4,343 in 564 before), `✔ Test run with 4376 tests in 566 suites passed`; no
  failure in the run, no flake.
- ⏳ **Live**, which only a real right-click on the real page can say: that the viewer's picture really gives
  `contextmenu → figure-viewer → version-ok → menu-matched → placed` (the `pointer-events: none` is read from the library's stylesheet, and
  confirmed in WebKit for a page that has the rule, not seen on the daemon's page); that a document in the right-hand panel gives
  `figure-document → name-from-tab → menu-matched → placed` and then `Figure menu: name matched 1` (the tab strip's markup is read
  from the bundle and shared with Capsid's tab hooks, which work live); that the version stepper really was the old first span; and the real click on
  Add to Shelf from the viewer, which Sam has not confirmed. **A limit, not an unknown**: in the single-column layout (no session
  beside the panel) there is no tab strip, so a document open in the viewer gets no items (`tile-unnamed`); a picture there is found by
  its address as always.

## 2026-10-26, Capsid 1.0.7 (Codex): Keep provenance, note Undo and document reading cards

- **Build and focused checks.** The package and tests build with two jobs. After all mutation checks were restored
  and the document menu's source-wiring assertion was updated:
  `✔ Test run with 186 tests in 26 suites passed after 0.187 seconds.` These cover document reads and rendering,
  Keep records, plans, versions and source replies, README parsing, note adds and Undo, figure duplicates,
  removal and restore, the diagnostic breadcrumb, and existing note-card rules. These are automated checks,
  not a live app walkthrough.
- **Keep's source reply.** A new test round-trips a known source row into a Shelf item, checks legend eligibility
  and source navigation, accepts row zero, and excludes pinned, fallback, missing and different-version answers.
  Leaving the quoted answer unticked still retains a known source row.
- **Immediate note Undo.** The temporary-disk test checks the count before another scan. Removals track folders,
  so notes and duplicate figure folders both count correctly.
- **Approved UI changes.** Ordinary Markdown and text documents now show their words, with a quiet source header
  and a closed What Claude said disclosure. The header and More retain file actions; figures and tables keep
  their preview cards. Filename extensions use full muted ink. The compatibility breadcrumb now includes tiles.
- **Bounded document reader.** Eleven tests cover supported types, actual Markdown styling and literal plain
  text, the fallback card, menu actions, size and UTF-8 checks, disk failures, a four-entry LRU, changed files,
  cancellation and an older read completing after a newer read with the same file stamp. Disk reads use KeptDisk;
  Markdown parses off the main actor. Source bytes are capped at 256 KiB per file; unreadable or offloaded files
  use the old card. The bound does not include attributed-string overhead.
- **Mutation checks.** Setting Keep's source row to nil and removing folder tombstones failed two tests with
  seven issues. Removing document request ownership, the post-read stamp check, cache eviction and the pre-read
  size guard failed four tests with five issues. Production files were restored before the passing checks.
- **Offscreen captures.** The original two conditional snapshot tests passed and produced 28 PNGs: short/long
  notes at normal/narrow widths and ten Ask states, in light and dark. The new document snapshot test passed and
  produced 22 PNGs: short/long Markdown, plain text, figure/table comparisons at normal/minimum content size,
  and missing-document fallback at minimum size, all in both themes. Each image was inspected for names and
  paths; only synthetic fixtures appear. No live window was opened. README adds just one image,
  `docs/ask-another-model.png` (215,051 bytes); the old Shelf image is unchanged.
- **Capture limits.** Seeded figure/table images still appear as placeholders because decoding fails in this
  execution environment. The old note harness clips its narrow mock bar; the new document harness adds the
  bar above 620 by 480 points of content and does not clip it. Short documents read cleanly, long ones fade
  above the actions, and the disclosure remains reachable. Actual scrolling, selection, VoiceOver, drag and
  Quick Look still need a live check. Layout comparisons do not certify thumbnail decoding.
- **Full suite did not complete.** The final UI-round full run exited 1 with unexpected signal code 5 at
  `BenchTests/ShelfThumbnailsTests.swift:330`, a nil image force-unwrap in
  `bytesForAKeptVersionReplaceItsPictureAtItsNewCost`. It recorded 19 failing test names before the abort.
  One was an old source-string assertion, `theDetailDrawsTheMenuFromTheRules`, which expected the menu call
  without its new document argument. That assertion was updated and passes in the 186-test run above.
  The full suite was not repeated after this test-only correction. There is no final `✔ Test run with` line
  for the full run and no full-suite pass is claimed.
- **Other unresolved validation failures.** Pasteboard, image/type, preferences, service, asset-catalog and
  swap-script checks failed in the full run. The prior nonvisual round also hit file-watch and installed
  Tailscale signature checks, and crashed at thumbnail line 287; that crash also happened alone.
  The UI capture run had five pasteboard failures despite its snapshot test passing. No load flake has been
  confirmed. Run the full suite in the ordinary development environment before merge; the detailed private
  handoff preserves names and logs. These failures have not been counted as passes.
- Commands used separate temporary compiler/package caches and SwiftPM's `--disable-sandbox`. Native service
  and permission errors remained in this execution environment. Only one Swift command ran at a time, with
  at most two jobs. Existing compiler warnings remain. No dependencies, version, installed app or live services
  changed; no merge, push, tag, install or release.
- The README now covers Shelf text, Claude's legend, Ask Another Model and Mac/phone message limits. Its local
  links resolve; release download, install-script and Nidus targets were checked against GitHub, and Tailscale
  resolved. The download size is 18 MB; the historical idle measurement is labelled as such.
- **Housekeeping.** All nine specified clean, merged worktrees were moved to the Trash, their records pruned,
  and the 60 original merged branch candidates deleted with `git branch -d`, after rechecking each. The main
  checkout, prepared Codex checkout, newer right-pane worktree, scripts, screenshots, remotes and older separate
  improvements clone were retained. The private handoff lists every move, pruned record and deleted branch.
- **Live checks still needed.** Keep-to-Shelf legend and exact reply landing; conversation-menu note Undo;
  duplicate folders and external/iCloud disks; document scrolling, selection, disclosure, keyboard, VoiceOver,
  drag and Quick Look in both themes at minimum size. No real conversations or Kept files were used. The eight
  wider review findings remain open. Source-action restyling and search-progress UI were not approved or changed.

## 2026-10-26, Capsid 1.0.6 released and installed

- ✅ Released as v1.0.6 (tag on 3339a43, "Capsid 1.0.6", by Sam with `gh release create`), marked Latest:
  `Bench.zip` with Capsid.app 1.0.6 (53) inside, 18,240,715 bytes, sha256 9601568be095e671…. GitHub's asset
  digest matches the file built from that commit. Build 52 was never published; 53 adds the note polish.
- ✅ Installed from that same build before the release (CDHash 76606bea; the unzipped copy's signature checks and
  its CDHash is the same). "Signing in: with a code from claude-science url", and the usage read answered 4 s
  after launch.
- The whole suite before the push: 4,343 tests in 564 suites pass.
- ⏳ **Live**: search inside a real Kept folder, a real note's card (drag, Quick Look, the fade), the duplicate-name
  menu, Add Selection to Shelf inside a real Markdown tile, Keep's legend row on a real figure, and OpenRouter's list.

## 2026-10-26, a note's detail card says its words once (`g/note-polish`, from main 7561a05, Capsid 1.0.6)

A note made by Add Selection to Shelf showed the same words three times on its detail card: a picture of its first lines, a
title of its first words, and the whole passage. The card now has no picture and no title: one quiet header ("Note · Plate
reader QC · Assay development · 11:12 AM"), the passage set as a quotation, and the same three controls. Ordinary documents,
figures and tables keep their card exactly (the main row of `ShelfDetail` is the old code, checked line for line against
main). Everything ran offscreen on made-up notes and scratch folders: no window shown, nothing launched, installed, merged
or pushed, the real Kept folder and `~/.claude-science` untouched.

- ✅ **The whole suite**: `✔ Test run with 4343 tests in 564 suites passed` (32 new tests). The first full run failed once, for
  a good reason and not a flake: `KeptDiskCallsTests` counts `NSWorkspace` in `ShelfView.swift`, and a note's ⋯ has one more
  (Show in Finder, the call the grid card's menu makes); the allowed count is now 6, with the reason beside it.
- ✅ **What changed**: `ShelfDetail` draws one of two forms (`ShelfDetail.form(for:reading:)`): an ordinary item's, or a
  note's, `ShelfNoteHeader` over `ShelfPassageText` over the controls. The header's words are `ShelfRules.noteHeader`
  ("Note", the session, the project, when it was put on the shelf in the grid card's own words; each only when known;
  VoiceOver reads them with commas). The passage is 14 on 21 (the reference reader's type), ink, a 2-point rounded rule
  at its leading edge (muted ink with Increase Contrast), at most 600 points wide, selectable, still not rendered as
  Markdown, scrolling inside 280 points with the fade at its foot. The fade is a mask over the words alone and its
  strength follows how much is below, so it needs no animation.
- ✅ **What the preview carried, and where it went**: the drag of the file and the double-click to Quick Look moved to the
  header (same file, same panel, the preview's tooltip reworded for a note); the ⋯ menu of a note opens with Quick Look
  and Show in Finder (a note's alone: every other item's ⋯ is as it was); the grid card (drag, Space, double-click,
  its right-click menu) is untouched; "Preview of note.md" goes with the picture, so VoiceOver reads the header and the
  passage once each. A note whose words can't be read (file gone, put away in iCloud, empty, a disk that didn't answer
  with nothing held) is drawn as any document is, picture and name, since it has only its file (`ShelfPassages.reading`
  tells not yet, words and none apart, so a note's card never starts as a document's and turns into a note's when its words arrive).
- ✅ **New tests** (`ShelfNoteCardTests.swift`, 31, and one more capture test): the header's words with each part present
  and missing (no project, no time, no session, nothing, blanks) and the time as the grid card's caption gives it; the
  note's ⋯ menu and an ordinary item's unchanged; which form a note, a numbered `note.md`, a document, a figure and a table
  get, whether the words are being read, read or missing; the reading states with fake files (gone, put away, empty,
  a disk that fails with and without words held, the wordless forgotten past 64); the drag provider, and the header, ⋯
  and grid card wiring for drag and Quick Look; Copy puts on the pasteboard the same string the card draws; the note's
  card has no preview, name, title or source line and the ordinary one has all of them; the VoiceOver wiring; the
  passage's type, rule, measure and fade; and one that **draws the card and reads it back with the system's text
  recognition**: a note's first words are on its card once (it was three), its header is there, and a document's picture
  (its file's heading) still is.
- ✅ **Mutation checks** (break it, see the test fail, restore it; eleven, all caught): a note drawn with its picture again
  (the form test and the recognition test); the header without its project (four header tests); Copy copying the file
  (three Copy tests); the header with no drag or double-click; a note's ⋯ without Quick Look; the title back on a note's
  card (the source test and the recognition test); Quick Look in ⋯ doing nothing; the passage's room back at 172 points
  (it was `height − 172`, now `− 120`); an animation put back on the fade; a wordless note staying "not yet"; and the
  rule no longer hidden from VoiceOver.
- ✅ **Offscreen captures**, light and dark, in `shots-notepolish/` beside the worktree: `shelf-passage-short-*`,
  `shelf-passage-long-*` (the same made-up notes as `shots-106/`, so each pair is before and after), their `-small-*`
  windows (620 × 480), `shelf-passage-oneline-*` (and `-small-*`), `shelf-passage-gone-*` (the file moved away: drawn as a
  document), `shelf-figure-*` (a figure's card, unchanged), and `shelf-note-*` (the note among the demo's cards, the
  Documents chip, the narrowest window). `first-pass/` holds the first complete render (the very first one
  had an animation on the fade's mask that, in an offscreen host, left the mask at the height it had before the words
  were measured, so the words were cut after two lines; that animation is gone and the fade's strength is now continuous).
  Refined after that first complete look: the rule is rounded, the words 600 points wide at most
  (was 620), the fade 40 points (was 32, which left a ghost of the next line), and a note being read keeps the room of
  one 17-point line (not 21) so a one-line note doesn't jump.
- ⏳ **Live, in a real window** (nothing here ran in one): dragging the header into Finder, a manuscript or a Markdown
  editor, and that the drag image is the header line and not something odd; double-clicking the header for Quick Look
  and that a single click does nothing; Quick Look and Show in Finder in the ⋯ menu of a note (and that a
  non-note's ⋯ has neither); that selecting words in the passage, ⌘C and Look Up still work inside the scroll view; the
  scroll itself, its indicator and the fade as the end arrives, with a trackpad and a mouse wheel; the card when a long
  session title wraps the header to two lines; VoiceOver reading the header ("Note, Plate reader QC, …") and then the
  passage once, with the rule skipped and the ⋯ items offered as actions; Increase Contrast (the rule's colour: the
  environment value can't be forced offscreen, so the choice is a tested function, `ShelfPassageText.ruleColor`); and the
  Shelf's text sizes (fixed points, so no Dynamic Type, as before).

## 2026-10-26, merging 1.0.6: OpenCode's five Shelf items, and Claude's legend in plain words

- ✅ **OpenCode's branch reviewed and merged** (`g/opencode-106`, nine commits: eight Sonnet 5.5, one Opus 5.5).
  - The tree was clean, and the privacy check over its whole diff came back clean.
  - Its captures looked right: a note's passage, Keep's "Claude's legend" row, and the tile's selection item.
  - Its own critique stands for later: a note's words show three times on its detail card (preview, title, passage).
- ✅ **Bold marks off a legend put in "Your legend"** (`ShelfClaudeLegendRules.unbolded`, used by the Shelf and
  Keep alike). Three new tests cover what comes off and what stays: significance stars, a lone star, snake_case,
  inline and fenced code. Five expectations changed from Claude's raw `**…**` to the plain words. The 177 legend
  and Keep tests pass.
- ✅ **A note's detail card says its words once** (`g/note-polish`, Sonnet 5.5). Merged after a look at its before
  and after captures: a quiet "Note · session · project · time" header, the passage as a quotation with a rule at
  its edge, and Quick Look and Show in Finder in its ⋯ menu.
- ✅ **A note, document or table isn't called a figure** when it's exported: "Export as PDF…" for one, "Export 3
  Items as PDF…" with one among the picks, and VoiceOver's action likewise. The card-menu test now picks by kind.
  The 126 Shelf and export tests pass.

## 2026-10-26, Capsid 1.0.6 (OpenCode): the Shelf searches inside notes, a note shows its passage, a menu for two files of one name, a tile's selection item, Claude's legend in Keep

Five changes on `g/opencode-106` (from main): the Shelf's search reads inside notes, documents and Claude's legend files
(`ShelfTextIndex`); a note's detail card shows its passage (`ShelfPassage`); two files of one name in a Markdown tile's menu
are asked about, newest first, in a native menu (`ShelfDocumentChoice`); Add Selection to Shelf in the page's menu for a
Markdown tile; and a Claude's legend row in Keep with Data and Code… (`ShelfClaudeLegendRules.reading`, shared with the Shelf).
Everything ran offscreen on made-up sessions, a made-up page (JavaScriptCore, as the figure menu's tests do), fake reads and
scratch Kept folders under the temporary folder: no window shown, no menu opened, the real Kept folder untouched, nothing read
under `~/.claude-science`, nothing launched, installed, merged or pushed.

- ✅ **The whole suite**: `✔ Test run with 4308 tests in 555 suites passed` (4,178 in 538 at 1.0.5).
- ✅ **One load flake, found and fixed**: `fiveHundredItemsWithAMadeUpReaderAreIndexedAndSearchedQuickly` took 16 s in the full
  suite under load, against 0.2 s alone: its budget for the reading was a speed check, which a loaded run misses. It is now
  relaxed to a guard against a stall, and the typing's budget (the search over what is read) still guards speed.
- ✅ **Offscreen captures**, light and dark, in `shots-106/` beside the worktree: `shelf-passage-short-*`, `shelf-passage-long-*`
  (and the `-small-*` window) for a note's passage, with the fade at the foot of the long one; `keep-sheet-legend-*` and
  `keep-sheet-legend-several-*` for Claude's legend row (one file; the best of several, with the detail that says so);
  `doc-tile-selection-menu-*` for a tile's page menu with the new item first in Capsid's group (a hand-drawn stand-in for the
  page's menu in a real WebKit view with the real script in its own world). The NSMenu for two files of one name is the
  system's and isn't drawn off screen; its lines are tested as text.
- ⏳ **Live, on the real page** (nothing here ran in the real Claude Science): that the real tile's markup is what the script
  expects (the preview region holds the file's words, and a selection inside it is wholly inside it), that the page's menu
  opens in time for the item to be placed first, that the selection is still there when the menu opens, and that it is kept
  on a real click on the item (and the words read once, within ten seconds), ending in a note with the right words.
- ⏳ **Live, two files of one name**: that the NSMenu opens at the pointer in the main window and not somewhere else, that
  choosing a line runs Add to Shelf, Keep with Data and Code… and Open as Reference on that file, and that closing it
  with Escape or a click away does nothing, over a real session with two different files called alike.
- ⏳ **Live, real history pages with legend files**: that the page of history around an answer's row lists the legend file
  under the reply that shows the figure, so Keep's row appears; the best of several is the right one; the kept folder's
  "Your legend" holds the figure's section of a real legend file.
- ⏳ **Live, search over a real Kept folder**: that a first search over hundreds of real items starts reading at once, finds
  more for a moment and settles, with no stutter in typing, and that notes, documents and kept legend files are found by a
  word inside them (with an accent, and with another case); that a Kept folder on a share or with files put away in iCloud
  is left alone; and the " · in its text" caption.
- ⏳ **Live, a note's passage with real notes**: that a long real note scrolls inside the detail card and fades at its foot,
  that its words can be selected and Copy puts the passage on the pasteboard as text, and that a note edited in another app
  shows the new words when the folders are read again.
- ✅ **Ask Another Model, a list of hundreds** (Settings → Another model): the model list keeps 1,000 names (`maxModels`, was 200;
  the 1,001st is dropped, a repeat or a too-long name doesn't use one up), and a made-up 466-name OpenRouter-shaped body reads whole.
  The Model pop-up became a text field with the system's `textInputSuggestions` (12 at most); `AnotherModelRules.matches` (every word,
  case and accents aside, the list's order, the limit) and `.choice` (what Return chooses: a listed name in the list's spelling, an
  id the list leaves out as typed, nothing from empty text or words) are pure and tested alone; the first model is still chosen when
  none is, or the chosen one is gone; an unlisted id is chosen, kept through the list and sent as the request's model. Mutations (break,
  see it fail, restore): cap back to 200, "any word" for "every word", accents not folded, the limit ignored, an unlisted id refused,
  and the first-model rule dropped. Captures `settings-ask-on-466-*` and `settings-ask-on-unlisted-*` in `shots-106/`; the suggestion
  list itself is the system's and isn't drawn off screen.
- ⏳ **Live, with a real OpenRouter key and address** (`https://openrouter.ai/api/v1`; nothing here ran against it): that the list of
  about 470 names is read whole; that typing narrows the system's suggestion list under the field and choosing a line fills the field
  with that id; Return on an id the list leaves out chooses it and the line says "Not listed by the address"; the real answer comes
  from the model chosen; and that the field takes focus and gives it up (the typed text is put back) without a stray keystroke.

## 2026-10-24, Capsid 1.0.5 released and installed

- ✅ Released as v1.0.5 (tag on 38522a8, "Capsid 1.0.5", by Sam with `gh release create`), marked Latest:
  `Bench.zip` with Capsid.app 1.0.5 (51) inside, 18,143,530 bytes, sha256 e2d7163ee69e0aff…. GitHub's asset
  digest matches the file built from that commit. 1.0.4 (7492fdd) was never published; its change is in 1.0.5's notes.
- ✅ Installed from that same build before the release (CDHash cd9e3565; the unzipped copy's signature checks and
  its CDHash is the same). "Signing in: with a code from claude-science url", and the usage read answered 4 s
  after launch.
- The whole suite before the push, with streaming, the Shelf's notes and document tiles and Claude's legend
  together for the first time: 4,178 tests in 538 suites pass.
- ⏳ **Live**: a real streamed answer, Add Selection to Shelf and a document tile's menu on the real page, and Use
  Claude's legend on a real figure.

## 2026-10-24, Claude's legend: the Shelf offers the legend file Claude made with a figure

When Claude makes a figure, its answer often makes a legend file too (`FIGURE_LEGENDS_final.md`, or a `.md` with the figure's
name). The detail card now offers it in one quiet line, **Use Claude's legend** · the file's name, and puts it in the legend
field. On `g/shelf-legend` (from 7492fdd). Everything ran on made-up sessions, a fake history page, fake reads and a scratch Kept
folder: no daemon, no window, nothing read under `~/.claude-science`, nothing launched, installed or pushed.

- ✅ **Finding the file.** The files of the answer that showed the figure are read as the reference reader reads them (one page of
  history around the README's `source_row`, `ReferenceRules.answers`, the files that aren't pictures). A candidate is an md,
  markdown or txt file, not empty and under 1,000,000 bytes, other than the figure, whose name has "legend" in it (any case) or whose
  stem is the figure's. Best first, at most six: stem match, a legend with the figure's stem or number in its name, a legend with no
  number, a legend that names another figure. No `source_row` (a last answer standing in), a document and a table: no offer; a page
  that can't be read is asked again, one that was read is asked once.
- ✅ **The card's offer.** Empty legend: "Use Claude's legend"; written (or typed and not yet saved): "Replace with Claude's legend…",
  which asks once and fetches nothing before the answer; several files: the name is a menu, best first; nothing while the field has a
  save waiting on the person, and nothing while it holds exactly what Claude's legend put in. A figure shelved alone has no legend
  field, so the line sits alone under a hairline there; after use the card shows its Files (the figure and Claude's file) and the field.
- ✅ **Only this figure's part.** A heading or a bold label at the start of a line that names the file name, the stem or "Figure N" /
  "Fig. N" for a number in the figure's name. "Figure 12", "Figure 20", "Figure 2A", and a supplementary "Figure S2" are not "Figure 2";
  headings in a code fence aren't headings; a heading that only names the figure is left out, one with words of its own opens the text;
  a bold label stays; a "**Figure 2.**" inside "## Figure 2" is one section; two equally plain sections mean none, and the whole file is
  used. At most 3,000 characters, cut at a paragraph, a line or a word, with "[Cut here: the rest is in FILE.]" as the last line.
- ✅ **Through the field's own save.** `ShelfLegendEditor.put` saves at once and takes the legend back whole if it can't (a README
  changed in another app: "Couldn't put Claude's legend in. README.md was changed in another app. Nothing was changed."; no draft
  left, the window's own line not added). `list` copies the file beside the figure and lists it (`KeptDisk.listFile`, role `legend`, new
  in `KeptRole`) in the editor's queue of writes, once for a version, a number for other bytes under the same name, never over
  another file, and the editor takes the new README as its base so the next edit isn't a false "changed in another app". The README
  with words under its title, with Windows line ends, with a byte order mark, and with all three comes out as the same README with
  only the legend and the file list changed (compared with `replacingLegend` then `updating` on the original, byte for byte).
- ✅ **Undo is the Shelf's pill**, eight seconds: the legend goes back to what it was (empty, or the words that were there, line breaks
  and all) unless it was edited since ("Your legend was edited since, so it was left as it is."). The copy of Claude's file stays,
  listed: nothing in a kept folder is deleted. Using it again after Undo copies nothing twice.
- ✅ **A legend file isn't data or code.** `KeptRecord.keepsDataOrCode`: Keep with Data and Code… stays in ⋯ after a legend file is
  listed, and a legend-only folder never beats a real keep for the same figure in `ShelfRules.items`.
- ✅ **Tests** (75, all new): `ShelfClaudeLegendRulesTests.swift` (39: candidates, numbers, figure references, parts, the cap, the
  offer's states, sentences, the answer's files from a page), `ShelfClaudeLegendTests.swift` (35: look and its cache, the whole use on
  each README shape, the pill, a written legend asked first, Undo three ways, the file once, a README changed elsewhere, a save waiting,
  a file that can't be had, a second ask, `KeptDisk.listFile`, the role's round trip), `ShelfClaudeLegendSnapshotTests.swift` (captures).
- ✅ **Mutations** (break the fix, see the tests fail, restore; each one alone, then `git checkout`):
  1. a number match that ignores the number: 16 tests fail (the section ones, and every use that picks a section);
  2. no question before replacing: `aWrittenLegendIsAskedAboutFirst…`, `wordsTypedButNotYetSavedCountAsWrittenToo`;
  3. the README written from the record instead of by `updating`: the five-shape test (all five shapes, the plain one too) and the
     editor-keeps-the-base test;
  4. the editor not taking the new README as its base: five tests (a later edit saying "changed in another app");
  5. Undo over an edited legend: `undoLeavesALegendThatWasEditedSince`;
  6. candidates worst first: eight tests;
  7. any file making a folder "kept with data and code": two tests;
  8. no cap: four tests;
  9. a put-in over a save waiting on the person: found missing (nothing failed), so `aSaveWaitingOnThePersonIsNeverTakenOverByClaudesLegend`
     was added; with both of its guards removed it fails;
  10. no reload after a put that failed: `aREADMEChangedInAnotherAppIsNeverWrittenOver…`;
  11. a figure number not ended by a non-letter: `aFigureReferenceMatchesOnlyItsOwnNumber` and `aFigureReferenceIsFigureOrFigNumberAndNotAPanel`
      (the first version of that test passed under mutation 1 as well, because two wrong sections made the same "whole file"; it
      now has one wrong section at a time).
- ✅ **Captures** (offscreen, light and dark, `ShelfClaudeLegendSnapshotTests` with `CAPSID_SNAPSHOT_DIR`): the offer for a figure
  shelved alone, after use (the field, the Files, the pill with Undo), the offer to replace, and the several-files line. The open menu
  and the question are the system's and can't be drawn off screen; the menu is a hand-drawn stand-in in the capture, the question isn't drawn.
  The pill fits one line at 900 points (about 95 characters; at the narrowest window it takes two). Against "gorgeous and minimal":
  the line reads as one quiet phrase in the card's own quiet-link register (muted, underlined, the source line's dots, a small muted
  chevron for the menu), spends no clay, and nothing competes with Show Where It Came From. The one wart is the Markdown marks in
  Claude's text (`**Edge effects.**`), which show in the plain field as they are written: a trade-off chosen, not an oversight (the field
  is plain text, the README is Markdown, and stripping would drop Claude's emphasis from the file too); easy to change if Sam wants it.
- ✅ **The whole suite**: 4,015 tests in 518 suites pass (3,940 in 509 before), `✔ Test run with 4015 tests in 518 suites passed`;
  no failure in the run, no flake.
- ⏳ **The one time-sensitive test** is `thePillWithUndoStaysAsLongAsARemovalsAndAFailureTwiceAsLong` (a 1 s lifetime, margins of 0.3 s and 0.9 s).
- ⏳ **Live**, with a real answer, a real legend file and the real daemon: that a real answer's history page lists the legend file
  under the reply that shows the figure (the offer depends on `_artifact_refs`, and on the row being on the page: a very long turn can
  drop it from the page); that real legend files are headed and labelled in the ways the rules read ("**Figure 2 | Title.**",
  "FIGURE 2", a table of contents first); the system's menu and question; the pill at the narrowest window; and that this Capsid's
  README with `role: legend` is not read by Capsid 1.0.4 (its folder leaves that Shelf); what browsing costs now (each figure with a
  `source_row` reads one page of history, 50 rows at most, the first time its card is shown, then not again in that window: arrowing
  through a shelf of hundreds); and whether the daemon, asked for rows `row - 24` to `row + 25` when the row is near the history's end,
  answers with the `from` the reader checks (it has never been asked for a page that runs past the end). `ShelfLegendEditor.show()`
  now waits for a write under way before it reads the README (so what it reads is what the write left); the older legend tests all
  pass with it.

## 2026-10-24, the Shelf's two new ways in: a Markdown tile by its name, and selected words as a note

On `g/shelf-text` (from 7492fdd). Everything ran on a made-up page (JavaScriptCore, as the figure menu's tests do), made-up
sessions, lists, shelves and toasts, and scratch Kept folders under the temporary folder: no daemon, no window shown, the real
Kept folder untouched, nothing read under `~/.claude-science` but the served bundle's `web-dist` (to see what a tile shows),
nothing launched, installed or pushed.

- ✅ **What a tile with no picture shows, read in the 0.1.70 bundle** (`ArtifactTile-DmtoiOPx.js`, `index-DhEuR7nq.js`; read,
  not run). The tile's wrapper has no attribute, no id and no data of its own; its right-click handler is on that wrapper. It
  holds a `<header>` with the file name as the text of its first span (`Us(filename)`, no test id), the "More actions" button
  (`data-testid="artifact-actions"`), and a body, `data-testid="artifact-preview-region"`. A card in the Generated tray
  (`data-testid="turn-tray-card"`, its wrapper has the handler) has a preview and a label,
  `data-testid="middle-truncated-filename"`, whose `title` is the whole sanitised name and whose text is cut in the middle.
  Neither carries an artifact or version id. So the script reads the name.
- ✅ **The script, for a file with no picture** (`DocumentTileScriptTests`, 25 tests, several with a case for each place): the right-click on a
  tile's words, its preview region, its header's name, the version stepper after it, its More actions button, a link out in its
  words, a card's words, its label and its preview each place Capsid's rule and four items in the page's menu, and a click on
  each posts `{action, kind: "document", name}` with no `version` and no `url`; the name is the last part of a path, one line,
  no control characters, cut at 300; a tile with a blank name, a card with no label, a header of the page's own, a tile's
  header without its button, a preview region with no headered tile around it and a pop-up over a tile get nothing; so does
  a made-up (untrusted) right-click and a made-up click on an item; and a page that is not `/projects/<p>/frames/<session>`
  (six addresses) gets nothing. A link with a version in a tile still names its version; a figure still its version. The
  trace says `figure-document` (and `figure-link → version-none → figure-document` for a link out in a tile) and every word
  is one Swift reads. The old test that said a notes card gets nothing now says a header of the page's own gets nothing.
- ✅ **Name to version** (`ShelfDocumentResolutionTests`): one match, none, an exact and whole name (another case, a part of a
  name and a trailing blank are no match), one artifact at several versions (the latest time; no time is older; a tie goes to
  the later in the list), and **two different artifacts of one name are `several`, whether listed with artifact ids or without**.
  **Decision: refuse**, with "This conversation has more than one file called “notes.md”, so Capsid can’t tell which you
  meant. Results lists them." Picking the newest would shelve the wrong file as often as the right one, and the toast has no
  room to say which was taken. The daemon's list names an artifact once, by its latest version, so two files of one name are
  two artifacts, and a tile stepped back to an older version of a file is added at the latest.
- ✅ **Each action on the resolved version** (`ShelfDocumentActionTests`): Add to Shelf gets the listing's own entry (version,
  artifact, type, size); Keep with Data and Code… the sheet with that version selected, and the daemon's facts when it has them;
  Open as Reference that version; none, two, an unreadable list and a page that isn't a session's are a sentence and nothing
  else; Show in Results needs only the session and asks for no list; the list asked for is the main window's session's.
  `ShelfDocumentMessageTests`: the message's shapes and everything that is no choice, a document's message is no figure's and
  the other way round, and the sender checks (main frame, main web view, the daemon's origin; anyone else's message runs
  nothing).
- ✅ **Add Selection to Shelf, the page's half** (in `DocumentTileScriptTests`): the right-click inside a selection adds
  `selected: <characters>` to its message, a control-click too, with a figure's or a link's message as well; **the words are in
  no message and no trace** (checked on the posted JSON); no count when the selection is empty or blanks, when the button
  wasn't down (a menu from the keyboard), when the selection was made by the right-click itself (WebKit selects the word under
  the pointer on a right-click outside the selection: the script keeps the selection at button-down and compares), when the
  right-click is not trusted, or on a page that is not a session's. The word selected before and left alone counts.
- ✅ **Add Selection to Shelf, Swift** (`ShelfSelectionMenuTests` and `ShelfSelectionActionTests`, 22): the count's reading and its second of freshness;
  the item goes after WebKit's Copy, or at the end after a rule; it is not offered with no selection, a stale count, off a
  session's page, from a message that isn't the main window's, beside a tab's, a figure's or its own item, or twice; choosing
  it shelves; the wiring in `willOpenMenu` is after the tab and figure groups; and what choosing does: the words are asked for
  at 32,000 characters, trimmed, cut (31,999 once the blank at the cut goes), a toast says adding, a duplicate or a failure is
  the shelf's sentence, nothing selected any more is a sentence, a page not on a session reads nothing, and the toast holds the
  title and not the rest of the words.
- ✅ **The note** (`ShelfSelectionNoteRuleTests`, `ShelfSelectionNoteAddTests`, on the real `KeptDisk` in a scratch folder with a
  stand-in Trash): the title is the first eight words of the first line with any (64 characters, marks off, "/" and ":" blank,
  an ellipsis when the line goes on, "Note from <session>" for a passage with no words); **the README is pinned byte for byte**
  (pinned zone and locale) and so is the folder on disk (`note.md` is the words and a line end, `README.md` is what the rules
  make, nothing else in the folder); it parses and renders to the same bytes, and the disk reads it as any kept folder; the
  Shelf makes it one document item with no version, its first lines as a card, no Keep with Data and Code…; the search finds
  it by its first words, its session and its project and the Documents chip counts it; the PDF page is a document's, its words
  as text; Undo (the folder is in the Trash, off the shelf and the count, through the toast's own Undo too); the same words
  from the same session are "Already on your shelf"; two asks at once make one note; two notes that begin alike get a dated
  folder; a Kept folder that isn't there is the disk's sentence naming the title and not the words; and a scan of the source
  for any logging line that interpolates the words.
- ✅ **Decisions.** *Duplicates*: refused, above. *The title*: the first words (not "Note from <session>", which the card's
  caption already says and every note of a session would share, and the search finds the note by the first words);
  "Note from <session>" only for a passage with no words. *The reply*: **not named**: the page does not say which reply holds a
  selection, and the selected words are rendered text where the history has Markdown, so finding the reply would be a guess;
  the README says the session and the time. *Search*: only the title, the session and the project, because the Shelf never
  reads file bodies; the passage is not put in "What Claude said" to be searched, since it may be the user's own and the PDF
  would then print it twice. *Show in Results* does not look up the file.
- ✅ **Mutations** (break the fix, see the tests fail, restore; eleven at once in one build, each caught by its own tests):
  exact name match widened to "contains" (`aNameIsMatchedWholeAndExactly`); the several-files refusal removed
  (`twoDifferentFilesOfOneNameAreTwoAndNeitherIsPicked`, `twoFilesOfOneNameAreRefused…`, 5 expectations); the trust check
  on the right-click removed (`aMadeUpRightClickStartsNothingAndEndsNothing`, `aRightClickTheBrowserDidNotMakeStartsNothing`,
  `anotherRightClickBeforeTheMenuEndsTheFirstOnesTrace`); the selection compared with the one at button-down removed
  (`theWordTheRightClickSelectedItselfIsNotAPassage`); the session test of the item removed (`notOnASessionsPageNoItem`,
  `notTwiceAndNotInAMenuWithCapsidsItems`); a document's message allowed to carry a version (`aFiguresMessageIsNotADocuments`);
  the session link taken out of the README (`theReadmeIsExactlyThis`, `aNoteIsAFolder…`); the duplicate check made to compare
  nothing (`theSameWordsFromTheSameSessionAreOnTheShelfAlready`); the sender check on the message made always true (6 tests:
  `aChoiceFromAnyoneElseIsNothing`, `aMessageFromAnyoneElseIsNothing`, `aCountFromAnAcceptedMessageIsCleared…`,
  `theMessagesTheMacsMenuHearsAreStillHeard`, the trace and unplaced ones); the 32,000 cut made 32,001
  (`aLongSelectionIsCutAtTheLimit`, `theWordsAreCutAtThe32000thCharacter`); Open as Reference given another version
  (`openAsReferenceNamesTheVersionOfTheFileFound` and the figure's). 44 expectations failed in 25 tests; the sources were
  restored from git and rebuilt.
- ✅ **Captures**, offscreen, light and dark (`shots-shelftext/`): `shelf-note-*.png` (a note among the demo's cards with its
  detail, the Documents chip with the shorter note selected, the narrowest window) and `doc-tile-menu-*.png`,
  `doc-card-menu-*.png` (a tile's and a card's page menu with Capsid's group, in a real WebKit view with the real script in its
  own world: the right-click, the group above the red Delete, a click on Keep with Data and Code… posting the name, the page's
  own Escape closing the menu). Critique: the note card reads as a document card, the first words as its name, nothing set it
  apart as a note, which is the point; the detail is sparse (name, session and project, three controls) and shows no time,
  where the card's caption does. One thing is plain: the card's first lines run a bulleted list into one paragraph, as `ShelfPeek`
  does for any Markdown, and a selection from the page's list has no bullets anyway.
- ✅ **The whole suite**: 4,040 tests in 518 suites (3,940 in 509 before: 100 new in nine suites), `✔ Test run with 4040 tests in
  518 suites passed`. The first full run had one failure, `AskEntryPointTests.theMainWindowsRightClickMenuHasNoAskItemAnyMore`:
  it reads `WebContainer.swift` for the names of Ask Another Model's old selection read (`SelectionScript`,
  `selectedText(limit`), which this change had reused for its own; renamed (`SelectedWordsScript`, `selectedWords(limit:)`), no
  test touched. No load flake in either run.
- ⏳ **Live, on the real page only** (nothing here ran in the real Claude Science): that a right-click in a Markdown tile's body
  or on a Generated card of a Markdown file opens the page's "Artifact actions" menu and Capsid's group lands in it; that the
  tile's header has the name as its first span when the tile is open as a tab or in the split view (the bundle's `_o` crumb,
  drawn when a tile was opened from a folder, is a shape not read); that the right-click on a word in a reply lets WebKit's
  Mac menu open with Copy and the new item after it, that the selection is the same at the menu as at the button-down inside
  a selection and not outside it, and that the words are still selected when the item is chosen; that a tile stepped back to an
  older version is added at the latest; and a real selection across a list or a table, as the page's own `getSelection()`
  words it.

## 2026-10-24, Ask Another Model streams: the answer fills in as it is written

The answer used to come whole, behind a spinner of up to two minutes. It now streams (`"stream": true`, server-sent
events), on `g/ask-stream` (from 7492fdd). Everything ran on made-up sessions, a fake `URLProtocol` and a made-up key:
no real network, no key entered, no daemon, nothing under `~/.claude-science` read, no window opened, nothing launched,
installed, merged or pushed.

- ✅ **The stream, cut every way** (`AskModelStreamTests`, a fake whose body the test feeds piece by piece, each its own
  `didLoad`): the same made-up stream (a comment, a role chunk, reasoning under both `reasoning_content` and `reasoning`,
  unknown fields `event:` `id:` `retry:`, words with a 2-, 3- and 4-byte character, a finish chunk, `[DONE]`) is read to
  the same text from one byte at a time, every 3 and 11 bytes, every multi-byte character cut in two, with CRLF and with
  lone CR line ends, and in one piece. The reasoning is told once, first, and is never in the text; words are heard
  while the stream is still open (so `URLSession.bytes` does deliver in-process as it comes, not at the end).
- ✅ **A bug found by a test, not by reading**: Foundation's `bytes.lines` (the first plan) also breaks at U+2028, U+2029,
  U+0085, U+000B and U+000C, all valid raw inside a JSON string, so a chunk holding one was cut in two and lost without
  an error. Replaced by `AskStreamLines`, which cuts at LF, CR and CRLF only (a probe confirmed the difference).
- ✅ **Endings**: an `{"error": …}` chunk mid-stream is a failure with the words kept and none of the server's own words
  shown; one before any word has no words; a stream that closes after `[DONE]` or a `finish_reason` is finished and one
  that closes without either is cut off (words kept); a connection lost after a chunk is "closed the connection", at once
  it is "no network"; reasoning and then `[DONE]` is no answer; an answer past 4 MiB stops with its words kept.
- ✅ **A server that ignores `stream`** and answers JSON (`application/json`, with and without a charset) is read as it
  always was and tells the window nothing piece by piece; JSON that is no answer is "not an answer"; a stream sent under
  another content type is still read, whole. A status before any byte (401, 403, 429, 500, 404, 302) keeps its sentence,
  and its body, which is built to read as an answer, is never read as one. The redirect test is unchanged and green.
- ✅ **Deadlines** (on `ManualClock`, no real waits): the first chunk has 120 s and the whole ask 600 s from the start;
  a reasoning chunk meets the first and starts the 60 s; a `:` keepalive before any chunk does neither; every chunk
  (words, reasoning, a role or usage chunk with none) and, once one has come, every keepalive starts the 60 s over (a new
  wait each time, the old one gone, one waiting); 60 s with none is "stopped coming" with the words kept; 600 s ends it
  while chunks still come; after any end no deadline is left waiting and nothing is heard. Each ends the request itself
  (`stops == 1`) and asks once.
- ✅ **Cancel** mid-stream returns `.cancelled` with the words that came, stops the request, hears nothing after, and
  leaves no deadline; before the first byte it returns at once with none; a task cancelled before it began does not hang.
- ✅ **The window's model** (`AskModelStreamingWindowTests`, a scripted ask): asking → thinking (the flag, not the words)
  → streaming → answered, with the caption, the seconds and the log; spaces alone are no answer yet; Copy and Send do
  nothing while words arrive and both work on the finished answer; Cancel, each failure and each deadline keep their words
  drawn in full, Copy works and Send is dim with its reason (`.partial`), "Stopped after 14 s" / "Cut off after 70 s"; a
  failure with no word is one centred sentence; Ask again starts clean; closing the window ends the stream.
- ✅ **The drawing**: the first words at once, then one drawing per tenth of a second (fifty words in one instant: one
  drawing waits, then one draws them all; a hundred words over a virtual second: 9 to 12 drawings, none sooner than 100 ms
  after the one before); a drawing that takes 80 ms makes the next wait 240 ms, capped at a second; the end draws every word
  and cancels the drawing that was waiting.
- ✅ **Following the end** (`AskScrollFollowTests`, the rule on its own: a window cannot be scrolled here): growth with the
  reader's place unchanged is growth and not a scroll up (the trap); scrolling up stops following and growth then leaves
  the reader alone; scrolling back to the end follows again; a wobble, a text drawn shorter at the end, and a foot that
  shrinks the window below the text are not scrolls up; a text shorter than the window has nothing to follow.
- ✅ **Offscreen renders**, light and dark, in `shots-stream/` beside the worktree (`CAPSID_SNAPSHOT_DIR`; the SwiftUI
  content drawn with `cacheDisplay`, as before): ready, asking, **thinking**, **partway** (short, and longer than the
  window), **stopped**, **cut off**, answered, and a streamed answer finished, failed. Looked at against "gorgeous and
  minimal": one clay action in every state (Cancel while it comes, Ask when it ends); the line over the words reads
  "Answering…", "Answered in 9 s", "Stopped after 14 s" or "Cut off after 70 s" in the same place, so nothing moves when it
  ends; "Thinking…" is the asking stage with one word changed; no new control; a stopped answer's foot is Copy, one muted
  line and a dim Send, as "too long to send" already is. Kept as they are: the two-line clay sentence after a cut-off
  (it is the failure's own words), and the Cancel pill as it was. What the renders cannot show: the text running to the
  foot of a long answer and the view following it (an offscreen scroll view stays at the top), and the title bar's glass.
- ✅ **A selection stays while the text grows** (`AskStreamSelectionTests`, a hosting view drawn offscreen): a reader's
  selection is where it was after a longer text is put in (`ReferenceTextView.keepsSelection`, on in this window), is
  dropped when the new text doesn't reach it, and where the view doesn't ask for it a new text starts unselected as ever.
- ✅ **Mutations** (break it, see the tests fail, restore; each run on the focused suites, 145 tests):
  - the line splitter cut at Unicode line ends too, as `bytes.lines` does: 2 fail (the raw U+2028 stream and the line
    rules);
  - a chunk no longer starts the minute over: 3 fail (stalled, the reasoning chunk, every chunk), and the run waits out
    URLSession's own 120 s;
  - reasoning read as words: 5 fail (the cut stream, reasoning-only, reasoning's own rules, a stream under another type,
    the reasoning chunk's deadline);
  - no throttle on drawing: 5 fail (the first words, a second of words, the end, stopping, the slow drawing);
  - a partial answer can be sent: 2 fail (stopped, failed);
  - an error chunk ignored: 2 fail (with and without words before it);
  - an error chunk dropping the words: 1 fail;
  - Cancel dropping the words: 1 fail;
  - growth with the reader's place unchanged read as a scroll up: 4 fail (the trap, and the three that follow from it);
  - a clean close without `[DONE]` or a finish reason counted as finished: 1 fail;
  - a keepalive meeting the first-chunk deadline: 1 fail;
  - the request saying `stream: false`: 1 fail;
  - the drawing never waiting longer for a long answer: 1 fail;
  - no ten-minute cap: 1 fail;
  - the selection not kept: 1 fail.
  Each one restored; the tree was clean after (`git status`).
- ✅ **The whole suite**: 4,003 tests in 520 suites pass (3,940 in 509 in the entry before: 63 new tests, 60 of them in the two stream
  files and 3 for the selection, and 11 suites), `✔ Test run with 4003 tests in 520 suites passed`. No flake this run.
  The `g/longer-messages` entry's one flake, `LabInsightsGateTests.bothOfTheFailureCardsSwitchesMustBeOn`, did not
  recur. `--jobs 1`, one swift process at a time throughout.
- ⏳ **Live, with Sam's own key** (nothing here has met a real Abliteration.ai): that it really streams (the first word in
  seconds through `URLSession.bytes` and whatever sits between), and the exact chunk shape: `delta.content`, whether the
  reasoning is `reasoning_content` or `reasoning` or absent, a role chunk or a usage chunk, `[DONE]` and a `finish_reason`
  (a stream that closes after neither is shown as cut off, with its words), the `Content-Type`, what a mid-stream
  `{"error": …}` looks like and whether a `:` keepalive is sent; the scroll following on a real trackpad and wheel (the
  rule is tested, the scroll view is not), and that a selection survives the redrawing in a real window; and whether two
  minutes to a first chunk, a minute between chunks and ten in all suit the real model.

## 2026-10-24, messages made on the Mac may be 32,000 characters (the phone's stay at 4,000)

Every message Capsid sends into a session shares one send path, and its cap (4,000 characters) was set for the
phone's small request bodies; the Mac's own senders reused it, so a long message couldn't go from the Mac. On
`g/longer-messages` (from ad0a315). Everything ran on made-up sessions, a fake page and fake writes: no daemon, no
window, nothing read under `~/.claude-science`, nothing launched, installed or pushed.

- ✅ **One limit for the Mac, one for the phone.** `RemoteActionRequest.macMessageLimit = 32_000` beside
  `messageLimit = 4_000`. The Mac's: Ask Another Model's Send to Session (`AskRules.sendable`, its "Too long…"
  sentence, `AskModel.message`), Quick Start (`QuickStartFlow.textLimit`, and so the panel, the menu bar's "Start a
  session…" field, Services' selected text, Shortcuts, recipes and their Settings line) and the reply window's changes
  to a plan (`checkedPlanFeedback`, `QuestionReplier.Sentence.feedbackProblem` under the field). The phone's, as they
  were: `RemoteActionRequest.parse`, `NewSessionRequest.parse`, `PhotoRequest.textLimit`, the phone page's `maxlength`
  and counter, and the 8 KB and 16 KB bodies. Since You Left's sheet sends a chosen answer (1,000 characters), not a
  message, so it is unchanged; `FailureReason.fullLimit`, the reader's 4,000-character reply, the live text's
  4,000 and the phone page's 4000 ms timer are not message limits.
- ✅ **A second 4,000 sat in the page.** Raising the Swift caps alone would have changed nothing: every Mac write goes
  through `benchBuildWrite`, whose `request()` refused plain text over 4,000, so a 4,001-character Mac send came
  back as a write that wasn't made ("Couldn't send"). It takes 32,000 now, for a message, a new session, plan changes
  and the words before Quick Start's file lines; a photo's text (`attachment: true`) stays at 4,000 there. It is not
  what stops the phone, whose bodies are refused by their parsers before a write is built (tested below).
- ✅ **Nothing else in the path assumed a length.** The write is `callAsyncJavaScript` arguments and a `fetch` body,
  with the 20-second deadline unchanged; a sent message is matched by `_intent_id` first, whatever its length. The
  words fallback sees only the reader's 2,000-character cut of a turn (ended "…"), so 4,001 and 32,000 characters
  are alike to it: a lost write of a long message whose turn has no intent id settles "Not sure", never "sent" and never
  "didn't go through" (`LongMessagePathTests`). A turn read whole is cut at 20,000, not refused. Claude Science's own
  API may cap a message's length: not known, not looked into (its files stay unread).
- ✅ **Tests** (`LongerMessagesTests.swift`, new, 19 tests, and 6 more at the end of `QuickStartFlowTests.swift`; others edited where they pinned 4,000 for a Mac sender):
  - the two constants, and the phone's routes still refusing 4,001 (message, new session, photo text), also refusing
    32,000, with their bodies and the phone page's `maxlength 4000` and counter as they were;
  - the page builder, for a message, a new session, plan changes and the two file-line kinds: 4,001 and 32,000
    build, 32,001 doesn't (characters, not bytes; an astral character is one; a reference is refused at any length);
    a photo's text still 4,000; the very page script with a fake `fetch` posts all 32,000 characters to `/api/request`
    and the project's request (and a 32,001 never leaves the page);
  - the shared path with a fake write: `respond` hands the writer a 32,000-character message and plan change whole,
    the phone's `act` takes 4,000 and answers 400 to 4,001 and 32,000 with nothing written;
  - each Mac sender at 32,000 and 32,001: Ask (`sendable`, `unsendable`'s "32,031 characters; the most is 32,000",
    `AskModel.message`, and the model end to end through `RemoteSessions`: the write carries all 32,000, one more
    sends nothing), Quick Start (`check` for both targets, a new session, a message, with files, one over uploads
    nothing; the menu bar field's request through the flow's check; recipes; Services' text cut at 32,000) and the
    reply window (`checkedPlanFeedback`, the line under the field, the replier sends the whole text).
- ✅ **Mutations** (break the fix, see the tests fail, restore):
  - `macMessageLimit` back to 4,000: 19 tests fail across every Mac sender and the path tests (the listings were
    first cut at 80 lines; both of these were run again whole);
  - Ask's three uses, Quick Start's `textLimit` and `checkedPlanFeedback` back to `messageLimit`, with the phone's
    `parse` and `NewSessionRequest.parse` widened to the Mac's, all at once: 21 tests fail, the Ask, Quick Start and
    plan-change ones on their own tests, and the phone's 4,001 tests (`RemoteActionBodyTests`'s old one,
    `aNewSessionsBody`'s old one, and `thePhonesRoutesStillRefuse…` and `thePhonesRouteTakes…` here: a 4,001-character
    body would otherwise parse, write and answer 200);
  - the page's 32000 back to 4000: five page-builder tests fail, and no sender-level test does, so the two layers are
    pinned apart;
  - a photo's room widened to 32,000, `PhotoRequest.textLimit` widened and the line under the field's limit back to
    4,000: the photo, the phone and the reply-line tests fail.
- ✅ **The whole suite**: 3,940 tests in 509 suites pass (3,909 in 505 before), `✔ Test run with 3940 tests in 509 suites
  passed`. The first full run had one failure, `LabInsightsGateTests.bothOfTheFailureCardsSwitchesMustBeOn` (its two
  switch expectations, nothing near a send), which passed alone and in the full run after it: a load flake, not this
  change.
- ⏳ **Live**: a real 32,000-character send to a real session (the daemon's own cap is unknown, and a row it holds too
  big to send reads as a placeholder), and typing that much into the reply window's field.

## 2026-10-24, Capsid 1.0.3 released and installed

- ✅ Released as v1.0.3 (tag on 9912039, "Capsid 1.0.3", by Sam with `gh release create`), marked Latest:
  `Bench.zip` with Capsid.app 1.0.3 (49) inside, 17,979,550 bytes, sha256 df8b74c03de216ab…. GitHub's asset
  digest matches the file built from that commit.
- ✅ Installed from that same build before the release (CDHash 477f0fdb; the unzipped copy's signature checks and
  its CDHash is the same). "Signing in: with a code from claude-science url", and the usage read answered 4 s
  after launch.
- The whole suite before the push: 3,909 tests in 505 suites pass.
- ⏳ **Live**: Ask Another Model's item in the real model menu, the toolbar button opening the window, and the title
  bar at 900 points with an update on offer.

## 2026-10-24, Ask Another Model moves: a toolbar button and an item in Claude Science's model menu; the right-click item goes

Sam turned the feature on and couldn't find it: he looked among the models in Claude Science's own model menu, and
found the Mac's right-click item on the conversation odd. Two new places, the right-click item removed (File's item and
the reference window's right-click as they were), on `g/ask-place`. Everything ran on made-up pages, a made-up key
folder and made-up sessions; no daemon, no real key and nothing under `~/.claude-science` but the web bundle's files was
read, nothing was launched or installed, and the key was never entered.

- ✅ **The model menu's markup, read from the 0.1.70 bundle** (`web-dist/assets/index-DhEuR7nq.js`, with
  `EffortControl-BLxh4RvT.js` only the effort control beside it, and `index-rmOZ0wut.css` for the look). The picker beside
  the message box is `toe` (the plain list, its popup `data-testid="model-selector-popup"`) or, with the catalog served,
  `M0e` (`ModelSelector`, its popup `data-cds="ModelSelector"`, which its button carries too, so the script matches
  `[role="menu"]` with it). Both are the design system's Base UI menu: a `role="menu"` popup, in it the `Ame` wrapper's
  scrolling list (`data-cds-sheet-scroll`), in it a `role="group"` of models (`menuitemradio`, a div with the item
  classes, `pR`), a `role="separator"` and the "More models" and effort rows (`menuitem`). The composer is
  `[data-testid="composer"]` round a `[role="textbox"]` contenteditable (`z9`) and the picker's test id. The effort and
  "More models" submenus are `ut.Popup` with the default `data-cds`, so they are left alone.
- ✅ **The item in the model menu, against a made-up page** (`ModelMenuScriptTests`, 35 tests, `FakeModelPage` on
  `FakeFigurePage`'s small DOM, now shared as `FakeFigurePage.dom`): a real pointer-down, Enter, Space or an arrow on the
  picker (the button, or the wrapper round it, or something inside) starts one two-second watch; the answer "may I?" and
  the popup come in either order; the rule and one item go last in the list of every shape the bundle draws (the plain
  popup, the catalog's, with a header above the list, with a closing note, with one model and no rule); the item is a
  div with `role="menuitem"` and the first item's classes less the page's second-line padding (the "More models" row's,
  when there is no model), the page's own rule's classes (its usual ones when it has none), and nothing of the page's
  words (the fake throws on a read of an item's text, as the figure menu's does); it lights under the pointer; a click
  posts the draft, stops the watch and the page's own Escape closes the popup, with the pointer-down outside it 80 ms
  later when Escape is ignored; the draft is the message box's text (a line break for a `<br>` and for a block after
  the first, a mention chip as it shows, not a dictation not yet kept or an upload's chip, trimmed, cut at 32,000,
  empty when there is none) of the composer the pressed picker sits in; made-up (untrusted) presses and clicks are
  ignored; a no from Swift, or an error, leaves the popup alone, ends the watch and says nothing; no answer at all
  leaves it alone and says "refused" once; no popup in two seconds is "menu-none" and no breadcrumb; a menu that is
  not the picker's, or the picker's with no list or no item, posts `{unplaced}` at two seconds and is left as it was;
  a node with the picker's `data-cds` that is not a menu is not the menu; nothing is watched until the picker is pressed
  and the watch is over at two seconds, at two minutes after the item went in, when the popup is pressed shut (and the
  click that ends that press starts nothing: the first cut re-armed on it, which the first test never sent), or when another press comes first or one anywhere else before the popup did (so a menu that opens for another
  press is not a miss of the picker's); a list drawn again, replaced, or with a late item of the page's after ours gets the group
  back last; the script does nothing off the daemon's pages or without its handler, and holds no `fetch`, `innerText`,
  `innerHTML`, `.click(` or write to the message box.
- ✅ **The Swift side and its sender checks** (`ModelPickerMenuTests`, 14 tests): each message's shape (`armed`, `ask` with
  a draft, `unplaced`, `trace`), a draft trimmed, cut at the question's limit and nil when blank; a trace's words
  kept to the script's own and every word the script can say is a step; only the main web view's main frame on the
  daemon's origin (and port, over http) is heard, and the handler's wiring (`isMainFrame`, `message.webView === webView`,
  `isDaemonOrigin`, a reply even from a proxy that lost its menu) is read from the source; a message from anyone else is
  nothing and the answer is no; the answer to a press is whether the item is wanted now, and a choice opens the window
  only while it still is; `{unplaced}` leaves one breadcrumb (`modelMenuNotUnderstood`, feature `modelMenu`) and its
  fixed line; no draft reaches a log line; and the container keeps the menu (below).
- ✅ **A bug the real-WebKit run found.** The message handler's proxy holds the menu weakly (as the tab and figure
  menus' do), and the first cut of `WebContainer` let go of its `ModelPickerMenu` at the end of `init`: every press was
  answered no, and no test of the script could say so. The container keeps it (`private let modelMenu`), and a
  source check says so.
- ✅ **The toolbar button** (`AskEntryPointTests`, +5 and one removed): the button and File's item are there only while the
  switch is on with a key (off, or on with no key: neither), on only with a session in the main window (dim with none,
  with a page that is not a session's, and in a demo), one click opens the window once, and switching off or removing the
  key takes it away, in one `AskCommands` (made from a made-up model and a made-up stream of addresses); the button is
  drawn like Results' (`ReadoutButtonStyle`, a symbol that exists, a help line that starts with its name and a colon,
  the label "Ask Another Model" for VoiceOver); the toolbar holds the condition around the item, after the fixed
  spacer and before Results. The readout style draws a disabled button as it does an enabled one, which showed in the
  first render, so the glyph dims itself (35%).
- ✅ **The right-click item is gone**: no `askMenu` hook in the main window's web view or its menu subclass, no
  `askFromPage`, no selection script (and its test), and the reference window still has its item
  (`AskMenu.insert` stays, without its check for a tab's or a figure's menu, which only the main window had).
- ✅ **The Compat suites pass** with the new script, its ten inventory entries (the picker, the popup, the list,
  the items, the rule, the composer, the message box, the two chips and Escape), the new files in both lists of files
  that read the page's markup and run a script in it, and `[role="menu"]`'s entry saying the model menu's watch uses it too.
- ✅ **Real WebKit, when asked** (`ModelMenuSnapshotTests`, `CAPSID_SNAPSHOT_DIR`; offscreen, borderless, never shown): the
  real script (only the two trust checks lifted) and the real `ModelPickerMenu` handler in a `WKWebView` on a made-up
  page with the bundle's classes and the stylesheet's values, light and dark: the press, the question and its answer
  through the real reply handler, the item in the popup, the pointer on it, a click and the draft reaching `run`, the
  page's Escape closing the popup; a no from Swift leaves the popup as it is; a second web view that shares the controller
  (as a pop-up does) is not the main one and gets no item, while the main one beside it does.
- ✅ **Offscreen renders**, light and dark, in `shots-askplace/` beside the worktree (the title bar by `cacheDisplay` of a
  stand-in with the real Ask, Results and Shelf buttons on a stand-in for the glass, which an unshown view leaves blank;
  the menu by a real WebKit snapshot): `titlebar-with-ask`, `titlebar-ask-dim`, `titlebar-without-ask`, `titlebar-close`,
  `symbols` (the glyphs it was chosen from), `model-menu` and `model-menu-hover`. Looked at against "gorgeous and
  minimal": the button is one glyph in the capsule Results has, the same height, nothing added to say what it is; the
  dim state is the same glyph at 35% so the bar doesn't change shape; the menu's item is one line in the menu's own type
  and padding under the page's rule, no icon (the models have none), no accent (the check is the only colour in the
  menu), lit on the pointer as the others are, so the menu reads as one more row and not a second menu; it is in the
  stand-in of the real classes, so what is certain is the structure and the classes, not the pixel. Kept as they are: the
  two-bubble glyph (`bubble.left.and.bubble.right`, another voice in the conversation; the question mark reads as help,
  a single bubble as Messages, the branch as a fork) a few points wider than Results' tray (43 against 39), and the item
  last in the menu after "More models" and the page's note, as asked.
- ✅ **The title bar at the narrowest main window** (900 points), an estimate and not a look at the real glass bar, which
  AppKit lays out. The items' own widths (`toolbar-widths.txt`, points, the real buttons where they could be drawn and
  stand-ins of the same labels where not: Ask 43, Results 39, Shelf with 120 items 102, Specimens 136 or 156 "off",
  Update 84, the Lab capsule 83 "Recent", 133 "Working · 12:34" or 157 "Paused · usage limit", the readouts 277 with a
  42% ring and a week limit with its reset, a usage label alone 198 ("5h") or 248 ("Sonnet week")), the gaps between
  capsules (about 8.5) and each capsule's own 2 points either side, both as `docs/toolbar.png` has them, and the fixed
  spacer (taken as 8), against 900 less the window's three buttons and a margin (about 82): a quiet bar (Recent, 42%, a
  week limit, Shelf 12, Specimens on) needs about 755 of 818 with the button and 699 without, so it fits with about 60
  to spare; with an update on offer it needs about 851 with the button and 796 without, so there the button is what
  tips it over; with a long Lab word, Specimens off and an update it needs about 945 (889 without), which overflows
  today. Nothing was changed for it: the button is icon-only (as Results is) and first of the three, so the others stay
  where they are, and AppKit's overflow menu takes what doesn't fit. A live look at 900 points, with and without an
  update on offer, is still to do.
- The whole suite: 3,909 tests in 505 suites pass (58 net new: 35 for the script, 14 for the Swift side, 4 more in
  `AskEntryPointTests`, one fewer in `AskSourceTests`, 6 snapshot tests, of which 5 draw or drive WebKit only when
  `CAPSID_SNAPSHOT_DIR` is set). No flakes. The continuation warnings in the log are other suites' (`browser`, `forever()`,
  `dependencies(postLimit:…)`, `sessions(turnLimit:…)`), none of this feature's.
- ⏳ **Live, on the real page and the real bar** (nothing here has met a real Claude Science page): that the served 0.1.70
  popup carries those markers (which of the two pickers a session shows); that Base UI opens its menu on the pointer-down
  the script listens for (and on Enter, Space, the arrows); that the item arrives and is not lost as the page draws the
  popup, and the popup grows to hold it and stays where it was put (its position follows its size); that the Escape sent
  from inside the popup closes it, and if not the pointer-down 80 ms later does; whether the page's own highlighted row
  lets go when the pointer moves to the item; that the draft is what is typed (a line break, a mention chip, with an
  upload on its way), from the main composer and from the aside's; that "Ask Another Model" is not offered on the
  project's own page, where no session is shown; the error card's "Switch models", which opens the picker without a
  press on it and gets no item; the glass toolbar's real width at 900 points with and without an update on offer; and a
  click on the button opening the window for the session in the main window.

## 2026-10-23, README follow-ups: words under the title, Windows line ends, the byte order mark, the fine print

The owner's rule for a kept folder's README.md: never lose or hide what a person wrote in it. The earlier fix (Try Again
updates only Capsid's parts) left three follow-ups, each fixed on `g/readme-robust2` with tests that were red on the old
code first. Everything ran on temporary folders and made-up content ("Plate reader QC", "z_prime.png"); the real Kept
folder was never read or written, and nothing was launched or installed.

- ✅ **Words under the title hid the folder.** Cause: `KeptReadme.parse` took the lines between the title and the first
  "##" heading as a place only blank lines may be, so a note there made it answer nil: the folder left the Shelf and the
  Kept window, and Try Again could never update it. Now those lines are passed over as the person's own (like a heading of
  theirs between sections) and neither `updating` nor `replacingLegend` changes a byte of them. Red before the fix on the
  parser, both writes, the disk (scan, read, legend save, Try Again's rewrite) and a real `ShelfModel` (the item left
  the model's `items`); green after, and the item's legend still saves under the words. The lines
  `KeepRules.leftOut` adds under "Where it came from" (upload, pending, data and code left out) were always read and now
  have a test through the parser and both writes.
- ✅ **The other shapes, each decided.** An extra blank line in the text (after the front matter, after the title, between
  sections, before or after the divider, after the fine print) and a missing final newline were already read: pinned, and
  both writes leave them where they are. The legend's own section is the exception (its lines, blank ones included, are
  rewritten with the legend), pinned. A blank line inside the front matter stays refused (the record is read in the shape
  Capsid writes it, and the writes find its rows by their places), pinned. Windows line ends were not read at all (every
  structural line carried a carriage return): a file whose first line break is CRLF is now read as the same file with plain
  ones, and `replacingLegend` and `updating` write Windows line ends back, new lines and a pasted legend included, byte
  order mark and a missing final line end too. A Windows file with a plain line end among them is read but not changed
  (they could not be put back as they were): `updating` answers nil (Try Again's existing "has a form Capsid can't update
  safely" sentence) and the legend save says "README.md has a form Capsid can't edit safely, so it was left alone." instead
  of the old, untrue "has no Your legend section". A plain file with Windows line ends only inside a person's words is
  not a Windows file (`lineEndsInTheLegendComeBackAsWritten` and the Try Again test with a Windows-edited section still
  pass untouched).
- ✅ **A legend save in a README with a byte order mark** always said "changed in another app" (and Use Mine too):
  `KeptDisk.replaceLegend` compared the file's bytes with the text the field was made from, and decoding the bytes had
  dropped the mark from the one. Now it compares without the mark, writes it back, and answers the README as text without
  it (two saves in a row, emptied again, a change made elsewhere with and without the mark, a README without a mark
  written without one; and `ShelfLegendEditor` through two saves, a change elsewhere and Use Mine). README text is decoded
  without the mark explicitly rather than by what Foundation does.
- ✅ **The fine print.** New READMEs end with "Capsid updates the file lists, “Not copied”, “Checksums” and “Your legend”
  here; everything else in this file is yours." The parser never read the line's words, so READMEs with the old line (and
  with a person's own) still read; neither write rewrites it (pinned). The contract's README and the anchors in the
  Try Again tests (`KeptReadmeTests`, `KeepModelTests`) use the new line.
- Break-and-see: for each item the new tests were run against the code before the fix and failed, then passed with it.
  Fine print: seven (the contract's README to the byte, the new wording, three Try Again tests whose anchor is the line,
  the old-line pin, and the footer test, which crashed on its force-unwrapped anchor). Byte order mark: the disk test
  (`.changedOutside`) and the editor test (eight issues, Use Mine among them). The words and the line ends: nine of the
  twelve tests then in `KeptReadmeShapeTests` failed (the other three were pins that already held: no final newline, a
  blank line in the front matter, extra blank lines in the text); and with `KeptReadme.swift` put back to the commit
  before the fix, the four new tests on the disk and on a real `ShelfModel` failed too (the item left the model's
  `items`). The test for the legend's own section keeping its blank lines was added after the fix, as a pin.
- The whole suite: 3,851 tests in 501 suites pass (21 new). One run, earlier, had `SinceYouLeftModelTests.lessThanThirtyMinutesAwayShowsNothing`
  failing, alone as well as in the suite: its rig starts at the real time minus 3 hours and the test counts 18 minutes, so
  when that start falls in the 18 minutes before midnight UTC the away stretch spans two days (its calendar is UTC) and the
  card appears. Nothing to do with Kept, and not a load flake; it passed in the next run, outside that window. (The
  baseline before this work was 3,829 at 1.0.2 and one test more in 05ebc4b.)
- ⏳ **Live**: not tried on a real README. No window was opened and the real Kept folder was not touched; what remains is
  to put a sentence under the title of one real kept folder and save its legend, and to open a folder saved by a Windows
  editor.

## 2026-10-23, Ask Another Model (off by default; a side door to another model, with your own key)

- ✅ **Finished from a checkpoint.** An earlier run (d626bef) was stopped three times by API overloads before it built or
  tested anything. It compiled as it stood and its 69 tests passed, so what was left was review and finishing:
  the snapshot's held ask waited on a continuation nothing resumed (the runtime said so; it now waits on a sleep Cancel
  ends); nothing asked the address while the switch was off, but a window left open still could, and a key saved while
  it was off listed the models; an edited address kept showing the old address's models; and Settings' own model row
  sent the person "to Settings → General" from Settings → General. All four fixed, each with a test.
- ✅ **Off hides every way in** (`AskEntryPointTests`, `AnotherModelSettingTests`): the switch is off and registered off;
  File's item is not there off, or on with no key, and is dim with no session in the main window or in a demo; the
  right-click item is added only while available, once, and never to a tab's or a figure's menu (which keep Capsid's
  own); the reference window's text menu has it only with a handler and only while available, starting from the
  selection; the window does not open. With the switch off a key can be saved and removed, and nothing is asked of
  the address, not even the model list; a window left open answers "Ask another model is off." and sends nothing.
- ✅ **The key is a file and nowhere else.** 0600 in a 0700 folder, trimmed, nothing else in the folder (no temporary
  copy), found again at the next launch, deleted by Remove with its list; a paste that is no key (a space, a line break,
  too short or long, not ASCII) writes nothing and the sentence names nothing of it. In no `UserDefaults` value (the
  suite's own or the app's) and in no log line, after a save, a list, an ask and a remove. Source checks: no
  Keychain, `SecItem` or `kSec` in the folder, `Authorization` in one file only, one `Logger` with one call, no
  `print`/`NSLog`, and the window, the rules and the menu never reach the key.
- ✅ **The requests**, against a fake `URLProtocol` with a made-up host each (nothing leaves the process): `GET /models`
  and `POST /chat/completions` with `{"model", "messages", "stream": false}` and nothing more; the key only in the
  `Authorization` header, not in the address, the body or any other header; no cookies, cache or credentials; a
  redirect is refused and the other host is never reached; 401 and 403, 429, 500, a 200 that is no answer, an answer
  over 4 MiB, no network, an unreachable host, each as its sentence; the deadline (120 s for an ask, 20 s for the list,
  on a manual clock) ends the request itself, and so does Cancel; asked once, never again on its own. The address:
  https only, no user, password, query or fragment.
- ✅ **The window's rules and model** (`AskRulesTests`, `AskModelQuestionTests`, `AskModelAskingTests`): the session's
  last message is the question (whole when the page cut it; never over what was typed while the read was out); a
  selection is the question and nothing is read for it; the conversation is the text turns before that message (the
  mid-run messages count as Claude's), 10 at most and 12,000 characters at most, an older turn never without the newer,
  only with the switch on, and exactly what is listed is sent; no model chosen means no Ask; Cancel and closing the
  window end the ask and nothing more comes; Copy gives the answer as it came; the log is counts and fixed words, and
  none of the made-up question, answer, session or project names is in a line.
- ✅ **Send to Session goes by the bounded path** (`AskModelSendTests`, `AskModelBoundedSendTests`, the second through
  `RemoteSessions` itself with a made-up page behind it): one message write carrying a UUIDv4 `_intent_id`, the model's
  name on its first line; a session waiting on a question takes none ("Answer its question first.") and nothing is
  written; a write with no answer is settled by one more read, found by its intent (sent) or not found ("That didn't
  go through. Try again.", and no second write on its own); a second press while it goes or after it went does nothing,
  and a press after a failure keeps the same intent, so a lost reply is the daemon's own repeat; an answer over 4,000
  characters or holding a file reference says so and writes nothing.
- ✅ **No new page hook.** The selection is read by one script (`window.getSelection()`; a test checks it names no
  element, selector or fetch), the question by the existing history reader. The Compat suites pass: 193 tests in 24
  suites.
- ✅ **Offscreen renders**, light and dark, in `shots-ask/` beside the worktree (the
  harness draws the SwiftUI content with `cacheDisplay`, as the Reference and Shelf ones do; nothing opens): the window
  ready, asking (the conversation listed, Cancel in Ask's place), answered (the Markdown, "Answered in 9 s", Copy and
  Send to Session) and failed (the deadline's sentence in clay text); Settings with the switch off, on with no key, on
  with a key and the models listed, and on with a key the address refused. Looked at against "gorgeous and minimal":
  one clay action in every state; the question card, one switch with its count, the quiet model name; the answer on
  the page with nothing around it; the failure a single centred sentence and no dialog; Settings one switch off and
  four rows on. Kept as they are: the two-line description under the switch (where the feature appears is the only
  trace of it while it is off) and the question card's height (room to edit). The pills' edges show a thin vertical
  stroke at their ends in these renders; the Reference window's captures have it too, so it is the harness, not the
  button. No real window was opened, so none shows Capsid's glass title bar, and no menu or popover was opened.
- The whole suite: 3,829 tests in 500 suites pass (3,749 before; 80 new, 78 of them checks and 2 that draw PNGs only when
  `CAPSID_SNAPSHOT_DIR` is set). No flakes. The continuation warnings in the log are other suites' (`browser`,
  `forever()`, `sessions(turnLimit:…)`), none of this feature's.
- ⏳ **Live, with Sam's own key** (nothing here has met a real Abliteration.ai): the real `GET /models` shape and
  whether its names carry the `abliteration-ai/` prefix; that `/chat/completions` takes the body as built and how long a
  real answer takes (the 120 s deadline); the three doors on real surfaces (File → Ask Another Model…, a right-click on
  selected text and on none, and the reference window's menu on Claude's words); the question prefilled from a real
  session's last message and the conversation list; a real Send to Session and its `_intent_id`; the key file landing
  in the real Application Support folder at 0600 and Remove deleting it; the paste into the secure field with Save; and
  Settings' height (1,190) on a real display.

## 2026-10-23, Capsid 1.0.2 released and installed

- ✅ Released as v1.0.2 (tag on 585c1f9, "Capsid 1.0.2", by Sam with `gh release create`), marked Latest:
  `Bench.zip` with Capsid.app 1.0.2 (48) inside, 17,971,623 bytes, sha256 0ddc07904add050b…. GitHub's asset
  digest matches the file built from that commit.
- ✅ Installed from that same build before the release (CDHash 460b5a7e; the unzipped copy's signature checks and
  its CDHash is the same). "Signing in: with a code from claude-science url", and the usage read answered 4 s
  after launch.
- The whole suite before the push: 3,829 tests in 500 suites pass.
- ⏳ **Live**: Ask Another Model with Sam's own Abliteration.ai key (the model list's names, a real answer, Send to
  Session).

## 2026-10-23, Capsid 1.0.1 released and installed

- ✅ Released as v1.0.1 (tag on 9229072, "Capsid 1.0.1", by Sam with `gh release create`), marked Latest:
  `Bench.zip` with Capsid.app 1.0.1 (47) inside, 17,823,654 bytes, sha256 fd2069ba67c9e1a8…. GitHub's asset
  digest matches the file built from that commit.
- ✅ Installed from that same build before the release (CDHash a5e63468; the unzipped copy's signature checks and
  its CDHash is the same). "Signing in: with a code from claude-science url", and the usage read answered 4 s
  after launch.
- The whole suite before the push: 3,749 tests in 488 suites pass.

## 2026-10-23, Keep waits for its provenance; the figure menu and Keep explain themselves in the log

- ✅ **Walkthrough 7, Keep with Data and Code, works**: "Kept 1 of 1 files" at 12:34. The first ✗ was the figure menu's:
  when 7 was first tried, a right-click on a figure showed none of Capsid's items, so no keep ever started. The log
  had no keep, and the morning's two folders were Add to Shelf (`files: []`).
- ✅ **Why that keep held the figure alone, found and fixed.** Keep was on while Claude Science was still working out
  the version's provenance, and the data and code rows, unticked while it was pending, stayed unticked once it came.
  Sam pressed Keep about ten seconds after the sheet opened. Now:
  - Keep stays off while the provenance is pending, for up to two minutes, asked every 5 seconds;
  - once the provenance is there, the rows are ticked and the inputs' names and sizes are read;
  - a README says why a folder has no data or no code (pending, no source data recorded, left out, and the like),
    and the Kept window reads it back byte for byte.

  Four new tests: the wait (Keep off at each of three waits, then figure, data and code kept), the two minutes
  running out, no inputs recorded, and a row left out.
- ✅ **Keep's log** (`keep`): the sheet opened, the first read's failure, ready with N versions, provenance with N
  inputs and M copyable (or unreadable, an upload, pending, ready after N checks), keeping N files, each failure and
  cancel. Fixed words and counts only; a test checks that the made-up figure, project and session names are in none.
- ✅ **The figure menu's step trace** (`figure-menu`): one line per right-click, e.g. "Figure menu: contextmenu →
  figure-beside → version-ok → menu-matched → placed". Every path is covered in the made-up page: each way to a
  figure, no figure, no version, no menu, another menu, unplaced, interrupted, and a made-up right-click (none).
  A trace never clears the Mac menu's pick, and Swift drops any word it doesn't know.
  Its one new selector, `[role="menu"]` (any menu, for menu-other), is in the compatibility inventory. The first
  install went in without it: the inventory tests failed, and the install script took a test named `running…` for
  the passing summary. Both are fixed, and the build was reinstalled.
- 933 tests in the Keep, Kept, Shelf and figure-menu suites pass.
- ⏳ **Live**: a real keep of a version whose provenance is pending, and one real right-click read back from the log.

## 2026-10-23, board 12: the shelf, a little prettier (days, bigger cards, quiet names, a calmer detail)

- ✅ **Days.** The cards stand under Today, Yesterday, This week, Earlier this month, then the month, by `kept_at` in
  the user's calendar (`ShelfRules.days`), newest first, empty days without a heading. Tested with a fixed clock in
  a zone with summer time: midnight to the second, the sixth day back against the seventh, a 25-hour day, the turn
  of the year (December's heading then names its year), the same instant on different days in New York and UTC,
  a date after now (Today), and two items shelved in the same second (by folder).
- ✅ **Rows and keys.** Three cards a row at 940 and 880 points, two at 620, four at 1,200
  (`ShelfRules.columns(forWidth:)`). ↑ and ↓ move by the rows drawn, across the headings, to the same column or the
  last card of a shorter row; ← and → run on. The old four-wide test now sets four columns itself.
- ✅ **Names.** The extension in grey only for a file's own name, and only a last part of one to eight letters and
  digits with a letter ("results_v1.0", "notes.", ".env", "a.verylongextension" stay whole; "archive.tar.gz" greys
  ".gz"); a keep's own name never split.
- ✅ **The detail.** "Session · Project · version N · time" (the old "From Claude's answer at … in “…”" line is
  repinned), the question in quotes without "You asked:", a muted line when Claude's words are only the session's
  last answer. Show Where It Came From stays the one clay action; Copy beside it; ⋯ holds Keep with Data and Code…
  (only when there is something to keep), Export Figure as PDF…, and Remove after a rule, each also a VoiceOver
  action. Export as PDF… in the title bar only with two or more picked; ⌘P on a button of its own, so it works
  with one and never twice (a source check: the pill has no key).
- ✅ **Offscreen renders**, light and dark, 940 × 820 and 620 × 480: the first card selected, an item kept with data
  and code, Tables, a search with no match, three picked, the older days, one project (This week and Earlier this
  month), the empty shelf. Compared beside board 12.
- ✅ **Real windows** through `shoot.sh`, by window ID: `--demo shelf-pdf` (two picked, the pill beside the search)
  and `--demo find` (the shelf's two heatmaps under Today and Earlier this month, then "In your sessions · 5").
  The first run showed the search by the project pill: with the title removed nothing pushed the bar's items
  right, so a flexible toolbar spacer now does, and the second build shows it at the right as the board does.
- ⚠️ **One capture's window was active.** The first launch of a freshly built bundle came up with its window key
  (coloured traffic lights), and one ↓ reached it: the demo's two picks became one on the card below. Later runs
  (one after `lsregister -f` on the new bundle) stayed behind; a watch of the frontmost app every quarter second
  saw only Sam's own Capsid in front through both final captures. Nothing in the Shelf demos opens a menu or a
  popover or puts focus in a field.
- The whole suite: 3,732 tests in 486 suites pass, before the toolbar spacer and again after it. No flakes.
- ⏳ **Live**: ⌘P with one card picked (a key on a button nothing shows can't be pressed offscreen), the ⋯ menu and
  the VoiceOver actions, the scroll to a selection further down when the window opens on it, and the headings
  after midnight with the window left open (they follow the next change, as the captions do).

## 2026-10-23, shelf polish: "Export Figure as PDF…", a PDF from what is saved, drafts that survive, Find's limit

- ✅ **The rename.** "Make PDF…" is "Export Figure as PDF…" / "Export 3 Figures as PDF…" on the card and in a
  card's menu, "Export as PDF…" in the title bar (no count: at 620 points the bar also holds the project pill and
  the search), "Exporting… 2/3" while it is made, "Export" on the save panel's button. ⌘P and "Lab meeting
  <date>.pdf" unchanged. Offscreen renders, light and dark, one, three and all ten picked (the narrowest window),
  and a real `--demo shelf-pdf` window through `shoot.sh` (light; the demo follows the system's appearance).
- ✅ **A PDF made right after typing a legend has that legend** (typed just before the command, typed while the
  panel is up, changed in another app while it is up, a conflict, an unreadable README), each mutation-checked
  by leaving `latest` out of the command.
- ✅ **A legend draft whose save fails after the item was left is still there**: kept by the model, the pill says
  so, choosing the item again shows the draft with its Use Mine / Use Theirs (a change made elsewhere, and a
  README that went missing). Mutation-checked by letting the editor go with the card.
- ✅ **Find's limit.** 200 files of a hidden session, the concierge, the uploads session and the planner, newer
  than five real matches: the five come back, with and without the two indexes. On a made-up database of 80,000
  artifacts and 2,000 sessions with 900 MB of blobs: 45–130 ms became 220–450 ms warm for words every session
  matches. Not measured on a real database.
- The whole suite: 3,593 tests in 466 suites pass.
- ⏳ **Live**: the save panel's new button and the pill in the real toolbar with a long project name, a real
  conflicting legend save after choosing another item (the pill line), and Find on a real database.

## 2026-10-23, Capsid 1.0 released and installed

- ✅ Released as v1.0.0 (tag on c3fcdb4, "Capsid 1.0", by Sam with `gh release create`): `Bench.zip` with
  Capsid.app 1.0.0 (46) inside, 17,403,437 bytes, sha256 5485422429a421f7…. GitHub's asset digest matches the file
  built from that commit.
- ✅ Installed from those same bytes before the release (unzipped, signature checked, swapped into /Applications).
  Diagnostics: "Capsid 1.0.0 diagnostics", "Signing in: with a code from claude-science url", "Claude Science
  0.1.70; Capsid was last checked with 0.1.70".
- The whole suite before the push: 3,526 tests in 461 suites pass.
- The phone's server stays on 47281: it remembers the port it last had (`remotePort`), and the phone's tailnet
  address (8443) doesn't change.

## 2026-10-23, review B's fixes, and test rigs that outlived their tests

- ✅ All nine of review B's findings, each with a test, mutation-checked:
  - a failed inline Send says why;
  - Quick Start holds still mid-send;
  - the sign-in path beside the app asks twice and then lets the page decide, and a read-only that keeps trying;
  - Finished card identity and the queued reviewer read;
  - the global key never hides a sending panel;
  - Tab to a finished row's pills;
  - the phone's "Still waiting for your Mac…";
  - the Since You Left loader's handle.
- ✅ **Sign-in against the real daemon after install** (browser tab, launchd, `require_token: yes`): Diagnostics says
  "Signing in: with a code from claude-science url", and the log shows only the launch-time 401; at 02:53 the
  five-minute usage read answered with its data ("Plan usage keys: data,ok"), so the page was signed in.
  `ScienceSwitchWiringTests.theTabDaemonsSignInIsUntouchedByTheTokenAndTheSecondAsk` pins that `require_token`
  can't reach the plan.
- ✅ **"Attempted to read an unowned reference" crashes.** Three crash reports tonight named test fakes (one was
  `CompatProbeTests`' `FakePage.environment`). A task the code under test left behind outlived its rig. Every rig
  without a `deinit` now captures strongly (or weakly with a benign default), and "60 yields" settles became bounded
  drains.
- ✅ Load flakes given room: `QuickOpenDatabaseCancellationTests` and `RemoteStaticCacheTests` now allow 60 s. Seen
  once more under load: `aReadThatNeverAnswersIsGivenUpOnSoon`.
- ✅ The whole suite: 3,526 tests in 461 suites pass.

## 2026-10-23, test settings stay out of ~/Library/Preferences

A suite named "x" is `~/Library/Preferences/x.plist`, and `removePersistentDomain` doesn't remove it: cfprefsd writes
the domain back out empty (42 bytes), and again about five seconds later or at exit, even after the file is deleted
by hand following a synchronize (measured). Every test that "cleaned" a suite left one, and about 6,000 piled up
(moved to the Trash, `capsid-test-preferences-2026-10-23`). Every suite now comes from
`ScratchDefaults.make(prefix:)`: a suite named by a path in `$TMPDIR/capsid-test-defaults-<pid>`, so cfprefsd writes it
there. `discard()` empties it and deletes its file; the folder goes at exit, and is swept next run if a run was
killed. `ScratchDefaultsTests` holds that nothing reaches Preferences, including seven seconds after a discard, and
scans the test target for any other way of making a suite. A full run used to leave 148 plists; now it leaves 0
(checked twice). The Kept demo's own suite is named the same way. Also in this round: Remove pressed twice, the
legend saved on leaving and off for an unreadable README, and Copy's picture off the main actor
(`ShelfLegendTests`, `ShelfFigureCopyTests`), all mutation-checked.

## 2026-10-23 (overnight), the safety batch, three features and a review pass

Sonnet agents in worktrees, merged on `g/reference` by the lead; each wave's full suite green before it was installed
(3,218 tests after the safety batch, 3,412 after the menu-bar home, PDF and review A's fixes, 3,482 after Find).

- ✅ **Safety batch.**
  - Bounded writes (`BoundedWriteTests`, `UnknownWriteTests`, `ManualClock` for the stall tests): a refresh, a
    POST and a Swift await that never answer; unknown settled each way for every write; no automatic retry; the
    queue moving on.
  - Quick Start's Cancel with an upload, a project read, a queued send and a session read held, and after the
    request is out.
  - Keep's clicked version, and the figure that can't be copied (`KeepPickedVersion*`, `KeepFigureFirst*`).
  - The compatibility watch and the 0.1.70 walk (`CompatWatchTests`, 44).
  - The handover dialog told from every other restart (`HandoverScriptTests.anyOtherRestartsDialogIsNotTheHandover`).
  - Web Inspector debug-only (`WebInspectorTests`), and the phone's content flag (`PhoneSinceTests`).
- ✅ **Menu-bar home** (`Companion*Tests`). Real-window captures of `--demo menubar` against board 1, light and
  dark. System Events lists the item "Capsid, 2 need you".
- ✅ **Lab-meeting PDF** (`ShelfPDF*Tests`, `ShelfPickingTests`): real PDFs read back with PDFKit; a page each
  for ten kinds of file; the Shelf window with two picked, captured.
- ✅ **Find any figure** (`Find*Tests`, `QuickOpenFilesTests`), on a fake database built from the 0.1.70
  migrations. On Sam's Mac after install, Diagnostics said "2,938 listed; a search for today's files returned 1
  in 50 ms".
- ✅ **Review A** (Keep, Shelf, Reference): 12 findings, and the agent fixed them all, each with a test and
  mutation-checked.
- ❌→✅ **The flaky Nidus test** (`aPreparedWriteSupersededByClearNeverCommits`) failed whenever agents built
  beside it: its 5 s hold was shorter than a busy Mac's turn. Now 120 s, as a backstop.
- ⏳ **Live**:
  - a real unknown write, and the line on the card;
  - the menu-bar item on a real menu bar (both appearances), Approve and Reply from it;
  - Make PDF… on real figures (Retina, rotated JPEG, SVG) and ⌘P/⌘A in the real window;
  - Find's Show Where It Came From on an old session;
  - the reference window's refresh on a real finish;
  - the compatibility card after a real Claude Science update.

## 2026-10-22, Capsid 1.0 M5: Since You Left (board 2)

Built by a Sonnet agent on `g/m-m5`, merged on `g/reference` (d0684c7);
follow-ups b72793f.

- ✅ `AwayRuleTests`, `SinceYouLeftSummaryTests`, `SinceYouLeftModelTests`,
  `SinceYouLeftStateTests`, `PhoneSinceTests`: idle stretches, a screen that
  goes off, a sleep with no word, the new-day floor; grouping by each session's
  latest event; the sheet, the card, the focus and presenting holds, Done,
  replacement and the 12-hour expiry; at most six reads, each once, none while
  away or with the content setting off (and hidden again when it is turned off
  later); the phone's `since` and its reasons.
- ❌→✅ **The sheet showed no rows.** `--demo since-you-left` captured by window
  ID was 177 points tall: the header and the foot only, because the window
  follows the sheet's size and a scroll view asks for none. The offscreen
  snapshot (laid out at 1,200 first) had hidden it. Now the rows' scroll view
  is as tall as they are, up to the screen; the capture is 744 points with
  every row, matching board 2.
- ✅ Settings → Alerts → When you're back, "Show what changed while you were
  away", captured (`--demo alerts`); the page is 940 tall and scrolls on a
  13-inch screen.
- ✅ Installed (M5 at 22:57, CDHash f4c2c09f; follow-ups at 23:20); the log
  shows only the launch-time 401 before sign-in.
- ⏳ **Live:** a real return after 30 minutes (the sheet over the main window,
  or the card when another app is in front), a real question answered from
  the sheet, Add to Shelf from a finished row, the phone's section, the 5-hour
  line against a real reading.

## 2026-10-22, the Shelf (Sam's priority #1, boards 10 and 11)

Built by two Sonnet agents against a contract written first (`Kept/Shelf.swift`
and `ReferenceWindowController.show(…at:mark:)`), merged on `g/reference`.

- ✅ **The Shelf** (`ShelfTests`, `ShelfRulesTests`, `KeptDiskTrashTests`,
  `KeptDiskPeekTests`, `KeptReadmeTests`): adding with the answer given, found
  or the last-answer fallback; already on the shelf; a failed download; one
  add per version; the README's new lines round-tripping; the Trash and Put
  Back; kinds and counts; the window's filters. The window drawn offscreen,
  light and dark, against board 11.
- ✅ **The ways in** (`ShelfAddressTests`, `ConversationMenuTests`,
  `ConversationShelfTests`, `ShelfToastTests`, `ShelfReferenceTests`,
  `ShelfWaysInTests`): every address shape, the menu only on artifact images
  and links, the toast's states, Results' rows, the reference mark, and
  landing on the right reply (ten pages back, inside a reply that starts
  earlier, past the 80-page cap). The toast and the marked reference window
  offscreen against boards 10 and 11.
- ✅ **The whole suite:** 2,899 tests in 377 suites pass.
- ⏳ **Live:** whether the page's figures carry a version in their address
  (`img.currentSrc`; if it is a `blob:` the menu shows no items), where the
  group lands in the real menu, ⌥⌘S, the toast over the page, Show Where It
  Came From on a real item several screens back, a real Quick Look of xlsx and
  docx, the Trash.

## 2026-10-22, M9a: surviving Claude Science's own window

- ✅ `ScienceSwitchTests` and `ScienceSwitchWiringTests`: detection (both
  places, the Safari web app, an unreadable id), status parsing (old and new
  shapes, the missing port, wrong types), the serve decision over every
  combination, the CLI order, the canonical host, the sign-in plan, the
  notices word for word, and the handover script in JavaScriptCore. Nothing
  started, stopped or asked a real daemon.
- ✅ The whole suite after the merge: 2,717 tests in 357 suites pass.
- ⏳ Only the live switch can settle the rest (DESIGN, Daemon and sign-in).

## 2026-10-22, Capsid 1.0 M6, M7, M8 and the Keep sheet

Built by four Sonnet agents in worktrees from one shared brief (the boards'
HTML, the Solanum kit, file ownership, a data contract), merged in order
(data, Keep sheet, Quick Start, panel) on `g/reference`.

- ✅ **Data** (`LabInsightsTests`, `InsightReaderTests`, `SpecimenTopicsTests`):
  plan progress, reviewer counts and mid-run notes, projected in the page on
  made-up trees with "SECRET" in every description and finding (none comes
  back); rates, gates and wake-ups on an injected clock; the topic matcher's
  words, plurals, phrases and determinism. Probes and Diagnostics lines added.
- ✅ **The Keep sheet as board 8**, seven states light and dark offscreen; its
  width now follows its window (600 from Results, the window's own from the
  reference reader).
- ✅ **Quick Start as board 4** (`QuickStart*Tests`, 120 tests): the writers
  driven with fakes (intent-id dedupe, plan first, a queued message, file
  refusals), recipes, keys, services, the Shortcuts gate; the panel light and
  dark offscreen. `Metadata.appintents` in the built app lists 7 intents.
- ✅ **The panel as board 6** (`PanelMomentsTests`): working with progress and
  the matched specimen, finished with figures and the reviewer line, stopped
  with the culture plate, the note card, the stack, sounds, VoiceOver
  sentences; flat stand-ins offscreen (glass doesn't draw offscreen).
- ✅ **The whole suite:** 2,616 tests in 342 suites pass. A Nidus writer timing
  test (`aPreparedWriteSupersededByClearNeverCommits`) failed in some full
  runs while four agents compiled, and passed alone every time: a flake under
  load, older than this work.
- ✅ **Installed** (CDHash a372b81f…).
- ⏳ **Live:** the global keys taking ⌃⌥⌘Space and ⌃⌥⌘R; Quick Start's panel,
  blur and drag-and-drop; a real start, message and upload of each file
  kind; Services in Finder without a logout; Shortcuts listing the actions
  (self-signed); the panel's glass and clay buttons, the stack's hover, the
  sounds, VoiceOver; plan progress on a real plan (whether the tree's root
  carries the plan), reviewer counts, notes.

## 2026-10-22, M4 follow-up: answers with their figures, the mock-up's look, Codex's review

Sam opened a real session as a reference and found it ugly, without figures,
and saying "Open in Claude Science" for what opens in Capsid; he asked for the
mock-ups' look. A Codex review of M2.1 and M3 came in at the same time.

- ✅ **Why there were no figures:** a figure sits on the tool step that made
  it, and the reader looked only at each Claude turn's own files. An answer is
  now Claude's whole reply to one message, its words and every figure made on
  the way (`ReferenceRules.answers`, `ReferenceRulesTests`, 9;
  `ReferenceModelTests`, 15, including a reply longer than a page read back
  until its question is in).
- ✅ **The mock-up's look** (board 7 of "Capsid 1.0 mock-ups"): the ivory page,
  a centred title over "<project> · read only", round chevrons, figure cards,
  14-on-21 text, pills at the foot (`SolanumSurface.swift`). Captured in the
  built app by window ID, light and dark, on the newest answer and on the one
  with two figures (`--demo reference --step figures`). A first try left the
  system title in the toolbar, which pushed the chevrons into the overflow
  menu; `toolbar(removing: .title)` fixed it, seen in the next capture.
- ✅ **Open Conversation** replaces "Open in Claude Science", in the window,
  the figure's menu, README and DESIGN.
- ✅ **Codex's five findings, all confirmed in the code, all fixed, fake
  dependencies only:** the update handshake (`.previous` kept until swap.sh's
  marker; the crash-after-clean-up test fails before the fix and passes
  after), Keep's Try Again (load and keep retries), the answer pinned to its
  version from the reference reader, checksum mismatches no longer silent,
  and a partial retry not done until its README agrees. None of it was seen
  live.
- ✅ **The Kept window as board 9** (list, tinted selection, figure card,
  pills, legend field), drawn offscreen light and dark
  (`KeptWindowSnapshotTests`): window captures failed again this evening
  ("could not create image from window", the display asleep or locked), so
  its title bar is unseen. Found on the way: the first result wasn't
  selected when the window opened on results already read.
- ✅ **The whole suite:** 2,316 tests in 303 suites pass, everything merged.
- ⏳ **Live:** the restyled window on a real session, figures from a real
  run, Keep… from a figure.

## 2026-10-22, Capsid 1.0 M4: the reference reader

Claude's answers beside the work (the handoff's M4; DESIGN.md, Reference): a
read-only 440-pt window per session, opened from Quick Open (⌥↩ or a row's
menu), an activity row's menu or a card's Later menu, with Earlier and Later,
Copy with Source and Open in Claude Science, and the history reader's
groundwork from spike S5 beneath it. Branch `g/reference` (on `g/keep`),
local, not pushed. Two agents in worktrees (the reader's groundwork on Sonnet,
the Markdown on Opus), merged; the window, the model and the gate here.

- ✅ **The whole suite:** 2,282 tests in 298 suites pass (`swift test --jobs 2`,
  one run).
- ✅ **History reader groundwork** (`HistoryReaderGroundworkTests`, 8 suites):
  the linear trim is byte-identical to the old rule on ten fixtures and on the
  full projection; a 25-row page is one `from=N&limit=25` GET and the first
  read stays the 12-row tail; a nonce files the AbortController and
  `abortArtifactRead` ends the fetch, the task ending in `CancellationError`;
  a body over 2 MiB, declared or streamed, is `tooBig` (the phone says 503,
  Keep unreadable); the page yields through `requestIdleCallback` or
  `setTimeout(0)` before each parse and the projection; timing is parsed
  strictly. Six deliberate breaks in the source were each caught.
- ✅ **Markdown** (`AnswerMarkdownTests`, 29): every block kind by walking the
  attributes; only http, https and mailto links stay links; tables, images and
  HTML blocks become placeholders listed with their ranges; a 20,000-character
  answer renders; the code ground is faint in both appearances. Probed first
  on this macOS: `.full` parsing keeps tables, hands HTML blocks through as
  marked text, and threw on nothing (50k-deep input included).
- ✅ **The reader** (`ReferenceModelTests`, 15; `ReferenceRulesTests`, 6;
  `ReadingGateTests`, 5): the newest answer on open; Earlier at the edge reads
  back and lands on the page's newest answer; empty pages are read until an
  answer appears, eight at most, and Earlier looks again; row 0 reached makes
  the count final ("2 of 3" against "2 of 3 so far"); a cut answer is read
  whole and replaced in place; a late whole answer lands on its own row while
  another is shown (the stale guard); a page landing while the user moved
  keeps the shown answer; unreadable, too big and thrown reads fail with their
  sentences and Try Again reads; closing cancels the read (the fake sees the
  cancellation) and drops what lands; Copy with Source; a thumbnail once per
  figure. The gate: the pause rule in whole milliseconds, one read at a time
  in order, a key press waited out, typing extending the wait to 2 s at most,
  cancellation reaching the read.
- ✅ **Drawn offscreen** (`ReferenceSnapshotTests`, `CAPSID_SNAPSHOT_DIR`): the
  content at 440 pt, light and dark, an answer with code and a figure, and the
  failed state. Reviewed: the text sizes to its content so the figure follows
  it (the first draft pinned the figure under an empty gap); no clay anywhere.
- ✅ **The real window:** `--demo reference` opened quietly (`open -g`) and was
  captured by window ID (`bench-wt/shoot.sh`; captures work again on this Mac):
  title and "Assay development · read only" subtitle, the Earlier/Later
  control group, the caption, the text, the footer.
- ✅ **⌥↩ in Quick Open** goes through `onKeyPress`, as the arrows do: a
  review caught that Option-Return in a text field inserts a line break and
  never submits, so the first draft's `onSubmit` check could not have fired.
  Builds; the Quick Open suites pass. Not yet pressed on the real sheet.
- ✅ **Installed** (2026-10-22 16:24, Sam's new rule: install as you build): the
  `g/reference` build replaced /Applications/Capsid.app (the 0.9.7 copy went to
  the Trash), signed by Solanum Code Signing, CDHash 4ec8ff62…, no quarantine;
  it still calls itself 0.9.7, so the update check says up to date.
- ✅ **Measured on a real session** (Sam, 16:40, the installed build): two first
  reads, each the 12-row tail plus 38 more (50 messages): fetch 35 and 33 ms,
  parse 3 and 0 ms, project 3 and 2 ms, 300 KB and 137 KB. The fetch is the wait
  for the daemon, not thread time; the page's thread spends about 5 ms a read.
  An Earlier page (25 rows) has not been read yet.
- ⏳ **Not live:** a real session was opened and read (above); the Earlier page,
  the typing gate against real key presses, ⌥⌘←/→ in the key window, Keep on
  Top, Keep… from a figure (its sheet reads through the Results shelf's
  queue, which has never served with the Results window closed), and Copy
  with Source on a real answer are unverified on the real app; the demo's
  reads are made up, so no cost was measured. Known: Copy with Source on a
  whole answer copies the drawn text, so a table comes out as "Not shown
  here: a table." and a rule as its dash.

## 2026-10-22, Capsid 1.0 M3: Keep, and the Kept window

The first 1.0 feature (the handoff's M3; DESIGN.md, Keep). Keep saves the
one real version of a figure with Claude's words about it, the data it was
drawn from and the script that drew it, into `~/Documents/Kept/<collection>/<name>/`
with a README; the Kept window puts those results beside a manuscript. Two
Sonnet agents built the page reads (`g/keep-reads`) and the on-disk layer
(`g/keep-disk`) in worktrees against a written contract; the sheet, the
model, the Kept window, the Results section and the demo were written here.

- ✅ **The whole suite:** 2,184 tests in 285 suites pass (`swift test --jobs
  2`), 193 of them new: the reads' allowlist, projections and caps against
  a fake `fetch` (SECRET markers never leave the page; an answer for another
  version is refused; lineage with a conversation snapshot is refused), the
  showing-message walk (the four ways, newest wins, thinking and tool inputs
  never read, six pages with overlap, the stop at the oldest version's time,
  abort by nonce), the README's byte-identical round trip with "Z′", CJK and
  an emoji and its strict parser, the legend edit leaving every other byte,
  the disk layer's layout, dated collisions, refusals, the held-disk
  sentences and the scan that allows file-system calls in `KeptDisk.swift`
  alone, the sheet's decisions (`KeepPlanTests`), and the inventory and
  probe suites with the `keep` feature.
- ✅ **The sheet, drawn offscreen** (`CAPSID_SNAPSHOT_DIR`, light and dark,
  before and after a partial keep): three sections on one screen, the
  answer's version ringed in the system's ink, "In the answer" in
  secondary, clay on the checkboxes and on Keep alone (the collection pop-up
  reads in primary), "Kept 2 of 3 files. The data it was drawn from wasn't
  copied." with the row saying why in clay-text, Try Again prominent.
- ✅ **`--demo kept --step sheet | sheet-partial | window | window-empty`**
  captured by window ID (`shoot.sh`) at 12:30: the sheet filled from
  made-up reads; the Kept window on three made-up folders in a temporary
  root (sidebar by collection, the figure on paper, the source line, Copy
  Figure and Copy Legend, the legend, Claude's words with their
  attribution); the empty window. The later captures failed with "could not
  create image from window" (the screen locked, or Screen Recording reset),
  so the final layout was checked offscreen instead.
- ⏳ **A real keep, end to end,** on a live session: the facts, versions,
  lineage and showing-message reads against Claude Science 0.1.70 (the
  shapes come from its shipped bundle, not from a running daemon), the
  thumbnails in the strip, the sha256 against the daemon's checksum, the
  folder in `~/Documents/Kept` and macOS's one-time Documents prompt, the
  Kept section in Results, and the Kept window on it. Needs Sam and a
  session with a figure; `Capsid --diagnose` with the window open now probes
  the versions and facts reads on the shown session's plan artifact.
- ⏳ **The legend's outside-edit refusal and Use Mine / Use Theirs** in the
  real window; drag of the figure into Pages and Word; Quick Look on a kept
  file; File → Keep… (⌥⌘K) from a selected row and Kept… (⇧⌘K) in the real
  app; the Keep button's dimming while a probe fails (not wired: the probes
  record no misses yet, M2.5's gate).
- ⏳ **Idle cost** with the Kept window open: by design nothing polls (the
  folders are read when a window opens or a keep lands), not measured.
- Not in 1.0's first cut, said in DESIGN.md: the "raw input" row (the list
  projection drops `is_user_upload`); Developer ID's effect on the Documents
  prompt; a sweep of leftover hidden `.keeping-` folders.
- Sam's calls still open: the Kept root (`~/Documents/Kept` built in) and
  collections defaulting to the project's name (built in).

## 2026-10-22, Capsid 1.0 M2.1: updates install natively, and the old copy waits

The first 1.0 milestone (the handoff's M2.1). Until now Install ran the
README's `curl … main/install.sh | zsh`, a script fetched live from `main`
that deleted the installed app before the new one was in place and checked
nothing about the download. Now Capsid downloads the offered release's own
Bench.zip, checks it is signed the way the running copy is and says the
version offered, and runs a shipped script that swaps it in and keeps the old
copy until the new one has been running for two seconds (DESIGN.md, Update
check → Installing natively).

- ✅ **The live download and every check, against the real v0.9.7 release**
  (`build/Capsid.app/Contents/MacOS/Capsid --update-dry-run v0.9.7`, a build
  signed with Solanum Code Signing): GitHub's redirect to its content host,
  the unzip, no quarantine mark, the running copy's designated requirement
  met, `codesign --verify --deep --strict`, bundle id and version, all in
  1.8 s; it stopped before the swap, as a dry run does, and left nothing in
  Caches. `--update-dry-run v0.0.1` (no such release) stopped at the download
  with "The download from GitHub stopped before it finished. You still have
  0.9.7, and nothing was changed."; `--update-dry-run latest` was refused
  before any request.
- ✅ **swap.sh against scratch bundles** (`SwapScriptTests`, 7 tests, 11 s):
  the swap with the old copy kept at `.previous`; a new copy that never
  starts is moved into the state folder and the old one comes back; a move
  that fails puts the old copy back; a running copy that never quits is left
  alone; a stale `.previous` is moved into the state folder first; bad
  arguments are refused; build-app.sh ships the script.
- ✅ **The flow with fakes** (`UpdateInstallTests`, 27 tests): a good download
  is checked, the script is started from its copy in the state folder with
  the right arguments and Capsid quits; a download that stops, no room, a zip
  without Capsid, a copy signed another way, quarantined, of another version
  or another bundle id, a copy without the script, and a cancel
  mid-download all touch nothing and leave nothing behind; the marker and the
  `.previous` copy at the next launch (removed only when older).
- ✅ **install.sh, rewritten and run against the real release** in a scratch
  folder (`BENCH_INSTALL_DIR`): a first install of 0.9.7 (verified,
  unquarantined, no `.previous` left), a second run over it (the inode
  changed), a stale `.previous` cleared, the first `mv` failing (an immutable
  file, then a read-only folder: exit 1, "Nothing was changed.", the original
  untouched), the final `mv` failing (injected: the old copy put back), the
  API fallback (`127.0.0.1:9`, then bad tags `v0.9.7/../../evil`, `latest`,
  empty: all fall back to `releases/latest/download`), and an offline
  harness of tiny signed executables: a new copy that runs, one that dies
  after 1 s (rolled back, the old one relaunched), one that dies at once, a
  fresh install whose copy dies, a tampered signature (nothing quit), the
  quarantine tripwire, and Bench.app → Capsid.app with and without the new
  copy starting. About 11 API calls were spent. The script is 183 lines.
- ✅ **The whole suite:** 2,025 tests in 261 suites pass (`swift test --jobs
  2`), 34 of them new.
- ✅ **The popover's phases drawn offscreen** (`CAPSID_SNAPSHOT_DIR`): the
  offer, "Downloading Capsid 0.9.7… 3.1 of 9.4 MB" with a clay bar and
  Cancel, "Checking the signature…", "Installing… Capsid will reopen in a
  moment.", and a copy that can't install, light and dark.
- ✅ **swap.sh through its production path, no hooks:** against a scratch
  Applications folder holding two fake Capsid.app bundles (a tiny Mach-O
  that sleeps, bundle id `test.capsid.swap.fake`, versions 9.9.8 and 9.9.9),
  with the real `/usr/bin/open` and the real `ps -axo pid=,comm=` exact
  match: marker `installed 9.9.9`, the new copy running from the scratch
  path (`comm` shows the bundle path in full), the old one kept at
  `.previous`, 4 s end to end. The dry run had already read a real bundle's
  Info.plist the way the launch after does.
- ⏳ **The chain as one, on the real app:** `UpdateChecker.install()` →
  the flow → `UpdateSwap.launch` → `terminate` → swap.sh → a real Capsid
  relaunched → `UpdateAftermath` at its launch (the "Capsid 1.0 is installed"
  card, the old copy gone). `install()` runs only from
  /Applications/Capsid.app and the dry run stops before the swap by design,
  so this needs a release newer than 0.9.7 on GitHub: the first thing to
  watch when 1.0's first release goes out, with
  `~/Library/Caches/local.sam.bench/update/swap.log` as the record. Until
  then, 0.9.7 copies update through `main`'s install.sh.
- ⏳ **A download over the 200 MB cap, and a stalled one:** the delegate
  stops the first and the alert says "stopped before it finished" (a
  cancelled session answer is told apart from the user's Cancel by
  `Task.isCancelled`); the second waits 60 s. Neither can be made with a
  real release.
- ⏳ **install.sh run by 0.9.7's own Update button** (its `curl | zsh` child
  outliving the quit through the longer swap): not seen; the same risk the
  old script had, with a wider window. Watch the first 0.9.7 → 1.0 update.
- ⏳ **A download cancelled from the popover, and the failure alerts** (Try
  Again, Later, Release Notes): drawn, not clicked.
- ⏳ **The first Developer ID-signed release** will fail the "signed the way
  this copy is" check from a self-signed copy, by design: one manual install
  then (DESIGN.md says so; M2.6 can widen the requirement).
- Not pushed: `main`'s install.sh is what every 0.9.7 runs, so the push is
  its own release step, after Sam's go.

## 2026-10-22, Capsid 0.9.7: updates you notice and install in one click

Capsid already had an update check, but it was off unless someone found the
switch, and an update it did find was easy to miss and fiddly to install: the
card had no button and said to use a menu. Sam chose to turn the check on by
default, tell people subtly, and make installing one click away.

- ✅ Released as v0.9.7 (tag on f7a323a) and installed from the release zip:
  0.9.7 (45), CDHash `9573e055…`, the same as the download and the local
  build. The first try at `gh release create` came before the push and
  GitHub refused the target commit (422); nothing was made, and the second
  worked.
- ✅ Seen live: `checkForUpdates` was never set on this Mac, so the new
  default turned the check on. It ran by itself 30 s after launch
  (09:16:35) and said up to date (GitHub's latest was still 0.9.6), with no
  card and no toolbar button.

- `checkForUpdates` is registered on, in the welcome window and in Settings
  too. Someone who turned it off has a stored `false`, which still wins.
- **Skip This Version** (`updateSkippedVersion`, `UpdateRules.shouldOffer`):
  hushes that version and anything older, never a newer one. The card, the
  toolbar button and the Dock item stop offering it; Settings and the menu's
  alert still show it, since you asked there.
- The card has **Install…** (`LabNotice.Action.installUpdate`). It dismisses
  itself and then opens the offer alert, so the alert doesn't hold the card on
  screen. One `UpdatePrompts.offer` serves the card, the Dock item and the
  menu: Install (a copy in Applications only), Release Notes, Later, and a
  "Skip this version" checkbox.
- The install sentence adds "Your sessions keep running in Claude Science."
- A toolbar **Update** button (clay arrow and the word) first among the
  trailing items, only while an update is offered and never in a demo, with a
  popover (`UpdateOfferView`): icon, "Capsid X is available", "You have Y.",
  the install sentence, and Skip This Version, Release Notes, Install and
  Reopen. The Dock menu starts with "Install Capsid X…" under the same
  conditions.
- Review fix: the button first followed `state`, so it would have blinked out
  during each daily check and vanished for a day after a failed one
  (offline, rate-limited). It now follows `newest`, which only a check that
  answers changes; a test walks offline, a 403 and then up to date.
- Docs follow: README's privacy sentence and Updates paragraph, DESIGN.md's
  Update check (and the Settings defaults and welcome notes), version 0.9.7
  (45).

- ✅ Drawn offscreen, light and dark, for the three states the popover has
  (install, installing, a copy that can't install), and looked at. It showed a
  real fault: at 320 across, "Skip This Version" wrapped onto two lines, so the
  content is 360 across. `ImageRenderer` leaves a "no entry" sign where a
  borderless button should be, so the test draws through an `NSHostingView`
  that is never put in a window (`CAPSID_SNAPSHOT_DIR`; without it the test
  does nothing).
- ✅ Builds with no warnings.
- ⏳ Not seen live (they need a release newer than 0.9.7 on GitHub: a 0.9.6
  is offered 0.9.7 the old way, with no toolbar button): the toolbar capsule, and
  that no empty capsule is left once the update is skipped or installed; the
  popover in a real window, with Capsid's own icon; the card's Install…
  button; the Dock item; the alert's "Skip this version" checkbox. The
  installer was not run, and no test goes online.

Automated:

- ✅ `swift test`: 1,991 tests in 256 suites, all passing (on the branch; 1,985 before, six new).

## 2026-10-21, Capsid 0.9.6: the window reconnects on its own

Claude Science 0.1.69 installed itself at 21:42 while another session ran
Simulator UI tests; its cold start froze the daemon twice (60 and 65 s, its
own stall reports) and requests took up to 158 s. Capsid's log: usage and
context reads timed out (21:44, 21:47), the main frame timed out (21:50,
"isn't responding on port 8765"), a Try again failed on `status`'s 5 s limit
(21:53), and nothing read again until 22:14. Nothing Capsid relies on changed
in 0.1.69: every page hook is in its web bundle, every route and field in the
binary, every column in its migrations, and no migration ran.

- ✅ Released as v0.9.6 (tag on 471fa93) and installed from the release zip:
  0.9.6 (44), CDHash `2882900e…`, the same as the download and the local
  build. After the relaunch it pressed Claude Science's Sign in once (the
  designed path after a restart) and read usage; phone server listening.
  Tailscale was stopped on the Mac at the time, so the phone wasn't tried.

- `StartRetry` retries a failure that may pass (DESIGN.md, Daemon and
  sign-in, Reconnecting): waits 5, 10, 20, 40 s, a minute ×15, then five
  minutes; asks `status` quietly and signs in only to a daemon that answers
  "running"; never runs `serve`. Try again and a ready page start the waits
  over. The failure overlay adds one line saying it reconnects by itself.
- `DaemonError.statusFailed` no longer says "Try again in a moment."
- 9 tests (`StartRetryTests`): the waits, which errors are retried, a try
  signs in once the daemon answers, a second begin does nothing, Try again
  during a wait ends it with no question asked, a window no longer failing
  is left alone, a sign-in that fails again keeps the waits growing.
- ⏳ Not seen live: it needs a daemon that stops answering, and we never stop
  or freeze Claude Science on purpose. Watch for it the next time Claude
  Science updates while Capsid is open.

Automated:

- ✅ `swift test`: 1,985 tests in 255 suites, all passing (on the branch).

## 2026-10-21, Capsid 0.9.5: six app icons

Sam asked for an ivory icon and a choice of colours. Solanum's brand book
allows three icon grounds (Ivory, Slate, Clay) and says which parts take clay,
so six: Clay (the default, unchanged), Ivory, Slate, Ivory one color, Slate
one color, Ivory and Clay (DESIGN.md, App icon).

- ✅ Released as v0.9.5 and installed with `install.sh`: 0.9.5 (43), CDHash
  `160bb7f3…`, the same as the download and the local build, and running;
  phone access came back by itself.

- `Scripts/make-icon-variants.py` splits `bench-glyph.png` into ring, capsid
  and escaped dot by radius and verifies the layers composite back to it
  pixel for pixel; the variants are Icon Composer documents in
  `Resources/AppIconVariants/`. No edge on the Ivory tiles: the format has no
  border, and a drawn one doubled with the system's own edge highlight.
- The first cut shipped each variant as a 256 px `.icns`, soft at full Dock
  magnification. `Scripts/compile-icons.sh` now compiles all six in one
  actool call as alternate app icons (`--alternate-app-icon`,
  `--include-all-app-icons`), so each has reps up to 1,024 px with the
  system's treatment. Cost: Assets.car 1.7 → 10.1 MB, the zipped app 6.5 →
  14.6 MB; Sam chose all six anyway. README's "3 MB download" (already wrong)
  now says 15 MB.
- Settings → General → App icon: six tiles; the choice sets
  `NSApp.applicationIconImage` (the Dock while Capsid runs, Settings' header,
  Welcome). Finder, Launchpad and a pinned Dock tile while Capsid is quit keep
  Clay: changing those means altering the signed bundle. 20 tests, an
  end-to-end compile included; mutations caught.
- ⏳ Not seen: the real Dock (and whether it uses the 1,024 px rep), Dark and
  Tinted icon styles, the badge over a custom icon, VoiceOver.

Automated:

- ✅ `swift test`: 1,976 tests in 254 suites, all passing (on the branch).

## 2026-10-20, Capsid 0.9.4: Results never touches the disk on the main thread

From the Codex review's item 4, built by a Sonnet agent and reviewed here.

- ✅ Released as v0.9.4 and installed with `install.sh`: 0.9.4 (42), CDHash
  `9a71a2aa…`, the same as the download and the local build, and running;
  phone access came back by itself.

- Every file-system call in Results (destination checks, Save All's names,
  the remembered folder, the saved copy behind Open and Reveal) now goes
  through the disk-work layer off the main actor, under the writes' time
  limits and 30 s hold-off. Save All names its files from one listing of the
  folder (capped at 10,000; by name past that), and the final "is the name
  free" check happens inside the write's own call. A folder that doesn't
  answer fails the batch at once with the existing wording, downloading
  nothing.
- The remembered folder before a Save panel has its own 3 s limit (the
  agent's first cut used 15 s, which made a panel wait too long on a dead
  drive); after it the panel opens in Downloads.
- `ResultsDiskCallsTests` fails if a new file-system call appears in
  Results. About 33 rule mutations, all caught but two redundant hold-off
  guards (caught together).
- The query-cancellation test that failed once under load now waits for the
  read to be waiting before cancelling, with no real deadline in the way
  (`SQLiteReadCancellation.waiterCount`, for tests); the broken wake-up fails
  it 3 runs in 3.
- ⏳ Not seen: a real slow or disconnected volume.

Automated:

- ✅ `swift test`: **1,956 tests in 253 suites, all passing in one run**.

## 2026-10-20, Capsid 0.9.3: thirteen specimens (541), phone follow-ups

0.9.2 was built and pushed but never published as a release; its changes
(next entry) ship in 0.9.3 with these.

- ✅ Installed from the release zip (`Bench.zip`, the same bytes to be
  published as v0.9.3), the way `install.sh` does it, since the release
  wasn't published yet: /Applications/Capsid.app is 0.9.3 (41), CDHash
  `494a7e3e…`, and running; phone access came back by itself.
- ✅ Published as v0.9.3 (Latest); its download's CDHash matches the installed
  app.

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

