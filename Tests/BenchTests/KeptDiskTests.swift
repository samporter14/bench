// KeptDiskTests.swift — the disk layer of Keep (KeptDisk.swift) on a scratch
// Kept folder made for each test, with made-up figures: that a keep is laid out
// exactly and its README is written last, that a name taken is never
// overwritten, that an abandoned keep leaves nothing, what a look finds (and
// passes over), the legend's round trip and its refusal after an outside edit
// (and the README's, when it is replaced after Try Again, byte order mark and all),
// what a folder that isn't there says, and what a folder that stops answering
// says: held as a dropped volume would hold it, with a clock that never sleeps.
// Nothing here touches a real folder: the root is under the temporary folder.
import CryptoKit
import Foundation
import Testing
@testable import Bench

// MARK: Made-up keeps and a scratch folder

/// 22 October 2026, 9:12 at -04:00.
private let when = Date(timeIntervalSince1970: 1_792_674_720)
private let figureName = "Fig 2B · Z′ by plate"
private let png = Data("made-up figure bytes".utf8)
private let csv = Data("plate,z_prime\n1,0.71\n2,0.64\n3,0.52\n".utf8)
private let script = Data("print('Z′ by plate')\n".utf8)
private let sheet = Data("made-up raw input".utf8)

private func made(_ name: String = figureName, at date: Date = when, missing: Bool = false) -> (KeptRecord, KeptText) {
    let record = KeptRecord(
        name: name, keptAt: date, projectID: "proj_1", projectName: "Assay development",
        sessionID: "frame_1", sessionTitle: "Plate reader QC",
        figure: KeptFile(path: "z_prime.png", role: .figure, artifact: "art_1", version: "ver_3", index: 3, of: 4,
                         sha256: KeptDisk.sha256(of: png), bytes: png.count),
        files: [
            KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: "art_2", version: "ver_9",
                     sha256: KeptDisk.sha256(of: csv), bytes: csv.count),
            KeptFile(path: "code/plot_z_prime.py", role: .code, artifact: "art_3", version: "ver_7",
                     sha256: KeptDisk.sha256(of: script), bytes: script.count),
        ],
        missing: missing ? [KeptMissing(role: .input, name: "plate_reader.xlsx", reason: "too big to keep here (over 8 MB)")] : [],
        claudeScience: "0.1.70", capsid: "1.0")
    let text = KeptText(legend: "", claudeSaid: "Z′ is above 0.5 for every plate.",
                        attribution: "From Claude’s answer.", origin: "")
    return (record, text)
}

private func readme(_ name: String = figureName, at date: Date = when, missing: Bool = false, legend: String = "") -> String {
    var (record, text) = made(name, at: date, missing: missing)
    text.legend = legend
    return KeptReadme.render(record, text: text)
}

private var files: FileManager { FileManager.default }

/// Everything under a folder, as paths relative to it, folders included.
private func listing(_ folder: URL) throws -> [String] {
    try files.subpathsOfDirectory(atPath: folder.path).sorted()
}

private func names(_ folder: URL) throws -> [String] {
    try files.contentsOfDirectory(atPath: folder.path).sorted()
}

/// A scratch folder with the Kept folder in it (made, unless asked not to),
/// removed when the test ends.
@MainActor
private func inScratch(makeRoot: Bool = true,
                       _ body: (_ scratch: URL, _ root: URL, _ disk: KeptDisk) async throws -> Void) async throws {
    let scratch = files.temporaryDirectory.appending(path: "capsid-tests-kept-\(UUID().uuidString)", directoryHint: .isDirectory)
    try files.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: scratch) }
    let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
    if makeRoot { try files.createDirectory(at: root, withIntermediateDirectories: false) }
    try await body(scratch, root, KeptDisk(root: { root }))
}

/// A whole keep: the figure, a data file, a script, and the README.
@MainActor
@discardableResult
private func keep(_ disk: KeptDisk, collection: String = "Assay development", name: String = figureName,
                  at date: Date = when, missing: Bool = false, legend: String = "") async throws -> URL {
    let destination = try await disk.prepare(collection: collection, name: name, at: date)
    try await disk.write(png, to: "z_prime.png", in: destination)
    try await disk.write(csv, to: "data/z_prime_by_plate.csv", in: destination)
    try await disk.write(script, to: "code/plot_z_prime.py", in: destination)
    return try await disk.finish(destination, readme: readme(name, at: date, missing: missing, legend: legend))
}

private func standardized(_ url: URL) -> String {
    url.resolvingSymlinksInPath().path
}

// MARK: Keeping

@Suite(.serialized) @MainActor
struct KeptDiskTests {
    @Test func aKeepIsLaidOutExactlyAndTheReadmeIsWrittenLast() async throws {
        try await inScratch { _, root, disk in
            let destination = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            #expect(destination.collection == "Assay development")
            #expect(destination.name == figureName)
            #expect(destination.finalFolder == root.appending(path: "Assay development/\(figureName)", directoryHint: .isDirectory))
            let collection = root.appending(path: "Assay development", directoryHint: .isDirectory)
            // A hidden folder beside the one it will be, and nothing else yet.
            #expect(destination.tempFolder.deletingLastPathComponent() == collection)
            #expect(destination.tempFolder.lastPathComponent.hasPrefix(".\(figureName).keeping-"))
            #expect(try names(collection) == [destination.tempFolder.lastPathComponent])
            #expect(try listing(destination.tempFolder) == [])

            try await disk.write(png, to: "z_prime.png", in: destination)
            try await disk.write(csv, to: "data/z_prime_by_plate.csv", in: destination)
            try await disk.write(script, to: "code/plot_z_prime.py", in: destination)
            try await disk.write(sheet, to: "input/plate_reader.xlsx", in: destination)
            // Folders made as needed, each file there whole, no README yet, no leftovers of the atomic writes.
            #expect(try listing(destination.tempFolder) == ["code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv",
                                                           "input", "input/plate_reader.xlsx", "z_prime.png"])
            #expect(try Data(contentsOf: destination.tempFolder.appending(path: "data/z_prime_by_plate.csv")) == csv)
            #expect(try names(collection) == [destination.tempFolder.lastPathComponent])

