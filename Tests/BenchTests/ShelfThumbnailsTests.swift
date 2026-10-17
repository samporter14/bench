// ShelfThumbnailsTests.swift — the results shelf's thumbnail store on pictures
// made in code: the byte budget and least-recently-used eviction on synthetic
// pictures, replacement costs, what is refused (not an image, a header that
// declares too many pixels, one picture over the whole budget), what a large
// image is kept as (small, never decoded at full size), that a picture is
// decoded once, and that a decode finishing after the store was emptied keeps
// nothing. No wall-clock waits: decodes are awaited with `settled()`, and a
// decode held mid-way waits on a semaphore the test lets go.
import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import Bench

// MARK: Made-up pictures

/// A flat picture of this size, drawn in code.
func madeUpPicture(_ width: Int, _ height: Int, gray: CGFloat = 0.5) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(gray: gray, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(gray: 1 - gray, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    return context.makeImage()!
}

/// The picture as a PNG, or as a JPEG that says it is stored on its side
/// (EXIF orientation 6: to be turned a quarter clockwise).
func madeUpBytes(_ width: Int, _ height: Int, type: UTType = .png, orientation: Int? = nil) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)!
    var options: [CFString: Any] = [:]
    if let orientation { options[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, madeUpPicture(width, height), options as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

private func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    return ~crc
}

private func bigEndian(_ value: UInt32) -> [UInt8] {
    [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
}

/// A flat black 1-bit PNG that declares this size, however large, and is a
/// few KB: a decompression bomb, since ImageIO would decode it to 8 bits a
/// pixel (400 MB at 20,000 × 20,000). Its header is the only cheap place to learn the size.
func madeUpFlatPNG(width: Int, height: Int) -> Data {
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
    }
    let rows = Data(count: (1 + (width + 7) / 8) * height)
    // The zlib stream: its header, the deflated rows, and the Adler-32 of all-zero bytes
    // (A stays 1, B counts the bytes).
    let deflated = (try? (rows as NSData).compressed(using: .zlib) as Data) ?? Data()
    let adler = bigEndian(UInt32((rows.count % 65_521) << 16 | 1))
    let header = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [1, 0, 0, 0, 0]
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header)
                + chunk("IDAT", [0x78, 0x9C] + [UInt8](deflated) + adler) + chunk("IEND", []))
}

/// A one-page PDF: bytes ImageIO opens, but not as an image.
private func madeUpPDF() -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 50, height: 50)
    let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private func refusal(_ result: Result<CGImage, ShelfThumbnailRefusal>) -> ShelfThumbnailRefusal? {
    if case .failure(let refusal) = result { refusal } else { nil }
}

private func picture(_ result: Result<CGImage, ShelfThumbnailRefusal>) -> CGImage? {
    if case .success(let image) = result { image } else { nil }
}

// MARK: Counting and holding decodes

/// The real decoder, counting what it is asked to decode.
final class ThumbnailDecodeLog: Sendable {
    private let seen = OSAllocatedUnfairLock(initialState: [Data]())

    var inputs: [Data] { seen.withLock { $0 } }
    var count: Int { inputs.count }

    var decoder: ShelfThumbnails.Decoder {
        { [self] data in
            seen.withLock { $0.append(data) }
            return ShelfThumbnails.decode(data)
        }
    }
}

/// The real decoder, held until the test calls `open()`, which lets every decode
/// go, those held and those to come (a test that fails must fail, not hang).
final class ThumbnailDecodeGate: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func open() { for _ in 0..<1_000 { semaphore.signal() } }

    var decoder: ShelfThumbnails.Decoder {
        { [self] data in
            semaphore.wait()
            return ShelfThumbnails.decode(data)
        }
    }
}

/// How many times a store said it changed.
@MainActor
final class ChangeCount {
    private(set) var count = 0
    private var subscription: (any Cancellable)?

    init(_ publisher: some Publisher<Void, Never>) {
        subscription = publisher.sink { [weak self] in MainActor.assumeIsolated { self?.count += 1 } }
    }
}

