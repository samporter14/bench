// RemoteBrowseDemo.swift — `--demo remote`'s made-up projects, sessions and
// histories for Phase 3 (DESIGN.md, Phase 3). Every name, sentence and file
// here is invented. Nothing is read from Claude Science or written anywhere;
// a session started from the phone lives in memory until the demo quits.
import Foundation

/// The demo's projects: "Example project" with more than a page of
/// sessions, and a few more; the Now list's made-up sessions belong to them.
@MainActor
final class DemoBrowseStore {
    struct Project: Equatable {
        let id: String
        let name: String
    }

    static let projects: [Project] = [
        Project(id: "proj_demo_example", name: "Example project"),
        Project(id: "proj_demo_sequencing", name: "Sequencing pilot"),
        Project(id: "proj_demo_assay", name: "Assay design"),
        Project(id: "proj_demo_reading", name: "Reading group"),
        Project(id: "proj_demo_cloning", name: "Cloning"),
        Project(id: "proj_demo_microscopy", name: "Microscopy"),
    ]

    /// The made-up project id for a made-up project name.
    static func projectID(for name: String) -> String {
        projects.first { $0.name == name }?.id ?? projects[0].id
    }

    /// The Now list's sessions, as the demo's Lab shows them.
    let nowSessions: [SessionStatus]
    private let nowReads: [String: SessionProjection]
    private var rows: [BrowseRow] = []
    private var reads: [String: SessionProjection] = [:]
    private var histories: [String: DemoHistory] = [:]
    /// A new session's intent id → its project and id.
    private var intents: [String: (project: String, id: String)] = [:]
    private let now: Date

    struct DemoHistory {
        var total: Int
        var items: [HistoryItem]
        /// A cut turn's whole text, by index.
        var whole: [Int: String] = [:]
    }

    init(nowSessions: [SessionStatus], reads: [String: SessionProjection], now: Date = Date()) {
        var seen = Set<String>()
        self.nowSessions = nowSessions.filter { seen.insert($0.id).inserted }
        nowReads = reads
        self.now = now
        for session in self.nowSessions { rows.append(Self.row(session)) }
        makeSessions()
        for session in self.nowSessions {
            histories[session.id] = session.title == "Primer design"
                ? Self.longHistory(now: now) : Self.shortHistory(reads[session.id], title: session.title, now: now)
        }
    }

    // MARK: Reading

    func projectRows() -> [ProjectRow] {
        Self.projects.map { project in
            let mine = rows.filter { $0.projectID == project.id }
            return ProjectRow(id: project.id, name: project.name, sessions: mine.count,
                              lastActiveMs: mine.map(\.updatedMs).max())
        }
        .sorted { ($0.lastActiveMs ?? 0, $1.id) > ($1.lastActiveMs ?? 0, $0.id) }
    }

    /// The database's page, in Swift: newest first by `(updated, id)`, after
    /// the cursor, names containing `search` (any case), 51 at most.
    func page(project: String, after cursor: BrowseCursor?, search: String?) -> [BrowseRow]? {
        guard BrowseSQL.isProjectID(project) else { return nil }
        let sorted = rows.filter { $0.projectID == project }.sorted { ($0.updatedMs, $0.id) > ($1.updatedMs, $1.id) }
        let after = sorted.filter { row in
            guard let cursor else { return true }
            return (row.updatedMs, row.id) < (cursor.updatedMs, cursor.id)
        }
        let found = search.map { text in after.filter { $0.name.localizedCaseInsensitiveContains(text) } } ?? after
        return Array(found.prefix(BrowseSQL.pageSize + 1))
    }

    func lookup(_ id: String) -> SessionStatus? {
        rows.first { $0.id == id }?.status(port: nil)
    }

    /// What the phone reads of a session browsing found (Phase 2's reader).
    func read(_ id: String) -> SessionProjection? {
        reads[id]
    }

    func history(_ id: String, before: Int?) -> HistoryPage? {
        guard let history = histories[id] else { return nil }
        let end = min(before ?? history.total, history.total)
        let start = max(0, end - HistoryReaderScript.pageRows)
        return HistoryPage(total: history.total, from: start,
                           items: history.items.filter { (start..<end).contains($0.index) })
    }