            let text = readme()
            let landed = try await disk.finish(destination, readme: text)
            #expect(landed == destination.finalFolder)
            #expect(try names(collection) == [figureName])
            #expect(try listing(landed) == ["README.md", "code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv",
                                           "input", "input/plate_reader.xlsx", "z_prime.png"])
            #expect(try String(contentsOf: landed.appending(path: "README.md"), encoding: .utf8) == text)
            #expect(try Data(contentsOf: landed.appending(path: "z_prime.png")) == png)
            #expect(try Data(contentsOf: landed.appending(path: "code/plot_z_prime.py")) == script)
            // The README was the last file written.
            func modified(_ path: String) throws -> Date {
                try #require(try files.attributesOfItem(atPath: landed.appending(path: path).path)[.modificationDate] as? Date)
            }
            let readmeTime = try modified("README.md")
            for path in ["z_prime.png", "data/z_prime_by_plate.csv", "code/plot_z_prime.py", "input/plate_reader.xlsx"] {
                #expect(try modified(path) <= readmeTime, "\(path)")
            }
        }
    }

    @Test func aSecondKeepUnderTheSameNameGetsTheDatedFolderAndNothingIsOverwritten() async throws {
        try await inScratch { _, root, disk in
            let first = try await keep(disk, legend: "the first")
            let firstReadme = try Data(contentsOf: first.appending(path: "README.md"))

            let later = when.addingTimeInterval(600)
            let second = try await keep(disk, at: later, legend: "the second")
            let dated = KeptName.dated(figureName, at: later)
            #expect(second.lastPathComponent == dated)
            #expect(dated.hasPrefix("\(figureName) 20"))
            // The first is exactly as it was.
            #expect(try Data(contentsOf: first.appending(path: "README.md")) == firstReadme)
            #expect(try listing(first).count == 6)
            #expect(try String(contentsOf: second.appending(path: "README.md"), encoding: .utf8).contains("the second"))

            // A third in the same minute is numbered, and still nothing is replaced.
            let third = try await keep(disk, at: later, legend: "the third")
            #expect(third.lastPathComponent == KeptName.numbered(dated, 2))
            #expect(try String(contentsOf: second.appending(path: "README.md"), encoding: .utf8).contains("the second"))
            #expect(try names(root.appending(path: "Assay development")) == [figureName, dated, KeptName.numbered(dated, 2)].sorted())
        }
    }

    @Test func aNameThatAppearedMeanwhileIsNeverReplacedByTheRename() async throws {
        try await inScratch { _, root, disk in
            // Two keeps prepared at once for one name: both are told the plain name.
            let one = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            let two = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            #expect(one.finalFolder == two.finalFolder)
            try await disk.write(png, to: "z_prime.png", in: one)
            try await disk.write(png, to: "z_prime.png", in: two)
            let landedOne = try await disk.finish(one, readme: readme())
            let landedTwo = try await disk.finish(two, readme: readme())
            #expect(landedOne == one.finalFolder)
            #expect(landedTwo.lastPathComponent == KeptName.dated(figureName, at: when))

            // A name taken by an empty folder, the case a plain rename would replace.
            let three = try await disk.prepare(collection: "Plates", name: "Run 7", at: when)
            let empty = root.appending(path: "Plates/Run 7", directoryHint: .isDirectory)
            try files.createDirectory(at: empty, withIntermediateDirectories: false)
            let landedThree = try await disk.finish(three, readme: readme("Run 7"))
            #expect(landedThree.lastPathComponent == KeptName.dated("Run 7", at: when))
            #expect(try listing(empty) == [])
            #expect(try listing(landedThree) == ["README.md"])
        }
    }

    @Test func anAbandonedKeepLeavesNothing() async throws {
        try await inScratch { _, root, disk in
            let destination = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            try await disk.write(png, to: "z_prime.png", in: destination)
            try await disk.write(csv, to: "data/z_prime_by_plate.csv", in: destination)
            await disk.abandon(destination)
            #expect(try names(root.appending(path: "Assay development")) == [])
            // Abandoning twice, or a keep that never wrote, is harmless.
            await disk.abandon(destination)
            // A folder that is not a keep's hidden one is never deleted.
            let kept = try await keep(disk)
            await disk.abandon(KeptDestination(collection: "Assay development", name: figureName, finalFolder: kept, tempFolder: kept))
            #expect(try listing(kept).count == 6)
        }
    }

    @Test func aFileIsNeverWrittenOverAnotherOrOutsideTheFolder() async throws {
        try await inScratch { scratch, root, disk in
            let destination = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            try await disk.write(png, to: "z_prime.png", in: destination)
            await #expect(throws: KeptDiskError.failed("A file with this name is already there.")) {
                try await disk.write(Data("other".utf8), to: "z_prime.png", in: destination)
            }
            #expect(try Data(contentsOf: destination.tempFolder.appending(path: "z_prime.png")) == png)
            let refusal = KeptDiskError.failed("That file's name can't be used in a Kept folder.")
            for path in ["../escape.png", "/tmp/escape.png", "data/../../escape.png", "README.md", "other/x.csv", "data/sub/x.csv", ".hidden", ""] {
                await #expect(throws: refusal, "\(path)") {
                    try await disk.write(Data("x".utf8), to: path, in: destination)
                }
            }
            #expect(!files.fileExists(atPath: scratch.appending(path: "escape.png").path))
            #expect(!files.fileExists(atPath: root.appending(path: "escape.png").path))
            #expect(try listing(destination.tempFolder) == ["z_prime.png"])
            // Once the keep is gone, a write to it fails and makes nothing.
            await disk.abandon(destination)
            await #expect(throws: KeptDiskError.failed("The folder for this keep isn't there.")) {
                try await disk.write(png, to: "data/x.csv", in: destination)
            }
            #expect(try names(root.appending(path: "Assay development")) == [])
        }
    }

    @Test func theCollectionAndTheNameAreCleanedAsFolderNames() async throws {
        try await inScratch { _, root, disk in
            let destination = try await disk.prepare(collection: "Lab/2026: plates", name: "../Run: 7", at: when)
            #expect(destination.collection == "Lab_2026_ plates")
            #expect(destination.name == "_Run_ 7")
            try await disk.write(png, to: "z.png", in: destination)
            let landed = try await disk.finish(destination, readme: readme())
            #expect(landed == root.appending(path: "Lab_2026_ plates/_Run_ 7", directoryHint: .isDirectory))
            #expect(try names(root) == ["Lab_2026_ plates"])
        }
    }

    @Test func aKeptFolderTakesOneMoreFileAndNeverReplacesOne() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, missing: true)
            try await disk.writeInto(folder, sheet, relativePath: "input/plate_reader.xlsx")
            #expect(try Data(contentsOf: folder.appending(path: "input/plate_reader.xlsx")) == sheet)
            // A second write to a taken path is refused, and the first stays.
            await #expect(throws: KeptDiskError.failed("A file with this name is already there.")) {
                try await disk.writeInto(folder, Data("other".utf8), relativePath: "input/plate_reader.xlsx")
            }
            await #expect(throws: KeptDiskError.failed("A file with this name is already there.")) {
                try await disk.writeInto(folder, Data("other".utf8), relativePath: "z_prime.png")
            }
            #expect(try Data(contentsOf: folder.appending(path: "input/plate_reader.xlsx")) == sheet)
            #expect(try Data(contentsOf: folder.appending(path: "z_prime.png")) == png)
            // The folder's own README, and paths out of it, are not writable.
            for path in ["README.md", "../x.csv", "data/../../x.csv"] {
                await #expect(throws: KeptDiskError.failed("That file's name can't be used in a Kept folder.")) {
                    try await disk.writeInto(folder, sheet, relativePath: path)
                }
            }
            #expect(try listing(folder) == ["README.md", "code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv",
                                           "input", "input/plate_reader.xlsx", "z_prime.png"])
        }
    }

    @Test func aFolderThatIsNotKeptIsNeverWrittenInto() async throws {
        try await inScratch { _, root, disk in
            let plain = root.appending(path: "Assay development/My own notes", directoryHint: .isDirectory)
            try files.createDirectory(at: plain, withIntermediateDirectories: true)
            try Data("# My notes\n".utf8).write(to: plain.appending(path: "README.md"))
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                try await disk.writeInto(plain, sheet, relativePath: "input/x.xlsx")
            }
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                try await disk.replaceReadme(at: plain, markdown: readme())
            }
            #expect(try listing(plain) == ["README.md"])
            #expect(try String(contentsOf: plain.appending(path: "README.md"), encoding: .utf8) == "# My notes\n")
        }
    }

    @Test func tryAgainRewritesTheReadmeAndItIsReadBack() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, missing: true)
            let before = try await disk.readme(at: folder)
            #expect(before.record.missing.count == 1)
            #expect(before.markdown.contains("## Not copied"))

            // The missing file comes in, and the README is rewritten without it.
            try await disk.writeInto(folder, sheet, relativePath: "input/plate_reader.xlsx")
            var (record, text) = made()
            record.files.append(KeptFile(path: "input/plate_reader.xlsx", role: .input, artifact: "art_4", version: "ver_1",
                                         sha256: KeptDisk.sha256(of: sheet), bytes: sheet.count))
            text.legend = before.text.legend
            let rewritten = KeptReadme.render(record, text: text)
            try await disk.replaceReadme(at: folder, markdown: rewritten)

            #expect(try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8) == rewritten)
            let after = try await disk.readme(at: folder)
            #expect(after.record == record)
            #expect(after.record.missing.isEmpty)
            #expect(!after.markdown.contains("## Not copied"))
            // No temporary file is left beside it.
            #expect(try listing(folder) == ["README.md", "code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv",
                                           "input", "input/plate_reader.xlsx", "z_prime.png"])
            // A README that isn't one Capsid can read back is not put in its place.
            await #expect(throws: KeptDiskError.failed("That README isn't one Capsid can read back.")) {
                try await disk.replaceReadme(at: folder, markdown: "# Nothing\n")
            }
            #expect(try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8) == rewritten)
            // And the scan sees the new one.
            let found = try await disk.scan()
            #expect(found.count == 1)
            #expect(found.first?.record.files.count == 3)
        }
    }

    @Test func aReadmeIsReplacedOnlyIfItIsStillWhatWasRead() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, missing: true)
            let url = folder.appending(path: "README.md")
            let read = try await disk.readme(at: folder)
            let (record, base) = made()
            var text = base
            text.legend = read.text.legend
            let rewritten = KeptReadme.render(record, text: text)

            // Edited in another app after it was read: left as that app saved it, nothing beside it.
            let edited = read.markdown + "\nAdded in an editor.\n"
            try Data(edited.utf8).write(to: url)
            await #expect(throws: KeptDiskError.changedOutside) {
                try await disk.replaceReadme(at: folder, markdown: rewritten, lastRead: read.markdown)
            }
            #expect(try Data(contentsOf: url) == Data(edited.utf8))
            #expect(try listing(folder) == ["README.md", "code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv", "z_prime.png"])

            // Read again, it goes through.
            let now = try await disk.readme(at: folder)
            try await disk.replaceReadme(at: folder, markdown: rewritten, lastRead: now.markdown)
            #expect(try String(contentsOf: url, encoding: .utf8) == rewritten)

            // A README that is gone is refused, whatever was read.
            try files.removeItem(at: url)
            await #expect(throws: KeptDiskError.failed("There is no README.md in this folder.")) {
                try await disk.replaceReadme(at: folder, markdown: rewritten, lastRead: rewritten)
            }
        }
    }

    @Test func aByteOrderMarkIsComparedWithoutItAndKept() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, missing: true)
            let url = folder.appending(path: "README.md")
            let mark = Data([0xEF, 0xBB, 0xBF])
            try (mark + Data(readme(missing: true).utf8)).write(to: url)
            // Reading it as text drops the mark; the README is still the one that was read.
            let read = try await disk.readme(at: folder)
            #expect(!read.markdown.hasPrefix("\u{FEFF}"))
            let rewritten = readme(missing: false)
            try await disk.replaceReadme(at: folder, markdown: rewritten, lastRead: read.markdown)
            #expect(try Data(contentsOf: url) == mark + Data(rewritten.utf8))
            // The README is not what was read any more: refused, mark or no mark.
            await #expect(throws: KeptDiskError.changedOutside) {
                try await disk.replaceReadme(at: folder, markdown: rewritten, lastRead: read.markdown)
            }
        }
    }
}

