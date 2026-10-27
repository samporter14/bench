// WorkspaceRecord.swift — a project's workspace as it is kept (DESIGN.md,
// Project Workspaces): one versioned record per project, keyed by the
// project's stable id, never its name. It holds ids, the exact row of each
// pinned reply, titles to name something that has gone, and the Working Note.
// Never a transcript, a document, a picture or anything that signs in. The
// rules here are pure: what a file's bytes are (a record, a damaged file, one
// from a newer Capsid), the file's name for an id, how long a note may be,
// how many references a project pins, and how a list tells two projects of
// one name apart.
import Foundation

/// A reference pinned to a project: the session, the reply the window showed
/// when it was pinned, and the session's title as it was then.
struct WorkspacePin: Codable, Equatable, Sendable, Identifiable {
    let sessionID: String
    let projectID: String
    /// The reply's last history row when it was pinned (the Shelf's `sourceRow`
    /// is the same): Return lands on the reply that holds it, or says it is
    /// gone. Nil when the window showed no reply: the newest, then.
    let row: Int?
    /// Presentation only: what to call it when the session can't be read.
    var title: String
    let pinnedAt: Date

    var id: String { sessionID }
}

struct WorkspaceRecord: Codable, Equatable, Sendable {
    /// The record's shape. A file with a higher number is a newer Capsid's and is left as it is.
    static let currentSchema = 1

    var schema: Int
    let projectID: String
    /// Presentation only: the name the project had when the record was last written.
    var projectName: String
    var note: String
    var pins: [WorkspacePin]
    var updatedAt: Date

    init(projectID: String, projectName: String, note: String = "", pins: [WorkspacePin] = [], updatedAt: Date) {
        schema = Self.currentSchema
        self.projectID = projectID
        self.projectName = projectName
        self.note = note
        self.pins = pins
        self.updatedAt = updatedAt
    }

    /// Something to come back to: a pin, or a note with words in it.
    var hasContent: Bool { !pins.isEmpty || !WorkspaceRules.isBlank(note) }

    func isPinned(_ sessionID: String) -> Bool { pins.contains { $0.sessionID == sessionID } }
}

/// What a workspace's file holds, as read.
enum WorkspaceFile: Equatable, Sendable {
    /// No file: a project with nothing kept yet.
    case none
    case record(WorkspaceRecord)
    /// Bytes that aren't a record of this shape. They are left as they are.
    case damaged
    /// A record from a newer Capsid (its schema). Left as it is too.
    case newer(Int)
}

enum WorkspaceRules {
    /// References a project pins at most.
    static let pinLimit = 4
    /// The Working Note's limit, in bytes of UTF-8: 64 KiB.
    static let noteLimit = 64 * 1_024
    /// From here the note shows how much of the limit it uses.
    static let noteShowsSizeFrom = 48 * 1_024
    /// A file larger than this is no record of ours (a full note and four pins are a small part of it).
    static let fileLimit = 1_024 * 1_024
    /// Titles and names a record keeps are cut to this many characters.
    static let titleLimit = 240

    // MARK: Ids and files

    /// A project id as the database has it (`BrowseSQL.isProjectID`): letters, digits, `-` and `_`, at most 64.
    static func isProjectID(_ id: String) -> Bool { BrowseSQL.isProjectID(id) }

