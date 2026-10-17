// ShelfCopy.swift — Copy (DESIGN.md, Results): what a file puts on the
// pasteboard. The decision is a pure function of the file's kind and bytes;
// the pasteboard write after it is thin. Images, text (markdown, plain text,
// tables) and PDFs can be copied; anything else is saved or dragged instead.
import AppKit

/// What Copy puts on the pasteboard, or why it can't.
enum ShelfCopyContent: Equatable, Sendable {
    /// The image file's bytes: the full picture, never the thumbnail.
    case image(Data)
    case text(String)
    case pdf(Data)
    /// Copy isn't offered for this kind of file.
    case notOffered
    /// A text kind whose bytes aren't valid UTF-8.
    case notText

    /// The line a row shows when Copy can't go ahead.
    var problem: String? {
        switch self {
        case .notOffered: "Copy isn't offered for this kind of file. Drag it out or save it instead."
        case .notText: "Couldn't copy this as text, because it isn't valid UTF-8. Save it instead."
        default: nil
        }
    }
}

enum ShelfCopy {
    /// Whether Copy is offered for a kind of file.
    static func isOffered(_ kind: ArtifactKind) -> Bool {
        switch kind {
        case .image, .markdown, .text, .table, .pdf: true
        case .svg, .html, .notebook, .other: false
        }
    }

    /// What goes on the pasteboard for a kind and the file's bytes. Text is
    /// decoded as UTF-8 (a leading byte-order mark dropped) and refused when
    /// it isn't.
    static func content(kind: ArtifactKind, data: Data) -> ShelfCopyContent {
        switch kind {
        case .image:
            return .image(data)
        case .markdown, .text, .table:
            guard var text = String(data: data, encoding: .utf8) else { return .notText }
            if text.unicodeScalars.first == "\u{FEFF}" { text = String(text.unicodeScalars.dropFirst()) }
            return .text(text)
        case .pdf:
            return .pdf(data)
        case .svg, .html, .notebook, .other:
            return .notOffered
        }
    }
}

/// The pasteboard write, kept thin: it replaces what was copied before.
@MainActor
enum ShelfPasteboard {
    /// False when the content couldn't be put there (an image that doesn't decode, say).
    static func write(_ content: ShelfCopyContent, to pasteboard: NSPasteboard = .general) -> Bool {
        switch content {
        case .image(let data):
            guard let image = NSImage(data: data) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects([image])
        case .text(let text):
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .pdf(let data):
            pasteboard.clearContents()
            return pasteboard.setData(data, forType: .pdf)
        case .notOffered, .notText:
            return false
        }
    }
}
