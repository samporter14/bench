// UsageView.swift — the toolbar's Usage button and the popover it opens
// (DESIGN.md, Usage and Title-bar readouts): the plan's limits, then the
// activity: three stat tiles on glass, a Sessions / Messages / Tokens switch,
// and the year graph.
import SwiftUI

/// The toolbar's Usage button, the right half of TitleBarReadouts' capsule.
/// Its label is what is left of the plan's
/// tightest limit once that has been read. Opening its popover reads the
/// plan and the activity if the last read is old, and keeps the activity
/// fresh while the popover stays open.
struct UsageToolbarButton: View {
    @State private var showing = false
    @ObservedObject private var plan = PlanUsageModel.shared

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            if let tightest = plan.tightest {
                PlanUsageLabel(limit: tightest)
            } else {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Usage")
            }
        }
        .buttonStyle(ReadoutButtonStyle())
        .help("Plan usage and activity")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            UsageView()
        }
        // The label needs the plan read from launch, not from the first open.
        .task { plan.start() }
        // The binding also flips when a click outside dismisses the popover,
        // which a button action would not see.
        .onChange(of: showing) { _, open in
            let activity = UsageModel.shared
            if open {
                // Also here, in case the toolbar never ran the task above.
                plan.start()
                plan.refreshIfStale()
                activity.refreshIfStale()
                activity.startLiveUpdates()
            } else {
                activity.stopLiveUpdates()
            }
        }
    }
}

/// What the popover holds: the plan's limits, then the activity. The
/// activity is a spinner for the first read, a sentence and "Try again" if it
/// fails, and otherwise the headline, the switch and the graph.
struct UsageView: View {
    @ObservedObject private var model = UsageModel.shared
    /// Remembered between openings; the popover's view is made afresh each time.
    @AppStorage("usageMetric") private var chosen: ActivityMetric = .sessions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // One Refresh for everything on show: fresh plan numbers, and the
            // activity read again.
            PlanLimitsSection {
                PlanUsageModel.shared.refresh()
                model.refresh()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Activity")
                    .font(.system(size: 13, weight: .semibold))
                activity
            }
        }
        .padding(20)
        .frame(width: 780)
    }

    @ViewBuilder private var activity: some View {
        if let history = model.history {
            loaded(history)
        } else if let failure = model.failure {
            VStack(spacing: 12) {
                Text(failure)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { model.refresh() }
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ProgressView("Reading your activity…")
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func loaded(_ history: ActivityHistory) -> some View {
        // Sessions always read; messages and tokens come from message records
        // a Claude Science update may reshape, so a nil one leaves the switch.
        let metrics = ActivityMetric.allCases.filter { history[$0] != nil }
        let metric = metrics.contains(chosen) ? chosen : .sessions
        return VStack(alignment: .leading, spacing: 16) {
            Headline(history: history)
            if metrics.count > 1 {
                Picker("Show", selection: Binding(get: { metric }, set: { chosen = $0 })) {
                    ForEach(metrics, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ActivityGraph(history: history, metric: metric)
        }
        .animation(reduceMotion ? nil : Theme.spring, value: metric)
    }
}

/// Today, this week and the streak, on glass tiles that share one container
/// so their shapes blend.
private struct Headline: View {
    let history: ActivityHistory

    var body: some View {
        let today = Date()
        let sessionsToday = ActivityMetric.sessions.describe(history.sessions.count(on: today))
        // The same week as the graph's last column.
        let thisWeek = ActivityGrid(counts: history.sessions, today: today, weeks: 1).thisWeek
        let streak = history.sessions.streaks(through: today)

        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let tokens = history.tokens {
                    StatTile(
                        label: "Today",
                        value: ActivityMetric.tokens.describe(tokens.count(on: today)),
                        detail: sessionsToday)
                } else {
                    StatTile(label: "Today", value: sessionsToday, detail: nil)
                }
                StatTile(label: "This week", value: ActivityMetric.sessions.describe(thisWeek), detail: nil)
                StatTile(
                    label: "Streak",
                    value: streak.current == 1 ? "1 day" : "\(streak.current) days",
                    detail: streak.longest > 0 ? "longest \(streak.longest)" : nil)
            }
            // Tiles with and without a detail line come out the same height.
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
