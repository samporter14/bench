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
- **Clay for words is clay-text** (since 0.9.0; `Theme.clayText`). The fill
  `#D97757` is about 3:1 on ivory, too faint for small text. Words drawn in
  clay (a card's heading "Asked you a question", "6 need you", a low "% left",
  "Approved ✓", a problem's sentence) use Solanum's clay-text, `#9C4221` on
  light grounds (6.2:1 on ivory, 5.6:1 on the scenes' ivory) and `#E4927A` on
  dark (7.6:1 on slate). It is one
  dynamic colour, so it follows the appearance it is drawn in: the Ivory and
  Slate setting (the app's appearance) and the Specimens tab's own light/dark
  switch (its window's) both reach it with nothing passed down. Fills, rings,
  bars, graph steps, switches, the prominent buttons' tint, the live dot and
  glyphs that only mark something (a warning triangle, a favourite's star, a
  choice's radio) stay `Theme.clay`. A test (`ClayTextTests`) lists every
  line that colours something with the fill through `foregroundStyle`, so a new
  one is a decision.
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
  about five times the Droppy pill (the working face and the cards that tell
  you something; a card that asks has a 24pt status glyph in its header
  instead, since 0.9.3). Measured cost is under 6 ms per second of
  frames at 96pt (`Capsid --measure-sheets 48,72,96`). The working rotation
  draws and plays a second of frames at a time, never a whole scene (since
  0.9.3; Efficiency, Shared changes), at 30 frames a second unless a view is
  given another (`PlayedGlyph(fps:)`).

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
you", and the graph's steps. No other hues, no gradients. Its words are
clay-text (Look).

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
  - **Update** (since 0.9.7, only while an update is on offer; see Update
    check);
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
  - File: Open Session… ⌘⇧O (Quick Open, below), Next Waiting Session ⌥⌘↓
    (since 0.9.0, below), Close Other Tabs ⌥⌘W and Close All Tabs (artifact
    tabs, below).
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
    `[data-testid="right-tab-strip"] [data-tab-id]`. The script says why it pressed nothing (`reason`), so a
    page with no tab open (no strip) is told from a strip that is wrong (several, no toolbar, a tab with no
    close button, no single shown tab): the second is recorded for Diagnostics' "Last problem", the first is
    not. Diagnostics also looks at the strip with the same reader (Diagnostics, below).
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
  later. A link that arrives while Capsid is starting wins over reopening the
  session you were in (Reopen where you were).

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
- **Reconnecting (Web/StartRetry.swift, since 0.9.6).** A failure that may
  pass by itself is retried on its own: `status` failing or timing out, a
  daemon that didn't come up in 20 s, no sign-in code, and a main frame that
  can't connect or times out. The overlay keeps Try again and adds "Capsid
  reconnects by itself as soon as Claude Science answers." Waits: 5, 10, 20,
  40 s, then a minute for 15 tries, then five minutes; Try again and a ready
  page start them over. A try asks `status` with nothing changing on screen,
  and only a daemon that answers "running" gets "Starting…" and the sign-in
  (which reopens the remembered session as usual). **A try never runs
  `serve`**: during an update `status` can say "not running" while the new
  daemon waits for the port (2026-10-21 log: "port 8765 is busy (predecessor
  still shutting down?)"), so starting one stays with Try again and launch.
  Not retried: a missing tool, a failed launch, a refused sign-in, or a page
  that answered with an error. Why: on 2026-10-21 the 0.1.69 cold start, on a
  Mac busy with Simulator tests, froze the daemon for 60 and 65 s; Capsid
  showed "isn't responding" and then a Try again failed after `status`'s 5 s.
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
- **The launch address** is a link that came with the launch (`bench://`), else
  the session you were in, else the home page (Reopen where you were, below).
  The sign-in code is added to whichever it is.

### Reopen where you were (Web/LastSession.swift, since 0.9.0)

Capsid used to open Claude Science's home page at every launch. It now opens
the session that was on screen when Capsid quit, or crashed.

- **Does the page restore the last session itself? Not known.** Nothing in
  Capsid's code or in this document says Claude Science sends `/` back to the
  last session, and Capsid never gave it the chance to: every launch loads `/`
  (or a link's address) with a fresh sign-in code, in a web view that keeps
  nothing but cookies and `localStorage` (`WKWebsiteDataStore.default()`; no
  `interactionState`). Claude Science can't be run to look from here. Reopening
  does not rely on the page: if the page did its own, loading the session's
  address would only agree with it. A reload (⌘R, or the one after the web
  content process ends) reloads the address on screen, so it never lost the
  place.
- **What is kept.** One `UserDefaults` value, `lastSession`
  (`SettingsKey.lastSession`): `<project id>/<session id>`, the two opaque ids of
  the exact `/projects/<p>/frames/<id>` address the main web view shows. Never a
  title, a name or a URL. Like the Results folders (project ids, never names),
  it is a setting-sized value, so README's "saves nothing but its own settings"
  stands. It is the one thing about a session on disk: the sentences that say
  Capsid writes nothing about sessions (reminders, Recent, Quick Open,
  notifications) mean titles, states and times, and say so. It is read back
  only if it still has that shape (a project id as the database's, a full
  36-character session id).
- **Following the user.** `WebContainer` watches the web view's address
  (`webView.publisher(for: \.url)`) and `LastSession.note` sorts it with
  `NidusTaskSelection.route(url:daemonPort:)`, the one definition of an exact
  session route (the daemon's origin, `projects/<id>/frames/<id>`, nothing
  after). A session's page is kept (a `?nonce=` on the address changes
  nothing); any other page of Claude Science (home, a project's overview,
  anything else) forgets it, so quitting from the home page launches at the
  home page. A page that isn't the daemon's (blank, a preview, a link that went
  to another window) says nothing about where the user is and changes nothing.
  It writes only a change, since every write is a
  `UserDefaults.didChangeNotification` that Nidus's task file answers. In a
  demo it neither writes nor reads: a demo shares the real app's defaults and
  has no daemon.
- **At launch (`WebContainer.signIn`).** With the daemon up, the destination
  is chosen by `LastSession.launchDestination`: a `bench://` link wins, whether
  it came before the port was known or while this is being decided (a link
  that arrives while the sign-in is under way waits in `pendingURL`; before
  0.8.1 it loaded at once and the sign-in's own load then replaced it). A link
  that is not a page of Claude Science's opens the home page, as before, never
  the remembered session. With no link, it is the remembered session if the
  database still has it, else the home page. "Has it" is `fetchSession`: a
  root session, not hidden, not a sub-agent, upload or concierge, **in that
  project**, read off the main actor with a 2 s limit (a locked database sends
  the launch to the home page, not a wait). The look runs while the sign-in
  code is fetched, so a launch waits for neither. A database that can't be read, or doesn't have the
  session (deleted, or another org's), opens the home page, and the home page
  then forgets the old route.
- **Signing in is not fought.** The sign-in code goes onto the chosen address as
  it does for a link: the daemon accepts it on any page, a signed-out browser
  sees the page's one Sign in button, which lands on the same page, and a 401
  reloads the same address with a new code (above). So a restored session
  behind a Sign in card is still that session once signed in.
- **No Settings switch.** Settings' switches are for what makes noise, shares
  or sends something (the panel, sounds, Mac notifications, the update check,
  the phone, Nidus). This changes which page a launch shows, as a browser's
  "continue where you left off", and a click on Claude Science's home undoes it
  for the next launch. It is on, and documented here; a switch can be added if
  it turns out to be unwanted.
- **Not checked.** The wiring in `WebContainer` (the address watch, the
  `signIn` ordering, `signingIn`) has no unit test, since `WebContainer` is the
  real web view; its decisions are `LastSession`'s and are tested. See the
  checklist.

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
  - **`apiGET`'s limits (since 0.9.3).** One 15 s deadline, kept in the page,
    covers the headers and the body together (before, `apiGET` had no
    deadline of its own). The body is streamed and stopped at 8 MiB, and a
    `Content-Length` over that is refused unread.
    Every read has a nonce and its own `AbortController` in the script world:
    when the task that asked is cancelled (the page moved to another session,
    a window closed) Capsid aborts that read alone and the other reads in the
    page are not touched. New `WebAPIError` cases: `timedOut` and
    `responseTooLarge`; a cancelled read ends as a `CancellationError`, and
    the compatibility probes say "no answer in time" and "the answer exceeded
    the read limit". The allowed paths and the 401 handling are as they were.
  - **Keep's reads (since 1.0)** are not `apiGET`'s. The artifact reader (`Remote/ArtifactReader.swift`)
    makes three more GETs from typed arguments, each an exact shape, checked in the page and again in Swift,
    `no-store`, projected in the page, and read through a capped stream (1 or 2 MB):
    `/api/artifacts/<36>/versions`, `/api/artifacts/versions/<36>?include_metadata=true` and
    `/api/artifacts/versions/<36>/lineage?slim=1` (ids exactly `[0-9a-f-]{36}`; the fields kept are in Capsid
    on your phone → Artifacts, Keep's reads). `apiGET`'s own `/api/artifacts/versions/` is now exactly the
    plan file, `/artifacts/versions/<id>` and nothing after the id (until 1.0 it was a prefix, which would
    have passed the last two unprojected into Swift; the 1.0 spikes' S2 found it).
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
    their own writer (Capsid on your phone → Actions); `apiPOST` is unchanged,
    and unaffected by the limits above: no deadline, and no retry but the one
    after a stale CSRF token, so a write is never sent twice blindly.
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
- **While the daemon is down** (since 0.9.3). There is no write-ahead log for
  the watcher to open, so it watches the log's folder for the log to be
  created, and picks it up at once when it is. As a back-up (the folder
  missing, an event missed) it looks again after 2 s, then 4, 8, 16, 32 and
  every 60 s, where it used to look every 2 s for as long as the daemon was
  down (1800 looks an hour; now about 64). A log that opens starts the
  sequence over for the next time it goes. What the watcher reports, and when,
  is unchanged while the log exists, and `isWatching` still means only "the log
  is open", so the model's fallback timer above is unchanged too. The code is
  the droplet's (`ScienceCore/DatabaseWatcher.swift`); `DatabaseWatcherTests`
  fires the retries by hand and uses real temporary folders.
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
    disk, due times included (the one thing kept is the two ids of the
    session you were in: Reopen where you were). A put-off session stays in
    the activity list's Needs you, under its Later group, and in the Dock
    badge, which count what waits, not what is on the panel.
- `failed` ("Stopped with an error", Open and Dismiss, with the sound) comes
  when a working or waiting session ends in an error, and stays until it is
  opened, dismissed, or the session runs again. Since 0.9.0 it also says why
  when Claude Science does: the first line of the reason under the project,
  and **Copy** for all of it (Why it stopped, on the failure card). Without
  a reason, or with the setting for plans, questions and requests off, it
  is Open and Dismiss as before.
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
- **Controls look live.** The panel is never key (`canBecomeKey` is false, or
  it would take the keyboard from whatever you type in), and SwiftUI draws a
  prominent or glass button dimmed in a window that is not: labels pale, as if
  disabled. So the content is told it appears active
  (`.environment(\.appearsActive, true)` on `LabPanelView`, held by
  `PanelActiveControlsTests`). Checked 2026-10-20 by quiet captures with and
  without it: without, Reply and Open read as disabled; with it, the active
  look (`.key` and `.active` draw the same). What a capture cannot show is
  the clay tint of `.glassProminent`: a window capture draws glass flat grey,
  and a red-tinted glass button comes out the same grey as the clay one, so
  Reply and Approve look grey in every demo capture. The tint is judged on a
  real screen (a card, with Capsid in the background), and a custom clay
  capsule is the fallback if it is grey there too.
- `colorSpace = .sRGB`. The scenes' frames are drawn in sRGB (`ImageRenderer`).
  In a window of the display's own colour space (Display P3 on a Mac's screen)
  Core Animation converts every frame of a scene on the main thread as the
  scene is committed, about half of what the panel costs to play (Efficiency,
  below). In an sRGB window it takes the frames as they are and the window
  server converts the window. The colours on screen are the same: a P3 and an
  sRGB window showing the same swatches through a keyframed `contents`
  animation captured pixel for pixel alike, and the panel's caption, title,
  clock line and glass edges captured identically before and after. Only the
  panel: the main window's web view is not ours to restyle.

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

- Whenever something works or a card is up, and the panel isn't turned off,
  and Capsid isn't quiet for a presentation (Quiet while presenting).
- Otherwise it fades out and is ordered out: no window at all while idle.

Layout (SwiftUI inside `GlassEffectContainer`, one glass shape
`.glassEffect(.regular, in: .rect(cornerRadius: 26))`, 16pt padding):

Two families of face (since 0.9.3). The working face and the cards that tell
you something (Finished, a page notification, a notice, Saved) keep the scene
well at the left, with the text in a column beside it. The cards that ask you
something (needs input, stopped with an error) have no well: a compact
status header, then the title, the project and the content across the card's
whole 360 pt width, which is 328 pt of text inside the 16pt padding, where
the column beside an 88 pt well had 226. A question, a plan or an error
reads at that width. The width of the cards that ask does not follow the
Size setting; the width of the others does (Scenes settings).

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
  - While nobody is at the Mac (Holding still, below) the well holds a still,
    the caption line names that specimen, and the turn clock moves a minute
    at a time.
- **Needs input (card, 360 wide, no well since 0.9.3).** Until 0.9.3 it was
  about 360×170, with the reason's waiting glyph in an 88 pt well at the left.
  - Status header (`actionCard`): the reason's waiting glyph (`PlayedLoop`)
    at 24 pt, hidden from VoiceOver, beside the caption in clay-text,
    `reason.sentence` ("1 of 3" at its end while cards are stacked).
  - Under it the title and the project, then the plan or question, then the
    buttons, each across the card's full width.
  - Buttons: **Open** (`.glassProminent`, clay tint) and **Later** (`.glass`),
    a split pull-down `Menu(primaryAction:)`: a click on Later is "In 5
    Minutes"; its menu has In 5 Minutes, In 15 Minutes, After My Focus
    Session (only while Nidus reports a focus session), a divider and Dismiss.
  - A plan to approve (since 0.3.4, with the setting on): under the project,
    the plan's `task_summary` (12.5 pt, 3 lines since 0.9.3 and 2 before,
    truncated) and "5 steps ·
    feasibility: high" in secondary (its tooltip: "Claude's own estimate of
    how feasible the plan is"); "Loading the plan…" while it is read.
    Under those, when the plan has step titles, a small chevron
    button **Show steps** / **Hide steps** (11 pt, secondary), closed by
    default. Open, it lists the first 8 titles as a numbered list (11 pt, one
    line each, cut at the end), then "and N more…" when there are more.
    When it is ready the buttons are **Approve** (`.glassProminent`, clay,
    the primary action), **Open** (`.glass`) and Later. Pressed, Approve is a
    small spinner; approved, the row reads "Approved ✓" in clay-text. The card
    keeps its width and grows taller; the panel measures its content, so the
    window follows. See Approving a plan from its card. Beside Show steps,
    **Request changes…** (since 0.7.0).
  - Any other wait (since 0.7.0, with the same setting): the question and
    Reply, or a permission request with Allow Once, Review or Deny. See
    Answering from the card. The question, and a permission request's title,
    take the same three lines as a plan's summary (two before 0.9.3).
- **Stopped with an error (card, 360 wide, no well since 0.9.3).**
  - Status header: the warning triangle (19 pt, in clay text, in a 24 pt box
    hidden from VoiceOver) beside the caption in clay-text, "Stopped with an
    error"; then the title and the project, across the card's full width.
  - Since 0.9.0, once the reason has been read: under the project, its first
    line (12 pt, plain text, up to two lines since 0.9.3 and one before, cut
    at the end of the second; its tooltip shows the first 600 characters).
    The buttons are **Open**
    (`.glassProminent`, clay tint), **Dismiss** (`.glass`) and, with a reason,
    **Copy** (`.glass`), which puts all of it on the pasteboard and says
    "Copied" for 1.5 s. The card keeps its width and grows by the lines the
    reason takes. With no reason it is the card it always was. See Why it
    stopped.
- **Finished.**
  - Left well: the flask, still (the well stays on the cards that tell you
    something, 0.9.3).
  - Caption: "Finished", then the duration and the tokens ("12m · 1.2M
    tokens"; times are written one way, below).
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
    VoiceOver is offered the same as a named **Dismiss** action beside Open
    (since 0.9.3), so it needs no hover.
- **Sound.** When a needs-input card arrives, play `NSSound(named: "Glass")`
  (a setting, on by default).
- **Open.** Activate Capsid, show the window and navigate the web view to the
  session's `deepLink`, through the Router.

### Lab status capsule (toolbar)

A 18pt live scene plus a short text: "Working · 4:12", "2 need you" (in clay-text),
"Recent" once something has happened, or a quiet "Activity" before then. It is
always in the toolbar since 0.3.1 (it used to vanish when nothing worked or
waited), so the list stays one click away. Clicking it opens the activity
list.

### Activity list (Lab/ActivityList.swift, Lab/ActivityMenu.swift, since 0.2.0)

Every session at once, in a popover under the status capsule and in the Dock
icon's menu: **Needs you** (waiting sessions with their reason, failures not
yet dismissed, and what is put off with Later), **Working** (with each turn's
clock) and **Recent** (the last 30 events: questions, plans, errors, finishes
and saved downloads, in the past tense, with when). Each row opens its session
in the one web view and closes the list; a saved file shows in Finder. Both
read `LabModel`, so nothing else polls.

**Needs you's groups and order** (`NeedsYou`, since 0.9.0). One pure type
decides them, for the popover, the Dock menu and Next Waiting Session, so they
cannot disagree about which sessions need you or which comes first:

1. **What asks now** (`asks`): waiting sessions whose card is not put off,
   **the one that has waited longest first**. A waiting session stops writing
   when it parks, so its last write (`updatedAt`, which the lists sort and date
   by) is when it began to wait: ascending, then by id. This is the order the
   panel's card queue comes in (oldest card on top) and the order Next Waiting
   Session walks, top to bottom. `LabModel.waiting` itself is unchanged, the
   most recently active first (the Dock badge, the capsule's glyph, the phone
   and the reply window read it as it is); only these lists reorder it.
2. **Stopped with an error** (`failed`): failures not yet dismissed, in the
   order the cards queue them.
3. **Later** (`later`), under a small "Later" title at the bottom of Needs
   you: the sessions put off with Later (below), the reminder due soonest first,
   the one that waits for the focus session last, a tie by the longer wait. It
   is a group of Needs you and not a section of its own because these sessions
   are still counted as needing you (the capsule's "N need you", the Dock
   badge). In the Dock menu it is a **Later** header after Needs you.

A session put off with Later keeps its row in Needs you, quieter:

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

**A put-off session counts as waiting once its reminder is due.** There is no
date to compare: a reminder that comes due (or is brought forward with Show
Now, or whose focus session ends) leaves `snoozed` in the same step that brings
its card back, so it is an ask again, with its wait counted from when it began.
Cancel Reminder does the same without the card. Before then it is under Later
and Next Waiting Session passes over it.

**Size** (`ActivitySizing`, since 0.9.0). The popover is as tall as its rows,
up to the space from the window's toolbar to the bottom of the screen's usable
area (`visibleFrame`) and no taller than that screen, but never under 320 pt
(it was a fixed 480 pt, which cut Working's rows in half once six sessions
waited). It scrolls only past that. Long lists keep what matters in view: Needs
you shows the rows that fit once Working's (up to three) and the titles have
their room, at least four, and the rest wait behind a quiet **N more** row that
shows them in place when pressed (cut from the end, so Later goes first, then
failures, then the most recent ask). Row heights are the drawn ones (52 pt a
row, 30 pt a title), so the count is an estimate that errs toward showing
fewer. With a 900 pt list and two working, ten or more Needs-you rows show
whole.

**Next Waiting Session** has a hint in the popover: at the end of Needs you's
title, "Next Waiting Session ⌥⌘↓", a plain button that does what the menu item
does (below). It shows while anything asks.

**Acting from a row** (since 0.9.0). On hover, or when keyboard focus is on
it, a Needs-you row offers what its card would, at its right end:

- a question: **Reply…**, which opens the reply window as the card's Reply does
  (the list closes first, as the window opens beside the panel);
- a plan, once it is read: **Approve** and **Request changes…**;
- a permission request: **Allow Once** or **Review…** (code to run) with
  **Deny**, **Deny** alone where the Mac's table offers nothing but a plain no,
  and nothing for a request it can't answer (an email, a helper's question),
  exactly the card's rules (`RemotePermission.decideOnMac`).

They stack in a small column at the row's right end, and the row's lines give
way to it (cut at their ends) rather than going under it. Only the answer the
card makes its primary (Reply, Approve, Review, Allow Once) is in the clay;
Deny and Request changes… are plain, alone or beside it. They are also in the
row's context menu and offered to VoiceOver as its actions, so they don't need a
hover. The list's content says it appears active
(`.environment(\.appearsActive, true)`, as the panel's does): a popover nothing has
made key would draw the clay button dimmed. Allow
Once, Deny and Approve leave the list open, so the row shows how the send goes:
a spinner while it is sent, then, as the card does, a failed or changed one says why
in a line under the project (clay-text), with its buttons still there to try
again. "Approved ✓" stays for a moment, as on the card (`PlanApprover` holds the
card for it). A request or question that went has no such moment: its card goes
with the send (`settleCard`), so its row turns plain until the next read takes the
session off the list.

- **Reuse, not a copy.** What a card offers is decided in one place,
  `CardOffer.of` (Lab/CardActions.swift), from the states the card reads
  (the plan's `PlanCardState`, the question's `QuestionCardState`, where each
  reply stands). The card (`LabPanelView`) and the rows (`ActivityList`) both draw
  from it and both call `CardActions.perform`, which is the card's own core:
  `PlanApprover.approve`, `QuestionReplier.decide`, `ReplyWindowController.show`.
  Neither view sends anything itself. `CardAction` carries the titles and
  tooltips; a row says "Reply…" and "Review…" where the card says "Reply" and
  "Review", since they open a window.
- **The same gates.** The offer comes from states that exist only while the card
  would show them: "Show a card" and "Show plans, questions and requests on the
  card" on, the page up, no demo. With either off no state is read and the
  row only opens the session, as before. A row acts while **its card is in the
  queue**: a session put off with Later or dismissed has no card, so no state,
  and its row only opens it (the Later rows keep Show Now and Cancel Reminder).
  Failures keep their one action, Open.
- **Reading a card.** `QuestionReplier` and `PlanApprover` read only the card on
  top as it comes. A row's card is read when the list opens (each shown ask) or
  when the pointer or focus comes to it, once (`prepare`, which `PlanApprover`
  gained for this, sharing `sync`'s load and its 15 s retry), never when the
  settings are off. "Loading…" has no row text: the buttons appear when the
  state does.
- A demo can't hover: `--demo toolbar --open-activity --hover-row "<title>"`
  shows that row's actions as if the pointer were on it (and leaves the plan
  out of Later, and adds a session asking to use a read-only tool). Answering
  sends nothing anywhere.

The Dock menu is never empty: with nothing working or waiting it says
"Nothing working right now", and while Recent is still empty (right after a
start) it lists **Latest**, the five sessions active most recently that
neither work nor wait, from the last read. The popover lists Latest the same
way since 0.3.1. Latest is published again when anything it shows of a session
changes (its title, project, state or link, `drawsTheSame`, as for Working),
not only when the sessions or their order do (since 0.9.3): a session renamed in
place used to keep its old name in the Dock menu until another session moved. A
read that moves only a session's tokens or its last write publishes nothing. It starts with **Next Waiting Session** (⌥⌘↓, dim when
nothing asks) and a separator, then the sessions in the popover's order:
Needs you, Later, Working, Recent. Below a divider it ends with **Quiet While
Presenting** (Quiet while presenting); `applicationDockMenu` adds it, so the
list is the same whatever the switch says. The panel's "+N more" pops up the
same menu.

Recent is kept in memory only, so Capsid still writes no title, state or time
of a session to disk (the one thing kept is the two ids of the session you
were in: Reopen where you were); it lasts until Capsid quits. An event is the
kind, the session and its turn (`startedAt`), so one turn's finish is one
entry however often it is read. Dismissing a card leaves its event in Recent.

The working specimen and the cards are separate settings since 0.2.0
(`showLabPanel`, `showLabCards`): the specimen can be off while questions and
errors still come. Someone who had the whole panel off before keeps the cards
off after updating. Under Reduce Motion the working specimen is a still.

### Next Waiting Session (Lab/NextWaiting.swift, since 0.9.0)

**File → Next Waiting Session**, ⌥⌘↓, also the first item of the Dock menu and
a button in the activity list's Needs you title. It opens the session that has
waited longest among those that need you, and on the next press the one after
it, and round again. Today, with several waiting, it is open the list, click,
come back, repeat.

- **Which sessions.** `NeedsYou.asks`: the waiting sessions whose card is not
  put off, in the list's order, the longest wait first. A session put off with
  Later counts again once its reminder is due (see the Activity list), not
  before. **Failures are not in it**: it is about what waits for you, which
  is what the capsule's "N need you" and the Dock badge count, and a failure
  has its card, its Dock-menu row and its notification.
- **The cycle.** `NextWaiting.pick`, pure: no press yet, the first; else the one
  after the one the last press opened, and the first again after the last.
  Opening a session doesn't take it out of what waits, so stepping past it is
  what makes repeated presses go round. If the one opened last has since been
  answered and left, the next press goes on from where it stood in the order
  (the first that waited less long), not back to the top. One session
  waiting is its own next. It opens as every row does (`LabModel.open`, which
  clears its cards and reminder). Kept in memory only.
- **Dim when nothing asks** (the File item and the Dock item), and in a demo,
  which has no main window.
- **Why ⌥⌘↓.** Not a letter: the page takes common ones (⌘⇧O and its like, which
  is why Quick Open is caught ahead of it) and ⌘⇧N is "new window" everywhere.
  Capsid binds nothing on the arrows (the menus' ⌘⇧O, ⌘⇧R, ⌘⇧L, ⌥⌘W, ⌘R, ⌘F,
  ⌘+ ⌘− ⌘0, ⌘[ ⌘] are held to one use each by `NextWaitingWiringTests`; the
  reply window's ⌘1…⌘9 and ⌘↩ are another window's). A text field has no
  binding for ⌥⌘↓, so it is safe in the composer, and the system has none
  (Mission Control takes ⌃, Safari's tabs ⌥⌘←/→). Down is "the next one down
  the list".
- **Caught ahead of the page.** A web view is offered key equivalents before the
  menu, so a local `NSEvent` monitor (beside Quick Open's, `AppDelegate`) takes
  ⌥⌘↓ in the main window and only there: a Browser window shows other sites,
  which may use it themselves, and keeps it. Matched by key code (125) and the
  four modifiers alone (`NextWaiting.isKey`; the arrow key's own `function` and
  `numericPad` flags and Caps Lock don't count). A held key does nothing
  after the first press and is not passed on while something waits; with nothing
  waiting the key goes on to the page.

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
  active), as `LabModel.sessions`, and, once a query is typed, older ones from
  the database (Older sessions, below). `LabModel.sessions` holds every state,
  where `working`, `waiting` and `latest` split them up, and like Recent it is
  in memory only: Capsid still writes no title, state or time of a session to
  disk, and nothing typed or found is kept.
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
- **Older sessions (`QuickOpenSearch`, `fetchSessionsNamed`, since 0.9.0).** The
  ~25 recent sessions answer a query at once; typing also looks in Claude
  Science's database for the sessions beyond them.
  - **When.** A query of at least two characters (all its words together)
    starts a look 250 ms after the last keystroke, off the main actor
    (`Task.detached`, the shared `SQLiteReader`). One letter would match nearly
    every title, so it only narrows the recent sessions. The first six words
    go, each cut to 64 characters, as the phone's `q` is 2–64. The same words
    again (a space typed at the end) do not search again; an emptied query
    clears what was found; closing the sheet cancels.
  - **Obsolete searches stop (since 0.9.3).** Each search owns a
    `SQLiteReadCancellation` that the cancelling of its asking task trips
    (`QuickOpenSearch.databaseRows`). A keystroke that changes the words, or
    closing the sheet, cancels the old search: if its read is still queued
    behind another it never runs and never opens a connection, and if it is
    running, SQLite's progress or busy callback stops it (the progress one
    every 10,000 steps), and the caller leaves at once rather than at the
    limit. Only the newest wanted query stays waiting behind another database
    read.
  - **The reader (`SQLiteReader`, one serial queue, since 0.9.3).** `timeout`
    counts from the moment a read is queued, not from reaching the front, so
    waiting in line and the one retry share the deadline. A request that is
    past it, or cancelled, when it reaches the front does no database work.
    A read that was cancelled stopped at its own request, so the connection
    stays: the next read, usually the search that replaced it, uses it instead
    of opening the database again. Any other failure still drops it, and the
    next read opens afresh. The read runs at the caller's quality of service
    (a Quick Open search is user-initiated): the caller waits on a semaphore,
    which hands its priority to nobody, so the block is submitted with the
    caller's QoS and `.enforceQoS`, which wins over the queue's own utility.
  - **The SQL.** Root sessions whose `frames.name` or `projects.name` contains
    every word: per word `(f.name LIKE ?N ESCAPE '\' OR p.name LIKE ?N ESCAPE
    '\')`, ANDed, the value bound with `\`, `%` and `_` escaped
    (`BrowseSQL.containsPattern`, as the phone's search), newest first by
    `(updated_at, id)`, `LIMIT` 30 (the call may ask 1 to 100). It is the poll's
    filter, `sessionFilterSQL`, so sub-agents, hidden sessions, uploads and the
    concierge stay out exactly as in Recent. It has neither the browse lists'
    `task_summary` test nor their archived-project test, which Recent doesn't
    have either: a session that shows in Recent is found here too. It reads the
    columns `fetchSession` reads, so `CompatInventory` is unchanged (its
    test runs the new read against the inventory's columns alone).
  - **Why it is cheap.** A `LIKE` that starts with `%` can't use an index, so
    the roots are looked at once, in whatever order SQLite finds cheapest: with
    an index on `updated_at` it walks newest first and stops at the limit (a
    common word is quick), else it reads each root once and keeps the newest
    few. It never reads a root's blobs or any text column but the two names.
    Measured on a made-up database of 60,000 frames (6,000 roots, one project
    per hundred): a word nothing matches took 3 ms with an index on
    `parent_frame_id`, 26 ms with only one on `updated_at`, 10 ms with none.
    Not measured on a real database. The read is interrupted at 3 s.
  - **What it can't match.** SQLite's `LIKE` folds ASCII case only and finds a
    piece of a name. Accents and widths (which `rank` also ignores) and
    letters scattered through a name (its fuzzy tier) are left to the recent
    sessions: an older session whose title has an accent is found when the
    accent is typed as stored, and one that only a fuzzy match would find is
    not found at all. Everything the database returns passes `rank`.
  - **Merging (`QuickOpen.rank(_:plus:query:)`).** The recent sessions and the
    found ones go through the one ranking above as `recent + older`, so the
    same rules apply to both: an older word-start match sits above a recent
    match inside a word. A session in both is listed once, as the recent one
    (it comes first in the list, and the ranking keeps the first of an id), so
    it keeps its live state and waiting reason; the database row has a state
    from `status` alone, as the phone's lists (`BrowseRow.status`). A tie
    stays with the recent one.
  - **In the sheet.** The recent matches show at once. While the database is
    read a small spinner sits at the end of the search field, and when the
    recent sessions have no match the empty state says "Searching…" instead of
    "No results". The found sessions rank in when they arrive. Every keystroke
    that changes the words makes the answer under way stale, and a stale
    answer is dropped; the answer in hand is kept while the next is awaited,
    since the sheet ranks it against the current query. A database that can't
    be read leaves what was found and adds nothing. The highlight does not
    move when older sessions arrive: if it was on the first row by default it
    stays on the row it was on, even if a better match now sits above it, so
    Return opens what was on screen; once you move it with ↑ ↓ it follows its
    session as before.

### Notices (Lab/LabNotice.swift, Lab/NoticeWatchers.swift, since 0.3.0)

Cards that tell rather than ask. They queue after every session card, never
play a sound, always time out on top, and respect "Show a card". When each is
due is `NoticeRules`, pure and tested on made-up data.

- **Plan:** one card per window when the 5-hour or the all-models weekly
  limit has 10% or less left ("9% of your 5-hour limit left · Resets in
  47m"), keyed by the window's reset time to the minute; and "has reset"
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
- **While you focused:** see Nidus below. **While you presented:** the same
  card, for Quiet while presenting.

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
- **Kept fresh (since 0.9.3 only as needed):** written when what it says
  changes, that is on focus, route and settings changes and when the task or
  project is renamed. A burst of focus, settings and session-snapshot
  notifications is read once the burst is over, and a snapshot that changes
  only token counts finds the same project and task and does not rewrite the
  file (it used to rewrite it at every snapshot). While a focused, eligible
  task is shared, a five-second heartbeat rewrites it so Nidus's 15 s
  freshness limit holds, and it is the only timer: with sharing off, Capsid in
  the background, another window key or a page that is no task, there is none,
  and it stops with the first of them. The file is removed when any condition
  above stops holding, the setting goes off, or Capsid quits. A crash leaves a
  file behind; Nidus ignores it because it accepts the file only when `pid` is the frontmost
  app's, `updatedAt` is at most 15 s old (or 2 s ahead), and its own
  document-names setting is on.
- **Written off the main actor (since 0.9.3).** One serial utility queue
  (`NidusTaskWriter`) encodes, writes a unique temporary file and renames it.
  Each request carries a generation: one that has been superseded is dropped
  before it does any work and again just before the rename, and a clear is
  ordered after a write already under way, so a late write cannot restore a
  file that was cleared (focus lost, the setting off). Quit waits for the
  removal; ordinary updates never wait. A current write that fails removes the
  file rather than leave an old title looking fresh.
- **Only the copy that started it touches the file.** A `--demo` copy never
  starts it, so its Settings switch and its quit leave a running Capsid's
  file alone.

### Quiet while presenting (Lab/PresentingMode.swift, App/PresentingFocusFilter.swift, since 0.8.0)

The panel and its cards are drawn by Capsid itself, so macOS's "no
notifications while sharing" does not cover them, and they name sessions and
projects. While the user presents (Keynote, a Zoom or Teams screen share, a
projector) Capsid stays out of sight, then catches up.

**Two ways in, one state.** `PresentingMode` holds `focusFilterOn` and
`manualOn`; `isQuiet` is either. With both on, quiet lasts until both are off.

- **A Focus filter** (`QuietWhilePresentingFilter`, a `SetFocusFilterIntent`).
  In System Settings → Focus → (a Focus kept for presenting) → Focus filters →
  Add Filter → Capsid, with one switch, "Keep Capsid quiet". While that Focus
  is on, Capsid is quiet. How the system runs it, from the SDK's doc comments
  (the `.swiftdoc` beside `AppIntents.swiftinterface`) and Apple's article
  "Defining your app's Focus filter":
  - `perform()` runs when the Focus turns on, with the parameters as the user
    set them, and again when it turns off, with each non-optional
    parameter's `default`. So the parameter is `quiet`, default `false`; a
    filter with no parameter could not tell on from off.
  - `suggestedFocusFilters(for:)` exists for when the suggested configuration
    differs from the one used when the Focus is turned off, which is this
    case: the filter is suggested with `quiet` already on, so adding it does
    something.
  - At launch while a Focus is already on, neither the SDK nor the article
    says the filter runs again. `static var current` is the SDK's way to
    retrieve the current Focus configuration (its error type is
    `SetFocusFilterIntentError`), so `PresentingMode.start()` reads it once;
    a throw (no filter configured) is off. A `perform()` that has already run
    is newer than that read and wins (`catchUp`).
  - SwiftPM does not extract App Intents metadata, so System Settings only
    knows the filter if `Scripts/appintents-metadata.sh` (ported from Nidus's)
    has put `Contents/Resources/Metadata.appintents` into the bundle. It runs
    from `Scripts/build-app.sh`, before signing.
- **A switch.** "Quiet While Presenting" with a checkmark, in the app menu
  (after Settings…), in the Dock menu (after the activity list) and in
  Settings → Alerts → While you present (below), for when
  the Focus filter never shows up in System Settings (a self-signed app built
  by SwiftPM can't be sure of it), or no Focus is kept for presenting. It
  stays on until turned off. It is **not saved**: a quit turns it off, so
  Capsid never comes back from a launch silent without anyone saying so. The
  Dock item says "A Focus is keeping Capsid quiet" when the Focus is why,
  and the switch is separate from it: turning the switch off does not end a
  Focus's quiet.
- **Never in a demo.** `PresentingMode.start()` is not called and refuses in
  a demo, the filter's `perform()` does nothing in one, and the menu items,
  and the Settings switch and button, are disabled.
- **In Settings** (`Lab/PresentingSettings.swift`, since 0.9.0): a section
  "While you present" on the Alerts tab, between "On the panel" and "Mac
  notifications".
  - *Quiet While Presenting*: the same switch, bound to
    `PresentingMode.shared` (`manualOn`, so the menus' checkmarks follow it).
    Its line under the title says what it does and, plainly, that it isn't
    saved ("Hides the panel and mutes sounds and notifications. Not saved: off
    again after a quit."). When a Focus is what keeps Capsid quiet the line
    says so, in the Dock item's words ("A Focus is keeping Capsid quiet right
    now. This switch is separate, and not saved."; with the switch on too, "…
    too. Not saved: off again after a quit."): `PresentingSettings.rowDetail`,
    pure and tested. Its ⓘ says what quiet covers (the phone's notifications,
    the menu bar specimen, the Dock menu and the main window are not part of
    it; finishes come as one card) and that a Focus and the switch each keep
    Capsid quiet until both are off.
  - *Quiet during a Focus*: "Add Capsid's filter to a Focus." with **Open
    Focus Settings…**, which opens
    `x-apple.systempreferences:com.apple.Focus-Settings.extension`
    (`PresentingSettings.focusSettingsURL`). That is the bundle identifier of
    the system's Focus settings extension
    (/System/Library/ExtensionKit/Extensions/FocusSettingsExtension.appex,
    `allowsXAppleSystemPreferencesURLScheme`), the shape Notifications' URL
    has; a test compares it with that Info.plist where it exists. Its ⓘ gives
    the path (Focus, the Focus used for presenting, Focus filters, Add Filter,
    Capsid, "Keep Capsid quiet") and, since the filter might not show up for a
    self-signed app, "If Capsid isn't in the list of filters, use the switch
    above instead." The URL was checked by reading that extension, never
    opened.

**While quiet:**

- **The panel** (working specimen and cards) is not shown: `LabPanelController`
  folds `isQuiet` into the rule that orders it front or out
  (`shouldShow(cards:working:preferences:active:quiet:)`). Quiet wins over
  every setting. Nothing is dropped: the sessions and the cards stay in
  `LabModel` as ever, so a session still waiting shows its card the moment
  quiet ends, through the normal logic.
- **"Finished" cards are held**, the way a Nidus focus session holds them
  (`LabModel.holdsFinishes`, `heldFinishes`; they still go to Recent), and come
  as one card when quiet ends, worded for it: caption "While you presented",
  the session's title or "3 sessions finished", "Finished" or "Title and 2
  more". The Nidus card keeps "While you focused". The two are told apart
  by `LabNotice.heldFor` (`NoticeRules.HoldReason`), and have their own id
  prefix (`presenting-held-`, `focus-held-`).
- **Both holds on at once:** the finishes stay held until neither holds, and
  the card is worded for the one that lifted last (a Nidus focus session that
  ends mid-presentation brings nothing, and nor does a presentation that ends
  mid-focus). `releaseHeldFinishes` waits while either holds, so turning off
  Settings → Alerts → Hold finishes during a presentation brings nothing
  either. A Later "After My Focus Session" reminder still comes back when its
  focus session ends, as a card the panel isn't showing yet.
- **No Mac notification:** `NotificationRules.content` returns nothing while
  `Settings.presenting` is set, for every card, so none is posted, and one
  waiting on macOS's answer when quiet begins is dropped. A needs-input card
  raised meanwhile is not notified when quiet ends (its card shows); the
  held finishes' one notification is, as for a Nidus focus session, and only
  with "When a session finishes too".
- **No sound:** `LabModel.chime()` plays nothing, for a new question, a Later
  reminder coming back or the end of a Nidus focus session.
- **Timed cards wait.** A card that times out (a page's notification, a saved
  file, a notice) does not count down while the panel isn't shown: its time
  starts when quiet ends, so it isn't lost unseen. Questions, plans and errors
  never time out.
- **The phone is not the Mac's screen.** Pushes to a paired phone
  (Capsid on your phone) are unchanged, except that a finish is held with the
  rest and its one push is worded "Finished while you presented". The
  menu bar specimen (Lab/MenuBarSpecimen.swift) keeps its glyph and its count,
  which name nothing; the list behind a click on it, the Dock menu and the
  main window are the user's own doing and are not hidden.

**Not done:** catching up with a notification for a question raised while
quiet. The Focus filter's launch read, and the filter appearing in System
Settings at all for a self-signed app, rest on the SDK's types and docs and
had not been seen working when this was written; the switch is the sure way.

### Holding still (Lab/SpecimenHold.swift, since 0.9.0)

A session can work for hours with nobody at the Mac, and the specimen plays
for all of them. After **ten minutes with no key, click or touch** it holds a
still, as `PlayedGlyphView` already does while its window is covered or the
screen sleeps, and plays again on the next input. Measured on a demo copy: a
playing panel costs about 1.2 to 2.1% of a core and 45 to 130 MB; held, 0.00%
and 23 MB (Efficiency).

- **The idle time** is `CGEventSource.secondsSinceLastEventType(
  .combinedSessionState, …)` for any input event, read through
  `MacPresence.live.secondsSinceInput` (the reader "only when away" for the
  phone already uses). The combined state counts synthetic events too, so an
  automation tool's click is input.
- **What holds.** `WorkingGlyph`, which is the panel's well, the toolbar
  capsule, the menu bar specimen, the activity list, Quick Open and the
  welcome, shows a still instead of the playing `PlayedGlyph`: the scene the
  rotation was in when the hold began, drawn once at the middle of it, as a
  covered window's specimen is. The playing view is removed, so its frames and
  their memory go with it. `SpecimenHold.heldAt` (on the rotation's clock) is
  the moment, so every copy holds the same scene, and the panel's caption line
  and its right-click menu name that scene instead of following the rotation.
  The turn clock (`TurnClockText`) ticks on the turn's own minutes instead of
  its seconds. Under Reduce Motion the specimen is already still, the flask,
  and only the clock slows.
- **When it looks.** Only while a view shows a specimen or the clock
  (`WatchesHold`, from `onAppear` to `onDisappear`), so a Capsid with nothing on
  screen runs no timer (Principle 1). Playing, it looks once a minute: going
  quiet is slow news next to ten minutes. Holding, every two seconds, so an
  input brings the specimen back within about two seconds; the look is one
  call and never per frame. A view that appears looks at once, so a session
  that begins after an hour away shows the still from its first frame.
- **Low Power Mode.** The limit is two minutes (`lowPowerIdleLimit`), never
  longer than the limit otherwise in force, and a change of power state
  (`NSProcessInfoPowerStateDidChange`) looks at once. A lower frame rate was
  considered and left: the measured saving is about 40% of the commit cost,
  and a hold saves all of it (Efficiency, Shared changes). Since 0.9.3 the
  Shared player takes a rate per view (`PlayedGlyph(fps:)`, default 30; a
  chunk is a second of frames at that rate), so 15 fps no longer needs a
  Capsid-owned player; Capsid does not use it yet, because no run of a view
  playing at 15 has been measured here. So Low Power Mode shortens the wait
  instead.
- **A hidden default**, not a setting and not in Settings:
  `specimenIdleSeconds`, a number of seconds above zero, replaces the ten
  minutes (anything else is ignored). It is for trying the rule without waiting:
  `open -g -n Capsid.app --args --demo working -showLabPanel YES
  -panelWhileFront YES --quiet -specimenIdleSeconds 20`. A command-line default
  is never saved.
- **Not held.** The waiting glyph on a card (`PlayedLoop`) draws its frames
  once and repeats them with no work from Capsid: a demo card measured 0.00%
  CPU. Nothing is saved by holding it.
- **Demo and tests.** A demo holds like the app does (that is how it was
  checked); the rules are tested with an injected idle reader, clock, power
  state and wait (`SpecimenHoldTests`), never the real Mac or a real sleep.

### Menu bar specimen (Lab/MenuBarSpecimen.swift, since 0.3.0)

Off by default. While a session works, the specimen plays in the menu bar;
while any waits, the waiting glyph and a count. Clicking it opens the
activity list in a popover. Its ink follows the menu bar's appearance (the
wallpaper's), not Capsid's Ivory or Slate. Hidden, not removed, while nothing
works, so it keeps its place. Measured at about 0–2% CPU while playing. It
shows the glyph and a count and no names, so Quiet while presenting leaves it.
It holds still with the rest (Holding still).

### Mac notifications (since 0.3.3)

A notification in Notification Center as well as the card, for the moments
the card is for. **Opt-in**, off by default, and explained where it is
turned on: what it does, that macOS asks once, that it names the session
and project unless told not to, and where to turn it off.

**Settings → Alerts → Mac notifications**, right after "When a session
needs you" (`MacNotificationsSection`, in Lab/MacNotifications.swift):

- **Also send a Mac notification.** Off. Its line says it comes as well as
  the card, so you see it in full screen or with the panel off; its ⓘ adds
  that macOS asks permission the first time, that notifications name the
  session and its project unless names are off, and how to stop them (turn
  the switch off, or Capsid off in System Settings → Notifications). (Until
  0.3.6 it also said "on your iPhone": macOS doesn't send a Mac's
  notifications to an iPhone, only the other way, so that went.) Turning it
  on asks macOS for alert and sound at once. If
  the answer is no, the switch stays on and the Permission row says why.
- **When a session finishes too.** Off. Without it, notifications come only
  when a session needs you or stops with an error.
- **Show session and project names.** On. Off, they read "A session needs
  you", "A session stopped with an error" and "A session finished", with
  nothing of the session's or project's in any field. Its line says "Off,
  they read "A session needs you", with no names and no answers."; its ⓘ
  has the three sentences and that, on, a question's notification also
  offers its answers.
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
- There is no footer any more (since 0.9.0): what it said, that names are
  shown unless turned off and that notifications stop by switching the first
  one off or by turning Capsid off in System Settings → Notifications, is in
  the first switch's ⓘ.

**What goes out.** `NotificationRules.content(for:settings:)` is pure and
decides everything: nothing unless the setting is on and macOS allows it.
The poster, `MacNotifications`, is thin: it speaks to the system only through
`SystemCenter`, which tests replace with a fake.

| Card | Title | Body |
|---|---|---|
| Needs input (a Later reminder coming back too) | the session's title | the reason sentence (`WaitingReason.sentence`), " · ", the project |
| Failed | the session's title | "Stopped with an error · " and the project |
| Finished, only with "When a session finishes too" | the session's title | "Finished · " and the project |

- **Never** for a page's own notification (`LabCard.web`), a saved file or
  a notice (but for the one below); on the first read after launch (as `chime` is not played);
  in a `--demo` mode; or in tests.
- **While Capsid is quiet for a presentation** (Quiet while presenting),
  nothing is sent at all; see that section for what comes after.
- **A finish held for a Nidus focus session** is not sent then: its card
  waits, so does its notification. When the session ends, what finished
  comes as one notification, as its "While you focused" card does, and only
  with "When a session finishes too" on: the one session's title and
  "While you focused · Finished", or "3 sessions finished" and the first
  title and "and 2 more". With names off, "A session finished while you
  focused", or "Sessions finished while you focused". A click opens the
  session when there is one, else the window. No other notice is sent.
- **Never the reason.** A failure's notification stays "Stopped with an
  error · " and the project. Why a session stopped is session content that
  can be read away from the card (Notification Center, a lock screen), so it
  is on the card alone (Why it stopped, on the failure card), and the phone
  doesn't get it either.
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
  `local.sam.bench` and no demo is running (`SystemCenter.live`; tests give
  `MacNotifications` a fake one). `LabModel`'s three hooks do nothing until
  `MacNotifications.start()` sets them at launch.
- **What stays on the Mac.** Capsid saves no name, state or time of a session
  (only the two ids of the one you were in, Reopen where you were), but
  macOS keeps a delivered notification in Notification Center until it is
  cleared. That is what "Show session and project names" is for; turning
  names, or notifications, off clears the ones already delivered (since
  0.3.6). A notification also
  carries the session's id and its link, opaque ids and no names, to open
  it on a click.
- **Notifications that outlive a quit.** macOS keeps a delivered
  notification through a quit or a crash, and what Capsid remembers of them
  is in memory, so a launch checks them against the sessions once, at the
  first read that can be trusted: one that worked (no read error, so not a
  failed read and not "Claude Science isn't running") and found sessions (a
  read that finds none is not believed that nothing waits, and the check
  waits for the next). Before that nothing is listed or taken back. It runs
  only with Mac notifications on and macOS allowing them, in the real app,
  and sends nothing: no new notification, no new words, no names. Its inputs
  are what Notification Center lists (`getDeliveredNotifications`): a
  notification's kind comes from its identifier, which is its card's id, and
  its session from the id it carries, and one that doesn't fit (the test
  notification, the "While you focused" notice) is left alone. The rule is
  the running app's own: `SessionStanding.holds`, which `LabModel` also asks
  of every needs-input and failure card on each read, so the two cannot
  differ.

  | Delivered notification | Taken back at the check when |
  |---|---|
  | Needs input | its session no longer waits. A session the read doesn't have (it holds the ~25 most recent) counts as no longer waiting, as it does for a card. |
  | Error | its session is not in error any more: running again, waiting, finished or not in the read. |
  | Finished | never. A finish is a record, as when its card only times out: it stays until clicked or cleared. |

  Needs-input and error notifications that stay are adopted: kept in memory
  for the rest of the run and checked by the same rule on every later read
  that can be trusted, besides their card's own withdrawal. That matters for
  an error, which has no card after a launch (the read announces no failure
  for a session it first meets failed), so nothing else would take its
  notification back when the session runs again. A plan held for its
  approval keeps its notification as it keeps its card. Clearing (names or
  notifications turned off) forgets them, and a check still waiting on macOS
  when that happens brings nothing back. A question's notification that
  stays keeps its answers: with names shown, its buttons are registered with
  macOS again from the notification's own copy of them, so the next question
  posted, which replaces the registered set, doesn't leave it without; an
  answer is still checked against the question's id and words afresh. Not
  done: a needs-input notification whose session still waits but for
  something else now (a question that became a plan) stays as it was, since
  nothing at a first read is news and the running app's re-post is not
  repeated.

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

Since 0.9.0 `prepare(_:)` reads the plan of any plan card in the queue, not only
the one on top (`sync` reads the top one as before, by the same load and the
same 15 s retry): a row of the activity list offers Approve for it (Activity
list → Acting from a row). The button is the card's: `CardActions.perform(.approve)`
calls `approve`.

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
because the longer wording was wider than the text column (226 pt at any
size of the scene well, until 0.9.3; the card's text is now 328 pt wide, and
the short wording stays); the tooltip says whose estimate it is.

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
read; the same for every other wait (Answering from the card), and a failure
card shows no reason (Why it stopped). A plan's
card also has **Request changes…** (Answering from the card → What to change
in a plan). Its line under the title is "Approve, reply or allow on the
card, and see why a session stopped." (since 0.9.0; it read "Approve a plan,
reply to a question or allow a request right on the card."); the longer
account of what each card shows and the check against the same plan, question
or request is in its ⓘ, with a paragraph on the failure card's reason.

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
  `ask` readable. The card shows the first question in three lines (two before
  0.9.3) and how it
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

**Which buttons** (`CardOffer`, Lab/CardActions.swift, since 0.9.0). What a needs-input
card offers is one pure decision, from the states it has read: the primary
button (Approve, Reply, Review, Allow Once, else Open or Open in Capsid), whether
a plain Open follows, Deny, what Later's menu carries, Request changes…, the line
for an answer on its way ("Sending…" spinner) or one sent ("Sent ✓", "Approved ✓",
"Allowed once ✓", "Denied ✓"; a card whose send went is dismissed with it, so these
show only for a moment, or while the reply window keeps the reply), and the sentence for
a send that didn't go. The card
draws it, and the activity list's rows draw the same (Activity list → Acting from a
row); both call `CardActions.perform`, which calls the replier, the approver or the
reply window as the card's buttons always did. `QuestionReplier.prepare` reads a card
that is not on top (it already did, for the reply window's Next).

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
answers. A failure card shows no reason then either.

**Demo.** `Capsid --demo card`: the made-up session's made-up question, with
Reply, and behind it a second card asking to run made-up Python, with
Review; Next steps from one to the other. `--demo plan` has Request
changes. Nothing is sent anywhere.

### Why it stopped, on the failure card (Lab/FailureReason.swift, since 0.9.0)

The failure card said "Stopped with an error" and nothing more, so you had to
open the session to find out why. Now it says the first line of the reason,
with a Copy button, when Claude Science has one.

**Where the reason lives.** Claude Science writes it. When a frame fails, the
daemon (`markFrameFailed`) sets its `status` to `failed` and keeps the rest of
its `output_data`, adding `error` (a string), `error_status` (an HTTP status,
or null), `error_kind`, `stop_reason` and `failure_ts`. Its own page shows it
under "Agent Failed": it takes `output_data.error`, drops a leading three-digit
status before a `{`, parses the rest as JSON, and shows `error.message`, else
`message`, else the text as it is, with "HTTP <error_status> · Request ID:
<request_id>" under it (and its own words for a few `error_kind`s and for 529).
Found in the 0.1.67 release's `web-dist` (the error banner's reader) and in
the strings of the `claude-science` binary (the schema of `output_data`, and
`markFrameFailed`), static files only: nothing else under `~/.claude-science`
was opened, and no daemon was called.

**Which read.** The root frame's shallow read,
`GET /api/frames/<id>?shallow=true`, the one the plan card makes: the daemon's
shallow read selects every column of the frame and only takes `_messages`,
`_system` and `_branch_meta` out of `context_data`, so `output_data` comes
whole. The database holds the same text (`frames.output_data`), but the page
gets it from the API, so Capsid does too: no new column, no new query
(CompatSchemaTests are untouched), and one read for one card.

**When.** `FailureReasoner` follows `LabModel.cards` as `PlanApprover` does.
When the card on top is a failure, it reads that session's frame once, keyed
by session id, while the card is drawn as it was. It reads nothing while
"Show plans, questions and requests on the card" or "Show a card" is off,
before the page is up, in a demo, or for a session id that isn't a full one.
A card behind another is read when it reaches the top. The read is given 5 s
and is not tried again: a failed one leaves the card as it was. A redraw or
any other change reads nothing; what was read goes when the card goes
(opened, dismissed, the session ran again, the setting turned off), and a
session that fails again is read afresh.

**The gate.** The setting that lets Capsid read what a session said, for a
card, is **Show plans, questions and requests on the card**: a plan's
summary, a question's text and a request's detail are all session content on
a card, and the reason is too (it can quote a file name or a prompt). So it
follows the same setting, on by default, with the names the card already
shows. Its line and ⓘ say so.

**What the card shows** (`FailureFrame`, `FailureReason`, `ReasonText`: pure,
tested on made-up JSON). Only for a frame whose `status` is `failed` and whose
`output_data.error` is a string with something readable in it; the answer's
`output_data` may be an object or a JSON string.
- *The message.* As Claude Science's page unwraps it: `error.message`, else
  `message`, else (beyond the page) an `error` that is a string, else the
  text as it is.
- *Plain text.* Any HTML (a proxy's error page) becomes its text: scripts,
  styles and comments go, the tags go, the common entities decode. Control
  and invisible characters (zero-width, direction marks) are dropped, line
  breaks are one kind, and a run of blank lines is one. The card draws it with
  `Text(verbatim:)`: nothing in it is markdown, HTML or a link.
- *The line.* The first line with something on it, with heading hashes, quote
  arrows, bullets, bold and code marks and `[text](link)` marks taken off,
  white space as one space, and a code fence skipped. A Python traceback
  leads with its own header, so its line is its last. Cut at 160 characters
  with an ellipsis, then by the card at the end of its second line (its one
  line before 0.9.3).
- *Copy.* The whole message as plain text (not the line, and not stripped of
  its markdown), cut at 4,000 characters, then a blank line and Claude
  Science's own detail line ("HTTP 400 · Request ID: req_…") when it has
  either. The pasteboard is injected (`Dependencies.pasteboard`): the live one
  is the general pasteboard, and tests use a private `NSPasteboard(name:)`.
- *No reason.* A frame that says nothing of why (no `error`, an empty or
  unreadable one), a read that fails or takes longer than 5 s, a session that
  is no longer `failed`: the card is as it was, with no placeholder and no
  retry.

**Privacy.** This widens Capsid's "never read content" rule by exactly a
failed frame's `status`, `output_data.error` and `error_status`, for the
card. Only those are picked (not the name, the input, the response or the
rest of the frame), kept in memory for as long as the card is up, and never
logged, saved or sent anywhere: the log says only "read" or "none". Copy puts
the text on the pasteboard only when pressed. **Not in Mac notifications,
the activity list, the Dock menu, the menu bar or on the phone**: a
notification can be read away from the card, and the others list sessions
at a glance. The failure notification stays "Stopped with an error · "
and the project, and a test holds the reason to the card.

**Diagnostics.** The reason is in the inventory (Diagnostics): a read,
`output_data.error on GET /api/frames/<session>?shallow=true`, for the
feature "The reason on a failure card" (`CompatFeature.errorCard`), checked
only when used (a probe would need a failed session on screen). An answer
to the read that isn't a frame at all (no `status`) is a breadcrumb,
`failedFrameNotUnderstood`: "a stopped session's answer has no status". A
session that gives no reason is ordinary and records nothing. The web bundle
read is of 0.1.67; `CompatInventory.checkedWith` is not moved, since that
means walking the whole inventory again.

**Demo.** `Capsid --demo failed`: a made-up API answer in the daemon's shape
(`400 {"type": "error", "error": {"message": "The example input file has no
header row, …"}, …}`, two lines long, with a made-up request id), run through
the real parser. The card shows the first line cut at its end, and Copy puts
both lines and the detail line on the pasteboard. Nothing is read.

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

The panel's well follows `size`, and so does the width of the faces that have
one: the working face (336 + size − 88) and the cards that tell you something
(Finished, a page notification, a notice, Saved: 360 + size − 88); likewise
"Not updating" and a paused session, which keep the well. Since 0.9.3 the cards
that ask (needs input, stopped with an error) have no well and stay 360 at every
size. So the family is mixed: at Small the panel is 24 pt narrower on a Finished
card than on a question, at Large 32 pt wider, and its width changes when the
queue moves from one to the other (only at the default Medium are they the
same, 360). The panel's and the capsule's scenes play `rotation`.
Right-clicking the working
panel offers Add "Name" to Favorites (or Remove), Don't Play "Name", Play Only
"Name" (the specimen playing when the menu opens, followed with
`SceneBoundarySchedule`) and Choose Specimens…; while only favourites play,
just Remove from Favorites and Choose Specimens…. The toolbar popover has an
"Only favorites" switch (off and greyed until something is starred), and
its categories grey while favourites play.

The Settings **Scenes** tab (760×776, or the screen's height when that is less:
Settings, Page sizes) has, in a header of two columns:
- on the left: the heading and what a click does (switch on or off, or,
  while only favourites play, star), a Size segmented picker, a Play picker
  ("What's on" or "Only favorites"), and under them the category checkboxes
  with counts (mixed when some are on), greyed while favourites play, in two
  columns of three since 0.9.0. The left is 420 pt wide, which holds two of
  the 200 pt checkboxes and not three; a header wider than the tab's 696 pt
  would widen the whole tab past its window, so the columns are sized to fit.
  Categories used to sit in a band of their own below the header, with a big
  empty gap where the taller preview column ended;
- on the right, the live well ("Playing what's on" or "Playing your
  favorites" under it, or, under the pointer, what the field guide says about
  that specimen), with the light/dark switch directly under the well and the
  text (name, caption, note, their lines reserved) below the switch;
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
  Canvas at 20 fps, 30 under the pointer, keeping no frames, at full strength
  with no fade, see Poster stills). The panel's
  `PlayedGlyph` pre-rendered about 1.5 s per scene (before 0.9.3; now a
  second or two of frames), and 40 cells of that cost
  about 320 MB more; live drawing costs about 11% of one core with no extra
  memory. Off screen (the lazy grid's onDisappear), or with Reduce Motion
  except under the pointer, a cell is a Canvas still at the specimen's
  **poster time** (below). With Reduce Motion that is what nearly every cell
  shows, so a still that shows nothing would be a grid of nothing.
- the ☀️/🌙 switch under the preview well (above the preview's text after
  0.8.0; it used to float below the text's reserved lines) sets the WHOLE tab
  light or dark
  (`.preferredColorScheme` on the tab, which sets its window's scheme while
  the tab shows); it starts on the app's. No boards inside the tab (Sam: "the
  entire panel should match… not a square around the glyphs").
- Category checkboxes (`CategoryChip`, shared with the Specimens popover):
  SwiftUI's `Toggle(sources:isOn:)` over two bindings (any on, all on) draws
  the mixed dash; each binding writes the whole category, so a click changes
  it once. The popover's way into the tab is "Choose specimens one by one…".

### Poster stills (Lab/SpecimenPoster.swift, since 0.9.0)

A specimen's still used to be the scene 60% in. A few specimens draw
themselves up over the loop, so a thin moment of them is nearly nothing. The
**poster time** of each is chosen once: `SpecimenPoster.times` gives the
candidates (the old 60%, then ten spread between the fade-in and the
fade-out, since a scene is half there inside `LabScenes.fade`), `ink`
draws them all onto one small sheet (40 pt cells, `ImageRenderer`) and sums
each cell's opacity, and `choose` takes the one with the most. The sum of
opacity, not a pixel count, so a faint wash counts for less than a solid
line. One rule softens it: **the old still keeps its place while it already
has 60% of the best frame's ink** (`keepsOldStill`). Ink is a rough measure
(a closed black door has more than an open one with things in it), and a
still that is good enough should not move for a few percent. Measured on the
catalogue, that moves 21 of 528 (Lithography, Tardigrade, Cryo-EM, Aspirator
among them); the rest keep their old still.

- **Where it is used** (Capsid's own code): the grid's still (`SceneStill`,
  with Reduce Motion, and the moment before a cell plays) and the flask under
  Reduce Motion (`StillSpecimen`). **Not** the panel's covered-screen still:
  `PlayedGlyphView` in Shared/ draws the middle frame of the scene it is on
  when its window is covered or the screen sleeps, and Shared/ is the
  droplet's. A poster there is a change to make in the droplet.
- **Lazily, and in line.** `ImageRenderer` and `GraphicsContext` need the
  main actor, so the choosing cannot go off the main thread. It costs
  0.7 ms a specimen (release; 0.4 s for all 528, `Capsid --measure-posters`),
  so it is asked for only when a still is first drawn, answered one at a time
  with a 2 ms breath between (`SpecimenPosters`), and kept for the run. Nothing
  is asked while every cell plays live, which is nearly always. Until the
  answer comes the old time shows.
- **The pale tiles were live cells, not stills.** A cell on screen plays from
  the clock, and it drew the scene with `LabScenes.draw`, which fades and
  grows a scene in over its first 0.3 s and out over its last 0.3 s: the
  rotation's hand-over to the next scene. A cell plays one scene round and
  round, so it was pale at the start and end of every loop (nearly a fifth of
  a three-second scene), and a screenshot caught ECL detection, Streak plate,
  Column and Flow cytometry that way. Live cells now draw with
  `SpecimenPoster.drawLooping`: the scene's own loop at full strength, clipped
  to its square. The preview well and the panel still fade between scenes, as
  they play. A scene that builds up (ECL starts with a bare plate) still has
  thin moments of its own; the poster is for stills.
- `Capsid --measure-posters [sheet.png]` prints the cost and how many moved,
  and writes a sheet of old and new stills.

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
  scans the transcript, so never poll. When the page moves to another session
  the read under way is cancelled, its fetch aborted in the page, and an answer
  that still arrives for the old session is ignored (since 0.9.3).
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
  one limit as what's left and when it resets, e.g. "66% left · resets in 1h
  12m" or "Week 12% left · resets Thu". Which limit is the Title bar shows
  setting's (since 0.9.1, below). The session limit goes unnamed: "5h" read
  as five hours to go. The countdown ticks each minute and is tertiary; the
  figure is secondary and turns clay-text under 20% left. `chart.bar.xaxis`
  shows until the first read lands.
- Popover (glass): a **Plan limits** section with a row per limit ("Current
  session", "Weekly · all models", "Weekly · Opus", "Weekly · Sonnet"), each
  with a bar, "% left" and "Resets in 2h 14m" (and the forecast line and
  sparkline below), plus extra usage when enabled. Then the **Activity** section (the graph from Claude Science's launch on June 30, 2026, a column per week up to a year; 14 pt squares while it spans 30 weeks or fewer, the days before launch blank; the popover is as wide as the graph needs, 600 pt at least), and a Refresh
  button (`.glass`).
- One Usage control, not two.

**Which limit the label shows (`TitleBarUsage`, since 0.9.1).** The label
used to show the limit with the least left, so once the week had less left
than the 5-hour window it named the week, and the 5-hour figure was gone.
Settings → Usage → **Title bar shows** (`titleBarUsage`) now picks, in a
native pop-up:
- **5-hour limit** (the default): the session limit. The exception, so a
  limit can't run out unseen: if another limit is low (`PlanLimit.isLow`,
  under 20% left, where its figure turns clay-text) and has less left than the
  session, that one shows instead, named as before ("Week 12% left"); of
  several, the one with the least left. The same left as the session keeps the
  session. An answer with no session limit (some accounts) shows the lowest.
- **Whichever is lowest**: the limit with the least left (`tightest`), as the
  label worked before 0.9.1.

One pure function chooses, `PlanUsageModel.shown(_:choice:)` (`nonisolated
static`; PlanUsageChoiceTests), and `UsageToolbarButton` reads the setting with
`@AppStorage`, so the label changes as soon as the pop-up does. The toolbar
button is named "Usage" for VoiceOver, with the limit shown as its value
("Weekly · all models: 12% left. Resets …"; "Plan usage and activity" before
the first read), so it follows the pop-up, and the popover lists every limit
either way. The name is set on the button itself (since 0.9.3), not left to
its changing label: the Context button beside it shares the native toolbar
group, and each button must name only its own half.
Nothing else reads `tightest`, and nothing else draws this label, so these are
as they were: heads-up notices (each limit against its own thresholds), the
usage pause (`limitReached`, `nearLimit`), the phone (every limit, with its
pace) and the menu bar (the specimen only).

**One way to write times (`TimeSpan`, since 0.9.0).** The toolbar said "resets
in 1h 28m" while the Usage popover said "Resets in 1 h 28 m", and the plan
notices said "in 47 minutes". One formatter now, in the compact style:
- a length: "45s" under a minute, then "12m", "1h 5m", and "2h" for an exact
  hour (never "1h 0m"); `short`, to the nearest minute (the finished card's
  "12m · 1.2M tokens");
- a countdown: `countdown`, minutes rounded up so it never reads "0m" while
  time is left;
- a reset: `reset`, "in 1h 28m" within a day, "now" once over, past a day the
  weekday. The toolbar writes "Thu"; the popover and the notices have room
  for the time, "Thu 11:27 PM" (`withTime`), in the Mac's own format;
- for VoiceOver, `spokenReset` spells the units out ("in 1 hour, 28 minutes"),
  since "1h 28m" is read letter by letter.
Not in it: the running turn clock ("4:12", `ElapsedClock`) and the pairing
code's countdown, which are clocks, and times of day ("Resumes at 3:40 PM",
"limit around 3:40 PM"), which are not lengths. "5 min. ago" and "2 minutes
ago" (Quick Open, the activity list, Diagnostics) say when something
happened, in the system's relative style, and are left to it.

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

- General is a grouped `Form`, as System Settings is: Capsid's icon (the chosen one, since 0.9.5), name, version and the "Unofficial,
  and not affiliated with Anthropic" line at the top, native switches, a segmented Theme picker, and
  Diagnostics as a plain button. Its frame was fixed (600 × 640) then; each page has its own height now, and
  since 0.9.3 a width of 760 and a cap by the screen (Settings, Page sizes). A
  grouped form has no height of its own, and the Settings window sizes to each
  tab.
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

## Update check (App/UpdateCheck.swift, App/UpdatePrompts.swift, App/UpdateInstall.swift, since 0.3.6)

Capsid can ask GitHub whether a newer Capsid is out, and install it. **On by
default since 0.9.7**; it was off from 0.3.6 to 0.9.6, because it is the one
request Capsid makes beyond this Mac that no click asked for. Sam chose to
turn it on (2026-10-22) so people actually see updates: the check never ran
for anyone who hadn't found the switch. What is sent is unchanged (below), and
the switch stays (Settings → General → Updates → **Check for updates once a
day**, `checkForUpdates`; the welcome window has it too, already on).
Someone who had turned it off keeps it off: their stored `false` wins over
the registered default. README's promise reads: Capsid talks to nothing
beyond your Mac except links you click, a once-a-day update check, which you
can turn off, and, if you turn on Capsid on your phone, your own paired
devices over your Tailscale network, with notifications, if you turn them on,
carried by Apple's push service and encrypted so only your device can read
them.

**What is sent.** One `GET https://api.github.com/repos/samporter14/bench/releases/latest`
through an ephemeral `URLSession` (no cookies, no cache, no credentials,
`httpShouldHandleCookies` off), with exactly three headers: `Accept:
application/vnd.github+json`, `User-Agent: Capsid/<version>` and a fixed
`Accept-Language: en`, so the system's language preferences aren't sent. No
identifier, no account, nothing about sessions, projects or the machine.
GitHub does see the connection's IP address, as any site does. It is
`UpdateRules.request`, and a test pins the headers. The install's download goes through the same
session; the phone's push sender has one of its own (Capsid on your phone →
Notifications).

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
last version announced (`updateAnnouncedVersion`) and the newest version
skipped (`updateSkippedVersion`, below). At launch Settings
shows an update seen last time while it is still newer than the running one,
and "up to date" after a check that found none, without asking.

**When there is a newer one.**
- *Card, once per version* (`UpdateRules.shouldAnnounce`): "Capsid 0.9.7 is
  available", "Install now, or any time from Update in the toolbar", with an
  **Install…** button (since 0.9.7; before it the card had no buttons and
  said to use the menu). Only from an automatic check; one you asked for shows
  its answer itself and counts as telling you. A newer version gets its own
  card, and a version you skipped gets none. The button is the notice's
  action `.installUpdate(update)` (`LabNotice.Action`); `LabModel.open`
  dismisses the card first and then, on the next turn of the main actor, runs
  the offer alert (`UpdatePrompts.offer`), because a modal alert opened while
  the card is still up would hold it on screen. The same `Action` is read by
  `LabPanelView`, `MacNotifications` and `PushCenter`, each with an `if case`
  for `.openSession`, so a new case changes nothing for them.
- *The toolbar's Update button* (`App/UpdateToolbarButton.swift`, since
  0.9.7): a clay `arrow.down.circle.fill` and "Update" in a glass capsule of
  its own, first among the trailing items. It is there only while an update
  is **offered** (`UpdateChecker.offered`: the newest known update, `newest`,
  and the version wasn't skipped) and never in a demo, which shares the toolbar and
  checks nothing. The condition wraps the `ToolbarItem` itself, in
  `BenchToolbar`: an item holding nothing still gets a capsule. Its help is
  "Capsid 0.9.7 is available". It is a `ReadoutButtonStyle` button, and the
  arrow carries its colour baked in, as the Specimens button's flask does,
  because the toolbar draws template symbols in its own ink. `newest` is not
  `state`: it is set by a check that finds an update, cleared by one that
  finds none, and left alone while a check runs or when one fails, so the
  button doesn't blink out during the daily ask or vanish for a day offline
  (a review fix: the first cut keyed it on `state`). Install uses it too.
- *Its popover* (`UpdateOfferView`, 400 wide with 20 points of padding all
  round, like the usage popover's): the app icon at 40 points, "Capsid 0.9.7
  is available" and "You have 0.9.6.", then the install sentence (or the
  sentence for a copy that can't replace itself) in callout size, and a row
  of **Skip This Version** (borderless, left), **Release Notes** and **Install
  and Reopen** (`.borderedProminent`, clay, the default action). Install and
  Reopen is left out of a copy that can't install, and reads "Installing…" and
  is dimmed while the installer runs. It asks nothing further: the sentence
  above it is the warning. The popover is told everything it shows and given
  its actions, so a test draws it without the checker. Release Notes closes it
  and opens the page; Skip closes it. At 320 across the three buttons wrapped
  "Skip This Version" onto two lines, so the content is 360 across.
- *Skip This Version* (`updateSkippedVersion`): `UpdateChecker.skip` keeps the
  version and `UpdateRules.shouldOffer` is true for a version newer than it.
  Skipping 0.9.7 hushes 0.9.7 and anything older, never 0.9.8; something stored
  that isn't a version hushes nothing. It stops the card, the toolbar button
  and the Dock item. `state` doesn't change: Settings and the menu's alert
  still show the version, since you asked there. The offer alert has the same
  choice as a checkbox, "Skip this version", used on any answer but Install.
- *The Dock item*: with an update on offer, the Dock icon's menu starts with
  "Install Capsid 0.9.7…" and a separator (`AppDelegate.applicationDockMenu`,
  never in a demo). It opens the same offer alert.
- *Settings → General → Updates:* the status line ("Asking GitHub…", "Capsid
  is up to date (0.3.5)", "Capsid 0.3.6 is available" or why a check failed)
  with **Check Now**, which reads "Checking…" and is dimmed while it runs,
  and under the status, in small secondary text, when the last answer came. When one is out, a row beneath says what Install will do, with
  **Release Notes** and **Install Update**.
- *The offer alert* (`UpdatePrompts.offer`, since 0.9.7 the one place that
  offers; the card's Install…, the Dock item and the menu's check all open
  it): "Capsid 0.3.6 is available" with **Install** (only for a copy that can
  replace itself), **Release Notes** and **Later** (Esc), and a "Skip this
  version" checkbox that skips on Release Notes or Later. A second ask while
  one is showing does nothing. The menu's check shows it for an available
  update, else an alert with OK: up to date, or why the check failed. Its
  text is the install sentence, so Install needs no second question.
  Settings' **Install Update** asks first, with the same words.
- **Release Notes** opens the page in the in-app Browser window, as any
  other link to a website does (Web routing policy: GitHub is "any other
  http(s)"), where "Open in Safari" is one click away.

**Installing natively (App/UpdateInstall.swift, Resources/swap.sh, since
1.0).** Until 0.9.7, Install ran the README's line, `curl … main/install.sh |
zsh`: a script fetched from the `main` branch as it stood at that moment, not
from the release being installed, which deleted the installed app before the
new copy was in place and checked nothing about what it had downloaded. Since
0.9.7 turned the daily check on by default, more copies run this path, so 1.0
installs natively, in three steps, and the installed Capsid is never deleted
until the new one is running:

1. *Download.* `GET https://github.com/samporter14/bench/releases/download/<tag>/Bench.zip`,
   the offered release's own file, through the update check's ephemeral
   session (`UpdateDownloader`: no cookies, no cache, a size cap of 200 MB,
   redirects followed only to https, since GitHub hands the file to its
   content host). The tag is the release's `tag_name` kept by the check
   (`AvailableUpdate.tag`, remembered as `updateNewestTag`), accepted only
   when it is a version with or without its `v` (`UpdateInstallRules.isTag`),
   so nothing read off the network steers the address; a version remembered
   without its tag gets `v` and its number. The file lands in a state folder,
   `~/Library/Caches/local.sam.bench/update/<tag>/`, on the same volume as
   /Applications, after a check that 200 MB are free. The popover, the
   toolbar button ("Updating", with a clay ring) and Settings show the
   progress ("Downloading Capsid 0.9.8… 3.1 of 9.4 MB"), and Cancel stops
   it: the download is deleted and nothing else has been touched.
2. *Check,* before anything is quit or moved: `ditto -x -k` unpacks the zip;
   it must hold `Capsid.app`; the copy must carry no quarantine mark (this
   path never sets one, so one means the file came another way; it is a
   tripwire, never stripped); its signature must be valid down to every
   nested piece **and meet the designated requirement of the copy running**
   (`SecCodeCopySelf` → `SecCodeCopyDesignatedRequirement`, checked with
   `SecStaticCodeCheckValidity` strict, nested, all architectures), with
   `codesign --verify --deep --strict` as a second opinion; and its
   `Info.plist` must say `local.sam.bench` and the version that was offered.
   A copy that fails any of these is deleted without being opened, and the
   alert says which check it failed ("The downloaded copy isn't signed the
   way this one is, so Capsid deleted it without opening it. You still have
   0.9.7, and nothing was changed."; "…says it is 0.9.6, not 0.9.8…").
   Because the requirement is the running copy's own, a release signed
   another way fails here on purpose: the first release signed with a
   Developer ID certificate after the self-signed ones will have to be
   installed by hand once (its successors then match again). The check is an
   injected closure (`UpdateInstallDependencies.meetsRequirement`), so that
   release can widen it to "or Solanum's Team ID" without rewiring.
3. *Swap.* `Resources/swap.sh`, shipped in the bundle, is copied into the
   state folder and started detached with this process's id, the installed
   app's path, the unpacked copy's path and the state folder; then Capsid
   quits the way ⌘Q does. The script waits up to 30 s for that process to
   exit (touching nothing while it runs), moves `/Applications/Capsid.app` to
   `Capsid.app.previous`, moves the new copy into place, opens it, and waits
   up to 30 s for a process whose executable is exactly the installed app's
   (compared as text, as install.sh does), looking again two seconds later
   because a copy that dies on launch is seen for an instant. Then it writes
   one marker in the state folder: `installed 0.9.8`, or `failed: <reason>`.
   If the new copy doesn't start it is moved into the state folder for a
   look, the old copy is moved back and opened; if a move fails the old copy
   is put back and opened; a leftover `.previous` from an earlier update goes
   into the state folder, not the bin. The script never deletes the installed
   app. Its test hooks (`CAPSID_SWAP_WAIT`, `CAPSID_SWAP_LAUNCH`,
   `CAPSID_SWAP_RUNNING_FILE`) are scrubbed from the environment Capsid gives
   it. If the script ends while Capsid is still here (Capsid didn't quit),
   its marker is shown as the failure.
4. *The launch after.* `UpdateAftermath.settle`, from `UpdateChecker.start()`,
   for the copy in Applications and never in a demo: with the marker saying
   installed, or a `Capsid.app.previous` beside it, the old copy is removed
   **only if its version is older than the running one** (anything else is
   left and logged), the state folder goes, and one notice card says
   "Capsid 0.9.8 is installed", "Your sessions kept running in Claude
   Science." (caption Updated, no button, 15 s). With the marker saying
   failed, this is the copy that was put back: an alert says why ("Capsid
   0.9.8 didn't open", "The new copy didn't start, so Capsid put 0.9.7
   back."), with Release Notes.

   The old copy is removed only after a handshake (a review found the gap,
   since 1.0). swap.sh opens the new copy, waits until it runs, looks again
   two seconds later (a copy that dies on launch is seen for an instant), and
   only then writes `installed <version>`. The new copy's launch clean-up
   used to remove `.previous` whenever it was there and older, so a copy that
   reached its clean-up and then died inside those two seconds left swap.sh
   with nothing to put back, and Applications with no Capsid. Now `settle`
   removes `.previous` only once the marker reads `installed`; with an older
   `.previous` and no marker yet it removes nothing (`.waiting`) and
   `settleAndReport` looks again every 2 s for up to 30. If the marker never
   comes, `.previous` stays, one line goes to the log, and the next update's
   swap.sh moves it into the state folder (step 2). A `failed:` marker is
   acted on at once. `SwapScriptTests` drives the real swap.sh through that
   window: clean-up, then a crash, and the old copy is back whole.

The confirmation now reads: "Capsid will download 0.9.8 from GitHub, check
that it's signed the way this copy is, then quit and reopen. Your sessions
keep running in Claude Science." Install is still offered only to the copy
that is /Applications/Capsid.app (`canInstall`); from a build folder or
Downloads the sentence says so and Install is left out. A failure's alert
offers Try Again only when trying again can help (a download that stopped,
a zip without Capsid.app, a Capsid that didn't quit), and Release Notes for a
copy that failed its checks or didn't open; every sentence names the version
you still have.

`install.sh` (first installs, and the path every copy up to 0.9.7 still
updates through, since it runs `main`'s script) does the same by hand: it
asks the API which release is latest and downloads that tag's zip (falling
back to `releases/latest/download` when the API refuses, which it does after
60 unauthenticated calls an hour), runs `codesign --verify --deep --strict`
and the quarantine check before quitting anything, moves the installed copy
aside instead of removing it, opens the new one and removes the old only
once the new one has been running for two seconds, putting it back otherwise.
A push of that file to `main` reaches every 0.9.7 at once, so it is tested
against the real release in a scratch folder (`BENCH_INSTALL_DIR`) before it
goes anywhere.

`Capsid --update-dry-run <tag>` runs the download and every check against a
real release into a scratch folder and stops before the swap, printing each
step: how the live path is tried without a newer release (TESTING.md).

- *What is sent* grows by one request, made only when you click Install: the
  release's file. README's promise says so ("and the update you choose to
  install").
- *Nothing automatic.* Install is a click; no download happens on the daily
  check.

**Tests** (`UpdateCheckTests`, `UpdateInstallTests`, `SwapScriptTests`):
version compare, the JSON from made-up fixtures (now keeping the tag), the
once-per-version card and its Install… action, `shouldOffer`, Skip This
Version, "not due yet", the setting off meaning no request, the request's
headers, failures, a check shared by two callers, and the README's line still
pointing at install.sh; the install's rules (tags, the asset address, the
bundle check, markers, which old copies may be removed, the hooks scrubbed,
the progress sentence, every failure's sentence and buttons); the whole flow
with fakes for every step (a good download is checked then swapped and Capsid
quits; a download that stops, no room, a zip without Capsid, a copy signed
another way or quarantined or of another version, a copy without the script,
and a cancel mid-download all leave nothing behind and touch nothing); what a
launch does with the marker and the `.previous` copy; and `swap.sh` run
against a scratch folder with made-up bundles (the swap, a new copy that
never starts, a move that fails, a running copy that never quits, a stale
`.previous`, bad arguments, and that build-app.sh ships it). No test goes
online, runs a real installer or touches /Applications. With
`CAPSID_SNAPSHOT_DIR` set to a folder, one more test draws the popover into
it as PNGs, light and dark, in each phase (the offer, downloading, checking,
installing, and a copy that can't install).

## Settings (⌘,)

Six tabs since 0.4.0 (`App/SettingsPages.swift`), each a grouped form at its
own height (the window follows the tab), every one 760 wide and none taller
than the screen it is on (Page sizes, below):

- **General** (`general`): Capsid's name and version, a banner when it can't see
  your sessions, Appearance (the theme, and App icon since 0.9.5), Updates
  (since 0.3.6), Nidus (since 0.7.3) and Help → Diagnostics.
- **Panel** (`panel`): the specimen while a session works (show it, name it,
  the menu bar), where the panel sits (corner, screen, while Capsid is in
  front), and a way to the Specimens tab.
- **Alerts** (`alerts`): on the panel (cards, plans with Approve, sound),
  Quiet While Presenting (since 0.9.0; see Quiet while presenting), Mac
  notifications, and what waits while Nidus is focusing.
- **Usage** (`usage`): which limit the title bar shows (since 0.9.1) and
  heads-up cards (plan and context, week in review).
- **Specimens** (`scenes`): what plays (above).
- **Phone** (`phone`, since 0.4.0): Capsid on your phone (below).

`--demo general|panel-settings|alerts|usage-settings|specimens|phone-settings`
shows each in a plain window that doesn't activate Capsid (`phone-settings`
takes `--step 1…7`; `--open-info "<a row's title>"` opens that row's ⓘ by
itself, for a screenshot of the popover).

**Short descriptions, and the ⓘ (since 0.9.0).** Under a row's title is one
plain line, or two at most, saying what the switch does for you. What is
only needed to decide, or only now and then (what a card shows, the numbers
behind a heads-up, where to turn something off, which switch works with which),
is in an ⓘ: a small `info.circle` button after the title that opens a popover
(`InfoButton` and `InfoTitle`, App/SettingsInfo.swift, the one component every
page uses, with the long texts beside the pages: `AlertsInfo`, `UsageInfo`,
`PanelInfo`, `MacNotificationsInfo`, `PresentingSettings`). The rows that
have one: Alerts → Show a card, Show plans, questions and requests on the
card, Also send a Mac notification, Show session and project names, Hold
finishes and the two Quiet rows; Panel → Screen; Usage → Title bar shows
(since 0.9.1) and Plan and context;
Specimens → the heading; Phone → browsing; and General → App icon (since
0.9.5; see App icon). General has no other: its lines were already two at
most. Keys and behaviour are unchanged.

**Page heights** (`settingsPage(height:)`, set from a capture so the first
and last rows have the same margin, about 22 pt): General 702 (it was 634 before App icon, since 0.9.5; the row is
67.5 pt, found by rendering the page offscreen with and without it and keeping the old margin), Panel 504,
Alerts 818 (it was 740, and already cut off at the bottom), Usage 316 (it was
238 before the Title bar shows row, since 0.9.1; a pop-up row with its line
and no heading adds 78 pt), Specimens 760×776, Phone 760. Alerts' two new rows (Quiet While Presenting,
one line each) are mostly paid for by the shorter lines and by the Mac
notifications footer moving into an ⓘ; the page is 78 pt taller than before. Phone's height is the
checklist's tallest states (step 4 or 6 open), so in the ready state it has
more room below; it is not trimmed.

**On a short or scaled screen (`SettingsViewport`, since 0.9.3).** Every form
was a fixed 600 pt wide and its page height, and Specimens a fixed 760×776, so
on a laptop display or a scaled one the bottom of a tab, and the controls
there, could sit under the screen's edge. Now every tab is 760 wide
(`SettingsSizing.width`); a form keeps its reading width, 600 pt
(`SettingsSizing.formWidth`), centred in it, and the page heights above are the
most it takes. `settingsViewport(height:)` caps the height at the usable frame
(`visibleFrame`) of the screen the Settings window is on, less the window's own
chrome (title bar and tab toolbar) and 16 pt of margin above and below. It looks again only
when the window changes screen or size or the screens' parameters change: no
polling, and it does not depend on which other Capsid window is key; before a
window exists it assumes 100 pt of chrome on the main screen. A grouped form
that no longer fits scrolls, as a form does. Specimens (`settingsViewport(776)`)
reads the height it was given: under 660 pt it is one `ScrollView` holding the
heading, the controls and the grid, with the grid at its natural height (220 pt
at least when empty), so the page has one scroll owner and the controls above
the grid can be reached; at 660 or more the grid scrolls inside the page, as
before.

| Setting | Default |
|---|---|
| Appearance: Match Mac, Ivory or Slate (the whole app, via `NSApp.appearance`; the page follows while its own theme is System) | Match Mac |
| App icon: one of six, the Dock icon while Capsid runs (`appIcon`, since 0.9.5; see App icon) | Clay |
| Title bar shows: 5-hour limit or Whichever is lowest (`titleBarUsage`, since 0.9.1; see Usage remaining) | 5-hour limit |
| Show the Lab panel | on |
| Play a sound when a session needs you | on |
| Show plans on the card, with Approve (`showPlansOnCard`, since 0.3.4) | on |
| Also send a Mac notification (Mac notifications) | off |
| When a session finishes too (Mac notifications) | off |
| Show session and project names (Mac notifications) | on |
| Show the Lab panel while Capsid is in front | on |
| Name the specimen that's playing, in the panel (`showSpecimenCaption`) | off |
| Check for updates once a day (`checkForUpdates`, since 0.3.6; on since 0.9.7; see Update check) | on |
| Use Capsid from your phone (`remoteEnabled`, since 0.4.0; see Capsid on your phone) | off |
| Skip "Put Tailscale on your phone" (`remotePhoneSkipped`; see Settings → Phone) | off |

Reopening the session you were in (Daemon and sign-in) has no row: it is on,
and not a setting.

## App icon (App/AppIconChoice.swift, App/AppIconPicker.swift, since 0.9.5)

Settings → General → Appearance → **App icon** offers six icons, drawn as small tiles in a row
(`AppIconPicker`), the chosen one ringed in the accent (clay: a Settings page tints with it).
Under the row's title is one plain line, "Changes Capsid's icon in the Dock while it's open.", and
an ⓘ (`AppIconInfo.dockOnly`) that says why only the Dock: macOS gives an app no way to change the
icon Finder and Launchpad show without altering the app itself, which would break its signature
and the permissions the user granted it, and every update would undo it. So **the choice is the
Dock icon while Capsid runs**, and the icon Capsid draws in its own windows (Settings' header and
the welcome's first page, through `AppIconChoice.shown`; an alert or the About panel takes
`NSApp.applicationIconImage` by itself). Finder, Launchpad, notifications and a Dock tile for
Capsid when it isn't running keep Clay, the bundle's own. Nothing writes to the bundle and nothing
calls `NSWorkspace.setIcon`; a test holds both, and holds `applicationIconImage =` to one file.

**The six** (`AppIconChoice`, the key `appIcon`, default `clay`). Solanum allows exactly three icon
grounds, Ivory #FAF9F5, Slate #141413 and Clay #D97757, and one colour rule: structure (the ring, the
capsid) takes ink, the organism (the escaped dot) takes clay, and a one-colour version sets
everything to ink. On a Slate tile the ink is Ivory. No other colour appears.

| Id | Name in Settings | Tile | Ring | Capsid | Escaped dot |
|---|---|---|---|---|---|
| `clay` | Clay | Clay | Slate | Slate | Slate |
| `ivory` | Ivory | Ivory | Slate | Slate | Clay |
| `slate` | Slate | Slate | Ivory | Clay | Clay |
| `ivoryMono` | Ivory, one color | Ivory | Slate | Slate | Slate |
| `slateMono` | Slate, one color | Slate | Ivory | Ivory | Ivory |
| `ivoryClay` | Ivory and Clay | Ivory | Slate | Clay | Clay |

Clay is today's icon, unchanged, and the default. The names use American spelling ("one color").

**One glyph, cut into three layers, never redrawn** (`Scripts/make-icon-variants.py`, Pillow and
numpy). `Resources/AppIcon.icon/Assets/bench-glyph.png` (1024 px, Slate on transparent) is split by
distance from its centre, since its three parts sit in separate bands: the capsid inside radius 180,
the ring 271 to 297 (the annulus), the escaped dot 323 to 364 at the upper right. The cuts are at
230 and 310, in the gaps; the script stops if a redrawn glyph puts ink within 5 px of a cut, leaves
a band empty, or moves the dot out of the upper right. The three layers cover every pixel once, so
nothing is lost or doubled. Each variant is written as `Resources/AppIconVariants/<id>.icon`: an
`icon.json` with the tile as an sRGB solid (the original's settings otherwise: no shadow, no
translucency) and `Assets/ring.png`, `capsid.png`, `escapee.png`. A layer is recoloured by setting
its RGB to the one colour wherever it has ink and keeping the alpha, so the glyph's antialiasing is
kept; a Slate layer keeps the glyph's own pixels (they are not one flat value: 20 to 22 at full
alpha, black at the faintest edge), so the Clay document's layers are the raw split. Re-run it after
changing its table (`python3 Scripts/make-icon-variants.py`; `--check` fails if the committed documents
differ, comparing pixels, not PNG bytes). It proves what it wrote, reading the PNGs back: the layers' ink
never overlaps, its union has exactly the glyph's alpha, each layer is one colour, and the Clay and
Ivory-one-colour documents' layers composite to `bench-glyph.png` byte for byte. `bench-glyph.png` is
not changed (`embed-remote-web.py` embeds it for the phone's icon). Capsid's own `AppIcon.icon` is
unchanged too.

**No edge on the Ivory tiles.** Solanum draws an Ivory icon with a `border-strong` edge, rgba(31, 30,
29, 0.3). Icon Composer's document format has no border or stroke key (its keys are fill, blend-mode,
lighting, glass, shadow, specular, translucency, opacity, position and scale, with the
fill and image specializations), so it would be a layer: a thin ring along the tile's edge. A layer is positioned in the same canvas as the tile and masked by it, and the squircle isn't
a shape that can be drawn to match exactly, so a trial (a superellipse stroke, 4 px, at 30%) compiled to a
doubled, uneven line against the system's own. macOS already gives a compiled icon its edge highlight
and a soft shadow (the compiled Ivory tile reads on light grey, #ECECEC, and on mid grey), so there is none. The
`border-strong` edge is for flat contexts (a page, a card), not for the Dock.

**Compiled in the build** (`Scripts/compile-icons.sh`, run by `Scripts/build-app.sh`). One `actool`
call compiles `Resources/AppIcon.icon` as the app's icon and every other document in
`Resources/AppIconVariants` (all but Clay, which is AppIcon) as an *alternate app icon*:
`--app-icon AppIcon`, then `--alternate-app-icon <id>` for each of the five and
`--include-all-app-icons`. The documents' folder names are their icons' names. The result is the
usual `AppIcon.icns` (unchanged, 49 KB) and one `Assets.car` holding all six as full icon stacks,
so there is no `AppIcons/` folder and no .icns per variant (an .icns tops out at 256 px, which is soft at
the Dock's largest magnification). The partial Info.plist actool writes keeps `CFBundleIconName` and
`CFBundleIconFile` at `AppIcon`, so Finder and Launchpad still get the app's own icon; the app's own
Info.plist is what ships. It costs 4 to 5 s more in the build. **Assets.car grows from 1.74 MB to
10.10 MB** (about 1.7 MB an icon: each is a full stack at 32 to 1024 px), and the zipped app from
6.48 MB to 14.64 MB (`ditto -c -k --keepParent`, measured 2026-10-21; compiling one .icns per
variant instead, which the catalog replaced, added only 0.32 MB). Either
`--alternate-app-icon` or `--include-all-app-icons` is enough for actool to compile the extra
documents; with neither it compiles only AppIcon. The script is failure-tolerant: if the combined call
fails it warns ("the alternate icons did not compile") and compiles AppIcon alone, so Capsid keeps
Clay and every choice falls back as a missing picture does; if that fails too it warns and goes on.
It runs before the Focus filter's metadata and the signature, which seal Resources. Tests check
that the folder, the enum and the script name the same six, and run the script itself into a
throwaway bundle (a test that needs Xcode's `actool`, about 5 s, skipped without it): no warning,
`AppIcon` still the partial plist's icon, and every choice, Clay as AppIcon, has a picture in the
catalog with a 1024 px rep. A release build isn't needed to check any of it.

**Runtime.** `AppIconDock.shared.apply()` reads `appIcon` and sets `NSApp.applicationIconImage` from
the choice's catalog picture (`AppIconChoice.image(in:)`, `Bundle.image(forResource:)`, which is
`NSImage(named:)` for the app's own bundle): reps at 32, 64, 256, 512 and 1024 px, with the
system's treatment (squircle, edge highlight, shadow), so it is crisp at the Dock's largest
magnification. For Clay, a picture that isn't there and a name this Capsid doesn't know it
sets nil, which restores the bundle's icon, but only when a chosen picture is up: a Mac that never
chooses, or launches on Clay, is never told anything (the Dock isn't asked to redraw an icon it
already has), and going back to Clay clears once. It runs at launch next to
`BenchAppearance.apply()` (before a demo's early return) and when the setting changes. The
picture and the setter are injected into an `AppIconDock` of a test's own, so a test never touches the
real `NSApp`. Pictures are read once (`picture`), since Settings draws six at each refresh. When the
catalog has none of them (`swift run`, the tests) the picker draws each tile's ground as a rounded
square.

**What it can't do, and wasn't seen.** A custom `applicationIconImage` is a still image, not the
layered rendering macOS makes of the bundle's own icon, so a chosen icon doesn't follow the system's Dark
or Tinted icon appearance. It was checked as compiled and rendered to PNG (the six at 512 px on grey),
and by tests; it has not been seen in the real Dock.

## Diagnostics (App/Diagnose.swift, App/Compat*.swift, since 0.8.0)

Help → Capsid Diagnostics… (also Settings → General → Diagnostics…, and the banner that says Capsid
can't see your sessions) shows what Capsid can and can't see of Claude Science, one line per step, with
Run Again and Copy. `Capsid --diagnose` prints steps 1 to 5 and the list of what is checked only when
used, says the page checks need the window, and exits. It names no project, session, tab, file or org
ID: only yes/no, versions, folders, sizes, ages, counts and fixed phrases, so it is safe to paste into a
message. ✓ is fine, ✗ a problem, • neither (a note, or something
that couldn't be told).

**The steps, in order.**
1. The `claude-science` tool and its `status`: running, version, port, data folder.
2. **The version line.** "Claude Science 0.1.65; Capsid was last checked with 0.1.63". The running version is
   `status.version` from the same `claude-science status` the app already runs to find the daemon (a CLI
   that omits it reads "unknown", and the line says Claude Science didn't say). No page or API read is used
   for it. `CompatInventory.checkedWith` is the version Capsid was last checked with: 0.1.63, the one whose web
   bundle the tab markup was read from (Main window, above). The versions are compared as numbers
   (`ScienceVersion`: 0.1.9 is older than 0.1.63; a suffix like "-rc1" can't be ordered and reads as
   different). If the status can't be read, the line is only "Capsid was last checked with Claude Science
   0.1.63". When they differ, ✓ becomes • and a second line says, in plain words, that this is a newer (or
   older, or different) Claude Science than Capsid was checked with, so features that depend on its page (the
   tab commands, the readouts, Approve) may need a look. Moving `checkedWith` is a claim: walk the whole
   inventory again first (and the 0.1.63 sentence in the Main window section).
3. Each data folder and org database, and which was picked.
4. The database opens read-only, and each table has the columns the queries read. The list is the
   inventory's (below), so it now includes `conversation_type`, `agent_name`, `task_summary` and `input_data`,
   which the session filter, the browse lists and the intent lookup read and the step once left out.
   `projects.archived_at` is optional: Capsid uses it when it is there, and the line only notes if it isn't.
5. The reads themselves, as the Lab does them: recent sessions, project names.
6. **The page and the API** (the window only: they need the open page). Below.
7. **Checked only when used**, and **Last problem**. Below.

**What Capsid relies on** (`CompatInventory.all`). Claude Science never promised to keep any of it, and an
update that changes it breaks a feature without a word. The list is in code, in five kinds, each entry with
what is looked for, what is expected, the Capsid feature it serves (`CompatFeature`), the file that relies
on it, and whether Diagnostics can check it now:

| Kind | What |
|---|---|
| Page | the right-hand panel's tab markup (the strip, its toolbar, a tab, the button that shows it, its close button, how the shown tab is marked); the visible "Sign in" button; the page's own `Notification`; a session's address `/projects/<project>/frames/<session>`; the `?nonce=` sign-in; previews on another port |
| Reads | `/api/usage`, `/api/frames/<id>/token-series`, `?shallow=true` (and a failed session's `output_data.error` in it, since 0.9.0), `/api/artifacts/versions/<v>`, and for the phone the thumbnails, the artifact list, `messages`, `trace-shallow`, `streaming`; for Keep (since 1.0) an artifact's `/versions`, a version's `?include_metadata=true`, its `/lineage?slim=1` and the `_artifact_refs` and `_ts` of `messages`; `/api/csrf`; a 401 when signed out |
| Writes | `approve-plan`, `resolve-input`, `/api/request`, `/api/projects/<p>/request`, `/api/projects/<p>/attachments`; the `operon_csrf` cookie sent back as `x-operon-csrf` |
| Command line | the tool's place; `status` (`running`, `version`, `port`, `pid`, `daemon.data_dir`, `active_frames`, `active_conversations`); `url`; `serve --no-browser --detached` |
| Database | `active-org.json`, `orgs/<org>/operon-cli.db`; the tables and columns above; the words and JSON keys stored inside (the frame statuses, `pending_input_requests`, `msg_json`'s `_ts`, `role`, `_intent_id`, `_tokens`) |

The tests hold the list to the code both ways (`CompatInventoryTests`), so a new dependency can't be added
silently and a stale one can't stay: every selector in the page scripts (`PageTabs`, `TabContextMenu`, the
sign-in script) is in the list and every scripted entry is in a script; every read path the allowlists let
through, and every write the builders make, is in the list and passes the real gate; every key the status
parser takes is listed; no other file reads the page's markup or runs a script in it, and no other `/api/`
resource is named, without a test failing; and a made-up database holding exactly the listed columns runs
every query the app makes, while leaving out any one required column makes one of them fail.

**The page and the API, live** (`CompatProbes`). Run only when the window opens or Run Again is pressed, one
after another, each given 6 s. Each says one of four things: ✓ it answered as expected; ✗ *not the shape
Capsid reads* (it answered, but not as Capsid parses it); • *not on screen now* (it only exists in some
state, and this isn't one: no tab is open, no session is shown, the page isn't up, the Sign in button shows
only while signed out; never a fault); ✗ *couldn't be checked* (refused, signed out, gone, no answer). What
is looked at:
- **The tab strip**: the very reader the commands use (`benchReadStrip`, run as `PageTabsScript.probe`)
  reports, as counts only, whether there is one strip with its toolbar, and whether each tab has its button
  and close button and exactly one is marked shown. It presses nothing.
- **The Sign in button**, with the finder the sign-in recovery uses, looked for and never pressed.
- **The session address**: whether the page is on a session.
- **`GET /api/usage`**, **`token-series`**, **`?shallow=true`** and, if the shown session names a plan,
  **`/api/artifacts/versions/<v>`**: each through `WebContainer.apiGET` (so Capsid never handles the
  cookie), answered through the real parsers: `PlanUsageModel.parse`, `TokenSeries.decode`, `PlanFrame`,
  `PlanDocument`, and the shape rules the readouts use. The session is the one the page shows; with none,
  these are not on screen now.
- **Keep's two pure reads** (since 1.0), on the shown session's plan artifact: **`GET /api/artifacts/<artifact>/versions`**
  (at least one version, each with a number and a time) and **`GET /api/artifacts/versions/<v>?include_metadata=true`**
  (an answer for the version asked, with a number and a checksum that is 64 hex digits or none). They go through
  the typed artifact reader (`CompatProbeEnvironment.artifactRead`), not `apiGET`, because `/versions` carries
  `file_path`, which must never reach Swift. The facts are read first: they name the artifact when the frame
  doesn't. A plan without 36-character ids is not on screen now. The lineage is never probed.
The probes' environment holds two reads and two looks and no write, so a probe can't send one. A 401 during a
probe starts the same sign-in recovery as any read.

**Checked only when used.** Listed with the feature that depends on them, never tried from Diagnostics: every
write (they change things), and the phone's reads (they return what was said or made: `messages`, the
artifact list and files, `trace-shallow`, `streaming`; `apiGET` has no path for messages, the list,
`trace-shallow` or `streaming`), Keep's lineage (reading it can start a code reconstruction) and its showing
read (what was said), the page's notifications, previews, the tab right-click, the `?nonce=`
sign-in, `/api/csrf`, `claude-science url` and `serve`. Each line says why. Their first real use is the check, and a failure there leaves a breadcrumb where it can be told from
an ordinary state.

**Last problem** (`CompatBreadcrumbs`). Where a feature looks for something in Claude Science and finds it
changed, it records the miss in memory (the latest only; gone when Capsid quits), logs it at notice level
(subsystem `local.sam.bench`, category `compat`) and Diagnostics says "Last problem: Close Other Tabs, 12 minutes ago: the tab strip has no toolbar of open panels". A repeat of
the same miss within 10 minutes is ignored by the log and by this line alike, so a usage read every five
minutes that keeps missing is one log line per 10 minutes and a "Last problem" whose time is the first
miss's, not one that restarts at "just now". A miss is one of a fixed set of phrases (`CompatMiss`), so
nothing read from the page can reach the log. Recorded: a tab
strip that is wrong (more than one, no toolbar), a tab with no close button, no single tab marked shown, or the
script's answer not understood; a usage answer that can't be decoded or has none of the limits; a context answer
that can't be decoded or has no window or no turns with a size; a shallow frame with no status (a stopped session's too, for its card's reason), a plan waiting
with no plan file named, a plan file that isn't an object or has no summary; an Approve answered 404, 405 or a
200 that isn't `accepted`. Keep's two probes use two more phrases for their lines (`keepVersionsNotUnderstood` and
`keepFactsNotUnderstood`: a list of versions or a version's details that isn't the shape Capsid reads); nothing
records them yet. Never recorded, because they are ordinary: no tab strip (no tab is open), a
signed-out 401 (and a 401 with no Sign in card on the page, which falls back to a fresh sign-in code by design,
Daemon and sign-in; the probe says the button is not on screen now), a page that isn't up, a slow or failed read, `ok: false` from
usage, a session with no turns yet, a sub-agent waiting rather than the root, the daemon refusing an Approve in
its own words (`plan_already_approved`, `plan_frame_processing`, no plan awaiting), a stopped session that gives no reason.

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
  1. *Welcome.* The app icon (the one chosen in Settings, since 0.9.5), "Capsid keeps Claude Science in one window, and
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
     setting as Settings' update check), on by default since 0.9.7 (it was
     off) and left as it is unless it is changed: showing the page writes
     nothing. Its subtitle says what is asked of GitHub and that nothing
     about you or your sessions is sent.
- **Keys.** Return is the default action: Next, and Get Started on the last
  page. Esc closes. Get Started closes the window.
- **Look.** System controls: `.glass` Back, and the one `.glassProminent` in
  clay for Next / Get Started. Clay is also the current switch's tint; the page
  dots are neutral. Nothing animates but the specimen.
- **Demo.** `--demo welcome` shows the real window, with `--page N` (1 to 4)
  to start on a page. As with the other plain-window demos, `--quiet` keeps
  it from activating Capsid, and closing it records nothing: it never writes
  `hasSeenWelcome`. Its switch is the real setting, so don't click it.

## Efficiency (measured 2026-10-20)

Starting point, from the installed app on Sam's Mac while a session worked
and the panel played: 7.9% CPU on average (5.5 to 10.2 over 60 `top` samples
in 6 minutes), footprint 114 to 257 MB; 0% and 49 MB with nothing playing.
**That was not reproduced.** Everything below is a demo copy.

**Method.** `open -g -n Capsid.app --args --demo working -showLabPanel YES
-panelWhileFront YES --quiet -ApplePersistenceIgnoreState YES`, then
`top -l N -s 5 -pid <pid> -stats pid,cpu,mem,power` (the first sample dropped,
20 to 40 samples), `sample` and `xcrun xctrace record --template 'Time
Profiler' --attach <pid>` on the demo only. The Mac was shared with other
agents (load average 3 to 14), so runs of the same build differ by about
0.3 points; the comparisons below are interleaved pairs.

**What the demo is not, and what was not measured.**

- Only the first baseline run (below) had an unlocked, awake screen. The rest
  were taken with the lock screen in front, where macOS reports the panel
  occluded and the specimen holds a still. For those, a test-only shim (a
  dylib loaded with `DYLD_INSERT_LIBRARIES`, never part of the repo) made
  `NSWindow.occlusionState` read as visible, so the demo played. That
  measures Capsid's own CPU; it does **not** measure what the window server
  and the GPU do for a panel that is really on screen, nor the glass over
  changing content, nor the CVDisplayLink and RenderBox/Metal threads Sam's
  `sample` saw, which the demo's samples never showed. "No glass cost" below
  means no cost in Capsid's process, not none.
- The demo has no main window. Its toolbar capsule is a second playing glyph
  and a second clock: `--demo toolbar` measured 1.13% playing and 0.24% with
  the glyph still. It has no web view and no database polling (about 0.3%).
- The 5.5 to 10.2% was steady, with no quiet samples. The demo's playing cost is
  mostly bursts, one per scene (0.2% between them on the unlocked run). The gap to 1.2 to 2.4% is
  unexplained; Sam's `sample` points at rendering work that a live screen
  would show. Measure the next build as the 7.9% was: the installed app, a
  session working, `top -l 61 -s 6`, screen unlocked.

**Where the time goes** (Time Profiler, 150 s of the playing demo, 2.65 s of
CPU, 1.76%; the panel's own SwiftUI content is idle between ticks):

| | before | after the sRGB window |
|---|---|---|
| Core Animation commit (before, 1.34 s of it `CAKeyframeAnimation CA_prepareRenderValue` → `CGContextDrawImage`: copy and colour-convert every frame of a scene) | 1.53 s, 58% | 0.32 s |
| SwiftUI layout and updates (the 1 Hz clock) | 0.25 s | 0.22 s |
| Drawing the frames (`ImageRenderer`) | 0.21 s | 0.17 s |
| Everything else (thread start, malloc, RenderBox, …) | 0.62 s | 0.57 s |
| Total CPU | 2.65 s, 1.76% | 1.31 s, 0.87% |

By switching parts off in the demo (20 samples each, pre-fix): playing 1.83%;
specimen still, clock running 0.23%; clock off, specimen playing 1.44%;
specimen still and clock off 0.00%; the glass replaced by a plain material
1.91%. So the specimen's frames are about 85% of the cost, the clock about
0.2 to 0.4 points, and the glass nothing in-process. The memory swing is the
frames: a scene's frames are held as images for as long as it plays, and Core
Animation keeps its own copy of each (a 20 s scene at 64 pt: +72 to 78 MB in a
test harness).

**What changed.**

| demo, 20 to 24 samples at 5 s | CPU mean (range) | footprint |
|---|---|---|
| before, awake unlocked screen | 1.37% (0.2 to 2.2) | 31 to 141 MB |
| before, locked screen, shim (two runs) | 2.14% and 2.10% (0.9 to 3.6) | 45 to 138 MB |
| after, playing (two runs, interleaved with the above) | 1.25% and 1.10% (0.7 to 2.3) | 45 to 127 MB |
| after, holding still | 0.00% (0.0 to 0.1) | 23 MB flat |

The sRGB panel took playing cost down 44% (2.12% to 1.18%); the hold takes it
to nothing while nobody is at the Mac. Footprint while playing is
unchanged: the sRGB window does not touch the frames. A harness that commits a
20 s scene's 600 frames (64 pt at 2x) measured 51.8 ms for the commit in a P3
window and 11.3 ms in an sRGB one.

**Shared changes, made since 0.9.3** (`Shared/PlayedViews.swift` and
`Shared/Core/DatabaseWatcher.swift` are the droplet's: written there,
copied here by `Scripts/sync-shared.sh`):

- **A second of frames at a time, not a scene** (`PlaybackPlan`,
  `ChunkedPlayback`, `PlayedGlyphView.restart`). Before, `restart` drew all of
  a scene's frames, then gave them to one `CAKeyframeAnimation`: a 20 s scene
  was 600 images (about 75 MB with Core Animation's copies) committed in one
  60 to 150 ms stall of the main thread. Now:
  - a scene is cut into chunks of at most a second (30 frames); what is left
    of it is split evenly, so none is a sliver (61 frames are 21, 20 and 20);
  - each chunk is its own `CAKeyframeAnimation`, due at `sceneStart +
    firstFrame / fps` on the rotation's clock, worked out from the scene's
    start every time and never by adding chunks up, so a chunk begins where the
    last ended (to a microsecond) and a scene begins when the rotation says;
  - two chunks are held, the one playing and the one after it. A chunk is
    released 20 ms after the next has begun, and only then is the following one
    drawn, so a chunk is drawn about a second (0.98 s) before it is due and
    never three exist. The look-ahead at a scene boundary is therefore that, not the 1.5 s
    a whole scene needed: the next scene's first chunk is drawn as the last
    chunk of the scene before begins, and takes about 6 ms;
  - a restart (resize, new backing scale, occlusion, a new tint) draws only the
    chunk due now, at once, and the next after 5 ms, so the specimen is back
    in a few milliseconds, not after the rest of the scene is drawn;
  - each animation holds its last frame (`fillMode = .forwards`, not removed on
    completion) until it is released. A scene's frames are `Int(duration *
    fps)`, so its last can end up to a frame before the next scene is due, and
    a clock a hair out at any boundary is the same gap: before, that showed the
    layer's own `contents`, the scene's middle frame, for up to 33 ms.
    Checked offscreen with `CARenderer` and flat-colour frames (a scratch
    program, no window): chunks abutting exactly show no gap at the boundary
    (one frame colour up to 100.999999 s, the next from 101.0 s); a second chunk
    50 ms late showed the model colour for the 50 ms without the fill and the
    held last frame with it; a chunk begun 10 ms early takes over at once (a
    later animation wins); removing the first chunk while the second was
    waiting shows the model colour, which is why a chunk is released only after
    the next has begun;
  - a chunk wholly in the past when its turn comes (the main thread stalled,
    the clock jumped) is skipped, not drawn late; a draw that makes no frames
    waits for the chunk's length (50 ms at least) instead of spinning; a view
    that has gone ends the loop at its next draw;
  - the rate is a property of the view (`PlayedGlyphView.fps`, `PlayedGlyph(
    fps:)`, default 30), and `frames(of:from:to:size:scale:tint:fps:)` takes it.
    A chunk is a second of frames at that rate.
  - The rules are tested with a clock and waits of the test's own
    (`PlaybackChunkTests`): chunk boundaries line up, at most two are held, a
    chunk is released only once the next has begun, a stop or restart leaves
    nothing drawn or begun, a stall skips what is over.

  **Measured** (demo copies, `top -l 25 -s 5`, first sample dropped,
  `-specimenIdleSeconds 86400` so the hold does not interfere):

  | | CPU mean (range) | footprint |
  |---|---|---|
  | before, awake screen | 1.02% (0.7 to 1.8) | 46 to 127 MB, mean 65 |
  | before, locked screen, shim (two runs) | 1.20% and 1.19% (0.2 to 2.4) | 42 to 133 and 46 to 128 MB, means 82 and 77 |
  | after, locked screen, shim (two runs) | 0.81% and 1.09% (0.2 to 1.6) | 36 to 95 and 91 to 97 MB; flat at about 93 to 95 after the first 15 s |

  The screen was locked for all but the first run, so the shim of the earlier
  runs (a test-only dylib reporting every window visible, never part of the
  repo) played the panel. The runs were interleaved (before, after, before,
  after) on a Mac with a load average of 4 to 12, so the CPU figures are the
  same to within the noise: a commit now covers a second of frames, not a
  scene's, but nothing here shows a CPU gain. Footprint, however, did
  not do what was hoped:
  - the swing is gone (91 to 97 MB once settled, against 42 to 133 MB) and
    the peak is about 30 MB lower (97 against 128 to 133 MB, or 74 against
    105 to 110 above the 23 MB of a held panel: a third less, not the half a
    harness had measured);
  - but the level is flat at about 95 MB, which is **higher than the old
    average** (77 to 82 MB; the old app spent most of its time near 45 MB and
    went to 110 to 120 MB at each scene start);
  - `footprint` puts 57 MB of it in "Owned physical footprint (unmapped)
    (graphics)", where the old app had 1 MB between scenes and 49 to 57 MB at
    its peaks, and `heap` shows what is held in the process is what was asked
    for (two `CAKeyframeAnimation`s, 71 `CGImage`s). The graphics memory is
    owned by this process but lives elsewhere, and what keeps it at that size
    when a frame is drawn every second has **not been found**. Drawing
    each chunk as 15-frame sheets (an experiment build, not kept) did not
    change it (96 to 100 MB, one run), so it does not follow the size of the
    sheet; 10-frame sheets were not finished. Next: a run on an unlocked
    screen, with Sam's agreement to a demo panel, trying a chunk of 15 frames
    and releasing the `contents` image per chunk.
  - Not measured: the commit stall itself (no Time Profiler run) and a view
    playing at 15 fps.
- **Back off while the daemon is down** (`DatabaseWatcher`): see LabModel,
  "While the daemon is down". 1800 looks an hour at the log become about 64
  (arithmetic, not measured) and a log that appears is picked up when it is
  created. Behaviour with the log in place is unchanged.
- **Not made: frames in the screen's own format and colour space** (premultiplied BGRA in
  the display's profile) make the commit nearly free (1.8 ms) but move the
  conversion into drawing (the same total), so the sRGB window is the better
  fix and this one is not worth making.

**Background work, 0.9.3 (not measured).** Four sources of it were cut: the
Nidus task file has no timer unless a focused, eligible task is shared, and
does not rewrite for token-only updates; an obsolete Quick Open search is
cancelled rather than finished; a context read for the session left behind is
cancelled; and the phone page lets go of the thumbnails and observers of a
screen it replaced. No CPU or memory figure was taken for any of them. Three
more follow from the code review's follow-on list (Capsid's phone page, not
measured either): the page keeps a bounded number of left sessions and texts
instead of every one it visited; the conversation's rows are built one at a time
rather than all at once; and a read for a screen that was left, or a page put away,
is cancelled on the phone and, for a file, on the Mac as well (Capsid on your
phone, above), so the page's fetch for it stops.

## Files and ownership

```
Package.swift, DESIGN.md, Scripts/build-app.sh, Resources/Info.plist   (planner)
Sources/Bench/App/        BenchApp, Router, Theme, TimeSpan, SharedShims, SheetCost, PosterCost, Demo, Settings, AppIconChoice and AppIconPicker (the Dock icon choice), Welcome, Diagnose and Compat* (inventory, probes, breadcrumbs)   (planner)
Sources/Bench/Web/        daemon, web view, routing, pop-ups, browser/preview windows, downloads, find, notification bridge, page tabs (Close Other Tabs, Close All Tabs), LastSession (reopen where you were)   (web agent)
Sources/Bench/Lab/        LabModel, LabCard, LabPanelController, LabPanelView, LabStatusCapsule, SpecimenHold,
                          QuestionReply and ReplyWindow (a question, a permission request or a plan's
                          changes answered from its card), FailureReason (why a session stopped, on its
                          failure card)   (lab agent)
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
Resources/AppIconVariants The six icons Settings offers (0.9.5), one Icon Composer document each, cut
                          from that glyph by Scripts/make-icon-variants.py and compiled with AppIcon
                          by Scripts/compile-icons.sh; see App icon.
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
- [ ] a question, a plan and an error card show the status header and the card's full width, with no well, while Finished keeps its well (at Small and Large the panel's width changes between them); VoiceOver offers Open and Dismiss on a card (0.9.3)
- [ ] App icon (0.9.5): Settings → General → Appearance → App icon: each of the six tiles changes Capsid's Dock icon at once and the one in Settings' header; the chosen tile is ringed; the choice survives quitting and launching (the Dock shows it from the launch); Clay puts the bundle's own icon back; Finder, Launchpad and a pinned Capsid that isn't running keep Clay; the ⓘ says why; VoiceOver reads each tile's name and which is selected
- [ ] Settings on a short or scaled display: every tab fits the screen, and Specimens scrolls as one page when it is short (0.9.3)
- [ ] find, zoom and back/forward, in the main window and in a Browser window
- [ ] with Settings in front, Reload, Zoom, Find and Back/Forward are dimmed
- [ ] the window closes and reopens without losing state
- [ ] on-screen CPU with the panel playing, on a live unlocked screen (Efficiency's numbers are from a locked one)
- [ ] the specimen holds a still after ten minutes without input and plays again on a touch (or `-specimenIdleSeconds 20` on a demo; the first look is at once, the next within a minute)
- [ ] update check: with the switch off nothing asks GitHub (no request in Little Snitch or `nettop` for a day); Check Now and Capsid → Check for Updates… do; with it on, a first check comes within a minute and the next a day later, not at the next launch
- [ ] update check against a real newer release: the card comes once, Settings shows "Capsid 0.3.6 is available", Release Notes opens the in-app Browser on the release, and Install Update (Capsid in /Applications) quits Capsid, installs it and reopens it. Capsid started from a build folder offers no Install
- [ ] update offer (0.9.7): on a first launch with nothing stored the switch is on and a check follows within a minute; with a newer release out the card has Install…, the toolbar shows Update first among the trailing items (and no empty capsule once it is skipped or installed), its popover fits on one row of buttons with Capsid's own icon, Skip This Version hides the button, the card and the Dock item until a newer release, and the Dock menu starts with Install Capsid X… and opens the same alert. None in a demo
- [ ] the field guide: hover text in Settings → Specimens, the Topics menu, search ranking, and the panel's caption lines (Panel, "Name the specimen that's playing")
- [ ] Quick Open finds an older session: ⌘⇧O, type a word from the title (or project) of a session older than the ~25 recent ones; it joins the list a moment after the recent matches and opens; a hidden or sub-agent session is never found; Esc closes without leaving anything running
- [ ] Next Waiting Session: with three sessions waiting (one a plan), ⌥⌘↓ in the Claude Science window with the page focused, and again with the cursor in the composer, opens the one that has waited longest, then the next, then the third, then the first; the same from File → Next Waiting Session and the Dock menu's first item; a Later session is skipped until its reminder is due; the items are dim with nothing waiting; in a Browser window the keys reach its page
- [ ] activity list: with six waiting, one put off with Later, and two working, Later is its own group at the bottom of Needs you, Working shows whole with its clocks, and the Dock menu has the same order; on a short screen "N more" appears and opens in place
- [ ] acting from the list: hover a question's row, Reply… opens the reply window; hover a plan's row, Approve approves it (a throwaway session) and the row says Approved; hover a read-only tool's request, Allow Once and Deny; Tab to a row with full keyboard access on and the same buttons appear; with "Show plans, questions and requests on the card" off, no buttons and the row only opens; a Later row has only its bells
- [ ] reopen where you were: open a session, ⌘Q, launch: that session; go to the home page, ⌘Q, launch: the home page; `kill -9` Capsid while in a session, launch: that session; launch from a `bench://session?…` link of another session: that one, not the remembered; the remembered session gone (deleted, or another org active): the home page; sign out and back in on a remembered session: still on it
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
searched). Since 0.9.3 the filter takes out the sessions that don't match
before the project headings are built, so no empty "Recent sessions", "Older
sessions" or project heading (and no Show Older Sessions footer) is left; with
no match at all the window says "No matching files" ("Only loaded results are
searched. Clear the search to open more sessions.") with a **Clear Search**
button. Opening Results for a card's session clears an old filter first, so it
cannot hide the session asked for. A session's row is open once read with
results; one opened by hand to load stays open when they arrive
(`ShelfDisclosure`).

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
in the queue at a time, so at most two finished files wait in memory.

**The limit on a read** (since this change). The 30 s is one fixed limit for
every kind of read, and it is also the longest a read can hold its slot,
whoever still waits for it. It is fixed on purpose: the page already stops a
slow fetch at its own deadline (10 s, or 20 s for a whole 8 MB file) and
answers honestly ("Couldn't read this"), so Capsid's 30 s fires only when the
page's script never answers at all, and a limit scaled by the listing's size,
or one that counts progress, couldn't do better (the one call into the page
returns once, with nothing to watch in between). When it passes, every asker
of that read (a preview and a drop of one file, say) gets "Claude Science
took too long to answer" at once, with Try Again as for any failed read; the
page is told to abort the fetch; and the read's slot goes to the next read
even if its reader never returns. A reader that does return later is counted
(`ShelfTransfers.lost`) and forgotten: its answer is dropped, it frees no
slot (the limit freed it once), and it is never handed to an asker of the
same file who came after, who has a read and a limit of their own. Closing
the window leaves the limit running for the reads it cancelled, so two
readers that ignore the abort stop holding their slots 30 s after they
began, not never.

**Cancellation.** Each asker can stop waiting on its own. A read nobody wants
any more never starts if it was waiting, and is cancelled if it was running:
the shelf's reads carry a nonce, and the page files an `AbortController`
under it in the reader's own content world (`globalThis.benchArtifactReads`),
so `benchAbortRead(nonce)` aborts that fetch and no other. An aborted read
answers `cancelled`, never a failure; one stopped by the 10/20 s deadline is
still "Couldn't read this". Cancelling a Swift task is never taken for proof
that a fetch stopped: a read cancelled or timed out keeps its place among the
two until the page has actually answered or its 30 s limit passes, so closing
and reopening the window never runs more than two reads that can still
answer. (The page's own deadline is 20 s at most, so a read still out at 30 s
has no fetch of its own left running: what the queue stops counting is a
reader the page was told to abort and never answered, and a page in that state
could not serve a third read either.) Closing the window lets every asker go except a
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
Save All…) are written, and everything the shelf asks of their destination is
looked at, through a coordinator whose bookkeeping is on the main actor
(`ShelfSavedFiles`) and whose blocking calls each run on a queue of its own,
one at a time per destination and within a time limit (below). Each
window opening is a run; a write that lands after its run was deleted is
dropped, so a closed window's folder is never made again, and deleting an old
run never touches the new one's. Quick Look asks for a copy on the main
thread, so the shelf keeps a list of copies known to be whole, updated when
each write lands. Launch cleanup (`ResultsShelf.shared.cleanUpAtLaunch()`,
from BenchApp) deletes earlier runs' folders off the main actor; this run's
first copy is written after it, and it never deletes this run's folder. A
cached copy asked for while its existence is being checked is not handed over
if the window closes meanwhile: it belongs to the run being deleted (since
0.7.2).

**No file-system call on the main actor** (since 0.9.4). Until 0.9.4 the
existence checks were synchronous `fileExists` calls on the main actor: Save
All's names (one per candidate name, repeated while it looked for an unused
one, and again just before each write), the remembered folder a save panel
starts in, and Open and Reveal in Finder on a saved copy. A stat of a name on
a volume that had stopped answering (a network mount, a disconnected disk, a
File Provider) blocked typing, scrolling and closing the window before the
writer's limit could help, because only the writes had one. They now go
through `ShelfSavedFiles` like the writes, with the same limit, hold-off and
sentences (Saved files within a limit, below), so the main actor only ever
waits for an answer, never for the disk. What the Results code still does on
the main actor is handing a path to Finder or to the app that opens a file
(`NSWorkspace`, after the file was looked for), and asking for the Downloads
folder's path (a search-path lookup). `ResultsDiskCallsTests` lists the
file-system calls it scans for in Results/ (the file manager, `opendir`,
`Data(contentsOf:)`, `resourceValues`, a file URL made without
`isDirectory:`, `NSWorkspace`…) with where each may be, so a new one fails a
test.

**Saved files within a limit** (`ShelfSavedFiles`, since this change). A
blocking file-system call can't be cancelled, so each write runs on a queue of
its own and the shelf only waits for it: 15 s, and a second more for each MiB
of the file (23 s for the 8 MB cap), which leaves room for a disk to spin up
or a share to take a big file at 1 MB/s. A write that is only slow is not
stopped; one that makes no sound that long is a folder that isn't there.
When the limit passes the save fails with "Couldn't save it there: The folder
didn't respond. If it comes back, the file may still appear there." (a Save
All counts it with the files that couldn't be saved). The call is left to
finish, or never to: a file it writes late stays where it lands, and is not
recorded as saved. Saves go one at a time per destination, which is the
mounted volume under /Volumes a file is going to, else its folder, told by the
path alone because resolving a volume is itself a file-system call that
could be the one that hangs; so a save to another destination never waits
behind a dead one. The destination whose write timed out then refuses saves
at once ("The folder still isn't responding.") until its stuck call returns
(the folder answers again) or 30 s pass, after which one save is let through
to find out. That is the rule for the saves behind it: a Save All into a dead
folder costs one limit, not one per file. The write that found out fails
after its limit, the files already in hand fail at once, and the rest are
counted as couldn't be saved without being downloaded (so is a single Save to
that folder, refused before it downloads). Continuing instead
would cost a limit and a stuck thread for every file. (A second folder on the
same dead disk outside /Volumes costs one limit of its own before it fails
fast too.) A file name has at most one write out at a time and stays spoken
for until its call has returned, late or not. A Save of that name meanwhile
is refused ("An earlier save of this file hasn't finished."), and Save All
numbers its names around it (" 2"), as around a file that exists, so a write
that lands late never races another for one name; a name pinned by a call that
never returns costs one suffix. The writer's clock, the queue a call runs on
and the limits are injected, so the tests hold a write as a dropped volume
would and never sleep.

**Looks within the same limit** (`ShelfSavedFiles`, since 0.9.4). Asking a
destination something is a call like a write, and has every rule of one: its
own thread, a turn (looks go one at a time per destination, in turns of their
own, so a slow write to a folder never holds up a look at it, nor a look a
write: a Save All started while a write is out still settles its names and
starts its downloads, and its writes then queue behind that write), the
injected clock and limit (a look has no bytes, so 15 s; the look at a
remembered folder, which a person is waiting on before a panel opens, gets
3 s), and the destination's one hold-off when it doesn't answer. A look that
doesn't answer counts like a write that didn't: its caller gets "The folder
didn't respond. If it comes back, the file may still appear there.", the
destination refuses everything at once ("The folder still isn't responding.",
no call made) until the stuck call returns or 30 s pass, and one call is then
let through to find out. The looks are: whether a file is there (Open and
Reveal in Finder), whether a folder is (the remembered folder), and what a
folder holds (Save All's names). A look speaks for no name, since it writes
nothing, and one whose task is cancelled before its turn makes no call.
Cancelling does not stop a call already out, as with a write; it is waited
for until it returns or its limit passes.

Where a look's answer goes. A **save panel's** starting folder and **Open and
Reveal in Finder** wait for it, off the main actor (the window stays alive; a
second press of Save… while the first is being prepared does nothing). A
destination that doesn't answer counts as "not there" for the panel, which
then starts in Downloads, but not for a saved copy: that is kept, because the
file may still be there, and its row says "The folder didn't respond. …" or
"The folder still isn't responding." (without "Couldn't save it there:", since
nothing was being saved). The look at the remembered folder is the one a
person waits on, so it has a limit of its own, 3 s (`rememberedFolderLimit`)
instead of 15 s: the first panel for a dead remembered folder opens in
Downloads after 3 s, as if nothing were remembered, and every later one opens
at once while the destination is held off (30 s, or until the stuck call
returns); the hold-off is the destination's, as for any other call. **Save All's names** are settled before its
first download (Save All…, below); if the folder doesn't answer to the
listing, nothing is downloaded, the first file's row says "Couldn't save it
there: The folder didn't respond. If it comes back, the file may still appear
there." and the rest "Couldn't save it there: The folder still isn't
responding.", and all are counted "couldn't be saved": one limit for the whole
batch.

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
nothing is overwritten. The names are settled before the first download, in
the session's order, from one listing of the folder taken off the main actor
(`ShelfNamePlan`; until 0.9.4 a stat per candidate name, repeated as the
numbers climbed, on the main actor). A name is taken when the batch has it,
the listing has it, or an earlier write of it hasn't returned. A folder that
holds more than 10,000 names, or that can't be listed (no read permission on a
drop box, say), is asked about by name instead, one look at a time through the
same layer, with the same answer. Just before a write, in the same call as the
write, the name is looked at once more (`write(unlessExists:)`): if a program,
or a Save of the same name, took it since the plan, nothing is written, the
name is learned as taken, and the file takes the next free one, numbered from
the name it asked for, up to 8 tries. That is the final protection against
overwriting, and it costs no extra turn or limit, since the look and the write
are one call. (A Save… leaves it out: the save panel already asked whether to
replace.) Each file saved is recorded like a single Save, so
Open and Reveal in Finder work for it, with no Saved card per file. The row
says "Saving 3 of 7…", then "Saved 6 files. 1 was too big to save here."
with a Reveal in Finder button for the folder. Failures are counted ("2
couldn't be saved."), never named; each file's own row says why. One Save
All runs at a time. Closing the window stops what hasn't started; a file is
written only whole, once its download is complete, so none is left
half-written. A folder that stops answering fails the rest at once (Disk,
Saved files within a limit).

**Folder memory.** The folder last saved to is remembered per project, by
project id and never its name (`UserDefaults` `resultsFolders`,
`[projectID: path]`), and starts both the Save All… panel and the Save…
panel for that project's files. A folder that no longer exists is ignored
and the panel starts in Downloads. Whether it is there is asked off the main
actor (Looks within the same limit), so the panel opens when the answer is in;
a folder that doesn't answer within 3 s is ignored the same way, and its
destination is held off.

**Saving** (Save… and Save All…) and the temporary copies are the only ways
a result's content reaches the disk. Save… asks where, reads the file within
the 8 MB cap and writes it there; the panel's Saved card follows, as for a
download. **Open** and **Reveal in Finder** then act on that copy, once a look
(off the main actor) has found it still there; one that was moved or deleted is
forgotten and says so. Over 8 MB says to open the session and download it
there.

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
draws it). A grouped form in the 760 pt Settings window
(`settingsPage(height:)`, no taller than the screen: Settings, On a short or
scaled screen): with
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
   and Pair Another Device, and under it, on a line of its own, the address in
   secondary text (it would otherwise be cut short beside the button) with
   **Copy Link** next to it (since 0.9.0). Copy Link puts the address on the
   pasteboard as a URL and as plain text (`LinkCopy.copy(_:to:)`, the pasteboard
   given by the caller: the general one from Settings, a private one in tests),
   and reads "Copied" for 1.5 s; another press starts the wait again. The link
   is the one the pairing QR code holds, with its closing slash. A demo's
   Copy Link does nothing (`PhoneSetupActions.none`). Pair Another Device
   opens the pairing block under the row (its button becomes Cancel, which also
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

**Groundwork for a Mac-side reader (since 1.0; the reference reader, Reference).**
`readHistory(_:before:knownTotal:rows:nonce:)` and `readTurn(_:index:nonce:)` take two
optional arguments the phone's routes never pass, and every GET of the file gains the
same limits. `rows` (1 to 50, default 50; else `notAllowed`, and the page refuses it
before any fetch) is how many rows the page before `before` covers: `before=120,
rows=25` is one GET of `from=95&limit=25`; a first read (no `before`) is the tail's
`from=-12&limit=12` and then up to 38 more rows whatever `rows` says. A `nonce`
(letters, digits and dashes, 1 to 64) makes the page file the read's AbortController
in `globalThis.benchArtifactReads`, the artifact reader's own map, so
`abortArtifactRead(nonce)` ends the fetch and the page answers `cancelled`; cancelling
the task asks for the same (`HistoryReadAbort`), and a cancelled read always throws
`CancellationError`, even when the page answered at that moment. Every GET's body
(history, turn and Keep's showing read, which share the fetch) is streamed and
stopped at 2 MiB (2,097,152 bytes, `HistoryReaderScript.bodyCap`), and a
`Content-Length` over it is refused unread; either way the page answers `tooBig`
(`HistoryRead.tooBig`), which the phone's routes take as unreadable (503) and Keep as
unreadable. The page yields once before it parses each body and once before it
projects (`requestIdleCallback` with a 1 s timeout when there is one, else
`setTimeout(0)`, else not at all), so a read doesn't hold the composer's thread in one
block. The trim that holds a page to 60 items and 64 KB counts each item's JSON once
(it stringified the whole remainder for every row it dropped), with byte-identical
output, pinned in the tests against a copy of the old rule. A page read answers
`timing` beside the page: `fetchMs` (request to body read, summed over the GETs),
`parseMs`, `projectMs`, `rawBytes` and `rows` (the messages in the page), whole
numbers from `performance.now()` (zeros without it; the byte and row counts stay).
Swift takes it strictly (all five whole numbers of at least 0, else none, never a
reason to refuse the page), and `readHistory` logs one `.notice` line in category
`reading`, `history read: fetch N ms, parse N ms, project N ms, N bytes, N rows`,
numbers only.

**Which message shows a version (Keep, since 1.0).** One more op beside the projection, in the same file and
on the same allowlisted GET and 15 s: `benchFindShowingMessage(page, base, versionIds)` takes one page of raw
rows and answers the newest assistant message that shows any of an artifact's version ids, as
`{i, at, text ≤ 20,000, how, v}`, or null. `how` is the first of four that fits the message: `inline`
(`{{artifact:<v>}}` or `?v=<v>` in its text), `image` (an `_artifact_refs` value for an id whose key is the last
segment of a `![…](src)` in the text), `mention` (any `_artifact_refs` value for an id) or `saved` (a save or run
tool's result lists the id in `artifacts[]`: the next assistant text after it, before the user's next turn,
else the message that made the call). Each message takes its best way, and the newest message with one wins.
It reads text blocks, tool names and ids, a save or run result's `artifacts[].version_id` and
`_artifact_refs`; never thinking, tool input, any other result or images. A shape that doesn't match is
unreadable, nothing shown is `null`. `WebContainer.readShowing(frameID:versions:near:nonce:)` walks the
pages back from the newest, one script run each (the last 50 rows, then the 50 before each, every older page
covering 6 rows of the one before it again so a save's reply is on the page that has the save), at most 6
pages, and stops early when a page's newest `_ts` is older than `near`, the oldest version's time (a reply
that shows a figure follows its save). It answers `found`, `notFound` or `unreadable`. The page files an
`AbortController` under the caller's nonce in the artifact reader's own map, so `abortArtifactRead(nonce)` and
cancelling the task end the fetch and the walk (a `CancellationError`). The page's fetch and its tail-then-
earlier row read are the history page's own, shared.

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
- **Keep's reads, since 1.0.** The same reader makes three more GETs for Keep, each from typed arguments,
  checked in the page and in Swift, `no-store`, and projected in the page so nothing else reaches Swift. Ids
  in all three are exactly `[0-9a-f-]{36}` (`PlanCheck.isUUIDLike`), so `/api/artifacts/<id>/versions` can't
  be read as `/api/artifacts/versions/…`. A 404 is `missing`, a 401 `lost`, a body past its cap `tooBig`.
  - `.versions(artifact:)`, `GET /api/artifacts/<36>/versions`: a bare array, oldest first, the newest 500
    kept as `{v, n, frame, mime, size, at, parent}`; `file_path`, `agent_name` and `language` stay in the
    page. Body ≤ 1 MB.
  - `.facts(version:)`, `GET /api/artifacts/versions/<36>?include_metadata=true`: kept as `{v, a, n, name,
    mime, size, at, sha, upload, code, codeCut, env}`. `sha` is 64 hex digits or null; `code` is the
    reproduction code cut at 256 KB of UTF-8, never inside a character, and `codeCut` says so; `env` is the
    snapshot's name, Python and at most 2,000 packages. The answer must be for the version asked, because an
    artifact's id in that slot serves the artifact's latest version: the page and Swift both refuse another
    `version_id`. Body ≤ 2 MB.
  - `.lineage(version:)`, `GET /api/artifacts/versions/<36>/lineage?slim=1`: kept as `{v, code, codeCut, desc,
    lang, pending, unavailable, cells, env, mapping, inputs}`, with at most 200 inputs `{v, a, name, file, how,
    inferred, fetchable}` (`file` is a workspace path's last segment; `inferred` is `consensus: ast_only`;
    `fetchable` is both ids). The page refuses a body whose `messages`, `environment_snapshot` or
    `interactions` isn't null (they are, under `slim=1`). Reading it can start Claude Science's own code
    reconstruction, so Diagnostics never does. Body ≤ 2 MB.
  The list, the thumbnails, the downloads and the phone's routes are as they were.
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
- **A phone that hangs up drops its read (since 0.9.3).** After a read's request
  is in, the server keeps listening on its connection for the end (a FIN or a
  reset; bytes that arrive are ignored). If it comes before the answer is
  sent, the task answering is cancelled and the connection closed
  (`RemoteServer.hungUp`). This holds for the reads (`RemoteRoute.isCancellableRead`: a
  session, its live text, its artifacts and files, projects, a project's sessions,
  history and turns), never for a write (an action, a photo, a new session, push,
  Open on Mac and the rest answer to their end whatever happens to the connection).
  An artifact read, which is the one that holds a transfer, is made abortable
  (`ArtifactReadAbort`, the results shelf's own): cancelling its task asks the page
  to abort that read's fetch by its nonce (`benchAbortRead`), so the Mac stops
  reading the file, and the read returns as `cancelled` (the route would say 503 to
  a phone that is no longer there). The transfer is given back once the page's read
  has actually ended, not when the connection goes, as before. The other readers
  (session, history, turn, live) have no abort in their page scripts: cancelling only
  stops one that has not yet started its page read (history and turn check before
  asking the page) and the encode and send. They are bounded by their own
  deadlines: 8 s for the session and live readers, 15 s for history and turn
  (since 1.0 a history or turn read made with a nonce aborts too: the reference
  reader's, above). That Tailscale Serve closes its connection to Capsid when the phone
  aborts is expected of its proxy (it ends the upstream request when the client
  goes) and was not seen with a real phone; the tests hang up a real loopback
  socket both ways (FIN and RST).
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
  parameters (its `timeout` counts from the moment a read is queued, since
  0.9.3; see Quick Open); ids and the cursor are still checked by shape first,
  and `q`'s
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
still fails shows its icon. A screen or list that is replaced lets go of the
thumbnails it removes (`replaceContents`, since 0.9.3): each leaves the
intersection observer, a load still waiting for one of the two slots is withdrawn
without taking one, and a retry timer is cleared. A transfer that has started
keeps its slot until it finishes, so leaving a screen never raises the two at a
time; an image reused or moved into the new tree stays live. Downloads are
fetched first and then saved from the bytes, so a refusal is a sentence under the button ("Another file is
still coming. Try again in a moment.") and never a saved file holding Capsid's
answer. Every map the page keys by an id has no prototype, and an address
naming a project or file `__proto__`, `constructor` or `prototype` opens Now.

**Reads that belong to a screen stop with it (since 0.9.3).** A read for a
screen (a session, its history rows, one earlier page of them, a whole turn, its
live text, its artifact list and its files' texts; a project's sessions) carries
the signal of a scope named for what it is about: `s:<session id>` for a session
and everything under it (its artifacts and its files too, so moving among a
session's own screens aborts nothing), `p:<project id>` for a project's list.
`/api/state`, `/api/me`, `/api/projects` and `/api/push` are not scoped: they are
the app's own and small. When a screen is left (`enterRoute`), the layout changes,
or the page is put away (`onHidden`), every scope no screen needs is aborted
(`syncScopes`, `abortScopes`): the iPad's sidebar keeps the project list it shows
beside an open session. An aborted request is cancelled (`AbortController`, where
the browser has one), and the connection it was on closes, which Capsid hears (How
the server does it, below); one still waiting for one of the two slots is withdrawn
without a request, and a 429's wait ends at once. It is `Aborted`, not `Down`, so
it never shows the offline screen, an error on a list or a "Couldn't load" under
Conversation; its loader puts back what it had taken (the busy flag, a
"Loading…" placeholder) so asking again works, and nothing is left looking like
a read under way. An aborted request keeps its slot until it has ended, so the two
at a time never rise. When the page comes back, `enterRoute` asks again for what
the screen was waiting on. Never aborted: any POST (a message, an answer, an
approval, a photo, Open on Mac, Unpair), `send`, and a download or Share, which
the person started (`getFile` takes its turn in the queue and keeps it). A page
put away also withdraws images still queued for a slot (`parkImages`), and asks
for them again when it is back; images already loading keep their slots.

**What the page keeps of screens left (since 0.9.3).** Reads stay in memory so
that going back shows them at once, but a Home Screen app lives for days, so what
is not on screen is kept within a budget, the one shown least recently going
first (`trimCaches`, on entering a screen, when a read lands and when the page is
put away; the clock is a count, not a time). The numbers are for bounding growth
in a long-lived page, not for memory pressure (a character is 2 bytes at most in
JavaScript, so the sessions' share is about 3 MB and the texts' about 1.5 MB):

| What | Kept besides the one open | Why |
|---|---|---|
| A session's read, its history rows (and whole turns from Show all) and its artifact list | 8 sessions and 1,500,000 characters of JSON between them | A history page is under 64 KB, so a dozen pages is about 0.8 MB: one long conversation is most of the budget; 8 is the sessions one goes back and forth among |
| A file's text, markdown or table | 4 files and 768,000 characters | A text is read up to 256 KB and a table's JSON can reach 1 MB: one big table may push the others out, which is fine |

The open session and file are kept however big. A session or text with a read
under way (a "Loading…" placeholder, earlier rows coming, a turn, a list, a
message or answer on its way) is kept until that ends. Never touched, by
construction: `S.ui` (what the person typed or chose on a session: drafts, a
photo made ready, answers to a question, a message's retry id) and
`S.newSess` (a new session's text and photo), which are not reads; and `S.files`
(a file's name, kind and size, about 200 bytes each), so an address naming a file
known only from a history row still opens after its session was evicted. Sizes
are worked out once per object (`weigh`, a `WeakMap`), history rows being
kept as the same object while a read says the same of them.

**The conversation's rows are made one at a time (since 0.9.3).** The history
used to sort and build every loaded row whenever anything about it changed (a
"More" tapped, earlier rows arriving, a whole turn loading). `setHistory` keeps
the list and each row between updates, by index, with what the row was drawn
from (its item, whether it is open, its whole text, whether that is loading or
failed, the day for a row with a time), and builds a row again only when that
changed, then puts the elements in order without touching the others
(`syncChildren`); a row whose text has an image link is built each time, so it
finds files listed since. The top of the list (earlier rows, loading, failed, the
beginning) is made again only when it changes kind, which is what the intersection
observer on it waits for. Rows that leave have their images let go
(`_disposeFileImage`), as `replaceContents` does. Windowing (building only the rows
near the screen) is not done: it would cost the scroll anchoring and find-in-page,
and nothing measured says it is needed.

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

## The 1.0 windows' surfaces (App/SolanumSurface.swift, since 1.0)

The feature windows 1.0 adds are drawn after the Capsid 1.0 mock-ups (a Design
canvas, "Capsid 1.0 mock-ups"), which Sam chose over the system's grey chrome
for them: the first reference window, in the system's toolbar glass and grey
bordered buttons, read as generic. Settings, menus, popovers and the main
window stay the system's own (Look, native over brand). The surfaces are
Solanum's tokens, light and dark: the page ivory #FAF9F5 (slate #141413),
raised cards and controls white (#262624), ink #141413 (#FAF9F5), muted ink
#5E5D59 (#B0AEA5), hairline edges at 15% (18%) and control edges at 30% (32%),
never shadows; the title bar a shade off the page with a hairline under it.
Type is the system font at the mock-ups' sizes: reading text 14 on 21,
captions and labels 12. Two controls: a pill (30 pt, or 26 under a figure),
white with a strong hairline and ink words, and a round 28-pt button for
chevrons; both dim when disabled and darken by a hairline's tint when pressed.
Clay stays what it is everywhere: one fill for the one action that asks, and
never on a window that only reads.

## Keep (Kept/, since 1.0)

Claude Science makes many drafts and versions, and a week later the one you
meant to use is hard to find. **Keep** pins down the real one, with the text,
data and code that go with it, in a folder you own; while writing a paper,
the **Kept** window puts those results beside the manuscript. Sam's biggest
complaint about Results, and 1.0's first feature.

**Entry points.** In Results, every file row has a `checkmark.seal` button
and **Keep…** in its context menu; **File → Keep…** (⌥⌘K) acts on the
selected file. **File → Kept…** (⇧⌘K) opens the Kept window; a kept
result's row in Results opens it on that result with a double-click. Neither
key is one the page uses (it takes ⌘K for its search). None of it works in a
demo but `--demo kept`.

**The reads** (Remote/ArtifactReader.swift, Remote/HistoryReader.swift; the
1.0 spikes' S2 found them). The list Results shows (`GET
/api/frames/<root>/artifacts`) gives each artifact's **latest version
project-wide**, which another session may have made, so Keep never takes the
version from it. It reads, in the page and through the shelf's queue at
foreground priority:

1. the picked file's facts, `GET /api/artifacts/versions/<v>?include_metadata=true`
   (the artifact id, the name, the daemon's sha256; an artifact id in that
   slot quietly serves the latest version, so the answer must name the id
   asked for);
2. the artifact's versions, `GET /api/artifacts/<artifact>/versions` (oldest
   first; `file_path` never leaves the page);
3. the answer that shows one of them: the newest assistant message whose
   text has `{{artifact:<v>}}` or `?v=<v>`, else whose `_artifact_refs` maps
   a `![…](name)` in its text to one of the versions, else any ref, else the
   save step that made it, walking the session's message pages backward from
   the newest, at most six (each re-reading six rows of the one before, so a
   save at a page's end finds its reply: about 270 rows), and no further
   back than the oldest version's time (a showing reply follows a save). None
   found: the session's last answer, labelled as such;
4. the chosen version's provenance, `GET /api/artifacts/versions/<v>/lineage?slim=1`
   (the inputs with their artifact and version ids, the mapping's state, and
   the script, which is the page's own "Claude-generated reconstruction", not
   a recording of what ran), then each input's facts for its name and size.
   Reading lineage can start the daemon's reconstruction when the version has
   none yet (a model call), so it is read once per sheet and polled six times
   five seconds apart while `pending`, and it is never a Diagnostics probe.
   The thumbnails in the strip are the shelf's own 120-px read.

**The sheet** (Kept/KeepSheet.swift, Kept/KeepModel.swift): a `.sheet` on the
Results window, 600 wide (its minimum width rose from 520 to 620 for it), a
grouped `Form` with one clay button. Minimal on purpose: the common keep is
Return.

- **Name**, the file name without its extension, selected on open; Return
  keeps.
- **Which version is the real one**: a strip of tiles, oldest to newest, "v3 ·
  8:09" under each picture (drawn on paper, never above its own pixels), the
  one Claude's answer shows pre-selected and labelled "In the answer" in
  secondary (a fact, not a demand; a version that vanished reads "Gone").
  The chosen tile has a 2-pt `.primary` stroke: not clay, which is spent on
  Keep and would read as a second primary; not the accent, a second hue; and
  thickness carries the state under Increase Contrast. ← and → move the
  choice. The footer says which and why: "Version 3 of 4, from 8:09. It's the
  one Claude's answer shows, at 8:12."
- **Keep with it**, three checkbox rows whose subtitles say what they hold,
  and, when they can't be ticked, why, in the page's own words where it has
  them (`KeepRules.rows`): *What Claude said about it* ("“All plates passed
  except plate 7…” · the answer at 8:12"; the fallback is titled *What Claude
  said last*; "Capsid couldn't find the answer that showed this version. The
  figure and its provenance can still be kept."); *The data it was drawn
  from* ("z_prime_by_plate.csv · 4 KB · listed in its provenance"; "No source
  data recorded." with an ⓘ saying Capsid doesn't guess from file names;
  "Claude Science is still working out what this was drawn from. Try again in
  a minute."; inputs found only by static analysis are offered off, tagged
  "inferred", with the page's tooltip behind the ⓘ; inputs over 8 MB or not
  saved in Claude Science are listed and not copied); *The code that drew it*
  ("z_prime.py · 2 KB · Claude-generated reconstruction"; "Generating
  reproduction code…"; "No reproduction code — <model> is off for your
  organization"; and the page's other sentences). A version you uploaded
  shows one line instead of the data and code rows. There is no "raw input"
  row in 1.0: the list projection drops `is_user_upload`, so Capsid can't tell
  uploads apart without a read per file; a later cut can add it.
- **Collection**, beside the name in the first section: a pop-up of the
  root's subfolders plus New Collection… (an alert with a name), defaulting
  to the collection last kept into for this project (`keptCollections`, by
  project id), else the project's name, marked "(new)" until it exists. That
  section's footer names the destination and what lands: "Into
  ~/Documents/Kept/Assay development/Fig 2B · Z′ by plate: z_prime.png, data,
  code and a README.md. About 92 KB." A taken name is said before Keep: "…is
  already kept in Assay development, so this one will be “Fig 2B · Z′ by plate
  2026-10-22 0912”." The Kept folder itself is in Settings → General → Kept,
  not in the sheet: three sections, no scrolling at 740 points.
- The status line: "Nothing in Claude Science changes. Capsid copies what's
  ticked and checks each file." Then Cancel (Esc) and **Keep** (Return,
  `.borderedProminent` in clay), dimmed until the versions are read and a
  version is chosen.

**What a keep does** (`KeepModel.perform`). The folder is made hidden beside
its destination (`.<Name>.keeping-<uuid>`, so a Keep in progress never shows
as a result) by `KeptDisk.prepare`, which also settles the name: `<Name>`, or
`<Name> 2026-10-22 0912` when it is taken; Keep never overwrites. Each ticked
file is fetched through the shelf's queue within the 8 MB cap (the figure
first), its sha256 computed (CryptoKit) and compared with the daemon's
checksum when it has one (a mismatch is logged, not refused: a reference
artifact's checksum can be stale), and written atomically; the script is the
reconstruction's text with `{{artifact:<v>}}` rewritten to `../data/<name>`
for the inputs that were kept (the daemon's own script bundle does the same
to its `inputs/`). README.md is written last and the folder renamed into
place. "Keeping 2 of 4 files…" meanwhile; Cancel stops the reads and deletes
the hidden folder. A figure that vanished mid-way: nothing is kept, the tile
reads "Gone", and the sheet says "Version 3 isn't in Claude Science any more,
so nothing was kept. Choose another version, or Cancel."; never another
version in its place. A file that couldn't be copied is listed under
`missing:` and the sheet stays: "Kept 3 of 4 files. The data it was drawn
from wasn't copied.", the row saying why in clay-text, with **Try Again**
(copies only what is missing, into the folder, and rewrites the README),
**Show in Finder** and **Done**. Everything copied: the sheet closes and the
Kept section shows the new row; no card, no toast.

**On disk** (Kept/KeptFolder.swift, Kept/KeptReadme.swift, Kept/KeptDisk.swift).
The root is `~/Documents/Kept` (`keptRoot`, a path; Sam's call between it and
`~/Lab/Kept`: Documents is where a Mac keeps what a person owns, in Finder's
sidebar and Spotlight's scope, at the price of macOS's one-time Documents
prompt, which `NSDocumentsFolderUsageDescription` words as "Capsid keeps the
results you choose in your Documents folder."). The layout:

```
<root>/<Collection>/<Name>/
  <the figure's own file name>
  data/…
  code/…
  README.md
```

README.md is YAML front matter the Kept window reads (`capsid_kept: 1`, the
name, when, the project and session as ids and names, the figure with its
artifact, version, index and sha256, the files with their roles, what is
missing and why, the Claude Science and Capsid versions) and readable
sections: the name as a heading; **Your legend** (empty, with an HTML comment
saying where to write it); **What Claude said**, quoted, with "From Claude's
answer at 8:12 AM on 22 October 2026." (dates written out, since the file may
be read anywhere; the fallback says so); **Where it came from**, the session
as a `bench://session?project=<id>&frame=<id>` link (`Router` now checks both
ids before building an address from them), the project, "Version 3 of 4 of
z_prime.png, kept on 22 October 2026 at 9:12 AM by Capsid 1.0, from Claude
Science 0.1.70"; **Not copied**, only when something is; and one line of fine
print: "Capsid changes only the “Your legend” section of this file, and only
when you edit it in the Kept window." The parser is strict and fixed-shape:
it reads what the renderer writes and nothing else, and a round trip is
byte-identical. Every disk call runs off the main actor on one utility queue
within a time limit (15 s plus 1 s per MiB per write, 15 s per look), with
the saved files' sentences for a folder that doesn't answer;
`KeptDiskCallsTests` allows file-system calls in `KeptDisk.swift` alone (and
the Finder and open calls the windows make, which look at nothing). A root
that isn't there yet (a new Mac) counts as empty and is made by the first
keep; only a root whose parent is gone, or a file in its place, is "The Kept
folder isn't there." The folder's own README and hidden names are refused as
file names, and a rename that would replace a folder is refused too.
Nothing about sessions is written anywhere but inside kept folders, and
there is no index: the folders are the record (`KeptIndex` scans
`<root>/*/*/README.md` when a window opens or a keep lands, skipping
dot-folders and anything without the marker, and never in the background).

**The Kept section** (Results/ResultsWindow.swift): the first section of
Results' list, the five newest kept results (a 36-pt picture on paper, the
name, "Paper draft · Oct 22"), then "Open Kept" with the count when there are
more. A double-click opens the Kept window on it; the context menu has Open
in Kept, Show in Finder and Open Conversation; the row drags the figure. The
filter narrows it by name and file name. With nothing kept the section is
left out: the seal on every row is the invitation.

**The Kept window** (Kept/KeptWindow.swift; File → Kept…, ⇧⌘K): a
`NavigationSplitView` with the system toolbar (a collection pop-up, Show in
Finder, Open Conversation, search over names, legends and Claude's words),
960 × 640, minimum 720 × 480, frame `CapsidKept`. The sidebar lists results
by collection, newest first, a 40-pt picture each, with the root and the
count at its foot. The detail: the figure, on paper, which drags into Pages,
Word or Keynote and previews with Quick Look on a double-click or Space; the
name; "Plate reader QC · Assay development · version 3 of 4, kept Oct 22";
**Copy Figure** (the file and its image on the pasteboard) and **Copy
Legend** (your legend, else Claude's words; the tooltip says so), each
reading "Copied" for a moment at its own width; **Your legend**, a text field
that saves itself a second after typing stops into the README's one section,
refusing when the file changed in another app ("README.md was changed in
another app." with Use Mine and Use Theirs) and never writing over an outside
edit unasked; **What Claude said**, quiet, with its attribution; and the
files with their sizes, each draggable, plus what wasn't copied. Nothing in
the window needs you, so nothing in it is clay. There is no Delete: nothing
in Capsid destroys what you chose to keep (Finder does).

**Thumbnails** (Kept/KeptThumbnails.swift): kept files are on this Mac, so
Quick Look draws them (`QLThumbnailGenerator`) at the size asked times the
screen's scale, off the main actor, kept by path within 24 MB and let go when
the window closes; a file iCloud has put away shows its kind's symbol and is
never fetched for a picture.

**Privacy.** Kept folders are files you chose to save, within the README's
promise, which now names them. The reads are the page's own, allowlisted
(`CompatInventory`, feature `keep`); the versions and facts reads are probed
live on the shown session's plan artifact, lineage only when used.

**Demo.** `--demo kept --step sheet` (the sheet filled from made-up reads, in
a plain window), `sheet-partial` (after a keep in which the data couldn't be
copied), `window` (the Kept window on three made-up folders in a temporary
root) and `window-empty`. The root is deleted when Capsid quits.

**Tests.** `KeepPlanTests` (the pre-selection, the tiles and their footer,
every row's sentence and availability, the plan from the choices with
nothing guessed, unique safe file names, the script's rewrite, the
destination and outcome sentences, the record naming the chosen version),
`KeptReadmeTests` (round trips with "Z′", the strict parser, a legend edit
leaving every other byte alone), `KeptDiskTests` (the layout, the dated
collision, abandon, scan, the outside-change refusal, the disk-calls scan),
the reader tests for the three shapes and the showing op against a fake
`fetch` (`RemoteArtifactsTests`, `HistoryReaderTests`), and the inventory's.

## Reference (Reference/, since 1.0)

A reply beside the work. A session's conversation lives in Claude Science's
window; when the user is writing from what Claude found, they want one reply
next to the document, its figures first, not the tab behind it. Open as
Reference opens a small read-only window on one session with Claude's newest
reply in it, and the replies before it a step away. It reads the way the phone
reads a conversation (Capsid on your phone → History) and writes nothing.

**A reply** is everything Claude did in answer to one of the user's messages:
from that message to the next, its words (every turn of Claude's and every
message it sent mid-run, in order) and every picture it made or showed on the
way. A figure sits on the tool step that made it, not on the words after it,
so the reply gathers the files of its steps, turns and messages, keeps the
images (`ArtifactGate.thumb`), one per artifact (the last version, in the
place the first appeared), and leaves out the user's own uploads; 24 at most.
A stretch with neither words nor figures (steps only, a plan, a question) is
no reply. A reply's id is its last row, which stays the same as earlier pages
are read (`ReferenceRules.answers`). The first version of the window showed
each of Claude's turns alone and only the turn's own files: on a real session
that meant narration ("Let me load the data.") as answers and no figures at
all, since the figures were on the steps.

**Opening.** Three doors, all on a session: Quick Open (⌥↩ on the field opens
the highlighted session as a reference instead of in the main window, caught
with `onKeyPress` as the arrows are, since Option-Return in a text field
inserts a line break and never submits; and every row's context menu has Open
as Reference), the activity list (every session row's context menu and VoiceOver
actions, `menuActions` on `ActivityRow`, never a hover button), and a card's
Later menu (Open as Reference under Open in Capsid, on the cards that name a
session). Opening a session as a reference leaves its cards and reminder as
they are; Open Conversation inside the window goes through
`Router.open(session)`, not `LabModel.open`, for the same reason. One window
per session (`ReferenceWindowController.windows`); opening it again brings it
forward.

**The window** (`ReferenceWindow.swift`), drawn as board 7 of the Capsid 1.0
mock-ups has it, on the 1.0 windows' Solanum surfaces (`SolanumSurface.swift`,
Look). A normal window, 440 by 620 at first (`ReferenceWindowController.size`,
no smaller than 360 × 320), its frame remembered under one name
(`CapsidReference`) when it closes (a demo's never), so the next opens where
the last was (a second one at the same place steps down). The title bar is the
page's own band (transparent, full-size content, a hairline under it): the
session's title, centred, over "<project> · read only" in muted ink, and at
the trailing edge two round chevrons, Earlier and Later, with ⌥⌘← and ⌥⌘→ on
the buttons themselves, so the keys work only while this window is key and
never reach the page (⌥⌘↓ is Next Waiting app-wide). They are SwiftUI toolbar
items with the shared glass hidden, and the system title is removed from the
toolbar (`toolbar(removing: .title)`): beside the centred one it pushed the
chevrons into the overflow menu. The page, ivory (slate in the dark), 24 pt
from the sides and 20 from the top, 14 between its parts: the caption
"Claude's answer · 8:47 · 2 of 3" (the time alone on the day it is, else the
day and month too; the place only once row 0 has been read, since before that
it would count only the answers read so far), with a small spinner while a page
is read; what the user asked, muted, three lines at most; the figures, each on
a white card the page's width with a hairline edge and 10-pt corners (800-pixel
pictures from the daemon, decoded into a store of the window's own, 48 MiB,
`ReferenceModel.figureStore`; shorter than 520 pt; a quiet 3:2 card with a
spinner until the picture comes, a photo glyph if it can't be read), its file
name under it and a small Keep… pill (and Keep… and Open Conversation in its
context menu); then Claude's words as selectable text at 14 on 21 in Solanum's
ink (`AnswerStyle.reference`; links in ink, underlined in clay) in an
`NSTextView` sized to its text and lined up with the figures (no inset), so the
page scrolls as one (`ReferenceTextView.sizeThatFits`). At the foot, under a
hairline, two pills: Copy with Source (⇧⌘C) and Open Conversation. The first
version said "Open in Claude Science", which named the wrong app: the
conversation opens in Capsid's own window. Nothing in it is in the clay: the
window reads, it never asks. Window → Keep on Top (`ReferenceCommands`) floats
the key reference window (`level = .floating`), dim unless one is key; it is
the only ordinary window that floats (the Reply window and the specimens panel
are panels, floating by nature).

**Copy with Source.** The selection, or the whole answer as drawn, then a
blank line, then `— Claude, in “<session>” (<project>), 22 October 2026, 8:47`
(Keep's date and time words) and `bench://session?project=…&frame=…` on the
line after, which opens the session in Capsid. Line separators the renderer put
in for hard breaks go back to newlines. The button says Copied for a moment.

**What is read** (`ReferenceModel.swift`). Pages of the session's history,
back from the newest end: the page's first read (its 12-row tail and the rows
before it, 50 in all), then 25 rows a page (`ReferenceModel.rows`), through
`readHistory(_:before:rows:nonce:)` and `readTurn(_:index:nonce:)` (the
groundwork, Capsid on your phone → History). The rows read are kept as items
and the replies worked out again after each page. A look reads pages until
what it wants is in, row 0 is reached, or eight pages were read
(`pagesPerLook`): on opening, the newest reply and the user's message that
began it (a long run of steps can fill many pages); on Earlier at the oldest
reply read, a whole reply before it, which is then shown unless the user moved
meanwhile; on Earlier onto a reply whose start is unread, that start. A look
that ends at eight pages shows what it has, and Earlier carries on. With no
reply the window says "No answer in the newest messages" (Earlier looks again)
or, at the start, "No answers yet". A turn's text is cut at 2,000 characters
on a page; each cut turn of the reply shown gets a whole-turn read (≤ 20,000),
once per row, kept by row and never applied to another; while one is in
flight the page says "Reading the rest…", and if one fails, "Part of this
reply couldn't be read." Every read is dropped once the window closes (`close`
bumps a token and cancels the tasks; a read that lands after the token moved
changes nothing). A read that fails says "The conversation couldn't be read.
Claude Science may not be up." with Try Again; a page over the reader's 2 MiB
cap says it is too large to read here and to open the conversation instead.

**When it reads** (`ReadingGate.swift`). The reads run in the page, on the
page's main thread, so each costs the user a few milliseconds of typing. The
gate runs them one at a time, in order, across every reference window; none
starts within 400 ms of a key press in the main window (a local key monitor
notes the time and passes the event on); a read waits at most 2 s all told and
then goes. The rule is pure (`ReadingGate.pause`), in whole milliseconds.
Cancelling the waiting task cancels the read with it, and the nonce makes the
page abort the fetch. The page measures each read and `readHistory` logs one
line at `.notice` in category `reading`, numbers only; the demo's numbers are
made up, so the cost is measured on a real session or not at all.

**The text** (`AnswerMarkdown.swift`). The window shows an answer through
`AnswerMarkdown.render`, a pure, nonisolated renderer: Foundation parses the
Markdown with full syntax and the renderer lays it out as one paragraph per
block, in system fonts and semantic colours. It shows headings, paragraphs,
lists (a bullet or the item's own number, hanging 20 pt a level), code blocks
(the monospaced font on a faint ground that follows light and dark), block
quotes and thematic breaks, with bold, italic, inline code, strikethrough and
links inline; only http, https and mailto links stay links, and any other link
keeps its words as plain text. What a text view can't show becomes a
placeholder paragraph in the secondary colour: a table ("Not shown here: a
table."), an image ("Figure: <file name>") and a raw HTML block (its source).
Each placeholder carries the `local.sam.bench.answer.unsupported` attribute (an
`AnswerUnsupportedBox`) and is listed with its range in
`AnswerDocument.unsupported`, and a figure's placeholder also carries
`local.sam.bench.answer.image` with its file name. (Figures reach the window
as the turn's `files`, not through the text, so that path is the secondary
one.) A hard line break is a line separator (U+2028), so a list item's second
line hangs under its text.

**Privacy.** The reader reads only what the phone's History reads, from the
page's own session, and the conversation stays in memory for as long as the
window is open. Nothing is written but the window's frame; the pasteboard gets
what Copy with Source copies and nothing else. No session or project name
reaches the log.

**`--demo reference`** (`ReferenceDemo.swift`): the window on a made-up session
shaped like a real one (Claude narrates, runs steps, answers; the figures sit
on the steps), its pages and pictures answered from the demo after 300 ms:
three replies, the middle one with a bar chart (and an earlier draft of it
that isn't shown) and a heatmap, the newest a report cut on its page and whole
on the turn read, with a table that becomes its placeholder; `--step failed`
opens it on reads that fail. Nothing is read from Claude Science.

**Tests.** `ReferenceModelTests` (the newest answer on open; Earlier at the
edge reading back; empty pages read until an answer appears, eight at most;
the final count once row 0 is read; a cut answer read whole in place; a late
whole answer landing on its own row while another is shown; a page landing
while the user moved; unreadable, too big and thrown reads; close cancelling
and dropping what lands; Copy with Source; thumbnails once per figure),
`ReferenceRulesTests` (which rows are answers, the caption, the time, the
source line, the copied text), `ReadingGateTests` (the pause rule, one at a
time in order, a key press waited out, typing extending the wait to 2 s,
cancellation reaching the read), `AnswerMarkdownTests` (every block kind by
its attributes, the link filter, the placeholders and their ranges, a
20,000-character answer, determinism), `HistoryReaderGroundworkTests` (the
trim's identity with the old rule, the rows argument, the nonce and abort, the
cap, the yields, the timing, the phone's 503), and `ReferenceSnapshotTests`
(draws the content to PNGs, light and dark, when `CAPSID_SNAPSHOT_DIR` is set).

## 1.0 spikes (2026-10-22, read-only)

Five research spikes for Capsid 1.0, run before any 1.0 code, against Claude
Science **0.1.70** (`BUILD.json`: release, public, darwin-arm64, built
2026-10-22; the only runtime on disk). Evidence came from the shipped static
files only: the web bundle (`~/.claude-science/runtime/0.1.70-release/web-dist`),
the drizzle migrations beside it, `strings` of the `claude-science` binary (a
Bun binary that embeds the daemon's own JavaScript, so its route handlers are
readable), the public docs, and Capsid's code. No database was opened, no
auth-shaped file was read, no call went to the daemon, nothing was built or
launched. The full write-ups, with byte offsets for every finding, were handed
to Sam beside the 1.0 handoff; this section keeps the decisions, the reads each
feature would add, and what only a live check can settle. Capsid's inventory
still says it was last walked against Claude Science 0.1.63; nothing in the
0.1.63 → 0.1.70 changelog touches the paths below, but that is an inference.

### Baseline corrections

- The handoff said 0.1.69; the Mac runs 0.1.70, and the launcher at
  `/Applications/Claude Science.app` is still the browser-tab one
  (`com.anthropic.operon`, 0.1.70). It ships its own copy of the CLI at
  `Contents/Resources/bin/claude-science`, byte-identical to
  `~/.claude-science/bin/claude-science`.
- The checkout was one commit past the handoff's baseline (the 0.9.7 TESTING
  note), clean, with every branch merged and no worktree. The handoff's file
  map matches the code.

### S1. Companion mode: can Capsid read and act beside Claude Science's own window?

**Probably yes.** Nothing in 0.1.70 enforces "one tab at a time". The page's
only `BroadcastChannel` (`operon-notif-suppression`) and its `storage`
listeners exist to keep several tabs in step; its WebSocket client reconnects
on any close and has no "you were replaced" path; the daemon keeps one bearer
and one CSRF secret per boot, shared by every client, and its WebSocket
registry evicts nothing. The belief came from the CLI's banner, which says a
sign-in link "logs one browser tab in, then expires": that is the single-use
nonce, not a tab lock. Principle 4 and the README have repeated the sentence
since the first commit with no source; a two-minute live check (a Safari tab on
the daemon's address beside Capsid's window) settles it.

In own-window mode the daemon is the same program, started by the app as a
child (`serve --stdio`, usually with `--adopt-install`; `status` then reports
`daemon.launch_context: app-child` and `daemon.boot: serving`). It still binds
`127.0.0.1:<port>` (the "dual-access" port when asked for, else an ephemeral
one), still serves the web UI and `/api` to any cookie-authenticated localhost
client, still writes the lockfile `status` reads, and the data folder stays
`~/.claude-science` (the move writes a `pre-app/` backup; only window
settings, logs and page storage go to `~/Library/Application Support/Claude
Science`). The official window never uses the cookie: it sends a bearer header
or goes through the shell's bridge port, both exempt from CSRF, so a second
cookie-signed client doesn't disturb it.

A hidden `WKWebView` on the default data store can therefore load a daemon
document that is not the app (`/health`, auth-exempt JSON) and make every read
and write Capsid makes today from its script world, with the same CSRF dance.
Sign-in without the bundle: load `/api/me?nonce=<code>`, which answers the
daemon's own small page with one "Sign in" button (the text `SignInScript`
already matches) and ends on JSON. Two things only a live test can settle:
whether every own-window launch uses the staged boot (a plain `--stdio` boot
starts no control socket, so `claude-science url` gives no code, and with
`require_token` forced on Capsid cannot sign in at all), and which port the
daemon gets (either works, since `status` reports it).

The switch itself is gated twice: by the remote flag `operon_mac_app_move`,
and by a trigger that runs only at the first boot after an in-app "Restart to
update" (`--app` with `--_restart-parent-pid`), with no session running and the
launcher owned by the account. Sam's daemon runs with `--app` alone, so the
check has never run here; no switch traces exist. The launcher already holds
the own-window logic and honours `OPERON_NO_WINDOW` (undocumented; noted, not
recommended).

Nothing on disk can send the official window to a session: the launcher
declares no URL scheme, no AppleScript, and the CLI opens the app only with
`open -g <path>`. The web route for a session is
`/projects/<project>/frames/<frame>`; after the switch, check the new app's
`Info.plist` and shell binary for URL handling before giving up on deep links.

**Decisions for the code that follows (M2, M9):**

- Never run `serve` when the installed app is `com.anthropic.claudescience` or
  `status` says `app-child`: the app adopts a running daemon (exit 73) and would
  be pinned to whatever version `~/.local/bin` holds.
- Read `daemon.launch_context`, `daemon.boot`, `daemon.url_host` and
  `daemon.require_token` from `status` (`parseCLIStatus` ignores them today),
  and drop its 8765 default for a missing port, which is wrong for an
  ephemeral one. Honour `url_host` in `WebContainer.canonical()`, which forces
  `localhost` and can reach another program when the daemon moved to
  `127.0.0.1`.
- Prefer the app's `Contents/Resources/bin/claude-science` over `~/.local/bin`
  once the own-window app is installed: inside a bundle the CLI stops
  maintaining that link.
- A page hook for the handover dialog (`[data-testid="restarting-dialog"]`,
  "Claude Science now opens in its own window"): when it shows, stop the
  reconnect retries and switch to companion mode.
- Fallback if the live test finds no sign-in code: the read-only companion.
  Everything from the database keeps working (panel, cards with their reasons,
  badge, Mac notifications, Next Waiting, Activity, Quick Open, the phone's
  state and browse); the usage readout, context ring, plan preview, every write
  and the phone's history and files stop, and every action becomes "Open in
  Claude Science" (activate the app in the background; no deep link until one
  exists).
- Doubled notifications: the official window's suppression can't see Capsid,
  so a finish may notify twice. Decide who owns them in the live test.
- The hidden view needs its own navigation delegate (Capsid's response policy
  turns JSON it can't show into a download) and its own 401 recovery
  (`sessionLost()` presses a button on the main page, which the hidden
  document doesn't have).

### S2. Keep: versions, provenance, the text behind a figure

**The one thing to know first.** `GET /api/frames/<root>/artifacts`, the list
Results and the phone read, returns one row per artifact, and that row is the
artifact's **latest version project-wide**, which another session may have
made. Keep must never take "the version" from that list. The daemon's own zip
of a conversation swaps in "the version this conversation contributed" for the
same reason.

What Keep can get, each through a GET the page already makes for itself:

| Want | Read | Notes |
|---|---|---|
| Every version of an artifact | `GET /api/artifacts/<artifact>/versions` | a bare array, oldest first: `version_id`, `version_number`, `frame_id` (the frame that saved it; null for a copy or a user edit), `content_type`, `size_bytes`, `created_at`, `parent_version_id`, and `file_path`, an absolute path the page must drop. No name, no checksum. The page's version stepper and its "compare against" use it. |
| A version's facts | `GET /api/artifacts/versions/<v>?include_metadata=true` | `version_id` (must equal the one asked for: an artifact id in that slot quietly serves the latest version), `artifact_id`, `version_number`, `filename`, `content_type`, `size_bytes`, `created_at`, `checksum` (sha256 hex of the bytes, or null), `is_user_upload`, `reproduction_code`, `environment`. No side effect. |
| The bytes | `GET /api/artifacts/versions/<v>` (allowed today) | honest `Content-Length`, `Accept-Ranges: bytes`, one Range at a time (206/416), so a streamed-to-disk path past 8 MB is possible later. Swift checks sha256 against the checksum. |
| The data it was drawn from | `GET /api/artifacts/versions/<v>/lineage?slim=1` | `dependency_mappings.inputs[]` as `{filename?, artifact_id?, version_id?, workspace_path?, consensus?}`; `mapping_status` can be `pending`; `consensus: ast_only` is what the page shows dimmed as "inferred". Inputs with no ids (workspace files, refused reads) can't be fetched. **Reading it can start the daemon's own code reconstruction** (a model call, a database write, a `lineage_ready` broadcast) when the version has none yet, so it is `whenUsed`, never a Diagnostics probe, asked once per Keep and polled at most 6 × 5 s as the page does. Under `slim=1` the `messages`, `environment_snapshot` and `interactions` fields are null; refuse a body where they aren't. |
| The script | the same lineage read's `code`, or the facts read's `reproduction_code` | it is the page's "Claude-generated reconstruction", not the code that ran (the cells as run are `GET /api/frames/<f>/execution-log?versionId=<v>`, with stdout and stderr). It holds `{{artifact:<vid>}}` tokens that Keep must rewrite to the names of the inputs it saved, as the daemon's script bundle does. |
| The answer that showed it | `GET /api/frames/<root>/messages?from=<n>&limit=<≤50>` (the phone's allowlisted read) | an assistant row's `_artifact_refs` maps each file name its text shows **or merely names** to `{artifact_id, version_id}` as it stood when the message was written; `_ts` (milliseconds; may be missing). Match "shown" against the text's `![…](…)` sources, `{{artifact:<vid>}}` or `?v=<vid>`; a plain mention is the last resort; the save step (a `save_artifacts` or run tool result listing the version) is the fallback, as the page's own "View in context" uses. No daemon lookup from a version to a message exists, so Keep scans pages, seeded at the page whose `_ts` brackets the version's `created_at` (messages are stamped monotonically), at most six pages. |
| The daemon's own packs | `GET /api/artifacts/<v>/script-bundle` (script, inputs, environment.yml, run.sh) and `GET /api/frames/<f>/bundle?scope=sliced&versionId=<v>` (notebooks and every output of the frames involved) | streamed zips with no `Content-Length`; the sliced bundle can be large. Not for Keep's first cut. |

An allowlist finding to fix regardless: `WebContainer.readablePrefixes` lets
`apiGET` read anything under `/artifacts/versions/`, which today includes
unslimmed lineage (with its conversation snapshot), `/verification` and
`/annotations`, straight into Swift. Narrow it to exactly the plan-file read
it exists for, and give Keep typed, projected shapes in `ArtifactReader`.

The list projection should gain `version_number`, `checksum` and a
`ref` flag (`ref_host_path` set: a reference to a file on this Mac, served as
it is now, with no immutable cache and possibly no checksum), keeping the path
in the page. Ids are UUIDs (`text(36)`); the new shapes take `[0-9a-f-]{36}`,
which also keeps `/api/artifacts/<id>/…` from ever matching
`/api/artifacts/versions/…`.

Proposed `CompatInventory` entries (feature `keep`): the versions and facts
reads as `.live` probes on the shown session's plan artifact (both are pure
reads), lineage and the script bundle as `whenUsed`, and `_artifact_refs` on
the messages read as `whenUsed` ("it is what was said"). Bump `checkedWith` to
0.1.70 once the whole inventory has been walked against this bundle.

What the sheet says when something is missing, reusing the page's own
sentences where it has them: the version gone (404/410): "This version isn't
in Claude Science any more."; a reference file whose bytes no longer match
its checksum: kept as it is now, with a warning; no showing message found:
"Capsid couldn't find the answer that showed this version. The figure and its
provenance can still be kept."; a user upload: no data or script rows; mapping
`pending`: "Claude Science is still working out what this was drawn from. Try
again in a minute."; inputs empty and complete: "Claude Science recorded no
input files for this version."; only `ast_only` inputs: offered off by
default, tagged "inferred"; an input without ids: listed, not copyable; no
code: the page's own "No reproduction code…" sentences. A version that isn't
the latest: "Keeping version n of m, the one this answer showed. A newer
version exists."

### S3. Plan progress ("Step 3 of 7 · Normalize counts")

**Go, narrowly: show "Step n of m" with the page's own arithmetic; add the
title only when it is unambiguous; show nothing otherwise.** The plan file is
JSON (`phases[] → delegations[] → steps[{title, description}]`, plus
`task_summary` and `feasibility`); steps have no ids and are keyed by exact
title, made unique only when the plan is first generated. Progress is the
model's own `update_step_status` calls, written as
`context_data._step_statuses[title] = {status, updated_at, notes?}` on the
frame that did the work: the root for its own steps, a child frame per
delegated track (its `_plan_claims` lists the titles it owns and the plan
version). Child statuses are never copied to the root. The page shows exactly
this: a chip "Plan — step N of M", where `done` counts `completed` or
`skipped` and N is `min(done + 1, total)`, merged from the root plus its direct
children's claims for the current version, only when the plan is approved and
has `phases`; and per-step icons in the plan tab. The daemon blocks a turn
from ending while steps are unmarked, but gives up after three denials, so
statuses can lag or be missing mid-run: the page then says "step 1" forever.
Capsid's guard: nothing until at least one status exists.

Reads: the shallow root read the card already makes carries the root's
statuses, but a delegated plan needs the children, which the page's own lean
tree gives in one read, `GET /api/frames/<root>/trace-shallow?include_messages=false`
(already allowlisted for the phone's permission queue, but not for `apiGET`,
which needs one new exact shape). The root in that tree is "fat" and carries
`_plan_json` with every step's description, and each child's claims repeat
their descriptions, so the projection must run in the page and return only the
status words, the counts and one title; the database poll can't supply this
(`context_data` may live in `frame_blobs`, and SQLite has no cap on what a
query extracts). Rate: only running sessions on screen, at least 15 s apart per
session, one in flight, plus one read when a plan leaves awaiting-approval.
Title rule: exactly one step `in_progress`, unique in the plan, at plan-order
index n. Flip to omit if the live checks find `in_progress` reported rarely or
late, or the tree read too heavy. A zero-API fallback for the shown session
only: the chip's text (`data-testid="plan-status-chip"`) read as the tab strip
is.

### S4. Reviewer findings and mid-run messages

**Reviewer findings: readable with one new route.** They are rows of a
dedicated `verification_checks` table (`verdict` pass|warn|fail|inconclusive,
`status` open|claimed|resolved|unaddressed, `rebuttal`, `reflag_count`,
`source_ref` naming the message by index), served by
`GET /api/frames/<root>/verification`; no existing read carries them. Reviewer
runs are child frames with `agent_name` REVIEWER or AUDITOR, hidden, so the
helper count is unaffected. Count the way the page does: a finding is `fail`
or `warn`; it stands while `open`, `claimed` or `unaddressed` and not withdrawn
(`unaddressed` with a rebuttal and `reflag_count` under 4). At turn end open
findings become `unaddressed`, so counting only `open` shows 0. `severity` is
declared and never rendered: not for a card. The page shows findings only
inside the transcript and on an artifact's Review tab, never in the session
list, so a "Reviewer: 2 findings" line on the Finished card surfaces what the
page shows, at a level it doesn't. Recommended read: the route projected in
the page to counts only (`{standing, fixed, running, reviews}`), gated like the
failure reason by "Show plans, questions and requests on the card"; a SQL
alternative over the table exists but re-derives the rule. Whether findings
land before `completed` is written needs the live check. The `[Auditor]`
notice row in transcripts is already hidden by Capsid's projections.

**Mid-run notes never reach the notification bridge.** The page has one
`new Notification(`, fired for five session statuses only. A note is a
`send_user_message` tool call in the root's transcript (shown by the page as
"Message to you"); the field `SessionReader` reads for the phone's `toYou`,
`context_data._sent_user_messages`, is written **only for sub-agent frames**
(both write sites guard on non-root), so on 0.1.70 the phone's root "Messages
to you" is empty by construction. The working path is `HistoryReader`, which
already projects the tool call. A metadata-only wake-up is possible in SQLite
(a presence test over new `frame_messages` rows, never text); the text comes
from one allowlisted `/messages?from=-12&limit=12` page, projected in the
page, behind the same card setting. The changelog's "progress notes" (0.1.49)
are derived from thinking blocks and stay out.

### S5. What reading another session costs the live page

A history page today is 50 rows: one GET for an earlier page, two sequential
GETs for the newest (a 12-row tail, then up to 38 before it), one synchronous
`JSON.parse` of the raw rows (tool results, thinking and all) and one
projection pass on the **WebContent main thread**, the composer's thread; at
most 60 items and 64 KB come back. Nothing yields, nothing pauses while the
user types, nothing watches the DOM. History, turn, session and live reads
have deadlines (15 s; 8 s for session and live, which DESIGN.md's phone
section mis-states as 15) but no byte cap and no abort once inside the page;
only `apiGET` and the artifact reader have those. Every limit today is per
phone device or per session, so a Mac-side reader bypasses all of it.

Nothing is logged about read time or size (the route line is `info`, not
persisted), so no live number exists. A synthetic run of Capsid's own
projection strings under the OS's JavaScriptCore (made-up pages, an Apple M4)
gives a floor: a typical 50-row page blocks about 1 ms warm, 3 ms cold; a 7 MB
page 5 to 8 ms; the one bad shape, a text-heavy page over the 64 KB output cap,
10 to 18 ms (42 ms cold max), because the trim loop re-stringifies and
re-counts the whole remainder for every row it drops. A scratch copy that
counts each row once gave identical output and about 3.5 ms. The only in-repo
calibration (8 MB of base64 "held it ~50 ms") suggests the live page runs
about 2.5× slower than bare JavaScriptCore; that is one unreplicated figure.

Proposed for 1.0, judgement unless marked: fix the trim loop first (linear
byte accounting; output byte-identical); 25-row pages for the reference
reader (the wire allows 1 to 50; the script hard-codes 50); a 2 MiB streamed
byte cap on history and session GETs with the `apiGET` mechanism; reads that
carry a nonce and abort like the artifact reader's; one history page in
flight, two reads in a Mac-side queue modelled on `ShelfTransfers` (foreground
before Since You Left, 30 s from start, abort on close); reuse `HistoryPages`'
30 s cache; no polling. Since You Left needs no history page: `readSession(id,
turns: false)` is one GET whose `reply` is already the last answer, up to
4,000 characters, so six sessions cost six small blocks. The typing rule: gate
the **start** of a read on no key in the main window for about 400 ms (a local
`NSEvent` monitor recording only the time, never the key), foreground reads
waiting at most 2 s, background reads until quiet; a block in progress can't
be interrupted, so bound its length instead; yield once in the page before
parse and before projection (`requestIdleCallback` with a 1 s timeout if
present, else `setTimeout(0)`), never a focus check, since the composer holds
focus whenever the window is key. A measurement protocol for Sam (event-loop
lag and keydown-to-frame in the page's console, Safari Timelines, interleaved
A/B runs including a hidden window) and a small go-phase change (page-measured
milliseconds logged at `.notice` in a new `reading` category) were handed over
with the spike.

### What the spikes change in the plan

- M2 gains four small safety items the spikes found: narrow `apiGET`'s
  `/artifacts/versions/` prefix; read the new `status` keys and drop the port
  default; never `serve` beside the own-window app; fix the phone's root
  `toYou` to read `/messages`.
- M3's reads are the versions, facts and lineage shapes above, plus one new
  in-page history op that finds the showing message; the figure's sha256 is
  checked against the daemon's checksum, and the README records the version
  the answer showed, never the list's latest.
- M4 starts with the trim-loop fix, abortable reads and a byte cap before any
  reader window exists.
- M5 reads six shallow frames, not six history pages.
- M6 may show step progress, number first, title behind the guard.
- M7's reviewer line is one projected count read; its notes card reads the
  transcript, not the bridge.
- M9 is "probably possible"; its live test decides, and a read-only fallback
  is specified.

### Live checks after go

Each needs Sam, a throwaway session, and notes that keep counts and key names
only. S1: the two-page check (a Safari tab beside Capsid); after a switch,
`status` from both CLIs, `claude-science url` once (a printed link proves the
control socket), the new app's `Info.plist` and shell strings for URL
handling, one approve from the card while the official window watches, who
notifies, and that Capsid starts no daemon when the app quits. S2: whether a
helper agent's figure carries `_artifact_refs` on the root's reply; the
lineage side effect and whether it draws on usage; sha256 against `checksum`;
whether `/versions` lists intermediate versions; a Range read through the
page. S3: that the shallow and tree reads carry the fields, sizes and latency
for 0, 3 and 10 helpers, how often and how late models report `in_progress`,
parity with the page's chip. S4: the findings body on a reviewed session,
whether they land before `completed`, the root-note case (no
`_sent_user_messages` on the root, the tool call in the last 12 messages, no
notification). S5: the protocol above, before and after the trim fix.
