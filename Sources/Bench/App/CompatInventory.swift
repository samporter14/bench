// CompatInventory.swift — what Capsid relies on in Claude Science that Claude
// Science never promised to keep (DESIGN.md, Diagnostics). An update that
// changes any of it breaks a feature without a word: Close Other Tabs does
// nothing, a readout goes blank. This is the list, grouped by kind, each with
// the Capsid feature it serves and the file that relies on it; Diagnostics
// checks what it can right now, and says plainly what it can't.
//
// The list is held honest by tests (CompatInventoryTests): every selector in
// the page scripts, every path an allowlist lets through, every column a query
// reads and every key the status parser takes must be here, and every column
// here must be one a query needs. Add a dependency in the code and the tests
// say to add it here.
//
// `checkedWith` is the Claude Science version this list was last walked
// against. When it moves, walk the whole list again.
import Foundation

enum CompatInventory {
    /// The Claude Science version Capsid was last checked with: the one whose
    /// web bundle the page markup was read from (DESIGN.md, Main window, and
    /// TESTING.md). Walked again on 2026-10-22 against the 0.1.70 bundle, by
    /// reading its files only. Move it only after walking `all` again.
    static let checkedWith = "0.1.70"
}

// MARK: The kinds

/// What sort of thing a dependency is. The order is the order Diagnostics
/// and DESIGN.md list them in.
enum CompatKind: String, CaseIterable, Sendable {
    /// The page Claude Science draws: its markup, its address, its sign-in.
    case pageHook
    /// A GET to Claude Science's own API, made from inside the page.
    case readEndpoint
    /// A POST to it. Diagnostics never sends one.
    case writeEndpoint
    /// The `claude-science` command line.
    case cli
    /// The data folder and the database in it.
    case schema

    var title: String {
        switch self {
        case .pageHook: "Page"
        case .readEndpoint: "Reads"
        case .writeEndpoint: "Writes"
        case .cli: "Command line"
        case .schema: "Database"
        }
    }
}

/// The Capsid features that lean on Claude Science, in the words the rest of
/// the app uses for them. Also what a breadcrumb names (CompatBreadcrumbs).
enum CompatFeature: String, CaseIterable, Sendable {
    case closeTabs, tabMenu, shelfMenu, modelMenu, signIn, notifications, sessionAddress, previews
    case usage, context, planCard, approve, errorCard, phone
    case start, sessions, activity, browse
    case handover
    case keep
    case planProgress, reviewer, notes
    case find
    /// Not a feature: the checks Capsid makes once when Claude Science's
    /// version changes (App/CompatWatch.swift), so "Last problem" can name them.
    case update

    var title: String {
        switch self {
        case .closeTabs: "Close Other Tabs and Close All Tabs"
        case .tabMenu: "The tab right-click menu"
        case .shelfMenu: "Add to Shelf from a figure, file link or document tile"
        case .modelMenu: "Ask Another Model in Claude Science's model menu"
        case .signIn: "Signing back in"
        case .notifications: "Needs-input cards from the page's notifications"
        case .sessionAddress: "Open on a card, Quick Open, reopening where you were and the context ring"
        case .previews: "HTML previews"
        case .usage: "The usage readout, pause and heads-up cards"
        case .context: "The context ring"
        case .planCard: "A plan on its card"
        case .approve: "Approve a plan"
        case .errorCard: "The reason on a failure card"
        case .phone: "Capsid on your phone"
        case .start: "Starting Claude Science"
        case .sessions: "Sessions in the Lab"
        case .activity: "The usage graph and the week in review"
        case .browse: "Quick Open, Results and the phone's project list"
        case .handover: "Staying with Claude Science when it opens in its own window"
        case .keep: "Keep a figure with its answer, data and script"
        case .planProgress: "Step n of m under a running session"
        case .reviewer: "The reviewer's findings on a finished card"
        case .notes: "Claude's messages to you, on a card"
        case .find: "Find a figure or file from any session, in the Shelf and in Quick Open"
        case .update: "The checks after a Claude Science update"
        }
    }

    /// How a breadcrumb names it ("Close Other Tabs, 12 minutes ago: …").
    var shortTitle: String {
        switch self {
        case .closeTabs: "Close Other Tabs"
        case .usage: "The usage readout"
        case .context: "The context ring"
        case .planCard: "The plan on a card"
        case .approve: "Approve"
        case .update: "A Claude Science update"
        default: title
        }
    }

