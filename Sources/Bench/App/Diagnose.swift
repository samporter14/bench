// Diagnose.swift — what Bench can and can't see of Claude Science on this
// Mac, step by step. For when the scenes or the needs-input cards don't come:
// they rest on reading Claude Science's session database, and this says which
// step fails. Two ways in: `Bench --diagnose` prints it and exits, and
// Help → Bench Diagnostics… shows it in a window with a Copy button.
//
// It names no projects, sessions or org IDs: only yes/no, versions, folders,
// sizes, ages and counts, so it is safe to paste into a message.
//
//   /Applications/Bench.app/Contents/MacOS/Bench --diagnose
import AppKit
import SwiftUI

enum Diagnose {
    /// What the session queries read, by table (Shared/Core/SQLiteSource.swift).
    private static let expected: [(table: String, columns: [String])] = [
        ("frames", ["id", "project_id", "name", "status", "created_at", "updated_at", "completed_at",
                    "last_user_message_at", "root_frame_id", "parent_frame_id", "input_tokens",
                    "output_tokens", "is_hidden", "output_data"]),
        ("projects", ["id", "name"]),
        ("frame_blobs", ["frame_id", "kind", "body"]),
        ("frame_messages", ["frame_id", "msg_json"]),
    ]

    @MainActor
    static func runIfAsked() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        report().forEach { print($0) }
        exit(0)
    }

    /// The whole report, one line per step. Blocking (it runs the CLI and
    /// sqlite3): call it off the main thread in the app.
    static func report() -> [String] {
        var out: [String] = []
        let info = Bundle.main.infoDictionary
        let bench = info?["CFBundleShortVersionString"] as? String ?? "(unbundled)"
        out.append("Bench \(bench) diagnostics. Nothing below names your projects or sessions.")
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("This copy of Bench: \(tilde(Bundle.main.bundlePath))")

        // 1. The command-line tool, which starts and describes the daemon.
        guard let cli = resolveCLI() else {
            out.append("✗ claude-science: not found in ~/.local/bin, ~/.claude-science/bin, /usr/local/bin, /opt/homebrew/bin or PATH")
            return out
        }
        out.append("✓ claude-science: \(tilde(cli.path))")
        do {
            let status = try fetchCLIStatus()
            out.append("✓ Claude Science is running: version \(status.version), port \(status.port)")
            out.append("  its data folder: \(status.dataDir.map(tilde) ?? "not reported")")
        } catch let error as ScienceError {
            out.append("✗ Claude Science status: \(error.label) (\(detail(error)))")
        } catch {
            out.append("✗ Claude Science status: \(error)")
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
        let sqlite = resolveSqlite3()
        out.append("✓ sqlite3: \(sqlite.path)")

        // 3. Its layout: a table or column the queries need that isn't there
        // is the likeliest break after a Claude Science update.
        for (table, columns) in expected {
            switch schema(of: table, in: db, sqlite: sqlite) {
            case .failure(let message):
                out.append("✗ Table \(table): \(message)")
            case .success(let present) where present.isEmpty:
                out.append("✗ Table \(table): missing")
            case .success(let present):
                let missing = columns.filter { !present.contains($0) }
                out.append(missing.isEmpty ? "✓ Table \(table): all \(columns.count) columns"
                                           : "✗ Table \(table): missing \(missing.joined(separator: ", "))")
            }
        }

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

    private enum Columns {
        case success(Set<String>)
        case failure(String)
    }

    /// The table's column names, or SQLite's own error message: the one thing
    /// the app's reads throw away.
    private static func schema(of table: String, in db: URL, sqlite: URL) -> Columns {
        let task = Process()
        task.executableURL = sqlite
        task.arguments = ["-list", "file:\(db.path)?mode=ro", "SELECT name FROM pragma_table_info('\(table)');"]
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return .failure("couldn't run sqlite3: \(error.localizedDescription)") }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errors = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(message.isEmpty ? "sqlite3 exited \(task.terminationStatus)" : message)
        }
        let names = String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        return .success(Set(names))
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

/// Help → Bench Diagnostics…: the same report, with Copy.
@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: DiagnosticsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Bench Diagnostics"
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
            lines = report
            running = false
        }
    }
}
