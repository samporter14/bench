# Bench — design

Bench is a small native Mac app for Claude Science. It shows Claude Science's
web UI in one native window, so there is never a Safari tab, and it plays the
Science Status lab scenes in a floating Liquid Glass panel in the bottom-right
corner while a session works. That panel is also where "needs your input"
comes from. Internal only. macOS 26+, Swift 6, SwiftUI + AppKit, no
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
- the 474 grid cells at rest. That many glass layers costs frames. They get
  a quiet `Color.primary.opacity(0.05)` fill, and a clay check when on.
- the page itself;
- text.

**Buttons:** `.glass` everywhere; `.glassProminent` with `.tint(Theme.clay)`
only for the one primary action in view.

**Colour:** clay stays the only accent: the on-state, the live dot, "needs
you", and the graph's steps. No other hues, no gradients.

## Main window

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
  case finished(SessionStatus)
  case web(WebNotification)
  case saved(URL)
}
```

- `needsInput` stays until the session stops waiting.
- `finished` lasts 6 s.
- `web` lasts until clicked or dismissed, or 8 s unless `requireInteraction`.
- `saved` lasts 5 s.

### The panel (LabPanelController + LabPanelView)

The window:

- `NSPanel` with `[.nonactivatingPanel, .borderless]`.
- `level = .floating`.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- `hidesOnDeactivate = false`, `isOpaque = false`, `backgroundColor = .clear`,
  `hasShadow = false` (the glass carries its own).

Position:

- Bottom-right of the **menu-bar screen**'s `visibleFrame`
  (`NSScreen.screens.first`), inset 20pt.
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
  - Buttons: **Open** (`.glassProminent`, clay tint) and **Later** (`.glass`).
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
    card (or hides the working panel until the next change).
- **Sound.** When a needs-input card arrives, play `NSSound(named: "Glass")`
  (a setting, on by default).
- **Open.** Activate Bench, show the window and navigate the web view to the
  session's `deepLink`, through the Router.

### Lab status capsule (toolbar)

A 18pt live scene plus a short text: "Working · 4:12", "2 need you" (in clay),
or hidden when idle. Clicking it opens the first waiting session, otherwise
the first working one.

## Scenes settings (Lab/SceneSettings.swift)

`SceneSettings.shared` holds three settings in UserDefaults:

| Setting | Key | Values | Default |
|---|---|---|---|
| `size` | `sceneSize` | small 64, medium 88, large 120 (points) | medium |
| `groups` | `sceneGroups` | `SceneGroup` raw values | all six |
| `hidden` | `hiddenScenes` | scene names | none |

`rotation` is `Rotation(LabScenes.spread(LabScenes.catalogue.filter { in a
chosen group and not hidden }))`, or `Rotation.full` when nothing is filtered.
At least one scene always stays on: the last one can't be switched off.

The panel's well, and its width (base + size − 88), follow `size`. The
panel's and the capsule's scenes play `rotation`.

The Settings **Scenes** tab (about 760×640) has:
- a Size segmented picker, with a live well at that size beside it;
- category chips with counts, which toggle;
- a search field;
- "N of 474 on", with All and None (None keeps one on);
- a LazyVGrid of every scene. Each cell is a 56 pt still, drawn with a Canvas
  at 60% of the scene's duration, with the name under it, dimmed with no
  check when off, and a clay check when on. A click toggles it, and hovering
  plays it with `PlayedGlyph(tint:rotation: Rotation([scene]))`.

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
  enabled. Then the **Activity** section (the year graph), and a Refresh
  button (`.glass`).
- One Usage control, not two.

## Settings (⌘,)

Two tabs: General (below) and Scenes (above).

| Setting | Default |
|---|---|
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
                          change them in the droplet, then run Scripts/sync-shared.sh.
Resources/AppIcon.icon    a copy of the droplet's icon (synced by the same script)
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
