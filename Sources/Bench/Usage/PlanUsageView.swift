// PlanUsageView.swift — what the plan's limits look like: the toolbar's
// meter and "66% left · resets in 1h 12m", and the popover's Plan limits
// section (DESIGN.md, Title-bar readouts).
import SwiftUI

/// The Usage button's label once the plan has been read: a small meter,
/// then the tightest limit as what is left and when it starts over, on one
/// line so it sits level with the context ring beside it. The figure is
/// secondary until under a fifth is left, then clay. The session limit goes
/// unnamed: "5h" read as five hours to go, whatever the clock said.
struct PlanUsageLabel: View {
    let limit: PlanLimit

    var body: some View {
        // The countdown moves, so the label is redrawn each minute.
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                // Drains as the limit is used up, like a battery.
                PlanMeter(
                    fraction: Double(limit.leftPercent) / 100,
                    fill: Theme.clay,
                    track: Color.primary.opacity(0.15))
                    .frame(width: 22, height: 5)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    Text(name + "\(limit.leftPercent)% left")
                        .foregroundStyle(limit.isLow ? Theme.clay : Color.secondary)
                    if let resetsAt = limit.resetsAt {
                        Text(" · resets " + resetPhrase(resetsAt, now: context.date, compact: true))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(now: context.date))
        }
    }

    /// "Week ", "Opus week " and so on; nothing for the session.
    private var name: String {
        limit.kind == .session ? "" : limit.kind.shortTitle + " "
    }

    private func spoken(now: Date) -> String {
        var text = "Usage. \(limit.kind.title): \(limit.leftPercent)% left"
        if let resetsAt = limit.resetsAt {
            text += ". " + resets(resetsAt, now: now)
        }
        return text
    }
}

/// A thin capsule bar, filled from the left.
private struct PlanMeter: View {
    /// 0 through 1.
    let fraction: Double
    let fill: Color
    let track: Color

    var body: some View {
        Capsule()
            .fill(track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * fraction)
                }
            }
    }
}

/// The popover's plan limits: a row for each, on one glass card, with the
/// Refresh button above it. Its numbers stay when a read fails, dimmed, with
/// a line saying so.
struct PlanLimitsSection: View {
    @ObservedObject private var plan = PlanUsageModel.shared
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan limits")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button("Refresh", action: onRefresh)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(plan.loading)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    @ViewBuilder private var content: some View {
        if plan.limits.isEmpty && plan.extra == nil {
            if let failure = plan.failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else if plan.lastRead != nil {
                Text("Claude Science reports no plan limits.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Reading plan usage…")
                    .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // A row's "resets in" counts down, so the card is redrawn each
                // minute while the popover is open.
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.limits) { limit in
                            PlanLimitRow(
                                title: limit.kind.title,
                                usedPercent: limit.usedPercent,
                                detail: limit.resetsAt.map { resets($0, now: context.date) })
                        }
                        if let extra = plan.extra {
                            PlanLimitRow(title: "Extra usage", usedPercent: extra.usedPercent, detail: nil)
                        }
                    }
                }
                .opacity(plan.failure == nil ? 1 : 0.5)
                if let failure = plan.failure, let lastRead = plan.lastRead {
                    Text("\(failure). Showing the last read, from \(lastRead.formatted(date: .omitted, time: .shortened)).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Name, bar (clay for what is used), what is left, and when it starts over.
private struct PlanLimitRow: View {
    let title: String
    /// Nil when Claude Science gives no percent: extra usage can be on without one.
    let usedPercent: Int?
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 160, alignment: .leading)
            if let usedPercent {
                PlanMeter(
                    fraction: Double(usedPercent) / 100,
                    fill: Theme.clay,
                    track: Color.primary.opacity(0.12))
                    .frame(height: 6)
                    .accessibilityHidden(true)
                Text("\(100 - usedPercent)% left")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            } else {
                Text("On")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(detail ?? "")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Resets in 2 h 14 m", or the day and time once it is over a day away.
private func resets(_ date: Date, now: Date) -> String {
    "Resets " + resetPhrase(date, now: now, compact: false)
}

/// "in 2 h 14 m", "now", or "Thu 9:00 AM" past a day. Compact, for the
/// toolbar: "in 2h 14m", or just the day.
private func resetPhrase(_ date: Date, now: Date, compact: Bool) -> String {
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else { return "now" }
    guard seconds < 24 * 3600 else {
        return compact
            ? date.formatted(.dateTime.weekday(.abbreviated))
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
    let (hours, minutes) = Int((seconds / 60).rounded(.up)).quotientAndRemainder(dividingBy: 60)
    let space = compact ? "" : " "
    return hours > 0
        ? "in \(hours)\(space)h \(minutes)\(space)m"
        : "in \(minutes)\(space)m"
}
