// ShelfAddressTests.swift — which file a figure or a link on the page is,
// from its address alone (Shelf/ShelfAddress.swift): every shape that names a
// version, and the many that don't. Made-up ids and ports; nothing is read.
import Foundation
import Testing
@testable import Bench

struct ShelfAddressTests {
    static let version = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
    static let other = "6d1f0c2e-7a3b-4c8d-9e10-2b3c4d5e6f70"
    static let port = 8123

    private func version(_ address: String, port: Int? = Self.port) -> String? {
        ShelfAddress.version(in: address, daemonPort: port)
    }

    // MARK: Shapes that name a version

    @Test func theBytesOfAVersionNameIt() {
        let v = Self.version
        #expect(version("http://localhost:8123/api/artifacts/versions/\(v)") == v)
        #expect(version("http://127.0.0.1:8123/api/artifacts/versions/\(v)") == v)
    }

    @Test func aThumbnailNamesItToo() {
        let v = Self.version
        #expect(version("http://localhost:8123/api/artifacts/versions/\(v)?thumbnail=120") == v)
        #expect(version("http://localhost:8123/api/artifacts/versions/\(v)?thumbnail=800") == v)
    }

    @Test func theTailsTheBytesAreServedUnder() {
        let v = Self.version
        for tail in ["download", "raw", "content", "file", "thumbnail"] {
            #expect(version("http://localhost:8123/api/artifacts/versions/\(v)/\(tail)") == v, "\(tail)")
        }
        // A fragment or other query on the address changes nothing.
        #expect(version("http://localhost:8123/api/artifacts/versions/\(v)?download=1#top") == v)
    }

    @Test func aLinkThatCarriesTheVersionInItsQuery() {
        let v = Self.version
        #expect(version("http://localhost:8123/artifacts/\(Self.other)?v=\(v)") == v)
        #expect(version("http://localhost:8123/projects/p/frames/f?x=1&v=\(v)") == v)
        #expect(version("http://localhost:8123/x?version=\(v)") == v)
        #expect(version("http://localhost:8123/x?version_id=\(v)") == v)
        #expect(version("http://localhost:8123/x?versionId=\(v)") == v)
    }

    // MARK: Shapes that don't

    @Test func otherPathsUnderVersionsAreNotAFile() {
        let v = Self.version
        // Its provenance, its annotations and a deeper path are not the file.
        for tail in ["lineage?slim=1", "lineage", "annotations", "verification", "download/extra", "../x"] {
            #expect(version("http://localhost:8123/api/artifacts/versions/\(v)/\(tail)") == nil, "\(tail)")
        }
    }

    @Test func anArtifactIdIsNotAVersion() {
        // /api/artifacts/<artifact>/versions lists versions; it is not one.
        #expect(version("http://localhost:8123/api/artifacts/\(Self.other)/versions") == nil)
        #expect(version("http://localhost:8123/api/artifacts/\(Self.other)") == nil)
    }

    @Test func anIdThatIsNotTheDaemonsShapeIsNotTaken() {
        for id in ["v1", "1C8D3A5F-2B3C-4D4E-9F00-B1C2D3E4F5A6", String(Self.version.dropLast()), Self.version + "0",
                   "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6/../x", "..", "%2E%2E"] {
            #expect(version("http://localhost:8123/api/artifacts/versions/\(id)") == nil, "\(id)")
            #expect(version("http://localhost:8123/x?v=\(id)") == nil, "\(id)")
        }
        // A cache-busting number is not a version.
        #expect(version("http://localhost:8123/logo.png?v=3") == nil)
    }

    @Test func onlyTheDaemonsOwnOriginCounts() {
        let v = Self.version
        let path = "/api/artifacts/versions/\(v)"
        #expect(version("http://localhost:9999\(path)") == nil)
        #expect(version("http://example.com:8123\(path)") == nil)
        #expect(version("https://localhost:8123\(path)") == nil)
        #expect(version("blob:http://localhost:8123/\(v)") == nil)
        #expect(version("data:image/png;base64,AAAA") == nil)
        #expect(version("javascript:alert(1)") == nil)
        // A page whose port isn't known yet answers nothing.
        #expect(version("http://localhost:8123\(path)", port: nil) == nil)
        // A relative address is the browser's to resolve before it gets here.
        #expect(version(path) == nil)
    }

    @Test func aHugeOrBrokenAddressIsRefused() {
        let v = Self.version
        #expect(version("http://localhost:8123/api/artifacts/versions/\(v)?" + String(repeating: "a", count: ShelfAddress.maxLength)) == nil)
        #expect(version("") == nil)
        #expect(version("not a url at all") == nil)
        #expect(version("http://") == nil)
    }

    // MARK: Names

    @Test func theNameIsTheElementsWordsOnOneLine() {
        #expect(ShelfAddress.name(hint: "z_prime_by_plate.png", isImage: true) == "z_prime_by_plate.png")
        #expect(ShelfAddress.name(hint: "  Z prime by plate \n and more", isImage: true) == "Z prime by plate")
        #expect(ShelfAddress.name(hint: "a\u{0000}b\u{0007}c", isImage: false) == "abc")
        #expect(ShelfAddress.name(hint: String(repeating: "n", count: 400), isImage: false).count == HistoryFile.nameLimit)
    }

    @Test func withNoWordsThePlainNounStandsIn() {
        #expect(ShelfAddress.name(hint: "", isImage: true) == "Figure")
        #expect(ShelfAddress.name(hint: "   \n ", isImage: true) == "Figure")
        #expect(ShelfAddress.name(hint: "", isImage: false) == "File")
    }

    @Test func aPictureWithNoExtensionIsStillAnImage() {
        let figure = ShelfAddress.entry(version: Self.version, name: "Z prime by plate", isImage: true)
        #expect(figure.kind == .image)
        #expect(figure.version == Self.version)
        #expect(figure.size == 0 && figure.artifact == nil)
        // Its own extension decides when it has one.
        #expect(ShelfAddress.entry(version: Self.version, name: "plate.svg", isImage: true).kind == .svg)
        #expect(ShelfAddress.entry(version: Self.version, name: "qc_notes.md", isImage: false).kind == .markdown)
        // A link with no extension in its words isn't guessed to be a picture.
        #expect(ShelfAddress.entry(version: Self.version, name: "the notes", isImage: false).kind == .other)
    }
}
