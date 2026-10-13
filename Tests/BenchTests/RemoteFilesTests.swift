// RemoteFilesTests.swift — how files are classed for the phone, and which
// versions a device may fetch.
import Foundation
import Testing
@testable import Bench

struct ArtifactKindTests {
    @Test func theExtensionDecides() {
        #expect(ArtifactKind.classify(name: "figure.PNG", mime: nil) == .image)
        #expect(ArtifactKind.classify(name: "notes.md", mime: "text/plain") == .markdown)
        #expect(ArtifactKind.classify(name: "counts.tsv", mime: "application/octet-stream") == .table)
        #expect(ArtifactKind.classify(name: "run.log", mime: nil) == .text)
        #expect(ArtifactKind.classify(name: "analysis.ipynb", mime: "application/json") == .notebook)
        #expect(ArtifactKind.classify(name: "report.pdf", mime: nil) == .pdf)
    }

    @Test func theContentTypeFillsInWithoutAnExtension() {
        #expect(ArtifactKind.classify(name: "plot", mime: "image/webp") == .image)
        #expect(ArtifactKind.classify(name: "table", mime: "text/csv; charset=utf-8") == .table)
        #expect(ArtifactKind.classify(name: "blob", mime: "application/zip") == .other)
        #expect(ArtifactKind.classify(name: "readme", mime: "text/x-rst") == .text)
    }

    @Test func scriptCapableTypesAlwaysWin() {
        #expect(ArtifactKind.classify(name: "harmless.txt", mime: "text/html") == .html)
        #expect(ArtifactKind.classify(name: "picture.png", mime: "image/svg+xml") == .svg)
        #expect(ArtifactKind.classify(name: "page.htm", mime: nil) == .html)
        #expect(ArtifactKind.classify(name: "diagram.svg", mime: "image/png") == .svg)
    }
}

@MainActor
struct ListedFilesTests {
    @Test func aDeviceMayFetchOnlyWhatItWasListed() {
        let files = ListedFiles()
        files.record(["v1", "v2"], device: "phone")
        #expect(files.allows("v1", device: "phone"))
        #expect(!files.allows("v3", device: "phone"))
        #expect(!files.allows("v1", device: "tablet"))
    }

    @Test func aListingLastsAnHourFromWhenItWasLastListed() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let files = ListedFiles(now: { now })
        files.record(["v1"], device: "phone")
        now += ListedFiles.lifetime - 1
        #expect(files.allows("v1", device: "phone"))
        files.record(["v1"], device: "phone")
        now += ListedFiles.lifetime - 1
        #expect(files.allows("v1", device: "phone"))
        now += 2
        #expect(!files.allows("v1", device: "phone"))
    }

    @Test func forgettingADeviceDropsItsListings() {
        let files = ListedFiles()
        files.record(["v1"], device: "phone")
        files.forget(device: "phone")
        #expect(!files.allows("v1", device: "phone"))
    }

    @Test func theOldestGoFirstPastCapacity() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let files = ListedFiles(now: { now })
        files.record(["first"], device: "phone")
        now += 1
        files.record((0..<ListedFiles.capacity).map { "v\($0)" }, device: "phone")
        #expect(!files.allows("first", device: "phone"))
        #expect(files.allows("v0", device: "phone"))
    }
}

@MainActor
struct ListedFilesForgetAllTests {
    @Test func removingEveryDeviceForgetsEveryListing() {
        let files = ListedFiles()
        files.record(["v1"], device: "phone")
        files.record(["v2"], device: "tablet")
        files.forgetAll()
        #expect(!files.allows("v1", device: "phone"))
        #expect(!files.allows("v2", device: "tablet"))
    }
}
