// KeptDisk.swift — everything Keep asks of the disk (DESIGN.md, Kept): making
// the folder a keep is built in, writing its files, finishing it, and looking
// at what has been kept. Keep stores nothing but the folders: there is no
// cache and no index here, so what the Kept window shows is whatever the
// folders say when it looks, and a folder moved, renamed or deleted in Finder
// is simply different the next time.
//
// Nothing here asks the disk anything on the main actor. Every call is a
// blocking one, so each runs on a queue of its own (`sam.bench.kept`, one
// at a time) and the caller only waits for it, as for the saved files of the
// Results shelf (`ShelfSavedFiles`): 15 s, and a second more for each MiB a
// write carries; 15 s for a look. A call that makes no sound that long is a
// folder that isn't there (a volume that was unplugged, a share that stopped
// answering), and the caller is told so at once, with the sentences the shelf
// uses ("The folder didn't respond. If it comes back, the file may still
// appear there."). The call is left to finish or never to. While one is out
// past its limit, the others are refused at once ("The folder still isn't
// responding.") instead of each waiting out a limit of its own, until it comes
// back. The queue is one at a time, so a call that never comes back holds every
// later one until Capsid is opened again: an abandon is not refused, but it
// waits behind the stuck call and gives up after its own limit, leaving the
// hidden folder where it is. The clock and the queue are injected, so tests
// hold a write as a dropped volume would and never sleep.
// All the file-system calls are in `KeptDiskWork`, below, which is not
// main-actor code, and `KeptDiskCallsTests` fails if any other file of
// Kept/ makes one.
//
// Taking a folder off the shelf is the Trash's job and never a deletion:
// `trash` moves a kept folder (its README is Capsid's, and it sits where a keep
// puts one) to the Trash and says where it went, and `restore` puts it back
// without replacing anything. Nothing here deletes a kept folder.
//
// A keep is built in a hidden folder beside the one it becomes
// (`.<Name>.keeping-<uuid>`), README last, and then renamed into place: a
// folder either has its README and all its files or isn't there. The rename
// never replaces a folder that exists: when the name was taken meanwhile the
// keep gets the dated name ("<Name> 2026-10-22 0912"), then a number. A file
// is never overwritten either (`write`, `writeInto`), and only the README of a
// folder with `capsid_kept: 1` in it is ever replaced; any other folder, and
// any file in it, is left alone.
//
// The Kept folder may be missing in two ways. Missing with its own folder
// there (nothing was ever kept, or it was deleted) is an empty Kept folder:
// the first keep makes it, and a look finds nothing. Missing with the folder
// around it gone too (a drive that is unplugged) is `rootMissing`, for every
// call, because making it would make a path that isn't ours.
import CryptoKit
import Foundation

/// Why a keep, or a look at the Kept folder, didn't happen, in sentences for a
/// person; `errorDescription` is the sentence.
enum KeptDiskError: Error, LocalizedError, Equatable, Sendable {
    /// The Kept folder, and the folder it should be in, aren't there.
    case rootMissing
    /// The folder didn't answer in time; the sentence says which call.
    case notResponding(String)
    /// README.md is not what it was when it was read.
    case changedOutside
    case noRoom
    /// The system won't let Capsid do this; the sentence says what.
    case denied(String)
    /// Anything else; the sentence is the system's.
    case failed(String)

    /// A write that waited out its limit.
    static let writeDidNotRespond = "The folder didn't respond. If it comes back, the file may still appear there."
    /// A look that did.
    static let lookDidNotRespond = "The folder didn't respond."
    /// A call refused because an earlier one is still out.
    static let stillSilent = "The folder still isn't responding."

    var errorDescription: String? {
        switch self {
        case .rootMissing: "The Kept folder isn't there."
        case .notResponding(let sentence): sentence
        case .changedOutside: "README.md was changed in another app."
        case .noRoom: "There isn't room on this disk."
        case .denied(let sentence): sentence
        case .failed(let sentence): sentence
        }
    }

    /// What a system error comes to: no room, not allowed, or its own words.
    static func from(_ error: Error) -> KeptDiskError {
        if let kept = error as? KeptDiskError { return kept }
        let top = error as NSError
        var chain = [top]
        var next = top
        while let inner = next.userInfo[NSUnderlyingErrorKey] as? NSError, chain.count < 5 {
            chain.append(inner)
            next = inner
        }
        for item in chain {
            if item.domain == NSPOSIXErrorDomain {
                switch Int32(truncatingIfNeeded: item.code) {
                case ENOSPC, EDQUOT: return .noRoom
                case EACCES, EPERM, EROFS: return .denied("Capsid isn't allowed to change the Kept folder.")
                default: break
                }
            }
            if item.domain == NSCocoaErrorDomain {
                switch item.code {
                case CocoaError.fileWriteOutOfSpace.rawValue: return .noRoom
                case CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileWriteVolumeReadOnly.rawValue:
                    return .denied("Capsid isn't allowed to change the Kept folder.")
                case CocoaError.fileReadNoPermission.rawValue:
                    return .denied("Capsid isn't allowed to read the Kept folder.")
                case CocoaError.featureUnsupported.rawValue:
                    return .failed("This disk has no Trash, so Capsid can't take it off from here. Remove the folder in Finder.")
                default: break
                }
            }
        }
        return .failed(top.localizedDescription)
    }
}

