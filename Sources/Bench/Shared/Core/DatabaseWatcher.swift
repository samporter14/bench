// DatabaseWatcher.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// How long to wait before looking again for something that isn't there:
/// two seconds, then twice as long each time, up to a minute. `advance()`
/// says how long to wait now and moves on to the next; `reset()` starts over.
struct RetryBackoff: Equatable, Sendable {
    static let first: TimeInterval = 2
    static let cap: TimeInterval = 60

    private var upcoming = RetryBackoff.first

    mutating func advance() -> TimeInterval {
        let now = upcoming
        upcoming = min(Self.cap, upcoming * 2)
        return now
    }

    mutating func reset() { upcoming = Self.first }
}

/// Tells the droplet the moment the daemon writes to its database, so a
/// session starting, parking on a card or finishing shows within a second
/// instead of at the next poll, and nothing runs while nothing changes.
///
/// Watches the write-ahead log (`<db>-wal`), where every write lands first,
/// with a kqueue vnode source. Not FSEvents: it reports a file's changes when
/// the file is closed, and the daemon keeps its database open for good. Not
/// the `-shm` file either: every reader touches it, the droplet's own reads
/// included.
///
/// The first write is reported at once; after that at most one report per
/// `interval`, with one trailing report so the last write is never missed.
/// When the log goes away (daemon stopped or restarted) it reports once and
/// looks for it again.
///
/// Looking again costs next to nothing while the daemon is down. The log's
/// folder is watched for entries coming and going, so the log is picked up the
/// moment it is created, and a timer backs that up (the folder missing, an
/// event missed) at two seconds, then twice as long each time, up to a minute.
/// A log that opens starts the timer over for the next time it goes.
public final class DatabaseWatcher: @unchecked Sendable {
    private let log: URL
    private let folder: URL
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let schedule: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var folderSource: DispatchSourceFileSystemObject?
    private var backoff: RetryBackoff
    /// Whether a timer is waiting, and which: a timer made stale by a log that
    /// opened since (a newer epoch) does nothing when it fires.
    private var retryPending = false
    private var retryEpoch = 0
    private var stopped = false

    // Touched only on `queue`.
    private var lastReport = Date.distantPast
    private var trailingScheduled = false

    public convenience init(database: URL, interval: TimeInterval = 1, queue: DispatchQueue = .main,
                            onChange: @escaping @Sendable () -> Void) {
        self.init(database: database, interval: interval, queue: queue, backoff: RetryBackoff(),
                  schedule: nil, onChange: onChange)
    }

    /// `schedule` runs a retry after a delay; a test supplies its own and fires
    /// the retries itself. By default it is `queue.asyncAfter`.
    init(database: URL, interval: TimeInterval, queue: DispatchQueue, backoff: RetryBackoff,
         schedule: (@Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void)?,
         onChange: @escaping @Sendable () -> Void) {
        log = URL(fileURLWithPath: database.path + "-wal")
        folder = log.deletingLastPathComponent()
        self.interval = interval
        self.queue = queue
        self.backoff = backoff
        self.onChange = onChange
        self.schedule = schedule ?? { delay, work in queue.asyncAfter(deadline: .now() + delay, execute: work) }
        open()
    }

    /// Whether the log is open right now. False while the daemon is down;
    /// the watcher keeps looking on its own.
    public var isWatching: Bool {
        lock.lock(); defer { lock.unlock() }
        return source != nil
    }

    public func stop() {
        lock.lock()
        stopped = true
        retryEpoch += 1
        let current = source, watchedFolder = folderSource
        source = nil
        folderSource = nil
        lock.unlock()
        current?.cancel()
        watchedFolder?.cancel()
    }

    deinit { stop() }

    /// Looks for the log: from `init`, when it has just gone, when its folder
    /// changes, and (with `retry`, the epoch the timer was set in) when the
    /// timer fires.
    private func open(retry: Int? = nil) {
        lock.lock()
        guard !stopped, source == nil else { lock.unlock(); return }
        if let retry {
            guard retry == retryEpoch else { lock.unlock(); return }
            retryPending = false
        }
        var watched = makeLogSource()
        var newFolder: DispatchSourceFileSystemObject?
        if watched == nil, folderSource == nil {
            newFolder = makeFolderSource()
            folderSource = newFolder
            // The log may have been created while the folder was being set up.
            watched = makeLogSource()
        }
        var dropped: DispatchSourceFileSystemObject?
        var wait: TimeInterval?
        let epoch = retryEpoch
        if let watched {
            source = watched
            retryEpoch += 1
            retryPending = false
            backoff.reset()
            dropped = folderSource
            folderSource = nil
        } else if !retryPending {
            retryPending = true
            wait = backoff.advance()
        }
        lock.unlock()
        newFolder?.resume()
        watched?.resume()
        dropped?.cancel()
        if let wait { schedule(wait) { [weak self] in self?.open(retry: epoch) } }
    }

    /// The log's source, not yet resumed, or nil if the log isn't there.
    /// Called with the lock held.
    private func makeLogSource() -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(log.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let watched = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: queue)
        watched.setEventHandler { [weak self, weak watched] in
            guard let self, let watched else { return }
            if !watched.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.lock.lock()
                if self.source === watched { self.source = nil }
                self.lock.unlock()
                watched.cancel()
                self.report()
                self.open()
            } else {
                self.report()
            }
        }
        watched.setCancelHandler { close(fd) }
        return watched
    }

    /// The log's folder, not yet resumed, or nil if it isn't there. Its
    /// events say only that an entry came or went, so each one is a look for
    /// the log. Called with the lock held.
    private func makeFolderSource() -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let watched = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: queue)
        watched.setEventHandler { [weak self, weak watched] in
            guard let self, let watched else { return }
            if !watched.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                // The folder itself went; the timer sets the watch up again.
                self.lock.lock()
                if self.folderSource === watched { self.folderSource = nil }
                self.lock.unlock()
                watched.cancel()
            }
            self.open()
        }
        watched.setCancelHandler { close(fd) }
        return watched
    }

    private func report() {
        let wait = interval - Date().timeIntervalSince(lastReport)
        if wait <= 0 {
            lastReport = Date()
            onChange()
        } else if !trailingScheduled {
            trailingScheduled = true
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.trailingScheduled = false
                self.lock.lock(); let live = !self.stopped; self.lock.unlock()
                guard live else { return }
                self.lastReport = Date()
                self.onChange()
            }
        }
    }
}
