// UsagePauseTests.swift — running sessions held by a used-up plan limit:
// which limits can hold a session, how a read of the plan is parsed around
// 100 %, when a session reads as paused (its whole tree quiet, and a recent
// read after its last write), how the watcher moves in and out of a pause
// through its own observing and scheduling, what it says, and what the phone
// is told. Made-up sessions and plans only; no real clock or sleep.
import Combine
import Foundation
import Testing
@testable import Bench

// MARK: Made-up sessions and plans

private let t0 = Date(timeIntervalSince1970: 1_791_986_400) // 2026-10-14 14:00 UTC

/// A running session whose tree last wrote at `wrote` (nil: not measured),
/// its root at `rootWrote`.
private func runningSession(_ id: String, wrote: Date?, rootWrote: Date? = nil) -> SessionStatus {
    SessionStatus(id: id, projectID: "proj_example", projectName: "Example project", title: "Made-up \(id)",
                  state: .running, updatedAt: rootWrote ?? wrote ?? t0.addingTimeInterval(-3_600),
                  startedAt: t0.addingTimeInterval(-600), activeAt: wrote)
}

private func limit(_ kind: PlanLimit.Kind, _ used: Int, reached: Bool = false, resets: Date?) -> PlanLimit {
    PlanLimit(kind: kind, usedPercent: used, resetsAt: resets, reached: reached)
}

private let inAnHour = t0.addingTimeInterval(3_600)
private let fiveHourUsedUp = limit(.session, 100, reached: true, resets: inAnHour)

// MARK: Which limits hold which sessions

struct UsagePauseLimitTests {
    @Test func onlyLimitsThatHoldEverySessionCanPauseOne() {
        #expect(PlanLimit.Kind.session.holdsEverySession)
        #expect(PlanLimit.Kind.week.holdsEverySession)
        #expect(!PlanLimit.Kind.weekOpus.holdsEverySession)
        #expect(!PlanLimit.Kind.weekSonnet.holdsEverySession)
    }

    /// Bench can't tell a session's model, so a used-up Opus week mustn't
    /// pause a session that may be running on Sonnet (or the other way).
    @Test func aUsedUpModelWeekPausesNoSession() {
        let opus = limit(.weekOpus, 100, reached: true, resets: inAnHour)
        let sonnet = limit(.weekSonnet, 100, reached: true, resets: inAnHour)
        let roomy = limit(.session, 40, resets: inAnHour)
        #expect(PlanUsageModel.limitReached([roomy, opus], extra: nil, now: t0) == nil)
        #expect(PlanUsageModel.limitReached([roomy, sonnet], extra: nil, now: t0) == nil)
        let plan = PlanReading(limits: [roomy, opus], lastRead: t0)
        let sessions = [runningSession("opus-maybe", wrote: t0.addingTimeInterval(-60)),
                        runningSession("sonnet-maybe", wrote: t0.addingTimeInterval(-60))]
        let decision = UsagePauseDecision.make(running: sessions, plan: plan, now: t0.addingTimeInterval(1), previous: nil)
        #expect(decision.held.isEmpty)
        #expect(decision.hold == nil)
    }

    @Test func anAccountWideLimitHoldsWhateverTheModelWeeksSay() {
        let opus = limit(.weekOpus, 30, resets: inAnHour)
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp, opus], extra: nil, now: t0)?.kind == .session)
    }

    @Test func aLimitIsUsedUpOnlyWhenAllOfItIsGoneAndItHasNotStartedOver() {
        // Rounded to 100 but still running (99.6 %) doesn't count.
        #expect(PlanUsageModel.limitReached([limit(.session, 100, resets: inAnHour)], extra: nil, now: t0) == nil)
        // Started over already: Claude Science sends again.
        let past = limit(.session, 100, reached: true, resets: t0.addingTimeInterval(-1))
        #expect(PlanUsageModel.limitReached([past], extra: nil, now: t0) == nil)
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp], extra: nil, now: t0)?.kind == .session)
    }

    @Test func withTwoUsedUpThePauseLastsUntilTheLaterReset() {
        let week = limit(.week, 100, reached: true, resets: t0.addingTimeInterval(86_400 * 2))
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp, week], extra: nil, now: t0)?.kind == .week)
    }

    @Test func extraUsageCarriesOnPastALimitUntilItIsUsedUpToo() {
        // On with room, on without a figure (taken as room, as before), used up.
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: 40), now: t0) == nil)
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: nil), now: t0) == nil)
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: 100), now: t0) == nil,
                "rounded to 100 is not used up")
        #expect(PlanUsageModel.limitReached([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: 100, reached: true),
                                            now: t0)?.kind == .session)
    }
}

