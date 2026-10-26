// KeepPlanTests.swift — the Keep sheet's decisions (Kept/KeepPlan.swift) on
// made-up versions, provenance and answers: which version is pre-selected,
// what each row says and whether it can be ticked, what gets copied, the
// sentences, and what the README records.
import Foundation
import Testing
@testable import Bench

private enum Made {
    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000aa", projectID: "p-1", projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let v1 = "aaaaaaaa-0000-4000-8000-000000000001"
    static let v2 = "aaaaaaaa-0000-4000-8000-000000000002"
    static let v3 = "aaaaaaaa-0000-4000-8000-000000000003"
    static let v4 = "aaaaaaaa-0000-4000-8000-000000000004"
    static let artifact = "bbbbbbbb-0000-4000-8000-000000000001"
    static let input = "cccccccc-0000-4000-8000-000000000001"
    static let inputArtifact = "dddddddd-0000-4000-8000-000000000001"
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    static let entry = ArtifactEntry(version: v4, artifact: artifact, name: "z_prime.png", mime: "image/png", size: 85_000, at: at(11))
    static let subject = KeepSubject(session: session, entry: entry)

    static let versions = [
        ArtifactVersion(v: v1, n: 1, frame: nil, mime: "image/png", size: 81_920, at: at(1), parent: nil),
        ArtifactVersion(v: v2, n: 2, frame: nil, mime: "image/png", size: 83_456, at: at(4), parent: v1),
        ArtifactVersion(v: v3, n: 3, frame: nil, mime: "image/png", size: 86_016, at: at(9), parent: v2),
        ArtifactVersion(v: v4, n: 4, frame: nil, mime: "image/png", size: 85_000, at: at(11), parent: v3),
    ]

    static func facts(_ v: String, n: Int, name: String = "z_prime.png", size: Int = 86_016, sha: String? = String(repeating: "ab", count: 32),
                      upload: Bool = false) -> ArtifactFacts {
        ArtifactFacts(v: v, a: artifact, n: n, name: name, mime: "image/png", size: size, at: at(Double(n)), sha: sha,
                      isUpload: upload, code: nil, codeCut: false, environment: nil)
    }

    static let showing = ShowingMessage(i: 41, at: at(12), text: "All plates passed except plate 7, which has an edge effect in column 12. It's flagged and left out of the cleaned table.", how: .image, v: v3)

    static func lineage(inputs: [LineageInput], code: String? = "import pandas as pd\nplates = pd.read_csv(\"{{artifact:\(input)}}\")\n",
                        pending: Bool = false, mapping: String? = "complete", language: String? = "python",
                        reason: String? = nil, hasCells: Bool = true) -> ArtifactLineage {
        ArtifactLineage(v: v3, code: code, codeCut: false, description: nil, language: language, pending: pending,
                        unavailableModel: reason == nil ? nil : "the lineage model", unavailableReason: reason, hasCells: hasCells,
                        hasEnvironment: true, mappingStatus: mapping, inputs: inputs)
    }

    static let savedInput = LineageInput(v: input, a: inputArtifact, name: "z_prime_by_plate.csv", file: nil, how: "runtime", inferred: false)
    static let inferredInput = LineageInput(v: input, a: inputArtifact, name: "z_prime_by_plate.csv", file: nil, how: "ast_only", inferred: true)
    static let unsavedInput = LineageInput(v: nil, a: nil, name: nil, file: "raw/plate7.xlsx", how: "runtime", inferred: false)

    static var full: KeepSources {
        var sources = KeepSources()
        sources.facts = facts(v4, n: 4)
        sources.versions = versions
        sources.showing = showing
        sources.chosenFacts = facts(v3, n: 3)
        sources.lineage = lineage(inputs: [savedInput])
        sources.inputFacts = [input: ArtifactFacts(v: input, a: inputArtifact, n: 1, name: "z_prime_by_plate.csv", mime: "text/csv",
                                                   size: 4096, at: at(0), sha: nil, isUpload: false, code: nil, codeCut: false, environment: nil)]
        return sources
    }

    static var choices: KeepChoices {
        KeepChoices(name: "Fig 2B · Z′ by plate", version: v3, withAnswer: true, withData: true, withCode: true, collection: "Paper draft")
    }
}

/// Claude's legend files: the files of the answer that shows version 3, made up (since 1.0.6).
private extension Made {
    static let legendsFile = HistoryFile(v: "ffffffff-0000-4000-8000-000000000031", a: "eeeeeeee-0000-4000-8000-000000000031",
                                         name: "FIGURE_LEGENDS_final.md", kind: .markdown, size: 2_400)
    static let siblingFile = HistoryFile(v: "ffffffff-0000-4000-8000-000000000032", a: "eeeeeeee-0000-4000-8000-000000000032",
                                         name: "z_prime.md", kind: .markdown, size: 300)
    static let otherLegend = HistoryFile(v: "ffffffff-0000-4000-8000-000000000033", a: "eeeeeeee-0000-4000-8000-000000000033",
                                         name: "legends_fig7.md", kind: .markdown, size: 900)

    static func withLegends(_ files: [HistoryFile]) -> KeepSources {
        var sources = full
        sources.answerFiles = files
        return sources
    }
}

struct KeepVersionTests {
    @Test func theAnswersVersionIsPreselectedElseTheNewest() {
        #expect(KeepRules.preselect(versions: Made.versions, showing: Made.showing) == Made.v3)
        #expect(KeepRules.preselect(versions: Made.versions, showing: nil) == Made.v4)
        let elsewhere = ShowingMessage(i: 1, at: nil, text: "x", how: .mention, v: "eeeeeeee-0000-4000-8000-000000000009")
        #expect(KeepRules.preselect(versions: Made.versions, showing: elsewhere) == Made.v4)
        #expect(KeepRules.preselect(versions: [], showing: nil) == nil)
    }

