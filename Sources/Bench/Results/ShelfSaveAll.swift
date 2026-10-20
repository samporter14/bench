// ShelfSaveAll.swift — Save All… and the folder a project's files are saved
// to (DESIGN.md, Results): the progress and summary lines a session's row
// shows, and the folder remembered per project. The batch itself runs in
// ResultsShelf (it needs the reads, the time limit and the cap). Here too:
// the disk-work layer every saved file goes through, off the main actor, with
// a time limit on each call: the writes, and the looks (does a name exist,
// what does the folder hold) behind Save All's names, the remembered folder
// and Open and Reveal in Finder. Nothing here, or anywhere in the Results
// code, asks the disk anything on the main actor.
import Foundation

/// What a session row says about its Save All.
enum ShelfSaveAllState: Equatable, Sendable {
    /// `done` files have finished (saved, skipped or failed) of `total`.
    case saving(done: Int, total: Int)
    case finished(ShelfSaveAllSummary)

    /// "Saving 3 of 7…", then the summary.
    var line: String {
        switch self {
        case .saving(let done, let total): "Saving \(min(done + 1, total)) of \(total)…"
        case .finished(let summary): summary.line
        }
    }
}

/// How a Save All came out, by count: a failure is never named by its file.
struct ShelfSaveAllSummary: Equatable, Sendable {
    /// Where the files went.
    let folder: URL
    var saved = 0
    /// Over the 8 MB cap, by the listing or by the bytes.
    var tooBig = 0
    /// Couldn't be read or written.
    var failed = 0

    /// "Saved 6 files. 1 was too big to save here."
    var line: String {
        var parts = [saved == 0 ? "Nothing was saved." : "Saved \(saved) file\(saved == 1 ? "" : "s")."]
        if tooBig > 0 { parts.append(tooBig == 1 ? "1 was too big to save here." : "\(tooBig) were too big to save here.") }
        if failed > 0 { parts.append(failed == 1 ? "1 couldn't be saved." : "\(failed) couldn't be saved.") }
        return parts.joined(separator: " ")
    }
}

/// The last folder files were saved to, by project id (never by its name):
/// `[projectID: path]` in UserDefaults. The save panels start there; a
/// folder that is gone, or that doesn't answer, is ignored, and the panel
/// starts where it would. Whether it is there is asked of the disk-work layer
/// (`ShelfSavedFiles.folderExists`), off the main actor, so the answer is
/// awaited.
@MainActor
struct ShelfFolderMemory {
    nonisolated static let key = "resultsFolders"

    let defaults: UserDefaults
    /// Whether the folder is there: false when it isn't, or doesn't answer.
    let exists: @MainActor (URL) async -> Bool

    /// The folder remembered for a project, whether or not it is still there.
    /// Nothing is asked of the disk. (`isDirectory: true` keeps `URL` from
    /// looking at the disk to find out.)
    func remembered(for projectID: String) -> URL? {
        guard let path = (defaults.dictionary(forKey: Self.key) as? [String: String])?[projectID] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The remembered folder, when it is still there and answers.
    func folder(for projectID: String) async -> URL? {
        guard let url = remembered(for: projectID) else { return nil }
        return await exists(url) ? url : nil
    }

    func remember(_ folder: URL, for projectID: String) {
        var all = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        all[projectID] = folder.path
        defaults.set(all, forKey: Self.key)
    }
}

/// Why a saved file wasn't written when the folder was to blame, as the end
/// of "Couldn't save it there: …".
enum ShelfSaveError: Error, LocalizedError, Equatable {
    /// The write waited out its time limit with the folder silent.
    case folderDidNotRespond
    /// An earlier save to this folder timed out and hasn't come back yet.
    case folderStillSilent
    /// An earlier write of this very name hasn't come back.
    case earlierSaveUnfinished
    /// Save All found something at the name when it came to write: the write
    /// was not made. The batch numbers the name again; this reaches a row
    /// only when every name it tried was taken.
    case nameTaken

