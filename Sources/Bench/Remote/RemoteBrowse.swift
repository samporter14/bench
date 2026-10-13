// RemoteBrowse.swift — Bench on your phone, Phase 3 (DESIGN.md, Phase 3:
// browse, history, artifacts, new sessions): every project and its sessions
// from Bench's own database reads, a session's whole conversation a page at a
// time through the page (HistoryReader.swift), and starting a session.
//
// The switch (`RemoteBrowse.isOn`) gates every Phase 3 route, the artifact
// routes included: off, they answer 403 `{"error":"browseOff"}`.
// What decides is pure and tested (the routes, the query, the cursor, the
// bodies, the answers); `RemoteBrowser` reads and writes through injected
// closures: the database and the page in the app, made-up sessions in
// `--demo remote` and the tests. Nothing here logs; the server logs the route's
// pattern and status.
import Foundation
import SwiftUI

// MARK: The switch

/// Settings → Phone → "Let paired devices browse every project, full
/// conversations and artifacts" (`remoteBrowse`, on).
enum RemoteBrowse {
    /// On unless it was turned off (as a bool, or as the string a
    /// command-line `-remoteBrowse NO` gives).
    static func setting(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.remoteBrowse) == nil ? true : defaults.bool(forKey: SettingsKey.remoteBrowse)
    }

    /// The one check every Phase 3 route makes first, the artifact routes
    /// included. Off: answer `off` (403 `{"error":"browseOff"}`).
    static var isOn: Bool { setting() }

    /// The error word when it is off.
    static let offError = "browseOff"

    /// 403 `{"error":"browseOff"}`.
    static let off = RemoteActionReply(status: 403, body: Data(#"{"error":"browseOff"}"#.utf8))
}

/// "Let paired devices browse every project, full conversations and
/// artifacts" (`remoteBrowse`, on). A row of Settings → Phone's options,
/// below the actions.
struct RemoteBrowseToggle: View {
    @AppStorage(SettingsKey.remoteBrowse) private var browseOn = true

    var body: some View {
        Toggle(isOn: $browseOn) {
            Text("Let paired devices browse every project, full conversations and artifacts")
            Text("They can also start a session when actions are on. Off, paired devices see only what Now shows, with each session's latest replies.")
        }
    }
}

// MARK: The routes

extension RemoteRoute {
    /// Phase 3's paths, matched exactly and never decoded:
    /// `/api/projects`, `/api/projects/<pid>/sessions` (`^[A-Za-z0-9_-]{1,64}$`),
    /// `/api/sessions/<36>/history` and `/api/sessions/<36>/turn/<0…9999999>`.
    static func browseRoute(for path: Substring) -> RemoteRoute? {
        if path == "/api/projects" { return .projects }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 5, parts[0].isEmpty, parts[1] == "api" else { return nil }
        switch parts[2] {
        case "projects":
            guard parts.count == 5, BrowseSQL.isProjectID(parts[3]), parts[4] == "sessions" else { return nil }
            return .projectSessions(String(parts[3]))
        case "sessions":
            let id = String(parts[3])
            guard PlanCheck.isFrameID(id) else { return nil }
            if parts.count == 5, parts[4] == "history" { return .history(id) }
            if parts.count == 6, parts[4] == "turn", let index = BrowseQuery.index(parts[5]) { return .turn(id, index) }
            return nil
        default:
            return nil
        }
    }
}

// MARK: The query and the cursor

/// A Phase 3 GET's query: only the names the route takes, each at most once,
/// percent-decoded (`+` is a space). Anything else is 400.
enum BrowseQuery {
    static func parse(_ target: String, allowed: Set<String>) -> [String: String]? {
        guard let mark = target.firstIndex(of: "?") else { return [:] }
        let query = target[target.index(after: mark)...]
        var values: [String: String] = [:]
        guard !query.isEmpty else { return values }
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, allowed.contains(String(parts[0])), values[String(parts[0])] == nil,
                  let value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            else { return nil }
            values[String(parts[0])] = value
        }
        return values
    }

    /// A row index as a path or query has it: `0` or `[1-9]\d{0,6}`.
    static func index(_ text: some StringProtocol) -> Int? {
        let bytes = Array(text.utf8)
        guard (1...7).contains(bytes.count), bytes.allSatisfy({ (0x30...0x39).contains($0) }),
              bytes.count == 1 || bytes[0] != 0x30 else { return nil }
        return Int(String(decoding: bytes, as: UTF8.self))
    }

    /// `q`: 2 to 64 characters (code points), no control characters, trimmed.
    /// Nil (400) for anything else; empty means no search.
    static func search(_ value: String?) -> String?? {
        guard let value else { return .some(nil) }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard (2...64).contains(trimmed.unicodeScalars.count),
              !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) })
        else { return nil }
        return .some(trimmed)
    }
}