// MARK: Looking

@Suite(.serialized) @MainActor
struct KeptDiskLookTests {
    @Test func aScanFindsEveryKeepNewestFirstAndPassesOverTheRest() async throws {
        try await inScratch { _, root, disk in
            let older = try await keep(disk, collection: "Assay development", name: "Fig 1A · Z′", at: when)
            let newer = try await keep(disk, collection: "Imaging", name: "Fig 3 · Z′ by plate", at: when.addingTimeInterval(3600))
            // A tie in the time is broken by the folder's path, the same way every time.
            let tied = try await keep(disk, collection: "Imaging", name: "Fig 3 · Z′ again", at: when.addingTimeInterval(3600))

            // A keep in progress, a hidden folder, a folder with no marker, one with no README, a stray file, a broken README.
            let building = try await disk.prepare(collection: "Imaging", name: "Fig 4 · half done", at: when)
            try await disk.write(png, to: "z_prime.png", in: building)
            let plain = root.appending(path: "Imaging/My own notes", directoryHint: .isDirectory)
            try files.createDirectory(at: plain, withIntermediateDirectories: true)
            try Data("# My notes\n".utf8).write(to: plain.appending(path: "README.md"))
            try files.createDirectory(at: root.appending(path: "Imaging/Empty folder"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appending(path: "Imaging/stray.txt"))
            let broken = root.appending(path: "Imaging/Broken", directoryHint: .isDirectory)
            try files.createDirectory(at: broken, withIntermediateDirectories: true)
            let damaged = readme().replacingOccurrences(of: "figure: { file: \"z_prime.png\"", with: "figure: { file: z_prime.png")
            #expect(damaged != readme())
            try Data(damaged.utf8).write(to: broken.appending(path: "README.md"))
            let hiddenCollection = root.appending(path: ".Trash-ish/Fig 9", directoryHint: .isDirectory)
            try files.createDirectory(at: hiddenCollection, withIntermediateDirectories: true)
            try Data(readme().utf8).write(to: hiddenCollection.appending(path: "README.md"))
            let hiddenKeep = root.appending(path: "Imaging/.Fig 8", directoryHint: .isDirectory)
            try files.createDirectory(at: hiddenKeep, withIntermediateDirectories: true)
            try Data(readme().utf8).write(to: hiddenKeep.appending(path: "README.md"))
            try Data("loose".utf8).write(to: root.appending(path: "loose.txt"))
            // Too deep to be a keep's README.
            let deep = root.appending(path: "Imaging/Fig 3 · Z′ by plate/data/inner", directoryHint: .isDirectory)
            try files.createDirectory(at: deep, withIntermediateDirectories: true)
            try Data(readme().utf8).write(to: deep.appending(path: "README.md"))

            let found = try await disk.scan()
            #expect(found.map(\.collection) == ["Imaging", "Imaging", "Assay development"])
            let expected = [newer, tied].sorted { $0.path < $1.path } + [older]
            #expect(found.map { standardized($0.folder) } == expected.map(standardized))
            #expect(found.map(\.record.keptAt) == [when.addingTimeInterval(3600), when.addingTimeInterval(3600), when])
            #expect(found.last?.record.name == "Fig 1A · Z′")
            #expect(found.first?.id == found.first?.folder.path)
            #expect(found.first?.figureURL.lastPathComponent == "z_prime.png")
            #expect(found.first?.figureURL.deletingLastPathComponent().path == found.first?.folder.path)
            #expect(found.first?.record.files.count == 2)
            await disk.abandon(building)
        }
    }

    @Test func collectionsAreListedWithoutRegardToCase() async throws {
        try await inScratch { _, root, disk in
            for name in ["beta", "Alpha", "assay development", "Zeta", ".hidden"] {
                try files.createDirectory(at: root.appending(path: name, directoryHint: .isDirectory), withIntermediateDirectories: false)
            }
            try Data("x".utf8).write(to: root.appending(path: "not a folder.txt"))
            #expect(try await disk.listCollections() == ["Alpha", "assay development", "beta", "Zeta"])
        }
    }

    @Test func aReadmeIsReadAndParsed() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, legend: "Plate 3 was re-run.")
            let found = try await disk.readme(at: folder)
            #expect(found.markdown == readme(legend: "Plate 3 was re-run."))
            #expect(found.record == made().0)
            #expect(found.text.legend == "Plate 3 was re-run.")
            #expect(found.text.claudeSaid == "Z′ is above 0.5 for every plate.")

