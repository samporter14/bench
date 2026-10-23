// KeptReadme.swift — the README a kept folder carries, and what is read back
// from it (DESIGN.md, Kept). Keep stores nothing but the folders: the README is
// the record. Its front matter holds everything the Kept window needs (the
// names, the ids, which version of the figure, every file with its checksum and
// size, what could not be copied); the sections under it are for a person: the
// legend they write, Claude's words, where it all came from.
//
// The renderer and the parser are a pair, and the parser is strict on purpose.
// It is not a YAML parser: it reads only the shape the renderer writes (inline
// maps for the project, the session and the figure, one `- { … }` row for each
// file and each missing file, strings in double quotes, and four optional lines
// after the figure, each only when there is something to say and in this order:
// `answer_shows_version:` when Claude's words were kept with another version
// than the one they show, and the Shelf's three, `source_row:` (the history row
// of the message that showed the figure), `question:` (what the user asked in
// that exchange) and `answer_at:` (when that message was sent)), in that order,
// and answers nil for anything else, so a folder it can't read is never half
// shown and is never touched. `render` then `parse` then `render` gives the same
// bytes, which `KeptReadmeTests` checks with names in every script.
//
// Ownership: the record owns the front matter, the title line, the "Not
// copied" rows and the "Checksums" rows (one for each file whose bytes don't
// match Claude Science's checksum). The four `KeptText` fields are the bodies of the sections and
// are written as given and read back as written. (An empty `origin` is made
// from the record; `origin(for:)` and `attribution(answerAt:)` make the
// usual ones, with the dates written out in English and the time the way the
// Mac writes it.) Capsid changes only "Your legend" afterwards, and
// `replacingLegend` leaves every other byte of the file as it was.
//
// A string in the front matter is escaped as in a YAML double-quoted string:
// `\"`, `\\`, `\n`, `\r`, `\t`, and `\uXXXX` for the other control characters
// and the line separators, so a name with a line break in it still fits on one
// line. A line in a free-text body that would start a section ("## …", with
// any backslashes before it) gets a backslash in front, which the parser takes
// off, so what a person writes in their legend can never end the legend early.
// Nothing here touches the disk.
import Foundation

/// What a kept file is for, and so where it goes (`KeptLayout`).
enum KeptRole: String, Sendable, Equatable, CaseIterable {
    case figure, data, code, input
}

/// One file of a keep: the figure, or a file beside it.
struct KeptFile: Equatable, Sendable {
    /// Relative to the kept folder: "z_prime.png" for the figure (its file
    /// name), "data/z_prime_by_plate.csv" for the rest.
    var path: String
    var role: KeptRole
    var artifact: String?
    var version: String?
    /// Which version of the artifact this is, of `of`: "version 3 of 4".
    var index: Int?
    var of: Int?
    var sha256: String?
    var bytes: Int
    /// Claude Science's checksum for this version when the bytes kept don't
    /// match it (`sha256` is theirs): kept anyway, and the README says so.
    var expectedSha256: String? = nil
}

/// Something that was meant to be kept and wasn't, with the reason.
struct KeptMissing: Equatable, Sendable {
    var role: KeptRole
    var name: String
    var reason: String
}

/// The front matter: what the Kept window needs without reading anything else.
struct KeptRecord: Equatable, Sendable {
    var name: String
    var keptAt: Date
    var projectID: String
    var projectName: String
    var sessionID: String
    var sessionTitle: String
    /// Always role `.figure`, whatever is set here: the README has one place for it.
    var figure: KeptFile
    var files: [KeptFile]
    var missing: [KeptMissing]
    var claudeScience: String
    var capsid: String
    /// Claude's words were kept with another version than the one they show:
    /// that version's number (`answer_shows_version:`, written only then).
    var answerShowsVersion: Int? = nil
    /// The Shelf's three, each written only when known. The history row of the
    /// message that showed the figure (`source_row:`), which "Show Where It
    /// Came From" opens the reference reader at.
    var sourceRow: Int? = nil
    /// What the user asked in that exchange (`question:`).
    var question: String? = nil
    /// When the message that showed the figure was sent (`answer_at:`).
    var answerAt: Date? = nil
}

