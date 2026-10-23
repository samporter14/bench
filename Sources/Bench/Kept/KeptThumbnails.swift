// KeptThumbnails.swift — pictures of kept files, which are on this Mac
// (DESIGN.md, Keep). Quick Look draws them at the size asked for, times the
// screen's scale, off the main actor; they are kept by path within a byte
// budget and let go when the window closes. A picture is only as good as the
// file it was drawn from: each time a card asks, the file is looked at (its
// modification date and size, off the main actor), and a file that is not the
// one the picture was drawn from, as when an item is taken off the shelf and
// a file of the same name is put on, has its pictures dropped and drawn again.
// A file iCloud has put away is never fetched for a picture (the same check as
// `KeptDisk.peek`'s): its kind's symbol shows instead. The Shelf's text files
// (Markdown, tables, scripts) are drawn from their first bytes instead
// (`ShelfPeek`), read through the disk layer off the main actor, because Quick
// Look's page of them is too small to read at a card's size.
import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class KeptThumbnails: ObservableObject {
    /// About what the Results shelf allows itself.
    static let budget = 24 * 1024 * 1024

    typealias FileFacts = KeptFileFacts
    typealias Stamp = KeptFileStamp

    /// A picture of a file at a side.
    private struct Key: Hashable {
        let side: Int
        let path: String
    }

    typealias Inspect = @Sendable (URL) async -> FileFacts?
    typealias Generate = @Sendable (URL, CGFloat, CGFloat) async -> CGImage?

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private var cost = 0
    private var pending: Set<Key> = []
    private var failed: Set<Key> = []
    private var peeks: [String: ShelfPeek] = [:]
    private var peeking: Set<String> = []
    private var unreadable: Set<String> = []
    /// What each path was when its pictures (or its text) were drawn.
    private var stamps: [String: Stamp] = [:]
    /// The first bytes of a kept text file; nil leaves the Shelf's text cards to Quick Look.
    private let peeker: (@MainActor (URL) async -> String?)?
    private let inspect: Inspect
    private let generate: Generate

    init(peek: (@MainActor (URL) async -> String?)? = nil,
         inspect: @escaping Inspect = KeptThumbnails.inspectFile,
         generate: @escaping Generate = KeptThumbnails.quickLook) {
        peeker = peek
        self.inspect = inspect
        self.generate = generate
    }

    /// The file as it is on disk now, looked at on the disk's queue. Nil when
    /// it can't be looked at.
    nonisolated static func inspectFile(_ url: URL) async -> FileFacts? {
        await KeptDisk.fileFacts(of: url)
    }

    /// Quick Look's picture at `side` points on the long edge, at `scale`.
    nonisolated static func quickLook(_ url: URL, _ side: CGFloat, _ scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .thumbnail)
        request.iconMode = false
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
    }

    func image(for url: URL, side: CGFloat) -> CGImage? {
        images[Key(side: Int(side), path: url.path)]
    }

    // MARK: Text files

    /// This card is drawn from the file's text: it is one the Shelf draws so,
    /// and what it holds hasn't turned out not to be text.
    func usesPeek(_ url: URL) -> Bool {
        peeker != nil && ShelfPeek.wants(fileName: url.lastPathComponent) && !unreadable.contains(url.path)
    }

    func peek(for url: URL) -> ShelfPeek? { peeks[url.path] }

    /// Reads a text file's first bytes, once for each state of the file: a file
    /// that is not the one read before is read again.
    func wantPeek(_ url: URL) {
        let path = url.path
        guard usesPeek(url), !peeking.contains(path), let peeker else { return }
        peeking.insert(path)
        let inspect = self.inspect
        Task { [weak self] in
            let facts = await inspect(url)
            guard let self else { return }
            noteFile(path, facts)
            // Put away in iCloud: no text to read; the card goes to the kind's symbol.
            if facts?.putAway == true {
                peeking.remove(path)
                unreadable.insert(path)
                objectWillChange.send()
                return
            }
            if peeks[path] != nil {
                peeking.remove(path)
                return
            }
            let text = await peeker(url)
            peeking.remove(path)
            // Another file came while this one was read: its own ask reads it.
            guard stamps[path] == facts?.stamp else { return }
            if let text, let made = ShelfPeek.make(text: text, fileName: url.lastPathComponent) {
                peeks[path] = made
            } else {
                unreadable.insert(path)
            }
            objectWillChange.send()
        }
    }

    // MARK: Pictures

    /// Asks Quick Look for the picture, once for each state of the file, at
    /// `side` points on the long edge, at the screen's scale. A file iCloud has
    /// put away gets none (and is not downloaded to get one); neither does one
    /// that is not the file the picture shown was drawn from, until it is drawn.
    func want(_ url: URL, side: CGFloat, scale: CGFloat, cropped: Bool = false) {
        let key = Key(side: Int(side), path: url.path)
        guard !pending.contains(key) else { return }
        pending.insert(key)
        let inspect = self.inspect, generate = self.generate
        Task { [weak self] in
            let facts = await inspect(url)
            guard let self else { return }
            noteFile(key.path, facts)
            if facts?.putAway == true {
                pending.remove(key)
                failed.insert(key)
                objectWillChange.send()
                return
            }
            guard images[key] == nil, !failed.contains(key) else {
                pending.remove(key)
                return
            }
            let image = await Task.detached(priority: .utility) { await generate(url, side, scale) }.value
            // A page's thumbnail is mostly paper: a card shows what is on it.
            let shown = cropped ? (image?.croppedToContent() ?? image) : image
            receive(shown, for: key, drawnFrom: facts?.stamp) {
                // The file changed while it was drawn: draw the new one.
                self.want(url, side: side, scale: scale, cropped: cropped)
            }
        }
    }

    /// The file is as it is now: if it is not the one the pictures and text
    /// held for its path were made from, they go.
    private func noteFile(_ path: String, _ facts: FileFacts?) {
        let now = facts?.stamp
        if let before = stamps[path], before != now {
            let gone = images.keys.filter { $0.path == path }
            for key in gone {
                if let image = images.removeValue(forKey: key) { cost -= image.bytesPerRow * image.height }
            }
            order.removeAll { $0.path == path }
            failed = failed.filter { $0.path != path }
            peeks[path] = nil
            unreadable.remove(path)
            objectWillChange.send()
        }
        stamps[path] = now
    }

    private func receive(_ image: CGImage?, for key: Key, drawnFrom stamp: Stamp?, again: () -> Void) {
        pending.remove(key)
        guard stamps[key.path] == stamp else {
            again()
            return
        }
        guard let image else {
            failed.insert(key)
            objectWillChange.send()
            return
        }
        let bytes = image.bytesPerRow * image.height
        while cost + bytes > Self.budget, let oldest = order.first {
            order.removeFirst()
            if let gone = images.removeValue(forKey: oldest) { cost -= gone.bytesPerRow * gone.height }
        }
        images[key] = image
        order.append(key)
        cost += bytes
        objectWillChange.send()
    }

    /// The window closed: the pictures go.
    func removeAll() {
        peeks = [:]
        unreadable = []
        images = [:]
        order = []
        cost = 0
        failed = []
        stamps = [:]
        objectWillChange.send()
    }
}