    /// How a notice names it in the middle of a sentence ("Close Other Tabs
    /// and the usage readout may not work"). Fixed words, so nothing read from
    /// the page can reach a card.
    var inASentence: String {
        switch self {
        case .closeTabs: "Close Other Tabs"
        case .tabMenu: "the tab right-click menu"
        case .shelfMenu: "Add to Shelf from the conversation"
        case .modelMenu: "Ask Another Model in the model menu"
        case .signIn: "signing back in"
        case .notifications: "needs-input cards from the page"
        case .sessionAddress: "Open on a card"
        case .previews: "HTML previews"
        case .usage: "the usage readout"
        case .context: "the context ring"
        case .planCard: "plans on cards"
        case .approve: "Approve"
        case .errorCard: "the reason on a failure card"
        case .phone: "Capsid on your phone"
        case .start: "starting Claude Science"
        case .sessions: "sessions in the Lab"
        case .activity: "the usage graph"
        case .browse: "Quick Open and Results"
        case .handover: "staying with Claude Science's own window"
        case .keep: "Keep"
        case .planProgress: "step progress"
        case .reviewer: "reviewer findings"
        case .notes: "Claude's messages on a card"
        case .find: "finding files"
        case .update: "the checks after an update"
        }
    }
}

/// How Diagnostics treats a dependency.
enum CompatCheck: Equatable, Sendable {
    /// Diagnostics checks it now, or the existing steps do (the command line,
    /// the database).
    case live
    /// It can only be checked when it is used, and why.
    case whenUsed(String)
}

/// One thing Capsid relies on.
struct CompatDependency: Equatable, Sendable {
    let kind: CompatKind
    /// What Capsid looks for, exactly: a selector, an attribute, a path, a
    /// field, a `table.column`. For a script's selectors it is the string the
    /// script holds, so the tests can compare them.
    let token: String
    /// What is expected of it, in a sentence.
    let detail: String
    let feature: CompatFeature
    /// The file under Sources/Bench that relies on it (the first one, when
    /// several do).
    let file: String
    let check: CompatCheck
    /// The token is a string literal in one of the page scripts
    /// (`CompatScripts`), so the tests hold the two lists equal.
    var literal = false
    /// Capsid copes without it (a column probed before it is used).
    var optional = false

    var isWhenUsed: Bool {
        if case .whenUsed = check { true } else { false }
    }
}

// MARK: The list

extension CompatInventory {
    static var all: [CompatDependency] { pageHooks + readEndpoints + writeEndpoints + commandLine + database }

    static func dependencies(of kind: CompatKind) -> [CompatDependency] {
        all.filter { $0.kind == kind }
    }

    // MARK: Page

    private static func hook(_ token: String, _ detail: String, _ feature: CompatFeature, _ file: String,
                             check: CompatCheck = .live, literal: Bool = false) -> CompatDependency {
        CompatDependency(kind: .pageHook, token: token, detail: detail, feature: feature, file: file,
                         check: check, literal: literal)
    }