    var errorDescription: String? {
        switch self {
        case .folderDidNotRespond: "The folder didn't respond. If it comes back, the file may still appear there."
        case .folderStillSilent: "The folder still isn't responding."
        case .earlierSaveUnfinished: "An earlier save of this file hasn't finished."
        case .nameTaken: "A file with this name is already there."
        }
    }
}

/// The disk-work layer of saved files: every call that touches the
/// destination of a Save, a Save All or an Open runs here, off the main actor,
/// within a time limit, one at a time per destination. A slow destination
/// never holds up typing, scrolling or closing the window, and a folder that
/// stops answering never holds up a save to any other.
///
/// Two kinds of call, one set of rules. The writes (`write`) put a file where
/// it goes. The looks ask the destination something (`fileExists`,
/// `folderExists`, `names(in:)`, and `plan`, which is built on them): is
/// there a file at this name, is the remembered folder there, what does the
/// folder hold. Writes go one at a time per destination, and so do looks, each
/// in a turn of its own: a slow write never holds up a look, nor a look a write
/// (a Save All started while a write is out still settles its names and starts
/// its downloads). A blocking file-system call can't be cancelled, so each runs
/// on a queue of its own and is only waited for: when its time limit passes
/// (15 s, and a second for each MiB of a write's bytes; a look has no bytes,
/// so 15 s) the caller is told the folder didn't respond and the call is left
/// to finish, or never to. That destination (a mounted volume, else the
/// folder) then refuses further calls, looks and writes alike, at once until
/// the call comes back or `holdOff` passes, so a Save All into a dead folder
/// costs one limit, not one per file; after the hold-off one call is let
/// through to find out. A look that doesn't answer counts like a write that
/// didn't. Calls to other destinations carry on.
///
/// A file name has at most one write out at a time: it stays spoken for until
/// its call has returned, late or not. A save of the name meanwhile is
/// refused, and Save All numbers its names around it (`isPending`), so a
/// write that lands late can never race another for one file. A look speaks
/// for no name: it writes nothing, so a late one lands nothing.
@MainActor
final class ShelfSavedFiles {
    typealias Work = @Sendable () -> Void

    /// What a call does: a write, or a look at the destination.
    private enum Kind {
        case write, look
    }

    /// One destination: its writes wait here in turn, and its looks in theirs
    /// (a slow write never holds up a look, nor a look a write). The time limit
    /// and the hold-off are the destination's, whichever kind of call timed out.
    private struct Lane {
        /// A write is out here, within its time limit.
        var busy = false
        /// Writes waiting for their turn, oldest first.
        var waiting: [CheckedContinuation<Void, Never>] = []
        /// A look is out here, within its time limit.
        var lookBusy = false
        /// Looks waiting for their turn, oldest first.
        var lookWaiting: [CheckedContinuation<Void, Never>] = []
        /// Calls past their time limit that haven't come back.
        var silent = 0
        /// Refusing calls: one timed out and neither it nor the hold-off has ended.
        var heldOff = false
        var holdOffTimer: Task<Void, Never>?

        var isIdle: Bool { !busy && waiting.isEmpty && !lookBusy && lookWaiting.isEmpty && silent == 0 && !heldOff }
    }

    /// One call, from the moment it starts to the moment it returns.
    @MainActor
    private final class Attempt<Value: Sendable> {
        let kind: Kind
        /// The file name a write speaks for until its call returns; nil for a look.
        let name: String?
        let destination: String
        var continuation: CheckedContinuation<Value, any Error>?
        var timer: Task<Void, Never>?
        /// The blocking call has returned.
        var returned = false
        /// The time limit passed first: the caller was told, and the call is still out.
        var timedOut = false

        init(kind: Kind, name: String?, destination: String) {
            self.kind = kind
            self.name = name
            self.destination = destination
        }
    }

    private let limit: (Int) -> Duration
    private let holdOff: Duration
    private let wait: @MainActor (Duration) async -> Void
    private let run: (@escaping Work) -> Void
    private var lanes: [String: Lane] = [:]
    /// Names with a write that hasn't returned, queued or out, lowercased.
    private var pending: Set<String> = []

    /// `limit` is how long a call may take for that many bytes (a look has
    /// none); `wait` waits it out (and the hold-off), and `run` starts a
    /// blocking call off the main actor: tests stand in for all three.
    init(limit: @escaping (Int) -> Duration = ShelfSavedFiles.limit(forBytes:),
         holdOff: Duration = .seconds(30),
         wait: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         run: @escaping (@escaping Work) -> Void = ShelfSavedFiles.runOnDisk) {
        self.limit = limit
        self.holdOff = holdOff
        self.wait = wait
        self.run = run
    }

    // MARK: The limits

