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
