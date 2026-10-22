// KeptThumbnails.swift — pictures of kept files, which are on this Mac
// (DESIGN.md, Keep). Quick Look draws them at the size asked for, times the
// screen's scale, off the main actor; they are kept by path within a byte
// budget and let go when the window closes. A file iCloud has put away is
// never fetched for a picture: its kind's symbol shows instead. The Shelf's
// text files (Markdown, tables, scripts) are drawn from their first bytes
// instead (`ShelfPeek`), read through the disk layer off the main actor,
// because Quick Look's page of them is too small to read at a card's size.
import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class KeptThumbnails: ObservableObject {
    /// About what the Results shelf allows itself.
    static let budget = 24 * 1024 * 1024

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private var cost = 0
    private var pending: Set<String> = []
    private var failed: Set<String> = []
    private var peeks: [String: ShelfPeek] = [:]
    private var peeking: Set<String> = []
    private var unreadable: Set<String> = []
    /// The first bytes of a kept text file; nil leaves the Shelf's text cards to Quick Look.
    private let peeker: (@MainActor (URL) async -> String?)?

    init(peek: (@MainActor (URL) async -> String?)? = nil) {
        peeker = peek
    }

    func image(for url: URL, side: CGFloat) -> CGImage? {
        images[key(url, side)]
    }

    private func key(_ url: URL, _ side: CGFloat) -> String { "\(Int(side))@\(url.path)" }

    // MARK: Text files

    /// This card is drawn from the file's text: it is one the Shelf draws so,
    /// and what it holds hasn't turned out not to be text.
    func usesPeek(_ url: URL) -> Bool {
        peeker != nil && ShelfPeek.wants(fileName: url.lastPathComponent) && !unreadable.contains(url.path)
    }

    func peek(for url: URL) -> ShelfPeek? { peeks[url.path] }

    /// Reads a text file's first bytes, once.
    func wantPeek(_ url: URL) {
        let path = url.path
        guard usesPeek(url), peeks[path] == nil, !peeking.contains(path), let peeker else { return }
        peeking.insert(path)
        Task { [weak self] in
            let text = await peeker(url)
            guard let self else { return }
            peeking.remove(path)
            if let text, let made = ShelfPeek.make(text: text, fileName: url.lastPathComponent) {
                peeks[path] = made
            } else {
                unreadable.insert(path)
            }
            objectWillChange.send()
        }
    }

    /// Asks Quick Look for the picture, once, at `side` points on the long
    /// edge, at the screen's scale.
    func want(_ url: URL, side: CGFloat, scale: CGFloat, cropped: Bool = false) {
        let key = key(url, side)
        guard images[key] == nil, !pending.contains(key), !failed.contains(key) else { return }
        pending.insert(key)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .thumbnail)
        request.iconMode = false
        Task.detached(priority: .utility) { [weak self] in
            let image: CGImage? = await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.cgImage)
                }
            }
            // A page's thumbnail is mostly paper: a card shows what is on it.
            await self?.receive(cropped ? (image?.croppedToContent() ?? image) : image, for: key)
        }
    }

    private func receive(_ image: CGImage?, for key: String) {
        pending.remove(key)
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