/// The opaque `next`: base64url (no padding) of `<updated_at>|<id>`.
enum BrowseCursorCoding {
    static func encode(_ cursor: BrowseCursor) -> String {
        Data("\(cursor.updatedMs)|\(cursor.id)".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Nil for anything Bench didn't make: `^\d{1,16}\|[0-9a-f-]{36}$` inside.
    static func decode(_ text: String) -> BrowseCursor? {
        guard (1...96).contains(text.utf8.count), text.utf8.allSatisfy({
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.utf8.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let plain = String(data: data, encoding: .utf8) else { return nil }
        let parts = plain.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...16).contains(parts[0].utf8.count),
              parts[0].utf8.allSatisfy({ (0x30...0x39).contains($0) }), let updated = Int64(parts[0]),
              PlanCheck.isFrameID(String(parts[1])) else { return nil }
        let cursor = BrowseCursor(updatedMs: updated, id: String(parts[1]))
        // Only the one spelling Bench writes.
        return encode(cursor) == text ? cursor : nil
    }
}

// MARK: The bodies

/// `POST /api/projects/<pid>/sessions`: `{"text":"…","id":"<uuid v4>","planFirst":false}`.
struct NewSessionRequest: Equatable, Sendable {
    let text: String
    let intentID: String
    let planFirst: Bool

    /// Text trimmed, 1…4,000 characters; the phone's uuid v4; `planFirst` a
    /// boolean, false when left out. Nil (400) for anything else.
    static func parse(_ body: Data) -> NewSessionRequest? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let text = Pick.string(root["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.unicodeScalars.count <= RemoteActionRequest.messageLimit,
              let id = Pick.string(root["id"]), RemoteActionRequest.isUUIDv4(id) else { return nil }
        var planFirst = false
        if root["planFirst"] != nil {
            guard let given = Pick.bool(root["planFirst"]) else { return nil }
            planFirst = given
        }
        return NewSessionRequest(text: text, intentID: id, planFirst: planFirst)
    }
}

// MARK: The answers

@MainActor
enum BrowseAPI {
    static let version = 1
    static let untitledSession = "Untitled session"
    static let untitledProject = "Untitled project"

    struct Projects: Encodable, Equatable {
        let version: Int
        let projects: [Project]
    }

    struct Project: Encodable, Equatable {
        let id: String
        let name: String
        let sessions: Int
        let lastActive: Date?

        private enum CodingKeys: String, CodingKey { case id, name, sessions, lastActive }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(sessions, forKey: .sessions)
            try c.encode(lastActive, forKey: .lastActive)
        }
    }

    struct Sessions: Encodable, Equatable {
        let sessions: [Session]
        let next: String?

        private enum CodingKeys: String, CodingKey { case sessions, next }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(sessions, forKey: .sessions)
            try c.encode(next, forKey: .next)
        }
    }

    struct Session: Encodable, Equatable {
        let id: String
        let title: String
        let state: String
        let sentence: String
        let startedAt: Date?
        let updatedAt: Date

        private enum CodingKeys: String, CodingKey { case id, title, state, sentence, startedAt, updatedAt }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(state, forKey: .state)
            try c.encode(sentence, forKey: .sentence)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(updatedAt, forKey: .updatedAt)
        }
    }

    /// `{"result":"started","id":"<root_frame_id>","sentence":"Started"}`.
    struct Started: Encodable, Equatable {
        let result: String
        let id: String
        let sentence: String

        init(id: String) {
            result = "started"
            self.id = id
            sentence = "Started"
        }
    }

    static func projects(_ rows: [ProjectRow]) -> Projects {
        Projects(version: version, projects: rows.map {
            Project(id: $0.id, name: $0.name.isEmpty ? untitledProject : $0.name, sessions: $0.sessions,
                    lastActive: $0.lastActiveMs.map(date))
        })
    }

    /// A page of up to 50, and the cursor after the 50th when there was a
    /// 51st. A session Bench knows now shows its own state (it sees what
    /// waits on a sub-agent; the database's status alone doesn't).
    static func sessions(_ rows: [BrowseRow], known: [SessionStatus]) -> Sessions {
        let page = Array(rows.prefix(BrowseSQL.pageSize))
        let next = rows.count > BrowseSQL.pageSize ? page.last.map {
            BrowseCursorCoding.encode(BrowseCursor(updatedMs: $0.updatedMs, id: $0.id))
        } : nil
        let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Sessions(sessions: page.map { row in
            let status = byID[row.id] ?? row.status(port: nil)
            return Session(id: row.id, title: row.name.isEmpty ? untitledSession : row.name, state: status.state.rawValue,
                           sentence: RemoteAPI.sentence(status), startedAt: date(row.createdMs), updatedAt: date(row.updatedMs))
        }, next: next)
    }

    nonisolated static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    // MARK: History

    /// The history page as the phone gets it:
    /// `{"total","from","items":[…]}`, items as DESIGN.md shows them.
    static func encode(_ page: HistoryPage) -> Data {
        RemoteAPI.encode(PageJSON(page: page))
    }

    static func encode(_ turn: HistoryTurn) -> Data {
        RemoteAPI.encode(TurnJSON(turn: turn))
    }

    private struct PageJSON: Encodable {
        let page: HistoryPage
        private enum CodingKeys: String, CodingKey { case total, from, items }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(page.total, forKey: .total)
            try c.encode(page.from, forKey: .from)
            try c.encode(page.items.map(ItemJSON.init), forKey: .items)
        }
    }

