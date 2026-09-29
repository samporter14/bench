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
