// CompareFixtures.swift — made-up Shelf items, pictures and a disk for Compare's
// tests (Kept/Compare*.swift): items from two sessions, pictures drawn here (with
// an EXIF orientation when asked), and a disk held in memory that can hold a read
// or the text changes until a test lets them go, change a file between two looks,
// and log what was read. Nothing is written anywhere.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Bench

enum CompareFixtures {
    /// A Shelf item for `file`, in a folder of its own under `root`, from `session` (and version `index`, when given).
    static func item(_ file: String, session: String = "Plate reader QC", project: String = "Assay development",
                     version index: Int? = 2, of total: Int? = nil,
                     root: URL = URL(filePath: "/tmp/compare-fixtures", directoryHint: .isDirectory)) -> ShelfItem {
        let folder = root.appending(path: project, directoryHint: .isDirectory)
            .appending(path: "\((file as NSString).deletingPathExtension) \(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        let figure = KeptFile(path: file, role: .figure, artifact: "a-\(UUID().uuidString.prefix(6))", version: UUID().uuidString.lowercased(),
                              index: index, of: total, sha256: nil, bytes: 10)
        let record = KeptRecord(name: (file as NSString).deletingPathExtension, keptAt: Date(timeIntervalSince1970: 1_800_000_000),
                                projectID: "p-1", projectName: project, sessionID: "00000000-0000-4000-8000-0000000000c1",
                                sessionTitle: session, figure: figure, files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
        let text = KeptText(legend: "", claudeSaid: "", attribution: "", origin: "")
        return ShelfItem(result: KeptResult(folder: folder, collection: project, record: record, text: text), others: [])
    }

    /// A PNG `width` × `height`, each pixel's colour from `colour(x, y)` (top-left origin).
    static func png(width: Int, height: Int, colour: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        encode(image(width: width, height: height, colour: colour), type: .png, orientation: nil)
    }

    /// A JPEG of those pixels, stored on its side with EXIF `orientation` (6: turn it a quarter clockwise to see it).
    static func jpeg(width: Int, height: Int, orientation: Int, colour: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        encode(image(width: width, height: height, colour: colour), type: .jpeg, orientation: orientation)
    }

    /// A PDF of `pages` pages, each `width` × `height` points with a flat blue bar across its lower half on white, as a
    /// plotting library's figure would be: a vector, no pixels of its own.
    static func pdf(width: CGFloat, height: CGFloat, pages: Int = 1) -> Data {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let consumer = CGDataConsumer(data: out as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            context.endPDFPage()
        }
        context.closePDF()
        return out as Data
    }

    /// An SVG `width` × `height` with a flat blue bar across its lower half and nothing under the rest (transparent).
    static func svg(width: Int, height: Int) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <rect x="0" y="\(height / 2)" width="\(width)" height="\(height / 2)" fill="#1a4dcc"/>
        </svg>
        """.utf8)
    }

    /// The colour at (x, y) of `image` (top-left origin), as 0 to 255.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(rgba[0]), Int(rgba[1]), Int(rgba[2]))
    }

    static func image(width: Int, height: Int, colour: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = colour(x, y)
                let at = (y * width + x) * 4
                pixels[at] = r
                pixels[at + 1] = g
                pixels[at + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func encode(_ image: CGImage, type: UTType, orientation: Int?) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// A bar chart for "Plate reader QC": twelve bars, the seventh `low` tall (0 to 1), on white.
    static func chart(width: Int = 480, height: Int = 320, low: Double) -> Data {
        png(width: width, height: height) { x, y in
            let left = width / 10, bar = width * 5 / 100, gap = width * 2 / 100, bottom = height - height / 8
            for index in 0..<12 {
                let start = left + index * (bar + gap)
                guard x >= start, x < start + bar else { continue }
                let tall = index == 6 ? low : 0.78 + Double((index * 5) % 7) / 100
                let top = bottom - Int(Double(height) * 0.7 * tall)
                if y >= top, y < bottom { return index == 6 ? (217, 119, 87) : (36, 36, 34) }
            }
            if y == bottom || y == bottom + 1, x > left - 8, x < width - 20 { return (36, 36, 34) }
            return (255, 255, 255)
        }
    }

    /// The same chart as a PDF of `pages` pages, `width` × `height` points, its bars and axis drawn as vectors, as a
    /// plotting library saves a figure for a paper.
    static func chartPDF(width: CGFloat = 460, height: CGFloat = 307, low: Double, pages: Int = 1) -> Data {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let context = CGContext(consumer: CGDataConsumer(data: out as CFMutableData)!, mediaBox: &box, nil)!
        let left = width / 10, bar = width * 0.05, gap = width * 0.02, bottom = height / 8
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            for index in 0..<12 {
                let tall = index == 6 ? low : 0.78 + Double((index * 5) % 7) / 100
                context.setFillColor(index == 6 ? CGColor(srgbRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
                                                : CGColor(srgbRed: 36 / 255, green: 36 / 255, blue: 34 / 255, alpha: 1))
                context.fill(CGRect(x: left + CGFloat(index) * (bar + gap), y: bottom, width: bar, height: height * 0.7 * tall))
            }
            context.setFillColor(CGColor(srgbRed: 36 / 255, green: 36 / 255, blue: 34 / 255, alpha: 1))
            context.fill(CGRect(x: left - 8, y: bottom - 1.5, width: width - 20 - (left - 8), height: 1.5))
            context.endPDFPage()
        }
        context.closePDF()
        return out as Data
    }
}

/// A disk in memory for Compare's reader: files with their facts, reads and text changes a test can hold, and a log of
/// what was read.
@MainActor
final class CompareFakeDisk {
    struct File {
        var data: Data
        var facts: KeptFileFacts
    }

    var files: [String: File] = [:]
    /// The next read of each of these paths waits for `release`.
    var holdReads: Set<String> = []
    /// The next this many text-changes calls wait for `releaseDiffs`.
    var holdDiffs = 0
    private var heldReads: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var heldDiffs: [CheckedContinuation<Void, Never>] = []
    private(set) var readLog: [String] = []
    private(set) var diffCalls = 0
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// Puts `data` at `url`'s file, as a newer file than any before.
    func put(_ data: Data, at url: URL, putAway: Bool = false) {
        clock = clock.addingTimeInterval(1)
        files[url.path] = File(data: data, facts: KeptFileFacts(modified: clock, size: data.count, putAway: putAway))
    }

    func put(_ text: String, at url: URL) { put(Data(text.utf8), at: url) }

    func remove(_ url: URL) { files[url.path] = nil }

    func facts(_ url: URL) -> KeptFileFacts? { files[url.path]?.facts }

    func read(_ url: URL, limit: Int) async -> Data? {
        readLog.append(url.lastPathComponent)
        // The bytes as they are when the read begins.
        let data = files[url.path]?.data
        if holdReads.remove(url.path) != nil {
            await withCheckedContinuation { heldReads[url.path, default: []].append($0) }
        }
        guard let data, !data.isEmpty, data.count <= limit else { return nil }
        return data
    }

    func isHolding(_ url: URL) -> Bool { !(heldReads[url.path] ?? []).isEmpty }

    func release(_ url: URL) {
        let waiting = heldReads[url.path] ?? []
        heldReads[url.path] = nil
        for continuation in waiting { continuation.resume() }
    }

    /// The answer is worked out when asked and handed back when let go: an answer that was ready but arrives late,
    /// after its request was cancelled or replaced.
    func diff(_ left: String, _ right: String) async -> CompareDiff.Outcome? {
        diffCalls += 1
        let outcome = try? CompareDiff.compare(left, right)
        if holdDiffs > 0 {
            holdDiffs -= 1
            await withCheckedContinuation { heldDiffs.append($0) }
        }
        return outcome
    }

    var holdingDiffs: Int { heldDiffs.count }

    func releaseDiffs() {
        let waiting = heldDiffs
        heldDiffs = []
        for continuation in waiting { continuation.resume() }
    }

    var reader: CompareReader {
        CompareReader(
            inspect: { url in await self.facts(url) },
            read: { url, limit in await self.read(url, limit: limit) },
            decode: { data in CompareImages.decode(data) },
            diff: { left, right in await self.diff(left, right) })
    }

    /// Waits until `condition` holds, yielding to the tasks under test; false if it never does.
    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}

extension CompareModel {
    /// Waits for the reads, reread and text changes under way to finish (none of them held).
    func settle() async {
        for _ in 0..<20 {
            // The look first: it may start a new read, and the one it replaced may be held.
            let checking = checkingTask
            await checking?.value
            let loading = loadingTask
            await loading?.value
            await Task.yield()
            if loading == loadingTask, checking == checkingTask { return }
        }
    }
}