// MARK: Reading the plan around 100 %

struct UsagePauseParsingTests {
    private func payload(fiveHour: Double?, extra: String = "null", wrapped: Bool = true) -> Data {
        let window = fiveHour.map { #"{"utilization":\#($0),"resets_at":"2026-10-14T15:30:00Z"}"# } ?? "null"
        let body = #"{"five_hour":\#(window),"seven_day":{"utilization":12.0,"resets_at":"2026-10-20T09:00:00.000Z"},"seven_day_opus":null,"seven_day_sonnet":null,"extra_usage":\#(extra)}"#
        return Data((wrapped ? #"{"ok":true,"data":\#(body)}"# : body).utf8)
    }

    private func extra(_ utilization: Double?, enabled: Bool? = true) -> String {
        let on = enabled.map { $0 ? "true" : "false" } ?? "null"
        return #"{"is_enabled":\#(on),"utilization":\#(utilization.map { String($0) } ?? "null")}"#
    }

    /// Rounding is for showing: only the unrounded figure says "used up".
    @Test(arguments: [(99.49, 99, false), (99.5, 100, false), (99.6, 100, false), (99.99, 100, false),
                      (100.0, 100, true), (100.4, 100, true)])
    func aLimitIsUsedUpByItsUnroundedFigure(utilization: Double, shown: Int, reached: Bool) throws {
        let parsed = try PlanUsageModel.parse(payload(fiveHour: utilization))
        let session = try #require(parsed.limits.first { $0.kind == .session })
        #expect(session.usedPercent == shown)
        #expect(session.reached == reached)
        #expect((PlanUsageModel.limitReached(parsed.limits, extra: parsed.extra, now: t0)?.kind == .session) == reached)
    }

    @Test(arguments: [(99.49, 99, false), (99.5, 100, false), (99.6, 100, false), (99.99, 100, false),
                      (100.0, 100, true)])
    func extraUsageIsUsedUpByItsUnroundedFigure(utilization: Double, shown: Int, reached: Bool) throws {
        let parsed = try PlanUsageModel.parse(payload(fiveHour: 100, extra: extra(utilization)))
        let extra = try #require(parsed.extra)
        #expect(extra.usedPercent == shown)
        #expect(extra.reached == reached)
        // A used-up five hours holds sessions only once the extra usage is used up too.
        #expect((PlanUsageModel.limitReached(parsed.limits, extra: parsed.extra, now: t0) != nil) == reached)
    }

    @Test func extraUsageOffOrWithoutAFigure() throws {
        // Off: nothing to carry on with, so a used-up limit holds.
        let off = try PlanUsageModel.parse(payload(fiveHour: 100, extra: extra(10, enabled: false)))
        #expect(off.extra == nil)
        #expect(PlanUsageModel.limitReached(off.limits, extra: off.extra, now: t0)?.kind == .session)
        // Not said whether it is on: read as off, as before.
        let unsaid = try PlanUsageModel.parse(payload(fiveHour: 100, extra: extra(10, enabled: nil)))
        #expect(unsaid.extra == nil)
        // On, with no figure: taken to have room, as before.
        let noFigure = try PlanUsageModel.parse(payload(fiveHour: 100, extra: extra(nil)))
        #expect(noFigure.extra == PlanExtraUsage(usedPercent: nil, reached: false))
        #expect(PlanUsageModel.limitReached(noFigure.limits, extra: noFigure.extra, now: t0) == nil)
        // Missing altogether.
        let missing = try PlanUsageModel.parse(payload(fiveHour: 100))
        #expect(missing.extra == nil)
    }

    @Test func aLimitWithoutAFigureIsLeftOutAndABareObjectReads() throws {
        let parsed = try PlanUsageModel.parse(payload(fiveHour: nil, wrapped: false))
        #expect(parsed.limits.map(\.kind) == [.week])
        #expect(PlanUsageModel.limitReached(parsed.limits, extra: parsed.extra, now: t0) == nil)
    }
}

// MARK: When a session reads as paused

struct UsagePauseDecisionTests {
    private let now = t0
    private var usedUp: PlanReading { PlanReading(limits: [fiveHourUsedUp], lastRead: now.addingTimeInterval(-5)) }

    @Test func aQuietSessionReadAfterItsLastWriteIsHeld() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-25))
        let decision = UsagePauseDecision.make(running: [session], plan: usedUp, now: now, previous: nil)
        #expect(decision.held == ["a": UsagePause(limit: .session, until: inAnHour)])
        #expect(decision.hold?.since == now)
        #expect(decision.wake == UsagePause.recheck)
    }

