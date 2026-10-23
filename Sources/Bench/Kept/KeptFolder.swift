// KeptFolder.swift — where a kept figure lives and what its folder is called
// (DESIGN.md, Kept): `<root>/<Collection>/<Name>/`, holding the figure under
// its own file name, `data/`, `code/`, `input/` and `README.md`. This file is
// only names and paths: it makes URLs and strings and never asks the disk
// anything, so any code, on any actor, may use it. The disk work is
// KeptDisk's, off the main actor, and `KeptDiskCallsTests` fails the build of
// any file in this folder but that one that touches the file system.
//
// The default root is `~/Documents/Kept`. It is a function of the home folder
// that is handed in, so a test can pass a scratch folder, and a setting that
// names another folder (a path, or empty for the default) is turned into a URL
// here without looking at the disk.
import Foundation

/// How a folder, or a collection, is named on disk.
enum KeptName {
    /// The longest name APFS takes, in UTF-8 bytes.
    static let longest = 255
    /// What stands in for a name with nothing left after cleaning.
    static let fallback = "Result"

    /// " 2026-10-22 0912": the blank, the date and the time of day.
    private static let stampBytes = 16

    /// A name fit to be a folder's: "/", ":" and control characters become
    /// "_", blanks at either end and any leading dots go (a dot would hide
    /// the folder from Finder and from the Kept window), at most 255 bytes
    /// (whole characters; one is never cut in half), and "Result" when
    /// nothing is left. Spaces and every other character stay, "Z′" and "·"
    /// among them.
    static func sanitized(_ name: String) -> String {
        // Blanks at the ends go first, so a name of only line breaks is empty, not "_".
        let replaced = String(String.UnicodeScalarView(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
            scalar == "/" || scalar == ":" || scalar.value < 0x20 || scalar.value == 0x7F ? "_" : scalar
        }))
        var text = replaced
        while text.hasPrefix(".") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = fitted(text, toBytes: longest)
        return text.isEmpty ? fallback : text
    }

    /// "Plate reader QC 2026-10-22 0912": the name made apart from one already
    /// there, by the date and time of the keep, in the zone the Mac is in
    /// (`timeZone`: tests pin one). The name gives up characters to make room,
    /// so the result is still a name a disk takes.
    static func dated(_ name: String, at date: Date, timeZone: TimeZone = .current) -> String {
        let stem = fitted(sanitized(name), toBytes: longest - stampBytes)
        return "\(stem) \(stamp(date, timeZone: timeZone))"
    }

    /// The name's `n`th try (2 on) when even the dated one is taken: "… 0912 2".
    static func numbered(_ name: String, _ n: Int) -> String {
        let suffix = " \(n)"
        return fitted(name, toBytes: longest - suffix.utf8.count) + suffix
    }

    /// The hidden folder a keep is built in until it is whole, beside the one
    /// it becomes: `.<Name>.keeping-<uuid>`. A long name is cut to leave room
    /// for the rest, so the folder can always be made.
    static func temporaryFolder(for name: String, id: UUID = UUID()) -> String {
        let tail = ".keeping-\(id.uuidString)"
        return "." + fitted(sanitized(name), toBytes: longest - 1 - tail.utf8.count) + tail
    }

    /// Whether the name ends in the date and time `dated` adds.
    static func isDated(_ name: String) -> Bool {
        let tail = Array(name.unicodeScalars.suffix(stampBytes))
        guard tail.count == stampBytes else { return false }
        // " dddd-dd-dd dddd"
        let shape = "_dddd-dd-dd_dddd"
        return zip(tail, shape.unicodeScalars).allSatisfy { scalar, want in
            switch want {
            case "_": scalar == " "
            case "d": ("0"..."9").contains(scalar)
            default: scalar == want
            }
        }
    }

    /// Whether this is the name of a keep still being made (or left behind by
    /// one that was), which nothing lists and nothing opens.
    static func isTemporary(_ folderName: String) -> Bool {
        folderName.hasPrefix(".") && folderName.contains(".keeping-")
    }

    /// "2026-10-22 0912", in a Gregorian calendar and English digits whatever
    /// the Mac's region says.
    static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: date)
    }

    /// `text` cut from the end, a whole character at a time, to at most
    /// `bytes` of UTF-8, without a blank left at the end.
    private static func fitted(_ text: String, toBytes bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var cut = text
        while cut.utf8.count > bytes, !cut.isEmpty { cut.removeLast() }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Where each kind of file goes inside a kept folder.
enum KeptLayout {
    static let readmeName = "README.md"
    static let dataFolder = "data"
    static let codeFolder = "code"
    static let inputFolder = "input"

    /// The subfolder a role's files go in; nil for the figure, which sits at
    /// the top under its own file name.
    static func folder(for role: KeptRole) -> String? {
        switch role {
        case .figure: nil
        case .data: dataFolder
        case .code: codeFolder
        case .input: inputFolder
        }
    }

    /// A file's name as it is kept: safe on disk (the shelf's rule: no
    /// separators or control characters, no leading dot, at most 255 bytes),
    /// and never `README.md`, which is Capsid's.
    static func fileName(_ name: String) -> String {
        let clean = ShelfFileName.sanitized(name)
        return isReadme(clean) ? ShelfFileName.numbered(clean, 2) : clean
    }

    /// The figure's name at the top of a kept folder: as `fileName`, and never one
    /// of the folders beside it ("data", "code" or "input", in any case), whose
    /// place a file of that name would take.
    static func figureFileName(_ name: String) -> String {
        let clean = fileName(name)
        return [dataFolder, codeFolder, inputFolder].contains(clean.lowercased()) ? ShelfFileName.numbered(clean, 2) : clean
    }

    /// Whether a (cleaned) file name is the folder's own README.md, in any case:
    /// a disk that ignores case takes "readme.md" for it too.
    static func isReadme(_ name: String) -> Bool {
        name.lowercased() == readmeName.lowercased()
    }

    /// "data/z_prime_by_plate.csv", "z_prime.png": the path, relative to the
    /// kept folder, a file of this role is written to and listed under in the
    /// README.
    static func relativePath(role: KeptRole, fileName name: String) -> String {
        let clean = fileName(name)
        guard let folder = folder(for: role) else { return clean }
        return "\(folder)/\(clean)"
    }

    /// Whether `path` is one a keep may write: a file name at the top, or in
    /// `data/`, `code/` or `input/`, and each part exactly as `fileName` would
    /// have made it. That refuses an absolute path, `..`, a hidden file, a
    /// deeper folder, and `README.md`, so nothing written can leave the folder
    /// or take the README's place.
    static func isValidRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        func isFileName(_ part: String) -> Bool { !part.isEmpty && fileName(part) == part }
        switch parts.count {
        case 1:
            return isFileName(parts[0])
        case 2:
            return [dataFolder, codeFolder, inputFolder].contains(parts[0]) && isFileName(parts[1])
        default:
            return false
        }
    }
}

/// The folder Kept uses when nothing says otherwise.
enum KeptDefaults {
    static let folderName = "Kept"

    /// `~/Documents/Kept`. The home folder is handed in so a test can give its
    /// own; nothing is looked at.
    static func root(home: URL = .homeDirectory) -> URL {
        home.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    /// The folder a setting names: empty is the default, "~" and "~/…" start at
    /// the home folder, an absolute path is itself, and anything else is
    /// taken as inside the home folder. Nothing is looked at.
    static func root(setting: String, home: URL = .homeDirectory) -> URL {
        let path = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return root(home: home) }
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2)), directoryHint: .isDirectory) }
        if path.hasPrefix("/") { return URL(filePath: path, directoryHint: .isDirectory) }
        return home.appending(path: path, directoryHint: .isDirectory)
    }
}
