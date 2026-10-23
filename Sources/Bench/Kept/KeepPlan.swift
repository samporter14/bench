// KeepPlan.swift — the decisions behind the Keep sheet (DESIGN.md, Keep).
// Keep saves one chosen version of a file a session made, with Claude's words
// about it, the data it was drawn from and the script that drew it, into a
// folder the user owns. Everything here is pure: which version to pre-select,
// what each "Keep with it" row says and whether it can be ticked, what gets
// copied, what the README records and what the sheet says afterwards. The
// reads and the disk are elsewhere (KeepModel, KeptDisk), so the tests run
// this on made-up versions, provenance and answers.
import Foundation

/// What the user picked in Results: the session and the file.
struct KeepSubject: Equatable, Sendable {
    let session: SessionStatus
    let entry: ArtifactEntry
    /// Keep… pressed on a figure inside a known answer (the reference reader): that
    /// version is preselected and that answer is the one kept with it, whatever newer
    /// answer shows another version. Nil from Results.
    var pinned: KeepPinnedAnswer? = nil
    /// The user picked this very version (a figure or a link they right-clicked in
    /// the conversation), whether or not the caller knows its answer: it is the
    /// selection, whatever answer is found, and the answer looked for is the one
    /// that shows it. False from Results, whose entry is the latest version
    /// project-wide, which Keep never takes as the user's pick.
    var selectsItsVersion = false

    /// Whether the entry's version is the user's own pick, by either way of saying so.
    var picksItsVersion: Bool { selectsItsVersion || pinned != nil }
}

/// The answer a figure was shown in, when the caller knows it: its words and
/// when it was sent. The version it shows is the subject's own.
struct KeepPinnedAnswer: Equatable, Sendable {
    let text: String
    let at: Date?
    /// Some of the words are cut: a long turn the page cut at 2,000 characters
    /// whose rest couldn't be read in time. The README says so.
    var cut = false
}

/// Claude's words about the figure: the answer that shows it, or the
/// session's last answer when that couldn't be found.
struct KeepAnswer: Equatable, Sendable {
    let text: String
    let at: Date?
    let how: ShowingHow?
    let isFallback: Bool
    /// Some of the words are cut (`KeepPinnedAnswer.cut`).
    var cut = false
}

/// What the reads gave the sheet. Each piece may be missing: the sheet says
/// so in words and never guesses.
struct KeepSources: Equatable, Sendable {
    /// The picked file's own version: the artifact id and the name.
    var facts: ArtifactFacts? = nil
    /// Every version of the artifact, oldest first.
    var versions: [ArtifactVersion] = []
    var versionsFailed: ShelfFailure? = nil
    /// The answer that shows one of the versions.
    var showing: ShowingMessage? = nil
    /// Its words are cut (the caller pinned an answer that is).
    var showingCut = false
    /// The session's last answer, the fallback.
    var lastAnswer: KeepAnswer? = nil
    /// Of the chosen version.
    var lineage: ArtifactLineage? = nil
    var lineageFailed: Bool = false
    var chosenFacts: ArtifactFacts? = nil
    /// Each input's facts (its name and size), by version id.
    var inputFacts: [String: ArtifactFacts] = [:]
    /// Versions that vanished while the sheet was open.
    var gone: Set<String> = []
}

/// One version in the strip.
struct VersionTile: Equatable, Identifiable, Sendable {
    let v: String
    let n: Int
    let at: Date?
    let size: Int
    let inAnswer: Bool
    let gone: Bool
    var id: String { v }

    /// "v3 · 8:09".
    var label: String {
        guard let at else { return "v\(n)" }
        return "v\(n) · \(at.formatted(date: .omitted, time: .shortened))"
    }

    /// The second line: a fact, in secondary; never invented.
    var note: String? {
        if gone { return "Gone" }
        return inAnswer ? "In the answer" : nil
    }

