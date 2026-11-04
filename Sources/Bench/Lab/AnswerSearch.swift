// Explicit, bounded search of answer text in a project. Nothing is indexed or saved.
import Foundation
import SwiftUI

struct AnswerSearchMatch: Identifiable, Sendable {
    let session: SessionStatus
    let row: Int
    let snippet: String
    var id: String { "\(session.id):\(row)" }
}

@MainActor
final class AnswerSearch: ObservableObject {
    nonisolated static let sessionLimit = 50
    nonisolated static let pagesPerSession = 6
    nonisolated static let resultLimit = 200

    struct Dependencies {
        var projects: @MainActor () async -> [ProjectRow]?
        var sessions: @MainActor (String) async -> [BrowseRow]?
        var page: @MainActor (String, Int?) async throws -> RemoteBrowser.HistoryRead
        var turn: @MainActor (String, Int) async throws -> HistoryReaderScript.Outcome
        var port: @MainActor () -> Int?

        static func live() -> Dependencies {
            Dependencies(
                projects: {
                    await Task.detached(priority: .utility) {
                        guard let db = resolveDatabase() else { return nil }
                        return try? fetchProjects(db: db)
                    }.value
                },
                sessions: { project in
                    await Task.detached(priority: .utility) {
                        guard let db = resolveDatabase() else { return nil }
                        return (try? fetchProjectSessions(db: db, project: project, after: nil, search: nil)) ?? nil
                    }.value
                },
                page: { id, before in
                    try await ReadingGate.shared.perform {
                        try await WebContainer.shared.readHistory(id, before: before, rows: 50,
                                                                  nonce: ArtifactReadAbort.makeNonce())
                    }
                },
                turn: { id, row in
                    try await ReadingGate.shared.perform {
                        try await WebContainer.shared.readTurn(id, index: row, nonce: ArtifactReadAbort.makeNonce())
                    }
                },
                port: { WebContainer.shared.port })
        }
    }

    @Published private(set) var projects: [ProjectRow] = []
    @Published private(set) var matches: [AnswerSearchMatch] = []
    @Published private(set) var searching = false
    @Published private(set) var status = "Choose a project and search for a phrase."
    private let dependencies: Dependencies
    private var task: Task<Void, Never>?
    private var generation = 0

    init(dependencies: Dependencies = .live()) { self.dependencies = dependencies }

    func loadProjects() async {
        guard let projects = await dependencies.projects() else {
            status = "Projects couldn't be read. Open Claude Science and try again."
            return
        }
        self.projects = projects
    }

    func cancel() {
        if searching { status = "Search canceled. Showing matches found so far." }
        generation += 1
        task?.cancel()
        task = nil
        searching = false
    }

    func clear() {
        cancel()
        matches = []
        status = "Choose a project and search for a phrase."
    }