    static let pageHooks: [CompatDependency] = [
        hook(#"[data-testid="right-tab-strip"]"#, "the one tab strip of the right-hand panel (none while no tab is open)",
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook(#"[role="toolbar"][aria-label="Open panels"]"#, "the toolbar in the strip where the tabs sit",
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("[data-tab-id]", "each tab", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("data-tab-id", "the attribute holding a tab's id", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("[data-tab-btn]", "the button in a tab that shows it; its last element is the label (an icon comes first), whose text is the open file's name, which the figure menu reads on the shown tab for a tile of the right-hand panel", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("aria-current", #"the attribute that is "true" on the shown tab's button (the figure menu takes the shown tab by this or by data-shown, and only when exactly one is shown)"#,
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("data-shown", "or an attribute on the shown tab itself", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("button[data-tab-close]", "a tab's own close button, which Capsid presses",
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook(#"[data-testid="right-tab-strip"] [data-tab-id]"#, "the tab under a right-click; the figure menu also reads each tab to find the shown one, for the name of a file open in the right-hand panel (the panel's tiles show none; see [data-pane=\"right\"])",
             .tabMenu, "Web/TabContextMenu.swift",
             check: .whenUsed("seen only on a right-click"), literal: true),
        hook("/api/artifacts/versions/<version>, ?v=<version>", "the address of a figure or a file link on the page names its version, the same path the page asks for a file's bytes and thumbnails with; a page that draws them from another address gets no Shelf items",
             .shelfMenu, "Shelf/ShelfAddress.swift", check: .whenUsed("seen only on a right-click")),
        hook("img, a[href]", "the figure or the file link under a right-click: a picture's address (currentSrc) or a link's (href) names one version of a file, as /api/artifacts/versions/<version> (any of its tails, with or without ?thumbnail=) or ?v=<version>",
             .shelfMenu, "Shelf/ConversationMenu.swift",
             check: .whenUsed("seen only on a right-click"), literal: true),
        hook(#"[data-testid="turn-tray-card"]"#, "a card in the Generated tray under a reply: a right-click on its label stands for the picture in the card; a card with no picture (a Markdown, table or text file) stands for the file its label names",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook(#"[data-testid="middle-truncated-filename"]"#, "the file-name label in a Generated card (a span whose title is the whole file name, sanitised, and whose text is that name cut in the middle): for a card with no picture Capsid reads the title as the file's name and looks that name up among the session's files, never taking a file whose name is not exactly that; seen on a right-click on such a card, on a session's page only",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click on a card with no picture"), literal: true),
        hook(#"[data-testid="artifact-preview-region"]"#, "the body of an open file tile (the side pane's, a tab's: the page's ArtifactTile): a right-click in it, or in the tile's header, is a right-click on that tile, which has no picture to name its version when the file is Markdown, a table or text; a picture drawn in a zoom-and-pan wrapper in this body is the file's viewer (see .react-transform-component img); since 1.0.6 words selected wholly inside it (both ends of the selection) and right-clicked there are a passage Capsid offers Add Selection to Shelf for, in the page's menu",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click in a tile with no picture"), literal: true),
        hook(#"[data-testid="artifact-actions"]"#, "the \"More actions\" button in a tile's header: what tells the tile's header from any other header on the page, since the tile's wrapper has no attribute of its own",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click in a tile with no picture"), literal: true),
        hook(".react-transform-component img", "the picture in the zoom-and-pan wrapper (react-zoom-pan-pinch's own class) the page draws a file's picture in when it is open large (the side pane, a tab, the fullscreen tile): the wrapper's stylesheet gives its images pointer-events: none, so a right-click lands on the layer over the picture or the space beside it and the picture is in no list of what is under the pointer. A right-click anywhere in a tile's body (the preview region) that holds exactly one such picture is a right-click on it; Capsid reads its address (currentSrc) for the version as for any figure (the page makes it /api/artifacts/versions/<version>?v=<version> for an artifact). A viewer whose picture names no version falls to the tile's name, a tile with no name gets nothing, and a wrapper with no preview region around it (a file on the host's disk) gets nothing",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click in the page's viewer for a picture"), literal: true),
        hook(#"[data-pane="right"]"#, "the right-hand panel's tabs, inside the split layout: a tile in it whose header shows no name is named by the shown tab (a tile anywhere else with no name gets nothing)",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click in a tile with no name in its header"), literal: true),
        hook("header", "the tile's header element, the one that holds that button: Capsid takes the first one in the tile (a header elsewhere in the page is never taken, only one that holds the button); the file's name is the text of the span that opens it (the header's first child's first child, a span with only text in it; the version stepper, the buttons and the provenance breadcrumb hold elements and are never taken for it), which the page shows for a tile of a conversation but not for a tile of the right-hand panel (its slot-chrome mode leaves the title to the panel's tab). Capsid looks the name up among the session's files, so a header that shows something else gets \"couldn't find\" and never a wrong file",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click in a tile with no picture"), literal: true),
        hook("window.getSelection()", "the words selected on a session's page, an ordinary browser call and no markup of Claude Science's: Capsid compares the selection at a right-click's button-down with the one at its menu (WebKit selects the word under the pointer when a right-click lands outside the selection) and, if it is the same, offers Add Selection to Shelf in the Mac's menu, or (since 1.0.6) first in Capsid's group in the page's own menu for a tile, when both ends of the selection are inside the tile's preview region; it puts the selection back with removeAllRanges and addRange if a click on that item moved it; it reads the words only when that item is chosen, and they go to a note on the shelf and nowhere else",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click on selected words")),
        hook("img", "the thumbnail inside a tray card, whose address names the file's version, as /api/artifacts/versions/<version>?thumbnail=<width>",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook("a picture beside what was clicked", "the page lays a transparent layer (its annotation layer) over a figure it draws, in the side pane, in a tab or inline in a reply, so a right-click lands on the layer and the picture is its sibling; Capsid takes the picture under the pointer that shares a parent with what was clicked, or with what that is in, never as far out as the body",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click")),
        hook(#"[role="menu"]"#, "any menu the page draws, named or not: only for the step traces' menu-other (a menu came after a right-click on a figure, or after the model picker was pressed, but not that one's), never touched; the model menu's watch also uses it, and posts a breadcrumb for it",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook(#"[role="menu"][aria-label="Artifact actions"]"#, "the page's own menu for a figure or a file (one component for a tile, an inline picture, a Generated card and the side pane's image), drawn in a wrapper at the end of the body when the page takes the right-click, which it does by cancelling the Mac's menu; Capsid adds a rule and four items at its end (above the red Delete item and its rule, when there is one) within two seconds of a right-click on a figure whose address names a version (or on a tile or card of a file with no picture; a fifth item, Add Selection to Shelf, comes first in the group for words selected in a tile), and posts a breadcrumb when the menu opens and has no item to copy",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook(#"[role="menuitem"]"#, "an item of that menu, a button: Capsid copies the classes of the first one that isn't the red Delete, and its icon box, never its words; the page's own arrow keys find buttons in the menu by this role, which is how the keyboard reaches Capsid's items",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook(#"[data-cds="Icon"]"#, "the box an item's icon sits in (a span with the icon font's size and weight inline); Capsid copies the empty box and draws its own line icon in it, and goes without an icon when the item has no such box",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only on a right-click"), literal: true),
        hook("Escape on the document", "the page closes its figure menu on a keydown Escape in the capture phase of the document (else on a pointer-down outside the menu); after one of Capsid's items is chosen Capsid sends Escape, and a pointer-down on the body if the menu is still there 80 ms later",
             .shelfMenu, "Shelf/ConversationMenu.swift", check: .whenUsed("seen only when an item of Capsid's is chosen")),
        hook(#"[data-testid="model-selector"]"#, "the model picker beside the message box (its button, or the wrapper round the button): a real pointer-down, Enter, Space or an arrow on it starts a two-second watch for its menu; the same test id is on every composer's picker, so the draft is read from the composer the pressed one sits in",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the model picker is pressed"), literal: true),
        hook(#"[role="menu"][data-cds="ModelSelector"], [role="menu"][data-testid="model-selector-popup"]"#, "the picker's own menu, a popup the page draws in a layer of its own when the picker opens: the catalog picker's has data-cds=\"ModelSelector\" (its button has it too, hence role=\"menu\" with it), the plain picker's has data-testid=\"model-selector-popup\"; the effort and \"More models\" submenus are other popups and are left alone. Capsid adds a rule and one item at the end of its list within two seconds of a press on the picker, and posts a breadcrumb when a menu opens that is not this one, or this one has no list or item to copy",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the model picker is pressed"), literal: true),
        hook("[data-cds-sheet-scroll]", "the element in that menu that holds its list of items (the page's design system marks it, and it scrolls when the menu is tall); Capsid puts its rule and item last in it, and puts them back if the page draws the list again",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the model picker is pressed"), literal: true),
        hook(#"[role="menuitemradio"], [role="menuitem"]"#, "an item of that menu (a model is a menuitemradio, the \"More models\" row a menuitem), a div: Capsid copies the tag and the classes of the first one, less the page's extra padding for an item with a second line (a class starting pb-[calc( ), never its words",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the model picker is pressed"), literal: true),
        hook(#"[role="separator"]"#, "the page's rule between groups in that menu: Capsid copies its classes for its own rule, and uses the page's usual ones when the menu has none",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the model picker is pressed"), literal: true),
        hook("Escape in the model menu", "the page closes its model menu on a keydown Escape that reaches its list or the document, as a key press with the menu focused does; after Capsid's item is chosen Capsid sends that Escape from inside the menu, and a pointer-down on the body if the menu is still there 80 ms later",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the item of Capsid's is chosen")),
        hook(#"[data-testid="composer"]"#, "the box round the message box and the picker (also the aside's composer), which the picker pressed sits in",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the item of Capsid's is chosen"), literal: true),
        hook(#"[role="textbox"]"#, "the message box in it, a contenteditable div: Capsid reads its text when the item is chosen (a line break for each <br> and each block after the first, mentions as they show), cut at 32,000 characters, as the seed of the question; it never writes to it",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the item of Capsid's is chosen"), literal: true),
        hook("data-voice-ghost", "the span of dictation not yet kept, which the draft leaves out",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the item of Capsid's is chosen"), literal: true),
        hook("data-upload-status", "an upload's chip in the message box, which the draft leaves out",
             .modelMenu, "AskModel/ModelPickerMenu.swift", check: .whenUsed("seen only when the item of Capsid's is chosen"), literal: true),
        hook("button, a", "the elements searched for the sign-in button",
             .signIn, "Web/WebContainer.swift", literal: true),
        hook("Sign in", #"a visible button or link reading exactly "Sign in": the page's "You've been signed out" banner (shown when the account login is stale) and its account menu have one; Capsid presses the first visible one"#,
             .signIn, "Web/WebContainer.swift", literal: true),
        hook("?nonce=<code>", "the page signs in with a one-time code on any of its addresses",
             .signIn, "Shared/Core/CLIStatus.swift", check: .whenUsed("seen only while signing in")),
        hook("/api/me?nonce=<code>", "a daemon the app started answers with its own small page, one Sign in button, and ends on JSON",
             .signIn, "Web/DaemonPolicy.swift", check: .whenUsed("seen only while signing in to a daemon the app started")),
        hook(#"[data-testid="restarting-dialog"]"#, "the dialog the page shows whenever Claude Science restarts its server (an update, a sign-out, a move of its data, or the move to its own window, the only one that says it now opens in its own window); Capsid only notes that it is on screen, never its words",
             .handover, "Web/HandoverWatch.swift", check: .whenUsed("seen only when Claude Science moves to its own window"), literal: true),
        hook("window.Notification", "the page makes its desktop notifications with new Notification(title, {body, tag, requireInteraction}) and listens for click",
             .notifications, "Web/NotificationBridge.swift", check: .whenUsed("seen only when a session needs you")),
        hook("/projects/<project>/frames/<session>", "a session's page has this address",
             .sessionAddress, "Web/WebAPI.swift"),
        hook("another localhost port", "HTML previews draw in a sandboxed frame on the origin the daemon names in the page's own config (sandboxOrigin; a remote content host when it names none); a link to another localhost port opens in a preview window",
             .previews, "Web/Routing.swift", check: .whenUsed("seen only when a preview opens")),
    ]

    // MARK: Reads

    private static func read(_ token: String, _ detail: String, _ feature: CompatFeature, _ file: String,
                             check: CompatCheck = .live) -> CompatDependency {
        CompatDependency(kind: .readEndpoint, token: token, detail: detail, feature: feature, file: file, check: check)
    }

    static let readEndpoints: [CompatDependency] = [
        read("GET /api/usage", "{ok, data: {five_hour, seven_day, seven_day_opus, seven_day_sonnet: {utilization, resets_at}, extra_usage}}; also ?fresh=1",
             .usage, "Usage/PlanUsageModel.swift"),
        read("GET /api/frames/<session>/token-series", "{window, turns: [{ctx_total}], truncated}",
             .context, "Context/ContextModel.swift"),
        read("GET /api/frames/<session>?shallow=true", "status, and the plan fields of context_data and output_data (and a failed one's error, next); the phone reads it too",
             .planCard, "Lab/PlanApproval.swift"),
        read("output_data.error on GET /api/frames/<session>?shallow=true",
             "a failed session's root frame: status \"failed\", and output_data.error, a string (often \"400 {…}\" holding error.message or message), with error_status beside it; read once, for the failure card",
             .errorCard, "Lab/FailureReason.swift", check: .whenUsed("read only when a session stops with an error")),
        read("GET /api/artifacts/versions/<version>", "a plan file: task_summary, phases[].delegations[].steps[], feasibility.confidence; the phone reads artifacts here too",
             .planCard, "Lab/PlanApproval.swift"),
        read("GET /api/artifacts/versions/<version>?thumbnail=<width>", "a WebP thumbnail, 120 or 800 wide",
             .phone, "Remote/ArtifactReader.swift", check: .whenUsed("it is an image of a file, so it is not read from here")),
        read("GET /api/frames/<session>/artifacts", "a session's list of artifacts",
             .phone, "Remote/ArtifactReader.swift", check: .whenUsed("it lists file names, so it is not read from here")),
        read("GET /api/frames/<session>/messages?from=<n>&limit=<n>", "a page of the session's messages",
             .phone, "Remote/SessionReader.swift", check: .whenUsed("it is what was said, so it is never read from here")),
        read("GET /api/frames/<session>/trace-shallow?include_messages=false", "the helpers' pending requests",
             .phone, "Remote/RemotePermissions.swift", check: .whenUsed("it reads what the helpers are asking, so it is not read from here")),
        read("GET /api/frames/<session>/streaming", "the text being written now; Capsid copes if the daemon has no such route",
             .phone, "Remote/RemoteLive.swift", check: .whenUsed("it exists only while a session works")),
        read("GET /api/artifacts/<artifact>/versions",
             "a bare array, oldest first: version_id, version_number, frame_id, content_type, size_bytes, created_at, parent_version_id (file_path, agent_name and language are dropped in the page)",
             .keep, "Remote/ArtifactReader.swift"),
        read("GET /api/artifacts/versions/<version>?include_metadata=true",
             "JSON: version_id (the one asked for), artifact_id, version_number, filename, content_type, size_bytes, created_at, checksum (sha256 hex or null), is_user_upload, reproduction_code?, environment {environment_name, python_version, packages [{name, version}]}?",
             .keep, "Remote/ArtifactReader.swift"),
        read("GET /api/artifacts/versions/<version>/lineage?slim=1",
             "code, code_description, language, pending, code_unavailable {model, reason}, has_cell_sources, has_environment, dependency_mappings {inputs [{filename, artifact_id, version_id, workspace_path, consensus}], mapping_status}; messages, environment_snapshot and interactions are null",
             .keep, "Remote/ArtifactReader.swift",
             check: .whenUsed("reading it can start Claude Science's own code reconstruction, so it is not read from here")),
        read("_artifact_refs and _ts on GET /api/frames/<session>/messages",
             "an assistant row's {name: {artifact_id, version_id}} for the files its text shows or names; _ts in milliseconds",
             .keep, "Remote/HistoryReader.swift", check: .whenUsed("it is what was said, so it is never read from here")),
        // Step progress, the reviewer's findings and Claude's notes (since 1.0): each is projected in the
        // page (Remote/InsightReader.swift; the notes by the history reader), so apiGET never reads them.
        read("plan statuses on GET /api/frames/<session>/trace-shallow?include_messages=false",
             "the session's tree: each frame's status; on the root context_data._plan_approved (true), _plan_version_id, _plan_json (phases[].delegations[].steps[].title, in order) and _step_statuses; on each direct child context_data._plan_claims[] (plan_version_id, steps[].title) and _step_statuses; a status is {status: pending|in_progress|completed|blocked|skipped}. Projected in the page to a step number, a total and at most one title: never a step's description or a status's notes. The page itself reads only _plan_approved, _plan_artifact_id, _plan_version_id, _plan_generated_at, _step_statuses and _plan_claims; _plan_json is the daemon's own, so only this live read can confirm it",
             .planProgress, "Remote/InsightReader.swift"),
        read("GET /api/frames/<session>/verification?resolved_limit=0&actionable_limit=500",
             "{checks: [{verdict: pass|warn|fail|inconclusive, status: open|claimed|resolved|unaddressed, rebuttal, reflag_count}], running: [], completed_review_count, resolved_by_verdict: {fail, warn}}; projected in the page to four counts: never a claim, its evidence or a rebuttal",
             .reviewer, "Remote/InsightReader.swift"),
        read("send_user_message in GET /api/frames/<session>/messages",
             "an assistant row's tool_use block named send_user_message, with input.message (text) and its tool_result {delivered, attachments}; the history reader projects it as a toYou item, and the panel offers the newest page's new ones",
             .notes, "Remote/HistoryReader.swift", check: .whenUsed("it is what was said, so it is never read from here")),
        read("GET /api/csrf", "sets the cookie that writes send back",
             .approve, "Web/WebAPI.swift", check: .whenUsed("read only when a write is refused as stale")),
        read("401 on any /api read", "what a signed-out page answers",
             .signIn, "Web/WebAPI.swift", check: .whenUsed("seen only after a restart")),
    ]

    // MARK: Writes

    private static func write(_ token: String, _ detail: String, _ feature: CompatFeature, _ file: String) -> CompatDependency {
        CompatDependency(kind: .writeEndpoint, token: token, detail: detail, feature: feature, file: file,
                         check: .whenUsed("it changes things, so Diagnostics never sends it"))
    }

    static let writeEndpoints: [CompatDependency] = [
        write("POST /api/frames/<session>/approve-plan", "body {}; answers 200 {status: accepted}, or 400 with plan_already_approved, plan_frame_processing or \"No plan awaiting\"",
              .approve, "Lab/PlanApproval.swift"),
        write("POST /api/frames/<session>/resolve-input", "{responses: [{tool_id, action, answers}]} for a question, {requestId, tool_id, approved, action} for a permission",
              .phone, "Remote/SessionWriter.swift"),
        write("POST /api/request", "{target_agent, root_frame_id, project_id, input_data: {request}, intent_id, plan_mode}: a message to a session",
              .phone, "Remote/SessionWriter.swift"),
        write("POST /api/projects/<project>/request", "{input_data: {request}, plan_mode, intent_id}: a new session",
              .phone, "Remote/SessionWriter.swift"),
        write("POST /api/projects/<project>/attachments", "a multipart file part; answers {id, version_id, filename, content_type, size_bytes}",
              .phone, "Remote/RemotePhotoUpload.swift"),
        write("operon_csrf cookie, x-operon-csrf header", "the cookie's value goes back as the header; a stale one answers 403 csrf_stale",
              .approve, "Web/WebAPI.swift"),
    ]

    // MARK: Command line

    private static func cli(_ token: String, _ detail: String, _ feature: CompatFeature, _ file: String,
                            check: CompatCheck = .live) -> CompatDependency {
        CompatDependency(kind: .cli, token: token, detail: detail, feature: feature, file: file, check: check)
    }

    static let commandLine: [CompatDependency] = [
        cli("claude-science", "the tool is in the own-window app's Contents/Resources/bin (first, once that app is installed), else ~/.local/bin, ~/.claude-science/bin, /opt/homebrew/bin, /usr/local/bin or on PATH",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.running", "a true or false: only an explicit false lets Capsid start a daemon",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.version", "the running version, shown here and compared with the one Capsid was checked with",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.port", "the port the daemon serves on; unknown when status names none, and Capsid guesses no other",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.pid", "the daemon's process, so later checks ask the kernel instead", .start, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.data_dir", "where the daemon keeps its data", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.active_frames", "a count, used only when the database can't be read", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.active_conversations", "a count, kept for completeness", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.launch_context", #"who started the daemon: "app-child" when Claude Science's own app did, which Capsid never starts a daemon beside"#,
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.boot", #"how far the start has come: "serving" once it is up; shown in Diagnostics"#,
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.url_host", #"the host its address uses: "localhost" or "127.0.0.1", which Capsid loads every page from"#,
            .signIn, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.require_token", "true when the daemon insists on a token: shown in Diagnostics only (a browser-tab daemon reports it too, and signs in with a code as it always has)",
            .signIn, "Shared/Core/CLIStatus.swift"),
        cli("url", "prints the sign-in address, with a nonce query item", .signIn, "Shared/Core/CLIStatus.swift",
            check: .whenUsed("run only when signing in")),
        cli("serve --no-browser --detached", "starts the daemon; never run beside the own-window app (com.anthropic.claudescience) or after status said app-child",
            .start, "Web/DaemonController.swift",
            check: .whenUsed("it starts a daemon, so Diagnostics never runs it")),
    ]

    // MARK: Database

    private static func column(_ table: String, _ name: String, _ feature: CompatFeature,
                               optional: Bool = false, detail: String? = nil) -> CompatDependency {
        CompatDependency(kind: .schema, token: "\(table).\(name)",
                         detail: detail ?? (optional ? "used when it is there" : "read by the session queries"),
                         feature: feature, file: "Shared/Core/SQLiteSource.swift", check: .live, optional: optional)
    }

    private static func stored(_ token: String, _ detail: String, _ feature: CompatFeature,
                               file: String = "Shared/Core/SQLiteSource.swift") -> CompatDependency {
        CompatDependency(kind: .schema, token: token, detail: detail, feature: feature, file: file,
                         check: .whenUsed("a value inside the database, seen only when it is read"))
    }

    static let database: [CompatDependency] = [
        stored("active-org.json", "holds org_uuid, which picks the org database", .sessions),
        stored("orgs/<org>/operon-cli.db", "the org's database, read-only, with its -wal file watched", .sessions),

        column("frames", "id", .sessions),
        column("frames", "project_id", .sessions),
        column("frames", "name", .sessions),
        column("frames", "status", .sessions),
        column("frames", "created_at", .sessions),
        column("frames", "updated_at", .sessions),
        column("frames", "completed_at", .sessions),
        column("frames", "last_user_message_at", .sessions),
        column("frames", "root_frame_id", .sessions),
        column("frames", "parent_frame_id", .sessions),
        column("frames", "input_tokens", .sessions),
        column("frames", "output_tokens", .sessions),
        column("frames", "is_hidden", .sessions),
        column("frames", "output_data", .sessions),
        column("frames", "input_data", .browse),
        column("frames", "conversation_type", .sessions),
        column("frames", "agent_name", .sessions),
        column("frames", "task_summary", .browse),
        column("projects", "id", .sessions),
        column("projects", "name", .sessions),
        column("projects", "archived_at", .browse, optional: true),
        column("frame_blobs", "frame_id", .sessions),
        column("frame_blobs", "kind", .sessions),
        column("frame_blobs", "body", .sessions),
        column("frame_messages", "frame_id", .activity),
        column("frame_messages", "msg_json", .activity),
        // Find a figure or file (Find/, since 1.0): the files of every session,
        // one row for each artifact, with its latest version.
        column("artifacts", "id", .find, detail: "read by Find"),
        column("artifacts", "project_id", .find, detail: "read by Find"),
        column("artifacts", "root_frame_id", .find, detail: "read by Find: the session a file belongs to"),
        column("artifacts", "filename", .find, detail: "read by Find"),
        column("artifacts", "latest_version_id", .find, detail: "read by Find: the version a file is listed by"),
        column("artifacts", "is_user_upload", .find, detail: "read by Find: uploads are not files Claude made"),
        column("artifacts", "is_ephemeral", .find, detail: "read by Find"),
        column("artifacts", "priority", .find, detail: "read by Find"),
        column("artifact_versions", "id", .find, detail: "read by Find"),
        column("artifact_versions", "content_type", .find, detail: "read by Find"),
        column("artifact_versions", "size_bytes", .find, detail: "read by Find"),
        column("artifact_versions", "created_at", .find, detail: "read by Find: the date a file shows and is found by"),
        column("artifact_versions", "version_number", .find, detail: "read by Find"),
        column("artifact_versions", "is_intermediate", .find, detail: "read by Find: intermediates are left out"),

        stored("frames.status (values)", "processing, awaiting_user_response, awaiting_plan_approval, completed, success, cancelled, replaced, failed", .sessions),
        stored("frames.conversation_type (uploads)", "uploads marks a project's hidden uploads frame", .sessions),
        stored("frames.agent_name (concierges)", "CONCIERGE and CANVAS_CONCIERGE are not sessions", .sessions),
        stored("projects.id (concierge prefix)", "the concierge's own project starts proj_concierge_sys_", .browse),
        stored("frame_blobs.kind (output)", "a frame's output is read from the row of this kind when the frame holds none", .sessions),
        stored("output_data.pending_input_requests", "a list of pending requests, each with a kind", .sessions),
        stored("msg_json._ts, role, _intent_id, _tokens", "when, who, the intent id, and input and output tokens of a message", .activity),
        stored("input_data._intent_id", "finds the session a lost reply made", .browse),
        stored("artifacts.priority (user_hidden)", "a file the user hid in Claude Science's list is hidden from Find too", .find),
        stored("artifacts.filename (plan, goal)", "plan*.json and goal_*.html are the planner's own files, which Claude Science's list hides; Find does too", .find),
        stored("ix_frames_bench_name_search", "the compact index Claude Science's own ⌘K search reads session titles from; Find asks for it by name only when the database has it, else it reads the wide frames rows", .find),
        stored("ix_artifact_versions_slim_covering", "the covering index of a version's facts; Find asks for it by name only when the database has it", .find),
    ]

    // MARK: Derived

    /// The tables and columns the session queries read, in the inventory's
    /// order: what the Diagnostics schema step checks.
    static var schemaTables: [(table: String, required: [String], optional: [String])] {
        var order: [String] = []
        var required: [String: [String]] = [:]
        var optional: [String: [String]] = [:]
        for item in database where item.check == .live {
            let parts = item.token.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if !order.contains(parts[0]) { order.append(parts[0]) }
            if item.optional { optional[parts[0], default: []].append(parts[1]) } else { required[parts[0], default: []].append(parts[1]) }
        }
        return order.map { ($0, required[$0] ?? [], optional[$0] ?? []) }
    }

    /// What Diagnostics can't try, from the page, the reads and the writes: it
    /// lists them as checked only when used.
    static var whenUsed: [CompatDependency] {
        all.filter { $0.isWhenUsed && ($0.kind == .readEndpoint || $0.kind == .writeEndpoint || $0.kind == .pageHook) }
    }
}

// MARK: The version

/// Claude Science's version against the one Capsid was checked with.
enum ScienceVersion {
    enum Relation: Equatable, Sendable {
        case same
        case newer
        case older
        /// Not the same, and not comparable (a suffix like "-rc1").
        case different
        /// Claude Science didn't say.
        case unknown
    }

    /// "0.1.63" as [0, 1, 63]; nil unless it is whole numbers joined by dots
    /// (a leading "v" is allowed).
    static func parse(_ text: String) -> [Int]? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 6 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    static func relation(running: String?, checkedWith: String = CompatInventory.checkedWith) -> Relation {
        guard let running = running?.trimmingCharacters(in: .whitespacesAndNewlines),
              !running.isEmpty, running.lowercased() != "unknown" else { return .unknown }
        if running == checkedWith { return .same }
        guard var ours = parse(running), var theirs = parse(checkedWith) else { return .different }
        let length = max(ours.count, theirs.count)
        ours += Array(repeating: 0, count: length - ours.count)
        theirs += Array(repeating: 0, count: length - theirs.count)
        if ours == theirs { return .same }
        return ours.lexicographicallyPrecedes(theirs) ? .older : .newer
    }

    /// What the page-dependent features are called in the note, so it says
    /// what to look at.
    private static let affected = "the tab commands, the readouts, Approve"

    /// The Diagnostics lines: the versions, and when they differ a plain note.
    static func lines(running: String?, checkedWith: String = CompatInventory.checkedWith) -> [String] {
        switch relation(running: running, checkedWith: checkedWith) {
        case .same:
            return ["✓ Claude Science \(running!.trimmingCharacters(in: .whitespacesAndNewlines)); Capsid was last checked with \(checkedWith)"]
        case .unknown:
            return ["• Claude Science didn't say which version it is; Capsid was last checked with \(checkedWith)"]
        case .newer:
            return head(running, checkedWith) + [note("a newer Claude Science than")]
        case .older:
            return head(running, checkedWith) + [note("an older Claude Science than")]
        case .different:
            return head(running, checkedWith) + [note("not the Claude Science")]
        }
    }

    /// When the status couldn't be read there is no version to compare, but
    /// the version Capsid was checked with is still worth showing.
    static func checkedOnlyLine(checkedWith: String = CompatInventory.checkedWith) -> String {
        "• Capsid was last checked with Claude Science \(checkedWith)"
    }

    private static func head(_ running: String?, _ checkedWith: String) -> [String] {
        ["• Claude Science \(running!.trimmingCharacters(in: .whitespacesAndNewlines)); Capsid was last checked with \(checkedWith)"]
    }

    private static func note(_ what: String) -> String {
        "  That is \(what) Capsid was checked with, so features that depend on its page (\(affected)) may need a look."
    }
}
