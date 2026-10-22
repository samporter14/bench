// ReferenceModel.swift — the reference reader's answers (DESIGN.md,
// Reference): Claude's replies in one session, read from the page's history a
// page at a time from the newest end, and which one is shown. A reply is
// everything Claude did in answer to one of the user's messages: its words,
// and every figure it made or showed on the way (a figure sits on the tool
// step that made it, not on the words after it). The window
// (ReferenceWindow.swift) draws it; the rules are pure and tested on made-up
// pages, and every read goes through the reading gate (ReadingGate.swift), so
// one is in flight at a time and none starts while the user is typing.
import AppKit
import Foundation

/// One of Claude's replies, as the reader shows it.
struct ReferenceAnswer: Equatable, Sendable, Identifiable {
    /// One of Claude's turns in it: its row, its text, whether the page cut it.
    struct Part: Equatable, Sendable {
        let i: Int
        let text: String
        let cut: Bool
    }

    /// The reply's last row: it stays the same as earlier pages are read.
    let id: Int
    /// What the user asked, when that row has been read: its first lines.
    let question: String?
    /// When Claude last spoke in it.
    let at: Date?
    /// Claude's words, oldest first.
    let parts: [Part]
    /// The pictures it made or showed, in order, one per artifact (the last
    /// version of each).
    let figures: [HistoryFile]
    /// The user's message that began it has been read (or the history's start).
    let complete: Bool

    /// The words as one text, a paragraph between turns.
    var text: String { parts.map(\.text).joined(separator: "\n\n") }
    /// The rows whose text the page cut.
    var cutRows: [Int] { parts.filter(\.cut).map(\.i) }
}

/// A page of history, as the reader's reads answer it.
enum ReferencePage: Equatable, Sendable {
    case page(HistoryPage)
    case unreadable
    /// The page's body was over the reader's 2 MiB cap (`HistoryReaderScript.bodyCap`).
    case tooBig
}

/// What the reader reads with and acts through. Tests fake every piece.
struct ReferenceDependencies {
    /// The rows before `before` (the newest rows when nil), `ReferenceModel.rows`
    /// a page. Cancelling the task ends the page's fetch.
    var readPage: @MainActor (_ frameID: String, _ before: Int?) async throws -> ReferencePage
    /// One row's text whole (`HistoryReaderScript.wholeTurn`); nil when it
    /// couldn't be read or isn't a turn.
    var readTurn: @MainActor (_ frameID: String, _ index: Int) async throws -> HistoryTurn?
    /// A figure's picture, 800 pixels wide (WebP); nil when it couldn't be read.
    var thumbnail: @MainActor (_ version: String) async -> Data?
    /// Opens the session in the main window.
    var open: @MainActor (SessionStatus) -> Void
    /// Puts the copied text on the pasteboard; false when it couldn't.
    var pasteboard: @MainActor (String) -> Bool
    /// An answer's text as the window draws it.
    var render: @MainActor (String) -> NSAttributedString
    var now: @Sendable () -> Date = { Date() }

    /// The page's own readers (Remote/HistoryReader.swift): 25 rows a page,
    /// each read under a nonce so cancelling its task aborts the fetch.
    @MainActor
    static func live() -> ReferenceDependencies {
        ReferenceDependencies(
            readPage: { frameID, before in
                guard Demo.mode == nil else { return .unreadable }
                switch try await WebContainer.shared.readHistory(frameID, before: before, rows: ReferenceModel.rows,
                                                                 nonce: ArtifactReadAbort.makeNonce()) {
                case .page(let page): return .page(page)
                case .tooBig: return .tooBig
                // `.same` only answers a read that named a known total; the reader never does.
                case .same, .unreadable: return .unreadable
                }
            },
            readTurn: { frameID, index in
                guard Demo.mode == nil else { return nil }
                let outcome = try await WebContainer.shared.readTurn(frameID, index: index, nonce: ArtifactReadAbort.makeNonce())
                if case .turn(let turn) = outcome { return turn }
                return nil
            },
            thumbnail: { version in
                guard Demo.mode == nil else { return nil }
                let result = await ReferenceWindowController.transfers.read(.thumb(version: version, width: 800),
                                                                            priority: .thumbnail)
                if case .answered(.bytes(let data)) = result, case .success(let webp) = ArtifactGate.thumbBytes(data) {
                    return webp
                }
                return nil
            },
            open: { Router.shared.open($0) },
            pasteboard: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.setString(text, forType: .string)
            },
            render: { AnswerMarkdown.render($0).text })
    }
}

