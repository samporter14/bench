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
    /// The files that aren't pictures (a document, a table, a page, a
    /// notebook), in order, one per artifact (the last version of each): what
    /// the Shelf takes beside the figures.
    var files: [HistoryFile] = []
    /// Every version of a picture the reply showed, drafts included, in the
    /// order they came: `figures` keeps one per artifact, and the shelf may
    /// hold an earlier draft of it.
    var pictureVersions: [HistoryFile] = []
    /// The last history row that belongs to the reply: the one before the next
    /// user message's row, so a run of steps that ends the reply (a run
    /// folded into one item, whose id is its first row) still holds its later
    /// rows. Nil for the newest reply read: it runs to the end.
    var rowEnd: Int? = nil
    /// The first row read of the reply. Its id is its last row, which moves as
    /// rows land after it; this stays, so the same reply is told again after
    /// the newest rows are read once more.
    var start: Int = 0

    /// The picture or file in this reply that has `version` (a draft too).
    func file(version: String) -> HistoryFile? {
        pictureVersions.first { $0.v == version } ?? files.first { $0.v == version }
    }

    /// Whether the reply showed this version of anything.
    func shows(version: String) -> Bool { file(version: version) != nil }

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

/// Where Show Where It Came From wants the window: the history row of the
/// message that showed the file, the version to mark, either or both.
struct ReferenceLanding: Equatable, Sendable {
    var row: Int?
    var mark: String?
}