    private struct ItemJSON: Encodable {
        let item: HistoryItem
        private enum CodingKeys: String, CodingKey { case i, role, kind, at, text, cut, files, line, failed, steps, q, a }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(item.index, forKey: .i)
            switch item {
            case .turn(_, let role, let at, let text, let cut, let files):
                try c.encode(role.rawValue, forKey: .role)
                try c.encode(at, forKey: .at)
                try c.encode(text, forKey: .text)
                try c.encode(cut, forKey: .cut)
                try c.encode(files.map(FileJSON.init), forKey: .files)
            case .steps(_, let line, let failed, let files):
                try c.encode("steps", forKey: .kind)
                try c.encode(line, forKey: .line)
                try c.encode(failed, forKey: .failed)
                // Only when the turn's text isn't on this page to carry them.
                if !files.isEmpty { try c.encode(files.map(FileJSON.init), forKey: .files) }
            case .plan(_, let steps):
                try c.encode("plan", forKey: .kind)
                try c.encode(steps, forKey: .steps)
            case .ask(_, let q, let a):
                try c.encode("ask", forKey: .kind)
                try c.encode(q, forKey: .q)
                try c.encode(a, forKey: .a)
            case .toYou(_, let text, let files):
                try c.encode("toYou", forKey: .kind)
                try c.encode(text, forKey: .text)
                try c.encode(files.map(FileJSON.init), forKey: .files)
            case .helper:
                try c.encode("helper", forKey: .kind)
            }
        }
    }

    private struct FileJSON: Encodable {
        let file: HistoryFile
        private enum CodingKeys: String, CodingKey { case v, a, name, kind, size }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(file.v, forKey: .v)
            try c.encode(file.a, forKey: .a)
            try c.encode(file.name, forKey: .name)
            try c.encode(file.kind.rawValue, forKey: .kind)
            try c.encode(file.size, forKey: .size)
        }
    }

    private struct TurnJSON: Encodable {
        let turn: HistoryTurn
        private enum CodingKeys: String, CodingKey { case i, role, at, text }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(turn.i, forKey: .i)
            try c.encode(turn.role.rawValue, forKey: .role)
            try c.encode(turn.at, forKey: .at)
            try c.encode(turn.text, forKey: .text)
        }
    }
}