/// Where a keep is being built, and where it will be.
struct KeptDestination: Sendable, Equatable {
    let collection: String
    /// The folder's name as `prepare` chose it: the name, or the dated one.
    let name: String
    let finalFolder: URL
    let tempFolder: URL
    /// When the keep was made: the date a dated name carries if `finish` finds the name taken.
    var keptAt: Date? = nil
}

/// A file listed in a kept folder's README by `KeptDisk.listFile`.
struct KeptListing: Sendable, Equatable {
    /// Where it is in the folder.
    let path: String
    /// The README as it is now, as text without a byte order mark: the next `lastRead`.
    let markdown: String
    /// It was listed already, so nothing was copied or changed.
    let wasListed: Bool
}

/// A folder found by `scan`.
struct KeptResult: Equatable, Sendable, Identifiable {
    var id: String { folder.path }
    let folder: URL
    let collection: String
    let record: KeptRecord
    let text: KeptText
    var figureURL: URL { folder.appending(path: record.figure.path, directoryHint: .notDirectory) }
}

/// Which file a path holds, to a cache of pictures drawn from it: when it was
/// last written, how big it is, and whether iCloud has put it away. If any
/// differs, what was drawn is not what is there (another file, or the same
/// one now back on this Mac).
struct KeptFileStamp: Equatable, Sendable {
    var modified: Date?
    var size: Int?
    var putAway = false
}

/// What a picture cache asks of a file (`KeptThumbnails`): its stamp, and
/// whether iCloud has put it away (so a picture of it must not be asked for).
struct KeptFileFacts: Equatable, Sendable {
    var modified: Date?
    var size: Int?
    var putAway = false

    var stamp: KeptFileStamp { KeptFileStamp(modified: modified, size: size, putAway: putAway) }
}

@MainActor
final class KeptDisk {
    typealias Work = @Sendable () -> Void
    /// Whether anyone still waits for the call's answer: a long look checks it
    /// as it goes, and stops early once its caller has been told or has left.
    typealias StillWanted = @Sendable () -> Bool

    private enum Kind {
        /// Changes the disk: its caller is waited for, and it goes on if the asking task is cancelled.
        case write
        /// Asks the disk something: not even started when the asking task was cancelled first.
        case look
        /// Clears away a keep that was abandoned: goes in even behind a silent folder.
        case cleanup
    }

    private let rootURL: () -> URL
    private let limit: (Int) -> Duration
    private let lookLimit: Duration
    private let wait: @MainActor (Duration) async -> Void
    private let run: (@escaping Work) -> Void
    /// Moves a folder to the Trash and says where it went; nil is the system's.
    /// Tests stand in for it, so they never fill the real Trash.
    private let trasher: (@Sendable (URL) throws -> URL?)?
    private let stuck = StuckCount()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// `root` is where the Kept folder is (asked each time, so a changed
    /// setting is seen). `limit` is how long a write of that many bytes may
    /// take, `lookLimit` a look; `wait` waits them out, and `run` starts a
    /// blocking call off the main actor: tests stand in for all three.
    init(root: @escaping () -> URL,
         limit: @escaping (Int) -> Duration = KeptDisk.limit(forBytes:),
         lookLimit: Duration = .seconds(15),
         wait: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         run: @escaping (@escaping Work) -> Void = KeptDisk.runOnDisk,
         trash: (@Sendable (URL) throws -> URL?)? = nil) {
        self.rootURL = root
        self.limit = limit
        self.lookLimit = lookLimit
        self.wait = wait
        self.run = run
        self.trasher = trash
    }

    /// 15 s, and one more for each MiB: room for a disk to spin up, or a share
    /// to take 8 MB at 1 MB/s.
    nonisolated static func limit(forBytes bytes: Int) -> Duration {
        .seconds(15 + (max(bytes, 0) + (1 << 20) - 1) >> 20)
    }

    private nonisolated static let diskQueue = DispatchQueue(label: "sam.bench.kept", qos: .utility)

    nonisolated static func runOnDisk(_ work: @escaping Work) {
        diskQueue.async(execute: work)
    }

    /// A file's stamp and whether iCloud has put it away, looked at on the
    /// disk's queue (never the main actor, never a cooperative thread). Nil
    /// when it can't be looked at. The picture cache asks it every time a card
    /// does, so a file put in the place of another is told from it.
    nonisolated static func fileFacts(of file: URL) async -> KeptFileFacts? {
        await withCheckedContinuation { continuation in
            runOnDisk { continuation.resume(returning: KeptDiskWork.fileFacts(file)) }
        }
    }

    /// Whether a call is out past its limit and hasn't come back: for tests.
    var isSilent: Bool { stuck.count > 0 }