    func start(project: String, query: String) {
        cancel()
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, BrowseSQL.isProjectID(project) else { return }
        let mine = generation
        matches = []
        searching = true
        status = "Reading sessions\u{2026}"
        ReadingGate.shared.start()
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == mine { searching = false }
            }
            guard let rows = await dependencies.sessions(project) else {
                guard generation == mine, !Task.isCancelled else { return }
                status = "Sessions couldn't be read."
                searching = false
                return
            }
            let sessions = Array(rows.prefix(Self.sessionLimit))
            var incomplete = rows.count > Self.sessionLimit
            var failed = 0
            var seen: Set<String> = []
            for (offset, row) in sessions.enumerated() {
                guard generation == mine, !Task.isCancelled else { return }
                status = "Searching session \(offset + 1) of \(sessions.count)\u{2026}"
                var before: Int?
                var reachedStart = false
                for _ in 0..<Self.pagesPerSession {
                    guard generation == mine, !Task.isCancelled else { return }
                    let response: RemoteBrowser.HistoryRead
                    do { response = try await dependencies.page(row.id, before) }
                    catch is CancellationError {
                        if generation == mine, !Task.isCancelled {
                            status = "Search interrupted. Showing matches found so far."
                        }
                        return
                    }
                    catch { failed += 1; break }
                    guard generation == mine, !Task.isCancelled else { return }
                    guard case .page(let page) = response else { failed += 1; break }
                    for item in page.items {
                        var candidate: (Int, String, Bool, Bool)?
                        switch item {
                        case .turn(let index, .claude, _, let text, let cut, _): candidate = (index, text, cut, false)
                        case .toYou(let index, let text, _, let cut): candidate = (index, text, cut, true)
                        default: break
                        }
                        guard let candidate else { continue }
                        var text = candidate.1
                        if candidate.2 {
                            do {
                                if case .turn(let whole) = try await dependencies.turn(row.id, candidate.0) {
                                    text = candidate.3 ? whole.notes.joined(separator: "\n") : whole.text
                                } else { incomplete = true }
                            } catch is CancellationError {
                                if generation == mine, !Task.isCancelled {
                                    status = "Search interrupted. Showing matches found so far."
                                }
                                return
                            }
                            catch { incomplete = true }
                        }
                        guard generation == mine, !Task.isCancelled else { return }
                        let content = text
                        let snippet = await Task.detached(priority: .userInitiated) { Self.snippet(content, matching: phrase) }.value
                        guard generation == mine, !Task.isCancelled else { return }
                        let key = "\(row.id):\(candidate.0)"
                        if let snippet, seen.insert(key).inserted {
                            matches.append(AnswerSearchMatch(session: row.status(port: dependencies.port()), row: candidate.0, snippet: snippet))
                            if matches.count >= Self.resultLimit { incomplete = true; break }
                        }
                    }
                    if matches.count >= Self.resultLimit { break }
                    if page.from == 0 { reachedStart = true; break }
                    if let before, page.from >= before { failed += 1; break }
                    before = page.from
                }
                if !reachedStart { incomplete = true }
                if matches.count >= Self.resultLimit { break }
            }
            guard generation == mine, !Task.isCancelled else { return }
            searching = false
            let suffix = incomplete || failed > 0 ? " Results may be incomplete\(failed > 0 ? " (\(failed) reads failed)" : "")." : "."
            status = "Found \(matches.count) \(matches.count == 1 ? "match" : "matches")" + suffix
        }
    }

    nonisolated static func snippet(_ text: String, matching phrase: String) -> String? {
        let text = text as NSString
        let match = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive])
        guard match.location != NSNotFound else { return nil }
        let start = max(0, match.location - 70)
        let end = min(text.length, NSMaxRange(match) + 110)
        let safe = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        let excerpt = text.substring(with: safe).replacingOccurrences(of: "\n", with: " ")
        return (safe.location > 0 ? "\u{2026}" : "") + excerpt + (NSMaxRange(safe) < text.length ? "\u{2026}" : "")
    }
}

struct AnswerSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = AnswerSearch()
    @State private var project = ""
    @State private var query: String

    init(query: String) { _query = State(initialValue: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Answers").font(.headline)
            Picker("Project", selection: $project) {
                Text("Choose a project").tag("")
                ForEach(search.projects, id: \.id) { project in
                    Text(project.name.isEmpty ? "Untitled project" : project.name).tag(project.id)
                }
            }
            HStack {
                TextField("Phrase in Claude's answer", text: $query)
                    .onSubmit { search.start(project: project, query: query) }
                if search.searching {
                    Button("Cancel") { search.cancel() }
                } else {
                    Button("Search") { search.start(project: project, query: query) }
                        .disabled(project.isEmpty || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Text("Searches up to 50 recent listed sessions and 300 history rows per session. Nothing is saved.")
                .font(.caption).foregroundStyle(.secondary)
            Text(search.status).font(.caption).foregroundStyle(.secondary)
            List(search.matches) { match in
                Button {
                    dismiss()
                    ReferenceWindowController.shared.show(match.session, at: match.row)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.session.displayTitle).fontWeight(.semibold)
                        Text(match.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 240)
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task { await search.loadProjects() }
        .onDisappear { search.cancel() }
        .onChange(of: project) { _, _ in search.clear() }
        .onChange(of: query) { _, _ in search.clear() }
    }
}