extension CGImage {
    /// The picture trimmed to where it isn't white, with a margin: a page's
    /// thumbnail is mostly paper. Nil when there is nothing to trim to.
    func croppedToContent(margin: CGFloat = 0.06, threshold: UInt8 = 244) -> CGImage? {
        let w = width, h = height
        guard w > 16, h > 16 else { return nil }
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4] < threshold || pixels[row + x * 4 + 1] < threshold || pixels[row + x * 4 + 2] < threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let padX = max(2, Int(CGFloat(maxX - minX + 1) * margin)), padY = max(2, Int(CGFloat(maxY - minY + 1) * margin))
        let rect = CGRect(x: max(0, minX - padX), y: max(0, minY - padY),
                          width: min(w, maxX + padX + 1) - max(0, minX - padX), height: min(h, maxY + padY + 1) - max(0, minY - padY))
        // Not worth it for a picture that is mostly its own content.
        guard rect.width * rect.height < CGFloat(w * h) * 0.9 else { return nil }
        return cropping(to: rect)
    }
}

/// A kept file's picture on paper, or its kind's symbol.
struct KeptThumbnailView: View {
    @ObservedObject var store: KeptThumbnails
    let url: URL
    let side: CGFloat
    let kind: ArtifactKind
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Color.white
            if let image = store.image(for: url, side: side) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: ResultFileRow.symbol(kind))
                    .font(.system(size: side >= 100 ? 40 : 18))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { store.want(url, side: side, scale: scale) }
    }
}