// MARK: The tests

@MainActor
struct ShelfThumbnailsTests {
    // MARK: The budget

    @Test func theNumbersAreWhatTheRowDraws() {
        // The row draws 36 pt square, filled: 72 px on a Retina screen; the long side is twice that.
        #expect(ShelfThumbnails.pixelSide == 2 * 2 * 36)
        let largest = ShelfThumbnails.cost(of: madeUpPicture(ShelfThumbnails.pixelSide, ShelfThumbnails.pixelSide))
        #expect(largest >= 144 * 144 * 4 + ShelfThumbnails.entryOverhead)
        // About 200 of the largest, as many as the shelf used to count; a hard bound in bytes.
        #expect(ShelfThumbnails.defaultBudget / largest >= 190)
        #expect(ShelfThumbnails.defaultBudget == 16 * 1_024 * 1_024)
    }

    @Test func pastTheBudgetTheLeastRecentlyUsedGoAndTheTotalNeverExceedsIt() {
        let one = ShelfThumbnails.cost(of: madeUpPicture(100, 100))
        let store = ShelfThumbnails(budget: 3 * one)
        for n in 1...9 {
            #expect(store.insert(madeUpPicture(100, 100), for: "v\(n)"))
            #expect(store.totalCost <= store.budget, "after storing \(n)")
        }
        #expect(store.versions == ["v7", "v8", "v9"])
        #expect(store.totalCost == 3 * one)
    }

    @Test func aRecentlyReadPictureSurvivesAndAPeekDoesNot() {
        let one = ShelfThumbnails.cost(of: madeUpPicture(100, 100))
        let store = ShelfThumbnails(budget: 3 * one)
        for name in ["a", "b", "c"] { store.insert(madeUpPicture(100, 100), for: name) }
        // Drawn: used. Asked about only: not.
        #expect(store.image(for: "a") != nil)
        #expect(store.contains("b"))
        store.insert(madeUpPicture(100, 100), for: "d")
        #expect(store.versions == ["a", "c", "d"], "b was the least recently used")
        // Then c is the oldest use.
        store.insert(madeUpPicture(100, 100), for: "e")
        #expect(store.versions == ["a", "d", "e"])
    }

    @Test func aVersionStoredAgainReplacesItsCostAndNeverCountsTwice() {
        let small = madeUpPicture(100, 100), big = madeUpPicture(200, 150)
        let store = ShelfThumbnails()
        store.insert(small, for: "v")
        #expect(store.totalCost == ShelfThumbnails.cost(of: small))
        store.insert(big, for: "v")
        #expect(store.totalCost == ShelfThumbnails.cost(of: big))
        store.insert(small, for: "v")
        #expect(store.totalCost == ShelfThumbnails.cost(of: small))
        #expect(store.versions == ["v"])
        // At a full budget, a replacement of the same size pushes nobody out.
        let one = ShelfThumbnails.cost(of: small)
        let full = ShelfThumbnails(budget: 3 * one)
        for name in ["a", "b", "c"] { full.insert(small, for: name) }
        full.insert(madeUpPicture(100, 100, gray: 0.2), for: "b")
        #expect(full.versions == ["a", "b", "c"] && full.totalCost == 3 * one)
        // A bigger replacement pushes out the least recently used, still within the budget.
        full.insert(madeUpPicture(100, 150), for: "c")
        #expect(full.totalCost <= full.budget)
        #expect(full.contains("c") && !full.contains("a"))
    }

    @Test func aPictureCostingMoreThanTheWholeBudgetIsRefusedAndNothingIsDisturbed() {
        let small = madeUpPicture(20, 20)
        let store = ShelfThumbnails(budget: ShelfThumbnails.cost(of: small) + 100)
        store.insert(small, for: "kept")
        let before = store.totalCost
        #expect(!store.insert(madeUpPicture(200, 200), for: "huge"))
        #expect(store.versions == ["kept"] && store.totalCost == before)
        #expect(store.knows("huge"), "marked, so it isn't read in a loop")
        #expect(!store.contains("huge"))
    }