/// The readable sections.
struct KeptText: Equatable, Sendable {
    /// What the person wrote; empty until they do.
    var legend: String
    /// Claude's words, without the quote marks.
    var claudeSaid: String
    /// "From Claude’s answer at 8:12 AM on 22 October 2026.": a plain paragraph
    /// that doesn't start with ">".
    var attribution: String
    /// The "Where it came from" body. Empty on the way in means the usual one
    /// (`KeptReadme.origin(for:)`); what `parse` returns is what the file holds.
    var origin: String
}

enum KeptReadme {
    static let legendHeading = "## Your legend"
    static let saidHeading = "## What Claude said"
    static let originHeading = "## Where it came from"
    static let missingHeading = "## Not copied"
    static let checksumHeading = "## Checksums"
    static let legendComment = "<!-- Write the legend here, or in Capsid’s Shelf window. -->"
    /// What the comment said while the window was called Kept: read as an empty legend all the same.
    static let legacyLegendComment = "<!-- Write the legend here, or in Capsid’s Kept window. -->"
    static let finePrint = "Capsid changes only the “Your legend” section of this file, and only when you edit it in the Shelf window."
    /// The optional lines of the front matter, right after `figure:`, in this order.
    static let answerShowsKey = "answer_shows_version"
    static let sourceRowKey = "source_row"
    static let questionKey = "question"
    static let answerAtKey = "answer_at"

    // MARK: Rendering

    /// The README, in full. `timeZone` is the zone `kept_at` and the dates in
    /// the usual `origin` are written in (the Mac's, unless a test pins one);
    /// `locale` is how the usual `origin` writes the time.
    static func render(_ record: KeptRecord, text: KeptText,
                       timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var front = ["---", "capsid_kept: 1"]
        front.append("name: \(quoted(record.name))")
        front.append("kept_at: \(rfc3339(record.keptAt, timeZone: timeZone))")
        front.append("project: { id: \(quoted(record.projectID)), name: \(quoted(record.projectName)) }")
        front.append("session: { id: \(quoted(record.sessionID)), title: \(quoted(record.sessionTitle)) }")
        front.append("figure: \(figureMap(record.figure))")
        if let shown = record.answerShowsVersion { front.append("\(answerShowsKey): \(shown)") }
        if let row = record.sourceRow { front.append("\(sourceRowKey): \(row)") }
        if let question = record.question { front.append("\(questionKey): \(quoted(question))") }
        if let answerAt = record.answerAt { front.append("\(answerAtKey): \(rfc3339(answerAt, timeZone: timeZone))") }
        front += rows("files", record.files.map(fileMap))
        front += rows("missing", record.missing.map(missingMap))
        front.append("claude_science: \(quoted(record.claudeScience))")
        front.append("capsid: \(quoted(record.capsid))")
        front.append("---")

        var out = front.joined(separator: "\n") + "\n\n"
        out += "# \(oneLine(record.name))\n\n"

        let legend = block(text.legend)
        out += section(legendHeading, legend.isEmpty ? legendComment : legend)

        var said: [String] = []
        if !text.claudeSaid.isEmpty { said.append(quote(text.claudeSaid)) }
        let attribution = block(text.attribution)
        if !attribution.isEmpty { said.append(attribution) }
        out += section(saidHeading, said.joined(separator: "\n\n"))

        let origin = block(text.origin)
        out += section(originHeading, origin.isEmpty
            ? self.origin(for: record, timeZone: timeZone, locale: locale)
            : origin)

        if !record.missing.isEmpty {
            out += section(missingHeading, record.missing.map { "- \(notCopied($0))" }.joined(separator: "\n"))
        }
        let unmatched = mismatched(record)
        if !unmatched.isEmpty {
            out += section(checksumHeading, unmatched.map { "- \(checksumSentence($0))" }.joined(separator: "\n"))
        }
        out += "---\n\n\(finePrint)\n"
        return out
    }

    /// "## X", a blank line, the body and a blank line; nothing after the
    /// heading's blank line when the body is empty.
    private static func section(_ heading: String, _ body: String) -> String {
        "\(heading)\n\n" + (body.isEmpty ? "" : body + "\n\n")
    }

