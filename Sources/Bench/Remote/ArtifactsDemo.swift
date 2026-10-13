// ArtifactsDemo.swift — the made-up artifacts of `--demo remote` (Phase 3
// files): a chart drawn with CoreGraphics (a PNG, and its WebP thumbnails),
// markdown, a CSV and a TSV, a log, an HTML page, an SVG, a PDF, a notebook,
// an 8 MB file at the download cap and one listed too big to fetch. The routes
// serve them from memory through the same checks as the real ones; no web view
// is touched. Every name and number is made up.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One made-up file: its listing, and its bytes (nil for one listed only by
/// its size, as too big to fetch).
struct DemoArtifact: Sendable {
    let entry: ArtifactEntry
    let bytes: Data?
    /// For a chart: the bars it draws, so a thumbnail can be drawn at any width.
    let bars: [Double]?
}

/// The made-up sessions' files, by session id; a session in `unreadable`
/// fails its list, as one the page can't read.
struct DemoArtifactLibrary: Sendable {
    var bySession: [String: [DemoArtifact]] = [:]
    var unreadable: Set<String> = []
    var byVersion: [String: DemoArtifact] = [:]

    /// Files for the demo's sessions, by their made-up titles.
    static func make(sessions: [SessionStatus], now: Date = Date()) -> DemoArtifactLibrary {
        var library = DemoArtifactLibrary()
        for session in sessions {
            let tag = String(session.id.suffix(2))
            var made = DemoFiles(tag: tag, now: now)
            let files: [DemoArtifact]?
            switch session.title {
            case "Primer design":
                files = [
                    made.chart("primer-melting-points.png", bars: [58.4, 60.1, 61.7, 59.2, 62.0, 58.9], minutes: 52),
                    made.text("primer-report.md", DemoFiles.report, minutes: 50),
                    made.text("primer-pairs.csv", DemoFiles.primerTable, minutes: 49),
                    made.text("run.log", DemoFiles.log, minutes: 48),
                    made.text("summary.html", DemoFiles.html, minutes: 47),
                    made.text("plate-map.svg", DemoFiles.svg, minutes: 46),
                    made.file("primer-design.pdf", DemoFiles.pdf(), minutes: 45),
                    made.text("analysis.ipynb", DemoFiles.notebook, minutes: 44),
                    made.file("plate-reader-raw.dat", Data(repeating: 0x2E, count: ArtifactReaderScript.Cap.download),
                              minutes: 43),
                    made.listedOnly("gel-images.zip", size: 120 * 1024 * 1024, minutes: 42),
                ]
            case "Protein stability screen":
                files = [
                    made.chart("buffer-screen.png", bars: [12, 31, 18, 44, 27, 9, 36, 22], minutes: 5),
                    made.text("buffers.tsv", DemoFiles.bufferTable, minutes: 5),
                    made.text("screen-notes.md", DemoFiles.screenNotes, minutes: 4),
                ]
            case "Figure 2 rebuild":
                files = [
                    made.chart("figure-2-draft.png", bars: [3, 5, 8, 13, 21, 34], minutes: 3),
                    made.text("plot.log", "plot: loading 48 replicates\nplot: out of memory at panel 3\n", minutes: 3),
                ]
            case "Literature sweep":
                files = [made.text("reading-list.md", DemoFiles.readingList, minutes: 2)]
            case "Gel quantification":
                // As a session the page can't read: the list fails.
                files = nil
            default:
                files = []
            }
            guard let files else {
                library.unreadable.insert(session.id)
                continue
            }
            library.bySession[session.id] = files
            for file in files { library.byVersion[file.entry.version] = file }
        }
        return library
    }