    /// 15 s, and one more for each MiB: room for a disk to spin up, or a
    /// share to take 8 MB at 1 MB/s. A call that is only slow isn't stopped;
    /// one that makes no sound for this long is a folder that isn't there.
    nonisolated static func limit(forBytes bytes: Int) -> Duration {
        .seconds(15 + (max(bytes, 0) + (1 << 20) - 1) >> 20)
    }

    private nonisolated static let diskQueue = DispatchQueue(label: "sam.bench.saved-files", qos: .utility,
                                                             attributes: .concurrent)

    nonisolated static func runOnDisk(_ work: @escaping Work) {
        diskQueue.async(execute: work)
    }

    // MARK: Where a file goes

    /// The destination a folder belongs to, by its path alone (resolving a
    /// volume is a file-system call, and may be the one that hangs): the
    /// mounted volume under /Volumes it names, else the folder itself.
    nonisolated static func destination(inFolder folder: URL) -> String {
        let parts = folder.pathComponents
        if parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" { return "/Volumes/\(parts[2])".lowercased() }
        return folder.path.lowercased()
    }

    nonisolated static func destination(of file: URL) -> String {
        destination(inFolder: file.deletingLastPathComponent())
    }

    private nonisolated static func name(of file: URL) -> String { file.path.lowercased() }

    /// Whether calls into this folder are being refused: one there timed out
    /// and hasn't come back, and the hold-off hasn't passed.
    func isHeldOff(_ folder: URL) -> Bool {
        lanes[Self.destination(inFolder: folder)]?.heldOff ?? false
    }

    /// Nothing waits, is out or is held off: for tests.
    var isAtRest: Bool { lanes.isEmpty && pending.isEmpty }

    /// Whether a write of this name hasn't returned yet. Save All treats such
    /// a name as taken, as it does one that exists.
    func isPending(_ file: URL) -> Bool {
        pending.contains(Self.name(of: file))
    }

    // MARK: Writing

    /// Writes `data` to `url` through `write`, off the main actor. Throws
    /// what `write` throws, or a `ShelfSaveError` when the folder didn't
    /// respond in time, is still held off, or the name has a write out.
    ///
    /// With `unlessExists` (Save All: nothing is overwritten) `exists` asks
    /// the disk about the name first, in the same call as the write: one turn,
    /// one limit, and nothing but another program can take the name between
    /// the look and the write. A name already there throws `nameTaken`, and
    /// nothing is written. (A Save… leaves it off: the person was asked
    /// whether to replace it.)
    func write(_ data: Data, to url: URL, using write: @escaping @Sendable (Data, URL) throws -> Void,
               unlessExists exists: (@Sendable (URL) -> Bool)? = nil) async throws {
        let body: @Sendable () throws -> Void
        if let exists {
            body = {
                if exists(url) { throw ShelfSaveError.nameTaken }
                try write(data, url)
            }
        } else {
            body = { try write(data, url) }
        }
        try await perform(.write, in: Self.destination(of: url), reserving: Self.name(of: url),
                          allowed: limit(data.count), body)
    }

    // MARK: Looking

    /// Whether something is at `url`, asked of the disk off the main actor,
    /// by the destination of the file's folder. Throws a `ShelfSaveError`
    /// when the folder didn't respond in time or is still held off, and
    /// `CancellationError` when the asking task was cancelled before its turn.
    func fileExists(_ url: URL, using exists: @escaping @Sendable (URL) -> Bool) async throws -> Bool {
        try await perform(.look, in: Self.destination(of: url), reserving: nil, allowed: limit(0)) {
            exists(url)
        }
    }

    /// Whether the folder itself is there: by the folder's own destination
    /// (where a Save All into it would go), not its parent's.
    func folderExists(_ folder: URL, using exists: @escaping @Sendable (URL) -> Bool) async throws -> Bool {
        try await perform(.look, in: Self.destination(inFolder: folder), reserving: nil, allowed: limit(0)) {
            exists(folder)
        }
    }