    /// The two lines under "Where it came from": the link to the session, and
    /// which version of the figure this is, when it was kept, by what.
    static func origin(for record: KeptRecord, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let title = oneLine(record.sessionTitle).isEmpty ? "Session" : oneLine(record.sessionTitle)
        let linkText = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let link = "bench://session?project=\(encoded(record.projectID))&frame=\(encoded(record.sessionID))"
        var first = "[\(linkText)](\(link))"
        if !oneLine(record.projectName).isEmpty { first += ", in \(oneLine(record.projectName))" }
        first += "."

        let file = oneLine(record.figure.path)
        var second: String
        if let index = record.figure.index, let of = record.figure.of {
            second = "Version \(index) of \(of) of \(file)"
        } else {
            second = file
        }
        second += ", kept on \(englishDate(record.keptAt, timeZone: timeZone)) at \(shortTime(record.keptAt, timeZone: timeZone, locale: locale))"
        second += " by Capsid" + (record.capsid.isEmpty ? "" : " \(oneLine(record.capsid))")
        if !record.claudeScience.isEmpty { second += ", from Claude Science \(oneLine(record.claudeScience))" }
        second += ". The link opens the session in Capsid on a Mac that has it."
        return first + "\n" + second
    }

    /// Said after the attribution when words kept here are cut: a long turn the
    /// page cut at 2,000 characters, and its rest couldn't be read in time.
    static let cutSentence = "The text is cut off: the rest couldn\u{2019}t be read."

