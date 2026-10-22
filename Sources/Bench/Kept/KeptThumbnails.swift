// KeptThumbnails.swift — pictures of kept files, which are on this Mac
// (DESIGN.md, Keep). Quick Look draws them at the size asked for, times the
// screen's scale, off the main actor; they are kept by path within a byte
// budget and let go when the window closes. A file iCloud has put away is
// never fetched for a picture: its kind's symbol shows instead.
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

    func image(for url: URL, side: CGFloat) -> CGImage? {
        images[key(url, side)]
    }

    private func key(_ url: URL, _ side: CGFloat) -> String { "\(Int(side))@\(url.path)" }

    /// Asks Quick Look for the picture, once, at `side` points on the long
    /// edge, at the screen's scale.
    func want(_ url: URL, side: CGFloat, scale: CGFloat) {
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
            await self?.receive(image, for: key)
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
        images = [:]
        order = []
        cost = 0
        failed = []
        objectWillChange.send()
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
