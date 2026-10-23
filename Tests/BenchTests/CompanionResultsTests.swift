// CompanionResultsTests.swift — Results today in the home popover, on made-up
// sessions, lists and a fake reader: it starts from what is in memory, reads
// only the lists that are missing (a few, one at a time, in the typing gate's
// turn), only while the popover is open, and lets go when it closes. Nothing
// here reaches Claude Science.
import Foundation
import ImageIO
import Testing
@testable import Bench

private let noon = Date(timeIntervalSince1970: 1_792_000_000)

private func entry(_ name: String, _ mime: String = "image/png", hoursAgo: Double = 1, version: String? = nil) -> ArtifactEntry {
    ArtifactEntry(version: version ?? "ver-\(name)", artifact: nil, name: name, mime: mime, size: 2_000,
                  at: noon.addingTimeInterval(-hoursAgo * 3600))
}

private func session(_ n: Int, updatedAgo: TimeInterval = 600) -> SessionStatus {
    SessionStatus(id: "00000000-0000-4000-8000-0000000b\(String(format: "%03d", n))", projectID: "p", projectName: "Example project",
                  title: "Session \(n)", state: .finished, updatedAt: noon.addingTimeInterval(-updatedAgo - Double(n)))
}

/// The page, as the fake reader answers it: lists by frame, a counted record of every read.
@MainActor
private final class Page {
    var lists: [String: [ArtifactEntry]] = [:]
    var ready = true
    private(set) var reads: [ArtifactRead] = []
    private(set) var running = 0
    private(set) var mostRunning = 0
    /// A read waits here until released, when set.
    var holdLists = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var listReads: [String] { reads.compactMap { if case .list(let frame) = $0 { frame } else { nil } } }
    var thumbReads: [String] { reads.compactMap { if case .thumb(let version, _) = $0 { version } else { nil } } }

    func release() {
        holdLists = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func read(_ read: ArtifactRead) async -> ArtifactReadOutcome {
        reads.append(read)
        running += 1
        mostRunning = max(mostRunning, running)
        defer { running -= 1 }
        switch read {
        case .list(let frame):
            if holdLists { await withCheckedContinuation { waiting.append($0) } }
            if Task.isCancelled { return .cancelled }
            return lists[frame].map { .list($0) } ?? .unreadable
        case .thumb:
            return .bytes(Self.webp)
        default:
            return .unreadable
        }
    }

    /// Bytes that say WebP and nothing more: enough for the gate, not for a decoder.
    static let webp = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBPVP8 ".utf8) + Data(count: 24)
}

@MainActor
private struct Rig {
    /// What the app holds, which a test changes after the popover is made.
    @MainActor
    final class Memory {
        var candidates: [SessionStatus] = []
        var held: [String: [ArtifactEntry]] = [:]
        var pictures: Set<String> = []
        /// Reads that asked the typing gate for their turn.
        var gated = 0
    }

    let page = Page()
    let memory = Memory()
    let results: CompanionResults

    init(candidates: [SessionStatus] = [], held: [String: [ArtifactEntry]] = [:], readsLists: Bool = true) {
        let memory = memory, page = page
        memory.candidates = candidates
        memory.held = held
        let image = Self.picture
        results = CompanionResults(dependencies: CompanionResults.Dependencies(
            candidates: { memory.candidates }, held: { memory.held },
            picture: { memory.pictures.contains($0) ? image : nil },
            reader: .init(read: { await page.read($0) }, isReady: { page.ready }),
            gate: { body in memory.gated += 1; return await body() },
            readsLists: readsLists, now: { noon }, calendar: Self.calendar))
    }

    var gated: Int { memory.gated }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// A one-pixel picture, for "a picture already in memory".
    static let picture: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    func holdPicture(_ version: String) { memory.pictures.insert(version) }
    func setCandidates(_ sessions: [SessionStatus]) { memory.candidates = sessions }
}

@MainActor
struct CompanionResultsTests {
    @Test func theAppsPopoverReadsNothingFromThePageByDefault() {
        #expect(CompanionResults.readsListsWhenOpen == false, "the brief: only what the app already holds in memory")
        #expect(CompanionResults.Dependencies.live().readsLists == CompanionResults.readsListsWhenOpen)
    }

