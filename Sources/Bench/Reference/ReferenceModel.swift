// ReferenceModel.swift — the reference reader's answers (DESIGN.md,
// Reference): Claude's answers in one session, read from the page's history a
// page at a time from the newest end, and which one is shown. The window
// (ReferenceWindow.swift) draws it; the rules are pure and tested on made-up
// pages, and every read goes through the reading gate (ReadingGate.swift), so
// one is in flight at a time and none starts while the user is typing.
import AppKit
import Foundation

/// One of Claude's answers, as the reader shows it.
struct ReferenceAnswer: Equatable, Sendable, Identifiable {
    /// Its row in the session's history.
    let i: Int
    let at: Date?
    /// The page's text, cut at `HistoryReaderScript.turnText` until the whole
    /// turn has been read.
    var text: String
    var cut: Bool
    /// The files the answer showed: the images among them are its figures.
    let files: [HistoryFile]

    var id: Int { i }

    var figures: [HistoryFile] { files.filter { ArtifactGate.thumb(kind: $0.kind) == nil } }
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
    /// A figure's thumbnail bytes; nil when they couldn't be read.
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
                let result = await ReferenceWindowController.transfers.read(.thumb(version: version, width: 120),
                                                                            priority: .thumbnail)
                if case .answered(.bytes(let data)) = result { return data }
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
    static let tooBigSentence = "This part of the conversation is too large to read here. Open it in Claude Science."
    /// Row 0 was read and no answer was found: Claude hasn't answered here.
    static let noAnswersYet = "No answers yet"
    /// Enough pages were read without an answer; Earlier keeps looking.
    static let noAnswerNear = "No answer in the newest messages"

    /// Claude's turns on a page, oldest first.
    static func answers(in page: HistoryPage) -> [ReferenceAnswer] {
        page.items.compactMap { item in
            guard case .turn(let i, .claude, let at, let text, let cut, let files) = item else { return nil }
            return ReferenceAnswer(i: i, at: at, text: text, cut: cut, files: files)
        }
    }

    /// "Claude's answer · 8:47 · 2 of 3", counting the answers read so far,
    /// oldest first; "2 of 3 so far" while earlier rows are still unread.
    static func positionLine(at: Date?, index: Int, count: Int, final: Bool, now: Date,
                             calendar: Calendar = .current, locale: Locale = .current) -> String {
        var parts = ["Claude\u{2019}s answer"]
        if let at { parts.append(when(at, now: now, calendar: calendar, locale: locale)) }
        parts.append("\(index + 1) of \(count)" + (final ? "" : " so far"))
        return parts.joined(separator: " · ")
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

/// The answers read so far and the one shown, for one session's window.
@MainActor
final class ReferenceModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reading
        case failed(String)
    }

    /// Rows a page: half the phone's, so a page lands sooner.
    static let rows = 25
    /// Pages read in a row looking for an answer before stopping (a stretch
    /// of rows may be all steps, plans and questions). Earlier looks again.
    static let pagesPerLook = 8

    let session: SessionStatus
    /// The figures' pictures, decoded small (ShelfThumbnails).
    let thumbnails: ShelfThumbnails
    private let dependencies: ReferenceDependencies
    private let gate: ReadingGate

    /// Oldest first.
    @Published private(set) var answers: [ReferenceAnswer] = []
    /// The shown answer's place in `answers`; nil before one is loaded.
    @Published private(set) var shown: Int?
    @Published private(set) var phase: Phase = .idle
    /// Row 0 has been read: the oldest answer loaded is the session's first.
    @Published private(set) var reachedStart = false
    /// Rows whose whole text couldn't be read: the cut text stays, with a note.
    @Published private(set) var restFailed: Set<Int> = []
    /// Copy with Source just copied: the button says so for a moment.
    @Published private(set) var copied = false
    /// The lowest row read so far; the next page ends before it.
    private(set) var from: Int?
    /// Bumped by `close`: a read that lands afterwards changes nothing.
    private var token = 0
    /// Earlier was pressed at the oldest answer loaded: the next page's newest
    /// answer is shown when it lands, unless the user moved meanwhile.
    private var wantsEarlier = false
    private var pageTask: Task<Void, Never>?
    /// Whole-turn reads under way, by row. One moved away from is left to
    /// land: it is small, and it lands on its row, never on the one shown.
    private var wholeTasks: [Int: Task<Void, Never>] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailsFailed: Set<String> = []
    private var copiedTask: Task<Void, Never>?
    /// Each answer's drawn text, by row, for the text it had when drawn.
    private var drawn: [Int: (text: String, rendered: NSAttributedString)] = [:]

    init(session: SessionStatus, dependencies: ReferenceDependencies, gate: ReadingGate = .shared,
         thumbnails: ShelfThumbnails = ShelfThumbnails()) {
        self.session = session
        self.dependencies = dependencies
        self.gate = gate
        self.thumbnails = thumbnails
    }

