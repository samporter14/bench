# Capsid — design

Capsid is a small native Mac app for Claude Science. It shows Claude Science's
web UI in one native window, so there is never a Safari tab, and it plays the
Science Status lab scenes in a floating Liquid Glass panel in the bottom-right
corner while a session works. That panel is also where "needs your input"
comes from. Internal only. macOS 27 only (Sam, 2026-09-29: build against macOS 27 exclusively), Swift 6, SwiftUI + AppKit, no
third-party dependencies.

## Principles

1. **Lightweight and native.** One process, system frameworks only: SwiftUI,
   AppKit, WebKit. No Electron, no web frameworks of our own, no timers
   running while nothing happens.
2. **Don't reinvent the wheel.** Use the system's own toolbar, menus,
   buttons, materials and Liquid Glass. Our look comes from the palette and a
   few deliberate choices, not custom chrome.
3. **Claude Science owns the page.** We never restyle, inject into or scrape
   its UI. The one exception is the notification bridge (below), which adds
   an API WebKit lacks.
4. **One Claude Science document, ever.** Claude Science works in one tab at a
   time. Capsid holds exactly one web view on the daemon's address, created
   once and never recreated.

## Look

- Palette (Theme.swift): clay `#D97757` is the one accent. Slate `#141413` and
  ivory `#F0EEE6` are the neutrals. Otherwise use system semantic colours
  (`.primary`, `.secondary`) so light and dark both work. There are no
  gradients, no drop shadows of our own, and no second accent hue. Clay marks
  only the primary action, the live dot and "needs you".
- Liquid Glass (macOS 26 SDK; these are the exact APIs):
  - `.glassEffect(_ glass: Glass = .regular, in shape: some Shape)`
  - `Glass.regular`, `Glass.clear`, `Glass.identity`, `.tint(Color?)`, `.interactive(Bool)`
  - `GlassEffectContainer(spacing: CGFloat? = nil) { … }`, to group and morph glass shapes
  - `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` (with `.tint(Theme.clay)` for primary)
  - AppKit: `NSGlassEffectView` (`contentView`, `cornerRadius`, `tintColor`)
  The standard window toolbar is already glass on macOS 26, so don't build
  our own.
- Type: the system font. Titles are semibold, captions 11pt medium in
  secondary, and times use monospaced digits.
- Motion: springs (`.spring(duration: 0.35, bounce: 0.15)`) for the panel's
  entrance and resize, and nothing else moves except the scenes. With
  Reduce Motion on there are no springs, and a waiting glyph is still.
- Scenes: the droplet's own. `PlayedGlyph(tint:rotation:)` for the working
  rotation and `PlayedLoop(glyph:tint:)` for a waiting reason. They draw in
  `.primary` ink with clay accents built in. The panel shows them at 88pt,
  about five times the Droppy pill. Measured cost is under 6 ms per second of
  frames at 96pt (`Capsid --measure-sheets 48,72,96`).

## Where the glass goes

Sam's rule: our design language, with Liquid Glass wherever it can go.