extension BrowseRow {
    /// As the Lab would show it: the same rules as the Now list (`startedAt`
    /// the latest turn's start, `updatedAt` its end when it ended), but from
    /// the status alone, which can't see a question waiting on a sub-agent.
    func status(port: Int?) -> SessionStatus {
        let state = SessionState(frameStatus: status)
        let ended = completedMs.flatMap { $0 >= turnStartedMs ? $0 : nil }
        let link = projectID.isEmpty ? nil
            : URL(string: "http://localhost:\(port ?? 8765)/projects/\(projectID)/frames/\(id)")
        return SessionStatus(id: id, projectID: projectID, projectName: projectName.isEmpty ? projectID : projectName,
                             title: name, state: state, updatedAt: BrowseAPI.date(ended ?? updatedMs),
                             startedAt: BrowseAPI.date(turnStartedMs), deepLink: link,
                             waitingReason: state == .needsInput ? WaitingReason(signal: status) : nil)
    }
}

// MARK: Answering

/// The Phase 3 routes over injected reads and writes. The session gate, the
/// held sessions and the six-a-minute limit are `RemoteSessions`', shared
/// with the actions.
@MainActor
final class RemoteBrowser {
    static let shared = RemoteBrowser(sessions: .shared, dependencies: .live())

    /// What a page of history read gave.
    enum HistoryRead: Equatable {
        case page(HistoryPage)
        case unreadable
    }

    /// What one turn's read gave.
    enum TurnRead: Equatable {
        case turn(HistoryTurn)
        /// No turn the history shows at that index.
        case none
        case unreadable
    }

    struct Dependencies {
        var browseOn: @MainActor () -> Bool
        var actionsOn: @MainActor () -> Bool
        /// The projects (`fetchProjects`); nil when the database can't be read.
        var projects: @MainActor () async -> [ProjectRow]?
        /// A page of a project's sessions (`fetchProjectSessions`).
        var sessions: @MainActor (_ project: String, _ after: BrowseCursor?, _ search: String?) async -> [BrowseRow]?
        /// Every session Bench knows now, for their own states.
        var known: @MainActor () -> [SessionStatus]
        /// The history reader (HistoryReader.swift).
        var history: @MainActor (_ id: String, _ before: Int?) async -> HistoryRead
        var turn: @MainActor (_ id: String, _ index: Int) async -> TurnRead
        /// The writer: nil when the write didn't complete.
        var create: @MainActor (RemoteWrite) async -> RemoteWriteResult?
        /// The session a new-session intent made (`fetchSessionByIntent`).
        var findIntent: @MainActor (_ project: String, _ intent: String) async -> String?
        /// Files listed to a device (`ListedFiles`).
        var listed: @MainActor (_ files: [HistoryFile], _ device: String) -> Void
        var now: @MainActor () -> Date
        /// Before the intent lookup's second try.
        var pause: @MainActor () async -> Void

        static func live() -> Dependencies {
            Dependencies(
                browseOn: { RemoteBrowse.isOn },
                actionsOn: { RemoteSessions.actionsSetting() },
                projects: {
                    guard Demo.mode == nil else { return nil }
                    return await Task.detached(priority: .utility) { () -> [ProjectRow]? in
                        guard let db = resolveDatabase() else { return nil }
                        return try? fetchProjects(db: db)
                    }.value
                },
                sessions: { project, after, search in
                    guard Demo.mode == nil else { return nil }
                    return await Task.detached(priority: .utility) { () -> [BrowseRow]? in
                        guard let db = resolveDatabase() else { return nil }
                        return (try? fetchProjectSessions(db: db, project: project, after: after, search: search)) ?? nil
                    }.value
                },
                known: { RemoteAPI.knownSessions(lab: .shared) },
                history: { id, before in
                    guard Demo.mode == nil, let page = (try? await WebContainer.shared.readHistory(id, before: before)) ?? nil
                    else { return .unreadable }
                    return .page(page)
                },
                turn: { id, index in
                    guard Demo.mode == nil, let outcome = try? await WebContainer.shared.readTurn(id, index: index) else {
                        return .unreadable
                    }
                    switch outcome {
                    case .turn(let turn): return .turn(turn)
                    case .none: return .none
                    default: return .unreadable
                    }
                },
                create: { write in
                    guard Demo.mode == nil else { return nil }
                    return try? await WebContainer.shared.writeSession(write)
                },
                findIntent: { project, intent in
                    guard Demo.mode == nil else { return nil }
                    return await Task.detached(priority: .utility) { () -> String? in
                        guard let db = resolveDatabase() else { return nil }
                        return (try? fetchSessionByIntent(db: db, project: project, intent: intent)) ?? nil
                    }.value
                },
                listed: { RemoteBrowser.recordListed($0, device: $1) },
                now: { Date() },
                pause: { try? await Task.sleep(for: .seconds(1)) })
        }
    }

