// Diagnose.swift — `Bench --diagnose` prints what Bench can and can't see of
// Claude Science on this Mac, step by step, then exits. For when the scenes or
// the needs-input cards don't come: they rest on reading Claude Science's
// session database, and this says which step fails.
//
// It prints no project or session names and no paths inside the org folder:
// only yes/no, versions, counts and column names, so the output is safe to
// paste into a message.
//
//   /Applications/Bench.app/Contents/MacOS/Bench --diagnose
import Foundation

@MainActor
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

    static func runIfAsked() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        let info = Bundle.main.infoDictionary
        let bench = info?["CFBundleShortVersionString"] as? String ?? "(unbundled)"
        print("Bench \(bench) diagnostics. Nothing below names your projects or sessions.")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 1. The command-line tool, which starts and describes the daemon.
        guard let cli = resolveCLI() else {
            print("✗ claude-science: not found in ~/.local/bin, ~/.claude-science/bin, /usr/local/bin, /opt/homebrew/bin or PATH")
            exit(0)
        }
        print("✓ claude-science: \(tilde(cli.path))")
        do {
            let status = try fetchCLIStatus()
            print("✓ Claude Science is running: version \(status.version), port \(status.port)")
        } catch let error as ScienceError {
            print("✗ Claude Science status: \(error.label) (\(detail(error)))")
        } catch {
            print("✗ Claude Science status: \(error)")
        }

        // 2. The session database.
        let base = NSHomeDirectory() + "/.claude-science"
        print(FileManager.default.fileExists(atPath: base) ? "✓ ~/.claude-science exists" : "✗ ~/.claude-science doesn't exist")
        print(FileManager.default.fileExists(atPath: base + "/active-org.json")
              ? "✓ active-org.json exists" : "• active-org.json missing (the newest org is used instead)")
        guard let db = resolveDatabase() else {
            print("✗ Session database: no readable orgs/<id>/operon-cli.db under ~/.claude-science")
            exit(0)
        }
        print("✓ Session database found (operon-cli.db, \(fileSize(db)))")
        let sqlite = resolveSqlite3()
        print("✓ sqlite3: \(sqlite.path)")

        // 3. Its layout: a table or column the queries need that isn't there
        // is the likeliest break after a Claude Science update.
        for (table, columns) in expected {
            switch schema(of: table, in: db, sqlite: sqlite) {
            case .failure(let message):
                print("✗ Table \(table): \(message)")
            case .success(let present) where present.isEmpty:
                print("✗ Table \(table): missing")
            case .success(let present):
                let missing = columns.filter { !present.contains($0) }
                print(missing.isEmpty ? "✓ Table \(table): all \(columns.count) columns"
                                      : "✗ Table \(table): missing \(missing.joined(separator: ", "))")
            }
        }

        // 4. The reads themselves, as the Lab does them.
        do {
            let frames = try fetchRecentFrames(db: db)
            let states = frames.map { SessionState(frameStatus: $0.status, hasPendingInput: $0.hasPendingInput) }
            let working = states.filter { $0 == .running }.count
            let waiting = states.filter { $0 == .needsInput }.count
            print("✓ Recent sessions read: \(frames.count) (\(working) working, \(waiting) waiting on you)")
            let statuses = Set(frames.map(\.status)).sorted().joined(separator: ", ")
            print("  statuses seen: \(statuses.isEmpty ? "none" : statuses)")
        } catch let error as ScienceError {
            print("✗ Recent sessions: \(error.label) (\(detail(error)))")
        } catch {
            print("✗ Recent sessions: \(error)")
        }
        do {
            print("✓ Project names read: \(try fetchProjectNames(db: db).count)")
        } catch {
            print("✗ Project names: \(error)")
        }
        exit(0)
    }

    /// The table's column names, or SQLite's own error message: the one thing
    /// the app's reads throw away.
    private enum Columns {
        case success(Set<String>)
        case failure(String)
    }

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
}
