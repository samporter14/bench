// KeepSheetSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names
// a folder, draws the Keep sheet (on the demo's made-up reads, after they
// have come in) into it as PNGs, light and dark, so it can be looked at
// without opening a window: ready, reading, a name already kept, a partial
// keep, a keep with a checksum that doesn't match, a failed read, the folder
// being put in place (no count, Cancel off), and a ready
// sheet on a short screen, where its body scrolls. Without the variable the
// test does nothing. It draws through an `NSHostingView` that is never put in
// a window, as the update popover's snapshot does, so a window-modal sheet's
// own material is absent (the sheet paints its own white or raised grey).
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct KeepSheetSnapshotTests {
    @Test func theKeepSheetIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-snapshot-\(UUID().uuidString)", isDirectory: true)
        let started = Date()
        defer { try? FileManager.default.removeItem(at: root) }

        // Ready, and partial after a keep whose data download timed out.
        for (name, failing) in [("keep-sheet", false), ("keep-sheet-partial", true)] {
            let model = KeptDemo.sheetModel(root: root, failingData: failing)
            model.open()
            try await settle(model)
            if failing {
                model.keep()
                for _ in 0..<100 {
                    if case .partial = model.phase { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            try await draw(model, name: name, to: directory)
        }

        // Reading: the first read is still out.
        let reading = Self.model(root: root, corruptFigure: false, failFirstRead: false, stall: true)
        reading.open()
        try await draw(reading, name: "keep-sheet-reading", to: directory)
        reading.cancel()

        // A name that is already kept in the collection: the folder will be dated.
        await KeptDemo.seed(KeptDisk(root: { root }))
        let taken = KeptDemo.sheetModel(root: root)
        taken.open()
        try await settle(taken)
        taken.setCollection("Paper draft")
        taken.setName("Fig 2B \u{00B7} Z\u{2032} by plate")
        for _ in 0..<100 where !taken.nameTaken { try await Task.sleep(for: .milliseconds(50)) }
        try await draw(taken, name: "keep-sheet-taken", to: directory)

        // A short screen: the body scrolls, the footer stays.
        let short = KeptDemo.sheetModel(root: root)
        short.open()
        try await settle(short)
        try await draw(short, maxHeight: 540, name: "keep-sheet-short", to: directory)

        // Kept, but a file's bytes don't match Claude Science's checksum: the sheet stays.
        let mismatched = Self.model(root: root, corruptFigure: true, failFirstRead: false)
        mismatched.open()
        try await settle(mismatched)
        mismatched.keep()
        for _ in 0..<100 {
            if case .kept = mismatched.phase { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await draw(mismatched, name: "keep-sheet-checksum", to: directory)

        // The folder is being put in place: "Finishing…", and Cancel is off.
        let hold = FinishHold()
        let finishing = Self.model(root: root, corruptFigure: false, failFirstRead: false, hold: hold)
        finishing.open()
        try await settle(finishing)
        finishing.keep()
        for _ in 0..<100 where !finishing.isFinishing { try await Task.sleep(for: .milliseconds(50)) }
        try await draw(finishing, name: "keep-sheet-finishing", to: directory)
        hold.release()
        for _ in 0..<100 {
            if case .kept = finishing.phase { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        // The first read failed: Cancel and Try Again.
        let failed = Self.model(root: root, corruptFigure: false, failFirstRead: true)
        failed.open()
        for _ in 0..<100 {
            if case .failed = failed.phase { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await draw(failed, name: "keep-sheet-failed", to: directory)

        // The preferences daemon writes its files a moment after the keeps above.
        try await Task.sleep(for: .seconds(2))
        Self.tidyPreferences(since: started)
    }

    /// The sheets' defaults suites (the demo's and this file's) are random names
    /// that keeping writes to; their plists made since the test began are removed.
    private static func tidyPreferences(since started: Date) {
        let preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
        for name in names where name.hasSuffix(".plist") && (name.hasPrefix("kept-demo-") || name.hasPrefix("keep-snapshot-")) {
            let url = preferences.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified >= started { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Drawing

    private func settle(_ model: KeepModel) async throws {
        for _ in 0..<100 where model.phase == .reading || model.readingProvenance {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The sheet at its own size, light and dark.
    private func draw(_ model: KeepModel, maxHeight: CGFloat = 740, name: String, to directory: URL) async throws {
        // The cap is given, so the display this runs on doesn't decide it.
        let sheet = KeepSheet(model: model, dismiss: {}, maxHeight: maxHeight)
        for dark in [false, true] {
            let host = NSHostingView(rootView: sheet)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: CGSize(width: KeepSheet.width, height: 900))
            host.layoutSubtreeIfNeeded()
            // Let the scroll view's geometry and the thumbnails land.
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    // MARK: Made-up reads for the states the demo doesn't have

    private static let session = SessionStatus(
        id: "00000000-0000-4000-8000-0000000000e1", projectID: "snapshot-assay", projectName: "Assay development",
        title: "Plate reader QC", state: .finished, updatedAt: Date().addingTimeInterval(-50 * 60), startedAt: nil)
    private static let artifact = "bbbbbbbb-0000-4000-8000-000000000011"
    private static let versionIDs = (1...4).map { "aaaaaaaa-0000-4000-8000-00000000001\($0)" }
    private static let inputID = "cccccccc-0000-4000-8000-000000000011"

    /// A sheet whose figure's checksum is stale, whose first read times out, or
    /// whose first read never comes back.
    private static func model(root: URL, corruptFigure: Bool, failFirstRead: Bool, stall: Bool = false,
                              hold: FinishHold? = nil) -> KeepModel {
        let figures = (0..<4).map { KeptDemo.chart(variant: $0) }
        let table = KeptDemo.csv()
        let thumbnails = ShelfThumbnails()
        for (index, v) in versionIDs.enumerated() { thumbnails.receive(figures[index], for: v) }
        let at = { (minutesAgo: Double) in Date().addingTimeInterval(-minutesAgo * 60) }
        let defaults = ScratchDefaults.make(prefix: "keep-snapshot").defaults
        let dependencies = KeepDependencies(
            read: { read in
                switch read {
                case .facts(let v):
                    if stall { try? await Task.sleep(for: .seconds(60)) }
                    if failFirstRead { return .timedOut }
                    if v == inputID {
                        return .answered(.facts(ArtifactFacts(v: v, a: "dddddddd-0000-4000-8000-000000000011", n: 1, name: "z_prime_by_plate.csv",
                                                              mime: "text/csv", size: table.count, at: at(62), sha: KeptDisk.sha256(of: table),
                                                              isUpload: false, code: nil, codeCut: false, environment: nil)))
                    }
                    guard let index = versionIDs.firstIndex(of: v) else { return .answered(.missing) }
                    let sha = corruptFigure ? KeptDisk.sha256(of: Data("an older file".utf8)) : KeptDisk.sha256(of: figures[index])
                    return .answered(.facts(ArtifactFacts(v: v, a: artifact, n: index + 1, name: "z_prime.png", mime: "image/png",
                                                          size: figures[index].count, at: at(Double(60 - index * 3)), sha: sha,
                                                          isUpload: false, code: nil, codeCut: false, environment: nil)))
                case .versions:
                    return .answered(.versions(versionIDs.enumerated().map { index, v in
                        ArtifactVersion(v: v, n: index + 1, frame: session.id, mime: "image/png", size: figures[index].count,
                                        at: at(Double(60 - index * 3)), parent: nil)
                    }))
                case .lineage(let v):
                    return .answered(.lineage(ArtifactLineage(
                        v: v, code: "plates = pd.read_csv(\"{{artifact:\(inputID)}}\")\n", codeCut: false, description: nil, language: "python",
                        pending: false, unavailableModel: nil, unavailableReason: nil, hasCells: true, hasEnvironment: true,
                        mappingStatus: "complete",
                        inputs: [LineageInput(v: inputID, a: "dddddddd-0000-4000-8000-000000000011", name: "z_prime_by_plate.csv",
                                              file: nil, how: "runtime", inferred: false)])))
                case .download(let v):
                    if v == inputID { return .answered(.bytes(table)) }
                    if let index = versionIDs.firstIndex(of: v) { return .answered(.bytes(figures[index])) }
                    return .answered(.missing)
                case .thumb, .text, .list:
                    return .answered(.unreadable)
                }
            },
            showing: { _, _, _ in
                .found(ShowingMessage(i: 41, at: at(50), text: "All plates passed except plate 7, which has an edge effect in column 12.",
                                      how: .image, v: versionIDs[2]))
            },
            lastAnswer: { _ in nil },
            thumbnails: thumbnails,
            disk: hold.map { hold in KeptDisk(root: { root }, run: { hold.run($0) }) } ?? KeptDisk(root: { root }),
            defaults: defaults,
            root: { root },
            // The last thing asked before the folder is put in place: with a hold, the disk stops answering then.
            scienceVersion: {
                hold?.arm()
                return "0.1.70"
            },
            capsidVersion: "1.0",
            now: { Date() },
            didKeep: { _ in })
        let entry = ArtifactEntry(version: versionIDs[3], artifact: artifact, name: "z_prime.png", mime: "image/png",
                                  size: figures[3].count, at: at(51))
        return KeepModel(subject: KeepSubject(session: session, entry: entry), dependencies: dependencies)
    }
}

/// A disk that stops answering once armed, as a share does while the call that
/// puts the folder in place is out: the calls after `arm` wait for `release`.
private final class FinishHold: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var held: [KeptDisk.Work] = []

    func arm() { lock.withLock { armed = true } }

    func run(_ work: @escaping KeptDisk.Work) {
        if lock.withLock({ armed }) { lock.withLock { held.append(work) } } else { work() }
    }

    func release() {
        let pending = lock.withLock { () -> [KeptDisk.Work] in
            armed = false
            let all = held
            held = []
            return all
        }
        for work in pending { work() }
    }
}
