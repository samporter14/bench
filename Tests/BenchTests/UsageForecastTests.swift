// UsageForecastTests.swift — when a plan limit is forecast to run out, the
// reads it is forecast from, and the heads-up card for it. Made-up reads and
// limits only.
import Foundation
import Testing
@testable import Bench

/// The clock the tests share: a multiple of five minutes, so a time that
/// rounds to five minutes is also a whole number of minutes from it.
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

/// Reads of `percents`, oldest first, `step` minutes apart, the last one at
/// `end` minutes from now.
private func reads(_ percents: [Int], step: Double = 5, end: Double = 0) -> [UsageSample] {
    percents.enumerated().map { index, percent in
        UsageSample(time: at(end - Double(percents.count - 1 - index) * step), usedPercent: percent)
    }
}

struct UsageForecastTests {
    @Test func tooEarlyWithFewerThanThreeReads() {
        #expect(UsageForecast.estimate(samples: [], resetsAt: at(300), now: now) == .tooEarly)
        #expect(UsageForecast.estimate(samples: reads([40, 50], step: 20), resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func tooEarlyInTheFirstFifteenMinutes() {
        // Four reads and ten points, but only ten minutes of them.
        let samples = reads([40, 43, 46, 50], step: 10.0 / 3)
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func tooEarlyUnderThreePointsOfChange() {
        let samples = reads([40, 40, 41, 41, 41, 42, 42, 42, 42, 42])
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func aSteadyClimbNamesTheTimeItReachesTheLimit() {
        // A point every five minutes, from 10% to 19%: 81 more points to go
        // at 0.2 a minute is 405 minutes.
        let samples = reads(Array(10...19))
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(480), now: now) == .limitAround(at(405)))
    }

    @Test func aFlatLineIsTooEarlyRatherThanLasting() {
        // Deliberate: under three points of change says nothing, even when the
        // line is perfectly flat. "Lasts until it resets" needs a climb.
        let samples = reads(Array(repeating: 40, count: 10))
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func aResetInsideTheReadsIsIgnored() {
        // Five reads climbing to 92%, then the window starts over: only the
        // reads since count, climbing 0.4 a minute from 0% to 8%.
        let samples = reads([80, 83, 86, 89, 92, 0, 2, 4, 6, 8])
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .limitAround(at(230)))
    }