    @Test func tilesAreOldestFirstWithTheAnswersMarked() {
        let tiles = KeepRules.tiles(versions: Made.versions.reversed(), showing: Made.showing, gone: [Made.v1])
        #expect(tiles.map(\.n) == [1, 2, 3, 4])
        #expect(tiles[2].inAnswer && !tiles[3].inAnswer)
        #expect(tiles[0].gone && tiles[0].note == "Gone")
        #expect(tiles[2].note == "In the answer")
        #expect(tiles[3].note == nil)
        #expect(tiles[2].label.hasPrefix("v3 · "))
        #expect(tiles[2].accessibilityLabel.contains("in the answer"))
    }

    @Test func theFooterSaysWhichVersionAndWhy() {
        let tiles = KeepRules.tiles(versions: Made.versions, showing: Made.showing, gone: [])
        #expect(KeepRules.versionSentence(tiles: tiles, chosen: Made.v3, showing: Made.showing).hasPrefix("Version 3 of 4, from "))
        #expect(KeepRules.versionSentence(tiles: tiles, chosen: Made.v3, showing: Made.showing).contains("It\u{2019}s the one Claude\u{2019}s answer shows, at "))
        #expect(KeepRules.versionSentence(tiles: tiles, chosen: Made.v4, showing: nil).contains("the newest"))
        #expect(KeepRules.versionSentence(tiles: tiles, chosen: Made.v2, showing: Made.showing).hasPrefix("Version 2 of 4, from "))
        let one = KeepRules.tiles(versions: [Made.versions[0]], showing: nil, gone: [])
        #expect(KeepRules.versionSentence(tiles: one, chosen: Made.v1, showing: nil).hasPrefix("This file has one version"))
        #expect(KeepRules.versionSentence(tiles: tiles, chosen: nil, showing: nil) == "Choose the version to keep.")
    }
}

struct KeepRowTests {
    @Test func theAnswerRowQuotesTheAnswerOrSaysItWasntFound() {
        var sources = Made.full
        let rows = KeepRules.rows(sources: sources)
        let answer = rows.first { $0.kind == .answer }!
        #expect(answer.available && answer.onByDefault)
        #expect(answer.title == "What Claude said about it")
        #expect(answer.detail.hasPrefix("\u{201C}All plates passed except plate 7, which has an edge effect in column 12."))
        #expect(answer.detail.hasPrefix("\u{201C}\(KeepRules.excerpt(Made.showing.text))\u{201D} · the answer at "))
        #expect(answer.detail.contains("\u{2026}\u{201D} · the answer at "))

        sources.showing = nil
        sources.lastAnswer = KeepAnswer(text: "The eleven plates are unchanged.", at: Made.at(30), how: nil, isFallback: true)
        let fallback = KeepRules.rows(sources: sources).first { $0.kind == .answer }!
        #expect(fallback.title == "What Claude said last")
        #expect(fallback.detail.contains("The session\u{2019}s last answer, at "))
        #expect(fallback.available)

        sources.lastAnswer = nil
        let none = KeepRules.rows(sources: sources).first { $0.kind == .answer }!
        #expect(!none.available)
        #expect(none.detail.hasPrefix("Capsid couldn\u{2019}t find the answer that showed this version."))
    }

