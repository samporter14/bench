// ProcessExitWatcher.swift — tells the Lab the moment Claude Science's daemon
// exits, as `DatabaseWatcher` tells it of a write: a kqueue process source,
// nothing polled. A quit or a crash then shows as "Claude Science isn't
// running" at once, whether or not the daemon's write-ahead log goes away
// (it stays when Bench's connection is open as the daemon closes).
import Foundation

@MainActor
final class ProcessExitWatcher {
    let pid: Int32
    private var source: DispatchSourceProcess?

    /// Calls `onExit` once, on the main queue, when `pid` exits; at once when
    /// it is already gone.
    init(pid: Int32, onExit: @escaping @MainActor () -> Void) {
        self.pid = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        var fired = false
        let exited: @MainActor () -> Void = { [weak self] in
            guard !fired else { return }
            fired = true
            self?.stop()
            onExit()
        }
        source.setEventHandler { MainActor.assumeIsolated { exited() } }
        self.source = source
        source.resume()
        // An exit before the source was registered may never be reported.
        if !processIsAlive(pid) { DispatchQueue.main.async { MainActor.assumeIsolated { exited() } } }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    isolated deinit {
        source?.cancel()
    }
}