    var accessibilityLabel: String {
        var parts = ["Version \(n)"]
        if let at { parts.append(at.formatted(date: .omitted, time: .shortened)) }
        if inAnswer { parts.append("in the answer") }
        if gone { parts.append("gone") }
        return parts.joined(separator: ", ")
    }
}

enum KeepRowKind: String, Sendable { case answer, data, code }

/// A "Keep with it" row: what it is, what it holds, and whether it can be
/// ticked. A row that can't says why in its detail.
struct KeepRow: Equatable, Identifiable, Sendable {
    let kind: KeepRowKind
    let title: String
    let detail: String
    let available: Bool
    let onByDefault: Bool
    /// A longer explanation behind an ⓘ, when the detail can't say it all.
    let info: String?
    var id: String { kind.rawValue }
}

/// Where a kept file's bytes come from.
enum KeepSource: Equatable, Sendable {
    case download(version: String)
    case text(String)
}

/// One file to copy.
struct KeepItem: Equatable, Sendable {
    let role: KeptRole
    let source: KeepSource
    let artifact: String?
    let version: String?
    /// The file name inside its folder.
    let name: String
    /// From the listing or the facts; checked again when the bytes come.
    let size: Int?
    /// The daemon's sha256 of the bytes, when it has one.
    let sha: String?

    var relativePath: String {
        switch role {
        case .figure: name
        case .data: "data/\(name)"
        case .code: "code/\(name)"
        case .input: "input/\(name)"
        }
    }
}

struct KeepChoices: Equatable, Sendable {
    var name: String
    var version: String?
    var withAnswer: Bool
    var withData: Bool
    var withCode: Bool
    var collection: String
}

/// What a keep will copy.
struct KeepPlan: Equatable, Sendable {
    let figure: KeepItem
    let files: [KeepItem]
    let answer: KeepAnswer?
    /// The version Claude's answer shows, when the answer is kept with another
    /// one (the user ticked it anyway): the README says so.
    var answerShows: String? = nil
    var all: [KeepItem] { [figure] + files }
    var totalBytes: Int { all.compactMap(\.size).reduce(0, +) }
}

/// What a keep came to.
struct KeepOutcome: Equatable, Sendable {
    let folder: URL
    let collection: String
    let folderName: String
    let kept: Int
    let total: Int
    let missing: [KeptMissing]
    /// Files landed but README.md couldn't be rewritten to list them: why, in
    /// a sentence. Try Again rewrites it.
    var recordFailed: String? = nil
    /// Files kept whose bytes don't match Claude Science's checksum for their
    /// version (each with both checksums): kept, but the sheet stays open to
    /// say so, and the README says it too.
    var mismatched: [KeptFile] = []
    var isComplete: Bool { missing.isEmpty && recordFailed == nil }
    /// Kept, with nothing to say about it: the sheet closes by itself.
    var closesSheet: Bool { isComplete && mismatched.isEmpty }
}

enum KeepRules {
    /// Inputs past this many aren't offered: a figure drawn from hundreds of
    /// files is kept with its figure, script and answer, and the README says so.
    static let inputLimit = 20
    /// The shelf's cap on a download; a file over it is listed, not copied.
    static let cap = ArtifactReaderScript.Cap.download

    // MARK: The versions

    /// The version the user picked, when the caller says so and it is one of the
    /// artifact's; else the one Claude's answer shows, when it is one of them;
    /// else the newest. A pick is never moved by an answer.
    static func preselect(versions: [ArtifactVersion], showing: ShowingMessage?, picked: String? = nil) -> String? {
        if let picked, versions.contains(where: { $0.v == picked }) { return picked }
        if let showing, versions.contains(where: { $0.v == showing.v }) { return showing.v }
        return versions.max(by: { $0.n < $1.n })?.v
    }