    /// A read, answered as the page would answer it.
    func read(_ read: ArtifactRead) -> ArtifactReadOutcome {
        switch read {
        case .list(let frame):
            guard !unreadable.contains(frame), let files = bySession[frame] else { return .unreadable }
            return .list(files.map(\.entry))
        case .thumb(let version, let width):
            guard let file = byVersion[version] else { return .unreadable }
            // The daemon's thumbnail of a raster image is WebP; of anything
            // else, the file itself.
            if let bars = file.bars { return .bytes(DemoChart.webp(bars: bars, width: width)) }
            guard let bytes = file.bytes else { return .unreadable }
            return bytes.count <= ArtifactReaderScript.Cap.thumb ? .bytes(bytes) : .tooBig
        case .text(let version):
            guard let bytes = byVersion[version]?.bytes else { return .unreadable }
            let head = bytes.prefix(ArtifactReaderScript.Cap.text)
            if head.prefix(ArtifactReaderScript.Cap.sniff).contains(0) { return .binary }
            return .text(String(decoding: head, as: UTF8.self), truncated: bytes.count > head.count)
        case .download(let version):
            guard let file = byVersion[version] else { return .unreadable }
            guard let bytes = file.bytes, bytes.count <= ArtifactReaderScript.Cap.download else { return .tooBig }
            return .bytes(bytes)
        }
    }
}

extension RemoteArtifacts {
    /// `--demo remote`: the made-up sessions' files, from memory. The library
    /// is made the first time it is asked for, from the sessions Demo shows.
    static func demo(known: @escaping @MainActor () -> [SessionStatus] = { RemoteAPI.knownSessions(lab: .shared) },
                     browseOn: @escaping @MainActor () -> Bool = { RemoteBrowse.isOn },
                     listed: ListedFiles = ListedFiles(), info: ListedFileInfo = ListedFileInfo()) -> RemoteArtifacts {
        let box = DemoLibraryBox()
        return RemoteArtifacts(dependencies: Dependencies(
            browseOn: browseOn,
            isSession: { id in known().contains { $0.id == id } },
            read: { read in
                let library = box.library ?? DemoArtifactLibrary.make(sessions: known())
                box.library = library
                return library.read(read)
            },
            listed: listed,
            info: info))
    }
}

/// Holds the demo's library once it is made.
@MainActor
private final class DemoLibraryBox {
    var library: DemoArtifactLibrary?
}

// MARK: The files

/// Makes one session's files: version ids `demo-<tag>-<n>`, times before now.
private struct DemoFiles {
    let tag: String
    let now: Date
    var count = 0

    init(tag: String, now: Date) {
        self.tag = tag
        self.now = now
    }

    mutating func file(_ name: String, _ bytes: Data, minutes: Double, bars: [Double]? = nil) -> DemoArtifact {
        count += 1
        let mime = Self.mime(name)
        return DemoArtifact(entry: ArtifactEntry(version: "demo-\(tag)-\(count)", artifact: "demo-art-\(tag)-\(count)",
                                                 name: name, mime: mime, size: bytes.count,
                                                 at: now.addingTimeInterval(-minutes * 60)),
                            bytes: bytes, bars: bars)
    }

    mutating func text(_ name: String, _ text: String, minutes: Double) -> DemoArtifact {
        file(name, Data(text.utf8), minutes: minutes)
    }

    mutating func chart(_ name: String, bars: [Double], minutes: Double) -> DemoArtifact {
        file(name, DemoChart.png(bars: bars), minutes: minutes, bars: bars)
    }

    /// Listed by its size alone: too big to fetch.
    mutating func listedOnly(_ name: String, size: Int, minutes: Double) -> DemoArtifact {
        count += 1
        return DemoArtifact(entry: ArtifactEntry(version: "demo-\(tag)-\(count)", artifact: "demo-art-\(tag)-\(count)",
                                                 name: name, mime: Self.mime(name), size: size,
                                                 at: now.addingTimeInterval(-minutes * 60)),
                            bytes: nil, bars: nil)
    }

    static func mime(_ name: String) -> String {
        switch (name as NSString).pathExtension {
        case "png": "image/png"
        case "md": "text/markdown"
        case "csv": "text/csv"
        case "tsv": "text/tab-separated-values"
        case "log": "text/plain"
        case "html": "text/html"
        case "svg": "image/svg+xml"
        case "pdf": "application/pdf"
        case "ipynb": "application/x-ipynb+json"
        case "zip": "application/zip"
        default: "application/octet-stream"
        }
    }

    static let report = """
    # Primer design

    Designed **6 primer pairs** for the three made-up target genes. All melt between 58 and 62 °C.

    ![Melting points](primer-melting-points.png)

    1. Pair 1 spans the first exon
    2. Pair 2 is the backup
    3. Pairs 3 to 6 cover the other two genes

    The pairs are in `primer-pairs.csv`. See [the protocol](https://example.com/protocol) for the cycling steps.
    """