    @Test func justAfterAResetThereIsNothingToGoOn() {
        let samples = reads([70, 80, 90, 2], step: 15)
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func readsOlderThanFortyFiveMinutesDontCount() {
        // A fast climb an hour ago, then 45 quiet minutes: the pace is the
        // last 45 minutes', which is flat.
        let old = reads([10, 30, 50], step: 5, end: -60)
        let quiet = reads([50, 50, 50, 50, 50, 50, 50, 50, 50, 50])
        #expect(UsageForecast.estimate(samples: old + quiet, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func lastsUntilTheResetWhenThePaceFallsShort() {
        let samples = reads(Array(10...19)) // reaches 100% at 405 minutes
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .lastsUntilReset)
        // The limit and the reset at the same time: the reset wins.
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(405), now: now) == .lastsUntilReset)
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(410), now: now) == .limitAround(at(405)))
    }

    @Test func theTimeIsRoundedToFiveMinutes() {
        // The same climb, its reads a minute and then four minutes off the
        // five-minute marks: 406 minutes rounds down, 409 rounds up.
        for (offset, expected) in [(1.0, 405.0), (4.0, 410.0)] {
            let samples = reads(Array(10...19), end: offset)
            let forecast = UsageForecast.estimate(samples: samples, resetsAt: at(600), now: at(offset))
            #expect(forecast == .limitAround(at(expected)))
        }
    }

    @Test func aLimitAboutToRunOutIsNamedNowNotInThePast() {
        // The fitted line crosses 100% before the last read, which says 99%.
        let samples = reads([70, 80, 90, 99, 99], step: 10)
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .limitAround(at(0)))
    }

    @Test func aLimitAlreadyUsedUpHasNothingToForecast() {
        let samples = reads([90, 93, 95, 97, 99, 100, 100, 100, 100, 100])
        #expect(UsageForecast.estimate(samples: samples, resetsAt: at(300), now: now) == .tooEarly)
    }

    @Test func wholePercentsDontThrowTheTimeAround() {
        // The true line is 20% to 20% + 45 minutes' climb, read as whole
        // percents every five minutes, from every phase of the rounding.
        for perMinute in [0.15, 0.25, 0.4, 0.6] {
            for phase in stride(from: 0.0, to: 1.0, by: 0.1) {
                let percents = (0...9).map { Int((20 + phase + perMinute * Double($0) * 5).rounded()) }
                let toGo = (100 - 20 - phase - perMinute * 45) / perMinute // minutes after the last read
                let forecast = UsageForecast.estimate(samples: reads(percents), resetsAt: at(24 * 60), now: now)
                guard case .limitAround(let time) = forecast else {
                    Issue.record("no time at \(perMinute) a minute, phase \(phase): \(forecast)")
                    continue
                }
                let estimated = time.timeIntervalSince(now) / 60
                #expect(abs(estimated - toGo) <= max(5, toGo * 0.08),
                        "\(perMinute) a minute, phase \(phase): \(estimated) against \(toGo)")
            }
        }
    }

    @Test func oneReadSwingingByAPointMovesTheTimeLittle() {
        let steady = UsageForecast.estimate(samples: reads(Array(10...19)), resetsAt: at(600), now: now)
        let bumped = UsageForecast.estimate(samples: reads(Array(10...18) + [20]), resetsAt: at(600), now: now)
        guard case .limitAround(let a) = steady, case .limitAround(let b) = bumped else {
            Issue.record("expected times")
            return
        }
        #expect(abs(b.timeIntervalSince(a)) <= 30 * 60)
    }

    @Test func theLineAndTheClock() {
        #expect(Forecast.tooEarly.line(now: now) == nil)
        #expect(Forecast.lastsUntilReset.line(now: now) == "At this pace: lasts until it resets")
        let tenAM = Calendar.current.startOfDay(for: now).addingTimeInterval(10 * 3600)
        let sameDay = tenAM.addingTimeInterval(3600)
        #expect(UsageForecast.clock(sameDay, now: tenAM) == sameDay.formatted(.dateTime.hour().minute()))
        #expect(Forecast.limitAround(sameDay).line(now: tenAM)
                == "At this pace: limit around " + sameDay.formatted(.dateTime.hour().minute()))
        // Another day names the day.
        let later = tenAM.addingTimeInterval(3 * 24 * 3600)
        #expect(UsageForecast.clock(later, now: tenAM).contains(later.formatted(.dateTime.weekday(.abbreviated))))
    }
}

struct UsageSamplesTests {
    @Test func aWindowStartingOverEmptiesTheReads() {
        var samples = UsageSamples()
        samples.record(usedPercent: 50, resetsAt: at(60), at: at(-10))
        samples.record(usedPercent: 52, resetsAt: at(60), at: at(-5))
        #expect(samples.points.count == 2)
        samples.record(usedPercent: 1, resetsAt: at(60 + 300), at: at(0))
        #expect(samples.points == [UsageSample(time: at(0), usedPercent: 1)])
    }

    @Test func aResetTimeWobblingBySecondsIsTheSameWindow() {
        var samples = UsageSamples()
        for (minute, wobble) in [(-10.0, 0.0), (-5, 8), (0, -11)] {
            samples.record(usedPercent: 50, resetsAt: at(60).addingTimeInterval(wobble), at: at(minute))
        }
        #expect(samples.points.count == 3)
    }

    @Test func aReadWithNoResetTimeClearsTheRest() {
        var samples = UsageSamples()
        samples.record(usedPercent: 50, resetsAt: at(60), at: at(-5))
        samples.record(usedPercent: 51, resetsAt: nil, at: at(0))
        #expect(samples.points.isEmpty)
    }

    @Test func oldReadsAreForgotten() {
        var samples = UsageSamples()
        // A week's window read every five minutes keeps only the last 90.
        for step in 0..<(12 * 24) {
            samples.record(usedPercent: step / 20, resetsAt: at(7 * 24 * 60), at: at(Double(step) * 5))
        }
        #expect(samples.points.count == 19)
        #expect(samples.points.first.map { $0.time >= at(Double(12 * 24 - 1) * 5 - 90) } == true)
    }
}