/// The reader's rules, pure.
enum ReferenceRules {
    /// What a read that failed says.
    static let failureSentence = "The conversation couldn't be read. Claude Science may not be up."
    /// A page over the reader's cap: nothing to do here but open it in full.
    static let tooBigSentence = "This part of the conversation is too large to read here. Open the conversation instead."
    /// Row 0 was read and no reply was found: Claude hasn't answered here.
    static let noAnswersYet = "No answers yet"
    /// Enough pages were read without a reply; Earlier keeps looking.
    static let noAnswerNear = "No answer in the newest messages"
    /// The user's message, as the reply shows it: its first lines.
    static let questionLimit = 400
    /// Figures a reply shows at most.
    static let figureLimit = 24

    /// Claude's replies in the rows read, oldest first. A reply begins at one
    /// of the user's turns and runs to the next; the rows before the first of
    /// the user's turns read so far are a reply whose start hasn't been read,
    /// unless they begin the history. `whole` holds turns read whole since.
    /// A reply with neither words nor figures (only steps, a plan, a
    /// question) isn't one.
    static func answers(items: [HistoryItem], reachedStart: Bool, whole: [Int: String]) -> [ReferenceAnswer] {
        var groups: [[HistoryItem]] = []
        var current: [HistoryItem] = []
        for item in items.sorted(by: { $0.index < $1.index }) {
            if isUsersTurn(item), !current.isEmpty {
                groups.append(current)
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { groups.append(current) }
        // Every group but the first begins with the user's turn; the first is
        // whole when it does too, or when it begins the history.
        return groups.compactMap { group in
            answer(group, complete: isUsersTurn(group[0]) || reachedStart, whole: whole)
        }
    }

    private static func isUsersTurn(_ item: HistoryItem) -> Bool {
        if case .turn(_, .you, _, _, _, _) = item { return true }
        return false
    }

    private static func answer(_ group: [HistoryItem], complete: Bool, whole: [Int: String]) -> ReferenceAnswer? {
        guard let last = group.last else { return nil }
        var question: String?
        var parts: [ReferenceAnswer.Part] = []
        var at: Date?
        var figures: [HistoryFile] = []
        var place: [String: Int] = [:]
        func add(_ files: [HistoryFile]) {
            for file in files where ArtifactGate.thumb(kind: file.kind) == nil {
                let key = file.a ?? file.v
                if let index = place[key] {
                    figures[index] = file
                } else if figures.count < figureLimit {
                    place[key] = figures.count
                    figures.append(file)
                }
            }
        }
        for item in group {
            switch item {
            case .turn(_, .you, _, let text, _, _):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { question = String(trimmed.prefix(questionLimit)) }
            case .turn(let i, .claude, let when, let text, let cut, let files):
                let full = whole[i]
                let words = (full ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { parts.append(.init(i: i, text: words, cut: full == nil && cut)) }
                if let when { at = when }
                add(files)
            case .toYou(let i, let text, let files):
                let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { parts.append(.init(i: i, text: words, cut: false)) }
                add(files)
            case .steps(_, _, _, let files):
                add(files)
            case .plan, .ask, .helper:
                break
            }
        }
        guard !parts.isEmpty || !figures.isEmpty else { return nil }
        return ReferenceAnswer(id: last.index, question: question, at: at, parts: parts, figures: figures, complete: complete)
    }

    /// "8:47 · Assay development": when Claude last spoke in the reply, then
    /// the project. The time first, since a narrow window's title bar cuts
    /// the end off. No count: Earlier and Later dim at the ends, and a count
    /// of the replies read so far would read as the session's.
    static func subtitle(project: String, at: Date?, now: Date,
                         calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let at else { return project }
        return when(at, now: now, calendar: calendar, locale: locale) + " · " + project
    }

    /// The time alone on the day it is, else the day and month too. The
    /// calendar's time zone is the one the words are in.
    static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated).hour().minute())
    }