/// A request to scroll the page to a card, by its id (the file's version);
/// the token tells a second request for the same card from the first.
struct ReferenceScroll: Equatable, Sendable {
    let id: String
    let token: Int
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
    /// The shelf the figures and files are put on, and asked about for "On
    /// Shelf ✓" and the mark. Nil is the real one (`ShelfAccess.live`); tests
    /// and snapshots stand a made-up shelf in.
    var shelf: ShelfAccess? = nil

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
            render: { AnswerMarkdown.render($0, style: .reference).text })
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
    /// Figures a reply shows at most; files of other kinds likewise.
    static let figureLimit = 24
    /// Versions of pictures a reply remembers at most, drafts included.
    static let versionLimit = 96

    /// Claude's replies in the rows read, oldest first. A reply begins at one
    /// of the user's turns and runs to the next; the rows before the first of
    /// the user's turns read so far are a reply whose start hasn't been read,
    /// unless they begin the history. `whole` holds turns read whole since, and
    /// `notes` the messages sent to the user mid-run in a row, whole, in order.
    /// A reply with neither words nor figures (only steps, a plan, a
    /// question) isn't one.
    static func answers(items: [HistoryItem], reachedStart: Bool, whole: [Int: String],
                        notes: [Int: [String]] = [:]) -> [ReferenceAnswer] {
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
        return groups.enumerated().compactMap { index, group in
            // The rows up to the next user message are this reply's.
            let end = index + 1 < groups.count ? groups[index + 1][0].index - 1 : nil
            return answer(group, complete: isUsersTurn(group[0]) || reachedStart, whole: whole, notes: notes, end: end)
        }
    }

    private static func isUsersTurn(_ item: HistoryItem) -> Bool {
        if case .turn(_, .you, _, _, _, _) = item { return true }
        return false
    }

    private static func answer(_ group: [HistoryItem], complete: Bool, whole: [Int: String], notes: [Int: [String]],
                               end: Int?) -> ReferenceAnswer? {
        guard let last = group.last else { return nil }
        var question: String?
        var parts: [ReferenceAnswer.Part] = []
        var at: Date?
        var figures: [HistoryFile] = []
        var place: [String: Int] = [:]
        var others: [HistoryFile] = []
        var otherPlace: [String: Int] = [:]
        var versions: [HistoryFile] = []
        // Messages to the user seen so far in each row: the nth of a row is the nth the whole read gives.
        var sent: [Int: Int] = [:]
        func add(_ files: [HistoryFile]) {
            for file in files {
                let key = file.a ?? file.v
                if ArtifactGate.thumb(kind: file.kind) == nil {
                    if !versions.contains(where: { $0.v == file.v }), versions.count < versionLimit { versions.append(file) }
                    if let index = place[key] {
                        figures[index] = file
                    } else if figures.count < figureLimit {
                        place[key] = figures.count
                        figures.append(file)
                    }
                } else if let index = otherPlace[key] {
                    others[index] = file
                } else if others.count < figureLimit {
                    otherPlace[key] = others.count
                    others.append(file)
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
            case .toYou(let i, let text, let files, let cut):
                let nth = sent[i, default: 0]
                sent[i] = nth + 1
                let full = notes[i].flatMap { nth < $0.count ? $0[nth] : nil }
                let words = (full ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { parts.append(.init(i: i, text: words, cut: full == nil && cut)) }
                add(files)
            case .steps(_, _, _, let files):
                add(files)
            case .plan, .ask, .helper:
                break
            }
        }
        guard !parts.isEmpty || !figures.isEmpty else { return nil }
        return ReferenceAnswer(id: last.index, question: question, at: at, parts: parts, figures: figures, complete: complete,
                               files: others, pictureVersions: versions, rowEnd: end, start: group[0].index)
    }

    /// "Claude's answer · 8:47 · 2 of 3": when Claude last spoke in the
    /// reply, and its place among the session's replies once they are all
    /// read (`final`); before that the place is left out, since a count of
    /// the replies read so far would read as the session's.
    static func caption(at: Date?, index: Int, count: Int, final: Bool, now: Date,
                        calendar: Calendar = .current, locale: Locale = .current) -> String {
        var parts = ["Claude\u{2019}s answer"]
        if let at { parts.append(when(at, now: now, calendar: calendar, locale: locale)) }
        if final { parts.append("\(index + 1) of \(count)") }
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

    /// Pages a landing reads at most (`land`): 80 of 25 rows, 2,000 rows back.
    static let landingPages = 80
    /// What a landing says when the reply it wanted is further back than that.
    static let tooFarSentence = "That reply is further back than Capsid reads at once. Earlier keeps looking."

    let session: SessionStatus
    let thumbnails: ShelfThumbnails
    /// The shelf the window asks about and adds to.
    let shelf: ShelfAccess
    private let dependencies: ReferenceDependencies
    private let gate: ReadingGate

    /// Oldest first.
    @Published private(set) var answers: [ReferenceAnswer] = []
    /// The reply shown, by its id.
    @Published private(set) var shownID: Int?
    /// Which reply the page is on: moves when the window goes to another reply
    /// (not when the reply it is on grows a row), so the page starts at the top
    /// for another reply and stays where it is for the same one.
    @Published private(set) var shownKey = 0
    @Published private(set) var phase: Phase = .idle
    /// Row 0 has been read: the oldest reply read is the session's first.
    @Published private(set) var reachedStart = false
    /// Rows whose whole text couldn't be read: the cut text stays, with a note.
    @Published private(set) var restFailed: Set<Int> = []
    /// Copy with Source just copied: the button says so for a moment.
    @Published private(set) var copied = false
    /// The version a landing came for (Show Where It Came From): its card is
    /// scrolled to, and shown as that version even where the reply went on to
    /// a later draft of the same figure.
    @Published private(set) var marked: String?
    /// Asks the page to scroll to a card: set when a landing finishes.
    @Published private(set) var scrollRequest: ReferenceScroll?
    /// Said under the caption when a landing stopped short.
    @Published private(set) var landingNote: String?
    /// Versions being added to the shelf from this window.
    @Published private(set) var shelving: Set<String> = []
    /// What went wrong with an add, by version: a sentence under the figure.
    @Published private(set) var shelfProblems: [String: String] = [:]
    /// The lowest row read so far; the next page ends before it.
    private(set) var from: Int?
    /// Pages merged, all told.
    private var pageCount = 0
    /// The landing under way, if any, and the page count it began at.
    private var goal: ReferenceLanding?
    private var landingStart = 0
    /// Where each version this window put on the shelf landed.
    private var placements: [String: URL] = [:]
    /// The rows read, as items, by their index.
    private var items: [Int: HistoryItem] = [:]
    /// Turns read whole since their page cut them.
    private var whole: [Int: String] = [:]
    /// The messages sent to the user mid-run in a row, read whole with it.
    private var wholeNotes: [Int: [String]] = [:]
    /// Bumped by `close`: a read that lands afterwards changes nothing.
    private var token = 0
    private var pageTask: Task<Void, Never>?
    private var wholeTasks: [Int: Task<Void, Never>] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailsFailed: Set<String> = []
    /// How many times each figure's picture was asked for.
    private var thumbnailAsks: [String: Int] = [:]
    private var copiedTask: Task<Void, Never>?
    /// When the newest rows were last read: the first page of a look, or a refresh.
    private var lastTail: Date?
    /// Earlier was pressed while a read was under way: it goes when that read ends (one step, and no more).
    private var earlierQueued = false
    /// The session finished while a read was under way: the newest rows are read again when it ends.
    private var refreshQueued = false
    /// The session's state as last told (`sessionChanged`).
    private var lastState: SessionState?
    /// The time, for the few seconds between two reads of the newest rows. Tests move it.
    var clock: @MainActor () -> Date = { Date() }
    /// How long Add to Shelf and Keep… wait, at most, for the rest of a long reply.
    var restWait: Duration = .seconds(2)
    /// Each reply's drawn text, for the text it had when drawn.
    private var drawn: [Int: (text: String, rendered: NSAttributedString)] = [:]

    init(session: SessionStatus, dependencies: ReferenceDependencies, gate: ReadingGate = .shared,
         thumbnails: ShelfThumbnails = ReferenceModel.figureStore()) {
        self.session = session
        self.dependencies = dependencies
        self.gate = gate
        self.thumbnails = thumbnails
        shelf = dependencies.shelf ?? .live
        lastState = session.state
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

    /// The page's first line: "Claude's answer · 8:47 · 2 of 3", the count
    /// only once the session's start has been read (before that it would
    /// count only the answers read so far).
    var caption: String {
        guard let index = shownIndex else { return "Claude\u{2019}s answer" }
        return ReferenceRules.caption(at: answers[index].at, index: index, count: answers.count, final: reachedStart,
                                      now: dependencies.now())
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
    /// and its start are in. With `row` or `mark` (Show Where It Came From) the
    /// window opens on the reply that holds that row, or shows that file,
    /// instead: see `land`.
    func open(at row: Int? = nil, mark: String? = nil) {
        if row != nil || mark != nil {
            land(at: row, mark: mark)
            return
        }
        guard pageTask == nil, shownID == nil else { return }
        look(until: { [unowned self] in answers.last?.complete == true }) { [unowned self] in
            if let newest = answers.last { show(newest.id) }
        }
    }

    func retry() {
        guard case .failed = phase else { return }
        phase = .idle
        if goal != nil {
            landStep()
        } else if shownID == nil {
            open()
        } else {
            completeShown()
        }
    }

    // MARK: Landing

    /// Goes to the reply that holds history row `row` (a reply's rows run from
    /// its user message to the one before the next user message), reading back
    /// as far as that takes, and scrolls to `mark`, the version shelved; with
    /// no row, to the newest reply that shows `mark`; with neither, the newest.
    /// A window already on another reply moves. The reply it lands on is
    /// complete (its question read), and the card for `mark` is shown as that
    /// version and marked "On your shelf" if it is on the shelf.
    func land(at row: Int?, mark: String?) {
        marked = mark
        landingNote = nil
        scrollRequest = nil
        goal = ReferenceLanding(row: row, mark: mark)
        landingStart = pageCount
        // A look already reading (the window just opened) calls `landStep` when it ends.
        landStep()
    }

    /// A landing is still reading toward its reply.
    var isLanding: Bool { goal != nil }

    /// What the rows read so far settle for a landing.
    private enum Landed {
        case found(ReferenceAnswer)
        case needMore
        case nothing
    }

    private func landed(_ goal: ReferenceLanding) -> Landed {
        func settled(_ answer: ReferenceAnswer) -> Landed { answer.complete ? .found(answer) : .needMore }
        if let row = goal.row {
            // Every row from `row` up must be read, or an older reply might be
            // the one that holds it.
            guard reachedStart || (from ?? Int.max) <= row else { return .needMore }
            guard let answer = answers.first(where: { max($0.id, $0.rowEnd ?? Int.max) >= row }) ?? answers.last else {
                return reachedStart ? .nothing : .needMore
            }
            return settled(answer)
        }
        if let mark = goal.mark {
            if let answer = answers.last(where: { $0.shows(version: mark) }) { return settled(answer) }
            // Not in what is read: further back, or not in this session's replies at all.
            guard reachedStart else { return .needMore }
            return answers.last.map(settled) ?? .nothing
        }
        guard let answer = answers.last else { return reachedStart ? .nothing : .needMore }
        return settled(answer)
    }

    private func landStep() {
        guard let goal, pageTask == nil else { return }
        switch landed(goal) {
        case .found(let answer):
            self.goal = nil
            show(answer.id)
            if let mark = goal.mark, answer.shows(version: mark) {
                scrollRequest = ReferenceScroll(id: mark, token: (scrollRequest?.token ?? 0) + 1)
            }
        case .nothing:
            self.goal = nil
        case .needMore:
            let remaining = Self.landingPages - (pageCount - landingStart)
            guard remaining > 0 else {
                // As far as one landing reads: the oldest reply read, and a word.
                self.goal = nil
                landingNote = Self.tooFarSentence
                if let nearest = answers.first(where: \.complete) ?? answers.first { show(nearest.id) }
                return
            }
            look(until: { [unowned self] in
                if case .needMore = landed(goal) { false } else { true }
            }, pages: min(Self.pagesPerLook, remaining)) { [unowned self] in landStep() }
        }
    }

    /// The pictures a reply shows, with the landing's version in the place of
    /// the later draft of the same figure.
    func figures(of answer: ReferenceAnswer) -> [HistoryFile] {
        guard let marked, let wanted = answer.pictureVersions.first(where: { $0.v == marked }) else { return answer.figures }
        let artifact = wanted.a ?? wanted.v
        return answer.figures.map { ($0.a ?? $0.v) == artifact ? wanted : $0 }
    }

    func earlier() {
        if let index = shownIndex, index > 0 {
            earlierQueued = false
            show(answers[index - 1].id)
            completeShown()
            return
        }
        guard !reachedStart else {
            earlierQueued = false
            return
        }
        guard pageTask == nil else {
            // A read is under way, the window's own: the step waits for it. One step, not a pile
            // of them, and only from a reply on the page (before one, there is nowhere to step from).
            earlierQueued = shownID != nil
            return
        }
        let edge = shownID ?? Int.max
        look(until: { [unowned self] in answers.contains { $0.id < edge && $0.complete } }) { [unowned self] in
            // The user may have moved meanwhile: only from the edge does the
            // newest earlier reply take over.
            guard shownID == nil || shownID == edge else { return }
            if let older = answers.last(where: { $0.id < edge }) { show(older.id) }
        }
    }

    func later() {
        earlierQueued = false
        guard let index = shownIndex, index + 1 < answers.count else { return }
        show(answers[index + 1].id)
    }

    /// Shows a reply. `before` is the start of the reply the page was on, when
    /// its id may have moved since (the rows were read again): the page starts
    /// again at its top only for another reply, not for the same one grown.
    private func show(_ id: Int, from before: Int? = nil) {
        if answers.first(where: { $0.id == id })?.start != (before ?? current?.start) { shownKey += 1 }
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
        goal = nil
        earlierQueued = false
        refreshQueued = false
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
    private func look(until done: @escaping @MainActor () -> Bool, pages: Int = ReferenceModel.pagesPerLook,
                      then: @escaping @MainActor () -> Void) {
        guard pageTask == nil else { return }
        guard !reachedStart else {
            then()
            return
        }
        let token = self.token
        phase = .reading
        pageTask = Task { [weak self] in
            guard let self else { return }
            // The look is over before `then` runs, so `then` may start another.
            var looked = 0
            // Nothing read yet always reads; after that, until `done` or the start.
            while looked < pages, !reachedStart, from == nil || !done() {
                let before = from
                let read: ReferencePage
                do {
                    read = try await gate.perform { [dependencies, session] in
                        try await dependencies.readPage(session.id, before)
                    }
                } catch is CancellationError {
                    endLook(token)
                    return
                } catch {
                    guard self.token == token else { return }
                    phase = .failed(ReferenceRules.failureSentence)
                    dropQueued()
                    endLook(token)
                    return
                }
                guard self.token == token else { return }
                switch read {
                case .unreadable:
                    phase = .failed(ReferenceRules.failureSentence)
                    dropQueued()
                    endLook(token)
                    return
                case .tooBig:
                    phase = .failed(ReferenceRules.tooBigSentence)
                    dropQueued()
                    endLook(token)
                    return
                case .page(let page):
                    looked += 1
                    if before == nil { lastTail = clock() }
                    merge(page)
                }
            }
            phase = .idle
            endLook(token)
            then()
            // A landing asked for while this look was reading carries on.
            landStep()
            stepQueued()
        }
    }

    /// What was asked for while a read was under way, now that it is over: the
    /// one Earlier, and a refresh the session's finishing called for.
    private func stepQueued() {
        guard pageTask == nil else { return }
        if earlierQueued {
            earlierQueued = false
            earlier()
        } else if refreshQueued {
            refreshQueued = false
            refresh(afterFinish: true)
        }
    }

    /// A look that failed drops what was waiting on it.
    private func dropQueued() {
        earlierQueued = false
        refreshQueued = false
    }

    /// A look is over: its task is let go, unless the window closed meanwhile.
    private func endLook(_ token: Int) {
        if self.token == token { pageTask = nil }
    }

    /// Takes a page in and works the replies out again; the shown one keeps
    /// its id.
    private func merge(_ page: HistoryPage) {
        pageCount += 1
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
        answers = ReferenceRules.answers(items: Array(items.values), reachedStart: reachedStart, whole: whole, notes: wholeNotes)
    }

    // MARK: Refreshing

    /// No sooner than this after the newest rows were last read, they are read again.
    static let refreshEvery: TimeInterval = 5

    private func recentlyRead() -> Bool {
        guard let lastTail else { return false }
        return clock().timeIntervalSince(lastTail) < Self.refreshEvery
    }

    /// Reads the newest rows again: the window was shown again or became key,
    /// or the session finished the reply it was writing (`afterFinish`, which
    /// is not held to the few seconds). A reply that has landed since is
    /// reachable with Later; a window on the newest reply goes to the newest
    /// (that reply grown, or a newer one); one on an older reply stays where
    /// it is. One read at a time, in the place of any look (a look that is
    /// reading calls for it again when it ends, if the session finished), and
    /// quiet: a read that fails changes nothing. The rows between the new
    /// ones and what was read before are read too, a look's worth; further
    /// than that, what was read is let go and the window starts from the new
    /// end, as on opening (Earlier reads back again).
    func refresh(afterFinish: Bool = false) {
        guard pageTask == nil, goal == nil else {
            if afterFinish, pageTask != nil { refreshQueued = true }
            return
        }
        guard afterFinish || !recentlyRead() else { return }
        guard shownID != nil else {
            // The first look found no reply, or failed: look again, from the newest end.
            if answers.isEmpty { restart() }
            return
        }
        lastTail = clock()
        let token = self.token
        pageTask = Task { [weak self] in
            guard let self else { return }
            let pages = await readNewest()
            guard self.token == token else { return }
            if let pages { applyNewest(pages) }
            endLook(token)
            landStep()
            stepQueued()
        }
    }

    /// The window has no reply: its first look again.
    private func restart() {
        items = [:]
        from = nil
        reachedStart = false
        answers = []
        phase = .idle
        open()
    }

    /// The newest rows, then pages back from them until they meet what is read
    /// (or a look's worth of pages). Nil when a read failed.
    private func readNewest() async -> [HistoryPage]? {
        let known = items.keys.max()
        var pages: [HistoryPage] = []
        var before: Int?
        while true {
            let read: ReferencePage
            do {
                read = try await gate.perform { [dependencies, session, before] in
                    try await dependencies.readPage(session.id, before)
                }
            } catch {
                return nil
            }
            guard case .page(let page) = read else { return nil }
            // A page that didn't move back (a shape the page shouldn't give): stop here.
            if let before, page.from >= before { break }
            pages.append(page)
            guard let known, page.from > known + 1, page.from > 0, pages.count <= Self.pagesPerLook else { break }
            before = page.from
        }
        return pages
    }

    private func applyNewest(_ pages: [HistoryPage]) {
        guard let low = pages.map(\.from).min() else { return }
        let was = shownID
        let wasStart = current?.start
        let onNewest = was != nil && was == answers.last?.id
        if let known = items.keys.max(), low > known + 1 {
            items = [:]
            from = nil
            reachedStart = false
        } else {
            items = items.filter { $0.key < low }
        }
        for page in pages {
            for item in page.items { items[item.index] = item }
        }
        from = Swift.min(from ?? low, low)
        if low == 0 { reachedStart = true }
        rebuild()
        guard let was else { return }
        // The reader stays on the reply they were reading: its last row may have moved, and when
        // it was the newest they follow it to the newest.
        let target = onNewest ? answers.last
            : (answers.first { $0.id == was } ?? answers.last { $0.start <= was } ?? answers.last)
        if let target { show(target.id, from: wasStart) }
    }

    /// The session's state as the panel's reads have it, told by the window's
    /// owner. A session that stops running has finished the reply it was
    /// writing: the newest rows are read again, at once.
    func sessionChanged(to state: SessionState?) {
        let was = lastState
        lastState = state
        guard was == .running, let state, state != .running else { return }
        refresh(afterFinish: true)
    }

    /// The shown reply's cut turns, read whole.
    private func wholeForShown() {
        guard let answer = current else { return }
        startWhole(for: answer)
    }

    /// A reply's cut turns (and cut messages to the user), each read whole
    /// once, by row, so a late answer for one row never lands on another.
    private func startWhole(for answer: ReferenceAnswer) {
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
                    wholeNotes[row] = turn.notes
                    rebuild()
                    // A message the read had no word of stays cut, and says so.
                    if answers.contains(where: { reply in reply.parts.contains { $0.i == row && $0.cut } }) {
                        restFailed.insert(row)
                    }
                } else {
                    restFailed.insert(row)
                }
            }
        }
    }

    /// Times a figure's picture is asked for again after the store let it go: a
    /// reply with more pictures than the store holds would otherwise ask for
    /// ever, each coming in as another goes out.
    static let thumbnailReAsks = 2

    /// A figure is drawn with no picture: its picture, when it has none and
    /// none is on its way (it comes into view, or the store let it go).
    func wantThumbnail(_ file: HistoryFile) {
        guard ArtifactGate.thumb(kind: file.kind) == nil, !thumbnails.knows(file.v),
              !thumbnailsFailed.contains(file.v), thumbnailTasks[file.v] == nil else { return }
        let asked = thumbnailAsks[file.v, default: 0]
        guard asked <= Self.thumbnailReAsks else {
            // Asked for as often as is fair: the card says it can't be shown.
            thumbnailsFailed.insert(file.v)
            objectWillChange.send()
            return
        }
        thumbnailAsks[file.v] = asked + 1
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

    /// The reply that shows `file`: the one on the page when it does, else the
    /// newest read that does.
    private func answer(showing file: HistoryFile) -> ReferenceAnswer? {
        if let current, current.shows(version: file.v) { return current }
        return answers.last { $0.shows(version: file.v) } ?? current
    }

    /// Keep with Data and Code… on a figure: the Keep sheet's subject for it,
    /// pinned to this answer, so the sheet keeps this version with these words
    /// rather than whatever newer answer shows another.
    func keepSubject(_ file: HistoryFile) -> KeepSubject {
        let reply = answer(showing: file)
        return KeepSubject(session: session,
                           entry: ArtifactEntry(version: file.v, artifact: file.a, name: file.name, mime: nil,
                                                size: file.size ?? 0, at: reply?.at),
                           pinned: reply.map { KeepPinnedAnswer(text: $0.text, at: $0.at, cut: !$0.cutRows.isEmpty) },
                           selectsItsVersion: true)
    }

    /// Waits, a couple of seconds at most (`restWait`), for the rest of the long
    /// turns of the reply that shows `file` to be read: Add to Shelf and Keep…
    /// are pressed on a figure at any time, and the words kept with it should
    /// be whole when they can be. The reads of a reply that isn't the one on
    /// the page are started here. Words still cut when it ends are said to be
    /// (`KeepPinnedAnswer.cut`), in the README.
    func restRead(for file: HistoryFile) async {
        guard let reply = answer(showing: file), !reply.cutRows.isEmpty else { return }
        startWhole(for: reply)
        let start = reply.start
        let time = ContinuousClock()
        let deadline = time.now + restWait
        while time.now < deadline, restIsBeingRead(inReplyStartingAt: start) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func restIsBeingRead(inReplyStartingAt start: Int) -> Bool {
        guard let reply = answers.first(where: { $0.start == start }) else { return false }
        return reply.cutRows.contains { wholeTasks[$0] != nil }
    }

    // MARK: The shelf

    /// What the shelf is told: this file, this reply's words and time, the
    /// reply's last row (the shelf finds the way back with it) and what the
    /// user asked.
    func shelfSource(_ file: HistoryFile) -> ShelfSource {
        let reply = answer(showing: file)
        return ShelfSource(session: session,
                           entry: ArtifactEntry(version: file.v, artifact: file.a, name: file.name, mime: nil,
                                                size: file.size ?? 0, at: reply?.at),
                           answer: reply.map { KeepPinnedAnswer(text: $0.text, at: $0.at, cut: !$0.cutRows.isEmpty) },
                           row: reply?.id, question: reply?.question)
    }

    /// Where a file stands on the shelf, for its pill and its mark.
    func shelfMark(_ file: HistoryFile) -> ShelfMark {
        shelving.contains(file.v) ? .adding : ShelfMark(file.v, in: shelf)
    }

    /// Add to Shelf on a figure or a file. One at a time per file; a failure
    /// is a sentence under the file until the next try.
    @discardableResult
    func addToShelf(_ file: HistoryFile) async -> ShelfAddOutcome? {
        guard shelfMark(file) == .off, !shelving.contains(file.v) else { return nil }
        let version = file.v
        shelving.insert(version)
        shelfProblems[version] = nil
        defer { shelving.remove(version) }
        let token = self.token
        // The words go with it whole, when the reads under way bring the rest in time.
        await restRead(for: file)
        guard self.token == token else { return nil }
        let source = shelfSource(file)
        let outcome = await shelf.add(source)
        guard self.token == token else { return outcome }
        switch outcome {
        case .added(let placement), .alreadyOnShelf(let placement): placements[version] = placement.folder
        case .failed(let sentence): shelfProblems[version] = sentence
        }
        return outcome
    }

    /// "On Shelf ✓": the Shelf window, on the item when this window put it there.
    func showOnShelf(_ file: HistoryFile) {
        shelf.show(placements[file.v])
    }
}
