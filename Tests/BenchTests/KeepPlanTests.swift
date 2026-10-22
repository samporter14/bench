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

    @Test func theExcerptIsOneLineCutAtAWord() {
        #expect(KeepRules.excerpt("Short.") == "Short.")
        let long = "All plates passed except plate 7, which has an edge effect in column 12. It's flagged and left out of the cleaned table; the other eleven are unchanged."
        let cut = KeepRules.excerpt(long)
        #expect(cut.hasSuffix("\u{2026}") && cut.count <= 92)
        #expect(KeepRules.excerpt("line one\n\n  line two  ") == "line one line two")
    }
}

struct KeepRecordTests {
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