            let plain = folder.deletingLastPathComponent().appending(path: "Plain", directoryHint: .isDirectory)
            try files.createDirectory(at: plain, withIntermediateDirectories: false)
            await #expect(throws: KeptDiskError.failed("There is no README.md in this folder.")) { try await disk.readme(at: plain) }
            try Data("# Notes\n".utf8).write(to: plain.appending(path: "README.md"))
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) { try await disk.readme(at: plain) }
        }
    }

    @Test func aNameIsTakenOnlyWhenThatFolderIsThere() async throws {
        try await inScratch { _, _, disk in
            #expect(try await !disk.isTaken(collection: "Assay development", name: figureName))
            try await keep(disk)
            #expect(try await disk.isTaken(collection: "Assay development", name: figureName))
            // A new name, and a new collection with the same name, are free.
            #expect(try await !disk.isTaken(collection: "Assay development", name: "Fig 2C · Z′"))
            #expect(try await !disk.isTaken(collection: "Imaging", name: figureName))
            // Names are cleaned the way a keep cleans them.
            try await keep(disk, name: "a/b")
            #expect(try await disk.isTaken(collection: "Assay development", name: "a_b"))
            #expect(try await disk.isTaken(collection: "Assay development", name: "a/b"))
            // A keep in progress is not a name taken (it has no name yet).
            let building = try await disk.prepare(collection: "Assay development", name: "Fig 5", at: when)
            #expect(try await !disk.isTaken(collection: "Assay development", name: "Fig 5"))
            await disk.abandon(building)
        }
    }

    @Test func theLegendIsReplacedAndPutBack() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk)
            let original = try await disk.readme(at: folder)
            #expect(original.text.legend == "")

            let written = try await disk.replaceLegend(at: folder, with: "Z′ above 0.5, plate 3 re-run.", lastRead: original.markdown)
            #expect(written == KeptReadme.replacingLegend(in: original.markdown, with: "Z′ above 0.5, plate 3 re-run."))
            #expect(try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8) == written)
            let again = try await disk.readme(at: folder)
            #expect(again.text.legend == "Z′ above 0.5, plate 3 re-run.")
            #expect(again.record == original.record)
            #expect(again.text.claudeSaid == original.text.claudeSaid)
            // Nothing is left beside it, and the rest of the folder is as it was.
            #expect(try listing(folder).count == 6)

            // Emptied again, it is the file it was.
            let restored = try await disk.replaceLegend(at: folder, with: "", lastRead: written)
            #expect(Array(restored.utf8) == Array(original.markdown.utf8))
            #expect(try Data(contentsOf: folder.appending(path: "README.md")) == Data(original.markdown.utf8))
        }
    }

    @Test func aReadmeChangedInAnotherAppIsNotReplaced() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk, legend: "mine")
            let original = try await disk.readme(at: folder)
            let url = folder.appending(path: "README.md")

            // Edited elsewhere: a word added to the legend.
            let edited = original.markdown.replacingOccurrences(of: "\nmine\n", with: "\nmine, and more\n")
            try Data(edited.utf8).write(to: url)
            await #expect(throws: KeptDiskError.changedOutside) {
                try await disk.replaceLegend(at: folder, with: "overwritten", lastRead: original.markdown)
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == edited)
            #expect(KeptDiskError.changedOutside.errorDescription == "README.md was changed in another app.")

            // Once read again, it goes through.
            let current = try await disk.readme(at: folder)
            let next = try await disk.replaceLegend(at: folder, with: "overwritten", lastRead: current.markdown)
            #expect(next.contains("\noverwritten\n"))
        }
    }

    @Test func aChangeOnlyInHowACharacterIsWrittenCountsAsAChange() async throws {
        try await inScratch { _, _, disk in
            let composed = "Caf\u{E9} plate"          // é as one character
            let decomposed = "Cafe\u{301} plate"      // é as e and an accent: equal as Strings, different bytes
            #expect(composed == decomposed)
            let folder = try await keep(disk, legend: composed)
            let onDisk = try await disk.readme(at: folder).markdown
            #expect(Array(onDisk.utf8) != Array(onDisk.replacingOccurrences(of: composed, with: decomposed).utf8))
            let other = onDisk.replacingOccurrences(of: composed, with: decomposed)
            #expect(other == onDisk)
            await #expect(throws: KeptDiskError.changedOutside) {
                try await disk.replaceLegend(at: folder, with: "new", lastRead: other)
            }
            // A README that is gone, or that has no marker, is refused too.
            let url = folder.appending(path: "README.md")
            try Data("# Not ours\n".utf8).write(to: url)
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                try await disk.replaceLegend(at: folder, with: "new", lastRead: "# Not ours\n")
            }
            try files.removeItem(at: url)
            await #expect(throws: KeptDiskError.failed("There is no README.md in this folder.")) {
                try await disk.replaceLegend(at: folder, with: "new", lastRead: onDisk)
            }
        }
    }
}