    /// "From Claude’s answer at 8:12 AM on 22 October 2026."
    static func attribution(answerAt date: Date?, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let date else { return "From Claude’s answer." }
        return "From Claude’s answer at \(shortTime(date, timeZone: timeZone, locale: locale)) on \(englishDate(date, timeZone: timeZone))."
    }

    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                 "September", "October", "November", "December"]

    /// "22 October 2026": English whatever the Mac's language, because the file
    /// is read by people and programs on other Macs.
    static func englishDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.day ?? 1) \(months[((parts.month ?? 1) - 1) % 12]) \(parts.year ?? 1970)"
    }

    /// The Mac's short time ("9:12 AM", "09:12"), with an ordinary space where
    /// the system puts a narrow no-break one, so the text can be searched for.
    static func shortTime(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func notCopied(_ missing: KeptMissing) -> String {
        let what: String
        switch missing.role {
        case .figure: what = "The figure"
        case .data: what = "The data file"
        case .code: what = "The script"
        case .input: what = "The raw input"
        }
        return "\(what), \(oneLine(missing.name)): \(oneLine(missing.reason))."
    }

    /// The figure and the files kept whose bytes don't match Claude Science's checksum.
    static func mismatched(_ record: KeptRecord) -> [KeptFile] {
        ([record.figure] + record.files).filter { $0.expectedSha256 != nil }
    }

    /// "z_prime.png doesn’t match Claude Science’s checksum for this version
    /// (expected 3f2a9c41…, got 9c41d2e0…). It may be a reference file that
    /// changed since; check it before you use it."
    static func checksumSentence(_ file: KeptFile) -> String {
        func short(_ sha: String?) -> String {
            guard let sha, !sha.isEmpty else { return "none" }
            return sha.count > 8 ? String(oneLine(sha).prefix(8)) + "…" : oneLine(sha)
        }
        return "\(oneLine(file.path)) doesn’t match Claude Science’s checksum for this version "
            + "(expected \(short(file.expectedSha256)), got \(short(file.sha256))). "
            + "It may be a reference file that changed since; check it before you use it."
    }

    private static func encoded(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? id
    }

    /// Line breaks become blanks: for the places a single line is needed.
    private static func oneLine(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0 == "\n" || $0 == "\r" ? " " : $0 }))
    }

    // MARK: Front matter, written

    private static func rows(_ key: String, _ maps: [String]) -> [String] {
        maps.isEmpty ? ["\(key): []"] : ["\(key):"] + maps.map { "  - \($0)" }
    }

    private static func figureMap(_ file: KeptFile) -> String {
        var fields = ["file: \(quoted(file.path))"]
        fields += common(file)
        return "{ \(fields.joined(separator: ", ")) }"
    }

    private static func fileMap(_ file: KeptFile) -> String {
        var fields = ["path: \(quoted(file.path))", "role: \(file.role.rawValue)"]
        fields += common(file)
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// artifact, version, index, of, sha256, expected_sha256, bytes: each but
    /// bytes only when there is one.
    private static func common(_ file: KeptFile) -> [String] {
        var fields: [String] = []
        if let artifact = file.artifact { fields.append("artifact: \(quoted(artifact))") }
        if let version = file.version { fields.append("version: \(quoted(version))") }
        if let index = file.index { fields.append("index: \(index)") }
        if let of = file.of { fields.append("of: \(of)") }
        if let sha = file.sha256 { fields.append("sha256: \(quoted(sha))") }
        if let expected = file.expectedSha256 { fields.append("expected_sha256: \(quoted(expected))") }
        fields.append("bytes: \(file.bytes)")
        return fields
    }

    private static func missingMap(_ missing: KeptMissing) -> String {
        "{ role: \(missing.role.rawValue), name: \(quoted(missing.name)), reason: \(quoted(missing.reason)) }"
    }

    /// A double-quoted string with `"` and `\` escaped, and the characters that
    /// would break a line or be unseen escaped as YAML does.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                let v = scalar.value
                if v < 0x20 || (0x7F...0x9F).contains(v) || v == 0x2028 || v == 0x2029 {
                    let hex = String(v, radix: 16, uppercase: true)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// "2026-10-22T09:12:00-04:00": whole seconds, the zone's offset.
    static func rfc3339(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ n: Int?, _ width: Int) -> String {
            let digits = String(abs(n ?? 0))
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        let offset = timeZone.secondsFromGMT(for: date)
        let minutes = abs(offset) / 60
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))T\(pad(c.hour, 2)):\(pad(c.minute, 2)):\(pad(c.second, 2))"
            + "\(offset < 0 ? "-" : "+")\(pad(minutes / 60, 2)):\(pad(minutes % 60, 2))"
    }

    // MARK: Free text, written

    /// The lines of a text, split at line feeds alone (a "\r" stays at the end
    /// of its line, so a file with Windows line ends is read back as written).
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
    }

    private static func isBlank(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
    }

    /// Lines without the blank ones at either end.
    private static func trimmed(_ lines: [String]) -> [String] {
        var lines = lines[...]
        while let first = lines.first, isBlank(first) { lines.removeFirst() }
        while let last = lines.last, isBlank(last) { lines.removeLast() }
        return Array(lines)
    }

    /// Whether the line would start a section: "## " after any backslashes.
    private static func startsSection(escaped line: String) -> Bool {
        line.drop(while: { $0 == "\\" }).hasPrefix("## ")
    }

    /// A free-text body as it is written: no blank lines at the ends, and a
    /// backslash before any line that would otherwise start a section.
    private static func block(_ text: String) -> String {
        trimmed(lines(text)).map { startsSection(escaped: $0) ? "\\" + $0 : $0 }.joined(separator: "\n")
    }

    /// The reverse of `block`.
    private static func unblock(_ lines: [String]) -> String {
        trimmed(lines).map { line in
            line.hasPrefix("\\") && startsSection(escaped: line) ? String(line.dropFirst()) : line
        }.joined(separator: "\n")
    }

    /// Every line behind "> " (an empty one behind ">").
    private static func quote(_ text: String) -> String {
        lines(text).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    // MARK: Parsing

    /// The record and the sections, or nil when the file is not a README this
    /// renderer made (no `capsid_kept: 1`, front matter out of order, a
    /// malformed row, a missing section or footer). Sections are read in
    /// order: "Your legend", "What Claude said", "Where it came from", then
    /// "Not copied" and "Checksums" when they are there; a heading of anyone else's between them
    /// is passed over, so a person's own notes never hide a folder.
    static func parse(_ markdown: String) -> (record: KeptRecord, text: KeptText)? {
        var all = lines(markdown)
        if all.first?.hasPrefix("\u{FEFF}") == true { all[0].removeFirst() }
        guard let front = parseFrontMatter(all) else { return nil }
        let rest = Array(all[front.next...])

        // The title line, then the sections, then the footer.
        guard let title = rest.firstIndex(where: { !isBlank($0) }), rest[title].hasPrefix("# "),
              !rest[title].hasPrefix("## ") else { return nil }
        guard let divider = rest.lastIndex(of: "---"), divider > title,
              rest[(divider + 1)...].contains(where: { !isBlank($0) }) else { return nil }
        let body = Array(rest[(title + 1)..<divider])

        var sections: [(heading: String, lines: [String])] = []
        for line in body {
            if line.hasPrefix("## ") {
                sections.append((line, []))
            } else if sections.isEmpty {
                guard isBlank(line) else { return nil }
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        let known = [legendHeading, saidHeading, originHeading, missingHeading, checksumHeading]
        let order = sections.map(\.heading).filter(known.contains)
        let base = [legendHeading, saidHeading, originHeading]
        guard order == base || order == base + [missingHeading] || order == base + [checksumHeading]
            || order == base + [missingHeading, checksumHeading] else { return nil }
        func bodyLines(of heading: String) -> [String] { sections.first { $0.heading == heading }?.lines ?? [] }

        let legendLines = trimmed(bodyLines(of: legendHeading))
        let legend = legendLines == [legendComment] || legendLines == [legacyLegendComment] ? "" : unblock(legendLines)

        var said = trimmed(bodyLines(of: saidHeading))
        var quoted: [String] = []
        while let line = said.first, line.hasPrefix(">") {
            if line == ">" {
                quoted.append("")
            } else if line.hasPrefix("> ") {
                quoted.append(String(line.dropFirst(2)))
            } else {
                return nil
            }
            said.removeFirst()
        }
        let text = KeptText(legend: legend, claudeSaid: quoted.joined(separator: "\n"),
                            attribution: unblock(said), origin: unblock(bodyLines(of: originHeading)))
        return (front.record, text)
    }

    /// The README with only the legend changed: the lines between "## Your
    /// legend" and the next "## " heading become the new legend (the comment
    /// again when it is empty), and every other byte stays. Nil when either
    /// heading isn't there.
    static func replacingLegend(in markdown: String, with legend: String) -> String? {
        var all = lines(markdown)
        guard let start = all.firstIndex(of: legendHeading),
              let end = all[(start + 1)...].firstIndex(where: { $0.hasPrefix("## ") }) else { return nil }
        let body = block(legend)
        all.replaceSubrange((start + 1)..<end, with: ["", body.isEmpty ? legendComment : body, ""].flatMap { lines($0) })
        return all.joined(separator: "\n")
    }

    // MARK: Front matter, read

    private enum Value {
        case string(String)
        case bare(String)
    }

    private enum Kind { case string, int, role }

    private struct Field {
        let key: String
        let optional: Bool
        let kind: Kind
        init(_ key: String, _ kind: Kind, optional: Bool = false) {
            self.key = key
            self.kind = kind
            self.optional = optional
        }
    }

    private static let fileFields = [Field("artifact", .string, optional: true), Field("version", .string, optional: true),
                                     Field("index", .int, optional: true), Field("of", .int, optional: true),
                                     Field("sha256", .string, optional: true), Field("expected_sha256", .string, optional: true),
                                     Field("bytes", .int)]

    private static func parseFrontMatter(_ all: [String]) -> (record: KeptRecord, next: Int)? {
        var i = 0
        func next() -> String? {
            defer { i += 1 }
            return i < all.count ? all[i] : nil
        }
        func value(_ key: String) -> String? {
            guard let line = next(), line.hasPrefix("\(key): ") else { return nil }
            return String(line.dropFirst(key.count + 2))
        }
        func string(_ key: String) -> String? {
            guard let raw = value(key), let (text, end) = readQuoted(raw, from: raw.unicodeScalars.startIndex),
                  end == raw.unicodeScalars.endIndex else { return nil }
            return text
        }
        func map(_ key: String, _ fields: [Field]) -> [String: Value]? {
            guard let raw = value(key) else { return nil }
            return readMap(raw, fields)
        }
        func list(_ key: String, _ fields: [Field]) -> [[String: Value]]? {
            guard let line = next() else { return nil }
            if line == "\(key): []" { return [] }
            guard line == "\(key):" else { return nil }
            var rows: [[String: Value]] = []
            while i < all.count, all[i].hasPrefix("  - ") {
                guard let row = readMap(String(all[i].dropFirst(4)), fields) else { return nil }
                rows.append(row)
                i += 1
            }
            return rows.isEmpty ? nil : rows
        }
        func text(_ values: [String: Value], _ key: String) -> String? {
            if case .string(let text)? = values[key] { return text }
            return nil
        }
        func number(_ values: [String: Value], _ key: String) -> Int? {
            if case .bare(let digits)? = values[key] { return Int(digits) }
            return nil
        }
        func file(_ values: [String: Value], path: String, role: KeptRole) -> KeptFile? {
            guard let bytes = number(values, "bytes") else { return nil }
            return KeptFile(path: path, role: role, artifact: text(values, "artifact"), version: text(values, "version"),
                            index: number(values, "index"), of: number(values, "of"), sha256: text(values, "sha256"),
                            bytes: bytes, expectedSha256: text(values, "expected_sha256"))
        }
        /// An optional `key: <digits>` line. Not there: `.some(nil)`, and the
        /// line is left for the next key. There but not a number: nil.
        func optionalNumber(_ key: String) -> Int?? {
            guard i < all.count, all[i].hasPrefix("\(key): ") else { return .some(nil) }
            let digits = all[i].dropFirst(key.count + 2)
            i += 1
            guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
                  let number = Int(digits) else { return nil }
            return .some(number)
        }

        /// An optional `key: "<string>"` line, as `optionalNumber`.
        func optionalString(_ key: String) -> String?? {
            guard i < all.count, all[i].hasPrefix("\(key): ") else { return .some(nil) }
            let raw = String(all[i].dropFirst(key.count + 2))
            i += 1
            guard let (text, end) = readQuoted(raw, from: raw.unicodeScalars.startIndex),
                  end == raw.unicodeScalars.endIndex else { return nil }
            return .some(text)
        }
        /// An optional `key: <time>` line, as `optionalNumber`.
        func optionalDate(_ key: String) -> Date?? {
            guard i < all.count, all[i].hasPrefix("\(key): ") else { return .some(nil) }
            let raw = String(all[i].dropFirst(key.count + 2))
            i += 1
            guard let parsed = date(rfc3339: raw) else { return nil }
            return .some(parsed)
        }

        guard next() == "---", next() == "capsid_kept: 1",
              let name = string("name"),
              let keptAt = value("kept_at").flatMap(date(rfc3339:)),
              let project = map("project", [Field("id", .string), Field("name", .string)]),
              let session = map("session", [Field("id", .string), Field("title", .string)]),
              let figureValues = map("figure", [Field("file", .string)] + fileFields),
              let figurePath = text(figureValues, "file"),
              let figure = file(figureValues, path: figurePath, role: .figure),
              let answerShows = optionalNumber(answerShowsKey),
              let sourceRow = optionalNumber(sourceRowKey),
              let question = optionalString(questionKey),
              let answerAt = optionalDate(answerAtKey),
              let fileRows = list("files", [Field("path", .string), Field("role", .role)] + fileFields),
              let missingRows = list("missing", [Field("role", .role), Field("name", .string), Field("reason", .string)]),
              let claudeScience = string("claude_science"),
              let capsid = string("capsid"),
              next() == "---",
              let projectID = text(project, "id"), let projectName = text(project, "name"),
              let sessionID = text(session, "id"), let sessionTitle = text(session, "title") else { return nil }

        var files: [KeptFile] = []
        for row in fileRows {
            guard let path = text(row, "path"), case .bare(let word)? = row["role"], let role = KeptRole(rawValue: word),
                  let kept = file(row, path: path, role: role) else { return nil }
            files.append(kept)
        }
        var missing: [KeptMissing] = []
        for row in missingRows {
            guard case .bare(let word)? = row["role"], let role = KeptRole(rawValue: word),
                  let name = text(row, "name"), let reason = text(row, "reason") else { return nil }
            missing.append(KeptMissing(role: role, name: name, reason: reason))
        }
        let record = KeptRecord(name: name, keptAt: keptAt, projectID: projectID, projectName: projectName,
                                sessionID: sessionID, sessionTitle: sessionTitle, figure: figure, files: files,
                                missing: missing, claudeScience: claudeScience, capsid: capsid,
                                answerShowsVersion: answerShows, sourceRow: sourceRow, question: question, answerAt: answerAt)
        return (record, i)
    }

    /// `{ key: value, key: value }` with the fields in the order given, the
    /// optional ones left out when there is nothing to say, and each value of
    /// its kind; nil for anything else.
    private static func readMap(_ raw: String, _ fields: [Field]) -> [String: Value]? {
        let s = raw.unicodeScalars
        var i = s.startIndex
        func expect(_ literal: String) -> Bool {
            var j = i
            for scalar in literal.unicodeScalars {
                guard j < s.endIndex, s[j] == scalar else { return false }
                j = s.index(after: j)
            }
            i = j
            return true
        }
        guard expect("{ ") else { return nil }
        var pairs: [(String, Value)] = []
        while true {
            var key = ""
            while i < s.endIndex, s[i] == "_" || ("a"..."z").contains(s[i]) || ("0"..."9").contains(s[i]) {
                key.unicodeScalars.append(s[i])
                i = s.index(after: i)
            }
            guard !key.isEmpty, expect(": ") else { return nil }
            if i < s.endIndex, s[i] == "\"" {
                guard let (text, end) = readQuoted(raw, from: i) else { return nil }
                pairs.append((key, .string(text)))
                i = end
            } else {
                var word = ""
                while i < s.endIndex, s[i] != ",", s[i] != " " {
                    word.unicodeScalars.append(s[i])
                    i = s.index(after: i)
                }
                guard !word.isEmpty else { return nil }
                pairs.append((key, .bare(word)))
            }
            if expect(", ") { continue }
            guard expect(" }"), i == s.endIndex else { return nil }
            break
        }
        var result: [String: Value] = [:]
        var at = 0
        for field in fields {
            if at < pairs.count, pairs[at].0 == field.key {
                switch (field.kind, pairs[at].1) {
                case (.string, .string): break
                case (.int, .bare(let digits)) where !digits.isEmpty && digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }): break
                case (.role, .bare(let word)) where KeptRole(rawValue: word) != nil: break
                default: return nil
                }
                result[field.key] = pairs[at].1
                at += 1
            } else if !field.optional {
                return nil
            }
        }
        return at == pairs.count ? result : nil
    }

    /// The string whose opening quote is at `start`, and where it ends (after
    /// the closing quote); nil if it is malformed or uses an escape the
    /// renderer doesn't write.
    private static func readQuoted(_ raw: String, from start: String.UnicodeScalarView.Index) -> (String, String.UnicodeScalarView.Index)? {
        let s = raw.unicodeScalars
        var i = start
        guard i < s.endIndex, s[i] == "\"" else { return nil }
        i = s.index(after: i)
        var out = String.UnicodeScalarView()
        while i < s.endIndex {
            let scalar = s[i]
            i = s.index(after: i)
            if scalar == "\"" { return (String(out), i) }
            guard scalar == "\\" else { out.append(scalar); continue }
            guard i < s.endIndex else { return nil }
            let escape = s[i]
            i = s.index(after: i)
            switch escape {
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    guard i < s.endIndex else { return nil }
                    hex.unicodeScalars.append(s[i])
                    i = s.index(after: i)
                }
                guard hex.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("A"..."F").contains($0) }),
                      let value = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(value) else { return nil }
                out.append(decoded)
            default: return nil
            }
        }
        return nil
    }

    /// Reads "2026-10-22T09:12:00-04:00" (or with "Z"): only a real date.
    private static func date(rfc3339 text: String) -> Date? {
        let c = Array(text.unicodeScalars)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= c.count, c[range].allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
            return Int(String(String.UnicodeScalarView(c[range])))
        }
        guard c.count >= 20, c[4] == "-", c[7] == "-", c[10] == "T", c[13] == ":", c[16] == ":",
              let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19) else { return nil }
        var offset = 0
        if c.count == 20, c[19] == "Z" {
            offset = 0
        } else if c.count == 25, c[22] == ":", c[19] == "+" || c[19] == "-",
                  let hours = number(20..<22), let minutes = number(23..<25), hours < 24, minutes < 60 {
            offset = (hours * 3600 + minutes * 60) * (c[19] == "-" ? -1 : 1)
        } else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        calendar.timeZone = zone
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts) else { return nil }
        // A date that rolled over (30 February) is not the one written.
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard back.year == year, back.month == month, back.day == day, back.hour == hour,
              back.minute == minute, back.second == second else { return nil }
        return date
    }
}