    @Test func aSessionStillWritingIsNotHeldButIsLookedAtWhenItWouldTurnQuiet() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-5))
        let decision = UsagePauseDecision.make(running: [session], plan: usedUp, now: now, previous: nil)
        #expect(decision.held.isEmpty)
        #expect(decision.wake == UsagePause.quiet - 5 + 1)
        #expect(decision.readIfOlder == nil)
    }

    /// The root has been quiet for minutes while its helper writes: the
    /// root's own time must not make it look paused.
    @Test func aQuietRootWithAHelperStillWritingIsNotHeld() {
        let busy = runningSession("tree", wrote: now.addingTimeInterval(-3), rootWrote: now.addingTimeInterval(-300))
        #expect(UsagePauseDecision.make(running: [busy], plan: usedUp, now: now, previous: nil).held.isEmpty)
        // Once the helper too has been quiet long enough, it is.
        let quiet = runningSession("tree", wrote: now.addingTimeInterval(-30), rootWrote: now.addingTimeInterval(-300))
        let plan = PlanReading(limits: [fiveHourUsedUp], lastRead: now.addingTimeInterval(-1))
        #expect(UsagePauseDecision.make(running: [quiet], plan: plan, now: now, previous: nil).held.keys.sorted() == ["tree"])
    }

    @Test func oneSessionHeldWhileAnotherStillWorks() {
        let held = runningSession("held", wrote: now.addingTimeInterval(-90))
        let busy = runningSession("busy", wrote: now.addingTimeInterval(-4))
        let decision = UsagePauseDecision.make(running: [busy, held], plan: usedUp, now: now, previous: nil)
        #expect(decision.held.keys.sorted() == ["held"])
        #expect(decision.wake == UsagePause.quiet - 4 + 1)
    }

    @Test func aSessionWithoutAMeasuredTreeIsNeverHeld() {
        let unknown = runningSession("unmeasured", wrote: nil, rootWrote: now.addingTimeInterval(-600))
        let decision = UsagePauseDecision.make(running: [unknown], plan: usedUp, now: now, previous: nil)
        #expect(decision.held.isEmpty)
        #expect(decision.wake == nil)
    }

    @Test func aReadFromBeforeTheLastWriteSaysNothingAboutItButAsksForOne() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-25))
        let older = PlanReading(limits: [fiveHourUsedUp], lastRead: now.addingTimeInterval(-40))
        let decision = UsagePauseDecision.make(running: [session], plan: older, now: now, previous: nil)
        #expect(decision.held.isEmpty)
        #expect(decision.readIfOlder == 25, "a read since its last write, now")
    }

    @Test func aReadTooOldSaysNothing() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-400))
        let stale = PlanReading(limits: [fiveHourUsedUp], lastRead: now.addingTimeInterval(-(UsagePause.evidence + 1)))
        let decision = UsagePauseDecision.make(running: [session], plan: stale, now: now, previous: nil)
        #expect(decision.held.isEmpty)
        #expect(decision.hold == nil)
        #expect(decision.readIfOlder == UsagePause.recheck)
    }

    @Test func farFromAnyLimitQuietSessionsDontCostARead() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-60))
        let roomy = PlanReading(limits: [limit(.session, 40, resets: inAnHour), limit(.weekOpus, 99, resets: inAnHour)],
                                lastRead: now.addingTimeInterval(-200))
        #expect(UsagePauseDecision.make(running: [session], plan: roomy, now: now, previous: nil).readIfOlder == nil)
        // Not known at all: worth a read.
        #expect(UsagePauseDecision.make(running: [session], plan: PlanReading(), now: now, previous: nil).readIfOlder
                == UsagePause.recheck)
    }

    @Test func roomByAReadTooSoonAfterThePauseBeganIsNotBelievedYet() {
        let session = runningSession("a", wrote: now.addingTimeInterval(-120))
        let hold = UsageHold(pause: UsagePause(limit: .session, until: inAnHour), since: now.addingTimeInterval(-30))
        let soon = PlanReading(limits: [limit(.session, 99, resets: inAnHour)], lastRead: now.addingTimeInterval(-2))
        #expect(UsagePauseDecision.make(running: [session], plan: soon, now: now, previous: hold).held.keys.sorted() == ["a"])
        let afterSettling = now.addingTimeInterval(UsagePause.settle)
        let later = PlanReading(limits: [limit(.session, 99, resets: inAnHour)], lastRead: afterSettling)
        #expect(UsagePauseDecision.make(running: [session], plan: later, now: afterSettling, previous: hold).held.isEmpty)
    }
}

