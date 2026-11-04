// Large saves stay in the authenticated page, but cross the WebKit bridge a
// bounded chunk at a time. The private spool and its checksum are built off
// the main actor. Preview/clipboard reads retain their smaller in-memory cap.
import Foundation
import CryptoKit
import WebKit
import Combine
import Darwin
import SwiftUI

enum ArtifactFileLimits {
    static let chunk = 256 * 1024
    static let maximum = 512 * 1024 * 1024
    static let timeout: Duration = .seconds(300)
}

/// Immutable shared ownership: deduplicated consumers can copy the same spool.
/// The private directory disappears after the last consumer releases it.
final class ArtifactFile: Sendable, Equatable {
    let url: URL
    let bytes: Int
    let sha256: String
    private let directory: URL

    init(url: URL, bytes: Int, sha256: String, directory: URL) {
        self.url = url; self.bytes = bytes; self.sha256 = sha256; self.directory = directory
    }

    static func == (lhs: ArtifactFile, rhs: ArtifactFile) -> Bool { lhs === rhs }

    deinit {
        let folder = directory
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
    }

    /// Called only from disk workers. Stage beside the destination, then
    /// atomically publish it; an exclusive save can never replace a new file.
    func copy(to destination: URL, replace: Bool) throws {
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".capsid-copy-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: url, to: temporary)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                replace ? Darwin.rename(source!, target!) : Darwin.renamex_np(source!, target!, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            if errno == EEXIST { throw ShelfSaveError.nameTaken }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    /// Only the short legend preview needs bytes after a large transfer.
    func prefix(_ limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: limit) ?? Data()
    }
}

actor ArtifactFileWriter {
    enum Failure: Error, Equatable { case tooBig, invalidChunk, wrongLength, closed }
    private var directory: URL?
    private var handle: FileHandle?
    private var digest = SHA256()
    private(set) var bytes = 0
    private var isClosed = false
    private let maximum: Int
    var temporaryDirectory: URL? { directory }

    init(maximum: Int = ArtifactFileLimits.maximum) { self.maximum = min(maximum, ArtifactFileLimits.maximum) }

    func append(base64: String) throws {
        guard !isClosed else { throw Failure.closed }
        guard base64.utf8.count <= (ArtifactFileLimits.chunk + 2) / 3 * 4,
              let data = Data(base64Encoded: base64), data.count <= ArtifactFileLimits.chunk else { throw Failure.invalidChunk }
        guard data.count <= maximum, bytes <= maximum - data.count else { throw Failure.tooBig }
        try openIfNeeded()
        try handle?.write(contentsOf: data)
        digest.update(data: data)
        bytes += data.count
    }

    func finish(expected: Int?) throws -> ArtifactFile {
        guard !isClosed else { throw Failure.closed }
        if let expected, expected != bytes { throw Failure.wrongLength }
        try openIfNeeded()
        try handle?.close(); handle = nil
        let directory = directory!
        self.directory = nil
        isClosed = true
        return ArtifactFile(url: directory.appendingPathComponent("content"), bytes: bytes,
                            sha256: digest.finalize().map { String(format: "%02x", $0) }.joined(), directory: directory)
    }

    func cancel() {
        isClosed = true
        try? handle?.close(); handle = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func openIfNeeded() throws {
        guard handle == nil else { return }
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("capsid-transfer-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = folder
        let file = folder.appendingPathComponent("content")
        guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: file)
    }

    deinit {
        try? handle?.close()
        if let directory { DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: directory) } }
    }
}

@MainActor
final class ArtifactFileProgress: ObservableObject {
    static let shared = ArtifactFileProgress()
    struct Value: Equatable { let bytes: Int; let total: Int? }
    @Published private(set) var versions: [String: Value] = [:]
    private var owners: [String: String] = [:]
    private var last: [String: ContinuousClock.Instant] = [:]

