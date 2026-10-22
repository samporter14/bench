// ReadingGateTests.swift — the reading gate: the pause rule, one read at a
// time, waiting out a key press, and cancellation reaching the read.
import Foundation
import Testing
@testable import Bench

@MainActor
struct ReadingGateTests {
    nonisolated static let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func thePauseIsTheRestOfTheQuietAfterAKeyWithinPatience() {
        #expect(ReadingGate.pause(lastKey: nil, now: Self.t0, waited: .zero) == nil)
        #expect(ReadingGate.pause(lastKey: Self.t0.addingTimeInterval(-0.1), now: Self.t0, waited: .zero)
                == .milliseconds(300))
        #expect(ReadingGate.pause(lastKey: Self.t0, now: Self.t0, waited: .zero) == .milliseconds(400))
        #expect(ReadingGate.pause(lastKey: Self.t0.addingTimeInterval(-0.5), now: Self.t0, waited: .zero) == nil)
        #expect(ReadingGate.pause(lastKey: Self.t0.addingTimeInterval(-0.4), now: Self.t0, waited: .zero) == nil)
        // Patience is spent: go anyway.
        #expect(ReadingGate.pause(lastKey: Self.t0, now: Self.t0, waited: .seconds(2)) == nil)
        #expect(ReadingGate.pause(lastKey: Self.t0.addingTimeInterval(-0.1), now: Self.t0, waited: .milliseconds(1_900))
                == .milliseconds(100))
        // A key press in the future counts as just now.
        #expect(ReadingGate.pause(lastKey: Self.t0.addingTimeInterval(5), now: Self.t0, waited: .zero) == .milliseconds(400))
    }

    @Test func readsRunOneAtATimeInOrder() async throws {
        let gate = ReadingGate(now: { Self.t0 }, sleep: { _ in })
        final class Log: @unchecked Sendable { var lines: [String] = [] }
        let log = Log()
        let first = Task { @MainActor in
            try await gate.perform {
                log.lines.append("first starts")
                try await Task.sleep(for: .milliseconds(30))
                log.lines.append("first ends")
                return 1
            }
        }
        let second = Task { @MainActor in
            try await gate.perform {
                log.lines.append("second starts")
                return 2
            }
        }
        #expect(try await first.value == 1)
        #expect(try await second.value == 2)
        #expect(log.lines == ["first starts", "first ends", "second starts"])
        #expect(gate.mostInFlight == 1)
        #expect(gate.inFlight == 0)
    }

    @Test func aReadWaitsOutAKeyPressThenGoes() async throws {
        final class Clock: @unchecked Sendable {
            var now = ReadingGateTests.t0
            var slept: [Duration] = []
        }
        let clock = Clock()
        let gate = ReadingGate(now: { clock.now }, sleep: { pause in
            clock.slept.append(pause)
            clock.now = clock.now.addingTimeInterval(Double(pause.components.seconds)
                                                     + Double(pause.components.attoseconds) / 1e18)
        })
        gate.noteKey(at: Self.t0.addingTimeInterval(-0.1))
        let value = try await gate.perform { "read" }
        #expect(value == "read")
        #expect(clock.slept == [.milliseconds(300)])
        // Quiet now: no wait.
        let again = try await gate.perform { "again" }
        #expect(again == "again")
        #expect(clock.slept.count == 1)
    }

    @Test func aKeyPressDuringTheWaitExtendsItWithinPatience() async throws {
        final class Clock: @unchecked Sendable {
            var now = ReadingGateTests.t0
            var slept: [Duration] = []
        }
        let clock = Clock()
        var gate: ReadingGate!
        gate = ReadingGate(now: { clock.now }, sleep: { pause in
            clock.slept.append(pause)
            clock.now = clock.now.addingTimeInterval(Double(pause.components.seconds)
                                                     + Double(pause.components.attoseconds) / 1e18)
            // Typing goes on: every sleep ends with a fresh key press.
            gate.noteKey(at: clock.now)
        })
        gate.noteKey(at: Self.t0)
        _ = try await gate.perform { "read" }
        let total = clock.slept.reduce(Duration.zero, +)
        #expect(total == ReadingGate.patience)
        #expect(clock.slept.first == ReadingGate.quiet)
    }

    @Test func cancellingTheCallerCancelsTheRead() async throws {
        let gate = ReadingGate(now: { Self.t0 }, sleep: { _ in })
        final class Flag: @unchecked Sendable { var cancelled = false; var started = false }
        let flag = Flag()
        let task = Task { @MainActor in
            try await gate.perform {
                flag.started = true
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    flag.cancelled = true
                    throw error
                }
                return 0
            }
        }
        for _ in 0..<100 where !flag.started { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(flag.cancelled)
        #expect(gate.inFlight == 0)
        // The next read is not held up by the cancelled one.
        #expect(try await gate.perform { 7 } == 7)
    }
}
