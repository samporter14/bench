// ShelfThumbnails.swift — the thumbnails the results shelf shows (DESIGN.md,
// Results): each image file's picture, decoded once, small, and kept within a
// byte budget. The shelf hands this the bytes of a thumbnail read; the rows
// ask it for the picture.
//
// What it keeps is the decoded picture and nothing else: the WebP bytes are
// dropped as soon as they are decoded. The numbers, and why:
//   - The row draws a thumbnail 36 × 36 points, filled (`scaledToFill`), so on
//     a Retina screen the picture's short side needs 72 pixels.
//   - `pixelSide` is 144, the long side at most: twice that, so a picture that
//     is not square still has 72 pixels on its short side up to 2:1. The
//     daemon's thumbnails are 120 pixels wide, so they pass as they are and
//     are never enlarged; a bigger one (the reply is only checked for WebP and
//     4 MB) is shrunk while it is decoded, never decoded at full size.
//   - The largest picture kept is 144 × 144 × 4 = 82,944 bytes, and costs 83,968
//     with the 1,024 each entry is charged for its objects. `defaultBudget` is
//     16 MiB: room for 199 of those, or 453 of 120 × 75 (a landscape chart as
//     the daemon makes it, 37,024 each). The shelf used to bound the count
//     (200) and not the bytes, so up to 800 MiB of WebP could be held; this is
//     a bound on bytes, whatever the replies are.
//   - Before a picture is decoded its header is read: more than 16 million
//     pixels (4096 × 4096) is refused, because that is not what a 120-pixel
//     thumbnail is, and decoding it would briefly need 64 MiB or more.
// The pictures are let go when the Results window closes (`removeAll`): the
// list is taken again when it opens, and a thumbnail is small to read again.
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Why a thumbnail was not kept.
enum ShelfThumbnailRefusal: Error, Equatable, Sendable {
    /// Not an image ImageIO reads, or its header has no size.
    case notAnImage
    /// Its header declares more pixels than a thumbnail can have.
    case tooLarge
    /// One picture costs more than the whole budget.
    case overBudget
}

/// Decoded thumbnails by version id, least recently used first out, with their
/// cost counted: `totalCost` never goes over `budget`.
@MainActor
final class ShelfThumbnails: ObservableObject {
    /// Turns a thumbnail's bytes into a picture, off the main actor. Tests count
    /// the calls.
    typealias Decoder = @Sendable (Data) -> Result<CGImage, ShelfThumbnailRefusal>

    /// The long side of a kept picture, in pixels, at most.
    nonisolated static let pixelSide = 144
    /// More pixels than this in a picture's header is refused unread.
    nonisolated static let maxSourcePixels = 4_096 * 4_096
    /// What each entry is charged besides its pixels: the image object, the
    /// dictionary slot and the version id. Tiny pictures can't make the count
    /// run away: at most `defaultBudget / entryOverhead` = 16,384 entries.
    nonisolated static let entryOverhead = 1_024
    /// The bytes all kept pictures may cost together.
    nonisolated static let defaultBudget = 16 * 1_024 * 1_024

    /// What a picture costs: its pixels (never less than width × height × 4,
    /// more if ImageIO kept wider pixels or padded the rows) and the overhead.
    nonisolated static func cost(of image: CGImage) -> Int {
        max(image.bytesPerRow * image.height, image.width * image.height * 4) + entryOverhead
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var used: UInt64
    }

    let budget: Int
    private let decoder: Decoder
    private var entries: [String: Entry] = [:]
    /// Bumped when a picture comes or goes, so a row that watches this redraws.
    /// Reading a picture (which only notes it was used) never bumps it.
    @Published private(set) var changes = 0
    /// What the kept pictures cost together, at most `budget`.
    private(set) var totalCost = 0
    /// Counts uses: the entry with the lowest `used` is the least recently used.
    private var clock: UInt64 = 0
    /// Versions whose bytes didn't decode (or whose picture is over the budget):
    /// not asked for again until `removeAll`.
    private var failed: Set<String> = []
    /// Decodes under way, by request; a version's `latest` is the one that counts.
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var latest: [String: Int] = [:]
    private var requests = 0