    /// "— Claude, in “Plate reader QC” (Assay development), 22 October 2026, 8:47".
    static func sourceLine(session: SessionStatus, at: Date?) -> String {
        var line = "\u{2014} Claude, in \u{201C}\(session.displayTitle)\u{201D} (\(session.projectName))"
        if let at { line += ", \(KeepRules.longDate(at)), \(KeepRules.longTime(at))" }
        return line
    }

    /// What Copy with Source puts on the pasteboard: the text, a blank line,
    /// the source line and the link that opens the session in Capsid. The
    /// drawn text's line separators (a hard line break, `AnswerMarkdown`)
    /// go back to newlines, which is what a text field or a file expects.
    static func copyText(_ text: String, session: SessionStatus, at: Date?) -> String {
        let body = text.replacingOccurrences(of: "\u{2028}", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body + "\n\n" + sourceLine(session: session, at: at) + "\n" + KeepRules.deepLink(session)
    }

    /// Plain text in the system font, for tests and demos that don't want
    /// Markdown's layout (`AnswerMarkdown.render` is what the window draws).
    static func plainText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
    }
}

/// The replies read so far and the one shown, for one session's window.
@MainActor
final class ReferenceModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reading
        case failed(String)
    }

    /// Rows a page: half the phone's, so a page lands sooner.
    static let rows = 25
    /// Pages read in a row looking for a reply (or a reply's start) before
    /// stopping: a long run of tool steps can fill many. Earlier looks again.
    static let pagesPerLook = 8
    /// The figures' pictures: 800 pixels wide from the daemon, kept within a
    /// byte budget of their own.
    static func figureStore() -> ShelfThumbnails {
        ShelfThumbnails(budget: 48 * 1_024 * 1_024, decoder: { ShelfThumbnails.decode($0, side: 1_200) })
    }

    let session: SessionStatus
    let thumbnails: ShelfThumbnails
    private let dependencies: ReferenceDependencies
    private let gate: ReadingGate

    /// Oldest first.
    @Published private(set) var answers: [ReferenceAnswer] = []
    /// The reply shown, by its id.
    @Published private(set) var shownID: Int?
    @Published private(set) var phase: Phase = .idle
    /// Row 0 has been read: the oldest reply read is the session's first.
    @Published private(set) var reachedStart = false
    /// Rows whose whole text couldn't be read: the cut text stays, with a note.
    @Published private(set) var restFailed: Set<Int> = []
    /// Copy with Source just copied: the button says so for a moment.
    @Published private(set) var copied = false
    /// The lowest row read so far; the next page ends before it.
    private(set) var from: Int?
    /// The rows read, as items, by their index.
    private var items: [Int: HistoryItem] = [:]
    /// Turns read whole since their page cut them.
    private var whole: [Int: String] = [:]
    /// Bumped by `close`: a read that lands afterwards changes nothing.
    private var token = 0
    private var pageTask: Task<Void, Never>?
    private var wholeTasks: [Int: Task<Void, Never>] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailsFailed: Set<String> = []
    private var copiedTask: Task<Void, Never>?
    /// Each reply's drawn text, for the text it had when drawn.
    private var drawn: [Int: (text: String, rendered: NSAttributedString)] = [:]

    init(session: SessionStatus, dependencies: ReferenceDependencies, gate: ReadingGate = .shared,
         thumbnails: ShelfThumbnails = ReferenceModel.figureStore()) {
        self.session = session
        self.dependencies = dependencies
        self.gate = gate
        self.thumbnails = thumbnails
    }

    // MARK: What is shown

    var current: ReferenceAnswer? {
        guard let shownID else { return nil }
        return answers.first { $0.id == shownID }
    }

    private var shownIndex: Int? {
        guard let shownID else { return nil }
        return answers.firstIndex { $0.id == shownID }
    }

    /// There is an earlier reply read, or earlier rows still to read.
    var canGoEarlier: Bool { (shownIndex ?? 0) > 0 || !reachedStart }
    var canGoLater: Bool {
        guard let index = shownIndex else { return false }
        return index + 1 < answers.count
    }

    /// The window's subtitle: the time, then the project.
    var subtitle: String {
        ReferenceRules.subtitle(project: session.projectName, at: current?.at, now: dependencies.now())
    }

    /// Part of the shown reply's text is still being read whole.
    var readingRest: Bool {
        guard let answer = current else { return false }
        return answer.cutRows.contains { wholeTasks[$0] != nil }
    }

    /// Part of the shown reply's text couldn't be read whole.
    var restMissing: Bool {
        guard let answer = current else { return false }
        return answer.cutRows.contains { restFailed.contains($0) }
    }

    /// A reply's text as drawn, rendered once per text.
    func rendered(_ answer: ReferenceAnswer) -> NSAttributedString {
        let text = answer.text
        if let kept = drawn[answer.id], kept.text == text { return kept.rendered }
        let rendered = dependencies.render(text)
        drawn[answer.id] = (text, rendered)
        return rendered
    }

    // MARK: Moving

    /// The newest reply, read when the window opens: pages are read until it
    /// and its start are in.
    func open() {
        guard pageTask == nil, shownID == nil else { return }
        look(until: { [unowned self] in answers.last?.complete == true }) { [unowned self] in
            if let newest = answers.last { show(newest.id) }
        }
    }

    func retry() {
        guard case .failed = phase else { return }
        phase = .idle
        if shownID == nil { open() } else { completeShown() }
    }

    func earlier() {
        if let index = shownIndex, index > 0 {
            show(answers[index - 1].id)
            completeShown()
            return
        }
        guard pageTask == nil, !reachedStart else { return }
        let edge = shownID ?? Int.max
        look(until: { [unowned self] in answers.contains { $0.id < edge && $0.complete } }) { [unowned self] in
            // The user may have moved meanwhile: only from the edge does the
            // newest earlier reply take over.
            guard shownID == nil || shownID == edge else { return }
            if let older = answers.last(where: { $0.id < edge }) { show(older.id) }
        }
    }

    func later() {
        guard let index = shownIndex, index + 1 < answers.count else { return }
        show(answers[index + 1].id)
    }

    private func show(_ id: Int) {
        shownID = id
        wholeForShown()
    }

    /// The shown reply's start hasn't been read: read back until it is.
    private func completeShown() {
        guard let shownID, current?.complete == false, !reachedStart else { return }
        look(until: { [unowned self] in answers.first { $0.id == shownID }?.complete != false }) {}
    }

    /// The window closed: nothing more is read, and what lands is dropped.
    func close() {
        token += 1
        pageTask?.cancel()
        pageTask = nil
        for task in wholeTasks.values { task.cancel() }
        wholeTasks = [:]
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks = [:]
        copiedTask?.cancel()
        thumbnails.removeAll()
    }

    // MARK: Reading

    /// Reads pages back from `from` until `done` holds, row 0 is reached, or
    /// `pagesPerLook` pages have been read; then `then`.
    private func look(until done: @escaping @MainActor () -> Bool, then: @escaping @MainActor () -> Void) {
        guard pageTask == nil else { return }
        guard !reachedStart else {
            then()
            return
        }
        let token = self.token
        phase = .reading
        pageTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.token == token { self.pageTask = nil } }
            var looked = 0
            // Nothing read yet always reads; after that, until `done` or the start.
            while looked < Self.pagesPerLook, !reachedStart, from == nil || !done() {
                let before = from
                let read: ReferencePage
                do {
                    read = try await gate.perform { [dependencies, session] in
                        try await dependencies.readPage(session.id, before)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.token == token else { return }
                    phase = .failed(ReferenceRules.failureSentence)
                    return
                }
                guard self.token == token else { return }
                switch read {
                case .unreadable:
                    phase = .failed(ReferenceRules.failureSentence)
                    return
                case .tooBig:
                    phase = .failed(ReferenceRules.tooBigSentence)
                    return
                case .page(let page):
                    looked += 1
                    merge(page)
                }
            }
            phase = .idle
            then()
        }
    }

    /// Takes a page in and works the replies out again; the shown one keeps
    /// its id.
    private func merge(_ page: HistoryPage) {
        for item in page.items { items[item.index] = item }
        if let from, page.from >= from {
            // A page that didn't move back (a shape the page shouldn't give): stop here.
            reachedStart = true
        } else {
            from = page.from
            reachedStart = page.from == 0
        }
        rebuild()
    }

    private func rebuild() {
        answers = ReferenceRules.answers(items: Array(items.values), reachedStart: reachedStart, whole: whole)
    }

    /// The shown reply's cut turns, each read whole once, by row, so a late
    /// answer for one row never lands on another.
    private func wholeForShown() {
        guard let answer = current else { return }
        for row in answer.cutRows where whole[row] == nil && !restFailed.contains(row) && wholeTasks[row] == nil {
            let token = self.token
            wholeTasks[row] = Task { [weak self] in
                guard let self else { return }
                defer { if self.token == token { self.wholeTasks[row] = nil; self.objectWillChange.send() } }
                let turn: HistoryTurn?
                do {
                    turn = try await gate.perform { [dependencies, session] in
                        try await dependencies.readTurn(session.id, row)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.token == token else { return }
                    restFailed.insert(row)
                    return
                }
                guard self.token == token else { return }
                if let turn, turn.role == .claude, turn.i == row {
                    whole[row] = turn.text
                    rebuild()
                } else {
                    restFailed.insert(row)
                }
            }
        }
    }

    /// A figure came into view: its picture, once.
    func wantThumbnail(_ file: HistoryFile) {
        guard ArtifactGate.thumb(kind: file.kind) == nil, !thumbnails.knows(file.v),
              !thumbnailsFailed.contains(file.v), thumbnailTasks[file.v] == nil else { return }
        let token = self.token
        let version = file.v
        thumbnailTasks[version] = Task { [weak self] in
            guard let self else { return }
            let data = await dependencies.thumbnail(version)
            guard self.token == token else { return }
            thumbnailTasks[version] = nil
            if let data { thumbnails.receive(data, for: version) } else { thumbnailsFailed.insert(version) }
        }
    }

    /// The figure's picture couldn't be read.
    func thumbnailFailed(_ file: HistoryFile) -> Bool { thumbnailsFailed.contains(file.v) }

    // MARK: Acting

    /// Copies `text` (the selection, or the whole reply as drawn) with the
    /// reply's source line and link.
    @discardableResult
    func copy(_ text: String) -> Bool {
        guard let answer = current else { return false }
        let done = dependencies.pasteboard(ReferenceRules.copyText(text, session: session, at: answer.at))
        if done {
            copied = true
            copiedTask?.cancel()
            copiedTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.copied = false
            }
        }
        return done
    }

    func openConversation() {
        dependencies.open(session)
    }

    /// Keep… on a figure: the Keep sheet's subject for it.
    func keepSubject(_ file: HistoryFile) -> KeepSubject {
        KeepSubject(session: session,
                    entry: ArtifactEntry(version: file.v, artifact: file.a, name: file.name, mime: nil,
                                         size: file.size ?? 0, at: current?.at))
    }
}
