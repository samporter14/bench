// ShelfTemporaryCopies.swift — the temporary copies Quick Look and a drag need
// (DESIGN.md, Results): both want a file, and this is the one place the shelf
// writes one besides Save. A run's copies live in
// `<temporary folder>/Capsid Quick Look/<UUID>/<version id>/<file name>`: the
// folders are 0700, the files 0600, and the whole run folder goes when the
// shelf closes (and the whole "Capsid Quick Look" folder at launch, for a run
// that never got to close). The version id in the path keeps two files of the
// same name apart, and the leaf keeps the file's real name, which is what
// Finder and Quick Look show.
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

@MainActor
final class ShelfTemporaryCopies {
    nonisolated static let folderName = "Capsid Quick Look"
    nonisolated static var defaultBase: URL {
        FileManager.default.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    let base: URL
    private let fileManager: FileManager
    /// This run's folder name; a new one after `removeAll()`.
    private var runID = UUID()
    /// Where each version's copy was written this run.
    private var copies: [String: URL] = [:]

    init(base: URL = ShelfTemporaryCopies.defaultBase, fileManager: FileManager = .default) {
        self.base = base
        self.fileManager = fileManager
    }

    /// This run's folder. Nothing is made until the first copy is written.
    var runFolder: URL { base.appending(path: runID.uuidString, directoryHint: .isDirectory) }

    /// A version id as a folder name: it is path-safe already, but never trusted to be.
    nonisolated static func folderComponent(for version: String) -> String {
        let safe = String(String.UnicodeScalarView(version.unicodeScalars.prefix(128).map { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-")
                ? scalar : "_"
        }))
        return safe.isEmpty ? "_" : safe
    }

    /// Where an entry's copy goes (or went): `<run>/<version>/<sanitized name>`.
    func url(for entry: ArtifactEntry) -> URL {
        runFolder
            .appending(path: Self.folderComponent(for: entry.version), directoryHint: .isDirectory)
            .appending(path: ShelfFileName.sanitized(entry.name), directoryHint: .notDirectory)
    }

    /// The copy made this run for a version, if it is still on disk.
    func cached(_ version: String) -> URL? {
        guard let url = copies[version] else { return nil }
        guard fileManager.fileExists(atPath: url.path) else {
            copies[version] = nil
            return nil
        }
        return url
    }

    /// Writes an entry's bytes into its place (0600, in 0700 folders) and
    /// remembers the copy.
    @discardableResult
    func write(_ data: Data, for entry: ArtifactEntry) throws -> URL {
        let url = url(for: entry)
        for folder in [base, runFolder, url.deletingLastPathComponent()] where !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        copies[entry.version] = url
        return url
    }

    /// Deletes this run's folder and forgets its copies; the next copy goes
    /// into a new run folder. Errors are ignored: it is only a temporary folder.
    func removeAll() {
        try? fileManager.removeItem(at: runFolder)
        copies = [:]
        runID = UUID()
    }

    /// Deletes the whole "Capsid Quick Look" folder: every run's, including
    /// one that never closed (launch does this).
    nonisolated static func removeAll(base: URL) {
        try? FileManager.default.removeItem(at: base)
    }
}