    @Test func anAnswerAboutAnotherVersionSaysSoAndIsOffByDefault() {
        var sources = Made.full
        // The answer shows version 3.
        #expect(KeepRules.rows(sources: sources, chosen: Made.v3).first { $0.kind == .answer }
            == KeepRules.rows(sources: sources).first { $0.kind == .answer })
        let other = KeepRules.rows(sources: sources, chosen: Made.v4).first { $0.kind == .answer }!
        #expect(other.title == "What Claude said about it")
        #expect(other.detail == "Claude\u{2019}s answer shows version 3, not this one.")
        #expect(other.available && !other.onByDefault)
        #expect(KeepRules.answerShowsAnother(sources, chosen: Made.v4) == Made.v3)
        #expect(KeepRules.answerShowsAnother(sources, chosen: Made.v3) == nil)
        #expect(KeepRules.answerShowsAnother(sources, chosen: nil) == nil)
        // A version the list doesn't have is named without a number.
        sources.showing = ShowingMessage(i: 1, at: nil, text: "x", how: .mention, v: "eeeeeeee-0000-4000-8000-000000000009")
        #expect(KeepRules.rows(sources: sources, chosen: Made.v4).first { $0.kind == .answer }!.detail
            == "Claude\u{2019}s answer shows another version, not this one.")
        // The last answer, the fallback, shows no version in particular.
        sources.showing = nil
        sources.lastAnswer = KeepAnswer(text: "Eleven plates.", at: nil, how: nil, isFallback: true)
        let fallback = KeepRules.rows(sources: sources, chosen: Made.v4).first { $0.kind == .answer }!
        #expect(fallback.title == "What Claude said last" && fallback.onByDefault)
    }

    @Test func theDataRowNamesTheInputsOrSaysWhyNot() {
        var sources = Made.full
        let data = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(data.available && data.onByDefault)
        #expect(data.detail == "z_prime_by_plate.csv · 4 KB · listed in its provenance")

        sources.lineage = Made.lineage(inputs: [])
        let none = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!none.available && none.detail == "No source data recorded.")
        #expect(none.info?.contains("doesn\u{2019}t guess from file names") == true)

        sources.lineage = Made.lineage(inputs: [Made.savedInput], pending: true)
        let pending = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!pending.available && pending.detail.hasPrefix("Claude Science is still working out"))

        sources.lineage = Made.lineage(inputs: [Made.inferredInput])
        let inferred = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(inferred.available && !inferred.onByDefault)
        #expect(inferred.detail.hasSuffix("· inferred"))
        #expect(inferred.info?.contains("static analysis") == true)

        sources.lineage = Made.lineage(inputs: [Made.unsavedInput])
        let unsaved = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!unsaved.available && unsaved.detail == "Not saved in Claude Science, so Capsid can\u{2019}t copy it.")

        sources.lineage = nil
        sources.lineageFailed = true
        let failed = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!failed.available && failed.detail == "Couldn\u{2019}t read this version\u{2019}s provenance.")

        sources.lineageFailed = false
        let reading = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!reading.available && reading.detail == "Reading its provenance\u{2026}")
    }

    @Test func anInputOverTheCapIsListedNotCopied() {
        var sources = Made.full
        sources.inputFacts[Made.input] = ArtifactFacts(v: Made.input, a: Made.inputArtifact, n: 1, name: "huge.csv", mime: "text/csv",
                                                       size: 9 * 1024 * 1024, at: nil, sha: nil, isUpload: false, code: nil,
                                                       codeCut: false, environment: nil)
        let data = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(!data.available)
        #expect(data.detail == "1 file · too big to keep here (over 8 MB).")
        let plan = KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices)!
        #expect(!plan.files.contains { $0.role == .data })
    }

    @Test func theCodeRowUsesThePagesOwnSentences() {
        var sources = Made.full
        let code = KeepRules.rows(sources: sources).first { $0.kind == .code }!
        #expect(code.available && code.onByDefault)
        #expect(code.detail.hasPrefix("z_prime.py · ") && code.detail.hasSuffix("· Claude-generated reconstruction"))

        sources.lineage = Made.lineage(inputs: [], code: nil, pending: true)
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .code }!.detail == "Generating reproduction code\u{2026}")
        sources.lineage = Made.lineage(inputs: [], code: nil, reason: "not_enabled_for_org")
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .code }!.detail
            == "No reproduction code — the lineage model is off for your organization")
        sources.lineage = Made.lineage(inputs: [], code: nil, reason: "quota")
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .code }!.detail
            == "No reproduction code — the lineage model isn\u{2019}t available")
        sources.lineage = Made.lineage(inputs: [], code: nil, hasCells: true)
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .code }!.detail == "No reproduction code available for this version")
        sources.lineage = Made.lineage(inputs: [], code: nil, hasCells: false)
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .code }!.detail
            == "No reproduction code — this version has no recorded execution")
    }

    @Test func anUploadHasNoProvenanceToOffer() {
        var sources = Made.full
        sources.chosenFacts = Made.facts(Made.v3, n: 3, upload: true)
        #expect(KeepRules.isUpload(sources))
        #expect(KeepRules.uploadSentence == "You uploaded this file, so it has no inputs or script.")
    }

    @Test func theScriptIsNamedAfterTheFigureAndItsLanguage() {
        var sources = Made.full
        #expect(KeepRules.scriptName(sources) == "z_prime.py")
        sources.lineage = Made.lineage(inputs: [], language: "R")
        #expect(KeepRules.scriptName(sources) == "z_prime.R")
        sources.lineage = Made.lineage(inputs: [], language: nil)
        #expect(KeepRules.scriptName(sources) == "z_prime.txt")
    }
}

struct KeepPlanBuildTests {
    @Test func thePlanCopiesTheChosenVersionAndWhatIsTicked() throws {
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        #expect(plan.figure.role == .figure)
        #expect(plan.figure.version == Made.v3)
        #expect(plan.figure.name == "z_prime.png")
        #expect(plan.figure.sha == String(repeating: "ab", count: 32))
        #expect(plan.files.map(\.relativePath) == ["data/z_prime_by_plate.csv", "code/z_prime.py"])
        #expect(plan.answer?.text == Made.showing.text)
        #expect(plan.answer?.isFallback == false)
        #expect(plan.totalBytes == 86_016 + 4096 + plan.files[1].size!)
        // The script points at the kept data, not at the version token.
        guard case .text(let script) = plan.files[1].source else { Issue.record("no script"); return }
        #expect(script.contains("pd.read_csv(\"../data/z_prime_by_plate.csv\")"))
        #expect(!script.contains("{{artifact:"))
    }

