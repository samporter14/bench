# Bench — live test log

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

