// ShelfFreshnessTests.swift — whether a Shelf item is still the newest of what
// it came from, on made-up records and made-up answers: that a newer figure or
// newer data marks the item and says so in the exact words, that anything the
// reads could not settle shows no mark, that a figure Claude Science no longer
// lists is called gone, and how a read's result becomes an answer. Nothing here
// touches the disk or the network.
import Foundation
import Testing
@testable import Bench

private let at = Date(timeIntervalSince1970: 1_792_674_720)

private func version(_ v: String, _ n: Int) -> ArtifactVersion {
    ArtifactVersion(v: v, n: n, frame: nil, mime: nil, size: 0, at: nil, parent: nil)
}

private func list(_ pairs: (String, Int)...) -> VersionsAnswer {
    .versions(pairs.map { version($0.0, $0.1) })
}

private func file(_ path: String, _ role: KeptRole, artifact: String?, version: String?, index: Int? = nil) -> KeptFile {
    KeptFile(path: path, role: role, artifact: artifact, version: version, index: index, of: nil,
             sha256: nil, bytes: 10)
}

private func record(figure: KeptFile? = nil, files: [KeptFile] = []) -> KeptRecord {
    KeptRecord(
        name: "Fig 2B", keptAt: at, projectID: "proj_1", projectName: "Assay", sessionID: "frame_1",
        sessionTitle: "QC",
        figure: figure ?? file("z_prime.png", .figure, artifact: "art_1", version: "ver_3", index: 3),
        files: files, missing: [], claudeScience: "0.1.70", capsid: "1.0")
}

private let csv = file("data/z_prime_by_plate.csv", .data, artifact: "art_2", version: "ver_9")

@Suite struct ShelfFreshnessTests {
    @Test func newerFigureIsStaleWithTheExactSentence() {
        let verdict = ShelfFreshnessRules.verdict(
            for: record(), answers: ["art_1": list(("ver_1", 1), ("ver_3", 3), ("ver_4", 4))])
        guard case .stale(let stale) = verdict else { Issue.record("expected stale"); return }
        #expect(stale.newerFigure?.v == "ver_4")
        #expect(stale.keptNumber == 3)
        #expect(stale.inputs.isEmpty)
        #expect(verdict.isOutOfDate)
        #expect(verdict.sentences == ["A newer version of this figure exists (version 3 \u{2192} 4)."])
        #expect(ShelfFreshnessRules.shortLabel(verdict) == "Out of date")
    }

    @Test func sameVersionIsCurrent() {
        let verdict = ShelfFreshnessRules.verdict(for: record(), answers: ["art_1": list(("ver_1", 1), ("ver_3", 3))])
        #expect(verdict == .current)
        #expect(verdict.sentences.isEmpty)
        #expect(ShelfFreshnessRules.shortLabel(verdict) == nil)
    }

    @Test func keptIsNewestWithOlderOnesBeforeIt() {
        let verdict = ShelfFreshnessRules.verdict(
            for: record(), answers: ["art_1": list(("ver_1", 1), ("ver_2", 2), ("ver_3", 3))])
        #expect(verdict == .current)
        #expect(!verdict.isOutOfDate)
    }

    @Test func tieInNumbersTakesTheLastAndIsNotNewer() {
        // Two versions numbered 3: the kept one is not older than the last.
        let current = ShelfFreshnessRules.verdict(for: record(), answers: ["art_1": list(("ver_3", 3), ("ver_x", 3))])
        #expect(current == .current)
        // Two versions numbered 4 after the kept 3: the last of them is the newest.
        let stale = ShelfFreshnessRules.verdict(
            for: record(), answers: ["art_1": list(("ver_3", 3), ("ver_a", 4), ("ver_b", 4))])
        guard case .stale(let s) = stale else { Issue.record("expected stale"); return }
        #expect(s.newerFigure?.v == "ver_b")
    }

    @Test func figureNotFoundIsGoneWithTheExactSentence() {
        let verdict = ShelfFreshnessRules.verdict(for: record(), answers: ["art_1": .gone])
        #expect(verdict == .gone)
        #expect(!verdict.isOutOfDate)
        #expect(verdict.sentences == ["This version isn\u{2019}t in Claude Science any more."])
        #expect(ShelfFreshnessRules.shortLabel(verdict) == "Not in Claude Science")
    }