// MARK: The watcher, moving through its own observing and scheduling

/// A made-up world for the watcher: sessions and a plan the test sets, a
/// clock it moves, and a schedule whose waits run only when it does.
@MainActor
private final class World {
    var now = t0
    var running: [SessionStatus] = []
    var plan = PlanReading()
    /// Each read the watcher asked for: the age it allowed.
    var reads: [TimeInterval] = []
    let changes = PassthroughSubject<Void, Never>()
    private var waits: [(at: Date, id: Int, action: @MainActor () -> Void)] = []
    private var cancelled: Set<Int> = []
    private var next = 0

    lazy var model = UsagePauseModel(now: { [self] in self.now },
                                     schedule: { [self] wait, action in self.schedule(wait, action) })

    func start() {
        model.start(UsagePauseModel.Inputs(changes: changes.eraseToAnyPublisher(),
                                           running: { [self] in self.running },
                                           plan: { [self] in self.plan },
                                           read: { [self] age, _ in self.reads.append(age) }))
    }

    /// When the watcher next looks by itself, from now.
    var nextWake: TimeInterval? {
        waits.filter { !cancelled.contains($0.id) }.map { $0.at.timeIntervalSince(now) }.min()
    }

    private func schedule(_ wait: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        next += 1
        let id = next
        waits.append((now.addingTimeInterval(wait), id, action))
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { _ = self?.cancelled.insert(id) }
        }
    }

    /// Moves the clock on, running each wait that falls due on the way.
    func advance(_ seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let due = waits.filter({ !cancelled.contains($0.id) && $0.at <= end }).min(by: { $0.at < $1.at }) {
            cancelled.insert(due.id)
            now = max(now, due.at)
            due.action()
        }
        now = end
    }

    /// A read of the plan arriving.
    func read(_ limits: [PlanLimit], extra: PlanExtraUsage? = nil) {
        plan = PlanReading(limits: limits, extra: extra, lastRead: now)
        changes.send()
    }

    /// A session writing, somewhere in its tree.
    func write(_ id: String) {
        running = running.map { $0.id == id ? runningSession(id, wrote: now, rootWrote: $0.updatedAt) : $0 }
        changes.send()
    }
}

