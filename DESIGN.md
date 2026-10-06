# Bench — design

Bench is a small native Mac app for Claude Science. It shows Claude Science's
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
   time. Bench holds exactly one web view on the daemon's address, created
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
  frames at 96pt (`Bench --measure-sheets 48,72,96`).

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
- the 487 grid cells. That many glass layers costs frames. They get
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
  chips (the same `CategoryChip` as Settings), "N of 487 on" and "Choose
  specimens…" (`SettingsWindow.open(tab:)`). It is not a SwiftUI Menu: in
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
  the Dock icon brings it back. ⌘Q quits Bench but never stops the daemon.
- Menus:
  - View: Reload ⌘R, Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0, Find ⌘F,
    Show Lab Panel ⌘⇧L.
  - History: Back ⌘[, Forward ⌘].
  - Window: the standard items.
  - Settings ⌘,.
- The Dock badge is the number of sessions waiting for input, or no badge.
- URL scheme `bench://open?url=<percent-encoded daemon URL>`, and
  `bench://session?project=<id>&frame=<id>`. Both show the window and
  navigate the one web view. This is for the droplet to hand Open to Bench
  later.

## Daemon and sign-in (Web/DaemonController.swift)

- **Lost session.** Often, right after a restart, the page shows Claude
  Science's own "Sign in" card and its API reads come back 401. A fresh
  `claude-science url` code does NOT fix it (tested 2026-09-29), but pressing
  the card's Sign in button goes straight back in, with no password or
  consent (Sam). So when `apiGET` gets a 401, `WebContainer.sessionLost()`
  presses the first visible "Sign in" button, looking for it over 6 s, then
  refreshes the plan readout. With no button it falls back to the fresh code.
  At most once every ten minutes.
- **SIGTERM quits like ⌘Q** (a DispatchSource in AppDelegate), so the web
  view saves its session. The installer quits Bench with that signal.

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
- `isInspectable = true` (internal build).
- `isElementFullscreenEnabled = true`.
- Find (⌘F): a small find bar under the toolbar that uses
  `WKWebView.find(_:configuration:completionHandler:)`, with Return/⇧Return
  for next/previous and Esc to close.
- Zoom: `pageZoom` in 0.1 steps between 0.5 and 3.0, persisted.

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
  for now: a question that becomes a plan to approve updates in place. A new
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
  - **In memory only**, like Recent: nothing about sessions is written to
    disk. A put-off session stays in the activity list's Needs you and in the
    Dock badge, which count what waits, not what is on the panel.
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
  General → Corner (`panelCorner`, `PanelCorner`) says another, since 0.3.1.
  The content is aligned to that corner and grows from it; a new corner moves
  the panel at once.
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
    and the turn clock `m:ss` (monospaced digits); and "+N more" when
    several work.
- **Needs input (card, about 360×170).**
  - Left well: the reason's waiting glyph (`PlayedLoop`) at 88pt.
  - Caption in clay: `reason.sentence`.
  - Title and project.
  - Buttons: **Open** (`.glassProminent`, clay tint) and **Later** (`.glass`),
    a split pull-down `Menu(primaryAction:)`: a click on Later is "In 5
    Minutes"; its menu has In 5 Minutes, In 15 Minutes, After My Focus
    Session (only while Nidus reports a focus session), a divider and Dismiss.
- **Finished.**
  - Left well: the flask, still.
  - Caption: "Finished", then the duration and the tokens.
  - Open.
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
- **Open.** Activate Bench, show the window and navigate the web view to the
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

The Dock menu is never empty: with nothing working or waiting it says
"Nothing working right now", and while Recent is still empty (right after a
start) it lists **Latest**, the five sessions active most recently that
neither work nor wait, from the last read. The popover lists Latest the same
way since 0.3.1.

Recent is kept in memory only, so Bench still writes nothing about sessions to
disk; it lasts until Bench quits. An event is the kind, the session and its
turn (`startedAt`), so one turn's finish is one entry however often it is
read. Dismissing a card leaves its event in Recent.

The working specimen and the cards are separate settings since 0.2.0
(`showLabPanel`, `showLabCards`): the specimen can be off while questions and
errors still come. Someone who had the whole panel off before keeps the cards
off after updating. Under Reduce Motion the working specimen is a still.

### Notices (Lab/LabNotice.swift, Lab/NoticeWatchers.swift, since 0.3.0)

Cards that tell rather than ask. They queue after every session card, never
play a sound, always time out on top, and respect "Show a card". When each is
due is `NoticeRules`, pure and tested on made-up data.

