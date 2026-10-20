// FailureReason.swift — why a session stopped, for its failure card (DESIGN.md,
// Why it stopped, on the failure card).
//
// Claude Science writes the reason itself: when a frame fails it sets its
// status to `failed` and keeps the error text in `output_data.error`, with
// `error_status` beside it (the frame's own page unwraps that text and shows
// it under "Agent Failed"). Capsid reads it from the root frame's shallow read
// (`GET /api/frames/<id>?shallow=true`, the read the plan card makes), which
// carries `output_data` whole.
//
// Everything that decides what the card says is pure (`FailureFrame`,
// `FailureReason`, `ReasonText`) and tested on made-up JSON. `FailureReasoner`
// is the thin part that reads through the page. The reason is session content:
// it is kept in memory only, for as long as the card is up, and is never
// logged, saved or sent anywhere.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "failure")

// MARK: What is read

/// The few fields of a session's root frame that say whether and why it failed
/// (`GET /api/frames/<id>?shallow=true`). Nothing else of the frame is kept.
struct FailureFrame: Equatable, Sendable {
    /// The longest error text kept, in characters, from whatever the frame
    /// held: an odd answer (a whole HTML error page) can't make the card keep
    /// more than this.
    static let errorLimit = 20_000

    /// The frame's own status: `failed` once it stopped with an error.
    let status: String
    /// `output_data.error`, when it is a string with something in it.
    let error: String?
    /// `output_data.error_status`, an HTTP status, when it is a whole number
    /// that is one.
    let httpStatus: Int?

    init(status: String, error: String?, httpStatus: Int? = nil) {
        self.status = status
        self.error = error
        self.httpStatus = httpStatus
    }

    /// Nil unless the body is a JSON object with a string `status`.
    init?(json data: Data) {
        guard let root = JSONPick.parse(data), let status = JSONPick.string(root["status"]) else { return nil }
        let output = JSONPick.object(root["output_data"])
        self.status = status
        let error = JSONPick.string(output?["error"])
        self.error = error.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String($0.prefix(Self.errorLimit)) }
        httpStatus = Self.http(output?["error_status"])
    }

    /// A JSON number that is a whole HTTP status (a `true` is a 1, so it is none).
    private static func http(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let code = number.doubleValue
        guard code == code.rounded(), (100...599).contains(code) else { return nil }
        return Int(code)
    }
}

/// What the failure card says of why: the first line for the card, and the
/// whole text for Copy.
struct FailureReason: Equatable, Sendable {
    /// The card's line is cut here, in characters; the card cuts it again
    /// where its own line ends, and shows the rest in the line's tooltip.
    static let lineLimit = 160
    /// The text Copy puts on the pasteboard is cut here, in characters, so an
    /// odd error can't make the card hold a page of text in memory.
    static let fullLimit = 4_000
    /// What the line's tooltip shows.
    static let tooltipLimit = 600

    /// The first line of the reason as plain text, on one line.
    let line: String
    /// The whole reason as plain text: the message, then Claude Science's own
    /// detail line ("HTTP 400 · Request ID: …") when it has one.
    let full: String

    init(line: String, full: String) {
        self.line = line
        self.full = full
    }

