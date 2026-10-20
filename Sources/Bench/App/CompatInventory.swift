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
    /// TESTING.md, 2026-10-17). Move it only after walking `all` again.
    static let checkedWith = "0.1.63"
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
    case closeTabs, tabMenu, signIn, notifications, sessionAddress, previews
    case usage, context, planCard, approve, phone
    case start, sessions, activity, browse

    var title: String {
        switch self {
        case .closeTabs: "Close Other Tabs and Close All Tabs"
        case .tabMenu: "The tab right-click menu"
        case .signIn: "Signing back in"
        case .notifications: "Needs-input cards from the page's notifications"
        case .sessionAddress: "Open on a card, Quick Open and the context ring"
        case .previews: "HTML previews"
        case .usage: "The usage readout, pause and heads-up cards"
        case .context: "The context ring"
        case .planCard: "A plan on its card"
        case .approve: "Approve a plan"
        case .phone: "Capsid on your phone"
        case .start: "Starting Claude Science"
        case .sessions: "Sessions in the Lab"
        case .activity: "The usage graph and the week in review"
        case .browse: "Quick Open, Results and the phone's project list"
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
        default: title
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
        hook("[data-tab-btn]", "the button in a tab that shows it", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("aria-current", #"the attribute that is "true" on the shown tab's button"#,
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("data-shown", "or an attribute on the shown tab itself", .closeTabs, "Web/PageTabs.swift", literal: true),
        hook("button[data-tab-close]", "a tab's own close button, which Capsid presses",
             .closeTabs, "Web/PageTabs.swift", literal: true),
        hook(#"[data-testid="right-tab-strip"] [data-tab-id]"#, "the tab under a right-click",
             .tabMenu, "Web/TabContextMenu.swift",
             check: .whenUsed("seen only on a right-click"), literal: true),
        hook("button, a", "the elements searched for the sign-in button",
             .signIn, "Web/WebContainer.swift", literal: true),
        hook("Sign in", #"a visible button or link reading exactly "Sign in" on the signed-out page"#,
             .signIn, "Web/WebContainer.swift", literal: true),
        hook("?nonce=<code>", "the page signs in with a one-time code on any of its addresses",
             .signIn, "Shared/Core/CLIStatus.swift", check: .whenUsed("seen only while signing in")),
        hook("window.Notification", "the page makes its desktop notifications with new Notification(title, {body, tag, requireInteraction}) and listens for click",
             .notifications, "Web/NotificationBridge.swift", check: .whenUsed("seen only when a session needs you")),
        hook("/projects/<project>/frames/<session>", "a session's page has this address",
             .sessionAddress, "Web/WebAPI.swift"),
        hook("another localhost port", "generated HTML previews are served from a port of their own",
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
        read("GET /api/frames/<session>?shallow=true", "status, and the plan fields of context_data and output_data; the phone reads it too",
             .planCard, "Lab/PlanApproval.swift"),
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
        cli("claude-science", "the tool is in ~/.local/bin, ~/.claude-science/bin, /opt/homebrew/bin, /usr/local/bin or on PATH",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.running", "a true or false: only an explicit false lets Capsid start a daemon",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.version", "the running version, shown here and compared with the one Capsid was checked with",
            .start, "Shared/Core/CLIStatus.swift"),
        cli("status.port", "the port the daemon serves on", .start, "Shared/Core/CLIStatus.swift"),
        cli("status.pid", "the daemon's process, so later checks ask the kernel instead", .start, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.data_dir", "where the daemon keeps its data", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.active_frames", "a count, used only when the database can't be read", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("status.daemon.active_conversations", "a count, kept for completeness", .sessions, "Shared/Core/CLIStatus.swift"),
        cli("url", "prints the sign-in address, with a nonce query item", .signIn, "Shared/Core/CLIStatus.swift",
            check: .whenUsed("run only when signing in")),
        cli("serve --no-browser --detached", "starts the daemon", .start, "Web/DaemonController.swift",
            check: .whenUsed("it starts a daemon, so Diagnostics never runs it")),
    ]

    // MARK: Database

    private static func column(_ table: String, _ name: String, _ feature: CompatFeature,
                               optional: Bool = false) -> CompatDependency {
        CompatDependency(kind: .schema, token: "\(table).\(name)", detail: optional ? "used when it is there" : "read by the session queries",
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

        stored("frames.status (values)", "processing, awaiting_user_response, awaiting_plan_approval, completed, success, cancelled, replaced, failed", .sessions),
        stored("frames.conversation_type (uploads)", "uploads marks a project's hidden uploads frame", .sessions),
        stored("frames.agent_name (concierges)", "CONCIERGE and CANVAS_CONCIERGE are not sessions", .sessions),
        stored("projects.id (concierge prefix)", "the concierge's own project starts proj_concierge_sys_", .browse),
        stored("frame_blobs.kind (output)", "a frame's output is read from the row of this kind when the frame holds none", .sessions),
        stored("output_data.pending_input_requests", "a list of pending requests, each with a kind", .sessions),
        stored("msg_json._ts, role, _intent_id, _tokens", "when, who, the intent id, and input and output tokens of a message", .activity),
        stored("input_data._intent_id", "finds the session a lost reply made", .browse),
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