// MARK: A Kept folder that isn't there

@Suite(.serialized) @MainActor
struct KeptDiskRootTests {
    @Test func aKeptFolderWhoseParentIsGoneIsMissing() async throws {
        try await inScratch(makeRoot: false) { scratch, _, _ in
            let gone = scratch.appending(path: "Drive/Kept", directoryHint: .isDirectory)
            let disk = KeptDisk(root: { gone })
            await #expect(throws: KeptDiskError.rootMissing) { try await disk.scan() }
            await #expect(throws: KeptDiskError.rootMissing) { try await disk.listCollections() }
            await #expect(throws: KeptDiskError.rootMissing) {
                try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            }
            // Nothing was made on the way.
            #expect(try names(scratch) == [])
            #expect(KeptDiskError.rootMissing.errorDescription == "The Kept folder isn't there.")
            // A file where the folder should be is no folder either.
            let file = scratch.appending(path: "Kept", directoryHint: .isDirectory)
            try Data("x".utf8).write(to: file)
            await #expect(throws: KeptDiskError.rootMissing) { try await KeptDisk(root: { file }).scan() }
        }
    }

    @Test func aKeptFolderNotMadeYetIsEmptyAndTheFirstKeepMakesIt() async throws {
        try await inScratch(makeRoot: false) { scratch, root, disk in
            #expect(try await disk.scan() == [])
            #expect(try await disk.listCollections() == [])
            #expect(try await !disk.isTaken(collection: "Assay development", name: figureName))
            #expect(try names(scratch) == [])
            let folder = try await keep(disk)
            #expect(try names(scratch) == ["Kept"])
            #expect(try names(root) == ["Assay development"])
            #expect(folder == root.appending(path: "Assay development/\(figureName)", directoryHint: .isDirectory))
            #expect(try await disk.scan().count == 1)
        }
    }

    @Test func theRootIsAskedEachTimeSoAChangedSettingIsSeen() async throws {
        try await inScratch { scratch, root, _ in
            let other = scratch.appending(path: "Elsewhere", directoryHint: .isDirectory)
            try files.createDirectory(at: other, withIntermediateDirectories: false)
            var current = root
            let disk = KeptDisk(root: { current })
            try await keep(disk)
            #expect(try await disk.scan().count == 1)
            current = other
            #expect(try await disk.scan().count == 0)
        }
    }
}