    /// What the folder holds, lowercased. Nil when it can't be listed: the
    /// call failed (no such folder, no permission to read it) or `list` says
    /// it holds too many (see `listFolder`); the names are then asked for one
    /// by one. Throws as `fileExists` does.
    func names(in folder: URL, using list: @escaping @Sendable (URL) throws -> [String]?) async throws -> Set<String>? {
        do {
            let listed = try await perform(.look, in: Self.destination(inFolder: folder), reserving: nil,
                                           allowed: limit(0)) { try list(folder) }
            return listed.map { Set($0.map { $0.lowercased() }) }
        } catch let error as ShelfSaveError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Save All's names, settled before its first download (`ShelfNamePlan`):
    /// one listing of the folder, off the main actor and within the limit.
    func plan(in folder: URL, exists: @escaping @Sendable (URL) -> Bool,
              list: @escaping @Sendable (URL) throws -> [String]?) async throws -> ShelfNamePlan {
        ShelfNamePlan(folder: folder, savedFiles: self, exists: exists, listed: try await names(in: folder, using: list))
    }

    /// The most names a folder's listing takes. A folder with more is asked
    /// about by name instead: a listing that long isn't bounded in time on a
    /// slow share, and a name asked for is.
    nonisolated static let listingCap = 10_000

    /// The names in a folder, without "." and "..", or nil when it holds more
    /// than `cap`. Throws when it can't be opened. Blocking: only ever run
    /// off the main actor (it is the default of `ResultsShelf.Dependencies.list`).
    nonisolated static func listFolder(_ folder: URL, cap: Int = listingCap) throws -> [String]? {
        guard let directory = opendir(folder.path) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            if names.count >= cap { return nil }
            names.append(name)
        }
        return names
    }

    // MARK: One call

    /// Runs `body` off the main actor for `destination`, in its kind's turn and
    /// within `allowed`. A write names the file it speaks for (`reserving`);
    /// a look is cancellable: if its task was cancelled while it waited for
    /// the turn, it makes no call (a write already chosen goes on, as a Save
    /// does when the window closes).
    private func perform<Value: Sendable>(_ kind: Kind, in destination: String, reserving name: String?,
                                          allowed: Duration,
                                          _ body: @escaping @Sendable () throws -> Value) async throws -> Value {
        if let name, pending.contains(name) { throw ShelfSaveError.earlierSaveUnfinished }
        if lanes[destination]?.heldOff == true { throw ShelfSaveError.folderStillSilent }
        if let name { pending.insert(name) }
        await takeTurn(in: destination, kind)
        func giveUpTurn() {
            if let name { pending.remove(name) }
            passTurn(in: destination, kind)
        }
        if kind == .look, Task.isCancelled {
            giveUpTurn()
            throw CancellationError()
        }
        // The folder may have gone silent while this call waited.
        guard lanes[destination]?.heldOff != true else {
            giveUpTurn()
            throw ShelfSaveError.folderStillSilent
        }
        let attempt = Attempt<Value>(kind: kind, name: name, destination: destination)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            attempt.continuation = continuation
            run { [weak self] in
                let result = Result { try body() }
                Task { @MainActor in self?.returned(attempt, result) }
            }
            attempt.timer = Task { [weak self, wait] in
                await wait(allowed)
                guard !Task.isCancelled else { return }
                self?.expired(attempt)
            }
        }
    }

    /// The call came back. If the caller was still waiting it gets the
    /// result; if its time limit passed first, the call was late and its
    /// result is dropped (a file it wrote stays where it landed).
    private func returned<Value>(_ attempt: Attempt<Value>, _ result: Result<Value, any Error>) {
        guard !attempt.returned else { return }
        attempt.returned = true
        attempt.timer?.cancel()
        attempt.timer = nil
        if let name = attempt.name { pending.remove(name) }
        if attempt.timedOut {
            // The folder answers again.
            lanes[attempt.destination]?.silent -= 1
            endHoldOff(attempt.destination)
            return
        }
        attempt.continuation?.resume(with: result)
        attempt.continuation = nil
        passTurn(in: attempt.destination, attempt.kind)
    }

    /// The time limit passed with the call still out: the caller is told at
    /// once, the destination is held off, and the next call may go. A write's
    /// name stays spoken for until the call returns.
    private func expired<Value>(_ attempt: Attempt<Value>) {
        guard !attempt.returned, !attempt.timedOut else { return }
        attempt.timedOut = true
        attempt.timer = nil
        let destination = attempt.destination
        lanes[destination]?.silent += 1
        lanes[destination]?.heldOff = true
        lanes[destination]?.holdOffTimer?.cancel()
        lanes[destination]?.holdOffTimer = Task { [weak self, wait, holdOff] in
            await wait(holdOff)
            guard !Task.isCancelled else { return }
            self?.endHoldOff(destination)
        }
        attempt.continuation?.resume(throwing: ShelfSaveError.folderDidNotRespond)
        attempt.continuation = nil
        passTurn(in: destination, attempt.kind)
    }

