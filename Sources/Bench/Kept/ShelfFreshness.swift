// ShelfFreshness.swift — whether a Shelf item is still the newest of what it
// came from (DESIGN.md, Shelf). A kept folder's README records the figure's
// artifact and version ids and, when it was kept with data and code, the ids of
// its input files. Capsid asks Claude Science for each artifact's list of
// versions and compares: if the figure has a newer version, or an input does,
// the item is marked out of date.
//
// The rule that shapes everything here is that a mark is a claim, so it is made
// only on evidence. A daemon that is down, a timeout, a signed-out session or a
// list that can't be read teaches nothing, and teaches nothing is never shown
// as a warning: the verdict is `.unknown` and the card carries no mark. An
// input that has gone away is not called out either, because the figure itself
// is still what was kept. Only a figure whose own version Claude Science no
// longer lists is called gone.
//
// Pure: the reads are made elsewhere (`ShelfTransfers`) and handed in as
// answers keyed by artifact id. Nothing here touches the disk or the network.
import Foundation

/// What one read of an artifact's versions came to, reduced to the three things
/// the verdict can use.
enum VersionsAnswer: Equatable, Sendable {
    /// The artifact's versions, oldest first.
    case versions([ArtifactVersion])
    /// Claude Science says the artifact isn't there any more (404 or 410).
    case gone
    /// Nothing was learned: offline, the daemon down, timed out, unreadable, signed out.
    case unknown

    /// `nil` when there is no answer to give because the asker left (the read
    /// was cancelled); everything that went wrong on the way is `.unknown`.
    static func from(_ result: ShelfTransferResult) -> VersionsAnswer? {
        switch result {
        case .cancelled:
            return nil
        case .timedOut, .notReady:
            return .unknown
        case .answered(let outcome):
            switch outcome {
            case .versions(let versions): return .versions(versions)
            case .missing: return .gone
            case .cancelled: return nil
            default: return .unknown
            }
        }
    }
}

/// An input file whose artifact has a newer version than the one kept.
struct InputChange: Equatable, Sendable {
    /// The last component of the file's path: "z_prime_by_plate.csv".
    let name: String
    /// The version number that was kept.
    let kept: Int
    /// The newest version number.
    let newest: Int
}

/// The verdict for one Shelf item.
enum ShelfFreshness: Equatable, Sendable {
    /// Nothing could be learned, so nothing is shown.
    case unknown
    /// The figure, and every input that could be read, is the newest.
    case current
    case stale(Stale)
    /// The kept figure version isn't in Claude Science any more.
    case gone

    struct Stale: Equatable, Sendable {
        /// The newest version, when it is newer than the one kept.
        var newerFigure: ArtifactVersion?
        /// The number of the kept version, when it is known.
        var keptNumber: Int?
        var inputs: [InputChange]
    }

    var isOutOfDate: Bool {
        if case .stale = self { return true }
        return false
    }

    /// What to tell the person, the figure first. Empty for `.current` and `.unknown`.
    var sentences: [String] {
        switch self {
        case .unknown, .current:
            return []
        case .gone:
            return ["This version isn\u{2019}t in Claude Science any more."]
        case .stale(let stale):
            var out: [String] = []
            if let newer = stale.newerFigure {
                if let kept = stale.keptNumber {
                    out.append("A newer version of this figure exists (version \(kept) \u{2192} \(newer.n)).")
                } else {
                    out.append("A newer version of this figure exists.")
                }
            }
            if let first = stale.inputs.first {
                var detail = "\(first.name), version \(first.kept) \u{2192} \(first.newest)"
                let more = stale.inputs.count - 1
                if more > 0 {
                    detail += ", and \(more) more file\(more == 1 ? "" : "s")"
                }
                out.append("The data behind this figure changed after you kept it (\(detail)).")
            }
            return out
        }
    }
}

enum ShelfFreshnessRules {
    /// The input files to compare: data and inputs that carry both ids, each
    /// version once, in the record's order. Code and Claude's legend are not
    /// what the figure was made from.
    static func inputs(of record: KeptRecord) -> [KeptFile] {
        var seen = Set<String>()
        var out: [KeptFile] = []
        for file in record.files where file.role == .data || file.role == .input {
            guard file.artifact != nil, let version = file.version else { continue }
            if seen.insert(version).inserted { out.append(file) }
        }
        return out
    }

    /// The artifacts to ask about: the figure's first (when it has both ids),
    /// then the inputs', each once.
    static func artifacts(of record: KeptRecord) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ id: String?) {
            if let id, seen.insert(id).inserted { out.append(id) }
        }
        if record.figure.version != nil { add(record.figure.artifact) }
        for file in inputs(of: record) { add(file.artifact) }
        return out
    }

    /// The newest of a list: the greatest number, and the last of any tie.
    private static func newest(of list: [ArtifactVersion]) -> ArtifactVersion? {
        var best: ArtifactVersion?
        for version in list where best == nil || version.n >= best!.n { best = version }
        return best
    }

    private enum Part { case unknown, current, newer }

    static func verdict(for record: KeptRecord, answers: [String: VersionsAnswer]) -> ShelfFreshness {
        var stale = ShelfFreshness.Stale(newerFigure: nil, keptNumber: nil, inputs: [])
        var figure = Part.unknown

        if let artifact = record.figure.artifact, let version = record.figure.version,
           let answer = answers[artifact] {
            switch answer {
            case .gone:
                return .gone
            case .unknown:
                break
            case .versions(let list):
                guard let kept = list.first(where: { $0.v == version }) else { return .gone }
                if let top = newest(of: list), top.n > kept.n {
                    stale.newerFigure = top
                    stale.keptNumber = kept.n
                    figure = .newer
                } else {
                    figure = .current
                }
            }
        }

        var anyInputCurrent = false
        for file in inputs(of: record) {
            guard let artifact = file.artifact, let version = file.version,
                  case .versions(let list)? = answers[artifact] else { continue }
            let keptNumber = list.first(where: { $0.v == version })?.n ?? file.index
            guard let keptNumber, let top = newest(of: list) else { continue }
            if top.v != version && top.n > keptNumber {
                let name = file.path.split(separator: "/").last.map(String.init) ?? file.path
                stale.inputs.append(InputChange(name: name, kept: keptNumber, newest: top.n))
            } else {
                anyInputCurrent = true
            }
        }

        if figure == .newer || !stale.inputs.isEmpty { return .stale(stale) }
        if figure == .current || (figure == .unknown && anyInputCurrent) { return .current }
        return .unknown
    }

    /// The small mark on a card; nothing when there is nothing to warn about.
    static func shortLabel(_ f: ShelfFreshness) -> String? {
        switch f {
        case .stale: return "Out of date"
        case .gone: return "Not in Claude Science"
        case .unknown, .current: return nil
        }
    }

    static func countOutOfDate(_ verdicts: [ShelfFreshness]) -> Int {
        verdicts.filter(\.isOutOfDate).count
    }
}
