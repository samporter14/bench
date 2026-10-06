// QuickOpenSheet.swift — the sheet ⌘⇧O shows on the main window (DESIGN.md,
// Quick Open): a search field and the recent sessions under it, narrowed and
// ordered by `QuickOpen.rank`. ↑ ↓ move, Return or a click opens, Esc closes.
import SwiftUI

struct QuickOpenSheet: View {
    @ObservedObject private var model = LabModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// The highlighted session, by id: a read that reorders the list while
    /// you choose must not move the highlight to another one. Nil, or one that
    /// has left the list, means the first.
    @State private var selectedID: String?
    @FocusState private var searching: Bool

    /// The sheet is about 560 wide and no more than about 420 tall: the field
    /// takes some, and the list scrolls in the rest.
    private static let listHeight: CGFloat = 366

    var body: some View {
        let results = QuickOpen.rank(model.sessions, query: query)
        let selected = results.first { $0.id == selectedID }?.id ?? results.first?.id
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Jump to a session", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searching)
                    .onSubmit { open(results.first { $0.id == selected }) }
                    .onKeyPress(.upArrow) {
                        selectedID = neighbour(of: selected, in: results, by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        selectedID = neighbour(of: selected, in: results, by: 1)
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            if results.isEmpty {
                nothingToShow
            } else {
                list(results, selected: selected)
            }
        }
        .frame(width: 560)
        // Focus on the field from the first frame, and again once the sheet
        // is up, in case the web view took it back in between.
        .defaultFocus($searching, true)
        .onExitCommand { dismiss() }
        .onAppear { searching = true }
        .onChange(of: query) { selectedID = nil }
    }

    // MARK: Parts

    private func list(_ results: [SessionStatus], selected: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(results) { session in
                        QuickOpenRow(session: session, isSelected: session.id == selected) { open(session) }
                            .id(session.id)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: Self.listHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private var nothingToShow: some View {
        Group {
            if !query.allSatisfy(\.isWhitespace) {
                ContentUnavailableView.search(text: query)
            } else if let problem = model.problem {
                ContentUnavailableView("Can't see your sessions", systemImage: "exclamationmark.triangle",
                                       description: Text(problem.label))
            } else {
                ContentUnavailableView("No sessions yet", systemImage: "clock",
                                       description: Text("They show up here once Claude Science has some."))
            }
        }
        .frame(height: 200)
    }

    // MARK: Acting

    /// The session `step` places from the highlighted one, stopping at the
    /// ends of the list.
    private func neighbour(of id: String?, in results: [SessionStatus], by step: Int) -> String? {
        guard let current = results.firstIndex(where: { $0.id == id }) else { return results.first?.id }
        return results[min(max(current + step, 0), results.count - 1)].id
    }

    /// Opens the session, which also clears its cards and reminder, and
    /// closes the sheet.
    private func open(_ session: SessionStatus?) {
        guard let session else { return }
        model.open(session)
        dismiss()
    }
}

/// One session: its state's glyph, its title over its project, and on the
/// right what it is doing or when it last did something.
private struct QuickOpenRow: View {
    let session: SessionStatus
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                glyph
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.displayTitle)
                        .lineLimit(1)
                    Text(session.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
                    .font(.callout)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the session")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The waiting reason's glyph while it waits, the working one while it
    /// works, else a plain symbol.
    @ViewBuilder
    private var glyph: some View {
        switch session.state {
        case .needsInput:
            PlayedLoop(glyph: (session.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
        case .running:
            WorkingGlyph(tint: colorScheme.sceneInk, rotation: SceneSettings.shared.rotation)
        case .finished:
            symbol("checkmark.circle")
        case .error:
            symbol("exclamationmark.triangle")
        case .unknown:
            symbol("clock")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var trailing: some View {
        switch session.state {
        case .needsInput:
            Text("Needs you")
                .fontWeight(.medium)
                .foregroundStyle(Theme.clay)
        case .running:
            if let since = session.startedAt {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text("Working · \(ElapsedClock.format(context.date.timeIntervalSince(since)))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Working")
                    .foregroundStyle(.secondary)
            }
        case .finished, .error, .unknown:
            TimelineView(.everyMinute) { context in
                Text(Self.ago(session.updatedAt, now: context.date))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Just now" or "5 min. ago": the formatter alone says "in 0 sec." for
    /// a session that wrote this instant.
    static func ago(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60
            ? "Just now"
            : date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private var spoken: String {
        let state: String? = switch session.state {
        case .needsInput: (session.waitingReason ?? .other).sentence
        case .running: "Working"
        case .error: "Stopped with an error"
        case .finished, .unknown: nil
        }
        let when = session.state == .running || session.state == .needsInput
            ? nil : Self.ago(session.updatedAt, now: Date())
        return [state, session.displayTitle, session.projectName, when].compactMap { $0 }.joined(separator: ", ")
    }
}
