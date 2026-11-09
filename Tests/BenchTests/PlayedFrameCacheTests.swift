// PlayedFrameCacheTests.swift — the rendered-frame cache behind a specimen's
// loops (Shared/PlayedViews.swift): the budget, which entry goes first, that a
// hit is the very images stored, and that anything which changes a render is a
// different key. Frames are small blank bitmaps; nothing is rendered.
import CoreGraphics
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct PlayedFrameCacheTests {
    private let scene = LabScene(name: "Test", theme: .bench, duration: 1) { _, _, _, _ in }

    private func key(_ from: Int = 0, to: Int = 1, scene: LabScene? = nil, size: CGSize = CGSize(width: 10, height: 10),
                     scale: CGFloat = 2, tint: Color = .red, fps: Double = 30) -> PlayedFrameCache.Key {
        PlayedFrameCache.Key(scene: scene ?? self.scene, from: from, to: to, size: size, scale: scale, tint: tint, fps: fps)
    }

    /// `count` images of `side` x `side` pixels: side * side * 4 bytes each.
    private func frames(_ count: Int = 1, side: Int = 10) -> [CGImage] {
        (0..<count).map { _ in
            CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    @Test func aHitIsTheVeryImagesStored() {
        let cache = PlayedFrameCache(budget: 10_000)
        let stored = frames(2)
        cache.store(stored, for: key())
        let hit = cache.frames(for: key())
        #expect(hit?.count == 2)
        #expect(zip(hit ?? [], stored).allSatisfy { $0 === $1 })
        #expect(cache.frames(for: key(5, to: 6)) == nil)
    }

    @Test func theLeastRecentlyUsedGoesFirstOnceOverBudget() {
        // Each entry is 400 bytes; 1,000 holds two.
        let cache = PlayedFrameCache(budget: 1000)
        cache.store(frames(), for: key(0))
        cache.store(frames(), for: key(1))
        _ = cache.frames(for: key(0))        // 0 is now newer than 1
        cache.store(frames(), for: key(2))   // 1 goes
        #expect(cache.frames(for: key(1)) == nil)
        #expect(cache.frames(for: key(0)) != nil)
        #expect(cache.frames(for: key(2)) != nil)
        #expect(cache.bytes == 800 && cache.count == 2)
    }

    @Test func oneThatCannotFitIsNotKeptAndEvictsNothing() {
        let cache = PlayedFrameCache(budget: 1000)
        cache.store(frames(), for: key(0))
        cache.store(frames(4), for: key(1))  // 1,600 bytes
        cache.store([], for: key(2))
        #expect(cache.count == 1 && cache.bytes == 400)
        #expect(cache.frames(for: key(0)) != nil)
    }

    @Test func storingAKeyAgainReplacesItAndCountsItOnce() {
        let cache = PlayedFrameCache(budget: 1000)
        cache.store(frames(), for: key())
        let newer = frames(2)
        cache.store(newer, for: key())
        #expect(cache.count == 1 && cache.bytes == 800)
        #expect(cache.frames(for: key())?.first === newer.first)
    }

    @Test func anythingThatChangesTheRenderIsAnotherKey() {
        let base = key()
        let other = LabScene(name: "Other", theme: .bench, duration: 1) { _, _, _, _ in }
        let longer = LabScene(name: "Test", theme: .bench, duration: 2) { _, _, _, _ in }
        #expect(base == key())
        #expect(base != key(scene: other))
        #expect(base != key(scene: longer))
        #expect(base != key(1, to: 2))
        #expect(base != key(to: 2))
        #expect(base != key(size: CGSize(width: 11, height: 10)))
        #expect(base != key(scale: 1))
        #expect(base != key(tint: .blue))
        #expect(base != key(tint: Color.red.opacity(0.5)))
        #expect(base != key(fps: 15))
    }
}