    @Test func untickedRowsAreLeftOutAndNothingIsGuessed() throws {
        var choices = Made.choices
        choices.withData = false
        choices.withCode = false
        choices.withAnswer = false
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: choices))
        #expect(plan.files.isEmpty)
        #expect(plan.answer == nil)
        // Data ticked but unavailable (no provenance): still nothing.
        var sources = Made.full
        sources.lineage = Made.lineage(inputs: [])
        let none = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        #expect(!none.files.contains { $0.role == .data })
    }

    @Test func anAnswerKeptWithAnotherVersionIsMarkedInThePlanOnlyWhenTicked() throws {
        var choices = Made.choices
        choices.version = Made.v4
        choices.withAnswer = false
        let off = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: choices))
        #expect(off.answer == nil && off.answerShows == nil)
        choices.withAnswer = true
        let on = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: choices))
        #expect(on.answer?.text == Made.showing.text)
        #expect(on.answerShows == Made.v3)
        // The answer's own version: nothing to mark.
        let same = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        #expect(same.answerShows == nil)
        // The fallback answer is never marked.
        var sources = Made.full
        sources.showing = nil
        sources.lastAnswer = KeepAnswer(text: "Eleven plates.", at: nil, how: nil, isFallback: true)
        let fallback = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: choices))
        #expect(fallback.answer?.isFallback == true && fallback.answerShows == nil)
    }

    @Test func aPinnedSubjectStillMakesTheSameSubjectWithoutIt() {
        #expect(KeepSubject(session: Made.session, entry: Made.entry).pinned == nil)
        let pinned = KeepSubject(session: Made.session, entry: Made.entry, pinned: KeepPinnedAnswer(text: "x", at: nil))
        #expect(pinned != Made.subject)
        #expect(pinned.pinned == KeepPinnedAnswer(text: "x", at: nil))
    }

    @Test func aVanishedOrUnchosenVersionMakesNoPlan() {
        var choices = Made.choices
        choices.version = nil
        #expect(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: choices) == nil)
        var sources = Made.full
        sources.gone = [Made.v3]
        #expect(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices) == nil)
    }

    @Test func fileNamesAreMadeSafeAndUnique() throws {
        var sources = Made.full
        sources.chosenFacts = Made.facts(Made.v3, n: 3, name: "z_prime_by_plate.csv")
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        // The data file shares the figure's name, so it is numbered.
        #expect(plan.figure.name == "z_prime_by_plate.csv")
        #expect(plan.files[0].name == "z_prime_by_plate 2.csv")
    }

    @Test func anInputTheLineageListsTwiceIsKeptOnce() throws {
        // A file two cells read is listed twice by its version. That used to trap
        // (a dictionary built from the data files' versions) and, past the trap,
        // fetched and kept the same bytes twice.
        var sources = Made.full
        sources.lineage = Made.lineage(inputs: [Made.savedInput, Made.savedInput, Made.inferredInput])
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        #expect(plan.files.map(\.relativePath) == ["data/z_prime_by_plate.csv", "code/z_prime.py"])
        #expect(plan.files.filter { $0.role == .data }.count == 1)
        guard case .text(let script) = plan.files[1].source else { Issue.record("no script"); return }
        #expect(script.contains("pd.read_csv(\"../data/z_prime_by_plate.csv\")"))
        // The row counts the file once, and listed beats inferred.
        let copyable = KeepRules.copyableInputs(sources).copyable
        #expect(copyable.count == 1 && copyable.first?.inferred == false)
        let data = KeepRules.rows(sources: sources).first { $0.kind == .data }!
        #expect(data.detail == "z_prime_by_plate.csv · 4 KB · listed in its provenance")
        // Twice over the cap is one file too big, once.
        sources.inputFacts[Made.input] = ArtifactFacts(v: Made.input, a: Made.inputArtifact, n: 1, name: "huge.csv", mime: "text/csv",
                                                       size: 9 * 1024 * 1024, at: nil, sha: nil, isUpload: false, code: nil,
                                                       codeCut: false, environment: nil)
        #expect(KeepRules.copyableInputs(sources).tooBig.count == 1)
        #expect(KeepRules.rows(sources: sources).first { $0.kind == .data }!.detail == "1 file \u{00B7} too big to keep here (over 8 MB).")
    }

    @Test func theDefaultNameIsTheFileWithoutItsExtension() {
        #expect(KeepRules.defaultName(for: Made.entry) == "z_prime")
        let bare = ArtifactEntry(version: Made.v1, artifact: nil, name: "README", mime: nil, size: 1, at: nil)
        #expect(KeepRules.defaultName(for: bare) == "README")
    }
}

struct KeepSentenceTests {
    @Test func theDestinationSentenceSaysWhereAndWhat() throws {
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        let root = URL(fileURLWithPath: "/Volumes/Lab/Kept", isDirectory: true)
        let sentence = KeepRules.destinationSentence(root: root, collection: "Paper draft", folderName: "Fig 2B · Z′ by plate",
                                                     plan: plan, nameTaken: false, requested: "Fig 2B · Z′ by plate")
        #expect(sentence.hasPrefix("Into /Volumes/Lab/Kept/Paper draft/Fig 2B · Z′ by plate: z_prime.png, data, code and a README.md. About "))
        let taken = KeepRules.destinationSentence(root: root, collection: "Paper draft", folderName: "Fig 2B · Z′ by plate 2026-10-22 0912",
                                                  plan: plan, nameTaken: true, requested: "Fig 2B · Z′ by plate")
        #expect(taken.hasPrefix("\u{201C}Fig 2B · Z′ by plate\u{201D} is already kept in Paper draft, so this one will be \u{201C}Fig 2B · Z′ by plate 2026-10-22 0912\u{201D}. Into "))
    }

    @Test func theOutcomeSentenceCountsAndNamesWhatIsMissing() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let complete = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 3, total: 3, missing: [])
        #expect(KeepRules.outcomeSentence(complete) == "Kept 3 files.")
        let one = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 2, total: 3,
                              missing: [KeptMissing(role: .data, name: "a.csv", reason: "too big")])
        #expect(KeepRules.outcomeSentence(one) == "Kept 2 of 3 files. The data it was drawn from wasn\u{2019}t copied.")
        let two = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 1, total: 3,
                              missing: [KeptMissing(role: .data, name: "a.csv", reason: "x"), KeptMissing(role: .code, name: "b.py", reason: "y")])
        #expect(KeepRules.outcomeSentence(two) == "Kept 1 of 3 files. 2 weren\u{2019}t copied.")
    }

    @Test func anOutcomeWhoseReadmeWasntUpdatedSaysSoAndIsntComplete() {
        let folder = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        let all = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 3, total: 3, missing: [],
                              recordFailed: "Capsid isn\u{2019}t allowed to change the Kept folder.")
        #expect(!all.isComplete)
        #expect(KeepRules.outcomeSentence(all)
            == "Kept 3 files. The files landed, but README.md couldn\u{2019}t be updated to list them. Capsid isn\u{2019}t allowed to change the Kept folder.")
        let some = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 2, total: 3,
                               missing: [KeptMissing(role: .data, name: "a.csv", reason: "too big")], recordFailed: "The folder didn\u{2019}t respond")
        #expect(KeepRules.outcomeSentence(some)
            == "Kept 2 of 3 files. The data it was drawn from wasn\u{2019}t copied. The files landed, but README.md couldn\u{2019}t be updated to list them. The folder didn\u{2019}t respond.")
    }

    @Test func filesThatDontMatchTheirChecksumsAreNamedAndKeepTheSheetOpen() {
        let folder = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        func file(_ path: String) -> KeptFile {
            KeptFile(path: path, role: path.hasPrefix("data/") ? .data : .figure, sha256: "9c41", bytes: 1, expectedSha256: "3f2a")
        }
        let one = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 3, total: 3, missing: [],
                              mismatched: [file("z_prime.png")])
        #expect(one.isComplete && !one.closesSheet)
        #expect(KeepRules.outcomeSentence(one)
            == "Kept 3 files. z_prime.png doesn\u{2019}t match Claude Science\u{2019}s checksum; see README.md before you use it.")
        let two = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 2, total: 3,
                              missing: [KeptMissing(role: .code, name: "z_prime.py", reason: "x")],
                              mismatched: [file("z_prime.png"), file("data/a.csv")])
        #expect(KeepRules.outcomeSentence(two)
            == "Kept 2 of 3 files. The code that drew it wasn\u{2019}t copied. z_prime.png and data/a.csv don\u{2019}t match Claude Science\u{2019}s checksums; see README.md before you use them.")
        #expect(KeepRules.mismatchClause(["a", "b", "c"])?.hasPrefix("a, b and c don\u{2019}t match") == true)
        #expect(KeepRules.mismatchClause([]) == nil)
        let clean = KeepOutcome(folder: folder, collection: "c", folderName: "n", kept: 3, total: 3, missing: [])
        #expect(clean.closesSheet)
    }

    @Test func theExcerptIsOneLineCutAtAWord() {
        #expect(KeepRules.excerpt("Short.") == "Short.")
        let long = "All plates passed except plate 7, which has an edge effect in column 12. It's flagged and left out of the cleaned table; the other eleven are unchanged."
        let cut = KeepRules.excerpt(long)
        #expect(cut.hasSuffix("\u{2026}") && cut.count <= 92)
        #expect(KeepRules.excerpt("line one\n\n  line two  ") == "line one line two")
    }
}

