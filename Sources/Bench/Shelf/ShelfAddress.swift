// ShelfAddress.swift — which file a figure or a link on Claude Science's page
// is (DESIGN.md, Shelf → From the conversation). A right-click in the main
// window gives Swift the element's address and a little text; this decides
// whether the address names one version of an artifact, and what to call it
// until the daemon says. Pure: no page, no network.
//
// The shapes known from Capsid's reads of the page: the bytes and thumbnails
// of a version are `/api/artifacts/versions/<v>` and `…?thumbnail=<w>` (the
// versions the page asks for itself), and its own links name a version as
// `?v=<v>`. Ids are the daemon's own, exactly 36 lowercase hex digits and
// dashes (`PlanCheck.isFrameID`, which keeps `/api/artifacts/<artifact>/…`
// from ever being read as a version). Anything else is not an artifact: an
// avatar, a link out, a `blob:` picture whose address says nothing. A page
// that draws figures from another shape simply gets no Shelf items, and the
// File menu's commands stay the way in.
import Foundation

enum ShelfAddress {
    /// An address longer than this is not read.
    static let maxLength = 4_096
    /// What may follow a version in a path and still be that file: the bytes
    /// under another name.
    private static let tails: Set<String> = ["download", "raw", "content", "file", "thumbnail"]
    /// The query names a link may carry a version in.
    private static let queryNames: Set<String> = ["v", "version", "version_id", "versionId"]

    /// The version an address on the daemon's own origin names, or nil.
    static func version(in address: String, daemonPort: Int?) -> String? {
        guard address.utf8.count <= maxLength, let components = URLComponents(string: address),
              let url = components.url, WebRoute.classify(url, daemonPort: daemonPort) == .daemon else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // ["", "api", "artifacts", "versions", <v>, <tail>?]
        if parts.count >= 5, parts[0].isEmpty, parts[1] == "api", parts[2] == "artifacts", parts[3] == "versions" {
            guard PlanCheck.isFrameID(parts[4]) else { return nil }
            if parts.count == 5 { return parts[4] }
            return parts.count == 6 && tails.contains(parts[5]) ? parts[4] : nil
        }
        for item in components.queryItems ?? [] where queryNames.contains(item.name) {
            if let value = item.value, PlanCheck.isFrameID(value) { return value }
        }
        return nil
    }

    /// A name for a picked element until the daemon's facts give the real one:
    /// the element's own words (a picture's alt text, a link's text), one line,
    /// bounded; else a plain noun.
    static func name(hint: String, isImage: Bool) -> String {
        let line = hint.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let clean = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { return isImage ? "Figure" : "File" }
        return String(clean.prefix(HistoryFile.nameLimit))
    }

    /// The entry for a picked element: everything but the version is a guess
    /// the shelf corrects from the daemon's facts (name, type, size), so the
    /// guess only has to classify it well enough to show a picture's tile.
    static func entry(version: String, name: String, isImage: Bool) -> ArtifactEntry {
        let kind = ArtifactKind.classify(name: name, mime: nil)
        // A picture on the page with no extension in its words is a raster.
        let mime: String? = isImage && kind == .other ? "image/png" : nil
        return ArtifactEntry(version: version, artifact: nil, name: name, mime: mime, size: 0, at: nil)
    }
}