    /// The live point lookup, for `RemoteSessions`: the database's root
    /// session with this id, read off the main thread.
    static func lookUp(_ id: String) async -> SessionStatus? {
        guard Demo.mode == nil, PlanCheck.isFrameID(id) else { return nil }
        let port = WebContainer.shared.port
        let row = await Task.detached(priority: .utility) { () -> BrowseRow? in
            guard let db = resolveDatabase() else { return nil }
            return (try? fetchSession(db: db, id: id)) ?? nil
        }.value
        return row?.status(port: port)
    }

    let sessions: RemoteSessions
    private let dependencies: Dependencies
    /// The projects `/api/projects` lists, and when they were read: a new
    /// session starts only in one of them (no hidden concierge or archived
    /// project), held a minute.
    private var listed: (ids: Set<String>, at: Date)?
    static let projectsLifetime: TimeInterval = 60

    init(sessions: RemoteSessions, dependencies: Dependencies) {
        self.sessions = sessions
        self.dependencies = dependencies
    }

    /// One Phase 3 route: browse on (403 `browseOff`) first, then the route's
    /// own checks.
    func respond(_ route: RemoteRoute, target: String, device: String, body: Data) async -> RemoteActionReply {
        guard dependencies.browseOn() else { return RemoteBrowse.off }
        switch route {
        case .projects:
            guard BrowseQuery.parse(target, allowed: []) != nil else { return .badRequest }
            guard let rows = await dependencies.projects() else { return Self.unreadable }
            listed = (Set(rows.map(\.id)), dependencies.now())
            return Self.json(RemoteAPI.encode(BrowseAPI.projects(rows)))
        case .projectSessions(let project):
            return await sessionsPage(project, target: target)
        case .newSession(let project):
            return await newSession(project, device: device, body: body)
        case .history(let id):
            return await history(id, target: target, device: device)
        case .turn(let id, let index):
            guard BrowseQuery.parse(target, allowed: []) != nil else { return .badRequest }
            guard await sessions.admitted(id) != nil else { return .notFound }
            switch await dependencies.turn(id, index) {
            case .turn(let turn) where turn.i == index: return Self.json(BrowseAPI.encode(turn))
            case .none: return .notFound
            default: return Self.unreadable
            }
        default:
            return .notFound
        }
    }