@MainActor
struct UsagePauseModelTests {
    /// A session working, near its limit, goes quiet; the watcher looks again
    /// when it would turn quiet, asks for a read, and the read says used up.
    private func enterPause(_ world: World) {
        world.running = [runningSession("a", wrote: t0.addingTimeInterval(-5))]
        world.plan = PlanReading(limits: [limit(.session, 97, resets: inAnHour)], lastRead: t0.addingTimeInterval(-10))
        world.start()
        #expect(world.model.held.isEmpty)
        #expect(world.nextWake == 16)
        #expect(world.reads.isEmpty)
        world.advance(16)
        // Quiet now, and near the limit: a read since its last write, please.
        #expect(world.reads == [21])
        #expect(world.model.held.isEmpty, "not on a read from before its last write")
        world.read([fiveHourUsedUp])
        #expect(world.model.pause(for: "a") == UsagePause(limit: .session, until: inAnHour))
        #expect(world.model.holdsAll(world.running))
        #expect(world.nextWake == UsagePause.recheck)
    }

    @Test func entersAPauseOnceQuietAndAReadSaysUsedUp() {
        enterPause(World())
    }

    @Test func aWriteAnywhereInTheSessionEndsItsPause() {
        let world = World()
        enterPause(world)
        world.advance(30)
        world.write("a")
        #expect(world.model.held.isEmpty)
        #expect(world.nextWake == UsagePause.quiet + 1)
        // Quiet again: it needs a read from after that write before it reads as paused again.
        world.advance(21)
        #expect(world.model.held.isEmpty)
        #expect(world.reads.last == 21)
        world.read([fiveHourUsedUp])
        #expect(world.model.held.keys.sorted() == ["a"])
    }

    @Test func theLimitStartingOverEndsThePauseEvenWithoutARead() {
        let world = World()
        enterPause(world)
        let soon = world.now.addingTimeInterval(40)
        world.read([limit(.session, 100, reached: true, resets: soon)])
        #expect(world.model.held.keys.sorted() == ["a"])
        #expect(world.nextWake == 41, "just after it starts over, before the minute's recheck")
        world.advance(41)
        #expect(world.model.held.isEmpty)
    }

    @Test func extraUsageSwitchedOnEndsThePauseOnceAReadCanBeBelieved() {
        let world = World()
        enterPause(world)
        world.advance(30)
        world.read([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: 0))
        #expect(world.model.held.keys.sorted() == ["a"], "too soon after the pause began to believe it")
        world.advance(50)
        world.read([fiveHourUsedUp], extra: PlanExtraUsage(usedPercent: 0))
        #expect(world.model.held.isEmpty)
    }

    @Test func failedReadsKeepThePauseForAWhileThenStopClaimingIt() {
        let world = World()
        enterPause(world)
        let lastGood = world.now
        // Each minute's look asks for a read; none comes back (the plan stays as it was).
        world.advance(UsagePause.recheck)
        #expect(world.reads.last == UsagePause.recheck)
        #expect(world.model.held.keys.sorted() == ["a"])
        world.advance(UsagePause.recheck)
        #expect(world.model.held.keys.sorted() == ["a"])
        // The next look comes after the last good read is too old to go on.
        world.advance(UsagePause.recheck)
        #expect(world.now.timeIntervalSince(lastGood) > UsagePause.evidence)
        #expect(world.model.held.isEmpty, "a read that old can't say it is still paused")
        #expect(world.reads.count >= 4, "and it keeps asking")
    }

    @Test func aSecondSessionStillWorkingIsNotHeldAndTheMenuBarKeepsGoing() {
        let world = World()
        enterPause(world)
        world.running.append(runningSession("b", wrote: world.now))
        world.changes.send()
        #expect(world.model.held.keys.sorted() == ["a"])
        #expect(!world.model.holdsAll(world.running))
        #expect(world.model.head(of: world.running)?.id == "b")
    }