struct KeepRecordTests {
    @Test @MainActor func aKeepRemembersOnlyTheReplyThatShowsItsChosenVersion() throws {
        func write(_ sources: KeepSources, _ choices: KeepChoices = Made.choices) throws -> (KeptRecord, KeptText) {
            let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: choices))
            return KeepRules.record(subject: Made.subject, sources: sources, plan: plan, folderName: "Plate reader QC",
                                    keptAt: Made.at(100), copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0.6")
        }
        let (record, text) = try write(Made.full)
        #expect(record.sourceRow == 41)
        let markdown = KeptReadme.render(record, text: text)
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(parsed.record.sourceRow == 41)
        let result = KeptResult(folder: URL(fileURLWithPath: "/made-up/Kept/Assay development/Plate reader QC"),
                                collection: "Assay development", record: parsed.record, text: parsed.text)
        let item = try #require(ShelfRules.items(from: [result]).first)
        #expect(ShelfClaudeLegend.canLook(at: item))
        #expect(item.record.sourceRow == 41, "Show Where It Came From uses this row")

        var sources = Made.full
        sources.showing = ShowingMessage(i: 0, at: Made.showing.at, text: Made.showing.text, how: .image, v: Made.v3)
        #expect(try write(sources).0.sourceRow == 0)
        sources.showing = ShowingMessage(i: -1, at: Made.showing.at, text: Made.showing.text, how: .image, v: Made.v3)
        #expect(try write(sources).0.sourceRow == nil, "a pinned answer has no history row")
        sources.showing = nil
        sources.lastAnswer = KeepAnswer(text: "Last answer.", at: Made.at(30), how: nil, isFallback: true)
        #expect(try write(sources).0.sourceRow == nil)
        sources.lastAnswer = nil
        #expect(try write(sources).0.sourceRow == nil)

