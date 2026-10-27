// ShowSource.swift — Show Where It Came From (DESIGN.md, Shelf → Show Where It Came
// From). It takes the main window to the session an item came from, in Claude
// Science's own page, scrolled to the reply that made it, with that reply's Generated
// tray in view (Shelf/SourceSeek.swift is the page's side). Until 1.0.7 it opened
// Capsid's small reference reader; that is Open as Reference now, in the Shelf's ⋯
// menus and in the page's own.
//
// Which reply. The item's README names the reply's history row (`source_row`, since
// 1.0.7), and that is used as it stands. An item without one (a figure kept before
// 1.0.7, or one whose answer was a fallback) is looked for: the newest reply that
// shows its version, by the same read Keep and Add to Shelf make
// (`WebContainer.readShowing`, here up to 24 pages of 50 rows instead of six, and
// stopping at the file's own time when a Find result has one). A note (Add Selection
// to Shelf) has no version and the page doesn't say which reply holds a selection, so
// it has no reply: the session opens at its newest reply, and nothing is claimed.
// The same goes for a version no reply was found for.
//
// The window. The session is opened with the Router as every other "open this
// session" is; a window already on it is not reloaded (that would lose the place),
// only brought forward. A read-only Capsid (it can't sign in) opens Claude Science's
// own app, as everything else does, and stops. Nothing is read or looked for until the
// page is up on the session, and a newer click replaces an older one.
//
// If the reply can't be reached in a few seconds the page is left as it was opened.
// One line of fixed words says how far each click got, in the log (`SourceStep`).
import Foundation
import os
import WebKit

private let log = Logger(subsystem: "local.sam.bench", category: "show-source")

/// What Show Where It Came From was asked to show: a session, and what is known of the file
/// and its reply.
struct SourceAsk: Equatable, Sendable {
    var sessionID: String
    var projectID: String
    var title: String
    var projectName: String
    /// The reply's history row, when the item's README has it.
    var row: Int?
    /// The file's version, to find its reply by and to outline its card; nil for a note.
    var version: String?
    /// The file's name, for a card with no picture.
    var name: String?
    /// Not before: the time of the file, when the caller has it.
    var near: Date?
}

extension SourceAsk {
    /// A shelved item. A note has no version, and no row unless its README has one.
    init(_ item: ShelfItem) {
        let record = item.record
        self.init(sessionID: record.sessionID, projectID: record.projectID, title: record.sessionTitle,
                  projectName: record.projectName, row: record.sourceRow, version: item.version, name: item.fileName, near: nil)
    }

    /// A file found in any session (Find): no row, and its time, less a minute for the two clocks' difference, is the
    /// earliest its reply can be.
    init(_ file: FoundFile) {
        self.init(sessionID: file.sessionID, projectID: file.projectID, title: file.sessionTitle,
                  projectName: file.projectName, row: nil, version: file.version, name: file.name,
                  near: file.created.addingTimeInterval(-60))
    }
}

enum ShowSourceRules {
    /// How many pages of 50 rows the look for a version's reply reads, at most (Keep reads six).
    static let lookupPages = 24
    /// The look for the reply, and the wait for the page to come up on the session.
    static let lookupTime: Duration = .seconds(12)
    static let pageWait: Duration = .seconds(20)

    /// The session's address, made only from ids as the database has them.
    @MainActor
    static func address(_ ask: SourceAsk, port: Int?) -> URL? {
        ReferenceWindowController.session(id: ask.sessionID, projectID: ask.projectID, title: ask.title,
                                          projectName: ask.projectName, port: port).deepLink
    }

    /// The row the item names, when it is one the history can have.
    static func knownRow(_ ask: SourceAsk) -> Int? {
        guard let row = ask.row, (0...HistoryReaderScript.maxIndex).contains(row) else { return nil }
        return row
    }

    /// The version to look the reply up by: only when no row is known, and only a version id.
    static func versionToLookUp(_ ask: SourceAsk) -> String? {
        guard knownRow(ask) == nil, let version = ask.version, PlanCheck.isVersionID(version) else { return nil }
        return version
    }

    /// The reply the item points at: the row it names, else the row of the message the look found, else
    /// none (the newest reply), with the step that says which.
    static func reply(for ask: SourceAsk, looked: ShowingRead?) -> (row: Int?, step: SourceStep) {
        if let row = knownRow(ask) { return (row, .rowKnown) }
        if case .found(let message)? = looked, (0...HistoryReaderScript.maxIndex).contains(message.i) { return (message.i, .rowFound) }
        return (nil, .rowNone)
    }

    /// What the page is asked: the reply by its row, else the end of the conversation. The version and the name go
    /// only to outline a card, and only with a row.
    static func request(for ask: SourceAsk, row: Int?) -> SourceSeekRequest {
        guard let row else { return SourceSeekRequest(mode: .newest, row: nil, version: nil, name: nil) }
        let version = ask.version.flatMap { PlanCheck.isVersionID($0) ? $0 : nil }
        return SourceSeekRequest(mode: .reply, row: row, version: version, name: ask.name)
    }
}

