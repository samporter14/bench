// PlanUsageChoiceTests.swift — which limit the title bar's usage readout
// shows (Settings → Usage → Title bar shows): the 5-hour limit unless another
// that is low has less left, or whichever is lowest. Made-up limits only.
import Foundation
import Testing
@testable import Bench

private let someday = Date(timeIntervalSince1970: 1_791_986_400) // 2026-10-14 14:00 UTC

/// A limit with `left` percent left.
private func limit(_ kind: PlanLimit.Kind, left: Int) -> PlanLimit {
    PlanLimit(kind: kind, usedPercent: 100 - left, resetsAt: someday.addingTimeInterval(3_600))
}

struct PlanUsageChoiceTests {
    /// What `SettingsKey.register()` hands the app, read from the registered
    /// defaults rather than the stored ones, so a value set on this Mac
    /// can't change the answer.
    @Test func theFiveHourLimitIsTheRegisteredDefault() {
        SettingsKey.register()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered[SettingsKey.titleBarUsage] as? String == TitleBarUsage.fiveHour.rawValue)
        #expect(SettingsKey.titleBarUsage == "titleBarUsage")
    }

    /// The old way showed the week once it had less left than the session,
    /// even with plenty left: now the session stays.
    @Test func theSessionShowsWhileAnotherLimitHasLessLeftButIsNotLow() {
        let limits = [limit(.session, left: 80), limit(.week, left: 30), limit(.weekOpus, left: 25)]
        #expect(PlanUsageModel.tightest(limits)?.kind == .weekOpus)
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .session)
    }

    @Test func aLowLimitWithLessLeftThanTheSessionShowsInstead() {
        let limits = [limit(.session, left: 60), limit(.week, left: 12)]
        let shown = PlanUsageModel.shown(limits, choice: .fiveHour)
        #expect(shown?.kind == .week)
        #expect(shown?.leftPercent == 12)
    }

    @Test func ofSeveralLowLimitsTheOneWithTheLeastLeftShows() {
        let limits = [limit(.session, left: 60), limit(.week, left: 15), limit(.weekOpus, left: 4), limit(.weekSonnet, left: 9)]
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .weekOpus)
    }

    /// Low, but the session has even less: the session is the lowest and
    /// stays, as itself.
    @Test func aLowLimitWithMoreLeftThanTheSessionDoesNotShow() {
        let limits = [limit(.session, left: 5), limit(.week, left: 18)]
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .session)
    }

    /// Whichever way round they are listed: with the same left, the session
    /// has nothing to give way to.
    @Test func aLowLimitWithTheSameLeftAsTheSessionLeavesTheSession() {
        for limits in [[limit(.session, left: 15), limit(.week, left: 15)],
                       [limit(.week, left: 15), limit(.session, left: 15)]] {
            #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .session)
        }
    }

    /// Low is what turns the figure clay: under a fifth left, so 20 is not.
    @Test func lowMeansUnderAFifthLeft() {
        #expect(PlanUsageModel.shown([limit(.session, left: 50), limit(.week, left: 19)], choice: .fiveHour)?.kind == .week)
        #expect(PlanUsageModel.shown([limit(.session, left: 50), limit(.week, left: 20)], choice: .fiveHour)?.kind == .session)
    }

    @Test func withoutASessionLimitTheTightestShows() {
        let limits = [limit(.week, left: 70), limit(.weekSonnet, left: 40), limit(.weekOpus, left: 55)]
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .weekSonnet)
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour) == PlanUsageModel.tightest(limits))
    }

    @Test func whicheverIsLowestIsTheTightest() {
        let sets = [
            [limit(.session, left: 80), limit(.week, left: 30), limit(.weekOpus, left: 25)],
            [limit(.session, left: 60), limit(.week, left: 12)],
            [limit(.session, left: 5), limit(.week, left: 18)],
            [limit(.session, left: 15), limit(.week, left: 15)],
            [limit(.week, left: 70), limit(.weekSonnet, left: 40)],
            [limit(.session, left: 33)],
        ]
        for limits in sets {
            #expect(PlanUsageModel.shown(limits, choice: .lowest) == PlanUsageModel.tightest(limits))
        }
        // And a case where it differs from the 5-hour choice.
        let limits = [limit(.session, left: 80), limit(.week, left: 30)]
        #expect(PlanUsageModel.shown(limits, choice: .lowest)?.kind == .week)
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .session)
    }

    @Test func nothingShowsWithoutLimits() {
        #expect(PlanUsageModel.shown([], choice: .fiveHour) == nil)
        #expect(PlanUsageModel.shown([], choice: .lowest) == nil)
    }

    /// A used-up session (shown as 0% left) is still the 5-hour limit, and
    /// nothing has less left than it.
    @Test func aUsedUpSessionStaysShown() {
        let limits = [limit(.session, left: 0), limit(.week, left: 3)]
        #expect(PlanUsageModel.shown(limits, choice: .fiveHour)?.kind == .session)
    }

    @Test func theSettingNamesItsChoices() {
        #expect(TitleBarUsage.allCases.map(\.title) == ["5-hour limit", "Whichever is lowest"])
        #expect(TitleBarUsage(rawValue: "lowest") == .lowest)
        #expect(TitleBarUsage(rawValue: "no longer a choice") == nil)
    }
}