        var choices = Made.choices
        choices.version = Made.v4
        #expect(try write(Made.full, choices).0.sourceRow == nil, "another version's reply is not this figure's source")
        choices = Made.choices
        choices.withAnswer = false
        let withoutWords = try write(Made.full, choices)
        #expect(withoutWords.0.sourceRow == 41, "omitting the quoted words keeps the known provenance")
        #expect(withoutWords.1.claudeSaid.isEmpty)
    }

    @Test func theRecordNamesTheChosenVersionNotTheLatest() throws {
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        let sha = String(repeating: "cd", count: 32)
        let copied = [KeptFile(path: "z_prime.png", role: .figure, artifact: Made.artifact, version: Made.v3, index: nil, of: nil, sha256: sha, bytes: 86_016),
                      KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: Made.inputArtifact, version: Made.input, index: nil, of: nil, sha256: "ef", bytes: 4096)]
        let missing = [KeptMissing(role: .code, name: "z_prime.py", reason: "the folder didn\u{2019}t respond")]
        let (record, text) = KeepRules.record(subject: Made.subject, sources: Made.full, plan: plan, folderName: "Fig 2B · Z′ by plate",
                                              keptAt: Made.at(100), copied: copied, missing: missing, scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(record.name == "Fig 2B · Z′ by plate")
        #expect(record.figure.version == Made.v3)
        #expect(record.figure.index == 3 && record.figure.of == 4)
        #expect(record.figure.sha256 == sha && record.figure.bytes == 86_016)
        #expect(record.files.map(\.path) == ["data/z_prime_by_plate.csv"])
        #expect(record.missing == missing)
        #expect(record.sessionID == Made.session.id && record.projectName == "Assay development")
        #expect(record.claudeScience == "0.1.70" && record.capsid == "1.0")
        #expect(text.claudeSaid == Made.showing.text)
        #expect(text.attribution.hasPrefix("From Claude\u{2019}s answer at "))
        #expect(text.attribution.hasSuffix(" on \(KeepRules.longDate(Made.at(12)))."))
        #expect(text.origin.hasPrefix("[Plate reader QC](bench://session?project=p-1&frame=\(Made.session.id)), in Assay development.\nVersion 3 of 4 of z_prime.png, kept on "))
        #expect(text.origin.contains("by Capsid 1.0, from Claude Science 0.1.70."))
        #expect(text.legend.isEmpty)
    }

    @Test func anAnswerWhoseWordsAreCutSaysSoInTheREADME() throws {
        var sources = Made.full
        let plain = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        let (_, whole) = KeepRules.record(subject: Made.subject, sources: sources, plan: plain, folderName: "Fig", keptAt: Made.at(100),
                                          copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(!whole.attribution.contains("cut off"))
        sources.showingCut = true
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        #expect(plan.answer?.cut == true)
        let (_, text) = KeepRules.record(subject: Made.subject, sources: sources, plan: plan, folderName: "Fig", keptAt: Made.at(100),
                                         copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(text.attribution.hasPrefix("From Claude\u{2019}s answer at "))
        #expect(text.attribution.hasSuffix(" The text is cut off: the rest couldn\u{2019}t be read."))
        // With the answer unticked there is nothing to say it of.
        var off = Made.choices
        off.withAnswer = false
        let none = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: off))
        #expect(none.answer == nil)
    }

    @Test func anAnswerKeptWithAnotherVersionIsRecordedAsSuch() throws {
        var choices = Made.choices
        choices.version = Made.v4
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: choices))
        let (record, text) = KeepRules.record(subject: Made.subject, sources: Made.full, plan: plan, folderName: "n", keptAt: Made.at(100),
                                              copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(record.figure.version == Made.v4 && record.figure.index == 4)
        #expect(record.answerShowsVersion == 3)
        #expect(text.attribution.hasPrefix("From Claude\u{2019}s answer at "))
        #expect(text.attribution.hasSuffix(". That answer shows version 3, not this one."))
        // Its own version: as before.
        let same = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        let (plain, plainText) = KeepRules.record(subject: Made.subject, sources: Made.full, plan: same, folderName: "n", keptAt: Made.at(100),
                                                  copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(plain.answerShowsVersion == nil)
        #expect(!plainText.attribution.contains("not this one"))
    }

    @Test func aFigureThatDoesntMatchItsChecksumKeepsBothInTheRecord() throws {
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        let copied = [KeptFile(path: "z_prime.png", role: .figure, artifact: Made.artifact, version: Made.v3, sha256: "9c41", bytes: 10,
                               expectedSha256: String(repeating: "ab", count: 32))]
        let (record, _) = KeepRules.record(subject: Made.subject, sources: Made.full, plan: plan, folderName: "n", keptAt: Made.at(100),
                                           copied: copied, missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(record.figure.sha256 == "9c41")
        #expect(record.figure.expectedSha256 == String(repeating: "ab", count: 32))
        #expect(record.figure.index == 3)
    }

    @Test func theFallbackAnswerIsLabelledAsSuch() throws {
        var sources = Made.full
        sources.showing = nil
        sources.lastAnswer = KeepAnswer(text: "Eleven plates.", at: Made.at(30), how: nil, isFallback: true)
        var choices = Made.choices
        choices.version = Made.v4
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: choices))
        let (_, text) = KeepRules.record(subject: Made.subject, sources: sources, plan: plan, folderName: "n", keptAt: Made.at(100),
                                         copied: [], missing: [], scienceVersion: nil, capsidVersion: "1.0")
        #expect(text.attribution.hasPrefix("From Claude\u{2019}s last answer in the session at "))
        #expect(text.attribution.hasSuffix("The answer that shows this version wasn\u{2019}t found."))
        #expect(text.origin.contains("from Claude Science an unknown version."))
    }

    @Test func datesAreWrittenOutInEnglish() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 22; components.hour = 9; components.minute = 12
        let date = Calendar.current.date(from: components)!
        #expect(KeepRules.longDate(date) == "22 October 2026")
        #expect(KeepRules.deepLink(Made.session) == "bench://session?project=p-1&frame=\(Made.session.id)")
    }
}

// MARK: A pick stays picked; a folder is its figure

struct KeepPickedVersionTests {
    @Test func aVersionTheUserPickedIsNotMovedByTheAnswer() {
        // Version 1 picked while the answer shows version 3: version 1.
        #expect(KeepRules.preselect(versions: Made.versions, showing: Made.showing, picked: Made.v1) == Made.v1)
        // No answer at all: still version 1, not the newest.
        #expect(KeepRules.preselect(versions: Made.versions, showing: nil, picked: Made.v1) == Made.v1)
        // A pick that isn't one of the artifact's falls back to the old rule, not to a guess.
        #expect(KeepRules.preselect(versions: Made.versions, showing: Made.showing, picked: "eeeeeeee-0000-4000-8000-000000000009") == Made.v3)
        #expect(KeepRules.preselect(versions: Made.versions, showing: nil, picked: nil) == Made.v4)
    }

    @Test func aSubjectSaysWhetherItsVersionWasPicked() {
        let results = KeepSubject(session: Made.session, entry: Made.entry)
        #expect(!results.selectsItsVersion && !results.picksItsVersion)
        let clicked = KeepSubject(session: Made.session, entry: Made.entry, selectsItsVersion: true)
        #expect(clicked.selectsItsVersion && clicked.picksItsVersion && clicked.pinned == nil)
        #expect(clicked != results)
        // An answer pinned by the reference reader is a pick too.
        let pinned = KeepSubject(session: Made.session, entry: Made.entry, pinned: KeepPinnedAnswer(text: "x", at: nil))
        #expect(!pinned.selectsItsVersion && pinned.picksItsVersion)
    }
}