/// Every reach into the app and the page, so tests run it all on made-up sessions.
struct ShowSourceDependencies {
    var port: @MainActor () -> Int?
    /// Brings the main window forward and loads the session in it (`Router.open`).
    var open: @MainActor (URL) -> Void
    var showWindow: @MainActor () -> Void
    /// Capsid can't sign in: opening anything opens Claude Science's own app.
    var readOnly: @MainActor () -> Bool
    /// The main window's address is this session.
    var isOn: @MainActor (_ sessionID: String) -> Bool
    /// …and its page is up and loaded.
    var isShowing: @MainActor (_ sessionID: String) -> Bool
    /// The newest reply that shows one of the versions (Remote/HistoryReader.swift).
    var showing: @MainActor (_ frameID: String, _ versions: [String], _ near: Date?) async -> ShowingRead
    /// The page's side (SourceSeek.swift): the steps it took.
    var seek: @MainActor (SourceSeekRequest) async -> [SourceStep]
    /// The line of steps, for the log.
    var note: @MainActor (String) -> Void
    /// A session's page with no conversation to scroll: Claude Science's markup changed (Diagnostics' "Last problem").
    var breadcrumb: @MainActor (CompatMiss) -> Void = { CompatBreadcrumbs.shared.record($0) }
    var wait: @MainActor (Duration) async -> Void = WriteDeadline.sleep
    var poll: Duration = .milliseconds(100)

    @MainActor
    static func live() -> ShowSourceDependencies {
        ShowSourceDependencies(
            port: { WebContainer.shared.port },
            open: { Router.shared.open($0) },
            showWindow: { Router.shared.showWindow() },
            readOnly: { Router.shared.openInScience != nil },
            isOn: { WebContainer.shared.currentFrameID == $0 },
            isShowing: { WebContainer.shared.isShowing(session: $0) },
            showing: { frameID, versions, near in
                guard Demo.mode == nil else { return .unreadable }
                let nonce = UUID().uuidString
                return await withTaskCancellationHandler {
                    (try? await WebContainer.shared.readShowing(frameID: frameID, versions: versions, near: near, nonce: nonce,
                                                                pages: ShowSourceRules.lookupPages)) ?? .unreadable
                } onCancel: {
                    Task { @MainActor in await WebContainer.shared.abortArtifactRead(nonce) }
                }
            },
            seek: { await WebContainer.shared.seekReply($0) },
            note: { line in log.notice("\(line, privacy: .public)") })
    }
}

@MainActor
final class ShowSource {
    static let shared = ShowSource(dependencies: .live())

    private let d: ShowSourceDependencies
    private var current: Task<Void, Never>?

    init(dependencies: ShowSourceDependencies) {
        d = dependencies
    }

    /// Shows where an item came from. A click while an earlier one is still under way replaces it. The task
    /// is for a test to wait for.
    @discardableResult
    func show(_ ask: SourceAsk) -> Task<Void, Never> {
        current?.cancel()
        let task = Task { @MainActor [self] in await run(ask) }
        current = task
        return task
    }

    private func run(_ ask: SourceAsk) async {
        var steps: [SourceStep] = []
        defer { d.note(SourceSeek.line(steps)) }
        guard let url = ShowSourceRules.address(ask, port: d.port()) else {
            d.showWindow()
            steps.append(.noAddress)
            return
        }
        if d.readOnly() {
            d.open(url)
            steps.append(.readOnly)
            return
        }
        if d.isOn(ask.sessionID) {
            d.showWindow()
            steps.append(.alreadyThere)
        } else {
            d.open(url)
            steps.append(.opened)
        }
        guard await waitUntilShowing(ask.sessionID) else {
            if !Task.isCancelled { steps.append(.notReady) }
            return
        }
        // The reply. The look reads from the daemon through the page, so it waits for the page to be up on the session.
        var looked: ShowingRead?
        if let version = ShowSourceRules.versionToLookUp(ask) {
            let raced = await WriteDeadline.race(ShowSourceRules.lookupTime, wait: d.wait, cancel: .finish) { [d] in
                await d.showing(ask.sessionID, [version], ask.near)
            }
            switch raced {
            case .finished(let read): looked = read
            case .timedOut: looked = nil
            case .cancelled: return
            }
        }
        guard !Task.isCancelled else { return }
        let reply = ShowSourceRules.reply(for: ask, looked: looked)
        steps.append(reply.step)
        // A page that went elsewhere meanwhile is not ours to scroll.
        guard d.isShowing(ask.sessionID) else {
            steps.append(.notReady)
            return
        }
        let taken = await d.seek(ShowSourceRules.request(for: ask, row: reply.row))
        steps += taken
        if taken.contains(.noScroller) { d.breadcrumb(.showSourceNoConversation) }
    }

    private func waitUntilShowing(_ sessionID: String) async -> Bool {
        let polls = max(1, Int(ShowSourceRules.pageWait / d.poll))
        for _ in 0..<polls {
            if Task.isCancelled { return false }
            if d.isShowing(sessionID) { return true }
            await d.wait(d.poll)
        }
        return !Task.isCancelled && d.isShowing(sessionID)
    }
}

extension WebContainer {
    /// The main window's page is up on this session: signed in, loaded, and at its address.
    func isShowing(session id: String) -> Bool {
        status == .ready && currentFrameID == id && !webView.isLoading
    }

    /// `SourceSeek.body` in Capsid's own content world on the main window's page: the steps it took, or
    /// `gave-up` when the page isn't up, the script couldn't run (the page went elsewhere), or no answer came
    /// within the waits it was given and a few seconds more. It reads no word of the page.
    func seekReply(_ request: SourceSeekRequest) async -> [SourceStep] {
        guard status == .ready else { return [.gaveUp] }
        let view = webView
        let limit = Duration.milliseconds(2 * request.readyMs + request.seekMs + request.settleMs) + .seconds(5)
        let raced = await WriteDeadline.race(limit, cancel: .ignore) { () async -> [SourceStep] in
            do {
                let value = try await view.callAsyncJavaScript(SourceSeek.body, arguments: request.arguments, in: nil,
                                                               contentWorld: ConversationMenu.world)
                return SourceSeek.steps(of: value) ?? [.gaveUp]
            } catch {
                return [.gaveUp]
            }
        }
        if case .finished(let steps) = raced { return steps }
        return [.gaveUp]
    }
}
