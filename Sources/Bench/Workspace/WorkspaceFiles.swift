// WorkspaceFiles.swift — where the workspaces are kept (DESIGN.md, Project
// Workspaces): one small JSON file per project in Capsid's own Application
// Support folder (`~/Library/Application Support/Bench/Workspaces`, folder 0700,
// files 0600), each written whole to a temporary file and renamed over the
// old one, off the main actor. The store reads and writes through
// `WorkspaceDisk`, so the tests stand a disk of their own in (a temporary
// folder, or one that holds a write until the test lets it go).
import Foundation

/// A file as read: none there, its bytes, or why it couldn't be read.
enum WorkspaceRead: Equatable, Sendable {
    case missing
    case bytes(Data)
    case failed(String)
}

/// What the workspaces are kept on.
protocol WorkspaceDisk: Sendable {
    /// `projectID`'s file.
    func read(_ projectID: String) async -> WorkspaceRead
    /// Writes `data` as `projectID`'s file, whole: a reader sees the old file or the new one, never part of either.
    func write(_ data: Data, for projectID: String) async throws
    /// Moves `projectID`'s file to the Trash (Clear Workspace…). No file is no error.
    func trash(_ projectID: String) async throws
    /// The projects that have a file, newest first.
    func projects() async -> [String]
}

enum WorkspaceDiskError: Error, Equatable, LocalizedError {
    case badID
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .badID: "That project can\u{2019}t have a workspace."
        case .failed(let sentence): sentence
        }
    }

    /// A short sentence for the panel, never a path.
    static func sentence(_ error: Error) -> String {
        if let error = error as? WorkspaceDiskError, let description = error.errorDescription { return description }
        let code = (error as NSError).code
        switch code {
        case NSFileWriteOutOfSpaceError: return "The disk is full."
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return "Capsid isn\u{2019}t allowed to write there."
        default: return "The disk didn\u{2019}t take it."
        }
    }
}

/// The live disk: the files in Capsid's own folder.
actor WorkspaceFiles: WorkspaceDisk {
    /// `~/Library/Application Support/Bench/Workspaces`.
    static var folder: URL {
        FileDeviceStore.folder.appendingPathComponent("Workspaces", isDirectory: true)
    }

    private let folder: URL
    private let trasher: @Sendable (URL) throws -> Void

    init(folder: URL = WorkspaceFiles.folder,
         trasher: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.folder = folder
        self.trasher = trasher
    }

    private func url(_ projectID: String) throws -> URL {
        guard let name = WorkspaceRules.fileName(for: projectID) else { throw WorkspaceDiskError.badID }
        return folder.appendingPathComponent(name, isDirectory: false)
    }

    func read(_ projectID: String) async -> WorkspaceRead {
        guard let url = try? url(projectID) else { return .failed(WorkspaceDiskError.badID.errorDescription ?? "") }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // One more byte than a record may be: a larger file is damaged, and is never read whole.
            let data = try handle.read(upToCount: WorkspaceRules.fileLimit + 1) ?? Data()
            return .bytes(data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return .missing
        } catch {
            return .failed("The workspace\u{2019}s file couldn\u{2019}t be read.")
        }
    }

    func write(_ data: Data, for projectID: String) async throws {
        let url = try url(projectID)
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)", isDirectory: false)
        guard files.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw WorkspaceDiskError.failed("The disk didn\u{2019}t take it.")
        }
        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? files.removeItem(at: temporary)
            throw WorkspaceDiskError.failed(code == ENOSPC ? "The disk is full." : "The disk didn\u{2019}t take it.")
        }
    }

    func trash(_ projectID: String) async throws {
        let url = try url(projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try trasher(url)
        } catch {
            throw WorkspaceDiskError.failed("It couldn\u{2019}t be moved to the Trash.")
        }
    }

    func projects() async -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [] }
        let found: [(id: String, at: Date)] = urls.compactMap { url in
            guard let id = WorkspaceRules.projectID(fromFileName: url.lastPathComponent) else { return nil }
            let at = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return (id, at)
        }
        return found.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at > $1.at }.map(\.id)
    }
}
