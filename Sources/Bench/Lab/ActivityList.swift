// ActivityList.swift — every session at once (DESIGN.md, Activity list): what
// needs you, what works and what happened lately, each a row that opens its
// session. The toolbar capsule shows it in a popover and the Dock icon's menu
// lists the same; both read LabModel, so nothing else polls.
import AppKit
import SwiftUI

struct ActivityList: View {
    let close: () -> Void
    @ObservedObject private var model = LabModel.shared
    @Environment(\.colorScheme) private var colorScheme

    private var failed: [SessionStatus] {
        model.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let problem = model.problem {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not updating: \(problem.label)")
                            if let since = model.staleSince {
                                Text("Last checked at \(since.formatted(date: .omitted, time: .shortened))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }
                if !model.waiting.isEmpty || !failed.isEmpty {
                    section("Needs you") {
                        ForEach(model.waiting) { session in
                            if let snoozed = model.snoozed.first(where: { $0.id == session.id }) {
                                snoozedRow(snoozed)
                            } else {
                                row(session, line: (session.waitingReason ?? .other).sentence, accent: true) {
                                    PlayedLoop(glyph: (session.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
                                }
                            }
                        }
                        ForEach(failed) { session in
                            row(session, line: "Stopped with an error", accent: true) {
                                symbol("exclamationmark.triangle")
                            }
                        }
                    }
                }
                if !model.working.isEmpty {
                    section("Working") {
                        ForEach(model.working) { session in
                            row(session, line: nil, accent: false) {
                                WorkingGlyph(tint: colorScheme.sceneInk, rotation: SceneSettings.shared.rotation)
                            } trailing: {
                                if let since = session.startedAt {
                                    TimelineView(.periodic(from: since, by: 1)) { context in
                                        Text(ElapsedClock.format(context.date.timeIntervalSince(since)))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !model.recent.isEmpty {
                    section("Recent") {
                        ForEach(model.recent) { event in
                            recentRow(event)
                        }
                    }
                }
                // Until something happens while Bench is open, the sessions
                // active last, as the Dock menu lists them.
                if model.recent.isEmpty, !model.latest.isEmpty {
                    section("Latest") {
                        ForEach(model.latest) { session in
                            row(session, line: nil, accent: false) {
                                symbol("clock")
                            }
                        }
                    }
                }
                if model.waiting.isEmpty, failed.isEmpty, model.working.isEmpty, model.recent.isEmpty, model.latest.isEmpty,
                   model.problem == nil {
                    Text("Nothing yet. Sessions show up here while they work, and what they did stays under Recent.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .frame(width: 360)
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Parts

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            content()
        }
    }

    private func row<Glyph: View>(_ session: SessionStatus, line: String?, accent: Bool,
                                  @ViewBuilder glyph: () -> Glyph) -> some View {
        row(session, line: line, accent: accent, glyph: glyph) { EmptyView() }
    }

    private func row<Glyph: View, Trailing: View>(_ session: SessionStatus, line: String?, accent: Bool,
                                                  @ViewBuilder glyph: () -> Glyph,
                                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        ActivityRow(action: {
            model.open(session)
            close()
        }) {
            HStack(spacing: 10) {
                glyph()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    if let line {
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent ? AnyShapeStyle(Theme.clay) : AnyShapeStyle(.secondary))
                    }
                    Text(session.displayTitle)
                        .lineLimit(1)
                    Text(session.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
            }
        }
        .accessibilityLabel([line, session.displayTitle, session.projectName].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the session")
    }

    /// A waiting session whose card is put off with Later: the reminder in
    /// place of the reason, a clock on its glyph, and Show Now and Cancel
    /// Reminder as buttons on the row and in its context menu. Clicking the
    /// row still opens the session, which clears the reminder.
    private func snoozedRow(_ snoozed: SnoozedReminder) -> some View {
        let session = snoozed.session
        return row(session, line: Self.line(for: snoozed), accent: false) {
            PlayedLoop(glyph: (session.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
                .opacity(0.55)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(1.5)
                        .background(.regularMaterial, in: .circle)
                        .offset(x: 3, y: 3)
                }
        } trailing: {
            // Room for the buttons below, which sit over the row so that
            // they don't open the session.
            Color.clear.frame(width: 44, height: 1)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                rowButton("Show Now", symbol: "bell") { model.showNow(session.id) }
                rowButton("Cancel Reminder", symbol: "bell.slash") { model.cancelReminder(session.id) }
            }
            .padding(.trailing, 6)
        }
        .contextMenu {
            Button("Show Now") { model.showNow(session.id) }
            Button("Cancel Reminder") { model.cancelReminder(session.id) }
        }
    }

    private func rowButton(_ title: String, symbol name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func recentRow(_ event: LabEvent) -> some View {
        let when = event.at.formatted(.relative(presentation: .named))
        switch event.kind {
        case .saved(let url):
            let exists = FileManager.default.fileExists(atPath: url.path)
            ActivityRow(action: {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                close()
            }) {
                recentLabel(symbol: "arrow.down.circle", line: "Saved", title: url.lastPathComponent,
                            detail: exists ? when : "\(when) · no longer there")
            }
            .disabled(!exists)
            .accessibilityLabel("Saved \(url.lastPathComponent), \(when)")
        default:
            if let session = event.session {
                ActivityRow(action: {
                    model.open(session)
                    close()
                }) {
                    recentLabel(symbol: Self.symbol(for: event.kind), line: Self.line(for: event.kind),
                                title: session.displayTitle, detail: "\(session.projectName) · \(when)")
                }
                .accessibilityLabel("\(Self.line(for: event.kind)), \(session.displayTitle), \(when)")
                .accessibilityHint("Opens the session")
            }
        }
    }

    private func recentLabel(symbol name: String, line: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            symbol(name)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(line)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
    }

    /// Past tense: these are what happened, not what waits now (that is
    /// Needs you).
    static func line(for kind: LabEvent.Kind) -> String {
        switch kind {
        case .needsInput(let reason):
            switch reason ?? .other {
            case .plan: "Had a plan for you to review"
            default: "Asked you a question"
            }
        case .failed: "Stopped with an error"
        case .finished: "Finished"
        case .saved: "Saved"
        }
    }

    /// What a put-off session's row says in place of its reason: when the
    /// reminder comes, or that it waits for the focus session.
    static func line(for reminder: SnoozedReminder) -> String {
        guard let due = reminder.due else { return "Reminds you after your focus session" }
        return "Reminds you at \(due.formatted(date: .omitted, time: .shortened))"
    }

    static func symbol(for kind: LabEvent.Kind) -> String {
        switch kind {
        case .needsInput: "questionmark.bubble"
        case .failed: "exclamationmark.triangle"
        case .finished: "checkmark.circle"
        case .saved: "arrow.down.circle"
        }
    }
}

/// A row that highlights under the pointer, as a menu's items do, and opens
/// on click or Return.
private struct ActivityRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}