// MARK: Facts

@Suite @MainActor
struct KeptDiskFactsTests {
    @Test func theChecksumIsSHA256InLowercaseHex() {
        let disk = KeptDisk(root: { URL(filePath: "/nowhere", directoryHint: .isDirectory) })
        #expect(disk.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(disk.sha256(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(KeptDisk.sha256(of: Data("abc".utf8)) == disk.sha256(of: Data("abc".utf8)))
        #expect(disk.sha256(of: Data(repeating: 0xFF, count: 10_000)).count == 64)
    }

    @Test func aWriteGetsFifteenSecondsAndOneMoreForEachMiB() {
        #expect(KeptDisk.limit(forBytes: 0) == .seconds(15))
        #expect(KeptDisk.limit(forBytes: 1) == .seconds(16))
        #expect(KeptDisk.limit(forBytes: 1 << 20) == .seconds(16))
        #expect(KeptDisk.limit(forBytes: (1 << 20) + 1) == .seconds(17))
        #expect(KeptDisk.limit(forBytes: 8 << 20) == .seconds(23))
    }

    @Test func aSystemErrorComesToNoRoomNotAllowedOrItsOwnWords() {
        #expect(KeptDiskError.from(POSIXError(.ENOSPC)) == .noRoom)
        #expect(KeptDiskError.from(POSIXError(.EDQUOT)) == .noRoom)
        #expect(KeptDiskError.from(CocoaError(.fileWriteOutOfSpace)) == .noRoom)
        #expect(KeptDiskError.from(POSIXError(.EACCES)) == .denied("Capsid isn't allowed to change the Kept folder."))
        #expect(KeptDiskError.from(CocoaError(.fileWriteNoPermission)) == .denied("Capsid isn't allowed to change the Kept folder."))
        #expect(KeptDiskError.from(CocoaError(.fileReadNoPermission)) == .denied("Capsid isn't allowed to read the Kept folder."))
        // The cause may be underneath.
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        #expect(KeptDiskError.from(wrapped) == .noRoom)
        #expect(KeptDiskError.from(KeptDiskError.changedOutside) == .changedOutside)
        if case .failed(let words) = KeptDiskError.from(POSIXError(.EIO)) { #expect(!words.isEmpty) } else { Issue.record("not failed") }
        // The sentences.
        #expect(KeptDiskError.noRoom.errorDescription == "There isn't room on this disk.")
        #expect(KeptDiskError.notResponding(KeptDiskError.writeDidNotRespond).errorDescription
                == "The folder didn't respond. If it comes back, the file may still appear there.")
        #expect(KeptDiskError.stillSilent == "The folder still isn't responding.")
    }
}

// MARK: A folder that stops answering

/// A disk that holds its calls as a dropped volume would, until told to let
/// them go; every call is recorded with whether it ran on the main thread.
private final class HeldDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [KeptDisk.Work] = []
    private var hold = true
    private var mainThread: [Bool] = []

    var count: Int { lock.withLock { held.count } }
    var ranOnMain: [Bool] { lock.withLock { mainThread } }
    func setHold(_ on: Bool) { lock.withLock { hold = on } }

    func run(_ work: @escaping KeptDisk.Work) {
        let hold = lock.withLock { self.hold }
        if hold { lock.withLock { held.append(work) } } else { work() }
    }

    /// Lets the held calls finish, late, on this thread.
    func release() {
        let pending = lock.withLock { let all = held; held = []; return all }
        for work in pending { work() }
    }
}

@Suite(.serialized) @MainActor
struct KeptDiskSilenceTests {
    private func disk(root: URL, held: HeldDisk) -> KeptDisk {
        KeptDisk(root: { root }, wait: { _ in }, run: { held.run($0) })
    }

    @Test func aWriteThatNeverAnswersFailsWithTheFoldersSentenceThenTheFolderIsHeldOff() async throws {
        try await inScratch { _, root, _ in
            let held = HeldDisk()
            let disk = disk(root: root, held: held)
            await #expect(throws: KeptDiskError.notResponding("The folder didn't respond. If it comes back, the file may still appear there.")) {
                try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            }
            #expect(disk.isSilent)
            #expect(held.count == 1)
            // The next call is refused at once, and makes no call at all.
            await #expect(throws: KeptDiskError.notResponding("The folder still isn't responding.")) { try await disk.scan() }
            await #expect(throws: KeptDiskError.notResponding("The folder still isn't responding.")) {
                try await disk.write(png, to: "z_prime.png", in: KeptDestination(collection: "c", name: "n", finalFolder: root, tempFolder: root))
            }
            #expect(held.count == 1)