- **Plan:** one card per window when the 5-hour or the all-models weekly
  limit has 10% or less left ("9% of your 5-hour limit left · Resets in 47
  minutes"), keyed by the window's reset time to the minute; and "has reset"
  only when Bench saw an announced window end in the last 10 minutes.
- **Context:** one card per session when the session open in the web view
  has used 85% of its context window, naming it.
- **Week in review:** once a new week starts (the activity graph's calendar),
  last week's sessions, messages and busiest day, read off the main thread
  at launch and just after each midnight.
- **While you focused:** see Nidus below.

What has been announced (plan windows, context sessions, the reviewed week)
is kept in Bench's settings so an update doesn't repeat it; demos keep
nothing. Settings → General → Heads-up turns each off.

### Nidus (Lab/NidusFocus.swift, since 0.3.0)

Nidus, the Solanum focus app, writes `~/Library/Application Support/Nidus/
focus.json` (`version`, `focusing`, `until`; never its goal) and posts
`local.sam.nidus.focus` on this Mac when that changes. Bench counts a focus
session as on only while the file says so, Nidus is running and `until`
hasn't passed, so a file a crash left behind means nothing. While it is on,
"Finished" cards wait (they still go to Recent, and Claude Science's own
notification for the same finish is dropped as usual); questions and errors
come at once. When it ends, the finishes come as one "While you focused"
card, and the cards put off with Later, After My Focus Session, come back if
their sessions still wait.

### Menu bar specimen (Lab/MenuBarSpecimen.swift, since 0.3.0)

Off by default. While a session works, the specimen plays in the menu bar;
while any waits, the waiting glyph and a count. Clicking it opens the
activity list in a popover. Its ink follows the menu bar's appearance (the
wallpaper's), not Bench's Ivory or Slate. Hidden, not removed, while nothing
works, so it keeps its place. Measured at about 0–2% CPU while playing.

## Scenes settings (Lab/SceneSettings.swift, Lab/SpecimenChoice.swift)

`SceneSettings.shared` holds three settings in UserDefaults:

| Setting | Key | Values | Default |
|---|---|---|---|
| `size` | `sceneSize` | small 64, medium 88, large 120 (points) | medium |
| `groups` | `sceneGroups` | `SceneGroup` raw values: the categories that are on | all six |
| `hidden` | `hiddenScenes` | names switched off one by one, inside categories that are on | none |

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
`Rotation.full` when everything is on.

The panel's well, and its width (base + size − 88), follow `size`. The
panel's and the capsule's scenes play `rotation`. Right-clicking the working
panel offers Don't Play "Name", Play Only "Name" (the specimen playing when
the menu opens, followed with `SceneBoundarySchedule`) and Choose Specimens….

The Settings **Scenes** tab (760×700) has:
- a Size segmented picker, with a live well at that size beside it, and a
  line saying a click switches a specimen on or off and a right-click plays
  only it;
- category checkboxes with counts (mixed when some are on);
- a search field, an All / On / Off filter, "N of M on", and All and None
  (None keeps one on);
- a LazyVGrid of every specimen, one section per category headed "Name N of
  M on", including categories that are off, so any specimen can be picked
  from anywhere. Each cell is 58 pt with the name under it, dimmed with no
  check when off, and a clay check when on; a click toggles it, and its
  right-click menu has Play Only, Switch On/Off, and Switch On/Off All in its
  category.
  Hovering a cell plays that specimen alone in the preview well, its name
  under the well ("Playing what's on" otherwise); leaving goes back to the
  rotation after 250 ms, so crossing between cells doesn't flash it.
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

## Title-bar readouts: context and usage remaining (Usage/)

Like Claude Code's desktop context indicator. Both read Claude Science's own
API through `WebContainer.apiGET` (Web/WebAPI.swift): a GET made inside the
page, in an isolated script world, so the page's cookie session carries it
and Bench never holds the session. Only read-only paths are allowed.

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
- Read it at launch, every 5 min while Bench is running, after each finished
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
  with a bar, "% left" and "Resets in 2 h 14 m", plus extra usage when
  enabled. Then the **Activity** section (the graph from Claude Science's launch on June 30, 2026, a column per week up to a year; 14 pt squares while it spans 30 weeks or fewer, the days before launch blank; the popover is as wide as the graph needs, 600 pt at least), and a Refresh
  button (`.glass`).
- One Usage control, not two.

## Native controls, Solanum where it counts (since 0.1.13)

Settings was drawn in Solanum (https://claude.ai/artifact/BjQZQTY4NYmLcz39pHWmQE) in 0.1.11 and
0.1.12: ivory and slate grounds, mono overlines, hairline cards, a serif heading. Sam then asked for the
menus and Settings to look like the Mac's own, even where that bends the brand, so since 0.1.13:

- General is a grouped `Form`, as System Settings is: Bench's icon, name, version and the "Unofficial,
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

## Settings (⌘,)

Two tabs: General (below) and Scenes (above).

| Setting | Default |
|---|---|
| Appearance: Match Mac, Ivory or Slate (the whole app, via `NSApp.appearance`; the page follows while its own theme is System) | Match Mac |
| Show the Lab panel | on |
| Play a sound when a session needs you | on |
| Show the Lab panel while Bench is in front | on |

## Files and ownership

```
Package.swift, DESIGN.md, Scripts/build-app.sh, Resources/Info.plist   (planner)
Sources/Bench/App/        BenchApp, Router, Theme, SharedShims, SheetCost, Demo, Settings   (planner)
Sources/Bench/Web/        daemon, web view, routing, pop-ups, browser/preview windows, downloads, find, notification bridge   (web agent)
Sources/Bench/Lab/        LabModel, LabCard, LabPanelController, LabPanelView, LabStatusCapsule   (lab agent)
Sources/Bench/Shared/     COPIES of the Science Status droplet's scenes and ScienceCore. Don't edit here:
                          change them in the droplet, then run Scripts/sync-shared.sh. Except
                          Core/CLIStatus.swift and Core/SQLiteSource.swift, which are Bench's own
                          since 0.1.2 (the database is found through the daemon's `data_dir` and
                          the live org); the sync script keeps them.
Resources/AppIcon.icon    Bench's own icon in Solanum's product family: the fig tile (#C46686), the
                          Solanum ring exactly, a flask at 9 units, one bubble escaped at the mark's
                          escaped node (152, 9.93). Drawn by code, not synced from the droplet.
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
- [ ] finished card
- [ ] find, zoom and back/forward
- [ ] the window closes and reopens without losing state
- [ ] on-screen CPU with the panel playing