    static let primerTable = """
    pair,gene,forward,reverse,tm_c,note
    1,GENE-A,ACGTTGCAAGTCCTGA,TTGACCGGTAACGTCA,58.4,"spans exon 1, preferred"
    2,GENE-A,AGCTTGACCGTAAGTC,CCATGGTTACGATCGA,60.1,backup
    3,GENE-B,TTGCAGTCCAGTACGA,GATCCGTTAGCATGCA,61.7,"says ""check"" on gel"
    4,GENE-B,CGTAGCTTAGGCATCC,AACGTTGGCCATTGCA,59.2,
    5,GENE-C,GGATCCATGCAAGTCT,TCGATGCAAGGTTCCA,62.0,"two
    lines"
    6,GENE-C,ATGCCGTTAGGACTTC,GCATTGCCAAGTTCGA,58.9,

    """

    static let bufferTable = "buffer\tpH\tsoluble_hours\n"
        + "HEPES\t7.5\t44\nTris\t8.0\t27\nPhosphate\t7.0\t31\nMOPS\t7.2\t36\n"

    static let screenNotes = """
    ## Buffer screen

    - 24 wells, 3 buffers, 8 concentrations
    - HEPES kept the protein soluble longest so far

    _All numbers here are made up._
    """

    static let readingList = """
    # Reading list

    1. A made-up review of dyes for thermal shift assays
    2. Another made-up comparison of melt curves
    """

    static let log = (1...40).map { "[00:\(String(format: "%02d", $0)):00] step \($0): ok" }.joined(separator: "\n")
        + "\n[00:41:00] done: 6 pairs\n"

    /// Never rendered on Bench's origin: the script here never runs.
    static let html = """
    <!doctype html><html><head><title>Summary</title></head>
    <body><h1>Primer design summary</h1><p>Six made-up pairs.</p>
    <script>document.body.append(" (this script never runs from Bench)")</script></body></html>
    """