    @Test func aRowReadingPublishesNothingButAPictureComingOrGoingDoes() {
        let store = ShelfThumbnails()
        let changes = ChangeCount(store.objectWillChange)
        store.insert(madeUpPicture(50, 50), for: "v")
        #expect(changes.count == 1)
        for _ in 0..<20 { _ = store.image(for: "v"); _ = store.contains("v"); _ = store.knows("v") }
        #expect(changes.count == 1, "a row may read while it draws")
        store.removeAll()
        #expect(changes.count == 2)
        store.removeAll()
        #expect(changes.count == 2, "nothing was there")
    }

    // MARK: What is refused

    @Test func bytesThatAreNotAPictureKeepNothingAndAreNotAskedForAgain() async {
        let log = ThumbnailDecodeLog()
        let store = ShelfThumbnails(decoder: log.decoder)
        let changes = ChangeCount(store.objectWillChange)
        let junk = Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)
        store.receive(junk, for: "junk")
        #expect(store.knows("junk"), "being decoded already counts: a second ask must not read it again")
        await store.settled()
        #expect(log.inputs == [junk])
        #expect(!store.contains("junk") && store.totalCost == 0 && store.versions.isEmpty)
        #expect(store.knows("junk"), "failed, so not fetched in a loop")
        #expect(changes.count == 0)
        // Closing the window forgets it, so it is tried again when the window opens again.
        store.removeAll()
        #expect(!store.knows("junk"))
        #expect(refusal(ShelfThumbnails.decode(Data())) == .notAnImage)
        #expect(refusal(ShelfThumbnails.decode(madeUpBytes(100, 100).prefix(60))) == .notAnImage, "cut short")
        #expect(refusal(ShelfThumbnails.decode(madeUpPDF())) == .notAnImage, "ImageIO opens it, but it isn't an image")
    }

    @Test func aHeaderDeclaringTooManyPixelsIsRefusedBeforeAnyDecode() async {
        // The most a WebP can declare, 16,384 × 16,384, is 268 million pixels:
        // 1 GB decoded, from a few KB. Refused on the size in its header, with the
        // reason that says so.
        let bomb = madeUpFlatPNG(width: 16_384, height: 16_384)
        #expect(bomb.count < 100_000)
        #expect(refusal(ShelfThumbnails.decode(bomb)) == .tooLarge)
        // Through the store: nothing kept, and marked so it isn't read in a loop.
        let log = ThumbnailDecodeLog()
        let store = ShelfThumbnails(decoder: log.decoder)
        store.receive(bomb, for: "bomb")
        await store.settled()
        #expect(store.versions.isEmpty && store.totalCost == 0 && store.knows("bomb"))
        // The limit is 4096 × 4096 pixels, at the edge exact.
        #expect(ShelfThumbnails.maxSourcePixels == 4_096 * 4_096)
        #expect(refusal(ShelfThumbnails.decode(madeUpFlatPNG(width: 4_097, height: 4_096))) == .tooLarge)
        let edge = picture(ShelfThumbnails.decode(madeUpFlatPNG(width: 4_096, height: 4_096)))
        #expect(edge?.width == 144 && edge?.height == 144, "at the limit it is decoded, small")
        let exact = madeUpBytes(100, 100)
        #expect(picture(ShelfThumbnails.decode(exact, maxSourcePixels: 10_000)) != nil)
        #expect(refusal(ShelfThumbnails.decode(exact, maxSourcePixels: 9_999)) == .tooLarge)
    }

    // MARK: What is kept

    @Test func aLargeImageIsKeptSmallNotAtFullSize() async {
        let large = madeUpBytes(4_000, 3_000)
        let tall = madeUpBytes(3_000, 4_000)
        let log = ThumbnailDecodeLog()
        let store = ShelfThumbnails(decoder: log.decoder)
        store.receive(large, for: "wide")
        store.receive(tall, for: "tall")
        await store.settled()
        let wide = store.image(for: "wide"), upright = store.image(for: "tall")
        #expect(wide?.width == 144 && wide?.height == 108)
        #expect(upright?.width == 108 && upright?.height == 144)
        // Counted at what is kept: two thumbnails of about 63 KB, where one at full size is 48 MB.
        let full = 4_000 * 3_000 * 4
        #expect(store.totalCost < full / 100)
        #expect(store.totalCost == ShelfThumbnails.cost(of: wide!) + ShelfThumbnails.cost(of: upright!))
        #expect(ShelfThumbnails.cost(of: wide!) >= 144 * 108 * 4, "never less than width × height × 4")
        #expect(store.totalCost <= store.budget)
    }

    @Test func aPictureIsKeptUprightAndASmallOneIsNeverEnlarged() async {
        // Stored on its side (EXIF 6): 200 × 100 on disk, 100 × 200 to look at.
        let sideways = madeUpBytes(200, 100, type: .jpeg, orientation: 6)
        let turned = picture(ShelfThumbnails.decode(sideways))
        #expect(turned?.width == 72 && turned?.height == 144)
        // The daemon's own kind of thumbnail: WebP, 120 px wide, as it comes.
        let webp = DemoChart.webp(bars: [3, 5, 4, 6], width: 120)
        let daemon = picture(ShelfThumbnails.decode(webp))
        #expect(daemon?.width == 120 && daemon?.height == 75)
        #expect((daemon?.height ?? 0) >= 72, "the short side still fills the row's 72 px")
        let tiny = picture(ShelfThumbnails.decode(madeUpBytes(30, 20)))
        #expect(tiny?.width == 30 && tiny?.height == 20)
    }

    @Test func askingForTheSameImageAgainDecodesOnce() async {
        let log = ThumbnailDecodeLog()
        let store = ShelfThumbnails(decoder: log.decoder)
        let changes = ChangeCount(store.objectWillChange)
        store.receive(DemoChart.webp(bars: [3, 5, 4], width: 120), for: "v")
        await store.settled()
        let first = store.image(for: "v")
        #expect(first != nil)
        let seen = changes.count
        for _ in 0..<50 { #expect(store.image(for: "v") === first) }
        #expect(log.count == 1)
        #expect(changes.count == seen)
        // Another version is a decode of its own.
        store.receive(DemoChart.webp(bars: [9, 1], width: 120), for: "w")
        await store.settled()
        #expect(log.count == 2 && store.versions == ["v", "w"])
        #expect(store.image(for: "v") === first)
    }

    @Test func bytesForAKeptVersionReplaceItsPictureAtItsNewCost() async {
        let store = ShelfThumbnails()
        store.receive(madeUpBytes(100, 50), for: "v")
        await store.settled()
        let first = store.totalCost
        #expect(first == ShelfThumbnails.cost(of: store.image(for: "v")!))
        store.receive(madeUpBytes(140, 140), for: "v")
        await store.settled()
        #expect(store.totalCost > first && store.versions == ["v"])
        #expect(store.totalCost == ShelfThumbnails.cost(of: store.image(for: "v")!), "the new cost, not both")
    }

    // MARK: Letting go

    @Test func aDecodeFinishingAfterTheStoreWasEmptiedKeepsNothing() async {
        let gate = ThumbnailDecodeGate()
        let store = ShelfThumbnails(decoder: gate.decoder)
        store.receive(madeUpBytes(100, 100), for: "v")
        #expect(store.knows("v"))
        store.removeAll()
        #expect(!store.knows("v"), "the window closed")
        gate.open()
        await store.settled()
        #expect(store.versions.isEmpty && store.totalCost == 0 && !store.knows("v"))
    }

    @Test func removeAllLetsEveryPictureGo() {
        let store = ShelfThumbnails()
        for n in 1...5 { store.insert(madeUpPicture(60, 60), for: "v\(n)") }
        #expect(store.totalCost > 0)
        store.removeAll()
        #expect(store.versions.isEmpty && store.totalCost == 0)
        #expect(store.image(for: "v1") == nil)
    }
}
