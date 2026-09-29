// Subprocess.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// Why a command did not produce output.
enum SubprocessFailure: Error, Equatable {
    case couldNotStart(String)
    case timedOut
}

/// How long a command that timed out has to exit after SIGTERM, and again
/// after SIGKILL.
private let terminationGrace: TimeInterval = 1

/// Run a command and return its exit status and standard output.
///
/// Output is drained while the command runs. Waiting for the exit first and
/// reading afterwards deadlocks as soon as the output outgrows the pipe
/// buffer (64 KB): the command blocks on a full pipe and never exits.
///
/// `timeout` bounds the output and the exit both, since a command can close
/// its output and carry on. One still going then gets SIGTERM, SIGKILL if it
/// ignores that, and the reader stops even while something the command
/// started holds the pipe open: nothing is left running once this returns.
func runProcess(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: Data) {
    let task = Process()
    task.executableURL = executable
    task.arguments = arguments
    let out = Pipe()
    task.standardOutput = out
    task.standardError = FileHandle.nullDevice
    task.standardInput = FileHandle.nullDevice
    let exited = DispatchSemaphore(value: 0)
    task.terminationHandler = { _ in exited.signal() }
    do { try task.run() } catch { throw SubprocessFailure.couldNotStart(error.localizedDescription) }

    let reader = OutputReader(out.fileHandleForReading)
    let deadline = DispatchTime.now() + timeout
    guard reader.wait(until: deadline), exited.wait(timeout: deadline) == .success else {
        stop(task, exited: exited)
        reader.stop()
        throw SubprocessFailure.timedOut
    }
    return (task.terminationStatus, reader.output)
}

/// SIGTERM, then SIGKILL for a command that ignores it, each given
/// `terminationGrace`. Only a command still running is signalled, so never
/// another process that has since been given its pid.
private func stop(_ task: Process, exited: DispatchSemaphore) {
    for signal in [SIGTERM, SIGKILL] {
        guard task.isRunning else { return }
        kill(task.processIdentifier, signal)
        if exited.wait(timeout: .now() + terminationGrace) == .success { return }
    }
}

/// Drains a pipe on a thread of its own. It polls rather than blocking in
/// read(), so `stop()` ends it even while the pipe is held open.
private final class OutputReader: @unchecked Sendable {
    private let done = DispatchGroup()
    private let lock = NSLock()
    private var stopped = false
    /// Written only by the reader, and read only once `done` is through.
    private var data = Data()

    init(_ pipe: FileHandle) {
        done.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { done.leave() }
            let fd = pipe.fileDescriptor
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while !lock.withLock({ stopped }) {
                var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let polled = poll(&ready, 1, 100)
                if polled == 0 || (polled < 0 && errno == EINTR) { continue }
                let count = polled < 0 ? -1 : read(fd, &chunk, chunk.count)
                if count > 0 {
                    data.append(contentsOf: chunk[..<count])
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return   // 0 is the end of the output; -1 a broken pipe
                }
            }
        }
    }

    /// Whether the output ended by `deadline`.
    func wait(until deadline: DispatchTime) -> Bool {
        done.wait(timeout: deadline) == .success
    }

    /// The output, once `wait(until:)` has returned true.
    var output: Data { data }

    /// Ends the read within a poll's tenth of a second.
    func stop() {
        lock.withLock { stopped = true }
        _ = done.wait(timeout: .now() + terminationGrace)
    }
}
