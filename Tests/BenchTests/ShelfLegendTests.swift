// ShelfLegendTests.swift — the legend field under an item kept with data and
// code (Kept/ShelfLegend.swift, ShelfView.swift): what is typed in the last
// second before another item is chosen is saved, not dropped; saves go one at a
// time, each from the README the one before wrote; a README that can't be read
// turns the field off with a sentence; and a README changed in another app is
// never written over. The disk is the real `KeptDisk` on a scratch Kept folder.
import Foundation
import Testing
@testable import Bench

private let when = Date(timeIntervalSince1970: 1_792_674_720)
private let figure = Data("made-up figure bytes".utf8)

/// The disk's calls, kept back while `holding` and started late, in order.
private final class Held: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [KeptDisk.Work] = []
    private var hold = false

    func holding(_ on: Bool) {
        let release: [KeptDisk.Work] = lock.withLock {
            hold = on
            guard !on else { return [] }
            defer { kept = [] }
            return kept
        }
        for work in release { KeptDisk.runOnDisk(work) }
    }

    var count: Int { lock.withLock { kept.count } }

    func run(_ work: @escaping KeptDisk.Work) {
        let held = lock.withLock { () -> Bool in
            guard hold else { return false }
            kept.append(work)
            return true
        }
        if !held { KeptDisk.runOnDisk(work) }
    }
}

@MainActor
private final class Saves {
    private(set) var count = 0
    func noted() { count += 1 }
}

@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw CancellationError()
}

@MainActor
struct ShelfLegendTests {
    /// A scratch Kept folder with one kept folder in it, a disk over it, and the editor on it.
    private func editor(delay: Duration = .seconds(60), legend: String = "", held: Held = Held(),
                        _ body: (ShelfLegendEditor, URL, Saves, KeptDisk) async throws -> Void) async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-legend-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let disk = KeptDisk(root: { root }, run: { held.run($0) })
        let destination = try await disk.prepare(collection: "Assay development", name: "Z prime by plate", at: when)
        try await disk.write(figure, to: "z_prime.png", in: destination)
        let record = KeptRecord(
            name: "Z prime by plate", keptAt: when, projectID: "p", projectName: "Assay development", sessionID: "s",
            sessionTitle: "Plate reader QC",
            figure: KeptFile(path: "z_prime.png", role: .figure, artifact: "a", version: "v-1", index: 1, of: nil,
                             sha256: KeptDisk.sha256(of: figure), bytes: figure.count),
            files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
        let text = KeptText(legend: legend, claudeSaid: "Z′ is above 0.5 for every plate.", attribution: "From Claude’s answer.", origin: "")
        let folder = try await disk.finish(destination, readme: KeptReadme.render(record, text: text))
        let saves = Saves()
        let editor = ShelfLegendEditor(folder: folder, disk: disk, delay: delay, saved: { saves.noted() })
        try await body(editor, folder, saves, disk)
    }

    private func legend(in folder: URL) throws -> String? {
        KeptReadme.parse(try String(contentsOf: folder.appending(path: "README.md", directoryHint: .notDirectory), encoding: .utf8))?.text.legend
    }

    // MARK: Leaving the field

    /// The wait is a minute here, so only leaving can have saved it. This is the case the review found: a legend typed
    /// and then another item chosen inside the second, when leaving cancelled the pending save and the text was gone.
    @Test func aLegendTypedJustBeforeMovingToAnotherItemIsSaved() async throws {
        try await editor { editor, folder, saves, _ in
            await editor.load()
            #expect(editor.canEdit && editor.problem == nil)
            editor.legend = "Z′ above 0.5; plate 3 re-run."
            #expect(editor.hasUnsavedText)
            let before = try legend(in: folder)
            #expect(before == "", "nothing is written yet")
            await editor.flush().value
            let after = try legend(in: folder)
            #expect(after == "Z′ above 0.5; plate 3 re-run.")
            #expect(!editor.hasUnsavedText && editor.problem == nil && !editor.changedOutside)
            #expect(saves.count == 1, "the shelf is told once")
        }
    }