    /// Nil unless the frame failed and holds an error text with something
    /// readable in it.
    init?(frame: FailureFrame) {
        guard frame.status == FailureCheck.failedStatus, let error = frame.error else { return nil }
        let unwrapped = ReasonText.unwrap(error)
        let message = ReasonText.plain(unwrapped.message)
        guard let line = ReasonText.firstLine(of: message) else { return nil }
        let detail = [frame.httpStatus.map { "HTTP \($0)" }, unwrapped.requestID.map { "Request ID: \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        self.line = line
        full = ReasonText.cut(detail.isEmpty ? message : message + "\n\n" + detail, to: Self.fullLimit)
    }

    /// The first part of the whole text, for the line's tooltip: the card's
    /// line is one line, and the reason is often longer.
    var tooltip: String {
        ReasonText.cut(full, to: Self.tooltipLimit)
    }
}

/// What the card does with the frame's own words.
enum FailureCheck {
    static let failedStatus = "failed"

    /// A card's reason is read only for a full session id, which the shallow
    /// read's path needs (the daemon matches a shorter one by prefix).
    static func framePath(_ sessionID: String) -> String? {
        PlanCheck.framePath(sessionID)
    }

    /// An answer that is not a frame (no JSON object, or no string `status`)
    /// is Claude Science having changed (CompatBreadcrumbs). A frame that no
    /// longer says `failed` (the session ran again meanwhile) or says why not,
    /// is not: it is the ordinary state of things.
    static func miss(_ frame: FailureFrame?) -> CompatMiss? {
        frame == nil ? .failedFrameNotUnderstood : nil
    }
}

// MARK: The words

/// Turns the error text into plain text. Pure. Nothing here ever makes
/// anything but a `String`: the card draws it verbatim, never as markdown or
/// HTML.
enum ReasonText {
    /// The text read for the card is cut here before it is cleaned.
    static let inputLimit = FailureFrame.errorLimit

    /// The message inside Claude Science's error text, as its own page unwraps
    /// it: the text is often an API's answer, `400 {"type": "error", "error":
    /// {"message": "…"}, "request_id": "…"}`, so a leading three-digit status
    /// is dropped before the JSON is parsed, and the message is `error.message`,
    /// else `message`. Beyond the page: an `error` that is itself a string is
    /// the message. Anything that is not such JSON is the message as it is.
    static func unwrap(_ text: String) -> (message: String, requestID: String?) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let digits = body.prefix(3)
        if digits.count == 3, digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let rest = body.dropFirst(3)
            if rest.hasPrefix(" {") { body = rest.dropFirst() }
        }
        guard let object = JSONPick.parse(Data(body.utf8)) else { return (text, nil) }
        let nested = (object["error"] as? [String: Any]).flatMap { nonEmpty(JSONPick.string($0["message"])) }
        let message = nested ?? nonEmpty(JSONPick.string(object["message"])) ?? nonEmpty(JSONPick.string(object["error"]))
        let requestID = nonEmpty(JSONPick.string(object["request_id"])).map(identifier)
        return (message ?? text, requestID.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// The text as plain text: any HTML tags gone, line breaks as `\n`,
    /// control and invisible characters gone, trailing spaces gone, a run of
    /// blank lines one, no blank line at either end. Indentation stays.
    static func plain(_ text: String) -> String {
        let source = strippingHTML(String(text.prefix(inputLimit)))
        var scalars = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in source.unicodeScalars {
            defer { previous = scalar }
            switch scalar.value {
            case 0x0A:
                if previous?.value == 0x0D { continue }
                scalars.append("\n")
            case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                scalars.append("\n")
            case 0x09:
                scalars.append(" ")
            default:
                if !isNoise(scalar) { scalars.append(scalar) }
            }
        }
        var lines: [String] = []
        for raw in String(scalars).split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            while line.last?.isWhitespace == true { line.removeLast() }
            if line.isEmpty, lines.last?.isEmpty != false { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The first line worth showing, on one line: markdown marks, quotes and
    /// bullets off it, white space one space, cut at `FailureReason.lineLimit`.
    /// A Python traceback leads with its own header, so the line is its last,
    /// which says what went wrong. Nil when nothing readable is left.
    static func firstLine(of plain: String) -> String? {
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isFence($0) }
        guard var chosen = lines.first else { return nil }
        if chosen.hasPrefix("Traceback (most recent call last)"), let last = lines.last { chosen = last }
        let words = withoutMarkdown(chosen).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.isEmpty ? nil : cut(words, to: FailureReason.lineLimit)
    }

    /// `text` cut to `limit` characters, with an ellipsis when something is left out.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return text.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: Parts

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A request id kept as one short word: no white space or control
    /// characters, at most 100 characters.
    private static func identifier(_ text: String) -> String {
        String(text.unicodeScalars.filter { !isNoise($0) && !$0.properties.isWhitespace }.prefix(100).map(Character.init))
    }

    /// A control, format (zero-width, direction marks), private-use or
    /// unassigned character: nothing a reader should see in an error.
    private static func isNoise(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: true
        default: false
        }
    }

    /// A line that is only a code fence (```` ``` ```` or `~~~`, with or without a language).
    private static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    /// Whether the text is an HTML page or fragment: an error behind a proxy is
    /// sometimes the proxy's own page. A message that merely mentions a
    /// `<placeholder>` is not.
    private static func looksLikeHTML(_ text: String) -> Bool {
        text.range(of: #"<(?:!doctype|html|head|body|title|div|p|br|center|h[1-6]|pre|span|b|i)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The text of an HTML page: scripts, styles and comments gone, block ends
    /// as line breaks, the other tags gone, the common entities decoded. Plain
    /// text comes back as it is.
    private static func strippingHTML(_ text: String) -> String {
        guard looksLikeHTML(text) else { return text }
        var result = text
        for (pattern, replacement) in [
            (#"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, ""),
            (#"(?s)<!--.*?-->"#, ""),
            (#"(?i)<br\s*/?>|</(?:p|div|li|tr|h[1-6]|pre|title|center)\s*>"#, "\n"),
            (#"<[a-zA-Z!/?][^>]*>"#, " "),
        ] {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// A line without the marks markdown puts on it: heading hashes, quote
    /// arrows and bullets at the start, `[text](link)` as its text, and bold
    /// and code marks. A lone `_` or `*` stays: it is often part of a name.
    private static func withoutMarkdown(_ line: String) -> String {
        var result = line
        for _ in 0..<4 {
            let trimmed = result.replacingOccurrences(of: #"^(?:#{1,6}\s+|>\s*|[-*+]\s+)"#, with: "", options: .regularExpression)
            if trimmed == result { break }
            result = trimmed
        }
        result = result.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`"] { result = result.replacingOccurrences(of: mark, with: "") }
        return result
    }
}

// MARK: The card's state

/// What a failure card shows of why, by session.
enum FailureCardState: Equatable, Sendable {
    /// Reading the frame: the card is as before.
    case loading
    /// The reason, on the card under its title, with Copy.
    case ready(FailureReason)
    /// There is none, or the read failed: the card is as before.
    case unavailable
}

/// Reads why a session stopped for the failure card on top, once, and copies
/// it when asked. One read per card: the state is dropped when the card goes
/// and read afresh if it comes back, and nothing is read again while it stays.
@MainActor
final class FailureReasoner: ObservableObject {
    static let shared = FailureReasoner(model: .shared, dependencies: .live())

    /// Everything that reaches outside, so tests can stand in for it.
    struct Dependencies {
        /// "Show plans, questions and requests on the card" and "Show a card"
        /// are on, and no demo runs: the card shows what the session said,
        /// which that switch is for.
        var isEnabled: @MainActor @Sendable () -> Bool
        /// The page is up, so its API can be called.
        var isReady: @MainActor @Sendable () -> Bool
        /// `WebContainer.apiGET`.
        var get: @MainActor @Sendable (String) async throws -> Data
        /// How long the read may take before the card goes on without it.
        var timeout: Duration
        /// Where Copy puts the text: the general pasteboard, and a private one in tests.
        var pasteboard: NSPasteboard
        /// Where an answer that isn't a frame is noted.
        var breadcrumbs: CompatBreadcrumbs = .shared

        static func live() -> Dependencies {
            Dependencies(
                isEnabled: {
                    let defaults = UserDefaults.standard
                    return Demo.mode == nil && defaults.bool(forKey: SettingsKey.showPlansOnCard)
                        && defaults.bool(forKey: SettingsKey.showCards)
                },
                isReady: { WebContainer.shared.status == .ready },
                get: { path in
                    guard Demo.mode == nil else { throw WebAPIError.notAllowed }
                    return try await WebContainer.shared.apiGET(path)
                },
                timeout: .seconds(5),
                pasteboard: .general)
        }
    }

    /// By session id: only sessions whose failure card is in the queue.
    @Published private(set) var states: [String: FailureCardState] = [:]

    private let model: LabModel
    private let dependencies: Dependencies
    private var tasks: [String: Task<Void, Never>] = [:]
    /// `--demo failed`'s made-up session: nothing is read for it.
    private var demoSessions: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()

    init(model: LabModel, dependencies: Dependencies) {
        self.model = model
        self.dependencies = dependencies
    }

    func state(for sessionID: String) -> FailureCardState? {
        states[sessionID]
    }

    /// The reason a card shows, when it has one.
    func reason(for sessionID: String) -> FailureReason? {
        if case .ready(let reason)? = states[sessionID] { reason } else { nil }
    }

    /// Follows the cards, the settings and the page. Never in a demo.
    func start() {
        guard subscriptions.isEmpty, Demo.mode == nil else { return }
        let center = NotificationCenter.default
        Publishers.Merge3(
            model.$cards.map { _ in () },
            center.publisher(for: UserDefaults.didChangeNotification).map { _ in () },
            WebContainer.shared.$status.map { _ in () })
            // @Published publishes before the value changes: look after it has.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &subscriptions)
    }

    /// Drops what no longer has a failure card to go with, and starts reading
    /// the reason of the card on top if it has none yet. Internal for tests.
    func sync() {
        let enabled = dependencies.isEnabled()
        var failureCards: Set<String> = []
        for case .failed(let session) in model.cards { failureCards.insert(session.id) }
        for id in Array(states.keys) {
            let keep = failureCards.contains(id) && (demoSessions.contains(id) || enabled)
            if !keep { discard(id) }
        }
        guard enabled, case .failed(let session)? = model.cards.first, dependencies.isReady(),
              states[session.id] == nil else { return }
        load(session.id)
    }

    /// Puts the whole reason on the pasteboard. False when the card has none.
    @discardableResult
    func copy(_ sessionID: String) -> Bool {
        guard let reason = reason(for: sessionID) else { return false }
        dependencies.pasteboard.clearContents()
        return dependencies.pasteboard.setString(reason.full, forType: .string)
    }

    /// `--demo failed`: a made-up reason, for a made-up session.
    func showDemo(sessionID: String, reason: FailureReason) {
        demoSessions.insert(sessionID)
        states[sessionID] = .ready(reason)
    }

    /// Waits until the reads under way are done. For tests.
    func settled() async {
        var done: Set<Task<Void, Never>> = []
        while let task = tasks.values.first(where: { !done.contains($0) }) {
            await task.value
            done.insert(task)
        }
    }

    // MARK: Reading

    private func load(_ id: String) {
        states[id] = .loading
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let reason = await self.readReason(id)
            // The card went, or was read afresh, meanwhile: nothing to show.
            guard !Task.isCancelled, self.states[id] == .loading else { return }
            self.states[id] = reason.map(FailureCardState.ready) ?? .unavailable
            log.notice("Reason for a failure card: \(reason == nil ? "none" : "read", privacy: .public)")
        }
    }

    /// The root frame, within the timeout. Nil at the first thing that isn't
    /// as expected: a read that fails or is too slow, a shape that doesn't
    /// match, a session that doesn't say why or no longer stopped.
    private func readReason(_ id: String) async -> FailureReason? {
        guard let path = FailureCheck.framePath(id) else { return nil }
        let get = dependencies.get
        guard case .success(let data) = await CompatProbes.timed(dependencies.timeout, { try await get(path) }) else {
            return nil
        }
        let frame = FailureFrame(json: data)
        if let miss = FailureCheck.miss(frame) { dependencies.breadcrumbs.record(miss) }
        return frame.flatMap { FailureReason(frame: $0) }
    }

    private func discard(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        states.removeValue(forKey: id)
        demoSessions.remove(id)
    }
}