    @Test func nothingIsReadUntilThePopoverOpens() async {
        let rig = Rig(candidates: [session(1), session(2)])
        rig.page.lists = [session(1).id: [entry("a.png")]]
        await Task.yield()
        #expect(rig.page.reads.isEmpty && rig.results.entries.isEmpty && !rig.results.isOpen && rig.gated == 0)
    }

    @Test func itStartsFromWhatIsInMemoryAndReadsNothingThatIsThere() async {
        let one = session(1), two = session(2)
        let rig = Rig(candidates: [one, two], held: [one.id: [entry("volcano.png")], two.id: [entry("hits.csv", "text/csv")]])
        rig.results.open()
        await rig.results.settled()
        #expect(rig.results.entries.map(\.name) == ["hits.csv", "volcano.png"] || rig.results.entries.count == 2)
        #expect(rig.page.listReads.isEmpty, "both lists were in memory")
        #expect(!rig.results.partial, "every session made today has a list")
    }

    @Test func itReadsTheListsThatAreMissingAndOnlyThose() async {
        let one = session(1), two = session(2), three = session(3)
        let rig = Rig(candidates: [one, two, three], held: [one.id: [entry("a.png", hoursAgo: 3)]])
        rig.page.lists = [two.id: [entry("b.csv", "text/csv", hoursAgo: 2)], three.id: [entry("c.png", hoursAgo: 1)]]
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.listReads == [two.id, three.id])
        #expect(rig.results.listsRead == 2)
        #expect(rig.results.entries.map(\.name) == ["c.png", "b.csv", "a.png"], "newest first")
        #expect(!rig.results.partial)
    }

    @Test func onlyTodaysFilesCountAndAVersionCountsOnce() async {
        let one = session(1), two = session(2)
        let yesterday = entry("old.png", hoursAgo: 30)
        let undated = ArtifactEntry(version: "ver-undated", artifact: nil, name: "undated.png", mime: "image/png", size: 1, at: nil)
        let twice = entry("twice.png", version: "same")
        let rig = Rig(candidates: [one, two], held: [one.id: [twice, yesterday, undated]])
        rig.page.lists = [two.id: [entry("again.png", version: "same"), entry("fresh.csv", "text/csv")]]
        rig.results.open()
        await rig.results.settled()
        #expect(Set(rig.results.entries.map(\.version)) == ["same", "ver-fresh.csv"])
        #expect(rig.results.entries.count == 2, "yesterday's, the undated and the repeat don't count")
    }