    func turn(_ id: String, index: Int) -> HistoryTurn? {
        guard let history = histories[id] else { return nil }
        for item in history.items where item.index == index {
            if case .turn(let i, let role, let at, let text, _, _) = item {
                return HistoryTurn(i: i, role: role, at: at, text: history.whole[i] ?? text)
            }
        }
        return nil
    }

    // MARK: Starting a session

    /// As the daemon answers `POST /api/projects/<pid>/request`: a new root
    /// that opens and lists; 404 for a project it doesn't have; 409 for an
    /// intent id used before.
    func create(_ write: RemoteWrite) -> RemoteWriteResult? {
        guard case .newSession(let project, let text, let planMode, let intent) = write else { return nil }
        guard Self.projects.contains(where: { $0.id == project }) else { return RemoteWriteResult(status: 404) }
        guard intents[intent] == nil else { return RemoteWriteResult(status: 409, code: "intent_conflict") }
        let id = UUID().uuidString.lowercased()
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        let name = String(text.prefix(50))
        rows.append(BrowseRow(id: id, projectID: project, projectName: Self.name(of: project), name: name,
                              status: "processing", createdMs: at, updatedMs: at, completedMs: nil, turnStartedMs: at))
        let turnAt = Date(timeIntervalSince1970: Double(at) / 1000)
        reads[id] = SessionProjection(status: "processing", agentName: "demo", projectID: project,
                                      statusLine: planMode ? "Drafting a plan first" : "Starting",
                                      turns: [SessionProjection.Turn(role: .you, at: turnAt, text: String(text.prefix(2000)))])
        histories[id] = DemoHistory(total: 1, items: [
            .turn(i: 0, role: .you, at: turnAt, text: String(text.prefix(2000)), cut: text.count > 2000, files: []),
        ], whole: text.count > 2000 ? [0: text] : [:])
        intents[intent] = (project, id)
        return RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: id)
    }

    func session(forIntent intent: String, in project: String) -> String? {
        intents[intent].flatMap { $0.project == project ? $0.id : nil }
    }

    // MARK: Made up

    private static func name(of project: String) -> String {
        projects.first { $0.id == project }?.name ?? ""
    }

    private static func row(_ session: SessionStatus) -> BrowseRow {
        let status: String = switch session.state {
        case .running: "processing"
        case .needsInput: session.waitingReason == .plan ? "awaiting_plan_approval" : "awaiting_user_response"
        case .finished: "completed"
        case .error: "failed"
        case .unknown: "replaced"
        }
        let updated = Int64(session.updatedAt.timeIntervalSince1970 * 1000)
        let started = Int64((session.startedAt ?? session.updatedAt).timeIntervalSince1970 * 1000)
        return BrowseRow(id: session.id, projectID: session.projectID, projectName: session.projectName,
                         name: session.title, status: status, createdMs: started - 30 * 60_000, updatedMs: updated,
                         completedMs: nil, turnStartedMs: started)
    }

    private static let titles = [
        "Melt curve analysis", "Growth curve fits", "Plate reader export", "Western blot quantification",
        "Dose response", "qPCR efficiency check", "Colony counts", "Figure 3 layout", "Stats review",
        "Codon optimisation", "Image segmentation", "Replicate QC", "Sample sheet cleanup", "Literature notes",
        "Protocol draft", "Reagent inventory", "Pilot summary", "Outlier check", "Power analysis", "Buffer screen",
    ]

    /// Made-up sessions for every project: 62 more in Example project, so its
    /// list has two pages, and a few in the others. Ids are shaped like real
    /// ones; one has no name, to show "Untitled session".
    private func makeSessions() {
        let counts = ["proj_demo_example": 62, "proj_demo_sequencing": 7, "proj_demo_assay": 5,
                      "proj_demo_reading": 4, "proj_demo_cloning": 6, "proj_demo_microscopy": 3]
        for (p, project) in Self.projects.enumerated() {
            for k in 0..<(counts[project.id] ?? 0) {
                let id = String(format: "00000000-0000-4000-8%03x-%012x", p + 1, k + 1)
                let base = Self.titles[(k + p * 7) % Self.titles.count]
                let round = (k + p * 7) / Self.titles.count
                let name = project.id == "proj_demo_example" && k == 17 ? "" : round == 0 ? base : "\(base) (\(round + 1))"
                let status = k % 9 == 4 ? "failed" : k % 13 == 7 ? "cancelled" : "completed"
                // Back in time: about five hours apart, with a little jitter.
                let updated = Int64(now.timeIntervalSince1970 * 1000) - Int64(k + 1) * 5 * 3_600_000 - Int64((k * 7919) % 3_600_000)
                let created = updated - Int64(10 + (k * 37) % 80) * 60_000
                rows.append(BrowseRow(id: id, projectID: project.id, projectName: project.name, name: name, status: status,
                                      createdMs: created, updatedMs: updated, completedMs: updated, turnStartedMs: created))
                let turnAt = Date(timeIntervalSince1970: Double(created) / 1000)
                let endAt = Date(timeIntervalSince1970: Double(updated) / 1000)
                let ask = "Please take a look at the \((name.isEmpty ? "data" : base).lowercased())."
                let reply = status == "failed"
                    ? "The run stopped: a made-up input file was missing. Send a message to try again."
                    : "Done. The made-up results are in the session, with a short summary at the top."
                reads[id] = SessionProjection(
                    status: status, agentName: "demo", projectID: project.id,
                    statusLine: status == "failed" ? "Stopped: a made-up input file was missing" : nil,
                    reply: reply, replyAt: endAt,
                    turns: [SessionProjection.Turn(role: .you, at: turnAt, text: ask),
                            SessionProjection.Turn(role: .claude, at: endAt, text: reply)])
                histories[id] = DemoHistory(total: 4, items: [
                    .turn(i: 0, role: .you, at: turnAt, text: ask, cut: false, files: []),
                    .steps(i: 1, line: "Ran 2 commands, read a file", failed: status == "failed", files: []),
                    .turn(i: 3, role: .claude, at: endAt, text: reply, cut: false, files: []),
                ])
            }
        }
    }

    /// A Now session's history, from its made-up turns: a line of steps
    /// between each question and its answer.
    private static func shortHistory(_ read: SessionProjection?, title: String, now: Date) -> DemoHistory {
        let turns = read?.turns ?? [SessionProjection.Turn(role: .you, at: now.addingTimeInterval(-600),
                                                           text: "Start on \(title.lowercased()).")]
        var items: [HistoryItem] = []
        var i = 0
        for turn in turns {
            if turn.role == .claude {
                items.append(.steps(i: i, line: "Read a file, ran a command", failed: false, files: []))
                i += 2
            }
            items.append(.turn(i: i, role: HistoryItem.Role(rawValue: turn.role.rawValue) ?? .you, at: turn.at,
                               text: turn.text, cut: false, files: []))
            i += 1
        }
        return DemoHistory(total: i, items: items)
    }

    private static func file(_ name: String, _ kind: ArtifactKind, _ size: Int) -> HistoryFile {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return HistoryFile(v: "demo-v-\(String(slug))", a: "demo-a-\(String(slug))", name: name, kind: kind, size: size)
    }

    /// "Primer design": well over two pages, with every kind of line: turns,
    /// steps (one failed), a plan, a question and its answer, messages to
    /// you, a helper, files of every kind, and one turn cut short.
    private static func longHistory(now: Date) -> DemoHistory {
        var items: [HistoryItem] = []
        var whole: [Int: String] = [:]
        var row = 0
        let start = now.addingTimeInterval(-6 * 3600)
        func at() -> Date { start.addingTimeInterval(Double(row) * 150) }
        func you(_ text: String) {
            items.append(.turn(i: row, role: .you, at: at(), text: text, cut: false, files: []))
            row += 1
        }
        func claude(_ text: String, files: [HistoryFile] = []) {
            items.append(.turn(i: row, role: .claude, at: at(), text: text, cut: false, files: files))
            row += 1
        }
        func steps(_ line: String, rows: Int, failed: Bool = false) {
            items.append(.steps(i: row, line: line, failed: failed, files: []))
            row += rows
        }
        func special(_ item: (Int) -> HistoryItem) {
            items.append(item(row))
            row += 2
        }

        you("Design primers for the three target genes.")
        claude("I'll start from the made-up reference sequences in the project, then draft a plan.")
        steps("Read 3 files, ran a command", rows: 5)
        special { .plan(i: $0, steps: 5) }
        special { .ask(i: $0, q: "Which melting temperature should the primers aim for?", a: "58 to 62 °C") }
        claude("Thanks. I'll aim for **58 to 62 °C** and keep every product under 300 bases.")

        you("Check the first pair against the off-target list.")
        claude("Checking pair 1 against the made-up off-target list.")
        steps("Ran 4 commands, read a file, ran a search", rows: 7)
        special { .toYou(i: $0, text: "Pair 1 has one weak off-target hit. I'm trying a version shifted by three bases.",
                         files: [file("melt-curves.png", .image, 182_400)]) }
        steps("Ran 2 commands, saved artifacts", rows: 3)
        claude("Pair 1, shifted by three bases, has no off-target hits.", files: [file("pair-1-check.csv", .table, 4_812)])

        let genes = ["gene A", "gene B", "gene C", "gene A (exon 2)", "gene B (exon 4)", "gene C (3′ end)", "the spike-in", "the reference"]
        for (n, gene) in genes.enumerated() {
            you("Now check pair \(n + 2), for \(gene).")
            claude("Looking at pair \(n + 2): GC content first, then hairpins and dimers.")
            steps(n % 3 == 0 ? "Ran 3 commands, read a file" : "Ran 2 commands", rows: 5)
            claude("Pair \(n + 2) looks fine: GC content \(48 + n)%, no hairpins, no dimers above the made-up threshold.")
        }

        you("Can you also design a backup pair for gene B?")
        special { .helper(i: $0) }
        steps("Ran a command, edited a file", rows: 3)
        claude("The backup pair for gene B is ready. It sits 40 bases downstream of the first.",
               files: [file("primer-notes.md", .markdown, 2_310)])

        you("Run the in-silico PCR on all pairs.")
        steps("Ran 3 commands", rows: 4, failed: true)
        claude("The first run failed: the made-up template file was empty. Retrying with the full sequences.")
        steps("Ran 2 commands, saved artifacts", rows: 3)
        claude("All six pairs amplify a single product of the expected size.",
               files: [file("in-silico-pcr.log", .text, 12_044), file("products.fasta", .text, 3_902)])

        you("Write up the method in detail.")
        steps("Read 2 files", rows: 3)
        let paragraph = "Each made-up primer pair was checked for melting temperature, GC content, hairpins, self-dimers "
            + "and cross-dimers, then against the made-up off-target list, and finally by in-silico PCR on the full "
            + "template set. Pairs that failed any check were shifted along the template and checked again. "
        let method = "## Method\n\n" + String(repeating: paragraph, count: 9) + "\n\nThe table lists every pair with its checks."
        whole[row] = method
        items.append(.turn(i: row, role: .claude, at: at(), text: String(method.prefix(1_999)) + "…", cut: true,
                           files: [file("methods.pdf", .pdf, 88_120), file("methods.html", .html, 14_200)]))
        row += 1

        you("Summarise.")
        steps("Ran a command, saved artifacts", rows: 3)
        claude("Designed **6 primer pairs**. All have a melting point between 58 and 62 °C.\n\n1. Pair 1 spans the first exon\n2. Pair 2 is the backup\n\nThe table is in the session.",
               files: [file("primer-pairs.csv", .table, 1_204), file("primer-pairs.ipynb", .notebook, 40_311),
                       file("summary.svg", .svg, 9_870), file("all-files.zip", .other, 2_400_000)])
        return DemoHistory(total: row, items: items, whole: whole)
    }
}