    static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
    <rect width="120" height="80" fill="#F7F4EC"/><rect x="10" y="10" width="30" height="60" fill="#D97757"/>
    <rect x="45" y="30" width="30" height="40" fill="#D97757"/><rect x="80" y="20" width="30" height="50" fill="#D97757"/>
    <script>/* never runs from Bench */</script></svg>
    """

    static let notebook = """
    {"cells": [{"cell_type": "markdown", "metadata": {}, "source": ["# Made-up analysis"]}],
     "metadata": {}, "nbformat": 4, "nbformat_minor": 5}
    """

    /// One page with a few bars, from CoreGraphics.
    static func pdf() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        context.fill(box)
        context.setFillColor(CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))
        for (index, height) in [220.0, 300, 260, 340].enumerated() {
            context.fill(CGRect(x: 96 + Double(index) * 110, y: 200, width: 70, height: height))
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

// MARK: The chart

/// A two-colour bar chart, ivory and clay, drawn without antialiasing so its
/// PNG and its WebP thumbnails show the same pixels.
enum DemoChart {
    static let aspect = 0.625
    static let ivory: (UInt8, UInt8, UInt8) = (0xF7, 0xF4, 0xEC)
    static let clay: (UInt8, UInt8, UInt8) = (0xD9, 0x77, 0x57)

    /// Which pixels are clay, top row first.
    static func mask(bars: [Double], width: Int) -> (mask: [Bool], height: Int) {
        let height = max(1, Int((Double(width) * aspect).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setShouldAntialias(false)
            context.setFillColor(gray: 1, alpha: 1)
            let w = Double(width), h = Double(height)
            let left = w * 0.08, bottom = h * 0.1, top = h * 0.92
            let slot = (w * 0.88) / Double(max(bars.count, 1))
            // The axis starts a little below the lowest bar, so close values
            // still differ.
            let highest = bars.max() ?? 1, least = bars.min() ?? 0
            let lowest = least - (highest - least) * 0.6
            for (index, value) in bars.enumerated() {
                let share = highest > lowest ? (value - lowest) / (highest - lowest) : 1
                let barHeight = max(1, (top - bottom) * (0.15 + 0.85 * share))
                context.fill(CGRect(x: left + Double(index) * slot + slot * 0.15, y: bottom,
                                    width: max(1, slot * 0.7), height: barHeight))
            }
            // The baseline and the axis.
            context.fill(CGRect(x: left - 2, y: bottom - 2, width: w * 0.88 + 2, height: max(1, h * 0.012)))
            context.fill(CGRect(x: left - 2, y: bottom - 2, width: max(1, w * 0.008), height: top - bottom + 2))
            return true
        }
        guard drawn else { return (Array(repeating: false, count: width * height), height) }
        return (pixels.map { $0 > 127 }, height)
    }

    static func png(bars: [Double], width: Int = 640) -> Data {
        let (mask, height) = mask(bars: bars, width: width)
        var rgba = [UInt8]()
        rgba.reserveCapacity(mask.count * 4)
        for on in mask {
            let colour = on ? clay : ivory
            rgba += [colour.0, colour.1, colour.2, 255]
        }
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }

    /// The thumbnail the daemon would make: WebP, `width` wide.
    static func webp(bars: [Double], width: Int) -> Data {
        let (mask, height) = mask(bars: bars, width: width)
        return DemoWebP.encode(width: width, height: height, mask: mask, off: ivory, on: clay)
    }
}

/// A lossless WebP (VP8L) of a two-colour picture. ImageIO reads WebP but
/// can't write it, so this writes the simplest stream the format allows: no
/// transforms, no colour cache, and each channel a "simple" prefix code of
/// its one or two values, so a pixel costs one bit per channel that differs.
enum DemoWebP {
    static func encode(width: Int, height: Int, mask: [Bool],
                       off: (UInt8, UInt8, UInt8), on: (UInt8, UInt8, UInt8)) -> Data {
        precondition((1...16384).contains(width) && (1...16384).contains(height) && mask.count == width * height)
        var bits = BitWriter()
        bits.write(0x2F, 8) // VP8L signature
        bits.write(width - 1, 14)
        bits.write(height - 1, 14)
        bits.write(0, 1) // no alpha
        bits.write(0, 3) // version 0
        bits.write(0, 1) // no transform
        bits.write(0, 1) // no colour cache
        bits.write(0, 1) // one prefix code group
        // Green, red, blue, alpha, distance: in that order.
        let green = (off.1, on.1), red = (off.0, on.0), blue = (off.2, on.2)
        for channel in [green, red, blue] { bits.simpleCode(channel.0, channel.1) }
        bits.simpleCode(255, 255)
        bits.simpleCode(0, 0)
        for pixel in mask {
            for channel in [green, red, blue] where channel.0 != channel.1 {
                // The larger value has the code 1.
                let value = pixel ? channel.1 : channel.0
                bits.write(value == max(channel.0, channel.1) ? 1 : 0, 1)
            }
        }
        var payload = bits.finish()
        let chunkSize = payload.count
        if payload.count % 2 == 1 { payload.append(0) }
        var data = Data("RIFF".utf8)
        data.append(littleEndian: UInt32(4 + 8 + payload.count))
        data.append(contentsOf: Array("WEBPVP8L".utf8))
        data.append(littleEndian: UInt32(chunkSize))
        data.append(contentsOf: payload)
        return data
    }

    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var buffer: UInt64 = 0
        private var count = 0

        /// Least significant bit first, as VP8L reads.
        mutating func write(_ value: Int, _ width: Int) {
            buffer |= UInt64(value & ((1 << width) - 1)) << UInt64(count)
            count += width
            while count >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: buffer))
                buffer >>= 8
                count -= 8
            }
        }

        /// A simple prefix code of one symbol (`a == b`) or two.
        mutating func simpleCode(_ a: UInt8, _ b: UInt8) {
            let low = min(a, b), high = max(a, b)
            write(1, 1) // simple
            write(low == high ? 0 : 1, 1) // one or two symbols
            if low < 2 {
                write(0, 1)
                write(Int(low), 1)
            } else {
                write(1, 1)
                write(Int(low), 8)
            }
            if low != high { write(Int(high), 8) }
        }

        mutating func finish() -> [UInt8] {
            if count > 0 { bytes.append(UInt8(truncatingIfNeeded: buffer)) }
            buffer = 0
            count = 0
            return bytes
        }
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