**Glass surfaces** (`.glassEffect`):
- the scenes panel (one shape);
- the toolbar (the system's own);
- popovers (the system's own);
- the find bar;
- the Usage headline stat tiles (`.regular` in `.rect(cornerRadius: 16)`,
  grouped in one `GlassEffectContainer`);
- the graph's hover label;
- the category chips (`.regular.interactive()` in `.capsule`; clay-tinted
  when on: `.regular.tint(Theme.clay.opacity(0.35)).interactive()`);
- the Size picker's live preview well;
- the search field's capsule;
- the hovered scene cell only.

Group neighbouring glass (a row of chips, the stat tiles) in one
`GlassEffectContainer(spacing:)` so the shapes blend.

**Not glass:**
- the 528 grid cells. That many glass layers costs frames. They get
  a quiet `Color.primary.opacity(0.05)` fill, and a clay check when on.
- the page itself;
- text.

**Buttons:** `.glass` everywhere; `.glassProminent` with `.tint(Theme.clay)`
only for the one primary action in view.

**Colour:** clay stays the only accent: the on-state, the live dot, "needs
you", and the graph's steps. No other hues, no gradients.

## Main window

- **Specimens split button** (Lab/ScenesToolbarButton.swift): one glass
  capsule, with "🧪 Specimens" (a click shows or hides the panel) | ⌄. The
  arrow opens a glass POPOVER with the panel switch, the size, the category
  checkboxes (the same `CategoryChip` as Settings), "N of 528 on" and
  "Choose specimens one by one…" (`SettingsWindow.open(tab:)`). It is not a SwiftUI Menu: in
  this AppKit window's toolbar a Menu kept the ticks it was first drawn
  with, and showed stale settings.

- One window, "Claude Science", with a default size of 1360×900, a minimum
  of 900×600 and an autosaved frame.
- Toolbar (unified compact, system glass). No back/forward/reload buttons:
  Claude Science has its own navigation, and ⌘[ ⌘] ⌘R stay in the menus.
  Trailing, left to right:
  - the **Lab status capsule** (only while something works or waits);
  - **Usage** (see Usage);
  - **Scenes**, a split button. Its click toggles the scenes panel. It shows
    a clay `flask.fill` and "Scenes" when on, and a secondary `flask` and
    "Scenes off" when off, always as title and icon. Its menu has:
    - "Show scenes panel" (⌘⇧L);
    - a Size picker (Small, Medium, Large);
    - one toggle per category (title and count);
    - "Choose scenes…", which opens Settings on the Scenes tab.
  - The title is hidden, because the page has its own header.
- The web view sits below the toolbar, not under it.
- Closing the window hides it (the web view and its state survive). Clicking
  the Dock icon brings it back. ⌘Q quits Capsid but never stops the daemon.
- Menus:
  - File: Open Session… ⌘⇧O (Quick Open, below), Close Other Tabs ⌥⌘W and
    Close All Tabs (artifact tabs, below).
  - View: Reload ⌘R, Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0, Find ⌘F,
    Show Lab Panel ⌘⇧L.
  - History: Back ⌘[, Forward ⌘].
  - Reload, Zoom, Find and Back/Forward act on **the page in front**
    (Web/WebPageWindow.swift), not always the main window's. That is the key
    window's web page if it has one: the main window's, a Browser or Preview
    window's, or a pop-up's. A sheet or panel over a page (Quick Open, an
    alert) leaves the page under it the target. A window with no page, such
    as Settings or Diagnostics, dims these items, and so does having no
    window in front. Open Session and Show Lab Panel are not about a page
    and stay as they were. Each window has its own find bar and, apart from
    the main window's, its own zoom (see Web routing policy).
    `ActiveWebPage` watches the key and main windows and publishes whether
    there is a page, for `.disabled`. It isn't `@FocusedValue`: the windows
    are AppKit's and a web view is their first responder, so SwiftUI's focus
    holds nothing for it to read.
  - Window: the standard items.
  - Settings ⌘,.
- **Close Other Tabs and Close All Tabs** (Web/PageTabs.swift, Web/TabContextMenu.swift,
  since 0.7.2). Claude Science opens each artifact (a file, result or figure) as a tab in
  its right-hand panel and has no command to close the rest. File → Close Other Tabs
  (⌥⌘W, Safari's) closes every tab but the one shown; Close All Tabs has no shortcut.
  Nothing else in Capsid uses ⌥⌘W, and the page binds no ⌘W or ⌥⌘W. Both act on the main
  window's page only (not `ActiveWebPage`'s choice) and are on only while the main window
  is the key window and the page is ready, so a Browser window, Settings or a sheet in
  front dims them (`PageTabCommands`). With no tabs they do nothing. A right-click on a
  tab also puts Close Tab, Close Other Tabs (keeping the tab clicked) and Close All Tabs,
  then a separator, at the top of WebKit's menu.
  - **They press the page's own close buttons**, one tab at a time, from inside the page
    (`callAsyncJavaScript`, `.defaultClient`), so the page's own check before discarding
    unsaved edits still applies. The strip is read again after every press. In 0.1.63 that
    check is not a `confirm`: the page raises its own dialog and keeps the tab until it is
    answered, and a second close that needs an answer would replace the first dialog. So
    each press waits up to 300 ms for the tab to leave, and the sweep stops at the first tab
    that is still there. That tab and the ones after it stay, and are counted as such; the
    user answers the page and asks again. Only one sweep runs at a time.
  - **Selectors relied on (Claude Science 0.1.63):** one `[data-testid="right-tab-strip"]`
    holding `[role="toolbar"][aria-label="Open panels"]`; in it each tab is
    `[data-tab-id]`, with `[data-tab-btn]` (`aria-current="true"` on the shown tab, or
    `data-shown` on the tab) and `button[data-tab-close]`. Tabs are looked for only inside
    the toolbar, and only those close buttons are pressed. If the strip, the toolbar or a
    close button of a tab to close is missing, or there are two strips, nothing is pressed.
    A tab to keep that is not in the strip also presses nothing. A newer Claude Science that
    changes this markup makes the commands do nothing; the right-click target uses
    `[data-testid="right-tab-strip"] [data-tab-id]`.
  - **The right-click target** comes from a user script in its own content world
    (`capsid-tabs`, document start, main frame only) with a capturing `contextmenu`
    listener. It posts `{tab: <id>}` when the click is on a tab and `{tab: null}` for
    anything else. Only the main web view's main frame on the daemon's origin is heard. The
    main window's web view is a `TabMenuWebView`, which adds the items in `willOpenMenu`
    if the last message named a tab less than a second ago, and uses it once. The message is
    sent from inside the event and WebKit asks for the menu after it, over one connection, so
    it should come first; that is not an API guarantee. If it didn't, the tab is not fresh
    and the menu simply has no extra items, so the File menu is the main path.
- The Dock badge is the number of sessions waiting for input, or no badge.
- URL scheme `bench://open?url=<percent-encoded daemon URL>`, and
  `bench://session?project=<id>&frame=<id>`. Both show the window and
  navigate the one web view. This is for the droplet to hand Open to Capsid
  later.

## Daemon and sign-in (Web/DaemonController.swift)

- **Lost session.** Often, right after a restart, the page shows Claude
  Science's own "Sign in" card and its API reads come back 401. A fresh
  `claude-science url` code does NOT fix it (tested 2026-09-29), but pressing
  the card's Sign in button goes straight back in, with no password or
  consent (Sam). So when `apiGET` (or the one write, `apiPOST`) gets a 401,
  `WebContainer.sessionLost()`
  presses the first visible "Sign in" button, looking for it over 6 s, then
  refreshes the plan readout. With no button it falls back to the fresh code.
  At most once every ten minutes.
- **SIGTERM quits like ⌘Q** (a DispatchSource in AppDelegate), so the web
  view saves its session. The installer quits Capsid with that signal.

- Run `claude-science status` (shared `fetchCLIStatus`) off the main thread.
  If the daemon isn't running, run `claude-science serve --no-browser
  --detached` once, with no other flags, then poll `status` every 0.5 s for
  up to 20 s.
- Never run `stop` or `serve` while it is running, never pass
  port/data-dir flags, never restart it.
- Port: `status.port`. Daemon origins are `http://localhost:<port>` and
  `http://127.0.0.1:<port>`. Any other localhost or 127.0.0.1 port is a
  **preview origin** (Claude Science serves generated HTML previews on a
  separate port, normally port+1).
- Sign-in: load `http://localhost:<port>/?nonce=<fresh nonce>` (shared
  `fetchLoginNonce()`; it is single use and lasts about 3 minutes). The
  daemon sets its cookie and redirects. If a later main-frame response from
  the daemon origin is HTTP 401, fetch a fresh nonce and reload the same path
  with it, at most once per 30 s.
- Use `WKWebsiteDataStore.default()` so cookies and localStorage persist.

## Web routing policy (Web/)

Every link goes through one function. The rules:

| What | Where it goes |
|---|---|
| Main-frame navigation to a daemon origin | The main web view |
| `window.open` / `_blank` to a daemon-origin URL | Cancel it, and load the URL in the **main** web view |
| `window.open("about:blank" or "", name)` (Claude Science's pop-out window pool and connector OAuth pop-ups) | A real child `WKWebView` made from the configuration WebKit hands to `createWebViewWith`, in its own NSWindow (so `window.opener` and `postMessage` work). Close that window on `webViewDidClose`. |
| Anything in a child/pop-up window (including OAuth to other sites) | Stays in that child window |
| Iframes to a preview origin | Allowed |
| New window or top-level nav to a preview origin | An in-app **Preview** window |
| Any other http(s) (docs, GitHub, claude.ai, papers) | An in-app **Browser** window: a WKWebView with Back/Forward/Reload, the URL shown, and an "Open in Safari" button (the only way to reach Safari, and only on the user's click) |
| `mailto:` / other schemes | `NSWorkspace.shared.open` |

- `javaScriptCanOpenWindowsAutomatically = false`, as in Safari; the pop-ups
  come from clicks. Change it only if the pool fails in testing.
- `WKUIDelegate`:
  - `runOpenPanelWith`: NSOpenPanel, honouring multiple selection and
    directories.
  - `runJavaScriptAlertPanel`, `Confirm` and `TextInput`: NSAlert sheets on
    the webview's window.
  - `requestMediaCapturePermissionFor`: grant for daemon origins only, deny
    others. The app's Info.plist has `NSMicrophoneUsageDescription` and
    `NSCameraUsageDescription`.
  - `webViewDidClose`: close the pop-up window.
- Downloads:
  - `navigationAction.shouldPerformDownload` (blob URLs and the `download`
    attribute) gives `.download`.
  - `navigationResponse` gives `.download` when it isn't `canShowMIMEType`,
    or on `Content-Disposition: attachment`.
  - `WKDownloadDelegate` saves to ~/Downloads with a unique name, then posts
    a "Saved <name>" item to the Lab panel with a Show in Finder action.
  - A download that fails (not one cancelled) says so in an alert, as a
    sheet on the main window: "Couldn't download "name"" and the reason.
    Before 0.3.1 it was only logged.
- **Calls to Claude Science's API** (Web/WebAPI.swift) are made from inside
  the page with `callAsyncJavaScript`, in Capsid's `.defaultClient` script
  world, so the page's cookie session carries them and Capsid never holds it:
  - `apiGET` reads, and only under `/api/usage`, (since 0.3.4, for a plan's
    card) `/api/artifacts/versions/`, and a frame exactly as
    `/api/frames/<36>?shallow=true` (the card) or
    `/api/frames/<id>/token-series` (the context ring); never a path with
    `..`, and never `/frames/<id>/messages` (since 0.4.0
    `WebContainer.isReadablePath`). A session's messages are read only by the
    phone's session reader, which projects them in the page (Capsid on your
    phone → Reading a session).
  - `apiPOST` is the **one write** (since 0.3.4). It accepts exactly one
    route, `^/frames/[0-9a-f-]{36}/approve-plan$` (`WebContainer.isWritablePath`),
    and its body is always exactly `{}`. It sends the `operon_csrf` cookie's
    value as `x-operon-csrf`, with `credentials: "include"` and
    `Content-Type: application/json`; the browser adds the page's `Origin`.
    On 403 `{code: "csrf_stale"}` it calls `GET /api/csrf` (inside the same
    script, not through `apiGET`) and retries once. It returns the status
    and the JSON `code` (and whether the body says "No plan awaiting"), never
    the body itself. A 401 calls `sessionLost()`, as `apiGET` does. See
    Approving a plan from its card. Since 0.4.0 the phone's writes go through
    their own writer (Capsid on your phone → Actions); `apiPOST` is unchanged.
- `isInspectable = true` (internal build).
- `isElementFullscreenEnabled = true`.
- Find (⌘F): a small find bar under the toolbar that uses
  `WKWebView.find(_:configuration:completionHandler:)`, with Return/⇧Return
  for next/previous and Esc to close. The main window, every Browser and
  Preview window and every pop-up has its own: `FindBar` over a `PageFinder`
  per window. A pop-up's content is hosted in SwiftUI (`NSHostingView`, as the
  Browser window's is) so the bar can sit over its web view.
- Zoom: `pageZoom` in 0.1 steps between 0.5 and 3.0 (`PageZoom`). The main
  window's is persisted. Every other window zooms on its own, starts at actual
  size and isn't remembered.

## Notification bridge (Web/NotificationBridge.swift)

WKWebView has no `Notification` API, so Claude Science's own desktop
notifications (session done, needs input) are off in a plain web view.

- A user script injected at document start, main frame only, defines
  `window.Notification`:
  - `permission` returns `"granted"`, and `requestPermission()` resolves
    `"granted"`.
  - `new Notification(title, {body, tag, requireInteraction})` posts
    `{id, title, body, tag, requireInteraction}` to the message handler
    `benchNotify`. It keeps the instance in a map by `id`; `close()` posts
    `{id, closed: true}`.
  - Native calls `window.__benchNotificationClicked(id)` to run that
    instance's `onclick`.
- Native side: forward it to the Router as a `WebNotification`. The Lab panel
  shows it as an attention card, and Open shows the window and calls the
  click. De-duplicate against the session engine. The tag is
  `operon-<root_frame_id>`, so if the session engine already showed that
  frame in the last 10 s, drop it.

## Lab (Lab/)

### LabModel

A port of the droplet's watching loop, with no DroppyKit:

- **Source.** `CombinedScienceSource()`: call `snapshot()` off the main
  thread.
- **When to read.** On every `DatabaseWatcher` change of `source.database`,
  and on a fallback timer (3 s while something works, 30 s otherwise). Only
  one read runs at a time; a change that arrives during a read triggers one
  more read after it.
- **Transitions.** `ScienceEngine(minDuration: 30).advance(to:)` gives the
  `.started`, `.finished` and `.needsInput` transitions.
- **Published state.** `snapshot`, `working: [SessionStatus]` (running) and
  `waiting: [SessionStatus]` (needsInput).
- **The card queue.** `cards: [LabCard]` is ordered with needs-input first,
  then web notifications, then finished and saved-download cards. Cards
  leave when they are acted on, dismissed or no longer true.
- **The Dock badge** is the waiting count.
- **Stop.** Everything stops in `stop()`.

### LabCard

```swift
enum LabCard: Identifiable {
  case needsInput(SessionStatus)
  case failed(SessionStatus)
  case finished(SessionStatus)
  case web(WebNotification)
  case saved(URL)
}
```

The queue runs needs-input, then failed, then page notifications, then
finished and saved. Only the card on top counts down: one queued behind
another starts its time when it reaches the top, so a finish behind a
question is still seen.

- `needsInput` stays until the session stops waiting, and shows what it waits
  for now: a question that becomes a plan to approve updates in place. A
  plan's card approved from the panel stays a moment longer: `PlanApprover`
  holds it through the approval and its "Approved ✓" (`holdPlanCard`,
  `releasePlanCard`), and a new request from the session, or the card
  going, ends the hold. A new
  kind of request comes back even after the last one was dismissed (the ×
  or Dismiss). Later puts a card off instead of dismissing it, below.
- **Later** takes a `needsInput` card out of the queue and brings it back at
  a time, a reminder kept in `LabModel` by session id.
  - **When.** In 5 minutes (a click on Later itself), in 15 minutes, or
    after the Nidus focus session that is on. That one is offered only while
    `NidusFocus` says one is on, whether or not finishes are held for it; if
    the session ended since the menu opened, it is the 5 minutes. A timed
    reminder is a `Task.sleep` scaled by `lifetimeScale`, as the card
    lifetimes are, cancelled with the reminder. A focus reminder is woken by
    `focusEnded()`, which `NidusFocus` calls as the session ends. Nothing
    polls.
  - **Comes back only if the session still waits.** It returns as a
    needs-input card saying what the session waits for now, with the sound
    (when that setting is on). A session that stopped waiting (answered
    elsewhere, finished or failed) drops its reminder at that read, silently.
  - **A new kind of request** shows at once, as for any card, and clears the
    reminder. Opening the session clears it too.
  - **Dismiss is still for good.** The × and the Later menu's Dismiss do what
    they did: the card goes, and only a new kind of request brings it back.
  - **Seen and managed.** `LabModel` keeps each reminder's due
    time with it: the `Date` it wakes, or none for After My Focus Session.
    `snoozed` publishes the put-off sessions that still wait as
    `SnoozedReminder`s (the session as last read, and its due time), in the
    order they wait; the activity list and the Dock menu show them. A session
    that stops waiting leaves `snoozed` with its reminder.
    - `showNow(sessionID)` brings a reminder forward: its timer is cancelled
      (an old one must not wake a later reminder on the same session) and the
      card returns at once if the session still waits, saying what it waits
      for now. No sound: the user asked for it.
    - `cancelReminder(sessionID)` drops the reminder silently. The card does
      not return and the session stays dismissed, as after Dismiss, until it
      asks something new.
  - **In memory only**, like Recent: nothing about sessions is written to
    disk, due times included. A put-off session stays in the activity list's
    Needs you and in the Dock badge, which count what waits, not what is on
    the panel.
- `failed` ("Stopped with an error", Open and Dismiss, with the sound) comes
  when a working or waiting session ends in an error, and stays until it is
  opened, dismissed, or the session runs again.
- `finished` lasts 6 s on top.
- `web` lasts until clicked, dismissed or closed by the page, or 8 s on top
  unless `requireInteraction`.
- `saved` lasts 5 s on top.

While the sessions can't be read, the working panel says "Not updating" and
when it last could, with a still symbol instead of the specimen and clock: the
last good list stays as the baseline, but it is not shown as live.

### The panel (LabPanelController + LabPanelView)

The window:

- `NSPanel` with `[.nonactivatingPanel, .borderless]`.
- `level = .floating`.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- `hidesOnDeactivate = false`, `isOpaque = false`, `backgroundColor = .clear`,
  `hasShadow = false` (the glass carries its own).

Position:

- A corner of the **menu-bar screen**'s `visibleFrame`
  (`NSScreen.screens.first`), inset 20pt: bottom right unless Settings →
  Panel → Corner (`panelCorner`, `PanelCorner`) says another, since 0.3.1.
  The content is aligned to that corner and grows from it; a new corner moves
  the panel at once.
- Settings → Panel → Screen (`panelScreen`, `PanelScreen`, since 0.3.3):
  the screen with the menu bar (empty, the default) or one chosen by its
  `localizedName` (display IDs can change on replugging). A chosen screen
  that isn't connected falls back to the menu bar's and is listed as "(not
  connected)", so the choice still reads true.
- Follow screen changes (`didChangeScreenParametersNotification`).

When it shows:

- Whenever something works or a card is up, and the panel isn't turned off.
- Otherwise it fades out and is ordered out: no window at all while idle.

Layout (SwiftUI inside `GlassEffectContainer`, one glass shape
`.glassEffect(.regular, in: .rect(cornerRadius: 26))`, 16pt padding):

- **Working (compact, about 336×120).**
  - Left: an 88×88 scene well playing the rotation.
  - Right column: a caption with a clay live dot and "Working"; the session
    title (15pt semibold, 2 lines); a meta line with the project name, "·"
    and the turn clock `m:ss` (monospaced digits); and "+N more ⌄" when
    several work, a button (since 0.3.3) that pops up the Dock's activity
    menu (`ActivityMenu`) under the pointer, without bringing Capsid to the
    front.
  - Optionally, up to two more quiet lines (11pt, secondary) under the meta
    line: the specimen that's playing, its name in medium weight then its
    caption, "**Kinesin** · A motor protein on a microtubule". Settings →
    Panel → "Name the specimen that's playing" (`showSpecimenCaption`), off
    by default. `SpecimenCaptionLine` follows the rotation, a
    `TimelineView(SceneBoundarySchedule)` that ticks when the specimen
    changes; a specimen with no note is its name alone. Two lines are kept
    (`lineLimit(2, reservesSpace: true)`), so the panel keeps its size while
    the setting is on: the column is about 200pt, too narrow for both on
    one, and a cut caption says little. Under Reduce
    Motion the well is the still flask, and the line names the flask. Not
    shown under "Not updating", where the well is a warning symbol.
- **Needs input (card, about 360×170).**
  - Left well: the reason's waiting glyph (`PlayedLoop`) at 88pt.
  - Caption in clay: `reason.sentence`.
  - Title and project.
  - Buttons: **Open** (`.glassProminent`, clay tint) and **Later** (`.glass`),
    a split pull-down `Menu(primaryAction:)`: a click on Later is "In 5
    Minutes"; its menu has In 5 Minutes, In 15 Minutes, After My Focus
    Session (only while Nidus reports a focus session), a divider and Dismiss.
  - A plan to approve (since 0.3.4, with the setting on): under the project,
    the plan's `task_summary` (12.5 pt, 2 lines, truncated) and "5 steps ·
    feasibility: high" in secondary (its tooltip: "Claude's own estimate of
    how feasible the plan is"); "Loading the plan…" while it is read.
    Under those, when the plan has step titles, a small chevron
    button **Show steps** / **Hide steps** (11 pt, secondary), closed by
    default. Open, it lists the first 8 titles as a numbered list (11 pt, one
    line each, cut at the end), then "and N more…" when there are more.
    When it is ready the buttons are **Approve** (`.glassProminent`, clay,
    the primary action), **Open** (`.glass`) and Later. Pressed, Approve is a
    small spinner; approved, the row reads "Approved ✓" in clay. The card
    keeps its width and grows taller; the panel measures its content, so the
    window follows. See Approving a plan from its card. Beside Show steps,
    **Request changes…** (since 0.7.0).
  - Any other wait (since 0.7.0, with the same setting): the question and
    Reply, or a permission request with Allow Once, Review or Deny. See
    Answering from the card.
- **Finished.**
  - Left well: the flask, still.
  - Caption: "Finished", then the duration and the tokens.
  - Open, and **Results** (`.glass`, since 0.7.0): the Results window on this
    session's files (Results → Opening on one session).
- **Web notification.** Claude Science's title as the caption, then the body,
  then Open.
- **Saved.** "Saved", the file name and Show in Finder.
- **Several cards.** The top card shows, with a small "1 of 3" and a stack
  hint (at most 2 edges peeking).
- **Interaction.**
  - Clicking the panel does what Open does.
  - Hovering shows a small glass × at top-left, which dismisses the current
    card for good (or hides the working panel until the next change).
- **Sound.** When a needs-input card arrives, play `NSSound(named: "Glass")`
  (a setting, on by default).
- **Open.** Activate Capsid, show the window and navigate the web view to the
  session's `deepLink`, through the Router.

### Lab status capsule (toolbar)

A 18pt live scene plus a short text: "Working · 4:12", "2 need you" (in clay),
"Recent" once something has happened, or a quiet "Activity" before then. It is
always in the toolbar since 0.3.1 (it used to vanish when nothing worked or
waited), so the list stays one click away. Clicking it opens the activity
list.

### Activity list (Lab/ActivityList.swift, Lab/ActivityMenu.swift, since 0.2.0)

Every session at once, in a popover under the status capsule and in the Dock
icon's menu: **Needs you** (waiting sessions with their reason, and failures
not yet dismissed), **Working** (with each turn's clock) and **Recent** (the
last 30 events: questions, plans, errors, finishes and saved downloads, in the
past tense, with when). Each row opens its session in the one web view and
closes the list; a saved file shows in Finder. Both read `LabModel`, so
nothing else polls.

A session put off with Later (see Later) keeps its row in **Needs you**,
quieter:

- Where the reason was, a secondary line: "Reminds you at 2:15 PM" (the time
  in the Mac's own format) or "Reminds you after your focus session".
- Its glyph is dimmed, with a small clock on it.
- Two borderless icon buttons at the row's right, with tooltips: **Show Now**
  (`bell`) and **Cancel Reminder** (`bell.slash`). The same two are in the
  row's context menu, with their names. They sit over the row, so they don't
  open the session, and they leave the list open: the row turns back into a
  plain one as the reminder goes.
- A click on the rest of the row still opens the session, which clears the
  reminder.

The Dock menu item's subtitle is the same line. Show Now and Cancel Reminder
are the popover's only: a submenu on the item would take the click that opens
the session, and items of their own would triple the section.

The Dock menu is never empty: with nothing working or waiting it says
"Nothing working right now", and while Recent is still empty (right after a
start) it lists **Latest**, the five sessions active most recently that
neither work nor wait, from the last read. The popover lists Latest the same
way since 0.3.1.

Recent is kept in memory only, so Capsid still writes nothing about sessions to
disk; it lasts until Capsid quits. An event is the kind, the session and its
turn (`startedAt`), so one turn's finish is one entry however often it is
read. Dismissing a card leaves its event in Recent.

The working specimen and the cards are separate settings since 0.2.0
(`showLabPanel`, `showLabCards`): the specimen can be off while questions and
errors still come. Someone who had the whole panel off before keeps the cards
off after updating. Under Reduce Motion the working specimen is a still.

### Quick Open (since 0.3.3)

⌘⇧O, or File → Open Session…: type to jump to a session
(Lab/QuickOpen.swift, Lab/QuickOpenSheet.swift). A sheet on the main window,
560 wide and up to about 420 tall, in system controls: a search field with
focus, and the recent sessions under it. The menu item shows the window first
if it is closed or hidden. It is off in a demo, which has no main window.

- **Rows.** A glyph for the state (the waiting reason's glyph while it waits,
  the working specimen while it works, else a checkmark, a warning triangle
  or a clock), the title over the project, and on the right "Needs you" (in
  clay, the sheet's only accent), "Working · m:ss" or how long ago it was
  last active ("Just now", "5 min. ago").
- **Keys.** ↑ and ↓ move the highlight and stop at the ends, Return opens it,
  Esc closes, and a click opens a row. The highlight follows its session by
  id, so a read that reorders the list while you choose does not move it.
  Typing puts it back on the first row.
- **Which sessions.** Those of the latest read (the ~25 most recently
  active), as `LabModel.sessions`. It holds every state, where `working`,
  `waiting` and `latest` split them up, and like Recent it is in memory
  only: Capsid still writes nothing about sessions to disk, and nothing typed
  is kept.
- **Ranking (`QuickOpen.rank`, pure).** With nothing typed: the sessions that
  need you, then those that work, then the rest, each by most recent
  activity. With a query, only sessions whose title or project matches,
  ignoring case and accents: the start of a word first (after a space or
  punctuation too), then inside a word, then letters in order with others
  between (fuzzy). Within each of those the order is the one for nothing
  typed. A query of several words needs every word to match, in the title or
  the project, and ranks by its worst.
- **Opening.** `LabModel.open(session)`, as every row does: it navigates the
  one web view, and clears that session's cards and reminder. Then the sheet
  closes.

### Notices (Lab/LabNotice.swift, Lab/NoticeWatchers.swift, since 0.3.0)

Cards that tell rather than ask. They queue after every session card, never
play a sound, always time out on top, and respect "Show a card". When each is
due is `NoticeRules`, pure and tested on made-up data.

- **Plan:** one card per window when the 5-hour or the all-models weekly
  limit has 10% or less left ("9% of your 5-hour limit left · Resets in 47
  minutes"), keyed by the window's reset time to the minute; and "has reset"
  only when Capsid saw an announced window end in the last 10 minutes.
- **Plan forecast:** one card per window, "At this pace your 5-hour limit
  runs out around 3:40 PM" (the weekly limit likewise), when the forecast
  (see Title-bar readouts) puts the limit under 45 minutes away and it is
  still under 90% used; the 90% card covers the rest. Its windows are kept
  apart from the Plan ones, so a window can have both. Never in a demo.
- **Context:** one card per session when the session open in the web view
  has used 85% of its context window, naming it.
- **Week in review:** once a new week starts (the activity graph's calendar),
  last week's sessions, messages and busiest day, read off the main thread
  at launch and just after each midnight.
- **While you focused:** see Nidus below.

What has been announced (plan windows, context sessions, the reviewed week)
is kept in Capsid's settings so an update doesn't repeat it; demos keep
nothing. Settings → Usage → Heads-up turns each off.

### Nidus (Lab/NidusFocus.swift, since 0.3.0)

Nidus, the Solanum focus app, writes `~/Library/Application Support/Nidus/
focus.json` (`version`, `focusing`, `until`; never its goal) and posts
`local.sam.nidus.focus` on this Mac when that changes. Capsid counts a focus
session as on only while the file says so, Nidus is running and `until`
hasn't passed, so a file a crash left behind means nothing. While it is on,
"Finished" cards wait (they still go to Recent, and Claude Science's own
notification for the same finish is dropped as usual); questions and errors
come at once. When it ends, the finishes come as one "While you focused"
card, and the cards put off with Later, After My Focus Session, come back if
their sessions still wait.

- **Locked or asleep (since 0.3.6):** Nidus pauses a session's clock while the
  Mac is locked or asleep but keeps blocking, and from Nidus 0.3.1 says so with
  `"away": true` in `focus.json` (`focusing` is false then, with no `until`).
  Capsid treats `away` as still focusing, so held finishes and after-focus
  reminders don't come out behind the lock screen. An older Nidus leaves the
  key out, and its pause ends the hold as before.

### The task you're viewing, for Nidus (Lab/NidusTaskContext.swift, since 0.7.3)

The other way round, and off by default: Settings → General → Nidus → "Share
the task I'm viewing with Nidus". Nidus's activity record can then name the
Claude Science task you spent the time in, not just "Capsid".

- **What is written:** `~/Library/Application Support/Capsid/nidus-context.json`,
  `{version: 1, pid, updatedAt, projectName, taskName}`. Names only: no
  conversation text, no URLs. Each name drops control characters and is cut
  to 240 characters; a file over 8 KiB is never written. The file is 0600 and
  replaced by a rename, so Nidus never reads half of one.
- **When:** only while Capsid is the active app, its main window is key, and
  the page is an exact `/projects/<id>/frames/<id>` route on the daemon whose
  session row has the same project. A project overview, the Browser window,
  Settings or any other window writes nothing. Names come from the 25 recent
  sessions LabModel already has; an older task is looked up by its exact ID
  off the main actor, at most once every five seconds.
- **Kept fresh:** rewritten on focus, route, session and settings changes and
  every five seconds, and removed when any condition above stops holding, the
  setting goes off, or Capsid quits. A crash leaves a file behind; Nidus
  ignores it because it accepts the file only when `pid` is the frontmost
  app's, `updatedAt` is at most 15 s old (or 2 s ahead), and its own
  document-names setting is on.
- **Only the copy that started it touches the file.** A `--demo` copy never
  starts it, so its Settings switch and its quit leave a running Capsid's
  file alone.

### Menu bar specimen (Lab/MenuBarSpecimen.swift, since 0.3.0)

Off by default. While a session works, the specimen plays in the menu bar;
while any waits, the waiting glyph and a count. Clicking it opens the
activity list in a popover. Its ink follows the menu bar's appearance (the
wallpaper's), not Capsid's Ivory or Slate. Hidden, not removed, while nothing
works, so it keeps its place. Measured at about 0–2% CPU while playing.

### Mac notifications (since 0.3.3)

A notification in Notification Center as well as the card, for the moments
the card is for. **Opt-in**, off by default, and explained where it is
turned on: what it does, that macOS asks once, that it names the session
and project unless told not to, and where to turn it off.

**Settings → Alerts → Mac notifications**, right after "When a session
needs you" (`MacNotificationsSection`, in Lab/MacNotifications.swift):

- **Also send a Mac notification.** Off. Its subtitle says it comes as
  well as the card, shows in full screen and with the panel off, and that
  macOS asks permission the first time. (Until 0.3.6 it also said "on your
  iPhone": macOS doesn't send a Mac's notifications to an iPhone, only the
  other way, so that went.) Turning it on asks macOS for alert and sound at once. If
  the answer is no, the switch stays on and the Permission row says why.
- **When a session finishes too.** Off. Without it, notifications come only
  when a session needs you or stops with an error.
- **Show session and project names.** On. Off, they read "A session needs
  you", "A session stopped with an error" and "A session finished", with
  nothing of the session's or project's in any field.
- Both switches are disabled while the first is off.
- **Permission**, read from `UNUserNotificationCenter` when the section
  appears and whenever Capsid becomes active, so a change made in System
  Settings shows without reopening: "Allowed"; "Not allowed: turned off in
  System Settings", with **Open Notification Settings…**
  (`x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.sam.bench`);
  "macOS will ask when you turn this on", or "Waiting for your answer to
  macOS's question" if it is on and macOS hasn't been answered.
- **Send a Test Notification**, enabled only when notifications are on and
  allowed. Made-up words ("This is how Capsid tells you a session needs
  you."), nothing of the user's. It banners even with Capsid in front, which
  it always is when sent from Settings.
- A footer says it all again in one place: names are shown unless turned
  off, and notifications stop by switching the first one off or by turning
  Capsid off in System Settings → Notifications.

**What goes out.** `NotificationRules.content(for:settings:)` is pure and
decides everything: nothing unless the setting is on and macOS allows it.
The poster, `MacNotifications`, is thin and tests never use it.

| Card | Title | Body |
|---|---|---|
| Needs input (a Later reminder coming back too) | the session's title | the reason sentence (`WaitingReason.sentence`), " · ", the project |
| Failed | the session's title | "Stopped with an error · " and the project |
| Finished, only with "When a session finishes too" | the session's title | "Finished · " and the project |

- **Never** for a page's own notification (`LabCard.web`), a saved file or
  a notice (but for the one below); on the first read after launch (as `chime` is not played);
  in a `--demo` mode; or in tests.
- **A finish held for a Nidus focus session** is not sent then: its card
  waits, so does its notification. When the session ends, what finished
  comes as one notification, as its "While you focused" card does, and only
  with "When a session finishes too" on: the one session's title and
  "While you focused · Finished", or "3 sessions finished" and the first
  title and "and 2 more". With names off, "A session finished while you
  focused", or "Sessions finished while you focused". A click opens the
  session when there is one, else the window. No other notice is sent.
- **Never with Approve.** A plan's notification only opens its session;
  approving a plan is on the panel's card alone (Approving a plan from its
  card), and so is a permission request's Allow Once or Deny. A question's
  notification may offer its answers (since 0.7.0; Answering from the card →
  From a Mac notification): every answer is checked against the question's
  id and words on a fresh read before anything is written, which is the
  check this rule was missing for plans.
- **Sound.** Capsid's own "Play a sound" on: the notification is silent, as
  the panel chimes. Off: the default sound.
- **Identifier.** The card's id, so a question that becomes a plan to
  approve replaces its notification (and is sent again) rather than
  adding another. Told by `LabModel.cardRaised`, which fires for a card
  that is new or asks something new, never on the first read.
- **Taken back.** `LabModel.cardWithdrawn` removes the delivered
  notification when its card (the "While you focused" one too) is opened or
  dismissed, when its session stops
  waiting, and when a failure's session runs again. A card that only times
  out (a finish after 6 s) leaves its notification where it is, so it is
  there to see later; opening it or clearing it in Notification Center
  removes it.
- **Clicking** one activates Capsid and opens that session by id
  (`LabModel.open(sessionID:)`: its card, the lists or Recent, else the
  deep link kept in the notification, else just the window). A notification
  from before a relaunch still opens its session. Capsid is the
  `UNUserNotificationCenterDelegate` from launch for this.
- **With Capsid in front** (`willPresent`) a notification goes to the list
  only: no banner and no sound, since the user is already here.
- **Safety.** `UNUserNotificationCenter.current()` crashes outside an app
  bundle, so it is touched only when the bundle identifier is
  `local.sam.bench` and no demo is running. `LabModel`'s two hooks do
  nothing until `MacNotifications.start()` sets them at launch.
- **What stays on the Mac.** Capsid saves nothing about sessions, but
  macOS keeps a delivered notification in Notification Center until it is
  cleared. That is what "Show session and project names" is for; turning
  names, or notifications, off clears the ones already delivered (since
  0.3.6). A notification also
  carries the session's id and its link, opaque ids and no names, to open
  it on a click.
- Not done: notifications that outlive a quit are not checked against the
  sessions at the next launch, so one for a session answered meanwhile
  stays until it is clicked or cleared.

### Approving a plan from its card (since 0.3.4)

Capsid's first write to Claude Science (Lab/PlanApproval.swift).
Until 0.3.4 it only read. (Since 0.4.0 a paired device can also approve,
answer and send a message: Capsid on your phone → Actions.) Plan approval only; every other kind of waiting
keeps Open and Later.

**The flow.** `PlanApprover` follows `LabModel.cards`:

1. When the card on top is a needs-input card whose reason is `.plan`, it
   reads that session's plan once, keyed by session id, while the card says
   "Loading the plan…". It reads nothing while the setting or "Show a card"
   is off, before the page is up, or in a demo.
2. If every check holds, the card shows the summary and the steps line, and
   offers **Approve**. If any check fails, the card is as before, Open and
   Later.
3. **Approve** goes to "approving" at once and shows a spinner, so a second
   press finds nothing to do and nothing is posted twice. `LabModel` holds
   the card up from here, even once the session runs on.
4. Capsid reads the root frame again, and posts only if it still waits for
   the very plan shown.
5. Approved: "Approved ✓" for about 1.5 s, then the card goes through
   `LabModel`, as Open would take it (its reminder too), without opening the
   session.
6. Anything else keeps Open and Later and says why: "The plan changed: open
   it to check", "Claude is still busy with it", or "Couldn't approve here".
   There is no second Approve on that card.

The plan state is dropped when the card goes, when it stops being about a
plan (a new request replaced it), or when the setting is turned off; a card
that comes back reads its plan afresh.

**The checks** (`PlanCheck`, pure, tested on made-up JSON):

- **Offer Approve** only when all of these hold: the **root** frame's own
  `status` is `awaiting_plan_approval`; `_plan_approved` is not true (a
  value that is neither true nor false counts against it); the version id is
  a string fit for a path (`[A-Za-z0-9_-]`, at most 128); and the plan file
  parses with a string, non-empty `task_summary`.
- **The root only.** The card's session id is the root frame, and it must
  be a full 36-character id (the daemon matches a shorter one by prefix). If
  a sub-agent is the one waiting, the root's own status is `processing`:
  no plan is read, and only Open.
- **At the press**, the shallow frame again: still `awaiting_plan_approval`,
  still not approved, the same version id, and the same artifact id when
  both are known. Otherwise `.changed`, and nothing is posted. The approve
  call carries no version, and the server approves whatever plan is pending,
  so this check is Capsid's to make, immediately before the POST. The window
  left between the check and the POST is small: a new plan only appears
  after the frame passes through `processing`.
- **The answer:** 200 with JSON `status: "accepted"`, or 400
  `plan_already_approved` (Claude Science's own UI counts that as success),
  is `.approved`; 400 `plan_frame_processing` is `.busy`; 400 "No plan
  awaiting approval…" is `.changed`; everything else (401, 403 after the
  one CSRF retry, 404, 405, other codes, a body that isn't JSON, a thrown
  call) is `.failed`.

**The endpoints** (all under the daemon's `/api`, made from the page):

```
GET  /api/frames/<rootFrameId>?shallow=true
     status
     context_data._plan_version_id, _plan_artifact_id, _plan_approved
     (else output_data.plan_version_id, plan_artifact_id, plan_approved)

GET  /api/artifacts/versions/<_plan_version_id>
     task_summary
     phases[].delegations[].steps[]   (counted, and each step's title kept;
                                       older plans: top-level steps[])
     feasibility.confidence           (when a short string)
```

```
POST /api/frames/<rootFrameId>/approve-plan
     Content-Type: application/json
     x-operon-csrf: <the operon_csrf cookie>
     body: {}
200  {"root_frame_id", "frame_id", "status": "accepted"}
403  {"code": "csrf_stale"}  →  GET /api/csrf, then the POST once more
```

The body is always `{}`: the session keeps its own settings, and the plan is
never sent back (sending it as `edited_plan` would save a new version marked
as a user edit).

**Steps on the card.** The step titles are read from the same
plan file, in plan order, from the same shape that is counted (the phases'
steps when they have any, else the top-level ones). A step's `description` is
never read. A title that is not a string, or is empty, is left out of the
list but its step still counts; any run of white space (line breaks too) in
a title becomes one space, and a title is cut at 200 characters. A plan with
no titles has no **Show steps** control and shows nothing extra. The cap is a
pure helper (`PlanStepList`, 8 titles, "and N more…" counting the titles
left out, not the steps), so a long plan can't grow the panel off a laptop
screen: open, the list adds roughly 150 pt. Whether a card's list is open is kept by `PlanApprover`
(`stepsOpen`, by session id), in memory: closed by default, per card, and
dropped with the card's plan, so a card that comes back starts closed. The
label reads "feasibility" rather than "Claude's feasibility estimate"
because the longer wording is wider than the text column (226 pt at any
size of the scene well); the tooltip says whose estimate it is.

**Privacy.** This widens Capsid's "never read content" rule by exactly the
plan's summary, its step count, its steps' titles and its confidence word,
for the card. Only those fields are picked from the responses (the frame's
`name`, `task_summary` and `input_data` are not, nor a step's description),
they are kept in memory only, for as long as the card is up, and they are
never logged, saved or sent anywhere. The log says only how an approval
ended ("approved", "changed"…). The demo and the tests use made-up plans.

**Not in notifications, ever.** A Mac notification can be read, and acted
on, away from the card (in Notification Center later, on a lock screen),
without the plan in front of you and
without the check against the plan you saw. So for a plan, Mac
notifications, the activity list and the Dock menu stay Open-only; Approve
(and Request changes) is only on the panel's card, where the summary shows.
A question's notification may offer its answers (since 0.7.0; Answering from
the card → From a Mac notification): the answer is checked against the very
question the notification showed, its id and its words, on a fresh read.

**The fallback is Open.** A setting turned off, a read that fails, a shape
that doesn't match (a newer daemon, a 404 or 405, an unknown code), a
sub-agent waiting, a changed plan: each leaves the card as it was before
0.3.4, with Open taking you to the session to decide there.

**Setting.** Settings → Alerts → On the panel → **Show plans,
questions and requests on the card** (`showPlansOnCard`; it read "Show plans on the card,
with Approve" until the question card, then "Show plans and questions on the
card"), on by default. Off, a plan's card is Open and Later, and no plan is
read; the same for every other wait (Answering from the card). A plan's
card also has **Request changes…** (Answering from the card → What to change
in a plan).

**Demo.** `Capsid --demo plan`: a made-up session whose made-up plan is
ready ("Screen 24 buffer conditions", "10 steps · feasibility: high", with
10 made-up step titles, so the list shows "and 2 more…", one of them long
enough to be cut). Its Approve shows the Approved state and calls nothing.

### Answering from the card (Lab/QuestionReply.swift, Lab/ReplyWindow.swift, since 0.7.0)

A session's question, a permission request, or what to change in a plan can be
answered without opening Claude Science: the card shows it, and a button
opens a small window to answer in where typing or reading is needed.

**The card.** `QuestionReplier` follows the cards as `PlanApprover` does. When
the card on top is a needs-input card waiting for anything but a plan
(`QuestionCardState.reads`), it reads the session once
(`RemoteSessions.readFrame(_:full: true)`: the root frame, its last turns, and
the head of its and its helpers' permission requests, as the phone's session
read), while the card says "Loading…". It reads nothing while the setting or
"Show a card" is off, before the page is up, or in a demo; a read that fails
is tried again after 15 s. Then (`QuestionCardState`, pure):

- **Ready**: the root itself is `awaiting_user_response` with its own first
  `ask` readable. The card shows the first question in two lines and how it
  is answered ("3 choices", "Pick any of 4", "Type an answer", "2
  questions"), never the answer choices themselves, and offers **Reply**
  (primary), **Open** and **Later**.
- **Permission**: no root question, but a permission request at the head of
  the queue (the root's or a helper's). See below.
- **Unsupported**: anything else: a question asked mid-run (`processing`,
  which the phone can't answer either), a first `ask` whose shape Capsid
  doesn't know, or a wait the read shows nothing for. The card says "Answer
  this one in Capsid" and offers **Open in Capsid** and **Later**.
- **Unavailable**: the read failed: Open and Later, as before.

**What Claude said.** The same read's last Claude turn
(`QuestionCardState.context`) is shown at the top of the window, three lines
and **Show more**, so a question that refers back ("which of these?") can be
answered without opening the session.

**The window.** The panel is never key (it must not take the keyboard from
whatever you're typing in), so Reply opens a window of its own
(`ReplyWindowController`): Capsid comes forward, as you asked it to, and the
window opens beside the panel (above it, or below when there is no room). A
question arriving never opens it; a second Reply brings the same window
forward. At its top it says where the answer goes: "Answering" (or "Request
from", "Changing the plan of"), the session's title and its project. Then
what Claude said, then each question with its header, its text, and its
choices as radio buttons (checkboxes when several may be picked), each with
its detail, and **Other…** with a text field (a question with no choices has
only the field). Below: **More** (Choose for Me, Cancel Question), **Open in
Capsid**, and **Send Answer**, which is only enabled once every question has
an answer.

**Keys** (`ReplyKeys`): ⌘1…⌘9 pick a choice of the question in hand (the
last one touched; the number after the last choice is Other…), shown as
"⌘1"… beside its choices; **⌘↩ sends**; Esc closes. Plain Return is left to
the text field, so a line break never sends.

**Next.** Sent, with more needs-input cards waiting (any but a plan's,
`othersWaiting`), the window doesn't close: **Next (N more)** (Return) gives
way to a window for the next session in the queue, in the same place; a card
not yet read is read then (`prepare`), the window saying "Loading…" until it
is. With none waiting, it closes after a moment as before.

**The answer** is the phone's own (`QuestionAnswers`, mirroring `answerOf` in
RemoteWeb/app.js): with one choice, the typed text when Other… is on, else
the pick; with several, the picked labels in the options' order, then the
typed text, joined by ", ". The request is built by
`RemoteActionRequest.checkedAnswer`, the very check the phone's bodies get
(one to ten questions, each answer trimmed, not empty, at most 1,000
characters), so the Mac sends nothing the phone's parser would refuse.

**Sending** goes through `RemoteSessions.respond`, the part beneath the
phone's gates (Capsid on your phone → Actions): on the session's own queue,
shared with the phone's actions and photos, it reads the root frame afresh,
checks it still asks the very question shown (the same `tool_id`, the same
question texts, every one answered), and only then writes `resolve-input`.
The phone's own gates (Settings → Phone's switches, the device's six a
minute, which sessions a device may open) stay in `act`, so a reply from the
Mac works with Capsid on your phone off, and a phone with actions off still
can't answer.

**States** (`ReplyPhase`): editing; **sending** (a spinner, everything
disabled: a second press sends nothing, and the card shows a spinner too);
**sent** ("Answer sent.", and the card and any reminder for it go);
**changed** (the question isn't the one shown: the window shows the new one,
keeping the draft when it is the same request read again, a fresh one when it
is another); **failed** ("Couldn't send it. Your answer is still here…": the
draft is kept and Send tries again); **closed** (answered elsewhere, "It was
already answered.", or the session stopped waiting). A re-read after
"changed" that fails claims neither: the draft stays, and Send, whose own
check reads afresh, can be pressed again. A reply outlives its card (Later,
×) but not the session's wait; closing the window keeps the draft for the
next Reply while the session still waits.

**Permission requests.** What may be done is the phone's own table
(Capsid on your phone → Phase 4), unchanged: `RemotePermission.decideOnMac`
is `decide(_:actionsOn: true)` with the reasons said for the Mac ("Open it in
Capsid" where the phone says "on your Mac"; `onMac`). The card shows no more
of a request than the phone does (never its `input`, never free text the
agent wrote), so it may do no more: an allow only for `local_exec` in Python,
R, Bash or PowerShell, in no shared environment, with its code whole (at
most 60 lines of 160 characters, no invisible or direction characters), and for an
`mcp_tool` that says it only reads, from a listed source; a deny for every
kind whose "no" is a plain no; nothing else (a password, an email, a
license, a usage checkpoint, a goal, a scan, a provider) but Open. The
daemon's own table confirms what an allow without a `scope` is: no grant is
recorded at all, so it is for this once whatever the kind's default scope in
Claude Science's UI. On the card:

| The Mac's table | Buttons | Under the title |
|---|---|---|
| Code that may run | **Review** (opens the window), **Deny**, Later (with Open in Capsid in its menu) | what it is ("Claude wants to run this code on your Mac.") |
| A read-only tool | **Allow Once**, **Deny**, Later (with Open in Capsid) | "The tool says it only reads." |
| Deny only | **Open**, **Deny**, Later | what it is, and why allowing is in Capsid ("Allowing this can give lasting access, so choose how long in Capsid.") |
| Neither | **Open in Capsid**, Later | why |

The window ("Permission Request") shows the request's title and detail, the
code in a monospaced, selectable, scrolling box with its line count, and
**Deny** and **Allow Once** (no key sends either). Allow Once and Deny go
through `respond` like an answer, as the phone's do (`PermissionDecide`):
read afresh with the helpers, the same request still the head and of the
same kind, its holder in this session, then `resolve-input` to the holder
with no `scope`. Sent: "Allowed once" / "Denied" ✓ on the card, which then
goes. Changed: the new request takes its place ("The request changed. Look
at it again."); handled elsewhere: closed. A failed write says try again; a
refusal from the table says why, in the Mac's words.

**What to change in a plan.** A plan's card (shown and not being approved)
has **Request changes…** beside Show steps. It opens the window ("Request
Changes"): the plan's summary and steps line, and "What should change?" (a
text field, focused). **Send** (⌘↩) sends it through `respond` as
`RemoteActionRequest.planFeedback(version:text:intentID:)`, checked as a phone
message is (trimmed, 1 to 4,000 characters, none of the UI's reference
prefixes) and made only by this window; the phone has no route for it. The
check (`RemoteDecide.planFeedback`): the root still `awaiting_plan_approval`,
not approved, at the very version the card showed, with an agent and a
project; then `POST /api/request` `{target_agent, root_frame_id, project_id,
input_data:{request}, intent_id}` with **no `plan_mode`**
(`RemoteWrite.planFeedback`). From the daemon's own code: a message to a
session whose plan waits is taken as a change request (its system prompt
tells the model that a change request is not approval: revise the plan and
keep waiting), the tool gate stays shut until `approve-plan`
(`plan_artifact_id` set and not approved), and a request without `plan_mode`
leaves the session's own as it is, where the phone's messages say `false`.
The intent id is kept while the words are the same, so a retry after a lost
reply is recognised ("already_delivered") and not sent twice; new words get a
new one. Sent: "Sent. Claude is revising the plan." and the card goes (the
session runs, then waits again with the new plan). The plan changed or stopped
waiting: closed, with the words still there to copy. The phone is unchanged: a
message to a session whose plan waits is still refused there ("Approve or
revise the plan on your Mac").

**From a Mac notification.** With Mac notifications on, names shown and this
setting on, a question's notification offers its answers
(`NotificationRules.QuestionActions`): a button per choice and **Reply…** (a
text field), for a single question with one answer and at most four choices
or none. Its words are then the question's. The question is the card's read,
or one read of its own when the card hasn't one (`askForNotification`). Either
way it waits four seconds at most (an injected clock in tests), then goes as
before. Waiting on the card's own read never cancels it, since the card still
needs it; a read of its own that loses to the limit is cancelled, and the
timer is cancelled when the read wins. Whichever comes first answers, once. The
buttons need the Mac unlocked and don't bring Capsid forward. An answer is
read back from the notification's own copy of what it offered, checked again
as the page's words are, made into a draft by the same rule, and sent by
`answerFromNotification` through `respond`, which checks the question's
`tool_id` and words afresh. It answers with how that one send ended, so the
notification waits for its own answer and never for other sessions' reads or
sends. That check is why a question may be answered
here while a plan may not (Mac notifications: plans and permission requests
stay Open-only). A launch from the notification waits up to 20 s for the page
and the session. Sent, or answered elsewhere meanwhile: nothing more. Not
sent: the reply window opens with the answer still in it (or the session,
when even that can't be).

**What is kept** (since 0.7.1; the card rule since 0.7.2). A reply is owned by its open
window (`windowOpened`, `windowClosed`, which the window controller calls), by
a send under way, as a draft (editing, changed or failed) by a session still
waiting, or by its card while the card is still up, since the card shows how
it ended (a request handled elsewhere: its note and Open in place of Allow and
Deny; in 0.7.1 that was let go at once and Allow and Deny came back with no
word of why). Anything else is let go at once (`prune`): one sent or closed
with no window or card to show it, and a draft whose session no longer waits.
An open window keeps what it shows,
sent or closed, until it closes. What was read for a card (its state, what
Claude said, a failed read's time) goes with the card however it goes (sent,
Later, ×, the wait ending); a card read takes itself out of the reads under
way when it ends. So a long run keeps nothing for sessions answered from the
card: hundreds of direct approvals or notification answers leave nothing
behind (`ReplyLifetimeTests`).

**Privacy.** As the plan card: the question's texts and choices, a
permission request's plain fields (as the phone's), and the session's last
Claude turn are read for the card and the window, kept in memory while the
session waits, and never logged or saved. What to change in a plan is typed
here and only sent. The log says only how a reply ended ("sent",
"changed"…). A question's notification holds its text and choices, as
Notification Center keeps any delivered notification (Mac notifications,
What stays on the Mac).

**Setting.** The plan card's (**Show plans, questions and requests on the
card**, `showPlansOnCard`): off, every needs-input card is Open and Later
(with Approve gone from plans), nothing is read, and notifications offer no
answers.

**Demo.** `Capsid --demo card`: the made-up session's made-up question, with
Reply, and behind it a second card asking to run made-up Python, with
Review; Next steps from one to the other. `--demo plan` has Request
changes. Nothing is sent anywhere.

## Scenes settings (Lab/SceneSettings.swift, Lab/SpecimenChoice.swift)

`SceneSettings.shared` holds three settings in UserDefaults:

| Setting | Key | Values | Default |
|---|---|---|---|
| `size` | `sceneSize` | small 64, medium 88, large 120 (points) | medium |
| `groups` | `sceneGroups` | `SceneGroup` raw values: the categories that are on | all six |
| `hidden` | `hiddenScenes` | names switched off one by one, inside categories that are on | none |
| `favorites` | `favoriteScenes` | names starred (since 0.3.2) | none |
| `onlyFavorites` | `onlyFavoriteScenes` | play the favourites and nothing else | off |

The rules live in `SpecimenChoice`, a value type with tests
(`SpecimenChoiceTests`); `SceneSettings` keeps one and writes it back.
- A specimen is on when its category is on and it isn't hidden.
- A category's checkbox has three states: on (all of it), mixed (some, shown
  as a dash with "N of M"), off (none). A click on on goes all off; on mixed
  or off goes all on, as a Mac's mixed checkbox does.
- Switching on a specimen in a category that is off turns on that specimen
  alone (the category comes on with its other specimens hidden).
- Switching off a category's last specimen switches the category off, so
  specimens it gains in an update stay off too. Stored choices are tidied the
  same way when read.
- "Play Only" leaves one specimen on. None keeps the first specimen that is
  on. At least one specimen always stays on: the last one can't be switched
  off, nor the last category with any on.

`rotation` is `Rotation(LabScenes.spread(the specimens that are on))`, or
`Rotation.full` when everything is on. With **only favourites** set and at
least one favourite, it is the favourites instead, whatever is on or off
(`SpecimenChoice.rotation(favorites:onlyFavorites:)`): favourites are kept
apart from what is on, so switching back finds the choice as it was. With no
favourites (none yet, or all renamed), what is on plays.

The panel's well, and its width (base + size − 88), follow `size`. The
panel's and the capsule's scenes play `rotation`. Right-clicking the working
panel offers Add "Name" to Favorites (or Remove), Don't Play "Name", Play Only
"Name" (the specimen playing when the menu opens, followed with
`SceneBoundarySchedule`) and Choose Specimens…; while only favourites play,
just Remove from Favorites and Choose Specimens…. The toolbar popover has an
"Only favorites" switch (off and greyed until something is starred), and
its categories grey while favourites play.

The Settings **Scenes** tab (760×776) has:
- a Size segmented picker, and a Play picker: "What's on" or "Only
  favorites", with a live well beside them ("Playing what's on" or "Playing
  your favorites" under it, or, under the pointer, what the field guide says
  about that specimen) and a line saying what a click does: switch on or
  off, or, while only favourites play, star;
- category checkboxes with counts (mixed when some are on), greyed while
  favourites play;
- a search field with a Topics menu (a tag button) beside it, an All / On /
  Off / ☆ filter (☆ shows the favourites; On and Off mean in or out of what
  plays), "N of M on" with All and None (None keeps one on), or "N favorites"
  while only favourites play (see "Field guide" below for the search);
- a LazyVGrid of every specimen, one section per category headed "Name N of
  M on" (or "N favorites"), including categories that are off, so any
  specimen can be picked from anywhere. While a search has words in it the
  categories give way to one "Results" section, best match first, so a name
  ranks above a note wherever each sits; the filter still applies. Each cell is 58 pt with the name
  under it, dimmed with no check when off, and a clay check when on; a click
  toggles it. A favourite has a clay star at the tile's top-left; under the
  pointer an empty star shows there, its own button, to star it. While only
  favourites play, the checks go, non-favourites dim and a click stars. The
  right-click menu has Add to/Remove from Favorites, then (unless only
  favourites play) Play Only, Switch On/Off, and Switch On/Off All in its
  category.
  Hovering a cell plays that specimen alone in the preview well, its name
  under the well and then what the field guide says (below), "Playing what's
  on" otherwise; leaving goes back to the rotation after 250 ms, so crossing
  between cells doesn't flash it.
  Cells on screen PLAY, drawn live by `SceneLive` (a TimelineView plus a
  Canvas at 20 fps, 30 under the pointer, keeping no frames). The panel's
  `PlayedGlyph` pre-renders about 1.5 s per scene, and 40 cells of that cost
  about 320 MB more; live drawing costs about 11% of one core with no extra
  memory. Off screen (the lazy grid's onDisappear), or with Reduce Motion
  except under the pointer, a cell is a Canvas still at 60% of its duration.
- the ☀️/🌙 switch under the preview well sets the WHOLE tab light or dark
  (`.preferredColorScheme` on the tab, which sets its window's scheme while
  the tab shows); it starts on the app's. No boards inside the tab (Sam: "the
  entire panel should match… not a square around the glyphs").
- Category checkboxes (`CategoryChip`, shared with the Specimens popover):
  SwiftUI's `Toggle(sources:isOn:)` over two bindings (any on, all on) draws
  the mixed dash; each binding writes the whole category, so a click changes
  it once. The popover's way into the tab is "Choose specimens one by one…".

### Field guide (Lab/SpecimenNotes.swift, Lab/SpecimenGuide.swift)

Words for every specimen, kept apart from the drawings.
- `SpecimenNotes.all` maps a specimen's name to a `SpecimenNote`: a
  **caption** (36 characters at most, for the panel's line), a **note** (one
  sentence, 140 at most), **topics** (from a fixed list) and **also** (extra
  words to search by that the name, caption and note don't use). The table
  is generated into SpecimenNotes.swift, which holds nothing else, so a new
  one drops in without touching the logic in SpecimenGuide.swift. It's a stub
  of a few specimens until the full table lands. Neither file is in
  Shared/, which the sync script overwrites.
- **Search** is `SpecimenIndex.search`, a pure function with tests
  (`SpecimenGuideTests`). The words typed and the guide's are folded alike
  (case, accents, width, curly apostrophes, so "angstrom" finds "Ångström"),
  and the index folds the table once. A specimen matches when every word of
  the search is somewhere in its name, caption, note, topics or also words.
  Ranked best first, ties in catalogue order: the search starts a word in the
  name, is inside the name, is in a topic, in the also words, the caption, the
  note, and last words spread over more than one of those. So "microscopy"
  finds every specimen with that topic, topics first.
- The **Topics** menu lists every topic in the table, once each in
  alphabetical order (taken from the table, so a new one brings its own). A
  click fills the search; the filled one has a check and clears it. It's an
  icon alone, since the controls row has no room for a word more.
- The preview's **text** is the name (callout, as before), the caption (12
  pt, secondary) and the note (11 pt, secondary, four lines), centred in a
  248 pt column. Each line reserves its height, so nothing moves whether the
  specimen has a note or nothing is hovered (an empty `Text` reserves
  nothing, so they hold a space). A specimen with no note shows its name
  alone.
- The completeness test (every catalogue name has a note, every note is for
  a real specimen) is disabled until the full table lands. The key check and
  the caption and note limits run now.

## Usage (Usage/)

- `UsageModel.shared` reads `CombinedScienceSource().activityHistory(days:
  7 * 53)` off the main thread. It reads when the popover opens if the last
  read is over 60 s old, and every 10 min while it is open.
- The popover opens from a toolbar button, `chart.bar.xaxis`, titled "Usage",
  about 780 wide. It holds:
  - the headline: today's tokens and sessions, this week's sessions, and the
    streak ("5-day streak · longest 12");
  - a Sessions / Messages / Tokens segmented switch;
  - the year graph, ported from the droplet's `ActivityGridView` (clay steps,
    with a hover label showing the date and that day's sessions, messages and
    tokens);
  - the legend.
- It shows a spinner while the first read runs, and a sentence if a read fails.

## Usage pause (Lab/UsagePause.swift, since 0.5.2; per session since 0.5.3)

When a plan limit runs out mid-turn, Claude Science keeps the session
`processing` but sends nothing until the limit starts over; its page shows
"Sending messages is paused — resumes at 3:40 PM" in the composer and drops the
working indicator. It learns this only over its own page's socket
(`frame_activity` with phase `usage_limit_paused`, `since`, `resets_at` and
`pause_source`; the last one per session replays when the socket connects).
There is no HTTP route for it, and Capsid opens no socket: the socket carries
every session's text and thinking (Capsid on your phone, Phase 4, Live text), so
using it would be a new integration, not a reuse. Capsid infers the pause, one
running session at a time, from what it already reads:

- **Quiet**: the session's whole tree, sub-agents included, has written nothing
  for 20 s: `SessionStatus.activeAt`, the poll's own order key (the latest
  `updated_at` of the root and every frame under it), returned since 0.5.3. A
  root waits quietly while its helpers work, so the root's `updatedAt` alone
  would read a busy session as paused. `updatedAt` keeps its meaning for the
  lists. A session without `activeAt` (made-up sources) is never quiet.
- **Used up**: a limit that holds every session (`PlanLimit.Kind.holdsEverySession`:
  the 5-hour and the weekly) is at 100 % or more by its unrounded figure, its
  window hasn't started over, and extra usage isn't on with room left (its own
  unrounded `reached`; on without a figure counts as room, as before;
  `PlanUsageModel.limitReached`; with several, the one that resets last).
  Claude Science's page, once it shows a pause, takes it as over when a read
  (75 s or more after) shows none of `five_hour`, `seven_day` and
  `seven_day_oauth_apps` used up; Capsid doesn't read the last. The Opus and
  Sonnet weeks hold only sessions on that model, and Capsid
  can't tell a session's model (it is chosen per message, in the request body,
  which Capsid never reads), so a used-up model week pauses no session in Capsid:
  such a session shows as working.
- **Evidence**: the read that says so was taken after the session's last write,
  and is no more than 150 s old. While a session is quiet and a holding limit
  is at 85 % or more (or unknown), or while anything is held, Capsid reads the
  plan again, bypassing Claude Science's cache, at once if the last try is
  older than the session's last write, else at most once a minute. After two
  failed reads in a row it stops saying paused rather than go on from a read
  it can no longer check.
- **Then** (`UsagePauseModel.held`, by session): the panel puts a session still
  working on top; a held one shows a pause symbol, "Paused · usage limit" and
  "Resumes at 3:40 PM" instead of the specimen and clock. The activity list
  marks each held row; its section reads "Paused · usage limit", and the menu
  bar and toolbar capsule stop and say "Paused", only when every working session
  is held. `/api/state` marks each held working row `"paused": true` and carries
  `"pause": {"limit": "5-hour", "until": "…", "sentence": "…"}` while any is held
  (null otherwise). The phone shows a banner, still rows for the held sessions,
  and stops polling live text for a held session only. It says the resume time
  from `until` in its own time zone and language ("Resumes tomorrow at 10:00
  AM" in Tokyo when the Mac in Detroit would say "Resumes at 9:00 PM"); without
  a time it can read, "Resumes when your limit resets". `sentence` is the Mac's,
  in the Mac's zone, kept for a phone app from before 0.5.3.
- **Over**: a session's next write anywhere in its tree ends its pause; the limit
  starting over ends them all at once (Capsid looks again just after `until`),
  as does a read saying there is room, extra usage switched on included, once
  taken 75 s or more after the pause began (the page waits as long before it
  believes one).
- **What it can't tell**: a session that keeps running a long tool after the
  limit ran out writes nothing either, so it reads as paused until it writes
  again (Claude Science pauses it at its next model call anyway). A session on
  a used-up Opus or Sonnet week reads as working. Neither was seen against a
  real used-up limit: TESTING.md says what is checked, and how.
- `--demo … -demoUsagePause YES` holds every made-up working session for an hour.

## Title-bar readouts: context and usage remaining (Usage/)

Like Claude Code's desktop context indicator. Both read Claude Science's own
API through `WebContainer.apiGET` (Web/WebAPI.swift): a GET made inside the
page, in an isolated script world, so the page's cookie session carries it
and Capsid never holds the session. Only the listed read paths are allowed;
the one write Capsid makes is a plan's Approve (Web routing policy, and
Approving a plan from its card).

**Context ring (toolbar).**
- Source: `GET /api/frames/<id>/token-series`, for
  `WebContainer.currentFrameID` (the session the page shows).
- It returns `{ window, turns: [{ ctx_total, … }], truncated }`, and used =
  `turns.last.ctx_total / window`. That's the same number Claude Science's
  "Context usage" view shows.
- Read it when the shown session changes, when that session finishes a turn
  or starts waiting (LabModel's transitions), and at most once per 15 s. It
  scans the transcript, so never poll.
- Look: a 14 pt ring in `.primary` at 15% for the track and clay for the
  fill, with the percent beside it (12 pt medium, monospaced digits,
  secondary; clay past 80%). Hidden when no session is shown.
- Both readouts share ONE toolbar item (`TitleBarReadouts`): one glass
  capsule, ring half | hairline | usage half, like the Scenes split button.
  Each half is a button in `ReadoutButtonStyle` (10 pt side padding, a faint
  pill on hover), so nothing touches the capsule's edge. Everything sits on
  one centered line: glyph, then figure.
- Tooltip: "Context: 42% (84K of 200K)".
- Click: a popover laid out like the Usage one: "Context" and Refresh, then
  one glass card with the percent (26 pt), "18K of 200K tokens", the turn
  count and a line chart of `ctx_total` per turn (the `window` dashed).

**Usage remaining (toolbar, the Usage button's label).**
- Source: `GET /api/usage` (`?fresh=1` on a manual refresh). It returns
  `five_hour`, `seven_day`, `seven_day_opus` and `seven_day_sonnet`, each
  `{ utilization (percent used), resets_at }`, plus `extra_usage`.
- Read it at launch, every 5 min while Capsid is running, after each finished
  turn, just after a limit resets, and when the popover opens (if over 60 s
  old).
- Label: a 22×5 pt clay meter (what's left, draining like a battery), then
  the tightest limit as what's left and when it resets, e.g. "66% left ·
  resets in 1h 12m" or "Week 12% left · resets Thu". The session limit goes
  unnamed: "5h" read as five hours to go. The countdown ticks each minute
  and is tertiary; the figure is secondary and turns clay under 20% left.
  `chart.bar.xaxis` shows until the first read lands.
- Popover (glass): a **Plan limits** section with a row per limit ("Current
  session", "Weekly · all models", "Weekly · Opus", "Weekly · Sonnet"), each
  with a bar, "% left" and "Resets in 2 h 14 m" (and the forecast line and
  sparkline below), plus extra usage when enabled. Then the **Activity** section (the graph from Claude Science's launch on June 30, 2026, a column per week up to a year; 14 pt squares while it spans 30 weeks or fewer, the days before launch blank; the popover is as wide as the graph needs, 600 pt at least), and a Refresh
  button (`.glass`).
- One Usage control, not two.

**Usage forecast (the popover, under each limit's bar).** "At this pace:
limit around 3:40 PM", "At this pace: lasts until it resets", or, while it
has no pace yet, "Learning your current pace…".
`PlanUsageModel` keeps each limit's reads of its current window, a time and
the whole percent (`UsageSamples`, published as `samples`), in memory only
and never on disk; they start over when `resets_at` moves by more than 5
minutes (it wobbles by seconds between reads). It adds no reads: the ones
above are the samples, one every 5 minutes at least. `UsageForecast.estimate`
is pure and tested: it takes the reads of the last 45 minutes
(`UsageForecast.lookback`; from the last drop in the percent on, a drop
being a reset) and fits a line by least squares, so one read's rounding
doesn't swing it. With fewer than 3 reads, less than 15 minutes of them, or
under 3 points of change (a flat line too), it is "too early". Where the
line reaches 100% after the reset, "lasts until it resets"; otherwise the
time, rounded to 5 minutes, with the day in front if it isn't today. The
weekly rows use the same 45 minutes, so they name a time only after a
burst of use, and are learning in between. The toolbar label doesn't
change.

- **Learning line.** (After 15 minutes of reads with under 3 points of change it says "Little use lately" instead, so a quiet week doesn't read "learning" for days.) A "too early" forecast says "Learning your current
  pace…" when the window has at least one read and the limit isn't at 100%;
  with no read yet, or once the limit is used up, nothing is said. This is
  `Forecast.line(now:reads:usedPercent:)`; the forecast itself, and the
  heads-up cards that read it, don't change. A window that stays flat reads
  "Learning…" until the use picks up, as a flat line is still "too early".
- **Help.** The forecast line has a tooltip: "Based on the last 45 minutes of
  use in this window; it updates every few minutes." The 45 is
  `UsageForecast.lookback`, so the wording follows the constant
  (`UsageForecast.explanation`).
- **Sparkline.** Once a window has 2 reads, its row shows an 80 × 18 pt
  sparkline just left of the forecast line, ending where the title column
  does so the line's text stays under the bar. It is a 1 pt line in the
  secondary colour, round-capped, with a 4 pt dot at the latest read, drawn
  with a Canvas like the context chart. Time runs across, from the window's
  first kept read to the last. The reads kept are the last 90 minutes (twice
  the lookback), so the line can reach back further than the 45 minutes the
  pace uses. Percent used is up on a fixed 0 to 100 scale, so a slow climb
  stays near the bottom or middle rather than being stretched to fill the
  height. A drop in the percent starts it over, as it does the forecast. The
  row grows by about 4 pt while it shows. `UsageSparkline.points` is pure and tested: it maps
  the reads to a unit square (nothing below 2 reads), and the view only
  places them. Hidden from VoiceOver: the bar and "% left" say the same
  figure.

## Native controls, Solanum where it counts (since 0.1.13)

Settings was drawn in Solanum (https://claude.ai/artifact/BjQZQTY4NYmLcz39pHWmQE) in 0.1.11 and
0.1.12: ivory and slate grounds, mono overlines, hairline cards, a serif heading. Sam then asked for the
menus and Settings to look like the Mac's own, even where that bends the brand, so since 0.1.13:

- General is a grouped `Form`, as System Settings is: Capsid's icon, name, version and the "Unofficial,
  and not affiliated with Anthropic" line at the top, native switches, a segmented Theme picker, and
  Diagnostics as a plain button. Its frame is fixed (600 × 640): a grouped form has no height of its
  own, and the Settings window sizes to each tab.
- Specimens keeps its heading, preview and live grid (cells on screen play, the rest hold a still; the
  hovered one lifts to glass), with system controls around them: a segmented Size picker and light/dark
  switch, a rounded search field, plain All/None buttons, and a checkbox per category. Checkboxes,
  not chips: a tinted chip read the same on and off on macOS 27. The last category on stays checked and
  greyed.
- The toolbar's Specimens options stay a popover (a SwiftUI Menu there kept stale ticks), with the
  same switch, segmented size and checkboxes.

The brand stays in the app icon (Solanum's product family), in clay as the one accent (switches, the
specimens' badges and the flask in the toolbar), and in the theme names Match Mac, Ivory and Slate.

## Naming

The animations are called **specimens** everywhere a user reads them (the Specimens tab, "Choose specimens…", the Specimens toolbar button). The code keeps its `Scene` names (LabScene, SceneSettings, the droplet's files).

**Capsid, once Bench (0.6.0).** The app was called Bench until 0.6.0, when it
was renamed Capsid. Solanum's brand is a spooky fictional bio-lab: a capsid is
the protein shell a virus lives in, and Capsid is the shell Claude Science
lives in on the Mac. Every name a person reads says Capsid: the app, its menus
and windows, the binary and `/Applications/Capsid.app`, Settings, the welcome,
alerts and notifications, the phone app ("Capsid on your phone", its title and
Home Screen name) and the docs. What deliberately kept the old name:

- **The bundle id `local.sam.bench`**, and with it the UserDefaults domain,
  every `Logger` subsystem and the URL type's `CFBundleURLName`. A new id
  would make macOS treat Capsid as another app: every setting, permission and
  notification choice would be lost.
- **The `bench://` URL scheme**, which other apps (the droplet, later) use to
  hand a session to the app (Main window).
- **`~/Library/Application Support/Bench`**, which holds the paired devices and
  the push keys. Moving it would unpair every phone.
- **The phone's wire names**: the `bench_device` cookie, the `X-Bench: 1`
  header, the API routes and their `bench` version field, and the page's
  storage keys (`bench-badge`, `bench-photo-note`). The service worker caches
  nothing, so it has no cache names. A device paired as Bench stays paired.
  Its Home Screen icon keeps the name Bench, since iOS names it when it is
  added.
- **`BenchMain`**, the main window's frame name: the welcome's existing-user
  check (`WelcomeGate`) looks for its saved frame.
- **The code's own names**: the package, the `Bench` target and module
  (`@testable import Bench`), `BenchTests`, `Sources/Bench` and its folders,
  files and types (`BenchApp`, `BenchVersion`, `BenchShapes`…). Only the
  product is named Capsid, so the binary and the bundle are. Comments in the
  code still call the app Bench, and so do the `OSLog` messages.
- **What an installed Bench updates through**: the GitHub repository
  `samporter14/bench`, the raw `install.sh` address the install line names,
  the release file `Bench.zip`, and the script's `BENCH_INSTALL_DIR` switch,
  which Bench's updater clears (Update check, "From Bench to Capsid").
- **`Sources/Bench/Shared`** (the droplet's copies) and
  **`Resources/AppIcon.icon`** with its `bench-glyph.png`: the icon is being
  redesigned separately.

## Update check (App/UpdateCheck.swift, App/UpdatePrompts.swift, since 0.3.6)

Capsid can ask GitHub whether a newer Capsid is out, and install it. **Off by
default**: it is the one request Capsid makes beyond this Mac that no click
asked for, so it needs the switch (Settings → General → Updates → **Check for
updates once a day**, `checkForUpdates`), which the welcome window can also
turn on. README's promise reads: Capsid talks to nothing beyond your Mac
except links you click, a once-a-day update check if you turn it on, and, if
you turn on Capsid on your phone, your own paired devices over your Tailscale
network, with notifications, if you turn them on, carried by Apple's push
service and encrypted so only your device can read them.

**What is sent.** One `GET https://api.github.com/repos/samporter14/bench/releases/latest`
through an ephemeral `URLSession` (no cookies, no cache, no credentials,
`httpShouldHandleCookies` off), with exactly three headers: `Accept:
application/vnd.github+json`, `User-Agent: Capsid/<version>` and a fixed
`Accept-Language: en`, so the system's language preferences aren't sent. No
identifier, no account, nothing about sessions, projects or the machine.
GitHub does see the connection's IP address, as any site does. It is
`UpdateRules.request`, and a test pins the headers. It is the only
`URLSession` in Capsid.

**What is read.** `tag_name`, `html_url` and whether `assets` has a
`Bench.zip`; `draft` and `prerelease`. Nothing else is decoded.
- *Version compare* (`BenchVersion`, `UpdateRules.isNewer`): one to four
  numbers compared one by one (0.3.10 is newer than 0.3.9; 0.3 equals 0.3.0),
  a leading `v` ignored. A tag with anything else in it (`-beta`, `latest`,
  an empty string) isn't a version and is never newer, and a draft or
  pre-release is skipped. A running copy with no version (an unbundled run)
  can't compare: the check says so.
- *No Bench.zip, no offer.* The installer downloads that file, so a newer
  release without it isn't offered yet; the check says up to date and the
  release is offered once the file is there.
- `html_url` is opened in a browser, so it is trusted only as an https
  `github.com/samporter14/bench/releases…` page. Anything else falls back to
  the tag's page, `…/releases/tag/v<version>`.

**When it runs.**
- Automatically, only with the switch on, never in a `--demo`: once, 30
  seconds after launch, and then when a day has passed since the last answer
  (`UpdateRules.isDue`, pure: never checked is due; 24 h is due; a last check
  in the future, from a clock moved back, is due). A launch an hour after a
  check doesn't ask again.
- The day counts from the last time GitHub *responded* (`updateLastAsked`),
  whatever it said: a rate limit, a 404 or JSON that isn't a release still
  count as the day's ask, so a refusing GitHub is asked once a day, not
  hourly. Settings says why it failed, and Check Now tries again. Only a try
  that never reached GitHub (offline, no route: nothing left the Mac) isn't
  counted and is repeated an hour later, so a Mac that was offline at launch
  still gets its check the same day.
- With the switch off nothing is scheduled at all: no timer, no wake-up.
  Turning it on (here or in the welcome window) is noticed through
  `UserDefaults.didChangeNotification` and starts the schedule, with a first
  look after 3 seconds; turning it off cancels it.
- When asked: **Check Now** in Settings and **Capsid → Check for Updates…**
  (after About) ask at once, switch or not. A check already under way answers
  for both, so there is never a second request. Neither works in a demo
  (the menu item and the button are dimmed).

**What is kept** (UserDefaults, the only place): the time GitHub last
responded (`updateLastAsked`, the schedule's), the time of the last answer
it gave (`updateLastChecked`, Settings' "Last checked"), the newest installable version seen
(`updateNewestVersion`, forgotten when a check finds nothing newer) and the
last version announced (`updateAnnouncedVersion`). At launch Settings
shows an update seen last time while it is still newer than the running one,
and "up to date" after a check that found none, without asking.

**When there is a newer one.**
- *Card, once per version* (`UpdateRules.shouldAnnounce`): "Capsid 0.3.6 is
  available", "Choose Capsid → Check for Updates… to install it". Only from an
  automatic check; one you asked for shows its answer itself and counts as
  telling you. A newer version gets its own card. **The card has no buttons**:
  a notice's action can only be Open on a session (`LabNotice.Action`,
  `LabModel.open` and the panel's card are written for that), so Install and
  Release Notes live in Settings and the menu's alert. Giving the card two
  actions means a new `Action` case and changes in `LabModel.swift` and
  `LabPanelView.swift`.
- *Settings → General → Updates:* the status line ("Asking GitHub…", "Capsid
  is up to date (0.3.5)", "Capsid 0.3.6 is available" or why a check failed)
  with **Check Now**, which reads "Checking…" and is dimmed while it runs,
  and under the status, in small secondary text, when the last answer came. When one is out, a row beneath says what Install will do, with
  **Release Notes** and **Install Update**.
- *The menu's alert:* up to date; or "Capsid 0.3.6 is available" with
  **Install**, **Release Notes** and **Later** (Esc); or why the check
  failed. Its text is the install sentence, so Install needs no second
  question. Settings' **Install Update** asks first, with the same words.
- **Release Notes** opens the page in the in-app Browser window, as any
  other link to a website does (Web routing policy: GitHub is "any other
  http(s)"), where "Open in Safari" is one click away.

**Install.** `UpdateInstaller` runs the README's line, exactly, as `/bin/zsh -c
"curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh
| zsh"`. The line is a constant (`UpdateRules.installLine`, with a test that
README.md contains it) and nothing the network says ever becomes part of it.
It is started with its input and output on /dev/null and not waited for;
`install.sh` takes it from there: SIGTERM quits this Capsid the way ⌘Q does
(`AppDelegate`), the new one is moved into /Applications and opened. The
confirmation says: "Capsid will quit, download 0.3.6 from GitHub and reopen."
- It is offered only to the copy that is /Applications/Capsid.app
  (`canInstall`). The script replaces that path and quits only that copy, so
  from a build folder or Downloads it would open a second Capsid beside the
  first. Those copies get Release Notes and the sentence "This copy of Capsid
  isn't in Applications, so it can't replace itself."
- `BENCH_INSTALL_DIR` (the script's testing switch) is removed from the
  environment it gets.
- **From Bench to Capsid (0.6.0).** A Bench 0.5.x asks the same
  `releases/latest`, wants the same `Bench.zip` and runs the same install line,
  which fetches `install.sh` from `main` as it is at that moment. That script
  takes Capsid.app out of the zip, quits a running Bench or Capsid in
  /Applications (each matched by its exact executable path, as before), puts
  Capsid at /Applications/Capsid.app and only then removes
  /Applications/Bench.app: the two share a bundle id and must never sit side
  by side. Capsid's `installDirectory` is /Applications/Capsid.app, so the
  next update finds it there. A zip from before 0.6.0, holding Bench.app, is
  still installed as Bench.app, so `main` can carry the new script before the
  0.6.0 release exists. The order matters: `install.sh` reaches `main` first,
  then 0.6.0 is published with a `Bench.zip` whose top level is Capsid.app.
  The other way round, a Bench offered 0.6.0 runs the old script, which finds
  no Bench.app in the zip, stops before quitting anything, and Bench says the
  update didn't install.
- If the installer ends while Capsid is still running, nothing was replaced (a
  success quits Capsid before the script ends), and an alert says so and points
  to the README's line. The script can't tell Capsid about a failed download
  (`curl | zsh` ends 0), so this is the only failure it shows.

**Tests** (`UpdateCheckTests`): version compare, the JSON from made-up
fixtures, the once-per-version card, "not due yet", the setting off meaning
no request (an injected fetch that records its calls), the request's headers,
failures, a check shared by two callers, and the install line matching the
README. No test goes online or runs the installer; the checker keeps its
state in a scratch `UserDefaults` suite.

## Settings (⌘,)

Six tabs since 0.4.0 (`App/SettingsPages.swift`), each a grouped form at its
own height (the window follows the tab):

- **General** (`general`): Capsid's name and version, a banner when it can't see
  your sessions, Appearance, Updates (since 0.3.6), Nidus (since 0.7.3) and
  Help → Diagnostics.
- **Panel** (`panel`): the specimen while a session works (show it, name it,
  the menu bar), where the panel sits (corner, screen, while Capsid is in
  front), and a way to the Specimens tab.
- **Alerts** (`alerts`): on the panel (cards, plans with Approve, sound), Mac
  notifications, and what waits while Nidus is focusing.
- **Usage** (`usage`): heads-up cards (plan and context, week in review).
- **Specimens** (`scenes`): what plays (above).
- **Phone** (`phone`, since 0.4.0): Capsid on your phone (below).

`--demo general|panel-settings|alerts|usage-settings|specimens|phone-settings`
shows each in a plain window that doesn't activate Capsid (`phone-settings`
takes `--step 1…7`).

| Setting | Default |
|---|---|
| Appearance: Match Mac, Ivory or Slate (the whole app, via `NSApp.appearance`; the page follows while its own theme is System) | Match Mac |
| Show the Lab panel | on |
| Play a sound when a session needs you | on |
| Show plans on the card, with Approve (`showPlansOnCard`, since 0.3.4) | on |
| Also send a Mac notification (Mac notifications) | off |
| When a session finishes too (Mac notifications) | off |
| Show session and project names (Mac notifications) | on |
| Show the Lab panel while Capsid is in front | on |
| Name the specimen that's playing, in the panel (`showSpecimenCaption`) | off |
| Check for updates once a day (`checkForUpdates`, since 0.3.6; see Update check) | off |
| Use Capsid from your phone (`remoteEnabled`, since 0.4.0; see Capsid on your phone) | off |
| Skip "Put Tailscale on your phone" (`remotePhoneSkipped`; see Settings → Phone) | off |

## Welcome window (since 0.3.6)

A short welcome for someone who has just installed Capsid (`App/Welcome.swift`),
so the panel, the cards and the update check (the one request Capsid can make
without a click) are explained once, in Capsid's own words. It is a plain titled, closable window,
560 × 460 and fixed in size, centred, hosting SwiftUI. No tabs, no toolbar. The
main Claude Science window opens behind it as usual.

- **When it shows.** On the first launch only: `hasSeenWelcome` is false and
  this isn't someone who used Capsid before the welcome existed. That is
  someone with any of `sceneGroups`, `settingsTab`, `appearance` or
  `showLabPanel` stored: Capsid writes those only when a setting is changed, so
  one being there means this Mac has run and used Capsid. Such a user has
  `hasSeenWelcome` set at launch and never sees the window.
  - The check reads what is *stored* (`persistentDomain(forName:)`), not
    `object(forKey:)`: Capsid registers defaults for `appearance` and
    `showLabPanel` at launch, so `object(forKey:)` would find them on every
    install and the welcome would never show.
  - `WelcomeGate` is pure apart from one thin wrapper over a `UserDefaults`
    (`isExistingUser`, `shouldShow`, `shouldShowAtLaunch`), and tested with
    throwaway suites.
  - Never in a demo: the launch hook is past the demo's early return.
- **Marked as seen** when the window closes, by Get Started, Esc or the close
  button alike (`windowWillClose`), not when it opens. Quit with it still open
  and it shows again next launch.
- **Help → Welcome to Capsid** shows it again at any time, from the first page.
  Already open, it only comes forward. The item is dimmed in a demo.
- **Pages**, with Back, Next and page dots (`WelcomeFlow`: both ends stop):
  1. *Welcome.* The app icon, "Capsid keeps Claude Science in one window, and
     lets you know when a session needs you.", and the small line "A Solanum
     product. Unofficial, and not affiliated with Anthropic."
  2. *The panel.* A specimen playing at 88 pt (`Theme.sceneSize`) in a glass
     well, the panel's own `WorkingGlyph` with the current rotation (a still
     flask under Reduce Motion). What the panel and its cards do, and that the
     corner, the screen and which specimens play are in Settings.
  3. *Getting around.* Four rows with SF Symbols: Quick Open ⌘⇧O (type to jump
     to a session), the toolbar's activity list, favorites in Settings →
     Specimens, and Mac notifications in Settings → Alerts (off unless turned on).
  4. *Updates and privacy.* Capsid reads your sessions on this Mac and changes
     nothing in Claude Science, except when you press Approve on a plan. One
     switch, "Check for updates once a day" (`checkForUpdates`, the same
     setting as Settings' update check), off by default and left off unless
     it is turned on: showing the page writes nothing. Its subtitle says what
     is asked of GitHub and that nothing about you or your sessions is sent.
- **Keys.** Return is the default action: Next, and Get Started on the last
  page. Esc closes. Get Started closes the window.
- **Look.** System controls: `.glass` Back, and the one `.glassProminent` in
  clay for Next / Get Started. Clay is also the current switch's tint; the page
  dots are neutral. Nothing animates but the specimen.
- **Demo.** `--demo welcome` shows the real window, with `--page N` (1 to 4)
  to start on a page. As with the other plain-window demos, `--quiet` keeps
  it from activating Capsid, and closing it records nothing: it never writes
  `hasSeenWelcome`. Its switch is the real setting, so don't click it.

## Files and ownership

```
Package.swift, DESIGN.md, Scripts/build-app.sh, Resources/Info.plist   (planner)
Sources/Bench/App/        BenchApp, Router, Theme, SharedShims, SheetCost, Demo, Settings, Welcome   (planner)
Sources/Bench/Web/        daemon, web view, routing, pop-ups, browser/preview windows, downloads, find, notification bridge, page tabs (Close Other Tabs, Close All Tabs)   (web agent)
Sources/Bench/Lab/        LabModel, LabCard, LabPanelController, LabPanelView, LabStatusCapsule,
                          QuestionReply and ReplyWindow (a question, a permission request or a plan's
                          changes answered from its card)   (lab agent)
Sources/Bench/Results/    ResultsShelf and ResultsWindow: the results shelf (Results)
Sources/Bench/Shared/     COPIES of the Science Status droplet's scenes and ScienceCore. Don't edit here:
                          change them in the droplet, then run Scripts/sync-shared.sh. Except
                          Core/CLIStatus.swift and Core/SQLiteSource.swift, which are Capsid's own
                          since 0.1.2 (the database is found through the daemon's `data_dir` and
                          the live org), Core/ScienceEngine.swift (0.1.15), and
                          Core/ScienceSource.swift and Core/SessionStatus.swift since 0.5.3
                          (`activeAt`, the usage pause); the sync script keeps them.
Resources/AppIcon.icon    Capsid's own icon, in Solanum's one-colour colourway (0.6.0): a Clay tile
                          (#D97757) with everything in Slate (#141413). The Solanum ring and its
                          escaped dot are kept pixel for pixel from Bench's glyph (the escaped node
                          at (152, 9.93)); inside, an icosahedral capsid seen down a three-fold axis:
                          a hexagon (radius 164 of 1024, 26 px) round a facing triangle (radius 67,
                          21 px). Drawn by code (PIL, 4x supersampled), not synced from the droplet.
                          The file keeps its name, bench-glyph.png, which embed-remote-web.py reads
                          for the phone's icon (RemoteIcon, the same Clay).
```

## Testing checklist ("every feature")

Each item gets checked live, and the result goes in TESTING.md:

- [ ] signs in on first launch
- [ ] no Safari tab ever opens
- [ ] file upload (single, multiple, folder)
- [ ] drag files into the page
- [ ] blob download and attachment download
- [ ] pop-out windows (the pool)
- [ ] connector OAuth pop-up round trip
- [ ] HTML preview (iframe, and opening a preview)
- [ ] external links go to the in-app Browser window
- [ ] confirm/alert/prompt dialogs
- [ ] clipboard copy
- [ ] microphone/voice
- [ ] Claude Science desktop notifications reach the panel
- [ ] needs-input card appears, Open lands on the session
- [ ] a plan's card shows its summary, and Approve approves it (a throwaway session)
- [ ] finished card
- [ ] find, zoom and back/forward, in the main window and in a Browser window
- [ ] with Settings in front, Reload, Zoom, Find and Back/Forward are dimmed
- [ ] the window closes and reopens without losing state
- [ ] on-screen CPU with the panel playing
- [ ] update check: with the switch off nothing asks GitHub (no request in Little Snitch or `nettop` for a day); Check Now and Capsid → Check for Updates… do; with it on, a first check comes within a minute and the next a day later, not at the next launch
- [ ] update check against a real newer release: the card comes once, Settings shows "Capsid 0.3.6 is available", Release Notes opens the in-app Browser on the release, and Install Update (Capsid in /Applications) quits Capsid, installs it and reopens it. Capsid started from a build folder offers no Install
- [ ] the field guide: hover text in Settings → Specimens, the Topics menu, search ranking, and the panel's caption lines (Panel, "Name the specimen that's playing")
- [ ] the welcome: shows on a first launch (defaults deleted) and not on the next; not to a Mac with Capsid settings already stored; Help → Welcome to Capsid shows it again; Return and Esc work; the updates switch stays off until turned on

## Results (Results/, since 0.7.0)

The files sessions made, in one native window: **File → Results…** (⇧⌘R) or
the toolbar's tray. Sessions by project, recent then older, each with its
files: a thumbnail (images) or an icon, the name, the kind, the size and the
date; **Preview** (Quick Look), **Copy**, **Save…**, a drag out to Finder or
another app, and once saved **Open** and **Reveal in Finder**; **Save All…**
on a session's row; and **Open Conversation** (the arrow on the session's
row) for where a file came from. A filter field narrows by file name,
among the files read so far (it says so: sessions not read yet aren't
searched). A session's row is open once read with results; one opened by hand
to load stays open when they arrive (`ShelfDisclosure`).

**Reading** (`ResultsShelf`) goes through the page's own artifact reader
(`WebContainer.readArtifact`, Remote/ArtifactReader.swift: the three allowed
GETs, every answer checked again in Swift) with the phone's own checks
(`ArtifactGate`, shared with Capsid on your phone's file routes: a thumbnail
only of an image, text only of markdown, text and tables, a download only
when the listing's size is within 8 MB, and the bytes checked again). It
needs nothing of Capsid on your phone: no server, no paired device, no
Settings → Phone switch. A file's version id is only ever one its session's
list gave.

**Coverage, said in the window:**

- **Recent sessions**: the ~25 the Lab reads anyway (`LabModel.sessions`),
  taken when the window opens and on Refresh, never followed live (they
  change with every write while a session works). The 8 newest are read
  then; the rest when you open them. A list read in the last 5 minutes is
  kept when the window opens again.
- **Older sessions**: **Show Older Sessions** reads 50 root sessions from the
  database (`fetchRecentSessions`: every project's, counted as the project
  lists count them, newest first by `(updated_at, id)`), **Show More** the
  next 50. Each one's files are read only when you open it.

Nothing scans in the background. What was read stays in memory, except the
decoded thumbnails, which are let go when the window closes.

**Transfers** (`ShelfTransfers`, since 0.7.1). Every read the shelf makes goes
through one queue: lists, thumbnails, Quick Look's and a drag's copies, Copy,
Save and Save All. At most two run at once, whoever asked (in 0.7.0 only
lists and thumbnails shared that limit; whole-file reads didn't, and eight
previews could download at once). The same read asked for twice (a preview
and a drop of one file, say) is read once, and each asker gets the answer.
Order: what you asked for (Quick Look, a drag, Copy, Save) first, then Save
All, then lists, then thumbnails, oldest first within each; a read that has
seen eight others start ahead of it goes next, so none waits for ever. Each
read has 30 s from its start (not its wait in line); the page's own fetch
gives up at 10 s, or 20 s for a download. Save All keeps two of its downloads
in the queue at a time, so at most two finished files wait in memory. A
reader that never returns pins its slot until it does, so two such readers
stop the shelf; the page's own 10/20 s fetch deadlines make that unlikely
unless the page's JavaScript is frozen.

**Cancellation.** Each asker can stop waiting on its own. A read nobody wants
any more never starts if it was waiting, and is cancelled if it was running:
the shelf's reads carry a nonce, and the page files an `AbortController`
under it in the reader's own content world (`globalThis.benchArtifactReads`),
so `benchAbortRead(nonce)` aborts that fetch and no other. An aborted read
answers `cancelled`, never a failure; one stopped by the 10/20 s deadline is
still "Couldn't read this". Cancelling a Swift task is never taken for proof
that a fetch stopped: a read cancelled or timed out keeps its place among the
two until the page has actually answered, so closing and reopening the window
never runs more than two. Closing the window lets every asker go except a
Save (you chose where it goes); a late answer lands nowhere and writes no
copy. Moving through files in Quick Look withdraws the file left
(`ShelfPreviewDemand`): its download never starts, or stops unless a drag,
Copy or a save still wants it. The phone's reads carry no nonce, and nothing
about them changed. A Save All the window closed on lets go, as it unwinds, of
only the files it marked as saving (each file's spinner is counted, so a Save
and a Save All can hold it at once), so a Save All started after reopening
keeps its progress row, its spinners and its place, and a Save of a file
either has in hand answers busy (since 0.7.2).

**Disk.** The temporary copies are written, read, re-checked and deleted by
an actor (`ShelfTemporaryCopies`), off the main actor; saved files (Save…,
Save All…) are written by another (`ShelfSavedFiles`), one at a time. Each
window opening is a run; a write that lands after its run was deleted is
dropped, so a closed window's folder is never made again, and deleting an old
run never touches the new one's. Quick Look asks for a copy on the main
thread, so the shelf keeps a list of copies known to be whole, updated when
each write lands. Launch cleanup (`ResultsShelf.shared.cleanUpAtLaunch()`,
from BenchApp) deletes earlier runs' folders off the main actor; this run's
first copy is written after it, and it never deletes this run's folder. A
cached copy asked for while its existence is being checked is not handed over
if the window closes meanwhile: it belongs to the run being deleted (since
0.7.2). `ShelfSavedFiles` is one serial writer with no time limit, so a save to
an unresponsive folder delays every later save until macOS fails it. Left
on the main actor on purpose: the existence checks behind Save All's names
and the remembered folders (metadata only).

**Thumbnails** (`ShelfThumbnails`, since 0.7.1). A thumbnail read's WebP is
decoded once, with ImageIO, off the main actor, to a picture of at most 144 px
on its long side (twice the 72 px the row's 36 pt square needs on a Retina
screen; the daemon's 120-px thumbnails are kept as they come, never
enlarged), and only that picture is kept; the WebP bytes are dropped. Before
decoding, the type and the size in the header are checked: more than 4096 ×
4096 pixels is refused unread, and bytes that aren't an image keep nothing;
either way the version is marked, so it isn't read again in a loop. What is
kept is counted: each picture costs its pixels (never less than width ×
height × 4) plus 1 KiB, and the total never exceeds 16 MiB (about 450 usual
thumbnails, 199 of the largest), the least recently used going first;
storing a version again replaces its cost. Rows draw the kept picture
through `ShelfThumbnailView`, which watches only this store, so progress
lines and other rows' states don't touch a thumbnail and nothing is decoded
while drawing. The pictures are let go when the window closes (a decode still
running then keeps nothing); opening again, or Refresh, the rows ask again. A
picture that didn't decode is tried again the next time the window opens,
not on Refresh. (Until this change the shelf kept up to 200 thumbnails as
WebP bytes, bounded by count and not by size: up to 800 MiB in theory, and
every row rebuilt its image from the bytes whenever the shelf changed.)

**States**, each with what to do: not read yet (**Load Results**), reading,
no files, and failures: "Capsid isn't connected to Claude Science right now",
"Claude Science needs you to sign in again", "This isn't in Claude Science any
more" (a 404 or 410: the session, or a version deleted or expired, told apart
by the reader's `missing` outcome since this change; the phone's routes still
answer it 503), "Couldn't read this", and "Claude Science took too long to
answer", each with **Try Again**. Older sessions that fail to read say so,
and Try Again picks up from the page that failed.

**Preview** opens the real macOS Quick Look panel on a temporary copy of the
file: the row's eye, **Preview** in its context menu, or the Space bar on a
selected file. The Results window is the panel's controller
(`ResultsWindow`, with `ResultsQuickLook` as the data source), so the panel
follows the responder chain as in Finder. The arrow keys move between the
files the list shows, bar any over 8 MB; only the file asked for is
downloaded, and the others are fetched one at a time as the keys reach them
(Quick Look shows its loading view meanwhile). Every kind can be previewed:
Quick Look renders HTML and SVG without running their scripts. While a copy
downloads the row shows a spinner and another press does nothing. A file
over 8 MB by its listing is never downloaded; its row says "Too big to
preview here (over 8 MB). Save it instead, or open it in Capsid."
Unreadable, missing, signed-out and timed-out files use the shelf's usual
sentences on the row. (Until this change Preview was in memory only, with no
temporary file: a thumbnail, styled markdown, text, a parsed table or PDFKit,
and never web pages, SVGs or notebooks. Quick Look was chosen over it, which
is what put a temporary copy on the disk.)

**Temporary copies** (`ShelfTemporaryCopies`). Quick Look and a drag need a
file, so the shelf writes one:
`<temporary folder>/Capsid Quick Look/<UUID>/<version id>/<file name>`, in
the user's own temporary folder. The folders are 0700 and the file 0600; the
name is sanitized (no path separators or colons, no leading dot, at most 255
bytes, extension kept), and the version id keeps two files of one name
apart. A copy is cached by version id while the window is open, so going
back to a file doesn't download it again. The run's folder is deleted when
the window closes (the panel is closed first), and the whole "Capsid Quick
Look" folder at launch (`ResultsShelf.shared.cleanUpAtLaunch()`, off the main actor, from
BenchApp), for a run that never closed.

**Drag out.** Each file row can be dragged to Finder, Mail, Slack and the
like. The drag carries a file representation (an `NSItemProvider`, typed by
the file's extension, plain data when unknown) that is fetched when the drop
is made, not when the drag begins, through the same capped download and into
the same temporary copy; two drops share one download. A file over 8 MB
carries nothing and its row says so. (Not SwiftUI's `Transferable`: its
content type is fixed per type, and this one follows each file.)

**Copy** (context menu) puts on the pasteboard the full image (not the
thumbnail), the text of markdown, plain text and tables (UTF-8; a file that
isn't valid UTF-8 says so), or a PDF's data. Other kinds aren't offered. The
decision is a pure function (`ShelfCopy.content(kind:data:)`); the download
keeps to the 8 MB cap.

**Save All…** (a button on a session's row once its results are read and
non-empty, and in its context menu) asks for a folder (choose or create),
then saves every file of the session there: two downloads at a time in the shared queue, each
within the time limit and the 8 MB cap (a file over it by its listing is
skipped without a download). A name already in the folder, or earlier in the
batch, gets " 2", " 3"… before its extension (compared without case);
nothing is overwritten. Each file saved is recorded like a single Save, so
Open and Reveal in Finder work for it, with no Saved card per file. The row
says "Saving 3 of 7…", then "Saved 6 files. 1 was too big to save here."
with a Reveal in Finder button for the folder. Failures are counted ("2
couldn't be saved."), never named; each file's own row says why. One Save
All runs at a time. Closing the window stops what hasn't started; a file is
written only whole, once its download is complete, so none is left
half-written.

**Folder memory.** The folder last saved to is remembered per project, by
project id and never its name (`UserDefaults` `resultsFolders`,
`[projectID: path]`), and starts both the Save All… panel and the Save…
panel for that project's files. A folder that no longer exists is ignored
and the panel starts in Downloads.

**Saving** (Save… and Save All…) and the temporary copies are the only ways
a result's content reaches the disk. Save… asks where, reads the file within
the 8 MB cap and writes it there; the panel's Saved card follows, as for a
download. **Open** and **Reveal in Finder** then act on that copy; one that
was moved or deleted is forgotten and says so. Over 8 MB says to open the
session and download it there.

**Opening on one session.** The Finished card's **Results** button
(`ResultsWindowController.shared.show(focusing:)`) opens or brings forward
the window, and the shelf makes sure the session is listed (taking the
recent sessions again if the Lab knows it now, else putting it at the top of
the recent ones), opens its row, reads its results if they weren't read or
were read before it last wrote, and the window selects it and scrolls to
it. The card shows no count of the files: nothing is read when a session
finishes, so it can't know one.

## Capsid on your phone (Remote, since 0.4.0)

A private mobile web app that Capsid serves to the user's own devices over
their Tailscale network. Off by default. Phase 1: see what needs you, what
works and what happened, read a session's status and plan, Open on Mac.
Phase 2 (below, same release): read replies, answer, approve, send a
message, and push notifications.

### Transport and trust

- Capsid's `RemoteServer` listens on **127.0.0.1:47280 only** (falls back to
  the next free port up to 47290 and remembers it). Never on other
  interfaces.
- **Tailscale Serve** publishes it to the tailnet with a real certificate:
  `tailscale serve --bg --https=8443 http://127.0.0.1:<port>`. A dedicated
  HTTPS port (8443) so it never collides with the user's own serve mappings
  on 443. Never Funnel. Never `tailscale serve reset`: read
  `tailscale serve status --json` first and add or remove only Capsid's own
  mapping. The CLI is `/Applications/Tailscale.app/Contents/MacOS/Tailscale`
  (not on PATH); a Mac App Store install has the same binary in its bundle.
  Capsid runs it only from an app bundle Tailscale signed: before a run,
  `SecStaticCodeCheckValidity` checks the bundle against
  `anchor apple generic and certificate leaf[subject.OU] = "W5364U7YZB"`
  (Tailscale Inc's Developer ID), or, for the Mac App Store app, whose leaf
  certificate is Apple's and names no team, the store's marker
  (`certificate leaf[field.1.2.840.113635.100.6.1.9] exists`) with
  `identifier "io.tailscale.ipn.macos"`. The answer is remembered per bundle
  path and modification date. A bundle that fails is passed over as if it
  weren't there; none left is "not installed". Launch Services is asked only
  when `/Applications` has none, and the CLI is looked for only when Capsid
  first needs it, never for someone who never opens Settings → Phone or
  turns Remote on.
- The URL is `https://<node>.<tailnet>.ts.net:8443/` from
  `tailscale status --json` (`Self.DNSName`, trailing dot dropped).
- **Every request**:
  - `Host` must be exactly the node's DNS name with `:8443` (or without a
    port). Anything else: 403. This blocks DNS rebinding from a browser on
    this Mac. `--demo remote` is the only exception (allows `127.0.0.1:<port>`
    and `localhost:<port>`).
  - All `/api/*` routes need a paired device token: cookie `bench_device`
    (HttpOnly, Secure, SameSite=Strict, Path=/). 401 without it. The token is
    the real gate: any local process can reach loopback and forge headers.
  - `Tailscale-User-Login` (set by Serve) must equal the login recorded when
    Remote was turned on; checked as an extra, not relied on. Capsid keeps
    that login only as the SHA-256 (hex) of its lowercased form
    (`remoteLogin`), hashes Serve's the same way and compares the hashes; an
    address an earlier build stored is hashed and written back at launch.
  - Responses: `Cache-Control: no-store` (but `/app.js` and `/app.css` are
    `private, max-age=31536000, immutable` when asked for as `?v=<hash>`, the
    first 12 hex digits of the SHA-256 of the file as embedded; `/` names those
    two URLs, and a missing, stale or padded `v` stays `no-store`, as do `/`,
    `/sw.js` and every `/api/*`), `X-Content-Type-Options: nosniff`,
    `Referrer-Policy: no-referrer`, and for HTML a strict CSP:
    `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`.
    All assets inline-free files served by Capsid itself (no CDNs).
  - POSTs need `Content-Type: application/json`, an `Origin` equal to the
    served origin, and `X-Bench: 1`. Bodies ≤ 8 KB (16 KB for a Phase 2
    `/message`).
  - Never log request bodies, tokens or session text. Log only route + status.
- **Pairing**: Settings → Phone's "Pair your phone" step shows a QR code of
  the URL and a one-time 6-digit code (expires after 10 minutes; 5 wrong tries wear it out, and
  Settings then shows "Too many wrong codes." with New Code rather than a new
  code by itself).
  `POST /pair {"code","name"}` → sets the cookie; Capsid stores only a SHA-256
  hash of each token, with the device name and when it was paired / last
  seen, in `~/Library/Application Support/Bench/remote-devices.json` (folder
  0700, file 0600, written to a temporary file and renamed). Not the Keychain:
  Capsid is signed without a Team ID, so macOS ties a Keychain item to one
  build and asks for the login password after every update, with Capsid
  frozen waiting (seen 2026-10-13). Settings lists paired
  phones with Remove. iOS keeps a Home Screen app's storage apart from
  Safari's, so the flow is: scan → Add to Home Screen → open it → enter the
  code there.

### Routes (one allowlisted table)

| Method | Path | Auth | What |
|---|---|---|---|
| GET | `/` | none | The app shell (HTML). Shows the pairing screen when not paired. |
| GET | `/app.js`, `/app.css`, `/manifest.webmanifest`, `/icon-180.png`, `/icon-512.png` | none | Static, from the binary. |
| POST | `/pair` | code | Pair this device. |
| GET | `/api/me` | token | `{"paired":true,"device":"Sam's iPhone","bench":"0.4.0","browse":true}` (`browse` since Phase 3) |
| POST | `/api/unpair` | token | Removes this device. |
| GET | `/api/state` | token | The snapshot below. |
| GET | `/api/events` | token | Server-Sent Events: `event: state` with the snapshot on every change, a `: keepalive` comment every 25 s. |
| GET | `/api/sessions/<id>` | token | One session (version 2 since Phase 2, below). `<id>` must match `^[0-9a-f-]{36}$`. |
| POST | `/api/sessions/<id>/open` | token | Open it on the Mac (`LabModel.open`). |
| GET | `/sw.js` | none | The service worker for pushes: static, from the binary, once the phone app has it. |
| GET | `/api/push` | token | `{"publicKey","subscribed","prefs"}` (Notifications, below). |
| POST | `/api/push/subscribe` | token | Keep this device's subscription (and prefs). |
| POST | `/api/push/prefs` | token | Change this device's prefs. |
| POST | `/api/push/unsubscribe` | token | Drop this device's subscription. |
| POST | `/api/push/test` | token | Push "Notifications are on." to this device. |
| POST | `/api/sessions/<id>/approve` | token | Approve its plan: `{"version"}` (Phase 2, Actions). |
| POST | `/api/sessions/<id>/answer` | token | Answer, choose for me or cancel its question (Phase 2, Actions). |
| POST | `/api/sessions/<id>/message` | token | Send it a message: `{"text","id"}`; body up to 16 KB (Phase 2, Actions). |
| GET | `/api/sessions/<id>/artifacts` | token | The session's artifacts, projected in the page (Phase 3, Artifacts). |
| GET | `/api/files/<v>/thumb?w=120\|800` | token | A listed image's WebP thumbnail (Phase 3, Artifacts). |
| GET | `/api/files/<v>/text` | token | A listed markdown, text or table file, as JSON (Phase 3, Artifacts). |
| GET | `/api/files/<v>/download` | token | A listed file's bytes, as an attachment, ≤ 8 MB (Phase 3, Artifacts). |
| GET | `/api/projects` | token | Every project, with its session count and latest activity (Phase 3, Browse). |
| GET | `/api/projects/<pid>/sessions[?before=<cursor>][&q=<text>]` | token | A project's sessions, 50 a page, newest first (Phase 3, Browse). |
| POST | `/api/projects/<pid>/sessions` | token | Start a session: `{"text","id","planFirst"}`; body up to 16 KB (Phase 3, New session). |
| GET | `/api/sessions/<id>/history[?before=<i>]` | token | A page of the whole conversation, oldest first (Phase 3, History). |
| GET | `/api/sessions/<id>/turn/<i>` | token | One cut turn whole (Phase 3, History). |
| POST | `/api/sessions/<id>/photo` | token | Send it a photo and a message: `{"image","text","id"}`; body up to 6 MB (Phase 4, Photos). |
| POST | `/api/projects/<pid>/photo` | token | Start a session with a photo: `{"image","text","id","planFirst"}`; body up to 6 MB (Phase 4, Photos). |
| POST | `/api/sessions/<id>/permission` | token | Allow once or deny the head of its permission requests: `{"id","decision":"allow"\|"deny"}` (optionally `"kind"`); answers `{"result":"allowed"\|"denied"\|"changed"\|"unavailable","sentence"}` (Phase 4, Permission requests). |
| GET | `/api/sessions/<id>/live` | token | A working session's text so far (its last 4,000 characters) and its activity line: `{"working","text","activity"}` (Phase 4, Live text). |

### `/api/state` (version 1)

```json
{
  "version": 1,
  "bench": "0.4.0",
  "updatedAt": "2026-10-12T19:40:00Z",
  "problem": null,
  "needsYou": [
    {"id": "…36…", "title": "Protein stability screen", "project": "Example project",
     "reason": "plan", "sentence": "Plan ready for your review",
     "since": "2026-10-12T19:31:00Z", "snooze": {"until": "2026-10-12T19:50:00Z", "afterFocus": false}}
  ],
  "failed": [{"id": "…", "title": "…", "project": "…", "since": "…"}],
  "working": [{"id": "…", "title": "…", "project": "…", "startedAt": "…", "paused": false}],
  "recent": [{"kind": "finished", "id": "…", "title": "…", "project": "…", "at": "…", "line": "Finished"}],
  "usage": {"limits": [{"name": "5-hour", "usedPercent": 54, "resetsAt": "…", "pace": "At this pace: limit around 3:40 PM"}]},
  "pause": null
}
```

`snooze` is null when not put off; `problem` is a short sentence when Capsid
can't see sessions ("Claude Science isn't running"); `usage` is null when
unknown. A working row's `paused` is true while a used-up limit holds it, and
`pause` then says which limit and until when (null while none is held; Usage
pause). Dates are ISO 8601 UTC. Titles and project names are the user's own,
shown only to their paired devices.

### `/api/sessions/<id>` (version 1)

```json
{
  "version": 1,
  "id": "…", "title": "…", "project": "…",
  "state": "needsInput", "reason": "plan", "sentence": "Plan ready for your review",
  "startedAt": "…", "updatedAt": "…",
  "plan": {"summary": "…", "steps": ["…"], "feasibility": "high"},
  "messages": []
}
```

`plan` only when Capsid already holds the plan card's preview; `messages`
stays empty in Phase 1 (session text needs its own research and Sam's
say-so).

### Settings → Phone (tab `phone`)

A checklist that walks a first-time user through setup, then gets out of the
way (`Remote/PhoneSetup.swift`, pure and tested; `Remote/PhoneSettings.swift`
draws it). A grouped form at a fixed 760 pt (`settingsPage(height:)`): with
steps 1, 2, 3 or 5 open, or ready, everything fits; with step 4 or 6 open, or
Pair Another Device, the whole checklist shows and the switches and devices
below are a scroll away.

1. **Header.** "Capsid on your phone", then "Use Claude Science from your
   iPhone or iPad: see what needs you, answer, approve and send messages,
   over your own private Tailscale network." and a "Setup guide" link to
   `docs/phone.md` on GitHub.
2. **Set up.** Six steps, each a row with a mark (`checkmark.circle.fill`
   when done, a numbered circle when not) and its title. Detection drives
   everything; nobody ticks anything. A done step is one line, its title and
   what was found in secondary text. Only the first step not done is open:
   its title, one line of help and its action. The steps after it are dimmed
   with no buttons (one already done keeps its tick).

   | # | Title | Help | Action | Done when (found) |
   |---|---|---|---|---|
   | 1 | Install Tailscale on this Mac | Free. It links your own devices into a private network. | Get Tailscale (tailscale.com/download/mac) | the signature-checked CLI is found ("Installed") |
   | 2 | Sign in to Tailscale | Use the same account you'll use on your phone. (Signed in but disconnected: "Tailscale is off. Open it and connect, with the same account you'll use on your phone.") | Open Tailscale (the app whose signature was checked) | running with a login (the login) |
   | 3 | Turn on HTTPS for your network | One switch on Tailscale's DNS page, so your phone gets a secure address. | Open DNS Settings… (login.tailscale.com/admin/dns, or the page `serve` printed) | `CertDomains` isn't empty ("On") |
   | 4 | Put Tailscale on your phone | Install Tailscale from the App Store and sign in with the same account. | a 96 pt QR code of Tailscale's App Store page, "Scan for the App Store"; "Don't see it? Make sure Tailscale is on and signed in with the same account on your phone (Apple, Google and GitHub sign-ins are separate accounts)."; a quiet Skip link | a `Peer` with `OS` iOS, iPadOS or android (any case) and the same user, online or not ("Found: <HostName>"); or Skip ("Skipped", `remotePhoneSkipped`) |
   | 5 | Turn on Capsid on your phone | A private page for your devices on Tailscale. Never on the internet. (Switched on but not served yet: what it waits for, and Try Again when blocked or failed.) | the switch (`remoteEnabled`) at the end of the title's line | serving (the `https://…:8443` address) |
   | 6 | Pair your phone | Once per device, with a one-time code. | the pairing block: the QR code of the address, the 6-digit code with its countdown (or "Too many wrong codes." and New Code), and the three steps (scan, Add to Home Screen, open it and enter the code) | a device is paired ("1 device") |

   The same user: the peer's `UserID` is `Self.UserID`, or its `User` entry
   has the same `LoginName` (any case); a `UserID` of 0 (tagged) is nobody's.
   An online phone is named before an offline one, then by name.
3. **Ready.** With all six done the section is one row: "Ready · 1 device"
   with the address under it in secondary text (the address would otherwise
   be cut short beside the button), and Pair Another Device. That opens the
   pairing block under the row (its button becomes Cancel, which also
   withdraws the code) until one more device pairs.
4. **The code** is issued only while "Pair your phone" is the step open
   (first time, or after Pair Another Device), not whenever the tab shows.
5. **Below**, as before: anything Capsid needs to say, each with a warning
   sign (Tailscale signed in as someone else now; "Capsid couldn't remove its
   Tailscale mapping" with Try Again; while serving, "Other Tailscale Serve
   sites on this Mac share its address, and can see your devices' Capsid
   sign-in. Serve only things you trust here."); one section of switches
   ("Use Capsid from your phone" whenever it is on and step 5 isn't the step
   open, so it can always be turned off; the actions and browse switches);
   and Paired devices: name, paired, last seen, Remove, Remove All Devices…,
   and the footnote "Expires if unused for 60 days."
6. **Looking again.** While the tab shows and setup isn't done, it looks at
   Tailscale every 10 s and whenever Capsid comes to the front
   (`RemoteController.poll`), so ticks appear by themselves as the user works
   in Tailscale's own app. A look is `status --json` only; `serve` runs only
   when it could now work (Tailscale has come up, or HTTPS was just turned
   on); one look at a time. Nothing looks while the tab is hidden or once
   setup is done.
7. **Look.** Grouped form, system controls, SF Pro. Clay only on the open
   step's one button (and, as on every tab, the switches); links are the
   system's.

The cookie keeps its name (`bench_device`), so paired phones stay paired.
Turning the switch off stops the listener, removes Capsid's serve mapping
only, and keeps paired devices (so turning it back on needs no re-pairing);
"Remove all devices" is separate.

`--demo phone-settings --step N` shows the page in a plain window that
doesn't activate Capsid (with `--quiet` and `open -g -n`): 1 to 6 opens that
step with every one before it done, 7 is ready with one device. All made up
(`you@example.com`, `https://your-mac.your-tailnet.ts.net:8443`, code 123 456,
a phone and a device both "iPhone"); no Tailscale, no files, no Keychain, and
its buttons do nothing.

### The phone app

- Mobile web app, iOS look (system font, large titles, inset grouped lists,
  light and dark from `prefers-color-scheme`), clay `#D97757` as the one
  accent. Standalone display (`apple-mobile-web-app-capable`), safe areas.
- Screens: **Now** (Needs you, Working with live clocks, Recent), **Session**
  (status, the plan's summary and steps when known, Open on Mac), **Settings**
  (this device's name, Unpair). Pull to refresh.
- Live: `EventSource('/api/events')`; on `visibilitychange` to visible, refetch
  `/api/state` and reconnect. If nothing new for 60 s while visible, show
  "Not updating since …". On 401 show pairing; on a network error or 502
  show "Capsid isn't running on your Mac, or your Mac is asleep".
- No third-party code, no CDNs, everything served by Capsid.

### `--demo remote`

Serves the app on `http://127.0.0.1:<port>` with made-up sessions, a fixed
pairing code `000000`, and the Host check relaxed to localhost. Never in a
real launch, never touches Tailscale, the stored devices or the real settings. Quitting it
removes no mapping: the quit hook doesn't run in a demo. Its budgets are the
real ones.

### How the server does it (0.4.0)

Files: `Remote/RemoteServer.swift` (parsing, the route table, the checks,
the `NWListener` server), `RemoteAuth.swift` (code, tokens, devices),
`RemoteAPI.swift` (the JSON and the change feed), `TailscaleBridge.swift`,
`RemoteController.swift`, `PhoneSetup.swift` and `PhoneSettings.swift` (the
tab's checklist and its page), and `RemoteWebApp.swift`
(the phone app's files, generated). What decides is pure and tested; the
CLI runs through one injectable runner, the devices through an injectable
store (in memory in tests and the demo).

- **Order of the checks**: Host (403), a `Tailscale-Funnel-Request` header
  (403), `Tailscale-User-Login` (403 when missing or different: a request
  without it didn't come through Serve), the route (404; a known path under
  another method 405), for a POST its media type (415), Origin and `X-Bench`
  (403) and size (413), then for `/api/*` the cookie (401). The parser
  refuses a head over 16 KB (431), `Transfer-Encoding` (501), absolute-form
  targets, folded or bare-CR/LF headers and doubled `Content-Length` (400),
  and a declared body over the route's limit before reading it (413; 8 KB,
  16 KB for Phase 2's `/message`). Routes match the
  path exactly, never decoded. The log names the route's pattern, the status
  and, for a refusal, which check refused (`host`, `login`, `funnel`,
  `route`, `method`, `type`, `origin`, `xbench`, `size`, `token`, `device`),
  never a path. Every check above reads the head alone, so they all run as
  soon as the head has parsed, before any body is waited for: a head that
  fails is answered at once, with its body still to come. One that passes has
  3 s for its body. A head has 10 s to arrive; at most 32 connections. Then
  the device's budget (Budgets, below).
- **The code** exists only once Settings → Phone shows one (while its
  "Pair your phone" step is open), and goes when used. The fifth wrong try still answers 403 but wears the code out and
  starts a wait in which tries get 429: 30 s, then 2 minutes, then 10 minutes
  each time after, starting again from 30 s after a pairing or an hour
  without a wrong try. No new code comes by itself after one is worn out:
  Settings says "Too many wrong codes." with a New Code button, so someone
  guessing doesn't get a fresh code after every wait and the real phone isn't
  kept waiting by them. (An expired code is still replaced by itself.) The
  demo keeps `000000` but waits the same way.
- **The cookie** has `Max-Age` 400 days, so a Home Screen app stays paired;
  the demo leaves out `Secure` (plain HTTP). A device not seen for 60 days
  (`lastSeen`, else when it was paired) is no longer paired: its token stops
  working at once, and it leaves the list (and the file) on the next load,
  with a log line that says how many, never which. Unpair clears it and ends the
  device's event streams, as Remove in Settings does. `lastSeen` changes at
  most once a minute and reaches the file at most every 5 minutes.
  Capsid reads the file only once the Phone tab shows or the switch is on.
- **State**: `recent` leaves out saved files (no session, and the file name
  stays on the Mac). Limit names are `5-hour`, `Weekly`, `Weekly Opus`,
  `Weekly Sonnet`; `pace` is the popover's forecast line or null. The
  stream sends the state only when something it shows changed.
- **Serve**: Capsid's mapping is 8443 with one handler, `/` proxied to
  `http://127.0.0.1:<p>` for a `p` in 47280…47290 (an earlier run's port is
  replaced: `off`, then add). 8443 with anything else (another target, more
  mounts, TCP forwarding, a foreground serve, Funnel) is someone else's:
  Settings says so and Capsid neither adds nor removes. When `serve` prints a
  `login.tailscale.com` page to turn HTTPS on, Capsid stops it there and
  offers the page as a button. With the switch on and Tailscale not up yet,
  Capsid looks again 15 s, 1 min and 5 min later, and whenever it comes to
  the front.
- **The mapping lasts only while Capsid answers behind it.** Otherwise
  whatever binds the loopback port while Capsid is away (another user's
  process, another app) would get what the phone sends, its `bench_device`
  cookie included, and could serve its own page on the trusted origin. So:
  - **Quitting** (`applicationWillTerminate`) removes Capsid's mapping,
    synchronously and best effort: `serve status`, then `serve --https=8443
    off` only when 8443 is Capsid's alone, waiting at most 2 s in all. Never in
    a demo; never for someone who never served (no switch on, no remembered
    port). It runs whether the switch is on or off; on, the next launch adds
    the mapping again. The phone then sees no Capsid until then.
  - **Launching with the switch off** removes a mapping Capsid left behind,
    the same way.
  - **Turning the switch off** when the mapping can't be removed (Tailscale
    not running, or `off` failing) leaves "Capsid couldn't remove its
    Tailscale mapping" in Settings with Try Again, and Capsid tries again on
    Check Again, when it comes to the front, and 15 s, 1 min and 5 min later.
  - The mapping is still `--bg`: Capsid doesn't keep a foreground `serve` as
    a child process.
  - What remains: a crash, or a quit that Tailscale doesn't answer within
    2 s, leaves the mapping until Capsid next launches.

### Phase 2: read, act, notify (0.4.0)

Sam's call (2026-10-12): the phone must do more than look. Paired devices can
read a session's latest reply and last few turns, answer its question,
approve its plan, and send it a message; and each device can opt in to push
notifications. Research: `Bench-phone-research.md` (outside the repo).

#### Reading a session (in-page, projected)

Capsid reads through its own web view, as `apiGET` does, but with a dedicated
**session reader** whose JavaScript runs the two GETs *and projects them inside
the page*, so Swift only ever receives the fields below. Allowed GETs, exactly:
`/api/frames/<36>?shallow=true` and `/api/frames/<36>/messages?from=-12&limit=12`.
`no-store`, never logged, never saved, held only while a response is built
and then at most 5 s in memory (so a burst of requests reads the page once;
dropped after any action on the session; whatever is older goes at every ask,
not only once the asking pauses).

- From the shallow frame: `status` (one of the eight known values, else
  unreadable), `agent_name`, `project_id`, `status_description` (≤ 200 chars),
  `output_data.response` (the last reply, ≤ 4,000 chars),
  `context_data._sent_user_messages[]` (the agent's "messages to you": last 5,
  `{text ≤ 2,000, at}`), `queued_user_messages.length`,
  `output_data.pending_input_requests[]` (only `kind:"ask"` with a string
  `tool_id` and non-empty `questions`, each with a string `question` and
  options with non-empty `label`s), and the plan fields Approve already uses.
- From `/messages`: `role` user|assistant rows only, dropping hidden user rows
  (any flag `_task_boundary`, `_rolling_summary`, `_harness_prompt`,
  `_from_agent`, `_from_aside`, `_harness_notice`; text starting `[System]`,
  `[compute]`, `[Memory]`, `[image:`, `[document:`; rows holding only tool
  results). Keep only `{type:"text"}` blocks, joined, ≤ 2,000 chars, with `_ts`.
  Never thinking, tool calls or results, images, paths, attachments,
  sub-agents or artifacts.
- Any shape that doesn't match → the session is "unreadable": the phone shows
  status and Open on Mac only. Root frame only throughout.

#### `/api/sessions/<id>` (version 2)

Adds to version 1 (all optional-null when unreadable; `version` becomes 2):

```json
{
  "readable": true,
  "statusLine": "Fitting the model",
  "reply": {"text": "…markdown…", "at": "…"},
  "turns": [{"role": "you", "at": "…", "text": "…"}, {"role": "claude", "at": "…", "text": "…"}],
  "toYou": [{"text": "…", "at": "…"}],
  "queued": 0,
  "question": {"toolId": "…", "items": [{"question": "…", "header": "…", "multi": false,
               "options": [{"label": "…", "detail": "…"}]}]},
  "plan": {"summary": "…", "steps": ["…"], "feasibility": "high", "version": "…opaque…"},
  "can": {"approve": true, "answer": false, "message": "send", "why": null}
}
```

`turns` oldest first, at most 12. `can.message` is `"send"` (completed),
`"queue"` (processing: it waits for a safe point), `"resume"` (failed or
cancelled: the session picks up again) or null with `why` ("Answer its question
first", "Approve or revise the plan on your Mac", "Actions are off in Capsid's
Settings", "Capsid can't read this session"). `can.approve` only when the root
itself awaits plan approval and Approve's shape checks pass; `can.answer` only
for a root `ask`. The phone renders `reply` and `turns` as plain text with a
small safe markdown subset (paragraphs, lists, bold, italic, inline and fenced
code), built as DOM nodes, never `innerHTML`; links are shown as text.

#### Actions (three routes, one shared limiter)

Bodies ≤ 8 KB, except `/message`, whose body may be up to 16 KB (4,000
characters of non-Latin text is more than 8 KB of JSON); the parser's
declared-length check takes the route's own limit.

| Route | Body | Capsid does |
|---|---|---|
| `POST /api/sessions/<id>/approve` | `{"version":"…"}` | `PlanApprover` as on the card: re-GET, require `awaiting_plan_approval`, not approved, same plan version; then `approve-plan` `{}`. |
| `POST /api/sessions/<id>/answer` | `{"toolId":"…","answers":{"<question>":"<text>"}}` or `{"toolId":"…","action":"chooseForMe"\|"cancel"}` | Re-GET; require `awaiting_user_response`, the same `tool_id` pending on the root, the same question texts; every question answered (≤ 1,000 chars each). Then `resolve-input` `{responses:[{tool_id, action:"answer", answers}]}`; chooseForMe sends `action:"answer"` with every question answered "Use your best judgment for this question"; cancel sends `{tool_id, action:"cancel", answers:{}}`. |
| `POST /api/sessions/<id>/message` | `{"text":"…","id":"<uuid v4>"}` | Text trimmed, 1…4,000 chars, with none of the UI's reference prefixes (400 `{"error":"reference"}`, as the photo routes). Re-GET; allowed only for `completed`/`success`, `processing`, `failed`/`cancelled`. Then `POST /api/request` `{target_agent: <agent_name from the re-GET>, root_frame_id, project_id, input_data:{request:text}, intent_id: id, plan_mode:false}`. A re-GET without a `project_id` sends nothing (`unavailable`): `/api/request` without one is how the daemon makes a project. The phone's `id` is the intent id, so a retry dedupes. |

Each answers `{"result": …, "sentence": "…"}`: approve → `approved` |
`changed` | `unavailable`; answer → `sent` | `changed` | `unavailable`;
message → `sent` | `queued` | `resumed` | `blocked` | `unavailable`. Any
unexpected status, 404/405, unknown 4xx `code` or non-JSON reply is
`unavailable` ("Couldn't do that from here. Open it on your Mac."). 403
`csrf_stale` is refreshed and retried once inside the page, as Approve does.

- **The writer**: `apiPOST` stays for the card; a separate in-page writer
  allows exactly `/frames/<36>/approve-plan` (`{}`),
  `/frames/<36>/resolve-input` and `/request`, and builds each body in the page
  from typed arguments (never string interpolation), checking the shape again
  there.
- **Limits**: at most 6 actions a minute per device (429 after), within the
  device's budget for every route (Budgets, below). Settings →
  Phone has "Let paired devices answer, approve and send messages"
  (`remoteActions`, on); off, the routes answer 403 and `can` is all off with
  `why` "Actions are off in Capsid's Settings".
- **Never logged**: route pattern and status only, as for every request.
- **Beneath the gates** (since 0.7.0): `act` checks the phone's own gates
  (the switch, the device's limit, which sessions it may open, the body),
  then calls `RemoteSessions.respond`, which does the rest on the session's
  serial queue: the fresh read, the decision and the write. The Mac's reply
  window (Lab, Answering from the card) calls `respond` itself,
  with an answer built by `RemoteActionRequest.checkedAnswer`, the check
  `parse` also uses; so the two take turns on a session, and the second to
  arrive finds it answered and writes nothing. Its permission answers are
  the phone's `.permission` requests, under the same table; what to change
  in a plan is `.planFeedback`, which `parse` never makes, so no phone route
  can send it.

#### How the server does it (Phase 2 actions)

Files: `Remote/SessionReader.swift` (the in-page projection and Swift's
checks of it), `Remote/SessionWriter.swift` (the in-page writer) and
`Remote/RemoteActions.swift` (the bodies, the decisions, the limit, and
`RemoteSessions`, which reads and acts over injected closures). The shared
files only gained hooks marked `// Phase 2 actions`.

- **Tested as it runs.** The projection, the writer's body builder and its
  reply summary are plain JavaScript strings; the tests run those very
  strings in JavaScriptCore (WebKit's engine) on made-up frames, and the
  in-page bodies against a fake `fetch` that records each path and body.
- **Shape gates.** Statuses are the daemon's eight (`processing`,
  `awaiting_user_response`, `awaiting_plan_approval`, `completed`,
  `success`, `cancelled`, `replaced`, `failed`). The page returns
  `JSON.stringify` of its projection; Swift re-checks every type, count and
  length (code points), and any mismatch is unreadable. A question's text
  and its option labels are never cut (they go back as the answer's keys):
  one that is too long, a duplicate question or an empty label leaves the
  question unoffered, and a first question that doesn't match is not
  passed over for a later one. The plan fields follow `PlanFrame`'s rules
  (context first, then output), checked against it in the tests.
- **The plan's text** isn't in the shallow frame: the card's preview when
  it is the same version, else `apiGET /artifacts/versions/<v>` and
  `PlanCheck.preview`, as the card does. `plan.version` is the plan version
  id; Approve sends it back and Capsid approves only while
  `PlanCheck.versionToRead` of a fresh read equals it.
- **Reading** happens only when the phone asks for `/api/sessions/<id>`,
  and only for a session Capsid knows (else 404, nothing read). What was read
  is held 5 s per session (a burst reads the page once; concurrent asks
  share one read) and dropped after any action on that session.
- **Order of an action's checks**: the setting (403
  `{"error":"actionsOff","result":"unavailable","sentence":…}`), the
  device's limit (429; every attempt counts), a known session (404), the
  body (400), then one action at a time per session: a fresh frame read
  (frame only, no messages), the decision, the write. Result mapping:
  approve uses `PlanCheck.outcome` (`plan_frame_processing` is `changed`,
  "Claude is busy with it"); answer: 200 `accepted`/`buffered` → `sent`,
  `already_resolved` or 400 "not awaiting user response" / "No pending
  request" → `changed`; message: `accepted` → `sent` (`resumed` when the
  fresh read was `failed`/`cancelled`), `message_queued` → `queued`,
  `already_delivered` → `sent`, 400 "pending question" or the daemon's 429
  → `blocked`; everything else `unavailable`.
- **`can.why`**, in this order: actions off, unreadable, then the status
  (`replaced`, which the research's table leaves out, says "This session
  can't take a message from here"; a root without an `agent_name` takes no
  message: "Capsid can't read this session").
- **`--demo remote`** reads made-up projections (a question with three
  options, a plan at version `demo`, a failed session, a queued message, a
  finished reply, one unreadable session) and its writes answer as the
  daemon would without touching a web view.

#### Notifications (Web Push, opt-in per device)

iOS delivers Web Push to a Home Screen web app (16.4+). Capsid sends them
itself: encrypted per RFC 8291 (`aes128gcm`) so only the device can read
them, signed with VAPID (RFC 8292, ES256), all with CryptoKit.

- **Keys**: one VAPID P-256 key pair, made the first time a device subscribes,
  kept in a file beside the devices'. JWT `aud` = the endpoint's origin, `exp`
  now + 1 h, `sub` = `https://github.com/samporter14/bench`.
- **Routes**: `GET /api/push` → `{"publicKey":"<base64url>","subscribed":bool,"prefs":{…}}`;
  `POST /api/push/subscribe` `{"endpoint":"…","keys":{"p256dh":"…","auth":"…"},"prefs":{…}}`;
  `POST /api/push/prefs` `{…}`; `POST /api/push/unsubscribe` `{}`;
  `POST /api/push/test` `{}` (sends "Notifications are on." to this device).
  The endpoint must be `https`, ≤ 1,024 chars, on `web.push.apple.com`,
  `fcm.googleapis.com`, `updates.push.services.mozilla.com` or
  `*.notify.windows.com`. The subscription is stored with the device's
  record and goes when the device is removed or unpaired.
- **Prefs** (per device): `needsYou` (on), `errors` (on), `finishes` (off),
  `names` (off), `onlyAway` (on), `badge` (on: the count on the Capsid icon,
  below). A record from before reads `badge` as on.
- **When**: from the same moments that raise a card (LabModel's announce hook),
  once per device per event (session + kind + since). Finishes held during a
  Nidus focus session follow the hold. `onlyAway`: skip while the Mac is in use
  (screen unlocked and input within the last 2 minutes).
- **Payload** (JSON, ≤ 1 KB before encryption):
  `{"v":1,"title":"…","body":"…","tag":"<kind>-<id>","url":"/#/session/<id>","badge":2}`.
  `badge` (an integer, 0 or more) is there only for a device whose `badge`
  pref is on (see the icon's count, below). With `names` off: title "Claude
  Science", body "A session needs you: plan ready for review" / "A session
  stopped with an error" / "A session finished". With names on: the session's title, then its sentence and
  project. Headers: `TTL: 3600`, `Urgency: high` (needs you, errors) or
  `normal`, `Topic` = a 22-char base64url hash of tag, so a newer push replaces
  an older one.
- **Delivery**: an ephemeral `URLSession`. 201 ok; 404/410 drop the
  subscription; 413/400 log the status; 429 or 5xx wait and retry once after
  `Retry-After` (≤ 10 min). Never log endpoints or payloads.
- **Phone**: `/sw.js` (served from the binary, scope `/`) shows the push with
  `icon:/icon-180.png` and `tag`, and on tap focuses the app or opens `url`.
  Settings on the phone: "Notifications" with a Turn On button (needs a tap,
  and only works from the Home Screen app; in Safari it says so), the six
  prefs (the last is "Show a count on the Capsid icon"), Send a test. Taps
  work off the tailnet too (the push comes through Apple), but opening the
  session needs Tailscale on.
- **The icon's count** (Home Screen badge, like Mail's unread count): the
  number of sessions that need you plus the number that stopped with an
  error, i.e. `needsYou.length + failed.length` of `/api/state`. It is
  the same number on the Mac side (`RemoteAPI.badge(lab:)`, which reads the
  two lists the state is built from) and in the app.
  - *In the app* (`applyBadge` in `app.js`): every time a state arrives (the
    stream, a poll, or opening the app) it calls `navigator.setAppBadge(n)`,
    or `clearAppBadge()` at 0 or when signed out. Only when
    `'setAppBadge' in navigator` and the app runs from the Home Screen
    (`navigator.standalone` or `display-mode: standalone`), and every call
    sits in try/catch, since the promise rejects when iOS doesn't allow it.
    It never asks for permission: iOS shows a Home Screen app's badge only
    when it has notification permission, so the count rides on the
    Notifications permission the user already gave.
  - *In a push*: Capsid puts `"badge": <count>` in the payload, and `sw.js`
    calls `self.navigator.setAppBadge(badge)` (or `clearAppBadge()` for 0,
    in try/catch) next to `showNotification`. A payload without a numeric
    `badge` leaves the icon alone.
  - *No silent pushes*: iOS doesn't deliver a push that shows nothing, so
    Capsid can't refresh the icon on its own. It changes when a push arrives
    (any push carries the count as it is then) or when the app is opened. A
    count that only goes down (answering a question on the Mac sends nothing),
    or goes up with no push (you were at your Mac, or turned that kind off),
    stays as it was until one of those.
  - *The switch*: "Show a count on the Capsid icon" in the phone's Settings →
    Notifications (on by default; also shown when notifications are off but
    allowed, since the app's count still works then). The app keeps it in
    `localStorage` (`bench-badge`: per device, and there before Settings has
    loaded; the phone app used no storage before this), and sends it as the
    `badge` pref with `POST /api/push/prefs`, because the service worker
    can't read `localStorage`. Off: the app clears the icon and doesn't set
    it, and Capsid leaves `badge` out of that device's pushes. When Settings
    loads, the Mac's value is written back to `localStorage` (so a
    re-paired phone follows what its pushes do).
- **Test**: `POST /api/push/test` ignores `onlyAway` (Sam is at the Mac when
  he presses it) and the other prefs (but `badge` decides whether it carries
  the count). At most three a minute per device (429
  `slowDown`): each is a push signed with the one key every device shares.
- **Demo**: `--demo remote` makes no keys and no network calls; subscribe
  answers as if subscribed, and the test does nothing.
- **Promise**: README's line gains "and, if you turn on notifications on a
  paired device, Apple's push service carries them, encrypted so only that
  device can read them". And "changes nothing in it, except when you press
  Approve on a plan's card" becomes "…except when you press Approve on a
  plan's card, or answer, approve or send a message from a paired device"
  (README and DESIGN together).

#### How the server does it (push)

Files: `Remote/WebPush.swift` (RFC 8291 encryption, RFC 8292 VAPID, the
subscription checks; pure, and tested byte for byte on RFC 8291's own
example) and `Remote/PushCenter.swift` (`PushRules`, pure: which cards, the
words, the payload, the headers, what an answer means; `PushCenter`: the key,
the routes, the announce hook, delivery). The hooks elsewhere are single
lines marked `// Phase 2 push`.

- **Storage**: a device's `push` (`{subscription, prefs}`) is a field of its
  record in the devices' file; a record from before reads as none,
  and one without push writes none. The VAPID key is a second file beside it
  (`remote-push-key.json`: JSON with the private scalar, 0600). It
  is made the first time a paired device asks `GET /api/push`, since the
  phone needs the public key to subscribe. One that can't be read is never
  replaced: every subscription depends on it. Unsubscribe keeps the prefs.
  An endpoint another device record had is taken from it, so a phone paired
  twice hears each push once.
- **Replies**: every push route but the test answers as `GET /api/push`
  does; the test answers `{"sent":true}` once it is on its way. Errors: 400
  `{"error":"body"|"endpoint"|"keys"|"prefs"|"notSubscribed"}`, 500
  `"key"|"store"`. A change of prefs holds in memory at once and reaches the
  file at most once a second (the first at once, the rest a second after the
  last write, or with the next write of the file, or when Capsid quits), so
  `/prefs` never answers `"store"`.
- **When**: `LabModel.pushRaised`, called with `cardRaised`, and only while
  the Phone switch is on. The cards are `NotificationRules`' (needs you,
  errors, finishes but not while a focus session holds them, and the "While
  you focused" notice that releases them). Once per device per event: the
  session, the kind (with the waiting reason, so a question that becomes a
  plan is news again) and `updatedAt`, remembered for a day. `onlyAway`
  reads `CGSessionCopyCurrentDictionary` (`CGSSessionScreenIsLocked`, on
  console) and `CGEventSource.secondsSinceLastEventType` (any input) only
  when a device needs it. A push skipped for it isn't remembered, so the same
  moment coming again while away (a reminder) still goes.
- **The count is read when the push goes**, not when it is decided:
  `PushCenter.deliver` reads it inside the delivery task, a turn after
  `announce`. LabModel raises a card (and so calls `pushRaised`) before it
  assigns `waiting` from the same read, so a count taken at the announce
  would miss the session that has just begun to wait. A retry sends the same
  payload. The test push carries the count too when the device's `badge`
  pref is on, so Send a Test shows what a real push will do.
- **Words**: names off, the needs-you body names the kind of wait ("a
  question to answer", "permission to reach the web", or just "A session
  needs you"); the held finishes say "A session finished" or "Sessions
  finished while you focused". Title and body are cut short (120 and 240
  characters, then the body further) so the JSON stays within 1 KB.
- **Sending**: the stored endpoint is checked again, each push is sealed with
  a new salt and sender key, and the JWT is for the endpoint's origin.
  Headers: `TTL: 3600`, `Urgency`, `Topic`, `Content-Encoding: aes128gcm`,
  `Content-Type: application/octet-stream`, `Authorization: vapid t=…, k=…`.
  The test push is `Urgency: high`. A Retry-After that says nothing waits a
  minute, and the retry is sealed afresh. The log has the status only.
- **Demo**: the public key is made at launch and kept in memory only, so a
  browser can subscribe; nothing reaches the disk or the network.

### Phase 3: browse, history, artifacts, new sessions (0.4.0)

Sam's call (2026-10-13): from the phone, change projects, scroll up through a
session's whole conversation, see the artifacts older sessions made, and
start a session. Research: `Bench-phone-browse-research.md` (outside the
repo; read it, its tables are the detail behind this section). This widens
"never read content" to full history and artifact bytes, for paired devices
only, behind its own switch.

- **Switch**: Settings → Phone, "Let paired devices browse every project, full
  conversations and artifacts" (`remoteBrowse`, on). Off: these routes answer
  403 `{"error":"browseOff"}`, `/api/me` says `"browse": false`, and the phone
  hides Projects and the History/Artifacts parts.
- **Ids**: session ids `^[0-9a-f-]{36}$`; project ids `^[A-Za-z0-9_-]{1,64}$`
  (but not `__proto__`, `constructor` or `prototype`: 404 at the route);
  version ids `^[A-Za-z0-9_-]{1,128}$`. Never decoded, matched exactly.

#### Browse (from Capsid's own database, metadata only)

New read-only SQLite queries beside the existing ones, never touching
`input_data`, `output_data` or any text column (a `task_summary IS NOT NULL`
*test* is allowed, as the UI filters on it; its value is never read):
projects (id, name, root-session count, latest activity; no
`proj_concierge_sys_%`; archived hidden when an `archived_at` column exists),
a project's root sessions (keyset `(updated_at, id)` desc, 50 a page, the
existing session filter; none for an archived project), and a point lookup by id that **replaces the
known-sessions gate** for `/api/sessions/<id>`, so any root session can open.

| Route | Answer |
|---|---|
| `GET /api/projects` | `{"version":1,"projects":[{"id","name","sessions":12,"lastActive":"…"}]}` newest activity first |
| `GET /api/projects/<pid>/sessions[?before=<cursor>][&q=<2–64 chars>]` | `{"sessions":[{"id","title","state","sentence","startedAt","updatedAt"}],"next":"<opaque cursor>"\|null}`; `q` matches the session's `name` only (`LIKE`, escaped); title falls back to "Untitled session" |

#### History (in-page, projected, paged backward)

`GET /api/sessions/<id>/history[?before=<i>]` → the 50 rows before index `i`
(default: the last 50) of `/frames/<root>/messages`, projected in the page:

```json
{"total": 812, "from": 762,
 "items": [
  {"i": 762, "role": "you", "at": "…", "text": "…≤2000", "cut": false, "files": []},
  {"i": 763, "kind": "steps", "line": "Ran a command, read a file +2 more", "failed": false},
  {"i": 765, "kind": "plan", "steps": 4},
  {"i": 766, "kind": "ask", "q": "…≤300", "a": "…≤300"},
  {"i": 770, "kind": "toYou", "text": "…≤2000", "files": [{"v","a","name","kind","size"}]},
  {"i": 771, "kind": "helper"},
  {"i": 772, "role": "claude", "at": "…", "text": "…", "cut": true, "files": [ … ]}
 ]}
```

At most 60 items and 64 KB a page. Steps use the UI's group phrases only (the
research's verb table; unknown tools "made a call"), so no tool input is read;
consecutive tool rows fold into one `steps` line. Hidden rows, thinking, tool
input and results, images and paths never leave the page. Allowlisted GET:
`^/frames/<36>/messages\?from=\d{1,7}&limit=([1-9]|[1-4]\d|50)$` (and the
Phase 2 `from=-12&limit=12`). `GET /api/sessions/<id>/turn/<i>` returns one
cut turn whole, ≤ 20,000 chars: `{"i","role","at","text"}`.

`files` come from the turn's artifacts (`_artifact_refs`, save/run tool
results' `artifacts[]`, `send_user_message` attachments), keeping only
`{v: version_id, a: artifact_id, name ≤255, kind, size}`.

#### Artifacts

`kind` is one of `image` (png, jpeg, gif, webp), `svg`, `markdown`, `text`
(text, code, json, log, fasta and the like), `table` (csv, tsv), `html`,
`pdf`, `notebook`, `other`, decided from extension and content type.

| Route | Answer |
|---|---|
| `GET /api/sessions/<id>/artifacts` | `{"artifacts":[{"v","a","name","kind","size","mime","at"}]}`: from `/frames/<root>/artifacts`, ≤ 300, without `file_path`/`ref_host_path`, intermediates, `plan*.json`, `goal_*.html` and `user_hidden`; documents, then images, then tables, then the rest |
| `GET /api/files/<v>/thumb?w=120\|800` | WebP from `?thumbnail=<w>`, only for `kind:image` and only when the bytes' magic says WebP; ≤ 4 MB |
| `GET /api/files/<v>/text` | `{"kind":"markdown"\|"text","text":"…","truncated":bool}` from a 256 KB range read (UTF-8, no NUL in the first 8 KB), or `{"kind":"table","columns":[…],"rows":[[…]],"truncated":bool}` (≤ 200 rows × 30 columns, cells ≤ 200 chars) |
| `GET /api/files/<v>/download` | The bytes, ≤ 8 MB (bigger: 413 `{"error":"tooBig"}`; the phone says "Too big for the phone. Open it on your Mac."), with `Content-Type` sniffed for raster images else `application/octet-stream`, `Content-Disposition: attachment; filename="<ASCII-safe>"; filename*=UTF-8''…`, `Content-Security-Policy: default-src 'none'; sandbox`, `X-Content-Type-Options: nosniff`, `Cross-Origin-Resource-Policy: same-origin`, `no-store` |

- **Only what was listed**: Capsid serves `/api/files/<v>/…` only for version
  ids it listed to *that device* (an artifacts list or a history page's
  `files`) in the last hour.
- **Never as a page**: HTML, SVG and notebooks are never rendered on Capsid's
  origin; SVG shows only as the download (a phone can still view it from
  Files). Markdown images resolve only to this session's listed images, via
  `thumb`. Links stay text.
- **Bytes** move in-page (fetch, base64, `callAsyncJavaScript`) in v1; Capsid
  never holds the daemon's cookies.

#### How the server does it (Phase 3 files)

Files: `Remote/ArtifactReader.swift` (the in-page reads and Swift's checks of
them), `Remote/RemoteArtifacts.swift` (the routes, their checks and headers,
the table parser, `ListedFileInfo`) and `Remote/ArtifactsDemo.swift` (the
demo's files). The shared files only gained hooks marked `// Phase 3 files`.

- **Three GETs, in the page**: `/api/frames/<36>/artifacts`,
  `/api/artifacts/versions/<v>?thumbnail=120|800` and
  `/api/artifacts/versions/<v>`, built from typed arguments and checked
  against that allowlist in the page (and by the same rule in Swift) before
  anything is fetched; `no-store`. The tests run the script in
  JavaScriptCore against a fake `fetch` that streams bytes.
- **The list**: a bare array or `{"artifacts":[…]}`. Every row needs a
  string `id`, a path-safe `version_id`, string `filename` and
  `content_type` and a numeric `size_bytes`, or nothing is listed. Rows the
  UI hides are dropped; the name is the path's last segment without control
  or direction characters (≤ 255); `mime` is the media type alone or null;
  the newest 300 are kept. Swift checks every field again, classes it
  (`ArtifactKind`), sorts it (documents: markdown, PDF, HTML, notebooks;
  images: raster and SVG; tables; the rest; the daemon's oldest-first order
  within each) and records each version in `ListedFiles` and in
  `ListedFileInfo` (name, type, listed size and kind, for an hour). The
  files routes take the kind and size from there, never from the request, so
  a history page's `files` must be recorded in both too.
- **Bytes** are read from the body's stream and never past the cap: a
  `Content-Length` over it is refused unread (thumbnails 4 MB, downloads
  8 MB) and a body that runs over is cancelled. Text asks for
  `Range: bytes=0-262143`, takes 200 or 206 (starting at 0; 416 is an empty
  file), stops at 256 KB even when the daemon ignores the Range, is
  `truncated` when the stream or `Content-Range` says there is more, refuses
  a NUL in the first 8 KB, and is decoded as UTF-8 in the page (a character
  the range cut in two is dropped). Base64 and the UTF-8 decoder are written
  out in the script: JavaScriptCore has neither `btoa` nor `TextDecoder`.
- **Order of the checks**: the browse switch (403 `browseOff`); for the
  list, a session Capsid knows (404; Phase 3 browse's point lookup takes this
  place); for a file, listed to this device within the hour with its listing
  at hand (404), `?w=` exactly `120` or `800` (400 `width`), a kind the route
  serves (415 `kind`: `thumb` only images, `text` only markdown, text and
  tables), the listed size (413 `tooBig`); then the read (503 `unreadable`
  when it fails), and what came back is checked again: a thumbnail must
  start `RIFF????WEBP` (415 `notWebP`), a download must be ≤ 8 MB (413),
  text with a NUL is 415 `notText`.
- **Headers**: every files response carries `Content-Security-Policy:
  default-src 'none'; sandbox` beside the usual `no-store`, `nosniff`,
  `no-referrer` and CORP `same-origin`. A thumbnail is `image/webp` with no
  disposition (an `<img>`). A download is `attachment; filename="…";
  filename*=UTF-8''…`: the ASCII name keeps printable ASCII without
  `" \ / : ; % * ? < > |`, folds accents, drops controls, shows a leading dot
  as `_`, keeps the extension within 150 characters and is "file" when
  nothing is left; `filename*` percent-encodes every byte outside
  `[A-Za-z0-9._-]` (180 characters of the name at most). Its type is the
  sniffed PNG, JPEG, GIF or WebP only for a file listed as an image whose
  bytes agree; everything else, HTML, SVG and notebooks always, is
  `application/octet-stream`.
- **Tables**: one pass; RFC 4180 quotes (`""`, line breaks inside quotes),
  CRLF, LF or CR, a BOM skipped, a tab for `.tsv` or
  `text/tab-separated-values`. The first record is `columns`; then at most
  200 rows and 30 columns (the rest of a 10,000-column line is scanned, never
  kept), cells cut at 200 characters with "…", every row padded to the
  widest; a text cut short loses its incomplete last record. `truncated`
  when anything was cut.
- **Size**: a response is built whole (the body up to 8 MB) and sent once;
  the phone has 60 s to take it (then the connection goes), and a device has
  at most two files under way at once (Budgets, below).
- **`--demo remote`**: "Primer design" has one file of every kind (a chart
  drawn with CoreGraphics as a PNG, its WebP thumbnails written by Capsid as
  two-colour lossless VP8L since ImageIO can't write WebP, markdown, a CSV
  with quotes and a line break, a log, HTML and SVG that carry a script, a
  PDF, a notebook, an 8 MB file at the cap and a 120 MB one listed only);
  two other sessions have a few, one has none, and "Gel quantification"
  can't be read (503). Served from memory through the same checks.

#### New session

`POST /api/projects/<pid>/sessions` `{"text":"…1–4,000","id":"<uuid v4>","planFirst":false}`
→ in the page, `POST /api/projects/<pid>/request`
`{input_data:{request:text}, plan_mode: planFirst, intent_id: id}` (no
`target_agent`: the server's default agent). Never `/api/request` (it creates
projects). Answer `{"result":"started","id":"<root_frame_id>","sentence":"Started"}`
or `unavailable`. Not retry-safe on the daemon (a reused intent gets 409 with no
ids), so on a timeout or 409 Capsid looks up, in SQLite, a root in that project
from the last 10 minutes whose `input_data` `_intent_id` equals `id` (the test
runs in SQLite; nothing else is read) and answers `started` with its id. It
counts toward the 6-a-minute action limit and needs `remoteActions` too. It
starts only in a project `/api/projects` lists (so never in a hidden concierge
or archived one): else 404, nothing written.

#### How the server does it (Phase 3 browse)

Files: `Remote/RemoteBrowse.swift` (the switch, the routes, the query and the
cursor, the answers, and `RemoteBrowser` over injected reads and writes),
`Remote/HistoryReader.swift` (the in-page projection and Swift's checks of
it), `Remote/RemoteBrowseDemo.swift` (the demo's made-up store), and the
reads at the end of `Shared/Core/SQLiteSource.swift` (Capsid's own copy). The
shared files gained lines marked `// Phase 3 browse`.

- **The switch**: `RemoteBrowse.isOn` is the first check of every Phase 3
  route, the artifact routes included; off, 403 `{"error":"browseOff"}`
  before anything is read. Off, `/api/sessions/<id>` and the actions open
  only the sessions Capsid knows, as in Phase 2.
- **SQL**: since 0.5.1 Capsid reads through one read-only SQLite connection
  (the system library, not the `sqlite3` tool), so values are bound
  parameters; ids and the cursor are still checked by shape first, and `q`'s
  `\`, `%` and `_` are escaped for `LIKE … ESCAPE '\'`. `archived_at` is probed
  with `pragma_table_info` (remembered five minutes), for the projects list and
  for a project's sessions (an archived project lists none; the point lookup by
  id is unchanged). A project's count is of
  the roots its list shows. Each read runs off the main thread; 503
  `{"error":"unreadable"}` when the database can't be read.
- **States in a list** come from `status` alone (no output is read), so a
  root still `processing` while a sub-agent waits lists as Working, unless
  Capsid knows the session: then its own state shows. A row's `startedAt` is
  when the session was created; `updatedAt` is its `updated_at`, the order.
- **The gate**: Capsid's own sessions first (nothing read), then, browse on,
  the point lookup. A session found is held an hour, so Open on Mac works
  for it; one the phone just started opens for two minutes before the
  database has it.
- **History**: without `before`, Phase 2's `from=-12&limit=12` gives the
  total and the last rows (its `from` may be the index or the -12 asked
  for), and one `from=max(0,total−50)&limit=…` reads the rest; with
  `before=i`, one GET of `from=max(0,i−50)&limit=i−from`. A 15 s timeout
  each. The page caps at 60 items and 64 KB by dropping the oldest rows
  whole and moving `from` up; Swift checks again on its own JSON. Tool calls
  fold until something is said (a turn, a plan, an ask, a message to you, a
  helper), so a row's text and its calls can share an `i`. The plurals are
  Capsid's ("ran 3 commands"), groups go by count then first use, and "+N
  more" counts the groups not shown. A turn's files (`_artifact_refs`, and
  the save and run tools' `artifacts[]`) go under its last reply on the page,
  else on its last `steps` line, which then carries `files`; a message to
  you carries its own attachments. Names lose any path. Every `v` a page
  lists goes into `ListedFiles` for that device. A row without `_ts` has
  `"at": null`. `/turn/<i>` is 404 for a row that isn't a turn.
- **New session**: browse, then actions (403 `actionsOff`), the device's six
  a minute (shared with the actions, 429), then the body (400; `planFirst`
  false when left out; up to 16 KB), then the project: one the projects query
  lists, that list held a minute (`/api/projects` fills it too), else 404 (503
  when it can't be read). 200 `accepted` with a full
  `root_frame_id` is `started`. A timeout, a 409 or a 200 without an id looks
  the intent up, and once more a second later; anything else is
  `unavailable`. README's "changes nothing" line gains "or start a session".
- **Errors**: 400 for a query or body out of shape (an unknown or repeated
  name too), 404 for a session that doesn't open, 503 for one that can't be
  read.
- **`--demo remote`**: six made-up projects; Example project has 64 sessions
  (two pages, one untitled); "Primer design" has 118 rows of history (three
  pages) with every kind of item, every kind of file and one cut turn. A new
  session is made in memory, lists first in its project, opens and reads;
  the same intent again gets the daemon's 409 and is found by it.

#### Phone

A **Projects** tab beside Now (bottom tab bar on the phone; in the iPad
sidebar, a Now/Projects switch at the top): projects with counts and last
activity → a project's sessions (50 a page, "Load more", search field, a
**New session** button) → the Session screen. The Session screen's
Conversation becomes the full history: it opens at the end and loads 50
earlier on scroll to the top (keeping the scroll position), with `steps`,
`plan`, `ask`, `toYou` and `helper` rows as one quiet line each, file chips
under turns, and "Show all" on cut turns. An **Artifacts** section (a row
count, opening a list: thumbnails for images, icons for the rest) → a viewer:
images full width (`thumb?w=800`, pinch zoom by the browser), markdown and
text through the safe renderer (`<pre>` for text), tables as a scrollable
table with a sticky header, everything else a Download button (size shown;
over 8 MB, "Open it on your Mac"). New session: a sheet with the project's
name, a text field, "Plan first" (off), Start → navigates to the new session.

Thumbnails, texts and downloads take turns, two at a time (Capsid's limit), an
image loading once it is near the screen. A read Capsid asks to wait (429) is
tried again quietly after the `Retry-After` it gives, twice; a thumbnail that
still fails shows its icon. Downloads are fetched first and then saved from
the bytes, so a refusal is a sentence under the button ("Another file is
still coming. Try again in a moment.") and never a saved file holding Capsid's
answer. Every map the page keys by an id has no prototype, and an address
naming a project or file `__proto__`, `constructor` or `prototype` opens Now.

### Budgets (since the 0.4.0 security review)

What a paired device may ask, so that a lost, stolen or buggy one can't hold
Capsid's memory, the page's main thread or the push key every device shares.
Pure (`Remote/RemoteBudget.swift`) and tested; the server asks once a
request's head has passed its checks and its device is known, before
anything is read. Over budget is 429 `{"error":"slowDown"}`, too many files
at once 429 `{"error":"busy"}`, each with `Retry-After` in whole seconds.

- **A token bucket per device** on every authenticated `/api/*` route: 120
  a minute, refilled evenly (two a second), at most 120 saved up. A request
  costs 1; `/history`, `/turn` and `/api/files/*` cost 3, and
  `/api/files/<v>/download` costs 10. A refused request spends nothing.
- **Two file transfers at a time** per device (`/api/files/<v>/thumb`,
  `/text`, `/download`): a third is `busy`, before anything is spent. One is
  under way while its connection is open and while the page is still reading
  for it.
- **A 60 s send timeout** for every response, and for each write to an
  events stream: one the phone hasn't taken by then ends the connection.
- **Open on Mac** at most once every 3 s per device; **the test push** at
  most three a minute per device. Both `slowDown`.
- **Event streams**: at most two per device (that device's oldest goes),
  eight in all (the oldest goes).
- **Push prefs** reach the devices file at most once a second.
- **`ListedFiles` and `ListedFileInfo`**, past their capacity, drop what has
  expired and then the oldest down to nine tenths of it in one sort, so a
  full list isn't sorted at every insert.
- **The phone** waits and tries a read again quietly (twice), takes its file
  transfers two at a time, and says a short sentence when an action of the
  person's is refused ("That's a lot at once. Try again in a moment.").

### Phase 4: permissions, live text, photos (0.5.0)

Sam's picks (2026-10-14): answer a session's permission requests from the
phone, watch its reply as it's written, and send it a photo. Research (outside
the repo, read them): `Bench-phone-permissions-streaming-research.md` and
`Bench-phone-upload-research.md`.

#### Permission requests

The phone sees the **head** of a session's queue of non-`ask` requests (root
or a sub-agent of it) and may answer it. Only two kinds can be **allowed**
from the phone, because only their allow is truly once:

| Kind | Allow once from the phone | Shown as |
|---|---|---|
| `local_exec` (python, r, bash, powershell; not a shared environment; no other pending request has its `tool_id`) | yes | "Run Python code" (etc.) and the code, ≤ 4 KB, ≤ 60 lines of ≤ 160 characters, monospace |
| `mcp_tool` with `read_only: true` and source `directory`, `bundled` or `antmcp` | yes | "Use <tool> from <server>" |
| every other known kind (`network`, `host`, `host_delete`, `skill_license`, credential kinds, `byoc_*`, `infer_submit`, `remote_*`, `usage_checkpoint`, `customize_mutation`, `managed_endpoint_register`, `artifact_delete`, …) | no, Deny or Open on Mac | a plain line from its own fields ("Wants to reach <host>", "Wants to read <path>"…) |
| unknown kinds | nothing but Open on Mac | "Wants your permission" |

- **Reading**: Capsid's session read adds, in the page, the pending requests of
  the root and of its children (the children's come from `trace-shallow`,
  which keeps `output_data.pending_input_requests`). Projected fields only:
  `requestId`, `tool_id`, `mode`, `kind`, the holder frame id, and the plain
  description fields per kind (host, path, tool and server names, language,
  the code ≤ 4 KB for `local_exec`). Never credentials, never secrets' values.
- `/api/sessions/<id>` version 2 gains
  `"permission": {"id": "<requestId>", "kind": "local_exec", "title": "Run Python code",
  "detail": "…", "code": "…" | null, "helper": true|false, "canAllow": true,
  "canDeny": true, "why": null | "…"}` or null. `helper` says a sub-agent is
  asking. `why` when `canAllow` is false: "Allowing this from your phone would
  give lasting access. Open it on your Mac."
- **Answering**: `POST /api/sessions/<id>/permission`
  `{"id": "<requestId>", "decision": "allow" | "deny"}`. Capsid re-reads; the
  same request must still be the head, of the same kind, its holder's parent
  chain must reach this session's root, and an allow must be allowed. Then
  `POST /api/frames/<holder>/resolve-input`
  `{"responses": [{"requestId", "tool_id", "approved": true|false, "action": "allow"|"deny"}]}`
  with **no `scope`** (an omitted scope is "once"). Answers
  `{"result": "allowed" | "denied" | "changed" | "unavailable", "sentence"}`;
  the daemon's `accepted`, `buffered` and `partial` count as done,
  `already_resolved` as `changed`. Counts toward the action limit; needs
  `remoteActions`.
- **Push**: a session waiting on a permission already raises a needs-you card
  and push; nothing new there.

#### Live text

`GET /api/sessions/<id>/live` → `{"working": bool, "text": "…" | null,
"activity": "Executing code" | null}`. In the page: `GET
/api/frames/<root>/streaming` → its `text` only (never `thinking` or
`tool_stdout`), the last 4,000 characters; plus the activity line in the UI's
own words, from pending requests and the last assistant message's unresolved
tool names (names only). The buffer is the current model call's and resets, so
the phone **replaces** what it shows each time, never appends. The phone polls
every 1.5 s only while a working session's screen is visible and the text is
changing (3 s after 3 polls alike, 5 s after 6, 1.5 s again on any change),
and stops when it isn't working. Costs 1 in the budget. Allowlisted GET:
`^/frames/<36>/streaming$`.

#### How the server does it (Phase 4 permissions and live)

Files: `Remote/RemotePermissions.swift` (the page's projection of the queue,
Swift's checks, the table of kinds, the decisions and the writer's body
builder), `Remote/RemoteLive.swift` (the streaming and activity reads, the
route's small state), `Remote/RemotePermissionsDemo.swift` (`--demo remote`).
The shared files only gained hooks marked `// Phase 4 permissions` and
`// Phase 4 live`.

- **Reading the queue.** A full read (the one with turns) of a root that is
  `processing` or `awaiting_user_response` also GETs
  `/frames/<root>/trace-shallow?include_messages=false`, after the messages.
  The path is built in the page from the id and checked there against
  `^/api/frames/[0-9a-f-]{36}/trace-shallow\?include_messages=false$` (Swift
  mirrors it in `PermissionPaths`); `apiGET`'s list is unchanged, and the
  card's reader still refuses both new paths. The reply is a frame with its
  children nested under `children`. It is validated whole: every frame an id
  of 36 characters, its `parent_frame_id` the id it hangs under, a known
  status, at most 2,000 frames and 16 levels, a holding frame's
  `output_data` an object (or a string holding one). A tree that doesn't
  match offers nothing, the root's own request included: an earlier request
  under a frame Capsid can't read might be the head. A failed trace, the same.
  An action's check of a plan, a question or a message still reads the frame
  alone.
- **Which frames hold requests.** Those `processing` (a live request leaves
  the frame working) or `awaiting_user_response` (a parked one), the root and
  every one under it. Each frame's `pending_input_requests` goes in one
  queue, ordered by `createdAt` (ISO text, seconds or milliseconds), then
  `requestId` (else `tool_id`), then frame id, as the UI orders them. A
  request with no readable time sorts first, so nothing behind it is offered.
  When the head is the root's own `ask` there is no `permission` (the root's
  question has its own field). A helper's `ask` as the head is projected as
  `{kind: "ask", helper: true, canAllow: false, canDeny: false, why: "A helper
  agent asked a question. Answer it on your Mac."}`, with no question text, so
  the phone shows its card with Open on Mac, and `can.message` is null with the
  same `why` while it waits.
- **What leaves the page**, one request: `requestId`, `tool_id`, `mode`,
  `kind`, the holder's frame id, `chain` (the ids from the holder up to the
  root, built from the tree), whether the daemon's own shape for the kind
  held (`network`/`host` a `target`; `host_delete` non-empty `paths` and
  `covering_roots`; `mcp_tool` `server_id`, `server_name`, `tool_name` and a
  `server_source`; a known `mode`; a readable time; an id), and a few plain
  lines: a host or path (the first of `host_delete`'s, and a count), a
  language or tool and server name, a source, a provider, a name. For
  `local_exec` the code whole, or not at all: over 4,000 characters, with a
  control character (a lone CR included), a direction override, a zero-width or
  joining character (U+200B–U+200D, U+2060, U+FEFF), a soft hyphen, a line or
  paragraph separator, U+180E, U+3164 or a variation selector (U+FE00–U+FE0F,
  U+E0100–U+E01EF) in it, a line over 160 characters or more than 60 lines, it
  isn't passed on (a tab and a line feed are fine). Swift holds the code to the
  same rule again. `toolIdShared` says another pending request anywhere in the
  queue has the head's `tool_id`. Lines
  lose control characters and are cut. Never `input`, `reason`, `warning`,
  `command`, `preview`, `credentials`, `environment`, `working_dir`, another
  request behind the head, nor any other field of a frame; the tests hold
  "SECRET" in each.
- **Swift decides** (`RemotePermission`, pure): an unknown kind or a shape
  that didn't hold is Open on Mac only. Allow: `local_exec` in python, r, bash
  or powershell, with no shared environment (`shared_env` absent or false) and
  its code shown whole; `mcp_tool` with `read_only` exactly `true` from
  `directory`, `bundled` or `antmcp`; either only when no other pending request
  has the same `tool_id` (an answer naming it may resolve that one too: "This
  needs more than one approval. Open it on your Mac."; Deny stays). Deny: those two and `network`, `host`,
  `host_delete`, `artifact_delete`, `remote_exec`, `remote_read`,
  `byoc_submit`, `byoc_kernel`, `infer_submit`, `customize_mutation`,
  `managed_endpoint_register`, `credential_access`. Open on Mac only:
  `skill_license`, `contact_email`, `credential_request`, `ssh_password`,
  `usage_checkpoint`, `set_goal`, `grant_scan`, `provider_discovery`. Both
  ids (`requestId` and `tool_id`) must be there for either. Actions off:
  neither, and `why` says so. `why` for a kind that gives lasting access is
  the spec's sentence; for the others (a shared environment, code too long to
  show, a tool that isn't read-only, an Open kind) its own (code that is odd, or
  "Too long to read on your phone. Open it on your Mac." for the line rules).
- **Answering**: the setting (403), the device's limit (429, shared with the
  other actions), a known session (404), the body (400), then one at a time
  per session: a full fresh read, the same request still the head (by `id`,
  and by `kind` when the phone sent it), the holder's `chain` ending at this
  session's root, the allow or deny allowed, then exactly one
  `POST /api/frames/<holder>/resolve-input`
  `{"responses":[{"requestId","tool_id","approved","action"}]}`, in that
  order, to the frame that holds the request (the root, or a helper): no
  `scope`, `mode`, `text` or `redirect`, ever. The body is built in the
  page from typed arguments and its shape checked there. Reply: `accepted`,
  `buffered` and `partial` → `allowed`/`denied`; `already_resolved`, "Frame
  not awaiting user response", "No pending request…", "no pending input
  requests", `live_approval_stale:…` and "Frame state changed while
  resolving input" → `changed`; anything else `unavailable`. A refused allow
  or deny writes nothing and says why.
- **Live**: the page reads the shallow frame (`working` is `processing`, and
  nothing else is read when it isn't), then, while it works,
  `/frames/<root>/streaming`, allowlisted as
  `^/api/frames/[0-9a-f-]{36}/streaming$`. Only `text` leaves, its last 4,000
  characters (by code point), null when empty; `thinking` and `tool_stdout`
  never. A shape that isn't the daemon's (`null`, or an object with string
  `text` and `thinking` and array `tool_stdout`), a 404, a 405, another 4xx
  except 401, 408 and 429, or a reply that isn't JSON switches streaming off
  for ten minutes; a 5xx or a failed fetch doesn't. The activity is worked out
  every fourth second only, from the pending requests of the root and its
  helpers and the last 12 messages (the same paths as the reads above),
  in the UI's order: "Waiting for your approval", then "Waiting on subagents"
  (every unresolved tool is `delegate` or `wait_for_notification`), "Executing
  code" (any is `bash`, `powershell`, `python` or `r`), "Running a tool" (any
  other that isn't a meta tool: `boundary`, `request_review`,
  `send_user_message`, `update_step_status`), else "Working". A call with a
  result in a later row is done; a visible user row ends the walk; tool names
  are read and never leave the page. While there is text only a pending
  request keeps its label, as in the UI. Askers at the same moment share one
  read; between activity reads only the shallow frame and the text are read. A
  read that fails answers `working` from what Capsid knows of the session.
- **`--demo remote`** has "Peak calling script" (a Python cell waits: allow
  or deny), "Reference genome download" (a network request: deny only),
  "Citation check" (a helper asks to use a read-only tool), and a live
  "Literature sweep" whose text grows 52 characters a read, then five reads of
  "Executing code", then starts over; "Plate layout" is always running code.
  Answers are the daemon's `accepted` and the request leaves the screen;
  nothing is sent.

#### Photos

- **Phone**: a camera button by the message box (and in New session):
  `<input type="file" accept="image/*">` (iOS offers camera or library). The
  phone draws it to a canvas at ≤ 3,072 px on the long side (orientation
  applied by the browser), exports JPEG at quality 0.85, and posts base64.
- **Routes**: `POST /api/sessions/<id>/photo` `{"image": "<base64>", "text": "…0–4,000", "id": "<uuid>"}`
  and `POST /api/projects/<pid>/photo` `{"image", "text", "id", "planFirst"}`.
  Body ≤ 6 MB on these two routes only, with the body timeout re-armed as
  data arrives (not a flat 3 s).
- **Capsid**: magic bytes must say JPEG, PNG or HEIC; decode with ImageIO and
  re-encode through the thumbnail API with the transform flag (orientation
  baked in, all metadata, GPS and EXIF dropped) as JPEG ≤ 3,072 px and ≤ 3 MB.
  Name it `phone-photo-YYYYMMDD-HHMMSS.jpg`. Text containing any of the UI's
  reference prefixes (`{{artifact:`, `{"type":"artifact"`,
  `{"type":"attachment"`, `{"type":"skill"`, `{"type":"session"`,
  `{"artifact_ref":`, `{"file_path":`) is refused (400), in a message's or a
  new session's text just the same (400 `{"error":"reference"}`): only a
  photo's own request may end in an attachment line.
- **Upload** in the page: `POST /api/projects/<pid>/attachments`, multipart,
  one `file` part (pid from the session's fresh read, or the route's). Gate:
  200, UUID `id` and `version_id`, the same filename and content type,
  `size_bytes` equal to what was sent; drop `file_path`, ignore
  `root_frame_id`. Then the message (or new session) as before, with
  `input_data.request` = the text, a blank line, and the attachment line
  `{"type":"attachment","id","version_id","filename","artifact_ref":"{{artifact:<vid>}}","content_type","size_bytes"}`
  in exactly that key order. Same send / queue / resume rules and results.
- The upload lands in the project's "User Uploads", which every session in the
  project can see; the phone says so once, under the button.

#### How the server does it (Phase 4 photos)

Files: `Remote/RemotePhoto.swift` (the routes, the body, the text check, the
picture, the attachment line), `Remote/RemotePhotoUpload.swift` (the in-page
upload and Swift's checks of it) and `Remote/RemotePhotos.swift` (the two
flows and the demo's). The shared files gained lines marked
`// Phase 4 photos`; `RemoteBrowser.start` is the new-session route's write
and intent recovery, taken out of `newSession` so the photo route runs the
same code.

- **The routes**: `POST /api/sessions/<id>/photo` and
  `POST /api/projects/<pid>/photo`, matched exactly like the others. 6 MiB of
  body on these two only (every other route keeps its 8 or 16 KB). Their
  body timer is re-armed as data arrives: 10 s of quiet and 120 s in all,
  instead of the flat 3 s. A photo costs 10 in the budget bucket, counts
  toward the six actions a minute and needs `remoteActions`. The project
  route is the new-session route's order: browse on (403 `browseOff`), then
  actions, the limit, the body, a project the list shows.
- **The body**: `{"image":"<base64>","text":"…0–4,000","id":"<uuid v4>"}`,
  and `"planFirst"` for a project. The base64 is the strict kind (padded, no
  whitespace); anything out of shape is 400. Text holding one of the seven
  reference prefixes, as it is or with its whitespace taken out, is 400
  `{"error":"reference"}`.
- **The picture**: the magic bytes decide (JPEG `FF D8 FF`, PNG, or HEIC with
  `ftyp` `heic`, `heix` or `mif1`), not the claimed type; anything else, or
  what ImageIO can't read, is 415 `{"error":"notAnImage"}`. The header's
  size is read first: over 24 megapixels is 413 `{"error":"tooBig"}`. Then
  `CGImageSourceCreateThumbnailAtIndex` with the transform flag and
  `FromImageAlways`, once, at 3,072 px at most and never enlarged, and drawn
  again as 8-bit sRGB whatever it was (alpha on white, CMYK or grey to RGB, and
  no profile of the source's, Display P3 or any other, written back), JPEG at
  0.85 and then 0.05 lower at a time to 0.4 until it is 3 MiB or less (below
  that the picture already drawn is drawn a quarter smaller, up to four times,
  never decoded again, else 413). No properties are written, and the JPEG's
  markers are then walked and every one but JFIF and an ICC profile (ImageIO's
  own sRGB one) dropped: ImageIO still writes an Exif segment (colour space,
  pixel size) and a Photoshop one on its own. It is read back once to check it is one image of
  the size it was drawn. The name is `phone-photo-YYYYMMDD-HHMMSS.jpg`, in
  UTC. Decoding runs off the main thread.
- **The upload** (`PhotoUploadScript`): its own in-page script, not a kind of
  `benchBuildWrite`, but the same cookie, `x-operon-csrf` and one retry after
  `csrf_stale`. It builds the one path
  `/api/projects/<pid>/attachments` from a project id
  (`^[A-Za-z0-9_-]{1,64}$`), the photo's name, `image/jpeg` and base64 whose
  length agrees with its size (3 MiB at most), makes a `Blob` and a
  `FormData` with one `file` part (a new one for the retry) and leaves
  `Content-Type` to `fetch`. 60 s. The reply passes the gate or is no upload:
  200, JSON, UUID `id` and `version_id`, the same file name and content type,
  `size_bytes` equal to what was sent. Only those five fields come back;
  `file_path` and `root_frame_id` never leave the page. Swift checks them
  again against the photo.
- **A session**: the session gate and the body as the message route has
  them; then, one at a time with its other actions, a read (nothing is
  uploaded for a session that is blocked, unreadable or has no agent or
  project), the upload to that read's project, and the message route's own
  re-read with its mode rules, agent and intent (the phone's `id`). The
  request is the text, a blank line and the attachment line, written key by
  key (`type`, `id`, `version_id`, `filename`, `artifact_ref`,
  `content_type`, `size_bytes`; never a dictionary); a photo alone is the line
  alone. The in-page writer allows that one strictly shaped line after 4,000
  characters of text only when the write says it is a photo's
  (`attachment: true`, passed by the photo flow alone), and nothing longer for
  plain text; every other message or new session refuses an attachment line and
  the seven reference prefixes there too. Answers as the
  message route: `sent`, `queued`, `resumed`, `blocked`.
- **A project**: the new-session route's list, `plan_mode` from `planFirst`
  and look for an intent whose answer was lost, with the upload between. 200
  `{"result":"started","id":…}`. Until the daemon names it, the session is
  called the text's first 50 characters, or "Photo".
- **Half done**: an upload that didn't go, or whose answer failed the gate, is
  `unavailable` with "Couldn't attach the photo from here. Send it from your
  Mac." and no message. An upload that went and a message that didn't (the
  session changed, the daemon refused or didn't answer, no session was
  found) is `unavailable` with "The photo was saved to the project, but the
  message didn't send. Open it on your Mac." Nothing is deleted. Capsid keeps
  `{intent id: the upload}` ten minutes (with a hash of the picture's bytes and
  its project): a retry of the same photo under the same intent id reuses it
  instead of saving another copy, and a 409 on that retried intent reads as
  `sent` (the first try went).
- **`--demo remote`**: the picture is still decoded and drawn again, so
  garbage is refused (415) there too; the upload's answer is made up (no web
  view), and the message or the new session answers as the demo's other
  writes do.
- **Not here**: the phone's history shows the attachment line as text until
  Phase 3's history projection learns to strip it (a "Photo" chip).
