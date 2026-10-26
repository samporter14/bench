// ShelfDocumentReading.swift — an ordinary text document on its Shelf card (since 1.0.7).
// Reads use KeptDisk's queue; Markdown parsing runs off the main actor. Only four documents are kept, each at most
// 256 KiB on disk. Larger, missing, non-text and iCloud-offloaded files keep their ordinary preview card.
import AppKit

enum ShelfDocumentReading {
    static let byteLimit = 256 * 1_024

    static func accepts(_ item: ShelfItem) -> Bool {
        item.kind == .document && !item.isSelectionNote
            && ["md", "markdown", "txt", "text", "rst"].contains(item.fileURL.pathExtension.lowercased())
    }

    static func markdown(_ url: URL) -> Bool { ["md", "markdown"].contains(url.pathExtension.lowercased()) }

    static func render(_ text: String, markdown: Bool) -> AnswerDocument {
        if markdown { return AnswerMarkdown.render(text, style: .reference) }
        let style = AnswerStyle.reference
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        return AnswerDocument(text: NSAttributedString(string: text, attributes: [
            .font: style.body, .foregroundColor: style.ink, .paragraphStyle: paragraph.copy(),
        ]), unsupported: [])
    }
}

/// A small cache owned by the Shelf window. A newer request, cancellation or a changed file invalidates a read in
/// flight; an old completion cannot replace a newer rendering. Nothing about the document is logged.
@MainActor
final class ShelfDocumentReadings: ObservableObject {
    typealias Inspect = @Sendable (URL) async -> KeptFileFacts?
    typealias Read = @MainActor (URL) async throws -> String?
    typealias Render = @Sendable (String, Bool) async -> AnswerDocument
    static let kept = 4
    static let remembered = 64

    enum Reading: Equatable, Sendable { case notYet, ready, none }

    private struct Held {
        let stamp: KeptFileStamp
        let document: AnswerDocument
    }

    @Published private var held: [String: Held] = [:]
    @Published private var wordless: Set<String> = []
    private var order: [String] = []
    private var requests: [String: UUID] = [:]
    private let inspect: Inspect
    private let read: Read
    private let render: Render

    init(inspect: @escaping Inspect = KeptDisk.fileFacts(of:), read: @escaping Read,
         render: @escaping Render = { text, markdown in
             await Task.detached(priority: .utility) { ShelfDocumentReading.render(text, markdown: markdown) }.value
         }) {
        self.inspect = inspect
        self.read = read
        self.render = render
    }

    convenience init(disk: KeptDisk) {
        self.init(read: { url in
            guard let data = try await disk.pictureBytes(url, limit: ShelfDocumentReading.byteLimit), !data.contains(0) else { return nil }
            return String(data: data, encoding: .utf8)
        })
    }

    func document(for item: ShelfItem) -> AnswerDocument? {
        ShelfDocumentReading.accepts(item) ? held[item.fileURL.path]?.document : nil
    }

    func reading(for item: ShelfItem) -> Reading {
        guard ShelfDocumentReading.accepts(item) else { return .none }
        let path = item.fileURL.path
        if held[path] != nil { return .ready }
        return wordless.contains(path) ? .none : .notYet
    }

    func look(at item: ShelfItem) async {
        guard ShelfDocumentReading.accepts(item), !Task.isCancelled else { return }
        let url = item.fileURL
        let path = url.path
        let request = UUID()
        requests[path] = request
        defer { if requests[path] == request { requests[path] = nil } }
        func current() -> Bool { requests[path] == request && !Task.isCancelled }

        let facts = await inspect(url)
        guard current() else { return }
        guard let facts, !facts.putAway, let size = facts.size, size <= ShelfDocumentReading.byteLimit else {
            drop(path)
            return
        }
        if held[path]?.stamp == facts.stamp {
            touch(path)
            return
        }
        let raw: String?
        do { raw = try await read(url) } catch {
            if current() { drop(path) }
            return
        }
        guard current() else { return }
        guard var text = raw, text.utf8.count <= ShelfDocumentReading.byteLimit, !text.utf8.contains(0) else {
            drop(path)
            return
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { drop(path); return }
        let document = await render(text, ShelfDocumentReading.markdown(url))
        guard current() else { return }
        let after = await inspect(url)
        guard current() else { return }
        guard after?.stamp == facts.stamp else { drop(path); return }
        wordless.remove(path)
        held[path] = Held(stamp: facts.stamp, document: document)
        touch(path)
        while order.count > Self.kept { held[order.removeFirst()] = nil }
    }

    private func touch(_ path: String) {
        order.removeAll { $0 == path }
        order.append(path)
    }

    private func drop(_ path: String) {
        held[path] = nil
        order.removeAll { $0 == path }
        if wordless.count >= Self.remembered { wordless.removeAll() }
        wordless.insert(path)
    }
}
