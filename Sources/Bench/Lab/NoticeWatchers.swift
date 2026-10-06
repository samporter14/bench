// NoticeWatchers.swift — what posts notices (DESIGN.md, Notices): the plan
// nearly used up, on course to run out, or reset, the shown session's context
// filling up, and the week in review. Each watches a model Bench already has;
// none reads on its own schedule except the weekly check, once a day. What
// has been announced is kept in Bench's settings so an update doesn't
// announce it again; demos keep nothing.
import Combine
import Foundation

@MainActor
final class NoticeWatchers {
    static let shared = NoticeWatchers()

    private var subscriptions: Set<AnyCancellable> = []
    private var weekly: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private enum Key {
        static let planWindows = "noticePlanWindows"
        static let forecastWindows = "noticeForecastWindows"
        static let contextFrames = "noticeContextFrames"
        static let reviewedWeek = "noticeReviewedWeek"
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        PlanUsageModel.shared.$limits
            .receive(on: DispatchQueue.main)
            .sink { [weak self] limits in self?.planChanged(limits) }
            .store(in: &subscriptions)
        let context = ContextModel.shared
        Publishers.CombineLatest3(context.$frameID, context.$used, context.$window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.contextChanged() }
            .store(in: &subscriptions)
        weekly = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reviewWeek()
                // Once a day, just after midnight.
                let calendar = Calendar.current
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
                try? await Task.sleep(for: .seconds(tomorrow.timeIntervalSinceNow + 60), tolerance: .seconds(300))
            }
        }
    }

    private var enabled: Bool { defaults.bool(forKey: SettingsKey.headsUpNotices) }

    // MARK: Plan

    private func planChanged(_ limits: [PlanLimit]) {
        guard !limits.isEmpty else { return }
        let stored = (defaults.dictionary(forKey: Key.planWindows) as? [String: Double]) ?? [:]
        let announced = stored.mapValues { Date(timeIntervalSince1970: $0) }
        let (notices, kept) = NoticeRules.plan(limits: limits, announced: announced, now: Date())
        if Demo.mode == nil {
            defaults.set(kept.mapValues(\.timeIntervalSince1970), forKey: Key.planWindows)
        }
        if enabled { notices.forEach(LabModel.shared.post) }
        forecastChanged(limits)
    }

    /// The pace card. A demo's made-up limits have no forecast, and never
    /// get one here.
    private func forecastChanged(_ limits: [PlanLimit]) {
        guard Demo.mode == nil else { return }
        let stored = (defaults.dictionary(forKey: Key.forecastWindows) as? [String: Double]) ?? [:]
        let announced = stored.mapValues { Date(timeIntervalSince1970: $0) }
        let (notices, kept) = NoticeRules.forecast(
            limits: limits, forecasts: PlanUsageModel.shared.forecasts, announced: announced, now: Date())
        defaults.set(kept.mapValues(\.timeIntervalSince1970), forKey: Key.forecastWindows)
        if enabled { notices.forEach(LabModel.shared.post) }
    }

    // MARK: Context

    private func contextChanged() {
        let model = ContextModel.shared
        guard let frame = model.frameID, let percent = model.figures?.percent else { return }
        let announced = Set(defaults.stringArray(forKey: Key.contextFrames) ?? [])
        let lab = LabModel.shared
        let title = (lab.working + lab.waiting + lab.latest + lab.recent.compactMap(\.session))
            .first { $0.id == frame }?.displayTitle
        guard let notice = NoticeRules.context(frameID: frame, percent: percent, title: title, announced: announced) else { return }
        if Demo.mode == nil {
            // The last few dozen sessions are plenty to never say it twice.
            defaults.set(Array(([frame] + announced.filter { $0 != frame }).prefix(40)), forKey: Key.contextFrames)
        }
        if enabled { LabModel.shared.post(notice) }
    }

    // MARK: Week in review

    private func reviewWeek() async {
        guard Demo.mode == nil, defaults.bool(forKey: SettingsKey.weekInReview) else { return }
        let source = CombinedScienceSource()
        // A second or more of SQLite: off the main thread.
        let history = await Task.detached(priority: .utility) { try? source.activityHistory(days: 16) }.value
        guard let history, let week = NoticeRules.lastWeek(history, today: Date()),
              defaults.string(forKey: Key.reviewedWeek) != week.key else { return }
        defaults.set(week.key, forKey: Key.reviewedWeek)
        LabModel.shared.post(NoticeRules.weekNotice(week))
    }
}