    @Test func theWaitStillSavesAfterTheLastKeystroke() async throws {
        try await editor(delay: .milliseconds(10)) { editor, folder, saves, _ in
            await editor.load()
            editor.legend = "Z′ above"
            editor.legend = "Z′ above 0.5"
            try await until("the save") { saves.count == 1 }
            #expect(try legend(in: folder) == "Z′ above 0.5", "the last text, once")
            #expect(!editor.hasUnsavedText)
        }
    }

    @Test func leavingWithNothingNewWritesNothing() async throws {
        try await editor(legend: "Kept as it was.") { editor, folder, saves, _ in
            await editor.load()
            #expect(editor.legend == "Kept as it was." && !editor.hasUnsavedText)
            await editor.flush().value
            // Typed and put back: the same text is not a change.
            editor.legend = "Kept as it was. Plus"
            editor.legend = "Kept as it was."
            #expect(!editor.hasUnsavedText)
            await editor.flush().value
            #expect(saves.count == 0)
            let kept = try legend(in: folder)
            #expect(kept == "Kept as it was.")
        }
    }

    @Test func leavingAfterTheWaitHasSavedAlreadyDoesNotWriteAgain() async throws {
        try await editor(delay: .milliseconds(10)) { editor, _, saves, _ in
            await editor.load()
            editor.legend = "Once."
            try await until("the save") { saves.count == 1 }
            await editor.flush().value
            #expect(saves.count == 1 && !editor.changedOutside && editor.problem == nil)
        }
    }

    @Test func aSaveUnderWayAndALaterLeaveGoOneAfterTheOtherFromTheREADMETheFirstWrote() async throws {
        let held = Held()
        try await editor(held: held) { editor, folder, saves, _ in
            await editor.load()
            editor.legend = "First."
            held.holding(true)
            let first = Task { await editor.save() }
            try await until("the first save reaches the disk") { held.count == 1 }
            // Typed on while the first is out, and then the item is left.
            editor.legend = "First. Second."
            let second = editor.flush()
            held.holding(false)
            await first.value
            await second.value
            #expect(try legend(in: folder) == "First. Second.")
            #expect(!editor.changedOutside && editor.problem == nil, "the second started from what the first wrote")
            #expect(saves.count == 2)
        }
    }

    // MARK: A README that can't be read