    func update(_ version: String, nonce: String, bytes: Int, total: Int?) {
        let now = ContinuousClock.now
        guard owners[version] != nonce || last[version].map({ now - $0 >= .milliseconds(200) }) != false else { return }
        owners[version] = nonce; last[version] = now
        versions[version] = Value(bytes: bytes, total: total)
    }

    func finish(_ version: String, nonce: String) {
        guard owners[version] == nonce else { return }
        owners[version] = nil; last[version] = nil; versions[version] = nil
    }
}

struct ArtifactTransferProgress: View {
    let version: String
    @ObservedObject private var progress = ArtifactFileProgress.shared
    var body: some View {
        if let value = progress.versions[version] {
            let received = ByteCountFormatter.string(fromByteCount: Int64(value.bytes), countStyle: .file)
            Text(value.total.map { "\(received) of \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" }
                 ?? "\(received) received")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityLabel("Downloaded \(received)")
        }
    }
}

enum ArtifactFileScript {
    static let stateName = "__capsidFileTransfers"

    /// One pull at a time applies backpressure. A response URL must still be
    /// the requested same-origin version; redirects are refused by fetch.
    static let body = #"""
    const reply = x => JSON.stringify(x);
    if (typeof nonce !== "string" || !/^[A-Za-z0-9-]{1,64}$/.test(nonce) ||
        typeof version !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(version)) return reply({outcome:"unreadable"});
    const all = globalThis.\#(stateName) = globalThis.\#(stateName) || Object.create(null);
    const path = "/api/artifacts/versions/" + version;
    const limit = \#(ArtifactFileLimits.maximum), chunkLimit = \#(ArtifactFileLimits.chunk);
    let state = all[nonce];
    const stop = async () => {
        if (!state) return;
        state.controller.abort(); clearTimeout(state.timer);
        try { await state.reader?.cancel(); } catch (_) {}
        delete all[nonce];
    };
    try {
        if (typeof origin !== "string" || location.origin !== origin || !Number.isSafeInteger(offset) || offset < 0 ||
            (!state && first !== true) || (state && state.read !== offset)) {
            await stop(); return reply({outcome:"unreadable"});
        }
        if (!state) {
            const controller = new AbortController();
            state = {version, controller, reader:null, pending:null, offset:0, read:0, expected:null};
            all[nonce] = state;
            state.timer = setTimeout(() => { controller.abort(); delete all[nonce]; }, 300000);
            const response = await fetch(path, {credentials:"include", cache:"no-store", redirect:"error", signal:controller.signal});
            if (response.status === 401) { await stop(); return reply({outcome:"lost"}); }
            if (response.status === 404 || response.status === 410) { await stop(); return reply({outcome:"missing"}); }
            const expectedURL = new URL(path, location.href);
            if (response.status !== 200 || response.url !== expectedURL.href || !response.body) {
                await stop(); return reply({outcome:"unreadable"});
            }
            const length = response.headers.get("Content-Length");
            // Encoded wire length isn't the decoded stream's length.
            if (!response.headers.get("Content-Encoding") && /^\d{1,16}$/.test(length || "")) {
                state.expected = Number(length);
                if (state.expected > limit) { await stop(); return reply({outcome:"tooBig"}); }
            }
            state.reader = response.body.getReader();
        }
        if (state.version !== version || state.controller.signal.aborted) { await stop(); return reply({outcome:"cancelled"}); }
        if (!state.pending) {
            const step = await state.reader.read();
            if (step.done) {
                const expected = state.expected, count = state.read;
                await stop();
                return reply({outcome:expected !== null && expected !== count ? "unreadable" : "done", total:expected, offset:count});
            }
            // A pathological individual stream chunk must not become an
            // unbounded JS allocation retained between native pulls.
            if (!ArrayBuffer.isView(step.value) || step.value.byteLength > 4 * 1024 * 1024) {
                await stop(); return reply({outcome:"unreadable"});
            }
            state.pending = new Uint8Array(step.value.buffer, step.value.byteOffset, step.value.byteLength);
            state.offset = 0;
        }
        const part = state.pending.subarray(state.offset, state.offset + chunkLimit);
        if (state.read > limit - part.length) { await stop(); return reply({outcome:"tooBig"}); }
        let binary = "";
        for (let i = 0; i < part.length; i += 8192) binary += String.fromCharCode(...part.subarray(i, i + 8192));
        state.offset += part.length; state.read += part.length;
        if (state.offset === state.pending.length) state.pending = null;
        return reply({outcome:"chunk", base64:btoa(binary), total:state.expected, offset:state.read - part.length, count:part.length});
    } catch (_) {
        const cancelled = state?.controller.signal.aborted;
        await stop(); return reply({outcome:cancelled ? "cancelled" : "unreadable"});
    }
    """#

    static let abort = #"""
    const state = globalThis.\#(stateName)?.[nonce];
    if (state) {
        state.controller.abort(); clearTimeout(state.timer);
        try { await state.reader?.cancel(); } catch (_) {}
        delete globalThis.\#(stateName)[nonce];
    }
    """#
}

private struct ArtifactFileReply: Decodable, Sendable {
    let outcome: String
    let base64: String?
    let total: Int?
    let offset: Int?
    let count: Int?
}

extension WebContainer {
    func readArtifactFile(version: String, nonce: String) async -> ArtifactReadOutcome {
        guard PlanCheck.isVersionID(version), status == .ready, let port else { return .unreadable }
        let origin = "http://\(host):\(port)"
        let writer = ArtifactFileWriter()
        ArtifactFileProgress.shared.update(version, nonce: nonce, bytes: 0, total: nil)
        defer { ArtifactFileProgress.shared.finish(version, nonce: nonce) }
        do {
            var first = true
            while !Task.isCancelled {
                let offset = await writer.bytes
                let value = try await webView.callAsyncJavaScript(ArtifactFileScript.body,
                    arguments: ["version": version, "nonce": nonce, "origin": origin, "offset": offset, "first": first],
                    in: nil, contentWorld: .defaultClient)
                first = false
                guard let text = value as? String else { throw WebAPIError.badResponse }
                let reply = try await Task.detached(priority: .userInitiated) {
                    try JSONDecoder().decode(ArtifactFileReply.self, from: Data(text.utf8))
                }.value
                if Task.isCancelled { break }
                let outcome = reply.outcome, total = reply.total
                if let total, !(0...ArtifactFileLimits.maximum).contains(total) { throw WebAPIError.badResponse }
                if outcome == "chunk", let base64 = reply.base64 {
                    guard reply.offset == offset, let count = reply.count,
                          (0...ArtifactFileLimits.chunk).contains(count) else { throw WebAPIError.badResponse }
                    try await writer.append(base64: base64)
                    guard await writer.bytes == offset + count else { throw WebAPIError.badResponse }
                    ArtifactFileProgress.shared.update(version, nonce: nonce, bytes: await writer.bytes, total: total)
                    continue
                }
                if outcome == "done" {
                    guard reply.offset == offset else { throw WebAPIError.badResponse }
                    let file = try await writer.finish(expected: total)
                    return Task.isCancelled ? .cancelled : .file(file)
                }
                await writer.cancel()
                switch outcome {
                case "lost": sessionLost(); return .lost
                case "tooBig": return .tooBig
                case "missing": return .missing
                case "cancelled": return .cancelled
                default: return .unreadable
                }
            }
            await writer.cancel()
            await abortArtifactRead(nonce)
            return .cancelled
        } catch {
            await writer.cancel()
            await abortArtifactRead(nonce)
            return error is ArtifactFileWriter.Failure && error as? ArtifactFileWriter.Failure == .tooBig ? .tooBig : .unreadable
        }
    }
}
