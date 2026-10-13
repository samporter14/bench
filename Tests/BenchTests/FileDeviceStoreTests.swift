// FileDeviceStoreTests.swift — the paired devices' file: private to this
// user, whole on every write, and quiet when it isn't there. Each test uses
// its own temporary folder, never Bench's real one.
import Foundation
import Testing
@testable import Bench

@MainActor
struct FileDeviceStoreTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Bench", isDirectory: true)
    }

    private func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func nothingStoredReadsAsNothing() throws {
        let store = FileDeviceStore(folder: folder())
        #expect(try store.load() == nil)
        try store.delete()
    }

    @Test func whatIsSavedComesBackAndOnlyThisUserCanReadIt() throws {
        let place = folder()
        let store = FileDeviceStore(folder: place)
        try store.save(Data("first".utf8))
        try store.save(Data("second".utf8))
        #expect(try store.load() == Data("second".utf8))
        #expect(try mode(place) == 0o700)
        #expect(try mode(place.appendingPathComponent("remote-devices.json")) == 0o600)
        // Written whole and renamed: no temporary files left behind.
        let left = try FileManager.default.contentsOfDirectory(atPath: place.path)
        #expect(left == ["remote-devices.json"])
    }

    @Test func eachNameIsItsOwnFile() throws {
        let place = folder()
        let devices = FileDeviceStore(folder: place)
        let key = FileDeviceStore(name: PushCenter.keyFile, folder: place)
        try devices.save(Data("devices".utf8))
        try key.save(Data("key".utf8))
        #expect(try devices.load() == Data("devices".utf8))
        #expect(try key.load() == Data("key".utf8))
        try devices.delete()
        #expect(try devices.load() == nil)
        #expect(try key.load() == Data("key".utf8))
    }
}