            // The folder comes back: the late call finishes, and the disk is let through again.
            held.setHold(false)
            held.release()
            #expect(!disk.isSilent)
            let found = try await disk.scan()
            #expect(found.isEmpty)
            #expect(held.count == 0)
        }
    }

    @Test func aLookThatNeverAnswersSaysSoWithoutTheLateFileClause() async throws {
        try await inScratch { _, root, _ in
            let held = HeldDisk()
            let disk = disk(root: root, held: held)
            await #expect(throws: KeptDiskError.notResponding("The folder didn't respond.")) { try await disk.scan() }
            await #expect(throws: KeptDiskError.notResponding("The folder didn't respond.")) {
                try await KeptDisk(root: { root }, wait: { _ in }, run: { held.run($0) }).listCollections()
            }
            held.setHold(false)
            held.release()
        }
    }

    @Test func abandoningStillGoesInBehindASilentFolder() async throws {
        try await inScratch { _, root, real in
            let destination = try await real.prepare(collection: "Assay development", name: figureName, at: when)
            let held = HeldDisk()
            let disk = disk(root: root, held: held)
            await #expect(throws: KeptDiskError.self) { try await disk.scan() }
            #expect(disk.isSilent)
            held.setHold(false)
            await disk.abandon(destination)
            #expect(try names(root.appending(path: "Assay development")) == [])
            held.release()
        }
    }

    @Test func aCancelledLookLetsItsCallerGoAtOnce() async throws {
        try await inScratch { _, root, _ in
            let held = HeldDisk()
            // A clock that never ends: only the cancel can let the caller go.
            let disk = KeptDisk(root: { root }, wait: { _ in try? await Task.sleep(for: .seconds(3600)) }, run: { held.run($0) })
            let task = Task { try await disk.scan() }
            for _ in 0..<1000 where held.count == 0 { await Task.yield() }
            #expect(held.count == 1)
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            // A cancel is not a folder that stopped answering.
            #expect(!disk.isSilent)
            held.setHold(false)
            held.release()
        }
    }

    @Test func theDiskWorkRunsOffTheMainThreadOnItsOwnQueue() async throws {
        try await inScratch { _, root, _ in
            let record = OnQueue()
            let disk = KeptDisk(root: { root }, run: { work in
                KeptDisk.runOnDisk {
                    record.note(onMain: Thread.isMainThread, qos: qos_class_self())
                    work()
                }
            })
            try await keep(disk)
            _ = try await disk.scan()
            _ = try await disk.listCollections()
            #expect(record.count >= 6)
            #expect(record.allOffMain)
            #expect(record.allUtility)
        }
    }
}

private final class OnQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var onMain: [Bool] = []
    private var classes: [qos_class_t] = []

    func note(onMain: Bool, qos: qos_class_t) {
        lock.withLock {
            self.onMain.append(onMain)
            classes.append(qos)
        }
    }

    var count: Int { lock.withLock { onMain.count } }
    var allOffMain: Bool { lock.withLock { !onMain.contains(true) } }
    var allUtility: Bool { lock.withLock { classes.allSatisfy { $0 == QOS_CLASS_UTILITY } } }
}

// MARK: The Trash