    @Test func itReadsAtMostEightSessionsAndSaysThereAreMore() async {
        let sessions = (1...12).map { session($0) }
        let rig = Rig(candidates: sessions)
        for one in sessions { rig.page.lists[one.id] = [entry("f\(one.id.suffix(3)).csv", "text/csv")] }
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.listReads.count == CompanionResults.sessionLimit && CompanionResults.sessionLimit == 8)
        #expect(rig.results.partial, "four sessions made today were not looked at: the count says \"+\"")
        let section = CompanionResultsSection.make(entries: rig.results.entries, partial: rig.results.partial)
        #expect(section?.title == "Results today · 8+")
    }

    @Test func readsGoOneAtATimeEachInTheGatesTurn() async {
        let sessions = (1...5).map { session($0) }
        let rig = Rig(candidates: sessions)
        for one in sessions { rig.page.lists[one.id] = [entry("p\(one.id.suffix(3)).png", hoursAgo: 1)] }
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.mostRunning == 1)
        #expect(rig.gated == rig.page.reads.count && rig.gated >= 5, "every read, lists and pictures, asked the gate")
    }

    @Test func aPictureIsReadForAnImageTileAndNotForOtherFilesOrOnesAlreadyHeld() async {
        let one = session(1)
        let rig = Rig(candidates: [one], held: [one.id: [
            entry("held.png", hoursAgo: 1), entry("need.png", hoursAgo: 2), entry("table.csv", "text/csv", hoursAgo: 3),
            entry("paper.pdf", "application/pdf", hoursAgo: 4),
        ]])
        rig.holdPicture("ver-held.png")
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.thumbReads == ["ver-need.png"], "no thumbnail for a CSV or a PDF, none for a picture the app holds")
        #expect(rig.results.picture(for: "ver-held.png") != nil, "the held picture is shown as it is")
    }

    @Test func onlyTheFourTilesPicturesAreRead() async {
        let one = session(1)
        let images = (1...7).map { entry("image\($0).png", hoursAgo: Double($0)) }
        let rig = Rig(candidates: [one], held: [one.id: images])
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.thumbReads.count == CompanionResultsSection.tileLimit)
        #expect(rig.page.thumbReads == ["ver-image1.png", "ver-image2.png", "ver-image3.png", "ver-image4.png"])
    }

    @Test func closingStopsTheReadUnderWayAndLetsGoOfEverything() async {
        let sessions = (1...4).map { session($0) }
        let rig = Rig(candidates: sessions)
        for one in sessions { rig.page.lists[one.id] = [entry("x\(one.id.suffix(3)).csv", "text/csv")] }
        rig.page.holdLists = true
        rig.results.open()
        while rig.page.reads.isEmpty { await Task.yield() }
        rig.results.close()
        rig.page.release()
        await rig.results.settled()
        #expect(!rig.results.isOpen && rig.results.entries.isEmpty && !rig.results.partial)
        #expect(rig.page.listReads.count == 1, "the pass stopped at the read it was in: no list after the close")
        #expect(rig.results.listsRead == 0, "what answered after the close is dropped")
    }

    @Test func aClosedPopoverReadsNothingEvenAsTheLabChanges() async {
        let one = session(1)
        let rig = Rig(candidates: [one])
        rig.page.lists[one.id] = [entry("a.png")]
        rig.results.open()
        await rig.results.settled()
        rig.results.close()
        let reads = rig.page.reads.count
        rig.setCandidates([one, session(2)])
        rig.page.lists[session(2).id] = [entry("b.png")]
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(rig.page.reads.count == reads && rig.results.entries.isEmpty)
    }

    @Test func aPageThatIsNotUpIsNotAskedAndTheCountSaysItIsIncomplete() async {
        let one = session(1)
        let rig = Rig(candidates: [one], held: [:])
        rig.page.ready = false
        rig.page.lists[one.id] = [entry("a.png")]
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.reads.isEmpty, "the transfer queue doesn't start a read the page can't answer")
        #expect(rig.results.entries.isEmpty && rig.results.partial)
    }

    @Test func aReadThatFailsLeavesTheCountIncompleteNotWrong() async {
        let one = session(1), two = session(2)
        let rig = Rig(candidates: [one, two])
        rig.page.lists = [two.id: [entry("kept.csv", "text/csv")]]
        rig.results.open()
        await rig.results.settled()
        #expect(rig.results.entries.map(\.name) == ["kept.csv"] && rig.results.partial)
    }

    @Test func withReadsTurnedOffWhatIsInMemoryIsAllThereIs() async {
        let one = session(1), two = session(2)
        let rig = Rig(candidates: [one, two], held: [one.id: [entry("a.png")]], readsLists: false)
        rig.page.lists[two.id] = [entry("b.png")]
        rig.results.open()
        await rig.results.settled()
        #expect(rig.page.reads.isEmpty && rig.results.entries.map(\.name) == ["a.png"] && rig.results.partial)
    }

    @Test func noSessionMadeTodayIsNoSectionAtAll() async {
        let rig = Rig(candidates: [])
        rig.results.open()
        await rig.results.settled()
        #expect(rig.results.entries.isEmpty && !rig.results.partial)
        #expect(CompanionResultsSection.make(entries: rig.results.entries, partial: rig.results.partial) == nil)
    }
}
