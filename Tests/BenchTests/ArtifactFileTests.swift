import CryptoKit
import Foundation
import Testing
@testable import Bench

struct ArtifactFileTests {
    @Test func aFileLargerThanThePreviewCapIsHashedAndWrittenInChunks() async throws {
        let writer = ArtifactFileWriter()
        let chunk = Data(repeating: 0x6B, count: ArtifactFileLimits.chunk)
        let encoded = chunk.base64EncodedString()
        let chunks = 36 // Nine MiB: deliberately larger than the unchanged preview cap.
        var expectedDigest = SHA256()
        for _ in 0..<chunks {
            try await writer.append(base64: encoded)
            expectedDigest.update(data: chunk)
        }
        let count = chunks * chunk.count
        let file = try await writer.finish(expected: count)
        #expect(count > ArtifactReaderScript.Cap.download)
        #expect(file.bytes == count)
        #expect(file.sha256 == expectedDigest.finalize().map { String(format: "%02x", $0) }.joined())
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        for _ in 0..<chunks { #expect(try handle.read(upToCount: chunk.count) == chunk) }
        #expect(try handle.read(upToCount: 1)?.isEmpty != false)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(await writer.temporaryDirectory == nil)
        await #expect(throws: ArtifactFileWriter.Failure.closed) { try await writer.append(base64: encoded) }
        await #expect(throws: ArtifactFileWriter.Failure.closed) { try await writer.finish(expected: count) }
    }

    @Test func invalidAndOversizedChunksCannotOpenATemporaryFile() async {
        let writer = ArtifactFileWriter()
        await #expect(throws: ArtifactFileWriter.Failure.invalidChunk) { try await writer.append(base64: "not base64!") }
        let over = Data(repeating: 0xFF, count: ArtifactFileLimits.chunk + 1).base64EncodedString()
        await #expect(throws: ArtifactFileWriter.Failure.invalidChunk) { try await writer.append(base64: over) }
        #expect(await writer.bytes == 0)
        #expect(await writer.temporaryDirectory == nil)
        await writer.cancel()
    }

    @Test func theSizeCapIsCheckedAgainstActualBytesAndCancellationRemovesThePartialFile() async throws {
        let writer = ArtifactFileWriter(maximum: 7)
        try await writer.append(base64: Data([1, 2, 3, 4]).base64EncodedString())
        let directory = try #require(await writer.temporaryDirectory)
        await #expect(throws: ArtifactFileWriter.Failure.tooBig) {
            try await writer.append(base64: Data([5, 6, 7, 8]).base64EncodedString())
        }
        #expect(await writer.bytes == 4)
        #expect(try Data(contentsOf: directory.appendingPathComponent("content")) == Data([1, 2, 3, 4]))
        await writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await writer.temporaryDirectory == nil)
        await #expect(throws: ArtifactFileWriter.Failure.closed) { try await writer.append(base64: "AA==") }
        await #expect(throws: ArtifactFileWriter.Failure.closed) { try await writer.finish(expected: nil) }
    }

    @Test func aMisreportedLengthNeverProducesACompletedSpool() async throws {
        for declared in [2, 4, -1] {
            let writer = ArtifactFileWriter()
            try await writer.append(base64: Data([4, 5, 6]).base64EncodedString())
            let directory = try #require(await writer.temporaryDirectory)
            await #expect(throws: ArtifactFileWriter.Failure.wrongLength) { try await writer.finish(expected: declared) }
            await writer.cancel()
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }
    }

    @Test func anEmptyFileHasTheCorrectDigestAndCanBeFinishedWithoutAChunk() async throws {
        let writer = ArtifactFileWriter()
        let file = try await writer.finish(expected: 0)
        #expect(file.bytes == 0)
        #expect(file.sha256 == SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined())
        #expect(try file.prefix(20).isEmpty)
    }

    @Test func savingWithoutReplacementDoesNotOverwriteAnExistingFileAndCleansItsStagingCopy() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("capsid-transfer-save-test-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let writer = ArtifactFileWriter()
        let bytes = Data("the new saved content".utf8)
        try await writer.append(base64: bytes.base64EncodedString())
        let file = try await writer.finish(expected: bytes.count)
        let target = directory.appendingPathComponent("result.txt")
        let original = Data("someone else's file".utf8)
        try original.write(to: target)

        #expect(throws: ShelfSaveError.nameTaken) { try file.copy(to: target, replace: false) }
        #expect(try Data(contentsOf: target) == original)
        #expect(try fm.contentsOfDirectory(atPath: directory.path) == ["result.txt"])
        try file.copy(to: target, replace: true)
        #expect(try Data(contentsOf: target) == bytes)
        let next = directory.appendingPathComponent("another.txt")
        try file.copy(to: next, replace: false)
        #expect(try Data(contentsOf: next) == bytes)
        #expect(try file.prefix(7) == bytes.prefix(7))
        #expect(try fm.contentsOfDirectory(atPath: directory.path).sorted() == ["another.txt", "result.txt"])
    }
}

