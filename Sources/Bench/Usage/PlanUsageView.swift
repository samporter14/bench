// PlanUsageView.swift — what the plan's limits look like: the toolbar's
// "5h 66% left" with its thin bar, and the popover's Plan limits section
// (DESIGN.md, Title-bar readouts).
import SwiftUI

/// The Usage button's label once the plan has been read: the tightest limit
/// as what is left, secondary until under a fifth is, then clay.
struct PlanUsageLabel: View {
    let limit: PlanLimit

    var body: some View {
        let colour = limit.isLow ? Theme.clay : Color.secondary
        VStack(spacing: 3) {
            Text("\(limit.kind.shortTitle) \(limit.leftPercent)% left")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            // The bar drains as the limit is used up, like a battery.
            PlanMeter(
                fraction: Double(limit.leftPercent) / 100,
                fill: colour,
                track: Color.primary.opacity(0.15))
                .frame(height: 3)
                .accessibilityHidden(true)
        }
        // The bar has no width of its own, so without this it would take all
        // the toolbar offers. Fixed, it is as wide as the text above it.
        .fixedSize()
        .foregroundStyle(colour)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usage. \(limit.kind.title): \(limit.leftPercent)% left")
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
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else { return "Resets now" }
    guard seconds < 24 * 3600 else {
        return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
    let (hours, minutes) = Int((seconds / 60).rounded(.up)).quotientAndRemainder(dividingBy: 60)
    return hours > 0 ? "Resets in \(hours) h \(minutes) m" : "Resets in \(minutes) m"
}
