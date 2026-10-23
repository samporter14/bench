// KeptDiskCallsTests.swift — nothing in the Kept code asks the disk anything
// on the main actor (DESIGN.md, Kept, and Results: No file-system call on the
// main actor). The same scan as `ResultsDiskCallsTests`, over Kept/: every way
// the code reaches the file system is looked for, in every file of the folder,
// and only KeptDisk.swift may have any, and only inside `KeptDiskWork`, the
// enum whose calls `KeptDisk` runs on its own queue. A file added to Kept/
// that makes none (names and paths, a view, a model) passes as it is; one that
// does makes this test fail until its calls are moved behind `KeptDisk`.
import Foundation
import Testing
@testable import Bench

struct KeptDiskCallsTests {
    private static var folder: URL {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Kept", isDirectory: true)
    }

    /// Every way the Kept code can reach the file system: the file manager, the
    /// C calls, and reads and writes of a URL. (The first group is the one
    /// `ResultsDiskCallsTests` scans for.)
    private static let calls = [
        "FileManager.default", "fileManager.", "opendir(", "readdir(", "Data(contentsOf", "String(contentsOf",
        "resourceValues(", "checkResourceIsReachable(", "standardizedFileURL", "resolvingSymlinksInPath",
        "FileHandle(", "NSWorkspace", "bookmarkData(",
        // What a file manager or a URL does to the disk, whatever the file manager is called.
        "FileManager(", ".createDirectory(", ".removeItem(", ".moveItem(", ".copyItem(", ".contentsOfDirectory(",
        ".fileExists(", ".attributesOfItem(", ".subpathsOfDirectory(", ".write(to:", "renamex_np(", "NSFileCoordinator",
        // The Trash.
        ".trashItem(",
    ]

    /// `file: call` → how many lines of code say it, in every file of Kept/.
    private func found() throws -> [String: Int] {
        var found: [String: Int] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".swift") {
            let text = try String(contentsOf: Self.folder.appending(path: name, directoryHint: .notDirectory), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for call in Self.calls where code.contains(call) { found["\(name): \(call)", default: 0] += 1 }
                // A file URL made without saying whether it is a folder looks at the disk to find out.
                if code.contains("URL(fileURLWithPath:"), !code.contains("isDirectory:") {
                    found["\(name): URL(fileURLWithPath:) without isDirectory", default: 0] += 1
                }
            }
        }
        return found
    }

    /// What each file of Kept/ may say (of the calls this scans for). Only the
    /// disk layer, and only the calls it makes on its queue.
    @Test func theOnlyFileSystemCallsAreTheOnesTheDiskLayerMakesOnItsQueue() throws {
        let allowed: [String: Int] = [
            // The one file-manager property every blocking call goes through, and the calls it makes.
            "KeptDisk.swift: FileManager.default": 1,
            "KeptDisk.swift: .createDirectory(": 2,
            "KeptDisk.swift: .contentsOfDirectory(": 1,
            "KeptDisk.swift: .fileExists(": 1,
            "KeptDisk.swift: .attributesOfItem(": 1,
            "KeptDisk.swift: .moveItem(": 1,
            "KeptDisk.swift: .removeItem(": 1,
            // Taking a folder off the shelf: into the Trash, never deleted.
            "KeptDisk.swift: .trashItem(": 1,
            // A text file's first bytes, for its card (and a look at whether iCloud has it).
            "KeptDisk.swift: FileHandle(": 1,
            "KeptDisk.swift: resourceValues(": 1,
            // The README's bytes, read whole; the atomic writes of a file, a README and a legend.
            "KeptDisk.swift: Data(contentsOf": 1,
            "KeptDisk.swift: .write(to:": 4,
            // The rename that refuses to replace a folder.
            "KeptDisk.swift: renamex_np(": 1,
            // Finder and the default app, asked to show or open a kept file (a UI call, not a look at the disk),
            // and the temporary folder a demo names: none of these reads or writes anything.
            "KeepModel.swift: NSWorkspace": 1,
            "KeptDemo.swift: FileManager.default": 1,
            "ShelfView.swift: NSWorkspace": 5,
            // Make PDF…'s drawing runs on a queue of its own (ShelfPDF.swift): its PDF is written to a temporary
            // file and moved over the old one only when whole, and a failed one is cleared away. Finder is
            // asked to show the file it made (a UI call, as above).
            "ShelfPDF.swift: FileManager.default": 1,
            "ShelfPDF.swift: .moveItem(": 1,
            "ShelfPDF.swift: .removeItem(": 1,
            "ShelfPDFCommand.swift: NSWorkspace": 1,
        ]
        let now = try found()
        #expect(now == allowed, "now: \(now.sorted { $0.key < $1.key })")
    }

    /// The counts above can't tell main-actor code from queue code, so this
    /// does: in KeptDisk.swift every such call comes after the start of
    /// `KeptDiskWork`, which is not main-actor code.
    @Test func everyCallInTheDiskLayerIsInsideTheEnumThatRunsOnItsQueue() throws {
        let text = try String(contentsOf: Self.folder.appending(path: "KeptDisk.swift", directoryHint: .notDirectory), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = try #require(lines.firstIndex { $0.hasPrefix("private enum KeptDiskWork") })
        // Nothing is main-actor code after it: the enum is not marked, and nothing else follows.
        #expect(!lines[start...].contains { $0.hasPrefix("@MainActor") })
        var outside: [String] = []
        for (number, line) in lines.enumerated() where number < start {
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//") else { continue }
            if Self.calls.contains(where: code.contains) { outside.append("\(number + 1): \(code)") }
        }
        #expect(outside.isEmpty, "\(outside)")
        // And the enum is the last thing in the file's code of that kind: its calls are the ones counted above.
        #expect(lines[start...].contains { $0.contains("FileManager.default") })
    }

    @Test func theScanFindsTheFilesItIsMeantToRead() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path)
        #expect(names.contains("KeptDisk.swift"))
        #expect(names.contains("KeptFolder.swift"))
        #expect(names.contains("KeptReadme.swift"))
    }
}
