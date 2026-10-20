// NextWaitingTests.swift — Next Waiting Session: which session a press opens
// and in what order, the round, a put-off session counting only once due, the
// dimming, the keys, and that ⌥⌘↓ is the menus' own. Made-up sessions; what a
// press opens is recorded, never opened.
import AppKit
import Foundation
import Testing
@testable import Bench

private let epoch = Date(timeIntervalSince1970: 1_792_000_000)

private func waiting(_ id: String, minutesAgo: Double, reason: WaitingReason = .question) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "Session \(id)", state: .needsInput,
                  updatedAt: epoch.addingTimeInterval(-minutesAgo * 60),
                  startedAt: epoch.addingTimeInterval(-(minutesAgo + 5) * 60), waitingReason: reason)
}

private func running(_ id: String) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "Session \(id)", state: .running,
                  updatedAt: epoch, startedAt: epoch.addingTimeInterval(-600))
}

private func snapshot(_ sessions: [SessionStatus]) -> ScienceSnapshot {
    ScienceSnapshot(runningCount: sessions.count, daemonVersion: "test", sessions: sessions)
}

struct NextWaitingPickTests {
    private let a = waiting("a", minutesAgo: 30), b = waiting("b", minutesAgo: 20), c = waiting("c", minutesAgo: 10)

    @Test func nothingWaitingPicksNothing() {
        #expect(NextWaiting.pick(from: [], after: nil) == nil)
        #expect(NextWaiting.pick(from: [], after: a) == nil)
    }

    @Test func theFirstPressOpensTheOneThatHasWaitedLongest() {
        #expect(NextWaiting.pick(from: [a, b, c], after: nil) == a)
    }

    @Test func eachPressGoesOnAndTheEndGoesRoundToTheStart() {
        #expect(NextWaiting.pick(from: [a, b, c], after: a) == b)
        #expect(NextWaiting.pick(from: [a, b, c], after: b) == c)
        #expect(NextWaiting.pick(from: [a, b, c], after: c) == a)
    }

    @Test func oneSessionIsItsOwnNext() {
        #expect(NextWaiting.pick(from: [b], after: b) == b)
    }

    /// The one opened last was answered between two presses: the next press goes on from where it
    /// stood, not back to the top.
    @Test func aSessionThatLeftIsReplacedByTheOneAfterItsPlace() {
        #expect(NextWaiting.pick(from: [a, c], after: b) == c, "b stood between a and c")
        #expect(NextWaiting.pick(from: [a, b], after: c) == a, "c was last: round to the start")
        #expect(NextWaiting.pick(from: [b, c], after: a) == b, "a was first")
    }
}

@MainActor
struct NextWaitingTests {
    private let model = LabModel()
    private let opened = Opened()

    private final class Opened {
        var ids: [String] = []
    }

    private func walker() -> NextWaiting {
        let opened = opened
        return NextWaiting(model: model, open: { opened.ids.append($0.id) })
    }

    /// Three sessions waiting: c wrote last (most recent), a first (longest wait).
    private func threeWaiting() {
        model.ingest(snapshot([running("a"), running("b"), running("c")]))
        model.ingest(snapshot([waiting("c", minutesAgo: 10), waiting("a", minutesAgo: 30), waiting("b", minutesAgo: 20)]))
    }

    @Test func pressesWalkTheListFromTheLongestWaitAndGoRound() {
        threeWaiting()
        let next = walker()
        for _ in 0..<5 { next.openNext() }
        #expect(opened.ids == ["a", "b", "c", "a", "b"])
        #expect(next.order.map(\.id) == ["a", "b", "c"], "the order is the activity list's")
        #expect(next.order == NeedsYou(model: model).asks)
    }

    @Test func nothingWaitingIsDimAndOpensNothing() {
        let next = walker()
        #expect(!next.isEnabled)
        #expect(next.openNext() == nil)
        model.ingest(snapshot([running("a")]))
        #expect(!next.isEnabled && next.openNext() == nil)
        #expect(opened.ids.isEmpty)
    }

    @Test func aFailureIsNotAWaitingSession() {
        model.ingest(snapshot([running("f")]))
        model.ingest(snapshot([SessionStatus(id: "f", projectID: "p", projectName: "P", title: "T", state: .error,
                                             updatedAt: epoch, startedAt: epoch.addingTimeInterval(-600))]))
        #expect(!model.cards.isEmpty, "its failure card is up")
        #expect(!walker().isEnabled)
    }

    @Test func answeringTheOneJustOpenedGoesOnToTheNextNotBackToTheTop() {
        threeWaiting()
        let next = walker()
        next.openNext() // a
        next.openNext() // b
        // b is answered and runs on.
        model.ingest(snapshot([waiting("c", minutesAgo: 10), waiting("a", minutesAgo: 30), running("b")]))
        next.openNext()
        #expect(opened.ids == ["a", "b", "c"])
    }