/// A stand-in for the Trash, a folder in the scratch folder, that counts what it was asked.
private final class FakeTrash: @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private var asked: [URL] = []

    init(in scratch: URL) throws {
        folder = scratch.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var requests: [URL] { lock.withLock { asked } }

    func take(_ source: URL) throws -> URL? {
        lock.withLock { asked.append(source) }
        let target = folder.appending(path: "\(UUID().uuidString) \(source.lastPathComponent)", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }
}

@Suite(.serialized) @MainActor
struct KeptDiskTrashTests {
    private func inTrashScratch(_ body: (_ scratch: URL, _ root: URL, _ disk: KeptDisk, _ trash: FakeTrash) async throws -> Void) async throws {
        let scratch = files.temporaryDirectory.appending(path: "capsid-tests-kept-trash-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        let trash = try FakeTrash(in: scratch)
        let disk = KeptDisk(root: { root }, trash: { try trash.take($0) })
        try await body(scratch, root, disk, trash)
    }

    @Test func aKeptFolderGoesToTheTrashWholeAndIsNotThereAnyMore() async throws {
        try await inTrashScratch { _, root, disk, trash in
            let folder = try await keep(disk)
            let trashed = try await disk.trash(folder)
            #expect(trash.requests == [folder])
            #expect(!files.fileExists(atPath: folder.path))
            #expect(trashed.deletingLastPathComponent() == trash.folder)
            // Everything came with it: nothing was deleted.
            #expect(try listing(trashed) == ["README.md", "code", "code/plot_z_prime.py", "data", "data/z_prime_by_plate.csv", "z_prime.png"])
            #expect(try Data(contentsOf: trashed.appending(path: "z_prime.png")) == png)
            #expect(try await disk.scan().isEmpty)
            _ = root
        }
    }

    @Test func onlyAFolderThatIsAResultIsEverMoved() async throws {
        try await inTrashScratch { scratch, root, disk, trash in
            let collection = root.appending(path: "Assay development", directoryHint: .isDirectory)
            // A folder with no README of ours, in the right place.
            let plain = collection.appending(path: "Mine", directoryHint: .isDirectory)
            try files.createDirectory(at: plain, withIntermediateDirectories: true)
            try Data("my notes".utf8).write(to: plain.appending(path: "notes.txt"))
            try Data("# Not ours\n".utf8).write(to: plain.appending(path: "README.md"))
            // A kept folder in the wrong place: the collection itself, the Kept folder, and one outside it.
            let kept = try await keep(disk)
            let outside = scratch.appending(path: "Elsewhere", directoryHint: .isDirectory)
            try files.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data(readme().utf8).write(to: outside.appending(path: "README.md"))
            let deeper = kept.appending(path: "data", directoryHint: .isDirectory)
            for refused in [plain, collection, root, outside, deeper, scratch] {
                await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                    _ = try await disk.trash(refused)
                }
            }
            #expect(trash.requests.isEmpty)
            #expect(files.fileExists(atPath: plain.appending(path: "notes.txt").path) && files.fileExists(atPath: kept.path))
            #expect(files.fileExists(atPath: outside.path))
        }
    }

    @Test func aFolderInProgressIsNotOneToMove() async throws {
        try await inTrashScratch { _, _, disk, trash in
            let destination = try await disk.prepare(collection: "Assay development", name: figureName, at: when)
            try await disk.write(png, to: "z_prime.png", in: destination)
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                _ = try await disk.trash(destination.tempFolder)
            }
            #expect(trash.requests.isEmpty)
        }
    }

    @Test func aFolderComesBackWhereItWasAndNeverOverAnotherFolder() async throws {
        try await inTrashScratch { _, root, disk, trash in
            let folder = try await keep(disk)
            let trashed = try await disk.trash(folder)
            let back = try await disk.restore(trashed, to: folder)
            #expect(back == folder)
            #expect(try listing(folder).contains("README.md"))
            #expect(try listing(trash.folder).isEmpty)

            // Something has the name now: the dated name, then a number; nothing is replaced.
            let second = try await disk.trash(folder)
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("mine".utf8).write(to: folder.appending(path: "mine.txt"))
            let dated = try await disk.restore(second, to: folder, at: when)
            #expect(dated.lastPathComponent == KeptName.dated(figureName, at: when))
            #expect(try Data(contentsOf: folder.appending(path: "mine.txt")) == Data("mine".utf8))
            #expect(try listing(dated).contains("README.md"))
            _ = root
        }
    }

    @Test func aCollectionThatWentWhileItWasInTheTrashIsMadeAgain() async throws {
        try await inTrashScratch { _, root, disk, _ in
            let folder = try await keep(disk)
            let trashed = try await disk.trash(folder)
            try files.removeItem(at: folder.deletingLastPathComponent())
            let back = try await disk.restore(trashed, to: folder)
            #expect(back == folder)
            #expect(try names(root) == ["Assay development"])
        }
    }

    @Test func whatIsntInTheTrashAnyMoreOrIsntOursIsRefused() async throws {
        try await inTrashScratch { scratch, root, disk, trash in
            let folder = try await keep(disk)
            let gone = trash.folder.appending(path: "nothing here", directoryHint: .isDirectory)
            await #expect(throws: KeptDiskError.failed("It isn't in the Trash any more.")) {
                _ = try await disk.restore(gone, to: folder)
            }
            let stranger = trash.folder.appending(path: "Stranger", directoryHint: .isDirectory)
            try files.createDirectory(at: stranger, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: stranger.appending(path: "a.txt"))
            await #expect(throws: KeptDiskError.failed("It isn't in the Trash any more.")) {
                _ = try await disk.restore(stranger, to: folder.deletingLastPathComponent().appending(path: "Other", directoryHint: .isDirectory))
            }
            // And never to a place outside the Kept folder.
            let trashed = try await disk.trash(folder)
            await #expect(throws: KeptDiskError.failed("This isn't a folder Capsid keeps.")) {
                _ = try await disk.restore(trashed, to: scratch.appending(path: "Out", directoryHint: .isDirectory))
            }
            #expect(files.fileExists(atPath: trashed.path))
            _ = root
        }
    }

    @Test func aDiskWithNoTrashSaysSoInASentence() {
        let error = CocoaError(.featureUnsupported)
        #expect(KeptDiskError.from(error) == .failed("This disk has no Trash, so Capsid can't take it off from here. Remove the folder in Finder."))
    }
}

// MARK: A look at a text file

@Suite(.serialized) @MainActor
struct KeptDiskPeekTests {
    @Test func aKeptTextFileIsReadForItsCardAndNothingElseIs() async throws {
        try await inScratch { scratch, root, disk in
            let folder = try await keep(disk)
            // The figure's bytes here are text; the README is text; a file with a NUL in it is not.
            #expect(try await disk.peek(folder.appending(path: "z_prime.png")) == "made-up figure bytes")
            let readme = try #require(try await disk.peek(folder.appending(path: "README.md")))
            #expect(readme.hasPrefix("---\ncapsid_kept: 1\n"))
            try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02]).write(to: folder.appending(path: "binary.png"))
            #expect(try await disk.peek(folder.appending(path: "binary.png")) == nil)
            // Nothing, and a file that isn't there.
            try Data().write(to: folder.appending(path: "empty.md"))
            #expect(try await disk.peek(folder.appending(path: "empty.md")) == nil)
            #expect(try await disk.peek(folder.appending(path: "nope.md")) == nil)
            // Never a file outside the Kept folder, nor one whose path only starts like its root's.
            let outside = scratch.appending(path: "Elsewhere.txt")
            try Data("not kept".utf8).write(to: outside)
            #expect(try await disk.peek(outside) == nil)
            let sibling = scratch.appending(path: "Kept2", directoryHint: .isDirectory)
            try files.createDirectory(at: sibling, withIntermediateDirectories: true)
            try Data("sibling".utf8).write(to: sibling.appending(path: "a.txt"))
            #expect(try await disk.peek(sibling.appending(path: "a.txt")) == nil)
            _ = root
        }
    }

    @Test func onlyTheFirstBytesAreReadAndACutInACharacterIsNotAReasonToRefuse() async throws {
        try await inScratch { _, _, disk in
            let folder = try await keep(disk)
            // "é" is two bytes: a limit of three cuts the second one in half.
            try Data("aéé".utf8).write(to: folder.appending(path: "accents.md"))
            #expect(try await disk.peek(folder.appending(path: "accents.md"), limit: 3) == "aé")
            #expect(try await disk.peek(folder.appending(path: "accents.md"), limit: 2) == "a")
            let long = String(repeating: "abcdefghij", count: 1_000)
            try Data(long.utf8).write(to: folder.appending(path: "long.md"))
            #expect(try await disk.peek(folder.appending(path: "long.md"))?.count == 2_000)
        }
    }
}