struct KeepFigureFirstTests {
    private func planFor(figure: String, input: String? = nil, version: String = Made.v3) throws -> KeepPlan {
        var sources = Made.full
        sources.chosenFacts = Made.facts(version, n: 3, name: figure)
        sources.facts = Made.facts(Made.v4, n: 4, name: figure)
        if let input {
            sources.lineage = Made.lineage(inputs: [LineageInput(v: Made.input, a: Made.inputArtifact, name: input, file: nil, how: "runtime", inferred: false)])
            sources.inputFacts = [Made.input: ArtifactFacts(v: Made.input, a: Made.inputArtifact, n: 1, name: input, mime: "text/plain", size: 4096,
                                                            at: Made.at(0), sha: nil, isUpload: false, code: nil, codeCut: false, environment: nil)]
        }
        return try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
    }

    @Test func aFigureCalledReadmeIsKeptUnderAnotherNameAndAllowedByTheDisk() throws {
        for name in ["README.md", "readme.md", "Readme.MD"] {
            let plan = try planFor(figure: name)
            #expect(plan.figure.name == KeptLayout.fileName(name), "\(name)")
            #expect(!KeptLayout.isReadme(plan.figure.name), "\(name)")
            #expect(plan.figure.relativePath == plan.figure.name)
            #expect(KeptLayout.isValidRelativePath(plan.figure.relativePath), "\(name)")
        }
        #expect(try planFor(figure: "README.md").figure.name == "README 2.md")
        // Other names, and names that only contain it, are left alone.
        #expect(try planFor(figure: "README.txt").figure.name == "README.txt")
        #expect(try planFor(figure: "my README.md").figure.name == "my README.md")
    }

    @Test func aFigureCalledLikeAFolderBesideItIsKeptUnderAnotherName() throws {
        // A file called "data" would be where the data folder has to go.
        for (name, kept) in [("data", "data 2"), ("Code", "Code 2"), ("INPUT", "INPUT 2"), ("data.csv", "data.csv")] {
            let plan = try planFor(figure: name, input: "z_prime_by_plate.csv")
            #expect(plan.figure.name == kept, "\(name)")
            #expect(KeptLayout.isValidRelativePath(plan.figure.relativePath))
            #expect(Set(plan.all.map { $0.relativePath.lowercased() }).count == plan.all.count)
        }
    }

    @Test func everyFileOfAPlanIsOneTheDiskTakes() throws {
        let plan = try planFor(figure: "README.md", input: "README.md")
        let paths = plan.all.map(\.relativePath)
        #expect(paths.first == "README 2.md")
        #expect(paths.contains { $0.hasPrefix("data/") } && paths.contains { $0.hasPrefix("code/") })
        for path in paths { #expect(KeptLayout.isValidRelativePath(path), "\(path)") }
        // The input called README.md doesn't take the figure's new name either.
        #expect(plan.files.first { $0.role == .data }?.relativePath == "data/README 3.md")
        // Lower-cased names are the same name on a disk that ignores case.
        let again = try planFor(figure: "readme.md", input: "README.md")
        #expect(Set(again.all.map { $0.relativePath.lowercased() }).count == again.all.count)
        for path in again.all.map(\.relativePath) { #expect(KeptLayout.isValidRelativePath(path), "\(path)") }
    }

    @Test func aVersionOverTheCapSaysSoAndIsNotKeepable() throws {
        let big = ArtifactVersion(v: Made.v2, n: 2, frame: nil, mime: "image/tiff", size: KeepRules.cap + 1, at: Made.at(4), parent: Made.v1)
        let versions = [Made.versions[0], big, Made.versions[2], Made.versions[3]]
        let tiles = KeepRules.tiles(versions: versions, showing: nil, gone: [])
        let sentence = KeepRules.versionSentence(tiles: tiles, chosen: Made.v2, showing: nil)
        #expect(sentence.hasPrefix("Version 2 of 4, from "))
        #expect(sentence.hasSuffix("it\u{2019}s over the 8 MB Capsid can copy here, so this version can\u{2019}t be kept."))
        // The others read as they did, and a version at the cap exactly is fine.
        #expect(!KeepRules.versionSentence(tiles: tiles, chosen: Made.v3, showing: nil).contains("8 MB"))
        let exact = ArtifactVersion(v: Made.v2, n: 2, frame: nil, mime: nil, size: KeepRules.cap, at: nil, parent: nil)
        let atCap = KeepRules.tiles(versions: [exact], showing: nil, gone: [])
        #expect(KeepRules.versionSentence(tiles: atCap, chosen: Made.v2, showing: nil) == "This file has one version.")

        var sources = Made.full
        sources.chosenFacts = Made.facts(Made.v3, n: 3, size: KeepRules.cap + 1)
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        #expect(KeepRules.figureOverCap(plan))
        #expect(!KeepRules.figureOverCap(try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))))
    }

    @Test func theSentencesSayWhatHappenedAndThatNothingWasKept() {
        #expect(KeepRules.figureTooBig("z_prime.tif")
            == "z_prime.tif is over 8 MB, which is more than Capsid can copy here, so nothing was kept. Choose another version, or Cancel.")
        #expect(KeepRules.figureNotCopied("z_prime.png", because: "There isn\u{2019}t room on this disk.")
            == "z_prime.png wasn\u{2019}t copied, so nothing was kept. There isn\u{2019}t room on this disk.")
        for sentence in [KeepRules.figureTooBig("a.png"), KeepRules.figureNotCopied("a.png", because: "x."), KeepRules.overCapSentence(size: 9_000_000)] {
            #expect(!sentence.contains("!"))
        }
    }
}

// MARK: Claude's legend (since 1.0.6)