    @Test func nothingRunningIsNothingHeldAndNothingScheduled() {
        let world = World()
        enterPause(world)
        world.running = []
        world.changes.send()
        #expect(world.model.held.isEmpty)
        #expect(world.nextWake == nil)
    }
}

// MARK: What it says

struct UsagePauseSentenceTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private let english = Locale(identifier: "en_US")

    @Test func itSaysWhenItResumesInTheCalendarsTimeZone() {
        let detroit = calendar("America/Detroit")
        let noon = detroit.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        func at(_ hours: Double) -> String {
            UsagePause(limit: .session, until: noon.addingTimeInterval(hours * 3_600)).sentence(now: noon, calendar: detroit, locale: english)
        }
        #expect(at(3).hasPrefix("Resumes at 3:00"))
        #expect(at(20).hasPrefix("Resumes tomorrow at 8:00"))
        #expect(at(50).hasPrefix("Resumes Friday at 2:00"))
        #expect(at(24 * 8).hasPrefix("Resumes on Oct 22 at 12:00"))
        #expect(at(-1) == "Resumes shortly")
        #expect(UsagePause(limit: .session, until: nil).sentence(now: noon) == "Resumes when your limit resets")
    }

    /// The same moment is the same day in Detroit and the next in Tokyo.
    @Test func theDayIsTheCalendarsOwn() {
        let until = Date(timeIntervalSince1970: 1_792_026_000) // 01:00 UTC the next day
        let pause = UsagePause(limit: .session, until: until)
        #expect(pause.sentence(now: t0, calendar: calendar("America/Detroit"), locale: english).hasPrefix("Resumes at 9:00"))
        #expect(pause.sentence(now: t0, calendar: calendar("Asia/Tokyo"), locale: english).hasPrefix("Resumes tomorrow at 10:00"))
    }
}

// MARK: What the phone is told

@MainActor
struct UsagePausePhoneStateTests {
    private func state(working: [SessionStatus], held: [String: UsagePause]) -> RemoteAPI.State {
        RemoteAPI.state(RemoteAPI.Input(bench: "0.5.3", now: t0, problem: nil, waiting: [], snoozed: [], failed: [],
                                        working: working, recent: [], limits: [], forecasts: [:], held: held))
    }

    @Test func eachWorkingSessionSaysWhetherItIsHeld() throws {
        let a = runningSession("00000000-0000-4000-8000-0000000000aa", wrote: t0)
        let b = runningSession("00000000-0000-4000-8000-0000000000bb", wrote: t0)
        let pause = UsagePause(limit: .session, until: inAnHour)
        let mixed = state(working: [a, b], held: [a.id: pause])
        #expect(mixed.working.map(\.paused) == [true, false])
        #expect(mixed.pause?.limit == "5-hour")
        #expect(mixed.pause?.until == inAnHour)
        let json = try #require(String(data: RemoteAPI.encode(mixed), encoding: .utf8))
        #expect(json.contains(#""paused":true"#) && json.contains(#""paused":false"#))
        #expect(json.contains(#""pause":{"limit":"5-hour","sentence":"#))
        #expect(json.contains(#""until":"2026-10-14T15:00:00Z""#))
    }

    @Test func noneHeldIsNoPauseAndNothingRunningHoldsNothing() throws {
        let a = runningSession("00000000-0000-4000-8000-0000000000aa", wrote: t0)
        #expect(state(working: [a], held: [:]).pause == nil)
        // A pause for a session no longer working says nothing.
        let gone = state(working: [], held: [a.id: UsagePause(limit: .session, until: inAnHour)])
        #expect(gone.pause == nil)
        let off = try #require(String(data: RemoteAPI.encode(gone), encoding: .utf8))
        #expect(off.contains(#""pause":null"#))
    }
}