    @Test func aReadmeThatCantBeReadTurnsTheFieldOffAndSaysWhy() async throws {
        try await editor { editor, folder, saves, _ in
            try FileManager.default.removeItem(at: folder.appending(path: "README.md", directoryHint: .notDirectory))
            await editor.load()
            #expect(!editor.canEdit)
            #expect(editor.problem == "Couldn\u{2019}t read the README, so the legend can\u{2019}t be edited here. There is no README.md in this folder.")
            // Whatever reaches it anyway is not kept for a save that could never happen, and writes no file.
            editor.legend = "typed anyway"
            #expect(!editor.hasUnsavedText)
            await editor.flush().value
            await editor.save()
            #expect(saves.count == 0)
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "README.md", directoryHint: .notDirectory).path))
        }
    }

    @Test func aReadmeThatIsNotCapsidsIsTreatedTheSameAndComesBackWhenItIs() async throws {
        try await editor(legend: "Mine.") { editor, folder, _, _ in
            let url = folder.appending(path: "README.md", directoryHint: .notDirectory)
            let original = try Data(contentsOf: url)
            try Data("# Not ours\n".utf8).write(to: url)
            await editor.load()
            #expect(!editor.canEdit)
            #expect(editor.problem == "Couldn\u{2019}t read the README, so the legend can\u{2019}t be edited here. This isn't a folder Capsid keeps.")
            // Put right, and read again ("Use Theirs" does this): the field is on, the sentence gone.
            try original.write(to: url)
            await editor.load()
            #expect(editor.canEdit && editor.problem == nil && editor.legend == "Mine.")
        }
    }

    @Test func aFolderThatDoesNotAnswerTurnsTheFieldOffWithTheDisksOwnSentence() async throws {
        // A disk whose calls never come back, and whose limit has run out at once.
        let silent = KeptDisk(root: { URL(fileURLWithPath: "/made-up/Kept", isDirectory: true) }, lookLimit: .milliseconds(1),
                              wait: { _ in }, run: { _ in })
        let editor = ShelfLegendEditor(folder: URL(fileURLWithPath: "/made-up/Kept/Assay development/z", isDirectory: true),
                                       disk: silent, saved: {})
        await editor.load()
        #expect(!editor.canEdit)
        #expect(editor.problem == ShelfLegendEditor.unreadable(KeptDiskError.lookDidNotRespond))
        #expect(editor.problem == "Couldn\u{2019}t read the README, so the legend can\u{2019}t be edited here. The folder didn't respond.")
    }

    // MARK: A README changed in another app

    @Test func aReadmeChangedElsewhereIsNeverWrittenOverUntilTheWriterSaysSo() async throws {
        try await editor(legend: "Mine.") { editor, folder, saves, _ in
            await editor.load()
            let url = folder.appending(path: "README.md", directoryHint: .notDirectory)
            let elsewhere = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\nMine.\n", with: "\nMine, edited in an editor.\n")
            try Data(elsewhere.utf8).write(to: url)
            editor.legend = "Mine, typed here."
            await editor.flush().value
            #expect(editor.changedOutside)
            #expect(try String(contentsOf: url, encoding: .utf8) == elsewhere, "the other app's text is untouched")
            #expect(saves.count == 0)
            // Use Mine.
            await editor.useMine()
            #expect(!editor.changedOutside && editor.problem == nil)
            #expect(try legend(in: folder) == "Mine, typed here.")
            #expect(saves.count == 1)
        }
    }

    @Test func useTheirsReadsTheREADMEAgain() async throws {
        try await editor(legend: "Mine.") { editor, folder, _, _ in
            await editor.load()
            let url = folder.appending(path: "README.md", directoryHint: .notDirectory)
            let elsewhere = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\nMine.\n", with: "\nTheirs.\n")
            try Data(elsewhere.utf8).write(to: url)
            editor.legend = "Mine, typed here."
            await editor.flush().value
            #expect(editor.changedOutside)
            await editor.load()
            #expect(editor.legend == "Theirs." && !editor.changedOutside && editor.canEdit)
            #expect(!editor.hasUnsavedText)
        }
    }

    // MARK: The view

    /// The wiring the editor's tests can't see: leaving the field flushes it (it used to cancel the save), and the field is
    /// off when the README couldn't be read.
    @Test func theFieldFlushesWhenItLeavesAndIsOffWhenTheReadmeCouldNotBeRead() throws {
        let kept = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Bench/Kept", directoryHint: .isDirectory)
        let view = try String(contentsOf: kept.appending(path: "ShelfView.swift", directoryHint: .notDirectory), encoding: .utf8)
        let extras = try #require(view.range(of: "struct ShelfExtras: View"))
        let body = String(view[extras.lowerBound...].prefix(upTo: view.range(of: "// MARK: Pieces")!.lowerBound))
        #expect(body.contains(".onDisappear { editor.flush() }"))
        #expect(!body.contains("saveTask"), "the pending save is no longer cancelled")
        #expect(body.contains(".disabled(!editor.canEdit)"))
        #expect(body.contains("@StateObject private var editor: ShelfLegendEditor"))
        // The card makes one editor for each item.
        #expect(view.contains("ShelfExtras(item: item, model: model)\n                        .id(item.id)"))
    }
}