    /// 503 `{"error":"unreadable"}`: the database or the page couldn't be read.
    static let unreadable = RemoteActionReply(status: 503, body: Data(#"{"error":"unreadable"}"#.utf8))

    private static func json(_ body: Data) -> RemoteActionReply {
        RemoteActionReply(status: 200, body: body)
    }

    private func sessionsPage(_ project: String, target: String) async -> RemoteActionReply {
        guard let query = BrowseQuery.parse(target, allowed: ["before", "q"]),
              let search = BrowseQuery.search(query["q"]) else { return .badRequest }
        var cursor: BrowseCursor?
        if let before = query["before"] {
            guard let decoded = BrowseCursorCoding.decode(before) else { return .badRequest }
            cursor = decoded
        }
        guard let rows = await dependencies.sessions(project, cursor, search) else { return Self.unreadable }
        return Self.json(RemoteAPI.encode(BrowseAPI.sessions(rows, known: dependencies.known())))
    }

    private func history(_ id: String, target: String, device: String) async -> RemoteActionReply {
        guard let query = BrowseQuery.parse(target, allowed: ["before"]) else { return .badRequest }
        var before: Int?
        if let text = query["before"] {
            guard let index = BrowseQuery.index(text), index >= 1 else { return .badRequest }
            before = index
        }
        guard await sessions.admitted(id) != nil else { return .notFound }
        guard case .page(let read) = await dependencies.history(id, before) else { return Self.unreadable }
        let page = read.capped { BrowseAPI.encode($0) }
        dependencies.listed(page.files, device)
        return Self.json(BrowseAPI.encode(page))
    }

    // MARK: A new session

    /// Browse on (checked before), actions on (403), the device's limit
    /// (429), the body (400), a project the projects list shows (404; 503
    /// when it can't be read); then the in-page write. Lost or refused as a
    /// repeat, the database says whether the session was made after all.
    private func newSession(_ project: String, device: String, body: Data) async -> RemoteActionReply {
        guard dependencies.actionsOn() else { return .actionsOff }
        guard sessions.allowAction(device: device) else { return .tooMany }
        guard BrowseSQL.isProjectID(project), let request = NewSessionRequest.parse(body) else { return .badRequest }
        guard let projects = await listedProjects() else { return Self.unreadable }
        guard projects.contains(project) else { return .notFound }
        let reply = await dependencies.create(.newSession(project: project, text: request.text,
                                                          planMode: request.planFirst, intentID: request.intentID))
        if let reply, reply.status == 200, reply.isJSON, reply.bodyStatus == "accepted", let id = reply.rootFrameID {
            return started(id, project: project, request: request)
        }
        // A timeout, a 409 (that intent made a session already: an earlier
        // try whose answer was lost), or a 200 Bench can't read: look.
        if reply == nil || reply?.status == 409 || reply?.status == 200 {
            var found = await dependencies.findIntent(project, request.intentID)
            if found == nil {
                await dependencies.pause()
                found = await dependencies.findIntent(project, request.intentID)
            }
            if let found, PlanCheck.isFrameID(found) { return started(found, project: project, request: request) }
        }
        return .ok(.unavailable)
    }

    /// The projects the list shows, read again when a minute old.
    private func listedProjects() async -> Set<String>? {
        let now = dependencies.now()
        if let listed, listed.at <= now, now.timeIntervalSince(listed.at) < Self.projectsLifetime { return listed.ids }
        guard let rows = await dependencies.projects() else { return nil }
        let ids = Set(rows.map(\.id))
        listed = (ids, now)
        return ids
    }

    private func started(_ id: String, project: String, request: NewSessionRequest) -> RemoteActionReply {
        let now = dependencies.now()
        // The daemon names a new session after its first 50 characters.
        sessions.admitStarted(SessionStatus(id: id, projectID: project, projectName: "",
                                            title: String(request.text.prefix(50)), state: .running,
                                            updatedAt: now, startedAt: now))
        return Self.json(RemoteAPI.encode(BrowseAPI.Started(id: id)))
    }

    /// A history page's files, listed to this device: the files routes
    /// serve a device only what it was listed (`ListedFiles`), and read the
    /// kind and size from the listing (`ListedFileInfo`). History doesn't know
    /// a file's content type, and may not know its size; the download checks
    /// the real length again either way.
    static func recordListed(_ files: [HistoryFile], device: String) {
        ListedFiles.shared.record(files.map(\.v), device: device)
        for file in files {
            ListedFileInfo.shared.record(file.v, .init(name: file.name, mime: nil, size: file.size ?? 0, kind: file.kind))
        }
    }

    // MARK: `--demo remote`

    /// Made-up projects, sessions and histories (`DemoBrowseStore`); a new
    /// session answers `started` with a made-up id that opens.
    static func demo(sessions: RemoteSessions, store: DemoBrowseStore,
                     browseOn: @escaping @MainActor () -> Bool = { RemoteBrowse.isOn },
                     actionsOn: @escaping @MainActor () -> Bool = { RemoteSessions.actionsSetting() },
                     listed: @escaping @MainActor ([HistoryFile], String) -> Void = { RemoteBrowser.recordListed($0, device: $1) })
        -> RemoteBrowser {
        RemoteBrowser(sessions: sessions, dependencies: Dependencies(
            browseOn: browseOn,
            actionsOn: actionsOn,
            projects: { store.projectRows() },
            sessions: { store.page(project: $0, after: $1, search: $2) },
            known: { store.nowSessions },
            history: { id, before in store.history(id, before: before).map(HistoryRead.page) ?? .unreadable },
            turn: { id, index in store.turn(id, index: index).map(TurnRead.turn) ?? TurnRead.none },
            create: { store.create($0) },
            findIntent: { store.session(forIntent: $1, in: $0) },
            listed: listed,
            now: { Date() },
            pause: {}))
    }
}
