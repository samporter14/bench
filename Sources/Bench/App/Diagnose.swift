// Diagnose.swift — what Bench can and can't see of Claude Science on this
// Mac, step by step. For when the scenes or the needs-input cards don't come:
// they rest on reading Claude Science's session database, and this says which
// step fails. Two ways in: `Capsid --diagnose` prints it and exits, and
// Help → Capsid Diagnostics… shows it in a window with a Copy button.
//
// The window goes further than the command line: it also looks at the page
// and the API it reads (Compat*.swift, DESIGN.md → Diagnostics), which need
// the open window. Both list what is checked only when used.
//
// It names no projects, sessions or org IDs: only yes/no, versions, folders,
// sizes, ages and counts, so it is safe to paste into a message.
//
//   /Applications/Capsid.app/Contents/MacOS/Capsid --diagnose
import AppKit
import SwiftUI

enum Diagnose {
    @MainActor
    static func runIfAsked() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        report().forEach { print($0) }
        // No web view exists out here, so the page can't be looked at.
        ([CompatReport.notFromTheCommandLine, ""] + CompatReport.whenUsedLines()).forEach { print($0) }
        exit(0)
    }

    /// What the window adds to `report()`: a look at the page and the API it
    /// reads, the Claude Science version Capsid last saw and what its look
    /// after a change found (App/CompatWatch.swift), what is checked only when
    /// used, and the last time a feature found something changed. On the main
    /// actor, for the page.
    @MainActor
    static func pageReport(environment: CompatProbeEnvironment = .live(),
                           breadcrumbs: CompatBreadcrumbs = .shared,
                           watch: CompatWatch = .shared) async -> [String] {
        var out = [""] + CompatReport.probeLines(await CompatProbes.run(environment))
        out += [""] + watch.diagnosticsLines()
        out += [""] + CompatReport.whenUsedLines()
        if let problem = breadcrumbs.line() { out += ["", problem] }
        return out
    }

    /// The whole report, one line per step. Blocking (it runs the CLI and
    /// reads the database): call it off the main thread in the app.
    static func report() -> [String] {
        var out: [String] = []
        let info = Bundle.main.infoDictionary
        let bench = info?["CFBundleShortVersionString"] as? String ?? "(unbundled)"
        out.append("Capsid \(bench) diagnostics. Nothing below names your projects or sessions.")
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("This copy of Capsid: \(tilde(Bundle.main.bundlePath))")

        // 0. Which app Claude Science opens in: a browser tab or its own window
        // (App/ScienceInstall.swift). It decides where the tool is looked for first
        // and whether Capsid ever starts a daemon.
        let install = ScienceInstall.current()
        out.append(contentsOf: install.lines())

        // 1. The command-line tool, which starts and describes the daemon.
        guard let cli = resolveCLI(install: install) else {
            out.append("✗ claude-science: not found in Claude Science's app, ~/.local/bin, ~/.claude-science/bin, /usr/local/bin, /opt/homebrew/bin or PATH")
            return out
        }
        out.append("✓ claude-science: \(tilde(cli.path))")
        do {
            let status = try fetchCLIStatus()
            out.append("✓ Claude Science is running: version \(status.version), port \(status.port.map(String.init) ?? "not reported")")
            out.append("  its data folder: \(status.dataDir.map(tilde) ?? "not reported")")
            out.append(contentsOf: daemonLines(status: status, install: install.opens))
            out.append(contentsOf: ScienceVersion.lines(running: status.version))
        } catch let error as ScienceError {
            out.append("✗ Claude Science status: \(error.label) (\(detail(error)))")
            out.append(startLine(status: nil, install: install.opens))
            out.append(ScienceVersion.checkedOnlyLine())
        } catch {
            out.append("✗ Claude Science status: \(error)")
            out.append(ScienceVersion.checkedOnlyLine())
        }

        // 2. Every data folder and org database Bench considers, and which it
        // picked: the wrong one reads fine and simply has no sessions.
        let home = URL(fileURLWithPath: NSHomeDirectory() + "/.claude-science")
        var bases = [home]
        if let known = ScienceDataDirectory.current?.standardizedFileURL, known != home.standardizedFileURL {
            bases.insert(known, at: 0)
        }
        for base in bases {
            let found = orgDatabases(in: base)
            guard FileManager.default.fileExists(atPath: base.path) else {
                out.append("• \(tilde(base.path)): doesn't exist")
                continue
            }
            out.append("• \(tilde(base.path)): \(found.all.count) org database\(found.all.count == 1 ? "" : "s")")
            for (n, org) in found.all.enumerated() {
                let sessions = (try? runReadOnlyQuery(db: org.url, sql: "SELECT COUNT(*) FROM frames;"))?.first?.first ?? "?"
                var tags: [String] = []
                if org.isActive { tags.append("active") }
                if org.url == found.picked { tags.append("picked") }
                out.append("  org \(n + 1)\(tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"): "
                           + "\(fileSize(org.url)), written \(age(org.lastWrite)), \(sessions) sessions")
            }
        }
        guard let db = resolveDatabase() else {
            out.append("✗ Session database: no readable orgs/<id>/operon-cli.db in those folders")
            return out
        }
        out.append("✓ Reading: \(tilde(db.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)) (\(fileSize(db)))")
        // The library Bench reads with, and whether the database opens with it,
        // read-only, on the connection the app's reads use.
        let library = "SQLite \(SQLiteReader.libraryVersion) (the system library)"
        do {
            _ = try runReadOnlyQuery(db: db, sql: "SELECT COUNT(*) FROM sqlite_schema;")
            out.append("✓ \(library): the database opens read-only")
        } catch let error as ScienceError {
            out.append("✗ \(library): \(detail(error))")
        } catch {
            out.append("✗ \(library): \(error)")
        }

        // 3. Its layout: a table or column the queries need that isn't there
        // is the likeliest break after a Claude Science update.
        out.append(contentsOf: schemaLines(db: db))

        // 4. The reads themselves, as the Lab does them.
        do {
            let frames = try fetchRecentFrames(db: db)
            let states = frames.map { SessionState(frameStatus: $0.status, hasPendingInput: $0.hasPendingInput) }
            let working = states.filter { $0 == .running }.count
            let waiting = states.filter { $0 == .needsInput }.count
            out.append("✓ Recent sessions read: \(frames.count) (\(working) working, \(waiting) waiting on you)")
            let statuses = Set(frames.map(\.status)).sorted().joined(separator: ", ")
            out.append("  statuses seen: \(statuses.isEmpty ? "none" : statuses)")
        } catch let error as ScienceError {
            out.append("✗ Recent sessions: \(error.label) (\(detail(error)))")
        } catch {
            out.append("✗ Recent sessions: \(error)")
        }
        do {
            out.append("✓ Project names read: \(try fetchProjectNames(db: db).count)")
        } catch {
            out.append("✗ Project names: \(error)")
        }
        return out
    }

    /// What `status` said about who started the daemon and how Capsid signs in
    /// to it (the four keys Claude Science's own app added), then what Capsid
    /// does about starting one. Fixed words and the daemon's own short words;
    /// nothing from the page.
    static func daemonLines(status: CLIStatus, install: ScienceInstall.Opens) -> [String] {
        var out: [String] = []
        let started: String
        switch status.launchContext {
        case CLIStatus.appChild?: started = "Claude Science's own app (its child)"
        case let other?: started = "not the app (\(other))"
        case nil: started = "not reported"
        }
        out.append("  started by: \(started)")
        out.append("  boot: \(status.boot ?? "not reported")")
        var address = DaemonHost.name(for: status.urlHost)
        if let named = status.urlHost, DaemonHost.name(for: named) != named {
            address += " (it names \(named); Capsid uses \(address))"
        } else if status.urlHost == nil {
            address += " (it names none)"
        }
        out.append("  address host: \(address)")
        let token = status.requireToken.map { $0 ? "yes" : "no" } ?? "not reported"
        out.append("  requires a token to sign in: \(token)")
        out.append(startLine(status: status, install: install))
        let owned = SignInPlan.appOwned(daemon: status, install: install, handoverSeen: false)
        // As `SignInPlan.decide`: a token matters only beside the app, with no code.
        let signIn: String
        if owned {
            signIn = status.requireToken == true
                ? "• Signing in: through the daemon's own page with a code from claude-science url; with none (it requires a token), Capsid only reads the database"
                : "• Signing in: through the daemon's own page with a code from claude-science url; with none, Capsid only reads the database"
        } else {
            signIn = "• Signing in: with a code from claude-science url"
        }
        out.append(signIn)
        return out
    }

    /// Whether Capsid would start a daemon if none ran.
    static func startLine(status: CLIStatus?, install: ScienceInstall.Opens) -> String {
        // The status in hand speaks for itself; with none, the last one seen does.
        let context = status != nil ? status?.launchContext : ScienceLaunchContext.current
        return switch StartPlan.decide(.notRunning, install: install, lastLaunchContext: context, handoverSeen: false) {
        case .waitForApp: "• Capsid starts Claude Science's server: never, its own app starts it"
        default: "• Capsid starts Claude Science's server: only when none is running, and waits for it"
        }
    }

    /// The main window's side of it, from the open window (the command line
    /// has none).
    @MainActor
    static func windowLines(companion: WebContainer.Companion) -> [String] {
        let line: String
        switch companion {
        case .none: line = "• The main window: signed in, or signing in"
        case .waitingForApp: line = "• The main window: waiting for Claude Science's own app to start its server"
        case .readOnly(let reason): line = "• The main window: only reading the database (\(reason.phrase))"
        }
        return ["", line]
    }

    /// The layout step, one line per table. The list is the inventory's
    /// (`CompatInventory.database`), which the tests hold to what the queries
    /// really read.
    static func schemaLines(db: URL) -> [String] {
        CompatInventory.schemaTables.map { table, columns, optional in
            switch schema(of: table, in: db) {
            case .failure(let message):
                return "✗ Table \(table): \(message)"
            case .success(let present) where present.isEmpty:
                return "✗ Table \(table): missing"
            case .success(let present):
                let missing = columns.filter { !present.contains($0) }
                let absent = optional.filter { !present.contains($0) }
                let extra = absent.isEmpty ? "" : " (\(absent.joined(separator: ", ")) is optional and isn't there)"
                return missing.isEmpty ? "✓ Table \(table): all \(columns.count) columns\(extra)"
                                       : "✗ Table \(table): missing \(missing.joined(separator: ", "))"
            }
        }
    }

    private enum Columns {
        case success(Set<String>)
        case failure(String)
    }

    /// The table's column names, or SQLite's own error message.
    private static func schema(of table: String, in db: URL) -> Columns {
        do {
            let rows = try runReadOnlyQuery(db: db, sql: "SELECT name FROM pragma_table_info(?1);", arguments: [.text(table)])
            return .success(Set(rows.compactMap(\.first)))
        } catch let error as ScienceError {
            return .failure(detail(error))
        } catch {
            return .failure("\(error)")
        }
    }

    private static func detail(_ error: ScienceError) -> String {
        switch error {
        case .cliFailed(let s), .databaseUnreadable(let s), .unknownSchema(let s): s
        default: "\(error)"
        }
    }

    private static func tilde(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }

    private static func fileSize(_ url: URL) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func age(_ date: Date) -> String {
        date == .distantPast ? "never" : date.formatted(.relative(presentation: .named))
    }
}

// MARK: The window

/// Help → Capsid Diagnostics…: the same report, with Copy.
@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiagnosticsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Capsid Diagnostics"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct DiagnosticsView: View {
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(lines.isEmpty ? "Checking…" : lines.joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            HStack(spacing: 8) {
                Text("Nothing here names your projects or sessions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if running { ProgressView().controlSize(.small) }
                Button("Run Again") { run() }
                    .buttonStyle(.glass)
                    .disabled(running)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.clay)
                .disabled(lines.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
        .task { run() }
    }

    private func run() {
        running = true
        Task {
            let report = await Task.detached(priority: .userInitiated) { Diagnose.report() }.value
            // The first part is on screen while the page is looked at.
            lines = report
            lines = report + Diagnose.windowLines(companion: WebContainer.shared.companion) + (await Diagnose.pageReport())
            running = false
        }
    }
}