    init(budget: Int = defaultBudget, decoder: @escaping Decoder = { ShelfThumbnails.decode($0) }) {
        self.budget = budget
        self.decoder = decoder
    }

    // MARK: What is kept

    /// A version's picture, for a row to draw: notes it was used just now. It
    /// publishes nothing, so a row may call it while drawing.
    func image(for version: String) -> CGImage? {
        guard var entry = entries[version] else { return nil }
        clock += 1
        entry.used = clock
        entries[version] = entry
        return entry.image
    }

    /// Whether a picture is kept, without noting a use.
    func contains(_ version: String) -> Bool {
        entries[version] != nil
    }

    /// The versions kept: for tests.
    var versions: Set<String> { Set(entries.keys) }

    /// Whether the shelf has no need to read this thumbnail: it is kept, being
    /// decoded, or its bytes didn't decode.
    func knows(_ version: String) -> Bool {
        entries[version] != nil || latest[version] != nil || failed.contains(version)
    }

    // MARK: Taking bytes in

    /// A thumbnail read's bytes: decoded off the main actor, then kept. Bytes
    /// that aren't a picture keep nothing and mark the version failed. Bytes
    /// for a version already kept replace its picture.
    func receive(_ data: Data, for version: String) {
        requests += 1
        let id = requests
        latest[version] = id
        let decoder = decoder
        tasks[id] = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { decoder(data) }.value
            guard let self else { return }
            self.tasks[id] = nil
            // Superseded, or let go by `removeAll` meanwhile: lands nowhere.
            guard self.latest[version] == id else { return }
            self.latest[version] = nil
            switch result {
            case .success(let image): self.insert(image, for: version)
            case .failure: self.failed.insert(version)
            }
        }
    }

    /// Keeps a picture, replacing the version's earlier one (its cost is
    /// replaced, not added), and lets the least recently used go until the
    /// total is within the budget. A picture that alone costs more than the
    /// budget is refused, and the version marked failed.
    @discardableResult
    func insert(_ image: CGImage, for version: String) -> Bool {
        let cost = Self.cost(of: image)
        guard cost <= budget else {
            failed.insert(version)
            return false
        }
        if let old = entries.removeValue(forKey: version) { totalCost -= old.cost }
        while totalCost + cost > budget, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            totalCost -= entries.removeValue(forKey: oldest)?.cost ?? 0
        }
        clock += 1
        entries[version] = Entry(image: image, cost: cost, used: clock)
        totalCost += cost
        failed.remove(version)
        changes += 1
        return true
    }

    /// Every picture let go, every failure forgotten, and every decode under
    /// way told to land nowhere: the Results window closed.
    func removeAll() {
        let hadPictures = !entries.isEmpty
        entries = [:]
        totalCost = 0
        failed = []
        latest = [:]
        if hadPictures { changes += 1 }
    }

    /// Waits until every decode started so far is done. For tests.
    func settled() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    // MARK: Decoding

    /// The picture at most `side` pixels long, from bytes of any image ImageIO
    /// reads. The type and the size in the header are checked before any pixel
    /// is decoded, and the decode itself is made at the small size
    /// (`kCGImageSourceThumbnailMaxPixelSize`), upright, from the whole image
    /// and at once, so it happens here and not when a row first draws it. Never
    /// enlarged. Safe off the main actor: it touches nothing but its arguments.
    nonisolated static func decode(_ data: Data, side: Int = pixelSide,
                                   maxSourcePixels: Int = maxSourcePixels) -> Result<CGImage, ShelfThumbnailRefusal> {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              UTType(identifier)?.conforms(to: .image) == true,
              CGImageSourceGetCount(source) >= 1 else { return .failure(.notAnImage) }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return .failure(.notAnImage) }
        guard width <= maxSourcePixels, height <= maxSourcePixels, width * height <= maxSourcePixels else {
            return .failure(.tooLarge)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(side, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return .failure(.notAnImage) }
        return .success(image)
    }
}
