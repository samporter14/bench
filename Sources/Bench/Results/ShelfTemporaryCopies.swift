// ShelfTemporaryCopies.swift — the temporary copies Quick Look and a drag need
// (DESIGN.md, Results): both want a file, and this is the one place the shelf
// writes one besides Save. A run's copies live in
// `<temporary folder>/Capsid Quick Look/<UUID>/<version id>/<file name>`: the
// folders are 0700, the files 0600, and the whole run folder goes when the
// shelf closes (and every earlier run's at launch, for a run that never got
// to close). The version id in the path keeps two files of the same name
// apart, and the leaf keeps the file's real name, which is what Finder and
// Quick Look show.
//
// The disk work is an actor's, off the main actor, one operation at a time:
// a write and a run's deletion never overlap. The shelf names the run each
// write is for (a window's opening to its closing); a run once removed is
// never written to again, so a write that lands late for it is dropped
// instead of making its folder anew.
import Foundation

/// File names for what the shelf writes: safe on disk, and never taking
/// another file's place.
enum ShelfFileName {
    /// The longest name APFS takes, in UTF-8 bytes.
    static let longest = 255

    /// A name fit to write: no path separators or control characters (each
    /// becomes "_"), no leading dot, no edge blanks, at most 255 bytes with
    /// its extension kept, and "file" when nothing is left.
    static func sanitized(_ name: String) -> String {
        let replaced = String(String.UnicodeScalarView(name.unicodeScalars.map { scalar in
            scalar == "/" || scalar == ":" || scalar.value < 0x20 || scalar.value == 0x7F ? "_" : scalar
        }))
        var text = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix(".") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "file" }
        guard text.utf8.count > longest else { return text }
        // Too long: the stem gives way, the extension stays (unless it is absurd itself).
        let ext = (text as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.utf8.count <= 32 ? "." + ext : ""
        var stem = String(text.dropLast(suffix.isEmpty ? 0 : suffix.count))
        while (stem + suffix).utf8.count > longest, !stem.isEmpty { stem.removeLast() }
        return (stem.isEmpty ? "file" : stem) + suffix
    }

    /// "report.md" → "report 2.md", "report 3.md"… until `taken` says no.
    static func unique(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken(candidate) { return candidate }
            n += 1
        }
    }
}

/// The temporary copies' disk work, off the main actor. Injectable, so tests
/// can hold it. Every call names the run it is for.
protocol ShelfCopyStorage: Sendable {
    /// Writes a copy for `run` (0600, in 0700 folders) and answers where;
    /// nil when that run was removed meanwhile, and then nothing is written.
    func write(_ data: Data, for entry: ArtifactEntry, run: UUID) async throws -> URL?
    /// Whether a copy is still there (the system may clean the temporary folder).
    func exists(_ url: URL) async -> Bool
    /// A copy's bytes: Copy, from the preview's copy.
    func read(_ url: URL) async throws -> Data
    /// Deletes a run's folder; a later write for that run is dropped.
    func remove(run: UUID) async
    /// Launch: deletes every run's folder but the ones this storage is writing.
    func removeLeftovers() async
}

actor ShelfTemporaryCopies: ShelfCopyStorage {
    nonisolated static let folderName = "Capsid Quick Look"
    nonisolated static var defaultBase: URL {
        FileManager.default.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    nonisolated let base: URL
    /// Runs removed: a write for one that comes late is dropped.
    private var removed: Set<UUID> = []
    /// Runs written to and not removed: what launch cleanup leaves.
    private var current: Set<UUID> = []

    init(base: URL = ShelfTemporaryCopies.defaultBase) {
        self.base = base
    }

    /// A run's folder. Nothing is made until its first copy is written.
    nonisolated func runFolder(_ run: UUID) -> URL {
        base.appending(path: run.uuidString, directoryHint: .isDirectory)
    }

    /// A version id as a folder name: it is path-safe already, but never trusted to be.
    nonisolated static func folderComponent(for version: String) -> String {
        let safe = String(String.UnicodeScalarView(version.unicodeScalars.prefix(128).map { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-")
                ? scalar : "_"
        }))
        return safe.isEmpty ? "_" : safe
    }

    /// Where an entry's copy goes (or went) in a run: `<run>/<version>/<sanitized name>`.
    nonisolated func url(for entry: ArtifactEntry, run: UUID) -> URL {
        runFolder(run)
            .appending(path: Self.folderComponent(for: entry.version), directoryHint: .isDirectory)
            .appending(path: ShelfFileName.sanitized(entry.name), directoryHint: .notDirectory)
    }

    func write(_ data: Data, for entry: ArtifactEntry, run: UUID) throws -> URL? {
        // Checked here, with the write, on the one actor that also removes runs.
        guard !removed.contains(run) else { return nil }
        let fileManager = FileManager.default
        let url = url(for: entry, run: run)
        for folder in [base, runFolder(run), url.deletingLastPathComponent()] where !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        current.insert(run)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    /// Errors are ignored: it is only a temporary folder.
    func remove(run: UUID) {
        removed.insert(run)
        current.remove(run)
        try? FileManager.default.removeItem(at: runFolder(run))
    }

    func removeLeftovers() {
        guard !current.isEmpty else {
            Self.removeAll(base: base)
            return
        }
        let keep = Set(current.map(\.uuidString))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: base.appending(path: name))
        }
    }

    /// Deletes the whole "Capsid Quick Look" folder: every run's, including
    /// one that never closed. Synchronous: only ever called off the main actor
    /// (and by tests).
    nonisolated static func removeAll(base: URL) {
        try? FileManager.default.removeItem(at: base)
    }
}