    /// The record's file name: the id's bytes in hex, so two ids that differ only in case stay two files on a
    /// disk that doesn't tell case apart, and nothing in a name can reach outside the folder. Nil for an id out of shape.
    static func fileName(for projectID: String) -> String? {
        guard isProjectID(projectID) else { return nil }
        return "project-" + projectID.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    /// The project id a record's file name stands for, or nil for any other file.
    static func projectID(fromFileName name: String) -> String? {
        guard name.hasPrefix("project-"), name.hasSuffix(".json") else { return nil }
        let hex = Array(name.dropFirst("project-".count).dropLast(".json".count))
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = 0
        while index < hex.count {
            guard let byte = UInt8(String(hex[index..<index + 2]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        guard let id = String(bytes: bytes, encoding: .utf8), fileName(for: id) == name else { return nil }
        return id
    }

    // MARK: Reading and writing

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private struct Schema: Decodable {
        let schema: Int
    }

    static func encode(_ record: WorkspaceRecord) throws -> Data {
        try encoder.encode(record)
    }

    /// The bytes of `projectID`'s file. The schema is read first: a newer one is never decoded as this shape. A record
    /// that isn't wholly in shape (another project's id, a session id that isn't one, five pins, a note over the
    /// limit) is damaged, not mended: its bytes stay for whoever wants them.
    static func decode(_ data: Data, projectID: String) -> WorkspaceFile {
        guard data.count <= fileLimit, let schema = try? decoder.decode(Schema.self, from: data) else { return .damaged }
        guard schema.schema <= WorkspaceRecord.currentSchema else { return .newer(schema.schema) }
        guard schema.schema == WorkspaceRecord.currentSchema,
              let record = try? decoder.decode(WorkspaceRecord.self, from: data),
              isInShape(record, projectID: projectID) else { return .damaged }
        return .record(record)
    }

    static func isInShape(_ record: WorkspaceRecord, projectID: String) -> Bool {
        guard record.projectID == projectID, isProjectID(projectID), record.pins.count <= pinLimit,
              fits(note: record.note), record.projectName.count <= titleLimit else { return false }
        var seen: Set<String> = []
        for pin in record.pins {
            guard pin.projectID == projectID, PlanCheck.isFrameID(pin.sessionID), seen.insert(pin.sessionID).inserted,
                  (pin.row ?? 0) >= 0, pin.title.count <= titleLimit else { return false }
        }
        return true
    }

    // MARK: The note

    static func bytes(_ note: String) -> Int { note.utf8.count }

    static func fits(note: String) -> Bool { bytes(note) <= noteLimit }

    static func isBlank(_ note: String) -> Bool { note.allSatisfy(\.isWhitespace) }

    /// "52 KB of 64 KB", once the note is near its limit; nil before.
    static func sizeLine(for note: String) -> String? {
        let used = bytes(note)
        guard used >= noteShowsSizeFrom else { return nil }
        return "\(kilobytes(used)) of \(noteLimit / 1_024) KB"
    }

    /// Whole kilobytes, rounded up, so a full note never reads under the limit's own number.
    private static func kilobytes(_ bytes: Int) -> String {
        "\((bytes + 1_023) / 1_024) KB"
    }

    /// Said when typing or a paste would take the note past its limit: nothing was cut, the change wasn't made.
    static let fullSentence = "That would make the note longer than 64 KB, so it wasn\u{2019}t added. Nothing was cut."

    // MARK: Names

    /// A title or name as a record keeps it: one line, no control characters, cut to `titleLimit`.
    static func clean(_ text: String) -> String {
        let line = text.filter { character in
            !character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
        return String(line.prefix(titleLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a list calls each project: its name, and where two or more listed share one, the end of the id too, so
    /// every line is a different project ("Assay development · …c0ffee"). Same order as given.
    static func listTitles(_ projects: [(id: String, name: String)]) -> [String] {
        func named(_ name: String) -> String { name.isEmpty ? "Untitled project" : name }
        var counts: [String: Int] = [:]
        for project in projects { counts[named(project.name), default: 0] += 1 }
        let short = projects.map { named($0.name) + " \u{00B7} \u{2026}" + String($0.id.suffix(6)) }
        var shortCounts: [String: Int] = [:]
        for title in short { shortCounts[title, default: 0] += 1 }
        return projects.enumerated().map { index, project in
            let name = named(project.name)
            guard counts[name, default: 0] > 1 else { return name }
            // Ids that end alike are named whole.
            return shortCounts[short[index], default: 0] > 1 ? "\(name) \u{00B7} \(project.id)" : short[index]
        }
    }
}