    @Test func aPutOffSessionIsSkippedUntilItsReminderIsDue() async throws {
        threeWaiting()
        model.lifetimeScale = 0.0001
        model.remind(try #require(model.cards.first { $0.id == "needs-a" }), .fiveMinutes)
        let next = walker()
        next.openNext()
        next.openNext()
        next.openNext()
        #expect(opened.ids == ["b", "c", "b"], "a is under Later")
        // Due: it is a waiting session like the rest, and the longest wait.
        for _ in 0..<300 where !model.snoozed.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.snoozed.isEmpty)
        let again = walker()
        again.openNext()
        #expect(opened.ids.last == "a")
    }

    @Test func everyoneThatWaitsBeingPutOffDimsIt() throws {
        threeWaiting()
        model.isFocusing = { true }
        for id in ["a", "b", "c"] {
            model.remind(try #require(model.cards.first { $0.id == "needs-\(id)" }), .afterFocus)
        }
        #expect(!walker().isEnabled)
        model.focusEnded()
        #expect(walker().isEnabled)
    }

    @Test func theDockMenusItemIsFirstDimWhenNothingWaitsAndKeepsItsKeys() throws {
        let idle = ActivityMenu.shared.make(model: model).items
        #expect(idle.first?.title == NextWaiting.title)
        #expect(idle.first?.isEnabled == false)
        // The menu validates its items when it opens: this one is off, the rest are on.
        #expect(idle.first.map(ActivityMenu.shared.validateMenuItem) == false)
        #expect(idle.dropFirst().first?.isSeparatorItem == true)
        threeWaiting()
        let items = ActivityMenu.shared.make(model: model).items
        let item = try #require(items.first)
        #expect(item.title == NextWaiting.title && item.isEnabled && ActivityMenu.shared.validateMenuItem(item))
        #expect(items.dropFirst(2).allSatisfy { $0.isSectionHeader || ActivityMenu.shared.validateMenuItem($0) })
        #expect(item.keyEquivalentModifierMask == [.command, .option])
        #expect(item.keyEquivalent == String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        #expect(item.action != nil && item.target != nil)
        #expect(items.filter { $0.title == NextWaiting.title }.count == 1)
    }
}

struct NextWaitingKeyTests {
    private let down: UInt16 = 125

    @Test func optionCommandDownArrowIsTheKeyWithOrWithoutTheArrowKeysOwnFlags() {
        #expect(NextWaiting.isKey(modifiers: [.command, .option], keyCode: down))
        // An arrow key always carries these two as well.
        #expect(NextWaiting.isKey(modifiers: [.command, .option, .function, .numericPad], keyCode: down))
        #expect(NextWaiting.isKey(modifiers: [.command, .option, .capsLock], keyCode: down), "Caps Lock doesn't count")
    }

    @Test func nothingElseIs() {
        #expect(!NextWaiting.isKey(modifiers: [.command], keyCode: down))
        #expect(!NextWaiting.isKey(modifiers: [.option], keyCode: down))
        #expect(!NextWaiting.isKey(modifiers: [.command, .option, .shift], keyCode: down))
        #expect(!NextWaiting.isKey(modifiers: [.command, .option, .control], keyCode: down))
        #expect(!NextWaiting.isKey(modifiers: [.command, .option, .function, .numericPad], keyCode: 126), "up arrow")
        #expect(!NextWaiting.isKey(modifiers: [.command, .option], keyCode: 2), "a letter")
    }
}

/// The shortcut is on the File menu, wired to the one object, and no other menu
/// item of Capsid's has it (this scans the source: a menu item is not something a test can press).
struct NextWaitingWiringTests {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)
    }

    @Test func theMenuItemAndTheMonitorAreBothThere() throws {
        let app = try source("App/BenchApp.swift")
        #expect(app.contains("Button(NextWaiting.title) { NextWaiting.shared.openNext() }"))
        #expect(app.contains(".keyboardShortcut(.downArrow, modifiers: [.command, .option])"))
        #expect(app.contains("NextWaiting.isKey(modifiers: event.modifierFlags, keyCode: event.keyCode)"))
        // As Quick Open's: only in the Claude Science window, and dimmed in a demo or when nothing waits.
        #expect(app.contains("event.window === MainWindowController.shared.windowIfLoaded"))
        #expect(app.contains(".disabled(Demo.mode != nil || !NextWaiting.shared.isEnabled)"))
    }

    @Test func noMenuItemTakesTheSameKeysTwice() throws {
        let app = try source("App/BenchApp.swift")
        var seen: [String: Int] = [:]
        for line in app.split(separator: "\n") {
            guard let start = line.range(of: ".keyboardShortcut(") else { continue }
            var arguments = String(line[start.upperBound...])
            guard let end = arguments.lastIndex(of: ")") else { continue }
            arguments = String(arguments[..<end]).replacingOccurrences(of: " ", with: "")
            let parts = arguments.components(separatedBy: ",modifiers:")
            let modifiers = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .components(separatedBy: ",").sorted().joined(separator: "+") : ".command"
            seen["\(parts[0])|\(modifiers)", default: 0] += 1
        }
        #expect(seen[".downArrow|.command+.option"] == 1)
        #expect(seen.values.allSatisfy { $0 == 1 }, "a key used twice: \(seen.filter { $0.value > 1 }.keys.sorted())")
    }
}