    // MARK: What is shown

    var current: ReferenceAnswer? {
        guard let shown, answers.indices.contains(shown) else { return nil }
        return answers[shown]
    }

    /// There is an earlier answer loaded, or earlier rows still to read.
    var canGoEarlier: Bool { (shown ?? 0) > 0 || !reachedStart }
    var canGoLater: Bool {
        guard let shown else { return false }
        return shown + 1 < answers.count
    }

    var positionLine: String? {
        guard let shown, let answer = current else { return nil }
        return ReferenceRules.positionLine(at: answer.at, index: shown, count: answers.count, final: reachedStart,
                                           now: dependencies.now())
    }

    /// The whole text of the shown answer is still being read.
    var readingRest: Bool {
        guard let answer = current else { return false }
        return answer.cut && wholeTasks[answer.i] != nil
    }

    /// An answer's text as drawn, rendered once per text.
    func rendered(_ answer: ReferenceAnswer) -> NSAttributedString {
        if let kept = drawn[answer.i], kept.text == answer.text { return kept.rendered }
        let rendered = dependencies.render(answer.text)
        drawn[answer.i] = (answer.text, rendered)
        return rendered
    }

    // MARK: Moving

    /// The newest answer, read when the window opens.
    func open() {
        guard pageTask == nil, shown == nil else { return }
        readPage()
    }

    func retry() {
        guard case .failed = phase else { return }
        phase = .idle
        readPage()
    }

    func earlier() {
        if let shown, shown > 0 {
            show(shown - 1)
        } else if !reachedStart {
            wantsEarlier = true
            readPage()
        }
    }

    func later() {
        guard let shown, shown + 1 < answers.count else { return }
        show(shown + 1)
    }

    private func show(_ index: Int) {
        wantsEarlier = false
        shown = index
        wholeIfCut()
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

    /// Reads pages back from `from` until one holds an answer, row 0 is
    /// reached, or `pagesPerLook` pages held none.
    private func readPage() {
        guard pageTask == nil, !reachedStart else { return }
        let token = self.token
        phase = .reading
        pageTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.token == token { self.pageTask = nil } }
            var looked = 0
            while looked < Self.pagesPerLook {
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
                    let added = merge(page)
                    if !added.isEmpty || reachedStart {
                        phase = .idle
                        settle(added: added.count)
                        return
                    }
                }
            }
            phase = .idle
            wantsEarlier = false
        }
    }

    /// Takes a page in: its answers go before those loaded (they are older),
    /// and the shown one stays the same answer. Gives how many were new.
    private func merge(_ page: HistoryPage) -> [ReferenceAnswer] {
        let known = Set(answers.map(\.i))
        let added = ReferenceRules.answers(in: page).filter { !known.contains($0.i) }
        answers = (added + answers).sorted { $0.i < $1.i }
        if let shown { self.shown = shown + added.count }
        if let from, page.from >= from {
            // A page that didn't move back (a shape the page shouldn't give): stop here.
            reachedStart = true
        } else {
            from = page.from
            reachedStart = page.from == 0
        }
        return added
    }

    /// After a page with answers: the newest when none was shown, the newest
    /// new one when Earlier asked for it, else where the user is.
    private func settle(added: Int) {
        if shown == nil {
            if !answers.isEmpty { show(answers.count - 1) }
        } else if wantsEarlier, added > 0 {
            show(added - 1)
        }
        wantsEarlier = false
    }

    /// The shown answer's whole text, when the page's was cut: read by row,
    /// once, so a late answer for one row never lands on another.
    private func wholeIfCut() {
        guard let answer = current, answer.cut, !restFailed.contains(answer.i), wholeTasks[answer.i] == nil else { return }
        let token = self.token
        let row = answer.i
        wholeTasks[row] = Task { [weak self] in
            guard let self else { return }
            defer { if self.token == token { self.wholeTasks[row] = nil } }
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
            if let turn, turn.role == .claude, let index = answers.firstIndex(where: { $0.i == row }) {
                answers[index].text = turn.text
                answers[index].cut = false
            } else {
                restFailed.insert(row)
            }
        }
    }

    /// A figure came into view: its thumbnail, once.
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

    // MARK: Acting

    /// Copies `text` (the selection, or the whole answer as drawn) with the
    /// answer's source line and link.
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

    func openInScience() {
        dependencies.open(session)
    }

    /// Keep… on a figure: the Keep sheet's subject for it.
    func keepSubject(_ file: HistoryFile) -> KeepSubject {
        KeepSubject(session: session,
                    entry: ArtifactEntry(version: file.v, artifact: file.a, name: file.name, mime: nil,
                                         size: file.size ?? 0, at: current?.at))
    }
}
