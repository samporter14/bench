// RemoteFiles.swift — what the phone may know about a session's artifacts
// (DESIGN.md, Bench on your phone → Phase 3: Artifacts). Two shared pieces:
// `ArtifactKind`, how a file is shown on the phone, decided from its name and
// content type alone; and `ListedFiles`, the versions Bench has listed to each
// device lately, the only ones `/api/files/<v>/…` will serve that device.
import Foundation

/// How the phone shows a file. Anything that could run script (HTML, SVG,
/// notebooks) is never rendered on Bench's origin, whatever its kind says.
enum ArtifactKind: String, Codable, CaseIterable, Sendable {
    case image, svg, markdown, text, table, html, pdf, notebook, other

    private static let byExtension: [String: ArtifactKind] = {
        var map: [String: ArtifactKind] = [:]
        for ext in ["png", "jpg", "jpeg", "gif", "webp"] { map[ext] = .image }
        map["svg"] = .svg
        for ext in ["md", "markdown"] { map[ext] = .markdown }
        for ext in ["txt", "text", "log", "json", "jsonl", "yaml", "yml", "toml", "xml",
                    "py", "r", "sh", "js", "ts", "swift", "c", "h", "cpp", "java", "go", "rs",
                    "sql", "fasta", "fa", "fastq", "fq", "gff", "gtf", "bed", "vcf", "sam", "tex"] {
            map[ext] = .text
        }
        for ext in ["csv", "tsv"] { map[ext] = .table }
        for ext in ["html", "htm", "xhtml"] { map[ext] = .html }
        map["pdf"] = .pdf
        map["ipynb"] = .notebook
        return map
    }()

    /// The kind for a file name and content type. The extension decides
    /// first; the content type only fills in when the extension says nothing.
    /// Script-capable types always win, so a `.txt` sent as `text/html` is
    /// still treated as HTML.
    static func classify(name: String, mime: String?) -> ArtifactKind {
        let type = (mime ?? "").lowercased().split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
        if type == "text/html" || type == "application/xhtml+xml" { return .html }
        if type == "image/svg+xml" { return .svg }
        let ext = (name as NSString).pathExtension.lowercased()
        if let kind = byExtension[ext] { return kind }
        switch type {
        case "image/png", "image/jpeg", "image/gif", "image/webp": return .image
        case "text/markdown": return .markdown
        case "text/csv", "text/tab-separated-values": return .table
        case "application/pdf": return .pdf
        case "application/x-ipynb+json": return .notebook
        case "application/json": return .text
        default: return type.hasPrefix("text/") ? .text : .other
        }
    }
}

/// The version ids Bench has listed to each device (an artifacts list, or a
/// history page's `files`), each kept for an hour from when it was last
/// listed. `/api/files/<v>/…` serves a device only the versions in its own
/// set, so a paired device can't walk the daemon's version ids.
@MainActor
final class ListedFiles {
    static let shared = ListedFiles()

    static let lifetime: TimeInterval = 60 * 60
    /// Per device, at most this many versions; the oldest go first.
    static let capacity = 2_000

    private var listed: [String: [String: Date]] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Remember that these versions were listed to this device.
    func record(_ versions: some Sequence<String>, device: String) {
        let time = now()
        var mine = (listed[device] ?? [:]).filter { time.timeIntervalSince($0.value) < Self.lifetime }
        for version in versions { mine[version] = time }
        if mine.count > Self.capacity {
            let keep = mine.sorted { $0.value > $1.value }.prefix(Self.capacity)
            mine = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        listed[device] = mine
    }

    /// Whether this device was listed this version within the last hour.
    func allows(_ version: String, device: String) -> Bool {
        guard let at = listed[device]?[version] else { return false }
        return now().timeIntervalSince(at) < Self.lifetime
    }

    /// A device unpaired or removed: forget what it was listed.
    func forget(device: String) {
        listed[device] = nil
    }
}