struct ForecastNoticeTests {
    private func limit(_ kind: PlanLimit.Kind = .session, used: Int, resetsIn minutes: Double) -> PlanLimit {
        PlanLimit(kind: kind, usedPercent: used, resetsAt: at(minutes))
    }

    @Test func aLimitRunningOutSoonGetsACard() {
        let session = limit(used: 70, resetsIn: 120)
        let result = NoticeRules.forecast(
            limits: [session], forecasts: [.session: .limitAround(at(30))], announced: [:], now: now)
        #expect(result.notices.count == 1)
        #expect(result.notices.first?.title
                == "At this pace your 5-hour limit runs out around \(UsageForecast.clock(at(30), now: now))")
        #expect(result.notices.first?.detail.hasPrefix("30% left · Resets ") == true)
        #expect(result.announced.count == 1)
    }

    @Test func theWeeklyLimitIsNamedAsTheWeekly() {
        let week = limit(.week, used: 80, resetsIn: 3 * 24 * 60)
        let result = NoticeRules.forecast(
            limits: [week], forecasts: [.week: .limitAround(at(20))], announced: [:], now: now)
        #expect(result.notices.first?.title.hasPrefix("At this pace your weekly limit runs out around ") == true)
    }

    @Test func onceInAWindowNotOnceAnHour() {
        let forecasts: [PlanLimit.Kind: Forecast] = [.session: .limitAround(at(30))]
        let first = NoticeRules.forecast(limits: [limit(used: 70, resetsIn: 120)], forecasts: forecasts, announced: [:], now: now)
        #expect(first.notices.count == 1)
        // The next read, a few seconds off the reset time and further on: the same window.
        let wobble = PlanLimit(kind: .session, usedPercent: 74, resetsAt: at(120).addingTimeInterval(8))
        let later = NoticeRules.forecast(limits: [wobble], forecasts: [.session: .limitAround(at(32))],
                                         announced: first.announced, now: at(5))
        #expect(later.notices.isEmpty)
        #expect(later.announced == first.announced)
        // The next window gets its own.
        let nextNow = at(121)
        let next = NoticeRules.forecast(limits: [limit(used: 70, resetsIn: 421)],
                                        forecasts: [.session: .limitAround(nextNow.addingTimeInterval(30 * 60))],
                                        announced: first.announced, now: nextNow)
        #expect(next.notices.count == 1)
        // The ended window is forgotten.
        #expect(next.announced.count == 1)
    }

    @Test func quietWhenFarOffAlreadyNearTheLimitOrNothingIsSaid() {
        func notices(_ used: Int, _ forecast: Forecast?, kind: PlanLimit.Kind = .session) -> [LabNotice] {
            NoticeRules.forecast(
                limits: [limit(kind, used: used, resetsIn: 200)],
                forecasts: forecast.map { [kind: $0] } ?? [:], announced: [:], now: now).notices
        }
        #expect(notices(60, .limitAround(at(50))).isEmpty) // not under 45 minutes
        #expect(notices(60, .limitAround(at(44.9))).count == 1)
        #expect(notices(90, .limitAround(at(20))).isEmpty) // the 90% card's
        #expect(notices(89, .limitAround(at(20))).count == 1)
        #expect(notices(60, .lastsUntilReset).isEmpty)
        #expect(notices(60, .tooEarly).isEmpty)
        #expect(notices(60, nil).isEmpty)
        #expect(notices(60, .limitAround(at(20)), kind: .weekOpus).isEmpty)
    }

    @Test func theNinetyPercentCardStillComesAfterwards() {
        let early = NoticeRules.forecast(
            limits: [limit(used: 70, resetsIn: 120)], forecasts: [.session: .limitAround(at(30))], announced: [:], now: now)
        #expect(early.notices.count == 1)
        let near = NoticeRules.plan(limits: [limit(used: 91, resetsIn: 90)], announced: [:], now: at(30))
        #expect(near.notices.count == 1)
    }
}
