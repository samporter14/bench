// ShelfSaveAll.swift — Save All… and the folder a project's files are saved
// to (DESIGN.md, Results): the progress and summary lines a session's row
// shows, and the folder remembered per project. The batch itself runs in
// ResultsShelf (it needs the reads, the time limit and the cap). Here too:
// the writer every saved file goes through, off the main actor, with a time
// limit on each write.
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
/// folder that is gone is forgotten, and the panel starts where it would.
@MainActor
struct ShelfFolderMemory {
    nonisolated static let key = "resultsFolders"

    let defaults: UserDefaults
    let exists: @MainActor (URL) -> Bool

    /// The remembered folder, when it is still there.
    func folder(for projectID: String) -> URL? {
        guard let path = (defaults.dictionary(forKey: Self.key) as? [String: String])?[projectID] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return exists(url) ? url : nil
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

    var errorDescription: String? {
        switch self {
        case .folderDidNotRespond: "The folder didn't respond. If it comes back, the file may still appear there."
        case .folderStillSilent: "The folder still isn't responding."
        case .earlierSaveUnfinished: "An earlier save of this file hasn't finished."
        }
    }
}

/// Writes saved files (Save…, Save All…) off the main actor, within a time
/// limit, one at a time per destination: a slow destination never holds up
/// typing, scrolling or closing the window, and a folder that stops
/// answering never holds up a save to any other.
///
/// A blocking file-system call can't be cancelled, so each write runs on a
/// queue of its own and is only waited for: when its time limit passes (15 s
/// and a second for each MiB, by the bytes) the caller is told the folder
/// didn't respond and the write is left to finish, or never to. That
/// destination (a mounted volume, else the folder) then refuses further saves
/// at once until the write comes back or `holdOff` passes, so a Save All into
/// a dead folder costs one limit, not one per file; after the hold-off one
/// save is let through to find out. Saves to other destinations carry on.
///
/// A file name has at most one write out at a time: it stays spoken for until
/// its call has returned, late or not. A save of the name meanwhile is
/// refused, and Save All numbers its names around it (`isPending`), so a
/// write that lands late can never race another for one file.
@MainActor
final class ShelfSavedFiles {
    typealias Work = @Sendable () -> Void

    /// One destination: its saves wait here in turn.
    private struct Lane {
        /// A write is out here, within its time limit.
        var busy = false
        /// Saves waiting for their turn, oldest first.
        var waiting: [CheckedContinuation<Void, Never>] = []
        /// Writes past their time limit that haven't come back.
        var silent = 0
        /// Refusing saves: a write timed out and neither it nor the hold-off has ended.
        var heldOff = false
        var holdOffTimer: Task<Void, Never>?

        var isIdle: Bool { !busy && waiting.isEmpty && silent == 0 && !heldOff }
    }

    /// One write, from the moment it starts to the moment its call returns.
    @MainActor
    private final class Attempt {
        let name: String
        let destination: String
        var continuation: CheckedContinuation<Void, any Error>?
        var timer: Task<Void, Never>?
        /// The blocking call has returned.
        var returned = false
        /// The time limit passed first: the caller was told, and the call is still out.
        var timedOut = false

        init(name: String, destination: String) {
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

    /// `limit` is how long a write of that many bytes may take; `wait` waits
    /// it out (and the hold-off), and `run` starts a blocking call off the
    /// main actor: tests stand in for all three.
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
    /// share to take 8 MB at 1 MB/s. A write that is only slow isn't stopped;
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

    /// Whether saves into this folder are being refused: a write there timed
    /// out and hasn't come back, and the hold-off hasn't passed.
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
    func write(_ data: Data, to url: URL, using write: @escaping @Sendable (Data, URL) throws -> Void) async throws {
        let name = Self.name(of: url), destination = Self.destination(of: url)
        if pending.contains(name) { throw ShelfSaveError.earlierSaveUnfinished }
        if lanes[destination]?.heldOff == true { throw ShelfSaveError.folderStillSilent }
        pending.insert(name)
        await takeTurn(in: destination)
        // The folder may have gone silent while this save waited.
        guard lanes[destination]?.heldOff != true else {
            pending.remove(name)
            passTurn(in: destination)
            throw ShelfSaveError.folderStillSilent
        }
        let attempt = Attempt(name: name, destination: destination)
        let allowed = limit(data.count)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            attempt.continuation = continuation
            run { [weak self] in
                let result = Result { try write(data, url) }
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
    private func returned(_ attempt: Attempt, _ result: Result<Void, any Error>) {
        guard !attempt.returned else { return }
        attempt.returned = true
        attempt.timer?.cancel()
        attempt.timer = nil
        pending.remove(attempt.name)
        if attempt.timedOut {
            // The folder answers again.
            lanes[attempt.destination]?.silent -= 1
            endHoldOff(attempt.destination)
            return
        }
        attempt.continuation?.resume(with: result)
        attempt.continuation = nil
        passTurn(in: attempt.destination)
    }

    /// The time limit passed with the call still out: the caller is told at
    /// once, the destination is held off, and the next save may go. The name
    /// stays spoken for until the call returns.
    private func expired(_ attempt: Attempt) {
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
        passTurn(in: destination)
    }

    private func endHoldOff(_ destination: String) {
        lanes[destination]?.holdOffTimer?.cancel()
        lanes[destination]?.holdOffTimer = nil
        lanes[destination]?.heldOff = false
        tidy(destination)
    }

    // MARK: Turns

    private func takeTurn(in destination: String) async {
        if lanes[destination]?.busy != true {
            lanes[destination, default: Lane()].busy = true
            return
        }
        await withCheckedContinuation { lanes[destination]?.waiting.append($0) }
    }

    /// The write that held the turn is over (returned, or past its limit):
    /// the next save of the destination goes, if any.
    private func passTurn(in destination: String) {
        if let next = lanes[destination]?.waiting.first {
            lanes[destination]?.waiting.removeFirst()
            next.resume()
        } else {
            lanes[destination]?.busy = false
            tidy(destination)
        }
    }

    private func tidy(_ destination: String) {
        if lanes[destination]?.isIdle == true { lanes[destination] = nil }
    }
}