    private func endHoldOff(_ destination: String) {
        lanes[destination]?.holdOffTimer?.cancel()
        lanes[destination]?.holdOffTimer = nil
        lanes[destination]?.heldOff = false
        tidy(destination)
    }

    // MARK: Turns

    private func takeTurn(in destination: String, _ kind: Kind) async {
        switch kind {
        case .write:
            if lanes[destination]?.busy != true {
                lanes[destination, default: Lane()].busy = true
                return
            }
            await withCheckedContinuation { lanes[destination]?.waiting.append($0) }
        case .look:
            if lanes[destination]?.lookBusy != true {
                lanes[destination, default: Lane()].lookBusy = true
                return
            }
            await withCheckedContinuation { lanes[destination]?.lookWaiting.append($0) }
        }
    }

    /// The call that held the turn is over (returned, or past its limit):
    /// the next call of its kind for the destination goes, if any.
    private func passTurn(in destination: String, _ kind: Kind) {
        switch kind {
        case .write:
            if let next = lanes[destination]?.waiting.first {
                lanes[destination]?.waiting.removeFirst()
                next.resume()
            } else {
                lanes[destination]?.busy = false
                tidy(destination)
            }
        case .look:
            if let next = lanes[destination]?.lookWaiting.first {
                lanes[destination]?.lookWaiting.removeFirst()
                next.resume()
            } else {
                lanes[destination]?.lookBusy = false
                tidy(destination)
            }
        }
    }

    private func tidy(_ destination: String) {
        if lanes[destination]?.isIdle == true { lanes[destination] = nil }
    }
}

/// The names a Save All gives its files in one folder, settled before its
/// first download, in the session's order, so the first of two of one name
/// gets the plain one whatever finishes first. A name is taken when this
/// batch has given it out (or found it taken since), the folder held it when
/// it was listed (one listing, off the main actor, instead of a question per
/// name), or an earlier write of it hasn't returned (a save that timed out
/// and may still land). Compared without case, as a Mac compares them.
///
/// When the folder couldn't be listed, each name not already ruled out is
/// asked of the disk instead, one look at a time through the same layer, with
/// the same limits. Either way a name free at planning can be taken by write
/// time (a program, a late write): the write looks again in its own call
/// (`ShelfSavedFiles.write(unlessExists:)`), and the name is claimed afresh.
///
/// Claims are made one at a time.
@MainActor
final class ShelfNamePlan {
    let folder: URL
    private let savedFiles: ShelfSavedFiles
    private let exists: @Sendable (URL) -> Bool
    /// Lowercased names the folder held when it was listed; nil when it couldn't be.
    private let listed: Set<String>?
    /// Lowercased names this batch gave out or learned are taken.
    private var held: Set<String> = []

    fileprivate init(folder: URL, savedFiles: ShelfSavedFiles, exists: @escaping @Sendable (URL) -> Bool,
                     listed: Set<String>?) {
        self.folder = folder
        self.savedFiles = savedFiles
        self.exists = exists
        self.listed = listed
    }

    func url(_ name: String) -> URL {
        folder.appending(path: name, directoryHint: .notDirectory)
    }

    /// The first free name from `wanted` on: the plain name, else " 2", " 3"…
    /// before its extension. The name is the batch's from then on. Throws what
    /// a look throws when the folder doesn't respond.
    func claim(_ wanted: String) async throws -> String {
        let name = try await ShelfFileName.firstFree(wanted) { try await self.isTaken($0) }
        held.insert(name.lowercased())
        return name
    }

    /// `name` was found taken when it came to be written: it is never offered again.
    func learnedTaken(_ name: String) {
        held.insert(name.lowercased())
    }

    private func isTaken(_ candidate: String) async throws -> Bool {
        let url = url(candidate)
        if held.contains(candidate.lowercased()) || savedFiles.isPending(url) { return true }
        if let listed { return listed.contains(candidate.lowercased()) }
        // Asked by name: what the disk has is remembered, so it isn't asked again.
        guard try await savedFiles.fileExists(url, using: exists) else { return false }
        held.insert(candidate.lowercased())
        return true
    }
}