/// Runs the actual pull/abort scripts. Every reply and byte is made up; no daemon or network is involved.
private final class FileTransferPage {
    private let page: PageScript
    private var nativeOffset = 0
    private var firstPull = true
    private static let setup = #"""
    var location = {href:"http://localhost:8123/session",origin:"http://localhost:8123"};
    var URL = function(path, base) { this.href = path.startsWith("/") ? "http://localhost:8123" + path : path; };
    var btoa = function(binary) {
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        return benchBase64(bytes);
    };
    var config = {status:200, length:12, chunk:12, declared:null, url:null, hold:false};
    var seen = {requests:0, reads:0, pulled:0, aborted:false, cancelled:false};
    var fetch = async function(path, options) {
        seen.requests++; seen.path = path; seen.credentials = options.credentials;
        seen.cache = options.cache; seen.redirect = options.redirect;
        options.signal.addEventListener("abort", function() { seen.aborted = true; });
        let offset = 0;
        return {
            status:config.status,
            url:config.url || "http://localhost:8123" + path,
            headers:{get:function(name) { return name === "Content-Length" ? config.declared : null; }},
            body:{getReader:function() { return {
                read:function() {
                    seen.reads++;
                    if (config.hold) return new Promise(function(resolve, reject) {
                        options.signal.addEventListener("abort", function() { reject(new Error("aborted")); });
                    });
                    if (offset >= config.length) return Promise.resolve({done:true});
                    const length = Math.min(config.chunk, config.length - offset);
                    const bytes = new Uint8Array(length).fill(65);
                    if (config.pattern) for (let i = 0; i < bytes.length; i++) bytes[i] = (offset + i) % 251;
                    offset += length; seen.pulled += length;
                    return Promise.resolve({done:false,value:bytes});
                },
                cancel:async function() { seen.cancelled = true; }
            };}}
        };
    };
    var result = null;
    """#

    init(_ configuration: String = "") {
        page = PageScript(PageScript.timerShim + "\n" + ArtifactReaderScript.codecs + "\n" + Self.setup)
        page.evaluate(configuration)
    }

    func pull(version: String = "version-1", nonce: String = "nonce-1", origin: String = "http://localhost:8123",
              offset: Int? = nil) -> [String: Any]? {
        page.set("testVersion", version); page.set("testNonce", nonce)
        page.set("testOrigin", origin)
        page.evaluate("result = null;")
        page.evaluate("""
        (async function(version, nonce, origin, offset, first) {
        \(ArtifactFileScript.body)
        })(testVersion, testNonce, testOrigin, \(offset ?? nativeOffset), \(firstPull ? "true" : "false"))
            .then(value => { result = value; }, error => { result = 'threw: ' + error; });
        """)
        firstPull = false
        #expect(page.exception == nil)
        let answer = reply()
        if answer?["outcome"] as? String == "chunk", let count = answer?["count"] as? Int { nativeOffset += count }
        return answer
    }

    func reply() -> [String: Any]? {
        guard let raw = page.evaluate("result") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    func abort(nonce: String = "nonce-1") {
        page.set("testNonce", nonce)
        page.evaluate("""
        (async function(nonce) {
        \(ArtifactFileScript.abort)
        })(testNonce);
        """)
        #expect(page.exception == nil)
    }

    func value(_ expression: String) -> String? { page.evaluate(expression) }
}

struct ArtifactFileScriptTests {
    @Test func chunkPullsUseTheAuthenticatedSameOriginWithoutBufferingTheWholeFile() throws {
        let cap = ArtifactFileLimits.chunk
        let page = FileTransferPage("config.length = \(cap * 2 + 7); config.chunk = \(cap * 2); config.declared = '\(cap * 2 + 7)'; config.pattern = true;")
        let first = try #require(page.pull())
        #expect(first["outcome"] as? String == "chunk")
        let firstBase64 = try #require(first["base64"] as? String)
        var reconstructed = try #require(Data(base64Encoded: firstBase64))
        #expect(reconstructed.count == cap)
        #expect(first["offset"] as? Int == 0)
        #expect(page.value("seen.reads") == "1")
        let second = try #require(page.pull())
        let middleBase64 = try #require(second["base64"] as? String)
        let middle = try #require(Data(base64Encoded: middleBase64))
        #expect(middle.count == cap)
        #expect(second["offset"] as? Int == cap)
        reconstructed.append(middle)
        #expect(page.value("seen.reads") == "1") // The next network chunk is not pulled while this one has a remainder.
        let last = try #require(page.pull())
        let endingBase64 = try #require(last["base64"] as? String)
        let ending = try #require(Data(base64Encoded: endingBase64))
        #expect(ending.count == 7)
        #expect(last["offset"] as? Int == cap * 2)
        reconstructed.append(ending)
        #expect(reconstructed == Data((0..<(cap * 2 + 7)).map { UInt8($0 % 251) }))
        #expect(page.pull()?["outcome"] as? String == "done")
        #expect(page.value("seen.requests") == "1")
        #expect(page.value("seen.credentials") == "include")
        #expect(page.value("seen.cache") == "no-store")
        #expect(page.value("seen.redirect") == "error")
        #expect(page.value("Object.keys(globalThis.\(ArtifactFileScript.stateName)).length") == "0")
    }

    @Test func statusesAndUnexpectedResponseURLsAreRefusedBeforeReadingBytes() {
        for (status, outcome) in [(401, "lost"), (404, "missing"), (410, "missing"), (206, "unreadable"), (302, "unreadable"), (500, "unreadable")] {
            let page = FileTransferPage("config.status = \(status);")
            #expect(page.pull()?["outcome"] as? String == outcome)
            #expect(page.value("seen.pulled") == "0")
            #expect(page.value("seen.aborted") == "true")
        }
        for url in ["https://untrusted.example/file", "http://localhost:8123/api/artifacts/versions/another-version"] {
            let page = FileTransferPage("config.url = '\(url)';")
            #expect(page.pull()?["outcome"] as? String == "unreadable")
            #expect(page.value("seen.pulled") == "0")
        }
    }

    @Test func theDeclaredCapAndTheActualCompletedLengthAreBothChecked() {
        let declared = FileTransferPage("config.declared = '\(ArtifactFileLimits.maximum + 1)';")
        #expect(declared.pull()?["outcome"] as? String == "tooBig")
        #expect(declared.value("seen.reads") == "0")
        for length in [11, 13] {
            let page = FileTransferPage("config.declared = '\(length)';")
            #expect(page.pull()?["outcome"] as? String == "chunk")
            #expect(page.pull()?["outcome"] as? String == "unreadable")
        }
    }

    @Test func cancelReleasesTheReaderAndAnAwaitingPull() {
        let page = FileTransferPage("config.hold = true;")
        #expect(page.pull()?.isEmpty == nil)
        #expect(page.value("seen.reads") == "1")
        page.abort()
        #expect(page.reply()?["outcome"] as? String == "cancelled")
        #expect(page.value("seen.aborted") == "true")
        #expect(page.value("seen.cancelled") == "true")
        #expect(page.value("Object.keys(globalThis.\(ArtifactFileScript.stateName)).length") == "0")
    }

    @Test func aPathInjectionAndANonceReusedForAnotherVersionAreRefused() {
        let path = FileTransferPage()
        #expect(path.pull(version: "../another-resource")?["outcome"] as? String == "unreadable")
        #expect(path.value("seen.requests") == "0")
        let nonce = FileTransferPage()
        #expect(nonce.pull()?["outcome"] as? String == "chunk")
        #expect(nonce.pull(version: "another-version")?["outcome"] as? String == "cancelled")
        #expect(nonce.value("seen.requests") == "1")
    }

    @Test func aLostPageStateDoesNotSilentlyRestartTheDownload() {
        let page = FileTransferPage("config.length = 24;")
        #expect(page.pull()?["outcome"] as? String == "chunk")
        _ = page.value("delete globalThis.\(ArtifactFileScript.stateName)['nonce-1']")
        #expect(page.pull()?["outcome"] as? String == "unreadable")
        #expect(page.value("seen.requests") == "1")
    }

    @Test func aChangedPageOriginAndAMismatchedOffsetAreRefused() {
        let origin = FileTransferPage()
        #expect(origin.pull(origin: "http://localhost:9999")?["outcome"] as? String == "unreadable")
        #expect(origin.value("seen.requests") == "0")
        let offset = FileTransferPage("config.length = 24;")
        #expect(offset.pull()?["outcome"] as? String == "chunk")
        #expect(offset.pull(offset: 1)?["outcome"] as? String == "unreadable")
        #expect(offset.value("seen.requests") == "1")
        #expect(offset.value("seen.aborted") == "true")
    }

    @Test func emptyAndUnknownLengthBodiesFinishWithoutInventingADeclaredLength() {
        let empty = FileTransferPage("config.length = 0;")
        let noBytes = empty.pull()
        #expect(noBytes?["outcome"] as? String == "done")
        #expect(noBytes?["offset"] as? Int == 0)
        #expect(noBytes?["total"] is NSNull)
        let unknown = FileTransferPage()
        #expect(unknown.pull()?["outcome"] as? String == "chunk")
        let complete = unknown.pull()
        #expect(complete?["outcome"] as? String == "done")
        #expect(complete?["offset"] as? Int == 12)
        #expect(complete?["total"] is NSNull)
    }
}