struct KeepLegendRowTests {
    @Test func theRowIsThereOnlyWithACandidateAndOnByDefault() {
        #expect(KeepRules.rows(sources: Made.full, chosen: Made.v3).map(\.kind) == [.answer, .data, .code])
        // Files that aren't a legend (a data table, a figure's own version) are no candidate.
        let others = [HistoryFile(v: "ffffffff-0000-4000-8000-000000000041", a: nil, name: "plate_map.csv", kind: .table, size: 90)]
        #expect(KeepRules.rows(sources: Made.withLegends(others), chosen: Made.v3).map(\.kind) == [.answer, .data, .code])

        let rows = KeepRules.rows(sources: Made.withLegends([Made.legendsFile]), chosen: Made.v3)
        #expect(rows.map(\.kind) == [.answer, .data, .code, .legend])
        let legend = rows.last!
        #expect(legend.title == "Claude\u{2019}s legend")
        #expect(legend.detail == "FIGURE_LEGENDS_final.md \u{00B7} its part for this figure goes in your legend")
        #expect(legend.available && legend.onByDefault && legend.info == nil)
    }

    @Test func noRowWhileNoVersionIsChosenOrForAnAnswerAboutAnotherVersion() {
        let sources = Made.withLegends([Made.legendsFile])
        #expect(KeepRules.rows(sources: sources).map(\.kind) == [.answer, .data, .code])
        // The answer shows version 3: its legend isn't about version 4.
        #expect(KeepRules.rows(sources: sources, chosen: Made.v4).map(\.kind) == [.answer, .data, .code])
        // An answer whose row isn't known (one the caller pinned) has no files to look in.
        var pinned = sources
        pinned.showing = ShowingMessage(i: -1, at: Made.at(12), text: "x", how: .image, v: Made.v3)
        #expect(KeepRules.rows(sources: pinned, chosen: Made.v3).map(\.kind) == [.answer, .data, .code])
        // An upload has no legend from Claude.
        var upload = sources
        upload.chosenFacts = Made.facts(Made.v3, n: 3, upload: true)
        #expect(KeepRules.rows(sources: upload, chosen: Made.v3).map(\.kind) == [.answer, .data, .code])
    }

    @Test func theBestOfSeveralIsUsedAndTheDetailSaysWhich() {
        let sources = Made.withLegends([Made.legendsFile, Made.otherLegend, Made.siblingFile])
        let candidates = KeepRules.legendCandidates(sources, chosen: Made.v3)
        // The same order the Shelf's offer shows: the file with the figure's name, then the legend files.
        #expect(candidates.map(\.name) == ["z_prime.md", "FIGURE_LEGENDS_final.md", "legends_fig7.md"])
        #expect(candidates.map(\.name) == ShelfClaudeLegendRules.candidates(among: sources.answerFiles, forFigure: "z_prime.png", version: Made.v3).map(\.name))
        let row = KeepRules.rows(sources: sources, chosen: Made.v3).last!
        #expect(row.detail == "z_prime.md, the closest of 3 in the answer \u{00B7} its part for this figure goes in your legend")
    }

    @Test func thePlanIncludesTheFileUnlessItIsUnticked() throws {
        let sources = Made.withLegends([Made.legendsFile])
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        let legend = try #require(plan.files.first { $0.role == .legend })
        #expect(plan.files.map(\.role) == [.data, .code, .legend])
        #expect(legend.source == .download(version: Made.legendsFile.v))
        #expect(legend.artifact == Made.legendsFile.a && legend.version == Made.legendsFile.v)
        #expect(legend.relativePath == "FIGURE_LEGENDS_final.md" && legend.size == 2_400)
        #expect(plan.totalBytes == 86_016 + 4096 + legend.size! + (plan.files.first { $0.role == .code }?.size ?? 0))

        var off = Made.choices
        off.withLegend = false
        let without = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: off))
        #expect(without.files.map(\.role) == [.data, .code])
        // No file to copy where there is no row, ticked or not.
        let none = try #require(KeepRules.plan(subject: Made.subject, sources: Made.full, choices: Made.choices))
        #expect(none.files.allSatisfy { $0.role != .legend })
    }

    @Test func theDestinationNamesItAndTheRecordCarriesTheLegend() throws {
        let sources = Made.withLegends([Made.legendsFile])
        let plan = try #require(KeepRules.plan(subject: Made.subject, sources: sources, choices: Made.choices))
        let sentence = KeepRules.destinationSentence(root: URL(fileURLWithPath: "/tmp/Kept"), collection: "Paper draft", folderName: "Fig",
                                                     plan: plan, nameTaken: false, requested: "Fig")
        #expect(sentence.contains("z_prime.png, data, code, Claude\u{2019}s legend and a README.md."), "\(sentence)")
        let (_, text) = KeepRules.record(subject: Made.subject, sources: sources, plan: plan, folderName: "Fig", keptAt: Made.at(100),
                                         copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0", legend: "Z\u{2032} by plate.")
        #expect(text.legend == "Z\u{2032} by plate.")
        // Without one, as before: the person writes it.
        let (_, plain) = KeepRules.record(subject: Made.subject, sources: sources, plan: plan, folderName: "Fig", keptAt: Made.at(100),
                                          copied: [], missing: [], scienceVersion: "0.1.70", capsidVersion: "1.0")
        #expect(plain.legend.isEmpty)
        #expect(KeepRules.roleTitle(.legend) == "Claude\u{2019}s legend file")
    }

    @Test func theShelfAndKeepReadTheSameFileTheSameWay() {
        let text = "# Legends\n\n## Figure 2\n\n**Z\u{2032}.** By plate.\n\n## Figure 3\n\nElsewhere.\n"
        let reading = ShelfClaudeLegendRules.reading(Data(text.utf8), fileName: "legends.md", forFigure: "fig2_z_prime.png")
        let part = ShelfClaudeLegendRules.part(of: text, fromFile: "legends.md", forFigure: "fig2_z_prime.png")
        #expect(reading == .part(part))
        #expect(part.text == "Z\u{2032}. By plate.")
        #expect(ShelfClaudeLegendRules.reading(Data([0x41, 0x00, 0x42]), fileName: "a.md", forFigure: "f.png") == .notText)
        #expect(ShelfClaudeLegendRules.reading(Data("\n  \n".utf8), fileName: "a.md", forFigure: "f.png") == .empty)
    }
}