    // MARK: Looking

    /// The Kept folder's subfolders (the collections), sorted without regard
    /// to case. Empty when there is no Kept folder yet.
    func listCollections() async throws -> [String] {
        let root = rootURL()
        return try await perform(.look, allowed: lookLimit) { wanted in
            try KeptDiskWork.listCollections(root: root)
        }
    }

    /// Every `<Collection>/<Name>/README.md` with `capsid_kept: 1`, newest
    /// kept first. A folder starting with "." (a keep in progress), a folder
    /// whose README can't be read, and one without the marker are passed over.
    func scan() async throws -> [KeptResult] {
        let root = rootURL()
        return try await perform(.look, allowed: lookLimit) { wanted in
            try KeptDiskWork.scan(root: root, wanted: wanted)
        }
    }

    /// A kept folder's README, read and parsed.
    func readme(at folder: URL) async throws -> (markdown: String, record: KeptRecord, text: KeptText) {
        let found = try await perform(.look, allowed: lookLimit) { wanted in
            try KeptDiskWork.readme(in: folder)
        }
        return (found.markdown, found.record, found.text)
    }

    /// The first `limit` bytes of a kept text file, as the card's picture of it:
    /// nil for a file that isn't text (a NUL in it), isn't under the Kept folder,
    /// or that iCloud has put away (never fetched for a picture).
    func peek(_ file: URL, limit: Int = 2_000) async throws -> String? {
        let root = rootURL()
        return try await perform(.look, allowed: lookLimit) { wanted in
            KeptDiskWork.peek(file, root: root, limit: limit)
        }
    }

    /// A kept picture's bytes, whole, for Copy: nil for a file that isn't under
    /// the Kept folder, that iCloud has put away (never fetched for a copy), is
    /// empty, or is bigger than `limit` (the 8 MB a keep takes).
    func pictureBytes(_ file: URL, limit: Int = 8 << 20) async throws -> Data? {
        let root = rootURL()
        return try await perform(.look, allowed: lookLimit) { wanted in
            KeptDiskWork.bytes(of: file, root: root, limit: limit)
        }
    }

    /// Whether `<root>/<collection>/<name>` is there already: false when the
    /// collection isn't there yet. The names are cleaned as `prepare` cleans them.
    func isTaken(collection: String, name: String) async throws -> Bool {
        let root = rootURL()
        return try await perform(.look, allowed: lookLimit) { wanted in
            KeptDiskWork.isTaken(root: root, collection: collection, name: name)
        }
    }

    // MARK: Keeping

    /// Makes `<root>/<Collection>/` if it isn't there and a hidden folder
    /// beside the one the keep will be, and says what to call it: `name`
    /// cleaned, or the dated name when that exists already.
    func prepare(collection: String, name: String, at date: Date) async throws -> KeptDestination {
        let root = rootURL()
        return try await perform(.write, allowed: limit(0)) { wanted in
            try KeptDiskWork.prepare(root: root, collection: collection, name: name, at: date)
        }
    }

    /// Writes a file into the folder being built; `data/`, `code/` and
    /// `input/` are made as they are needed. Atomic, and never over a file
    /// that is there: `.failed` then.
    func write(_ data: Data, to relativePath: String, in destination: KeptDestination) async throws {
        let folder = destination.tempFolder
        try await perform(.write, allowed: limit(data.count)) { wanted in
            try KeptDiskWork.writeFile(data, to: relativePath, in: folder)
        }
    }

    /// Writes README.md, last, and moves the folder into place. The name is
    /// never taken from a folder that exists: the dated one is used when it
    /// appeared meanwhile, then a numbered one. Answers where the folder is.
    func finish(_ destination: KeptDestination, readme: String) async throws -> URL {
        let bytes = Data(readme.utf8)
        return try await perform(.write, allowed: limit(bytes.count)) { wanted in
            try KeptDiskWork.finish(destination, readme: bytes)
        }
    }

    /// Deletes the folder a keep was being built in. Never throws: a folder
    /// that can't be removed is left, hidden, where it is.
    func abandon(_ destination: KeptDestination) async {
        let folder = destination.tempFolder
        _ = try? await perform(.cleanup, allowed: limit(0)) { wanted in
            KeptDiskWork.removeTemporary(folder)
        }
    }

    // MARK: Changing a folder that is kept

    /// One more file in a kept folder that is there (Try Again after a partial
    /// keep). As `write`: atomic, folders made as needed, nothing replaced.
    /// The folder must be a kept one (its README has the marker).
    func writeInto(_ folder: URL, _ data: Data, relativePath: String) async throws {
        try await perform(.write, allowed: limit(data.count)) { wanted in
            try KeptDiskWork.writeInto(folder, data, relativePath: relativePath)
        }
    }