    @Test func gonePrecedesNewerInputs() {
        let r = record(files: [csv])
        let verdict = ShelfFreshnessRules.verdict(
            for: r, answers: ["art_1": .gone, "art_2": list(("ver_9", 3), ("ver_10", 5))])
        #expect(verdict == .gone)
    }

    @Test func listWithoutTheKeptVersionIsGone() {
        let verdict = ShelfFreshnessRules.verdict(for: record(), answers: ["art_1": list(("ver_8", 1), ("ver_9", 2))])
        #expect(verdict == .gone)
    }

    @Test func unreachableFigureWithNoInputsIsUnknown() {
        let verdict = ShelfFreshnessRules.verdict(for: record(), answers: ["art_1": .unknown])
        #expect(verdict == .unknown)
        #expect(verdict.sentences.isEmpty)
        #expect(ShelfFreshnessRules.shortLabel(verdict) == nil)
        #expect(ShelfFreshnessRules.verdict(for: record(), answers: [:]) == .unknown)
    }

    @Test func unreachableFigureButNewerInputIsStaleWithOnlyTheInputSentence() {
        let r = record(files: [csv])
        let verdict = ShelfFreshnessRules.verdict(
            for: r, answers: ["art_1": .unknown, "art_2": list(("ver_9", 3), ("ver_10", 5))])
        guard case .stale(let stale) = verdict else { Issue.record("expected stale"); return }
        #expect(stale.newerFigure == nil)
        #expect(stale.inputs == [InputChange(name: "z_prime_by_plate.csv", kept: 3, newest: 5)])
        #expect(verdict.sentences == [
            "The data behind this figure changed after you kept it (z_prime_by_plate.csv, version 3 \u{2192} 5).",
        ])
    }

    @Test func inputWhoseKeptVersionIsMissingFallsBackOnItsIndex() {
        let withIndex = file("data/z_prime_by_plate.csv", .data, artifact: "art_2", version: "ver_9", index: 3)
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [withIndex]),
            answers: ["art_1": list(("ver_3", 3)), "art_2": list(("ver_1", 1), ("ver_10", 5))])
        guard case .stale(let stale) = verdict else { Issue.record("expected stale"); return }
        #expect(stale.inputs == [InputChange(name: "z_prime_by_plate.csv", kept: 3, newest: 5)])
    }

    @Test func inputWhoseKeptVersionIsMissingWithoutAnIndexIsNeverAnAlarm() {
        // Nothing else is known either, so the whole verdict stays unknown.
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv]), answers: ["art_1": .unknown, "art_2": list(("ver_1", 1), ("ver_10", 5))])
        #expect(verdict == .unknown)
    }

    @Test func figureAndInputBothNewerPutTheFigureSentenceFirst() {
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv]),
            answers: ["art_1": list(("ver_3", 3), ("ver_4", 4)), "art_2": list(("ver_9", 3), ("ver_10", 5))])
        #expect(verdict.sentences == [
            "A newer version of this figure exists (version 3 \u{2192} 4).",
            "The data behind this figure changed after you kept it (z_prime_by_plate.csv, version 3 \u{2192} 5).",
        ])
    }

    @Test func twoInputsChangedSaysOneMoreFile() {
        let second = file("data/plates.csv", .input, artifact: "art_5", version: "ver_20")
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv, second]),
            answers: ["art_1": list(("ver_3", 3)),
                      "art_2": list(("ver_9", 3), ("ver_10", 5)),
                      "art_5": list(("ver_20", 1), ("ver_21", 2))])
        #expect(verdict.sentences == [
            "The data behind this figure changed after you kept it (z_prime_by_plate.csv, version 3 \u{2192} 5, and 1 more file).",
        ])
    }

    @Test func threeInputsChangedSaysTwoMoreFiles() {
        let second = file("data/plates.csv", .input, artifact: "art_5", version: "ver_20")
        let third = file("data/controls.csv", .data, artifact: "art_6", version: "ver_30")
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv, second, third]),
            answers: ["art_2": list(("ver_9", 3), ("ver_10", 5)),
                      "art_5": list(("ver_20", 1), ("ver_21", 2)),
                      "art_6": list(("ver_30", 2), ("ver_31", 3))])
        #expect(verdict.sentences == [
            "The data behind this figure changed after you kept it (z_prime_by_plate.csv, version 3 \u{2192} 5, and 2 more files).",
        ])
    }

    @Test func inputThatWentAwayIsIgnored() {
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv]), answers: ["art_1": list(("ver_3", 3)), "art_2": .gone])
        #expect(verdict == .current)
    }

    @Test func currentInputKeepsAnUnreadableFigureCurrent() {
        let verdict = ShelfFreshnessRules.verdict(
            for: record(files: [csv]), answers: ["art_1": .unknown, "art_2": list(("ver_8", 2), ("ver_9", 3))])
        #expect(verdict == .current)
    }

    @Test func recordWithNoIdsIsUnknown() {
        let bare = record(figure: file("z_prime.png", .figure, artifact: nil, version: nil))
        #expect(ShelfFreshnessRules.verdict(for: bare, answers: [:]) == .unknown)
        let noVersion = record(figure: file("z_prime.png", .figure, artifact: "art_1", version: nil))
        #expect(ShelfFreshnessRules.verdict(for: noVersion, answers: ["art_1": list(("ver_3", 3), ("ver_4", 4))]) == .unknown)
        #expect(ShelfFreshnessRules.artifacts(of: noVersion).isEmpty)
    }

    @Test func inputsSkipCodeLegendAndFilesWithoutIds() {
        let code = file("code/plot.py", .code, artifact: "art_3", version: "ver_7")
        let legend = file("legend.md", .legend, artifact: "art_4", version: "ver_8")
        let noVersion = file("data/a.csv", .data, artifact: "art_7", version: nil)
        let noArtifact = file("data/b.csv", .input, artifact: nil, version: "ver_40")
        let input = file("data/c.csv", .input, artifact: "art_8", version: "ver_50")
        let dup = file("data/c_copy.csv", .data, artifact: "art_8", version: "ver_50")
        let r = record(files: [code, legend, noVersion, noArtifact, csv, input, dup])
        #expect(ShelfFreshnessRules.inputs(of: r).map(\.path) == ["data/z_prime_by_plate.csv", "data/c.csv"])
    }

    @Test func artifactsAreDedupedFigureFirst() {
        let sameAsFigure = file("data/x.csv", .data, artifact: "art_1", version: "ver_70")
        let again = file("data/y.csv", .data, artifact: "art_2", version: "ver_71")
        let r = record(files: [csv, sameAsFigure, again])
        #expect(ShelfFreshnessRules.artifacts(of: r) == ["art_1", "art_2"])
    }

    @Test func versionsAnswerMapsEveryResult() {
        let one = [version("ver_1", 1)]
        #expect(VersionsAnswer.from(.answered(.versions(one))) == .versions(one))
        #expect(VersionsAnswer.from(.answered(.missing)) == .gone)
        #expect(VersionsAnswer.from(.cancelled) == nil)
        #expect(VersionsAnswer.from(.answered(.cancelled)) == nil)
        #expect(VersionsAnswer.from(.timedOut) == .unknown)
        #expect(VersionsAnswer.from(.notReady) == .unknown)
        #expect(VersionsAnswer.from(.answered(.unreadable)) == .unknown)
        #expect(VersionsAnswer.from(.answered(.lost)) == .unknown)
        #expect(VersionsAnswer.from(.answered(.tooBig)) == .unknown)
        #expect(VersionsAnswer.from(.answered(.binary)) == .unknown)
        #expect(VersionsAnswer.from(.answered(.bytes(Data()))) == .unknown)
        #expect(VersionsAnswer.from(.answered(.text("x", truncated: false))) == .unknown)
        #expect(VersionsAnswer.from(.answered(.list([]))) == .unknown)
    }

    @Test func countsOnlyTheOutOfDate() {
        let stale = ShelfFreshness.stale(.init(newerFigure: nil, keptNumber: nil,
                                               inputs: [InputChange(name: "a.csv", kept: 1, newest: 2)]))
        #expect(ShelfFreshnessRules.countOutOfDate([stale, .current, .gone, .unknown, stale]) == 2)
        #expect(ShelfFreshnessRules.countOutOfDate([]) == 0)
    }

    @Test func newerFigureWithoutAKeptNumberDropsTheArrow() {
        let verdict = ShelfFreshness.stale(.init(newerFigure: version("ver_4", 4), keptNumber: nil, inputs: []))
        #expect(verdict.sentences == ["A newer version of this figure exists."])
    }
}