    static func tiles(versions: [ArtifactVersion], showing: ShowingMessage?, gone: Set<String>) -> [VersionTile] {
        versions.sorted { $0.n < $1.n }.map { version in
            VersionTile(v: version.v, n: version.n, at: version.at, size: version.size,
                        inAnswer: showing?.v == version.v, gone: gone.contains(version.v))
        }
    }

    /// The strip's footer, in a sentence.
    static func versionSentence(tiles: [VersionTile], chosen: String?, showing: ShowingMessage?) -> String {
        guard let chosen, let tile = tiles.first(where: { $0.v == chosen }) else {
            return tiles.isEmpty ? "" : "Choose the version to keep."
        }
        let sentence = versionSentence(for: tile, of: tiles, showing: showing)
        // A figure over the cap can't be copied, so the folder would have no figure:
        // said here, where the version is chosen, and Keep is off for it.
        return tile.size > cap ? "\(sentence) \(overCapSentence(size: tile.size))" : sentence
    }

    private static func versionSentence(for tile: VersionTile, of tiles: [VersionTile], showing: ShowingMessage?) -> String {
        let chosen = tile.v
        let from = tile.at.map { ", from \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        if tiles.count == 1 {
            return "This file has one version\(from)."
        }
        let position = "Version \(tile.n) of \(tiles.count)"
        if tile.inAnswer, let showing {
            let when = showing.at.map { ", at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return "\(position)\(from). It\u{2019}s the one Claude\u{2019}s answer shows\(when)."
        }
        let newest = tiles.max(by: { $0.n < $1.n })?.v == chosen
        if showing == nil, newest {
            return "\(position), the newest\(from). Capsid couldn\u{2019}t tell which version Claude\u{2019}s answer shows."
        }
        return "\(position)\(from)."
    }

    // MARK: The rows

    static func defaultName(for entry: ArtifactEntry) -> String {
        let stem = (entry.name as NSString).deletingPathExtension
        return stem.isEmpty ? entry.name : stem
    }

    /// The three "Keep with it" rows for the chosen version. `chosen` is the
    /// version picked in the strip, nil while none is.
    static func rows(sources: KeepSources, chosen: String? = nil) -> [KeepRow] {
        [answerRow(sources, chosen: chosen), dataRow(sources), codeRow(sources)]
    }

    /// The version Claude's answer shows, when a version is chosen and it is
    /// another one: that answer isn't about the chosen version.
    static func answerShowsAnother(_ sources: KeepSources, chosen: String?) -> String? {
        guard let chosen, let showing = sources.showing, showing.v != chosen else { return nil }
        return showing.v
    }

    /// "version 4", or "another version" when the answer's version isn't in the list.
    static func versionName(_ v: String, in versions: [ArtifactVersion]) -> String {
        versions.first { $0.v == v }.map { "version \($0.n)" } ?? "another version"
    }

    /// Whether the chosen version is something the user uploaded: then there
    /// is no provenance and no script to keep, and the sheet says so once.
    static func isUpload(_ sources: KeepSources) -> Bool {
        sources.chosenFacts?.isUpload ?? sources.facts?.isUpload ?? false
    }

    static let uploadSentence = "You uploaded this file, so it has no inputs or script."

    // MARK: When the figure itself can't be copied
    // A kept folder is its figure: with none, the folder is not made. These say why.

    /// Under the tiles, for a version whose listed size is over the cap.
    static func overCapSentence(size: Int) -> String {
        "At \(bytes(size)) it\u{2019}s over the 8 MB Capsid can copy here, so this version can\u{2019}t be kept."
    }

    /// After a keep in which Claude Science said the figure is over the cap (its
    /// size wasn't listed, or was listed wrong).
    static func figureTooBig(_ name: String) -> String {
        "\(name) is over 8 MB, which is more than Capsid can copy here, so nothing was kept. Choose another version, or Cancel."
    }

    /// After a keep in which the figure couldn't be written; `reason` is the disk's sentence.
    static func figureNotCopied(_ name: String, because reason: String) -> String {
        "\(name) wasn\u{2019}t copied, so nothing was kept. \(reason)"
    }

    /// Whether the plan's figure is known to be over the cap.
    static func figureOverCap(_ plan: KeepPlan) -> Bool {
        (plan.figure.size ?? 0) > cap
    }

    private static func answerRow(_ sources: KeepSources, chosen: String?) -> KeepRow {
        if let other = answerShowsAnother(sources, chosen: chosen) {
            // The answer is about another version: offered, but off unless ticked.
            return KeepRow(kind: .answer, title: "What Claude said about it",
                           detail: "Claude\u{2019}s answer shows \(versionName(other, in: sources.versions)), not this one.",
                           available: true, onByDefault: false, info: nil)
        }
        if let showing = sources.showing {
            let when = showing.at.map { " · the answer at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            let how = showing.how == .saved ? " Claude saved this version here; the reply after it may show a newer one." : ""
            return KeepRow(kind: .answer, title: "What Claude said about it",
                           detail: "\u{201C}\(excerpt(showing.text))\u{201D}\(when).\(how)",
                           available: true, onByDefault: true, info: nil)
        }
        if let last = sources.lastAnswer {
            let when = last.at.map { ", at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return KeepRow(kind: .answer, title: "What Claude said last",
                           detail: "The session\u{2019}s last answer\(when). The answer that shows this version wasn\u{2019}t found.",
                           available: true, onByDefault: true, info: nil)
        }
        return KeepRow(kind: .answer, title: "What Claude said about it",
                       detail: "Capsid couldn\u{2019}t find the answer that showed this version. The figure and its provenance can still be kept.",
                       available: false, onByDefault: false, info: nil)
    }

    /// The first ~90 characters of an answer, on one line.
    static func excerpt(_ text: String, limit: Int = 90) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.index(flat.startIndex, offsetBy: limit)
        let end = flat[..<cut].lastIndex(of: " ") ?? cut
        return String(flat[..<end]) + "\u{2026}"
    }

    /// The inputs that can be copied: saved in Claude Science (both ids),
    /// within the limit, not over the cap. `tooBig` lists the ones over it.
    static func copyableInputs(_ sources: KeepSources) -> (copyable: [LineageInput], tooBig: [LineageInput], unsaved: [LineageInput]) {
        guard let lineage = sources.lineage else { return ([], [], []) }
        var copyable: [LineageInput] = [], tooBig: [LineageInput] = [], unsaved: [LineageInput] = []
        // A lineage may list one input version twice (a file read by two cells):
        // its bytes are fetched, and kept, once. Listed beats inferred.
        var placed: [String: Int] = [:]
        for input in lineage.inputs.prefix(inputLimit) {
            guard input.fetchable, let v = input.v else { unsaved.append(input); continue }
            let big = sources.inputFacts[v]?.size.map { $0 > cap } ?? false
            if let at = placed[v] {
                if big {
                    if tooBig[at].inferred, !input.inferred { tooBig[at] = input }
                } else if copyable[at].inferred, !input.inferred {
                    copyable[at] = input
                }
                continue
            }
            if big {
                placed[v] = tooBig.count
                tooBig.append(input)
            } else {
                placed[v] = copyable.count
                copyable.append(input)
            }
        }
        return (copyable, tooBig, unsaved)
    }

    private static func dataRow(_ sources: KeepSources) -> KeepRow {
        let title = "The data it was drawn from"
        if sources.lineageFailed {
            return KeepRow(kind: .data, title: title, detail: "Couldn\u{2019}t read this version\u{2019}s provenance.",
                           available: false, onByDefault: false, info: nil)
        }
        guard let lineage = sources.lineage else {
            return KeepRow(kind: .data, title: title, detail: "Reading its provenance\u{2026}", available: false, onByDefault: false, info: nil)
        }
        if lineage.pending || lineage.mappingStatus == "pending" {
            return KeepRow(kind: .data, title: title,
                           detail: "Claude Science is still working out what this was drawn from. Try again in a minute.",
                           available: false, onByDefault: false, info: nil)
        }
        if lineage.inputs.isEmpty {
            return KeepRow(kind: .data, title: title, detail: "No source data recorded.", available: false, onByDefault: false,
                           info: "Claude Science lists no input files in this version\u{2019}s provenance. Capsid doesn\u{2019}t guess from file names.")
        }
        let (copyable, tooBig, unsaved) = copyableInputs(sources)
        if copyable.isEmpty {
            if !tooBig.isEmpty {
                return KeepRow(kind: .data, title: title, detail: "\(count(tooBig.count, "file")) · too big to keep here (over 8 MB).",
                               available: false, onByDefault: false, info: nil)
            }
            return KeepRow(kind: .data, title: title, detail: "Not saved in Claude Science, so Capsid can\u{2019}t copy it.",
                           available: false, onByDefault: false,
                           info: "\(count(unsaved.count, "input")) in this version\u{2019}s provenance \(unsaved.count == 1 ? "is" : "are") a file on the computer that ran the code, or a read Claude Science refused, with no copy of its own.")
        }
        let allInferred = copyable.allSatisfy(\.inferred)
        var detail: String
        if copyable.count == 1, let one = copyable.first, let v = one.v {
            detail = inputName(one, facts: sources.inputFacts[v])
            if let size = sources.inputFacts[v]?.size { detail += " · \(bytes(size))" }
        } else {
            let total = copyable.compactMap { $0.v.flatMap { sources.inputFacts[$0]?.size } }.reduce(0, +)
            detail = count(copyable.count, "file")
            if total > 0 { detail += " · \(bytes(total))" }
        }
        detail += allInferred ? " · inferred" : " · listed in its provenance"
        var notes: [String] = []
        if allInferred {
            notes.append("Detected by static analysis only — may not have contributed to this artifact.")
        }
        if !tooBig.isEmpty { notes.append("\(count(tooBig.count, "input")) over 8 MB won\u{2019}t be copied.") }
        if !unsaved.isEmpty { notes.append("\(count(unsaved.count, "input")) not saved in Claude Science can\u{2019}t be.") }
        if lineage.inputs.count > inputLimit { notes.append("Only the first \(inputLimit) of \(lineage.inputs.count) inputs are offered.") }
        let list = copyable.compactMap { input -> String? in
            guard let v = input.v else { return nil }
            var line = inputName(input, facts: sources.inputFacts[v])
            if let size = sources.inputFacts[v]?.size { line += " · \(bytes(size))" }
            return line
        }
        let info = (copyable.count > 1 ? list : []) + notes
        return KeepRow(kind: .data, title: title, detail: detail, available: true, onByDefault: !allInferred,
                       info: info.isEmpty ? nil : info.joined(separator: "\n"))
    }

    private static func codeRow(_ sources: KeepSources) -> KeepRow {
        let title = "The code that drew it"
        if sources.lineageFailed {
            return KeepRow(kind: .code, title: title, detail: "Couldn\u{2019}t read this version\u{2019}s provenance.",
                           available: false, onByDefault: false, info: nil)
        }
        guard let lineage = sources.lineage else {
            return KeepRow(kind: .code, title: title, detail: "Reading its provenance\u{2026}", available: false, onByDefault: false, info: nil)
        }
        if let code = lineage.code, !code.isEmpty {
            let name = scriptName(sources)
            return KeepRow(kind: .code, title: title, detail: "\(name) · \(bytes(code.utf8.count)) · Claude-generated reconstruction",
                           available: true, onByDefault: true,
                           info: "Claude Science reconstructs the script from the cells that made this version. It is the page\u{2019}s \u{201C}Download script\u{201D}, not a recording of what ran.")
        }
        if lineage.pending {
            return KeepRow(kind: .code, title: title, detail: "Generating reproduction code\u{2026}", available: false, onByDefault: false, info: nil)
        }
        if let reason = lineage.unavailableReason {
            let model = lineage.unavailableModel ?? "the model"
            let detail = reason == "not_enabled_for_org"
                ? "No reproduction code — \(model) is off for your organization"
                : "No reproduction code — \(model) isn\u{2019}t available"
            return KeepRow(kind: .code, title: title, detail: detail, available: false, onByDefault: false, info: nil)
        }
        let detail = lineage.hasCells ? "No reproduction code available for this version"
                                      : "No reproduction code — this version has no recorded execution"
        return KeepRow(kind: .code, title: title, detail: detail, available: false, onByDefault: false, info: nil)
    }

    /// The script's file name: the figure's stem and the language's extension.
    static func scriptName(_ sources: KeepSources) -> String {
        let figure = sources.chosenFacts?.name ?? sources.facts?.name ?? "figure"
        let stem = (figure as NSString).deletingPathExtension
        let ext: String = switch sources.lineage?.language?.lowercased() {
        case "python", "py": "py"
        case "r": "R"
        case "bash", "sh", "shell", "zsh": "sh"
        case "julia": "jl"
        case "javascript", "js": "js"
        default: "txt"
        }
        return "\(stem.isEmpty ? "script" : stem).\(ext)"
    }

    static func inputName(_ input: LineageInput, facts: ArtifactFacts?) -> String {
        if let name = facts?.name, !name.isEmpty { return name }
        if let name = input.name, !name.isEmpty { return name }
        if let file = input.file, !file.isEmpty { return file }
        return "input-\(String((input.v ?? "").prefix(8)))"
    }

    // MARK: The plan

    /// What to copy, from the choices. Nil until a version is chosen.
    static func plan(subject: KeepSubject, sources: KeepSources, choices: KeepChoices) -> KeepPlan? {
        guard let chosen = choices.version, !sources.gone.contains(chosen) else { return nil }
        let version = sources.versions.first { $0.v == chosen }
        let facts = sources.chosenFacts?.v == chosen ? sources.chosenFacts : (sources.facts?.v == chosen ? sources.facts : nil)
        let figureName = facts?.name ?? sources.facts?.name ?? subject.entry.name
        // Named as the Kept folder names its figure (`KeptLayout.figureFileName`): a file
        // called README.md would otherwise be refused by the disk (README.md is Capsid's),
        // and one called "data" would stand where the data folder goes.
        let figure = KeepItem(role: .figure, source: .download(version: chosen),
                              artifact: facts?.a ?? sources.facts?.a ?? subject.entry.artifact, version: chosen,
                              name: KeptLayout.figureFileName(figureName), size: facts?.size ?? version?.size ?? subject.entry.size,
                              sha: facts?.sha)
        var files: [KeepItem] = []
        var taken: Set<String> = [figure.name.lowercased()]
        func unique(_ name: String) -> String {
            let clean = ShelfFileName.sanitized(name)
            var candidate = clean
            var n = 2
            while taken.contains(candidate.lowercased()) || KeptLayout.isReadme(candidate) {
                candidate = ShelfFileName.numbered(clean, n)
                n += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
        let rows = rows(sources: sources, chosen: chosen)
        if choices.withData, rows.first(where: { $0.kind == .data })?.available == true {
            for input in copyableInputs(sources).copyable {
                guard let v = input.v else { continue }
                let facts = sources.inputFacts[v]
                files.append(KeepItem(role: .data, source: .download(version: v), artifact: input.a, version: v,
                                      name: unique(inputName(input, facts: facts)), size: facts?.size, sha: facts?.sha))
            }
        }
        if choices.withCode, rows.first(where: { $0.kind == .code })?.available == true, let code = sources.lineage?.code {
            // One path per version, the first kept: the script points there.
            let names = Dictionary(files.filter { $0.role == .data }.compactMap { item in
                item.version.map { ($0, item.relativePath) }
            }, uniquingKeysWith: { first, _ in first })
            let text = rewriteScript(code, kept: names)
            files.append(KeepItem(role: .code, source: .text(text), artifact: nil, version: chosen,
                                  name: unique(scriptName(sources)), size: text.utf8.count, sha: nil))
        }
        let answer: KeepAnswer? = choices.withAnswer
            ? (sources.showing.map { KeepAnswer(text: $0.text, at: $0.at, how: $0.how, isFallback: false, cut: sources.showingCut) }
                ?? sources.lastAnswer)
            : nil
        // Kept with another version than the one it shows: the README notes which.
        let answerShows = answer?.isFallback == false ? answerShowsAnother(sources, chosen: chosen) : nil
        return KeepPlan(figure: figure, files: files, answer: answer, answerShows: answerShows)
    }

    /// `{{artifact:<version id>}}` in the reconstruction names a file by its
    /// version; the kept copies are in `data/`, so the script points there
    /// (as the daemon's own script bundle rewrites them to its `inputs/`).
    /// A version that wasn't kept keeps its token, so nothing is pretended.
    static func rewriteScript(_ code: String, kept: [String: String]) -> String {
        var text = code
        for (version, path) in kept {
            text = text.replacingOccurrences(of: "{{artifact:\(version)}}", with: "../\(path)")
        }
        return text
    }

    // MARK: Sentences

    /// The footer: where it lands and what lands there.
    static func destinationSentence(root: URL, collection: String, folderName: String, plan: KeepPlan?,
                                    nameTaken: Bool, requested: String) -> String {
        let where_ = abbreviated(root.appendingPathComponent(collection).appendingPathComponent(folderName))
        guard let plan else { return "Into \(where_)." }
        var parts = [plan.figure.name]
        if plan.files.contains(where: { $0.role == .data }) { parts.append("data") }
        if plan.files.contains(where: { $0.role == .code }) { parts.append("code") }
        parts.append("a README.md")
        let list: String
        if parts.count == 1 {
            list = parts[0]
        } else {
            list = parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
        var sentence = "Into \(where_): \(list). About \(bytes(plan.totalBytes))."
        if nameTaken {
            sentence = "\u{201C}\(requested)\u{201D} is already kept in \(collection), so this one will be \u{201C}\(folderName)\u{201D}. " + sentence
        }
        return sentence
    }

    static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// "Kept 3 of 4 files. The data it was drawn from wasn't copied."
    static func outcomeSentence(_ outcome: KeepOutcome) -> String {
        var sentence: String
        if outcome.missing.isEmpty {
            sentence = "Kept \(count(outcome.total, "file"))."
        } else {
            let lead = "Kept \(outcome.kept) of \(count(outcome.total, "file"))."
            if outcome.missing.count == 1, let one = outcome.missing.first {
                sentence = "\(lead) \(roleTitle(one.role)) wasn\u{2019}t copied."
            } else {
                sentence = "\(lead) \(outcome.missing.count) weren\u{2019}t copied."
            }
        }
        if let clause = mismatchClause(outcome.mismatched.map(\.path)) {
            sentence += " \(clause)"
        }
        if let reason = outcome.recordFailed {
            sentence += " \(recordFailedSentence) \(reason)"
            if !sentence.hasSuffix(".") { sentence += "." }
        }
        return sentence
    }

    /// "z_prime.png doesn't match Claude Science's checksum; see README.md
    /// before you use it." Nil when every file matched.
    static func mismatchClause(_ paths: [String]) -> String? {
        guard let last = paths.last else { return nil }
        if paths.count == 1 {
            return "\(last) doesn\u{2019}t match Claude Science\u{2019}s checksum; see README.md before you use it."
        }
        let names = paths.dropLast().joined(separator: ", ") + " and " + last
        return "\(names) don\u{2019}t match Claude Science\u{2019}s checksums; see README.md before you use them."
    }

    /// After files landed in a kept folder and its README couldn't be rewritten.
    static let recordFailedSentence = "The files landed, but README.md couldn\u{2019}t be updated to list them."

    /// The sheet's status once the folder is being put in place: no count any
    /// more, and Cancel is off (`KeepModel.isFinishing`).
    static let finishingSentence = "Finishing\u{2026}"
    /// Why Cancel is off then (its tooltip).
    static let finishingHelp = "The folder is being put in place. It can\u{2019}t be cancelled now."


    static func roleTitle(_ role: KeptRole) -> String {
        switch role {
        case .figure: "The figure"
        case .data: "The data it was drawn from"
        case .code: "The code that drew it"
        case .input: "The raw input"
        }
    }

    static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    // MARK: The README

    /// The record and the readable text for a kept folder.
    static func record(subject: KeepSubject, sources: KeepSources, plan: KeepPlan, folderName: String, keptAt: Date,
                       copied: [KeptFile], missing: [KeptMissing], scienceVersion: String?, capsidVersion: String) -> (KeptRecord, KeptText) {
        let versions = sources.versions
        let index = versions.first { $0.v == plan.figure.version }?.n
        let figure = copied.first { $0.role == .figure }
            ?? KeptFile(path: plan.figure.name, role: .figure, artifact: plan.figure.artifact, version: plan.figure.version,
                        index: index, of: versions.isEmpty ? nil : versions.count, sha256: plan.figure.sha, bytes: plan.figure.size ?? 0)
        let record = KeptRecord(
            name: folderName, keptAt: keptAt,
            projectID: subject.session.projectID, projectName: subject.session.projectName,
            sessionID: subject.session.id, sessionTitle: subject.session.displayTitle,
            figure: KeptFile(path: figure.path, role: .figure, artifact: figure.artifact, version: figure.version,
                             index: index, of: versions.isEmpty ? nil : versions.count, sha256: figure.sha256, bytes: figure.bytes,
                             expectedSha256: figure.expectedSha256),
            files: copied.filter { $0.role != .figure }, missing: missing,
            claudeScience: scienceVersion ?? "unknown", capsid: capsidVersion,
            answerShowsVersion: plan.answerShows.flatMap { shown in versions.first { $0.v == shown }?.n })
        var attribution: String
        if let answer = plan.answer {
            let when = answer.at.map { " at \(longTime($0)) on \(longDate($0))" } ?? ""
            attribution = answer.isFallback
                ? "From Claude\u{2019}s last answer in the session\(when). The answer that shows this version wasn\u{2019}t found."
                : "From Claude\u{2019}s answer\(when)."
            if let shown = plan.answerShows {
                attribution += " That answer shows \(versionName(shown, in: versions)), not this one."
            }
            if answer.cut { attribution += " \(KeptReadme.cutSentence)" }
        } else {
            attribution = ""
        }
        var origin = "[\(subject.session.displayTitle)](\(deepLink(subject.session))), in \(subject.session.projectName).\n"
        if let index, !versions.isEmpty {
            origin += "Version \(index) of \(versions.count) of \(figure.path), "
        } else {
            origin += "\(figure.path), "
        }
        origin += "kept on \(longDate(keptAt)) at \(longTime(keptAt)) by Capsid \(capsidVersion), from Claude Science \(scienceVersion ?? "an unknown version"). The link opens the session in Capsid on a Mac that has it."
        let text = KeptText(legend: "", claudeSaid: plan.answer?.text ?? "", attribution: attribution, origin: origin)
        return (record, text)
    }

    /// `bench://session?project=<id>&frame=<id>`, which `Router` opens.
    static func deepLink(_ session: SessionStatus) -> String {
        "bench://session?project=\(session.projectID)&frame=\(session.id)"
    }

    /// "22 October 2026": written out, since the file may be read anywhere.
    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    static func longTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