    /// Replaces README.md in a kept folder (a temporary file, then a rename):
    /// for a rewritten `missing:` list and "Not copied" section. Both the
    /// README that is there and the new one must be Capsid's. With `lastRead`,
    /// the text the new one was made from, it is replaced only if the README
    /// is still, byte for byte, that (`changedOutside` when it isn't, and
    /// nothing is written): the comparison and the write are one call, so a
    /// person's edit in between is never written over.
    func replaceReadme(at folder: URL, markdown: String, lastRead: String? = nil) async throws {
        let bytes = Data(markdown.utf8)
        let last = lastRead.map { Data($0.utf8) }
        try await perform(.write, allowed: limit(bytes.count + (last?.count ?? 0))) { wanted in
            try KeptDiskWork.replaceReadme(in: folder, with: bytes, lastRead: last)
        }
    }

    /// Replaces the legend in a kept folder's README, and only that. Refuses
    /// (`changedOutside`) when the README is no longer, byte for byte, what
    /// the caller last read. Answers the new README.
    func replaceLegend(at folder: URL, with legend: String, lastRead markdown: String) async throws -> String {
        let last = Data(markdown.utf8)
        return try await perform(.write, allowed: limit(last.count + legend.utf8.count)) { wanted in
            try KeptDiskWork.replaceLegend(in: folder, with: legend, lastRead: last)
        }
    }

    /// Copies one more file into a kept folder, beside the figure, and lists it in the README (`files:`, through
    /// `KeptReadme.updating`, so every other byte of the README stays). Refuses (`changedOutside`) when the README is no
    /// longer, byte for byte, what the caller last read, and writes nothing then. The file is never written over another:
    /// the same bytes already under that name are reused, other bytes under it get the next free number. A version that
    /// is listed already (same role and version) is not copied again. Answers the path and the new README.
    func listFile(_ data: Data, as file: KeptFile, in folder: URL, lastRead markdown: String) async throws -> KeptListing {
        let root = rootURL()
        let last = Data(markdown.utf8)
        return try await perform(.write, allowed: limit(data.count + 2 * last.count)) { wanted in
            try KeptDiskWork.listFile(in: folder, root: root, data: data, file: file, lastRead: last)
        }
    }

    // MARK: Taking a folder off the shelf

    /// Moves a kept folder to the Trash and answers where it is there. Only a
    /// folder a keep made: its README is Capsid's, and it is a result in a
    /// collection of the Kept folder. Nothing is deleted.
    func trash(_ folder: URL) async throws -> URL {
        let root = rootURL()
        let trasher = self.trasher
        return try await perform(.write, allowed: limit(0)) { wanted in
            try KeptDiskWork.trash(folder, root: root, using: trasher)
        }
    }

    /// Puts a folder `trash` moved back where it was, or under the dated name
    /// when that name is taken now; never over a folder that is there. Answers
    /// where it is.
    func restore(_ trashed: URL, to folder: URL, at date: Date = Date()) async throws -> URL {
        let root = rootURL()
        return try await perform(.write, allowed: limit(0)) { wanted in
            try KeptDiskWork.restore(trashed, to: folder, root: root, at: date)
        }
    }

    /// The checksum of some bytes, in lowercase hex. A computation, not a
    /// disk call, so it is fit to run anywhere.
    nonisolated func sha256(of data: Data) -> String {
        Self.sha256(of: data)
    }

    nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: One call

    /// Runs `body` off the main actor within `allowed`, one call at a time. A
    /// look is cancellable: if its task was cancelled before its turn it makes
    /// no call, and if after, its caller is let go at once and the call
    /// finishes on its own.
    private func perform<Value: Sendable>(_ kind: Kind, allowed: Duration,
                                          _ body: @escaping @Sendable (StillWanted) throws -> Value) async throws -> Value {
        if kind != .cleanup, stuck.count > 0 { throw KeptDiskError.notResponding(KeptDiskError.stillSilent) }
        await takeTurn()
        defer { passTurn() }
        if kind == .look, Task.isCancelled { throw CancellationError() }
        // The folder may have gone silent while this call waited.
        if kind != .cleanup, stuck.count > 0 { throw KeptDiskError.notResponding(KeptDiskError.stillSilent) }

        let sentence = kind == .write ? KeptDiskError.writeDidNotRespond : KeptDiskError.lookDidNotRespond
        let call = Call<Value>(stuck: stuck)
        defer { call.stopTimer() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                call.install(continuation)
                run {
                    let result: Result<Value, any Error>
                    do {
                        result = .success(try body { call.isLive })
                    } catch {
                        result = .failure(KeptDiskError.from(error))
                    }
                    call.returned(result)
                }
                call.setTimer(Task { [wait] in
                    await wait(allowed)
                    guard !Task.isCancelled else { return }
                    call.timeout(KeptDiskError.notResponding(sentence))
                })
            }
        } onCancel: {
            if kind == .look { call.cancel() }
        }
    }

    private func takeTurn() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func passTurn() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// MARK: One call's bookkeeping

/// How many calls are out past their limit and haven't come back.
private final class StuckCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func enter() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func leave() {
        lock.lock()
        value -= 1
        lock.unlock()
    }
}

/// One call, from the moment it starts to the moment it returns: whichever
/// comes first of the answer, the time limit and a cancel resumes its caller,
/// once. A call that comes back after its time limit passed is late, and its
/// result is dropped (what it wrote stays where it landed).
private final class Call<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let stuck: StuckCount
    private var continuation: CheckedContinuation<Value, any Error>?
    private var timer: Task<Void, Never>?
    private var resumed = false
    private var timedOut = false
    private var cancelRequested = false

    init(stuck: StuckCount) {
        self.stuck = stuck
    }

    var isLive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !resumed
    }

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        lock.lock()
        if cancelRequested, !resumed {
            resumed = true
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setTimer(_ task: Task<Void, Never>) {
        lock.lock()
        let done = resumed
        if !done { timer = task }
        lock.unlock()
        if done { task.cancel() }
    }

    func stopTimer() {
        lock.lock()
        let task = timer
        timer = nil
        lock.unlock()
        task?.cancel()
    }

    /// The blocking call came back.
    func returned(_ result: Result<Value, any Error>) {
        lock.lock()
        let waiter = take()
        let late = timedOut
        let task = timer
        timer = nil
        lock.unlock()
        task?.cancel()
        // The folder answers again.
        if late { stuck.leave() }
        waiter?.resume(with: result)
    }

    /// The time limit passed first.
    func timeout(_ error: any Error) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        timedOut = true
        stuck.enter()
        let waiter = take()
        timer = nil
        lock.unlock()
        waiter?.resume(throwing: error)
    }

    /// The asking task was cancelled.
    func cancel() {
        lock.lock()
        cancelRequested = true
        let waiter = take()
        lock.unlock()
        waiter?.resume(throwing: CancellationError())
    }

    /// Hands out the continuation, once. (Call with the lock held.)
    private func take() -> CheckedContinuation<Value, any Error>? {
        guard !resumed, let continuation else { return nil }
        resumed = true
        self.continuation = nil
        return continuation
    }
}

// MARK: The disk work

/// Every file-system call Keep makes, blocking, and so only ever run by
/// `KeptDisk.perform` on its queue. Not main-actor code.
private enum KeptDiskWork {
    /// A README is a page or two; one this big isn't one of ours.
    static let readmeCap = 2 << 20
    static let notKept = "This isn't a folder Capsid keeps."

    private static var files: FileManager { FileManager.default }

    /// Whether something is at `url`, and whether it is a folder.
    private static func look(_ url: URL) -> (exists: Bool, isDirectory: Bool) {
        var isDirectory: ObjCBool = false
        let exists = files.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    }

    /// Makes one folder (not the ones above it). Another program making it
    /// first is as good as making it.
    private static func makeFolder(_ url: URL) throws {
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            guard look(url).isDirectory else { throw error }
        }
    }

    // MARK: The root

    enum RootState {
        case ready
        /// Not there, but the folder it belongs in is: the first keep makes it.
        case absent
        /// Not there, and neither is the folder it belongs in.
        case missing
    }

    static func rootState(_ root: URL) throws -> RootState {
        let here = look(root)
        if here.exists {
            guard here.isDirectory else { throw KeptDiskError.rootMissing }
            return .ready
        }
        return look(root.deletingLastPathComponent()).isDirectory ? .absent : .missing
    }

    /// The names of the folders in `folder` that aren't hidden.
    private static func subfolders(of folder: URL) throws -> [String] {
        try files.contentsOfDirectory(atPath: folder.path).filter { name in
            !name.hasPrefix(".") && look(folder.appending(path: name, directoryHint: .isDirectory)).isDirectory
        }
    }

    private static func sortedWithoutCase(_ names: [String]) -> [String] {
        names.sorted { a, b in
            let order = a.compare(b, options: .caseInsensitive)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
    }

    static func listCollections(root: URL) throws -> [String] {
        switch try rootState(root) {
        case .missing: throw KeptDiskError.rootMissing
        case .absent: return []
        case .ready: return sortedWithoutCase(try subfolders(of: root))
        }
    }

    static func isTaken(root: URL, collection: String, name: String) -> Bool {
        let folder = root.appending(path: KeptName.sanitized(collection), directoryHint: .isDirectory)
            .appending(path: KeptName.sanitized(name), directoryHint: .isDirectory)
        return look(folder).exists
    }

    // MARK: Reading READMEs

    /// A README's bytes, unless there is none or it is too big to be ours.
    private static func readmeData(in folder: URL) throws -> Data {
        let url = folder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory)
        let size = (try files.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= readmeCap else { throw KeptDiskError.failed("README.md is too big to read.") }
        return try Data(contentsOf: url)
    }

    /// A folder's README when it is one Capsid wrote: nil for anything else, for
    /// whatever reason.
    private static func keptReadme(in folder: URL) -> (markdown: String, record: KeptRecord, text: KeptText)? {
        guard let data = try? readmeData(in: folder), let markdown = readmeText(data),
              let parsed = KeptReadme.parse(markdown) else { return nil }
        return (markdown, parsed.record, parsed.text)
    }

    static func readme(in folder: URL) throws -> (markdown: String, record: KeptRecord, text: KeptText) {
        guard look(folder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory)).exists else {
            throw KeptDiskError.failed("There is no README.md in this folder.")
        }
        guard let found = keptReadme(in: folder) else { throw KeptDiskError.failed(notKept) }
        return found
    }

    static func scan(root: URL, wanted: KeptDisk.StillWanted) throws -> [KeptResult] {
        switch try rootState(root) {
        case .missing: throw KeptDiskError.rootMissing
        case .absent: return []
        case .ready: break
        }
        var results: [KeptResult] = []
        for collection in try subfolders(of: root) {
            let collectionFolder = root.appending(path: collection, directoryHint: .isDirectory)
            // A collection that can't be listed has nothing to show.
            guard let names = try? subfolders(of: collectionFolder) else { continue }
            for name in names {
                guard wanted() else { return results }
                let folder = collectionFolder.appending(path: name, directoryHint: .isDirectory)
                guard let found = keptReadme(in: folder) else { continue }
                results.append(KeptResult(folder: folder, collection: collection, record: found.record, text: found.text))
            }
        }
        return results.sorted { a, b in
            a.record.keptAt == b.record.keptAt ? a.folder.path < b.folder.path : a.record.keptAt > b.record.keptAt
        }
    }

    // MARK: Building a keep

    /// The first name not taken: the plain one, the dated one, then the dated
    /// one numbered.
    private static func firstFreeName(in folder: URL, base: String, date: Date) -> String {
        func taken(_ name: String) -> Bool { look(folder.appending(path: name, directoryHint: .isDirectory)).exists }
        if !taken(base) { return base }
        let dated = KeptName.dated(base, at: date)
        if !taken(dated) { return dated }
        for n in 2...999 {
            let candidate = KeptName.numbered(dated, n)
            if !taken(candidate) { return candidate }
        }
        return KeptName.numbered(dated, Int.random(in: 1000...999_999))
    }

    static func prepare(root: URL, collection: String, name: String, at date: Date) throws -> KeptDestination {
        switch try rootState(root) {
        case .missing: throw KeptDiskError.rootMissing
        case .absent: try makeFolder(root)
        case .ready: break
        }
        let collectionName = KeptName.sanitized(collection)
        let collectionFolder = root.appending(path: collectionName, directoryHint: .isDirectory)
        let here = look(collectionFolder)
        if here.exists {
            guard here.isDirectory else { throw KeptDiskError.failed("“\(collectionName)” in the Kept folder isn't a folder.") }
        } else {
            try makeFolder(collectionFolder)
        }
        let finalName = firstFreeName(in: collectionFolder, base: KeptName.sanitized(name), date: date)
        let temp = collectionFolder.appending(path: KeptName.temporaryFolder(for: finalName), directoryHint: .isDirectory)
        try files.createDirectory(at: temp, withIntermediateDirectories: false)
        return KeptDestination(collection: collectionName, name: finalName,
                               finalFolder: collectionFolder.appending(path: finalName, directoryHint: .isDirectory),
                               tempFolder: temp, keptAt: date)
    }

    /// One file into `folder`: the path must be one a keep may write, the
    /// folder must be there, and nothing at the path may be.
    static func writeFile(_ data: Data, to relativePath: String, in folder: URL) throws {
        guard KeptLayout.isValidRelativePath(relativePath) else {
            throw KeptDiskError.failed("That file's name can't be used in a Kept folder.")
        }
        guard look(folder).isDirectory else { throw KeptDiskError.failed("The folder for this keep isn't there.") }
        let parts = relativePath.split(separator: "/").map(String.init)
        if parts.count == 2 {
            let subfolder = folder.appending(path: parts[0], directoryHint: .isDirectory)
            let here = look(subfolder)
            if here.exists {
                guard here.isDirectory else { throw KeptDiskError.failed("“\(parts[0])” in this folder isn't a folder.") }
            } else {
                try makeFolder(subfolder)
            }
        }
        let target = folder.appending(path: relativePath, directoryHint: .notDirectory)
        guard !look(target).exists else { throw KeptDiskError.failed("A file with this name is already there.") }
        try data.write(to: target, options: .atomic)
    }

    static func writeInto(_ folder: URL, _ data: Data, relativePath: String) throws {
        guard keptReadme(in: folder) != nil else { throw KeptDiskError.failed(notKept) }
        try writeFile(data, to: relativePath, in: folder)
    }

    /// README last, then the rename, which doesn't replace a folder: the
    /// plain name, else the dated one, else it numbered.
    static func finish(_ destination: KeptDestination, readme: Data) throws -> URL {
        guard look(destination.tempFolder).isDirectory else {
            throw KeptDiskError.failed("The folder for this keep isn't there.")
        }
        try readme.write(to: destination.tempFolder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory),
                         options: .atomic)
        let parent = destination.finalFolder.deletingLastPathComponent()
        var names = [destination.finalFolder.lastPathComponent]
        let dated = KeptName.isDated(destination.name)
            ? destination.name : KeptName.dated(destination.name, at: destination.keptAt ?? Date())
        if dated != names[0] { names.append(dated) }
        names += (2...99).map { KeptName.numbered(dated, $0) }
        for name in names {
            let target = parent.appending(path: name, directoryHint: .isDirectory)
            if try moveWithoutReplacing(destination.tempFolder, to: target) { return target }
        }
        throw KeptDiskError.failed("No free name was left for this folder.")
    }

    /// Renames a folder to a name nothing has. False when something has it.
    /// (Renaming onto an empty folder would replace it, so the check is made by
    /// the file system, in the same call, where the volume can.)
    private static func moveWithoutReplacing(_ source: URL, to target: URL) throws -> Bool {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return true }
        let code = errno
        if code == EEXIST { return false }
        if code == ENOTSUP || code == EINVAL {
            // A volume that can't say "only if free": look first, then move.
            if look(target).exists { return false }
            try files.moveItem(at: source, to: target)
            return true
        }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    /// Deletes a keep's hidden folder, and only that: never a folder that
    /// doesn't have the hidden folder's name.
    static func removeTemporary(_ folder: URL) {
        guard KeptName.isTemporary(folder.lastPathComponent), look(folder).isDirectory else { return }
        try? files.removeItem(at: folder)
    }

    // MARK: A look at a text file

    /// A file iCloud has put away (not on this Mac, or not all of it): reading
    /// it, or asking Quick Look for its picture, would bring it back. A file
    /// that isn't in iCloud has no such status, and is not put away.
    static func isPutAway(_ file: URL) -> Bool {
        // A URL keeps the values it was asked for: a fresh one, so it is today's.
        var fresh = file
        fresh.removeAllCachedResourceValues()
        guard let status = (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status != .current
    }

    /// A file's date, size and whether iCloud has put it away; nil when it
    /// can't be looked at.
    static func fileFacts(_ file: URL) -> KeptFileFacts? {
        var fresh = file
        fresh.removeAllCachedResourceValues()
        guard let values = try? fresh.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
        return KeptFileFacts(modified: values.contentModificationDate, size: values.fileSize, putAway: isPutAway(file))
    }

    static func peek(_ file: URL, root: URL, limit: Int) -> String? {
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        // A file iCloud has put away isn't read: reading it would bring it back.
        if isPutAway(file) { return nil }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit), !data.isEmpty, !data.contains(0) else { return nil }
        // Cut at a whole character: a cut in the middle of one is not a reason to refuse.
        for cut in 0...3 where data.count - cut > 0 {
            if let text = String(data: data.prefix(data.count - cut), encoding: .utf8) { return text }
        }
        return nil
    }

    /// A file's bytes when it is under `root`, is here, and is no bigger than
    /// `limit`: one byte more than that is read to tell. Nil otherwise.
    static func bytes(of file: URL, root: URL, limit: Int) -> Data? {
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        if isPutAway(file) { return nil }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), !data.isEmpty, data.count <= limit else { return nil }
        return data
    }

    // MARK: The Trash

    /// `<root>/<collection>/<name>`: the shape of a result and nothing else.
    private static func isResult(_ folder: URL, in root: URL) -> Bool {
        folder.deletingLastPathComponent().deletingLastPathComponent().path == root.path
            && !KeptName.isTemporary(folder.lastPathComponent)
    }

    static func trash(_ folder: URL, root: URL, using trasher: (@Sendable (URL) throws -> URL?)?) throws -> URL {
        guard isResult(folder, in: root), keptReadme(in: folder) != nil else { throw KeptDiskError.failed(notKept) }
        if let trasher { return try trasher(folder) ?? folder }
        var landed: NSURL?
        try files.trashItem(at: folder, resultingItemURL: &landed)
        return (landed as URL?) ?? folder
    }

    static func restore(_ trashed: URL, to folder: URL, root: URL, at date: Date) throws -> URL {
        guard look(trashed).isDirectory, keptReadme(in: trashed) != nil else {
            throw KeptDiskError.failed("It isn't in the Trash any more.")
        }
        guard isResult(folder, in: root) else { throw KeptDiskError.failed(notKept) }
        let parent = folder.deletingLastPathComponent()
        let here = look(parent)
        if here.exists {
            guard here.isDirectory else { throw KeptDiskError.failed("“\(parent.lastPathComponent)” in the Kept folder isn't a folder.") }
        } else {
            switch try rootState(root) {
            case .missing: throw KeptDiskError.rootMissing
            case .absent: try makeFolder(root)
            case .ready: break
            }
            try makeFolder(parent)
        }
        let base = folder.lastPathComponent
        let dated = KeptName.isDated(base) ? base : KeptName.dated(base, at: date)
        var names = [base]
        if dated != base { names.append(dated) }
        names += (2...99).map { KeptName.numbered(dated, $0) }
        for name in names {
            let target = parent.appending(path: name, directoryHint: .isDirectory)
            if try moveWithoutReplacing(trashed, to: target) { return target }
        }
        throw KeptDiskError.failed("No free name was left for this folder.")
    }

    // MARK: Changing READMEs

    /// An editor's byte order mark: not in the text a README is read as
    /// (`readmeText` takes it off), so it is set aside to compare, and put back
    /// when the file is written again, by the legend's save as by Try Again's.
    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    /// A README's bytes without a byte order mark, and whether it had one.
    private static func withoutByteOrderMark(_ data: Data) -> (bytes: Data, marked: Bool) {
        data.starts(with: byteOrderMark) ? (Data(data.dropFirst(byteOrderMark.count)), true) : (data, false)
    }

    /// A README's text: its bytes as UTF-8, never with the mark. This is the
    /// text callers hold (`lastRead`) and compare against, whatever the
    /// system's decoding does with a mark.
    private static func readmeText(_ data: Data) -> String? {
        String(data: withoutByteOrderMark(data).bytes, encoding: .utf8)
    }

    static func replaceReadme(in folder: URL, with markdown: Data, lastRead: Data? = nil) throws {
        var written = markdown
        if let lastRead {
            guard look(folder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory)).exists else {
                throw KeptDiskError.failed("There is no README.md in this folder.")
            }
            let (current, marked) = withoutByteOrderMark(try readmeData(in: folder))
            // Bytes, not characters: "é" typed two ways is two files.
            guard current == lastRead else { throw KeptDiskError.changedOutside }
            if marked { written = byteOrderMark + markdown }
        }
        guard keptReadme(in: folder) != nil else { throw KeptDiskError.failed(notKept) }
        guard let text = String(data: markdown, encoding: .utf8), KeptReadme.parse(text) != nil else {
            throw KeptDiskError.failed("That README isn't one Capsid can read back.")
        }
        try written.write(to: folder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory), options: .atomic)
    }

    static func replaceLegend(in folder: URL, with legend: String, lastRead: Data) throws -> String {
        let url = folder.appending(path: KeptLayout.readmeName, directoryHint: .notDirectory)
        guard look(url).exists else { throw KeptDiskError.failed("There is no README.md in this folder.") }
        // An editor's byte order mark is no part of the text the caller read: compared without it, and put back.
        let (current, marked) = withoutByteOrderMark(try readmeData(in: folder))
        // Bytes, not characters: "é" typed two ways is two files.
        guard current == lastRead else { throw KeptDiskError.changedOutside }
        guard let text = String(data: current, encoding: .utf8), KeptReadme.parse(text) != nil else {
            throw KeptDiskError.failed(notKept)
        }
        guard let replaced = KeptReadme.replacingLegend(in: text, with: legend) else {
            // It read as Capsid's, so the heading is there: this is a README whose line ends can't be put back as they were.
            throw KeptDiskError.failed("README.md has a form Capsid can\u{2019}t edit safely, so it was left alone.")
        }
        // The answer is the README as text, without the mark: the caller's next `lastRead`.
        try ((marked ? byteOrderMark : Data()) + Data(replaced.utf8)).write(to: url, options: .atomic)
        return replaced
    }

    /// The work of `KeptDisk.listFile`: the README is compared first and the new one made in memory, then the file is
    /// written (never over another), and the README last, by `replaceReadme`, which compares and writes in one call.
    static func listFile(in folder: URL, root: URL, data: Data, file: KeptFile, lastRead: Data) throws -> KeptListing {
        let (current, _) = withoutByteOrderMark(try readmeData(in: folder))
        // Bytes, not characters: "é" typed two ways is two files.
        guard current == lastRead else { throw KeptDiskError.changedOutside }
        guard let text = String(data: current, encoding: .utf8), let parsed = KeptReadme.parse(text) else {
            throw KeptDiskError.failed(notKept)
        }
        if file.version != nil,
           let listed = parsed.record.files.first(where: { $0.role == file.role && $0.version == file.version }) {
            return KeptListing(path: listed.path, markdown: text, wasListed: true)
        }
        // The name asked for; if something else is there already, the next free number.
        let clean = KeptLayout.fileName(file.path)
        var path = clean
        var present = false
        var number = 2
        while look(folder.appending(path: path, directoryHint: .notDirectory)).exists {
            if bytes(of: folder.appending(path: path, directoryHint: .notDirectory), root: root, limit: data.count) == data {
                present = true
                break
            }
            guard number < 100 else { throw KeptDiskError.failed("No free name was left for this file.") }
            path = ShelfFileName.numbered(clean, number)
            number += 1
        }
        var listing = file
        listing.path = path
        guard let updated = KeptReadme.updating(text, files: parsed.record.files + [listing], missing: parsed.record.missing) else {
            throw KeptDiskError.failed("README.md has a form Capsid can\u{2019}t update safely, so it was left alone.")
        }
        if !present { try writeFile(data, to: path, in: folder) }
        try replaceReadme(in: folder, with: Data(updated.utf8), lastRead: lastRead)
        return KeptListing(path: path, markdown: updated, wasListed: false)
    }
}
