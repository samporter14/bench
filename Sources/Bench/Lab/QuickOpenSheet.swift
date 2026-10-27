// QuickOpenSheet.swift — the sheet ⌘⇧O shows on the main window (DESIGN.md,
// Quick Open): a search field and the recent sessions under it, narrowed and
// ordered by `QuickOpen.rank`, with older sessions from the database ranked in
// when they are found (QuickOpenSearch), and under them a group of figures and
// files from every session ("Figures and files", Find/QuickOpenFiles.swift).
// ↑ ↓ move through both, Return or a click opens a session or shows where a
// file came from, ⌥↩ opens a session as a reference or adds a file to the
// shelf, Esc closes.
import SwiftUI

struct QuickOpenSheet: View {
    @ObservedObject private var model = LabModel.shared
    /// The last read's sessions, published apart from `LabModel`.
    @ObservedObject private var reads = LabModel.shared.reads
    @Environment(\.dismiss) private var dismiss
    /// Older sessions, looked up by name once typing pauses.
    @StateObject private var search = QuickOpenSearch()
    /// Figures and files from every session, looked up the same way.
    @StateObject private var files = FindSearch()
    private let find = FindActions.live()
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
        let results = QuickOpenFiles.entries(sessions: QuickOpen.rank(reads.sessions, plus: search.found, query: query),
                                             files: files.files)
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
                    .onSubmit { activate(results.first { $0.id == selected }) }
                    // ⌥↩ opens the highlighted session as a reference. Caught
                    // here, as the arrows are: in a text field Option-Return
                    // would insert a line break and never submit.
                    .onKeyPress(keys: [.return]) { press in
                        guard press.modifiers.contains(.option) else { return .ignored }
                        alternate(results.first { $0.id == selected })
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selectedID = neighbour(of: selected, in: results, by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        selectedID = neighbour(of: selected, in: results, by: 1)
                        return .handled
                    }
                if search.isSearching || files.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching older sessions")
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
        .onDisappear {
            search.cancel()
            files.cancel()
        }
        .onChange(of: query) {
            selectedID = nil
            search.queryChanged(query)
            files.update(query, limit: QuickOpenFiles.asked)
        }
        // Older sessions arriving must not move the highlight from under
        // the user: the row it was on stays, even if a better match now sits
        // above it. (Once they have moved it themselves, it follows its id.)
        .onChange(of: search.found) { previous, _ in
            if selectedID == nil {
                selectedID = QuickOpenFiles.entries(sessions: QuickOpen.rank(reads.sessions, plus: previous, query: query),
                                                    files: files.files).first?.id
            }
        }
        .onChange(of: files.files) { previous, _ in
            if selectedID == nil {
                selectedID = QuickOpenFiles.entries(sessions: QuickOpen.rank(reads.sessions, plus: search.found, query: query),
                                                    files: previous).first?.id
            }
        }
    }

    // MARK: Parts

    private func list(_ results: [QuickOpenEntry], selected: String?) -> some View {
        let firstFile = results.first { if case .file = $0 { true } else { false } }?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(results) { entry in
                        switch entry {
                        case .session(let session):
                            QuickOpenRow(session: session, isSelected: entry.id == selected,
                                         action: { open(session) }, reference: { reference(session) })
                                .id(entry.id)
                        case .file(let file):
                            // The group's heading, once, before its first row.
                            if entry.id == firstFile {
                                Text(QuickOpenFiles.heading)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            QuickOpenFileRow(file: file, isSelected: entry.id == selected, onShelf: find.onShelf(file.version),
                                             action: { showWhere(file) }, add: { addToShelf(file) })
                                .id(entry.id)
                        }
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
            if search.isSearching || files.isSearching {
                // The recent sessions had no match; the database may.
                ProgressView("Searching…")
            } else if !query.allSatisfy(\.isWhitespace) {
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
    private func neighbour(of id: String?, in results: [QuickOpenEntry], by step: Int) -> String? {
        guard let current = results.firstIndex(where: { $0.id == id }) else { return results.first?.id }
        return results[min(max(current + step, 0), results.count - 1)].id
    }

    /// Return: opens a session, or shows where a file came from.
    private func activate(_ entry: QuickOpenEntry?) {
        switch entry {
        case .session(let session)?: open(session)
        case .file(let file)?: showWhere(file)
        case nil: break
        }
    }

    /// ⌥↩: a session as a reference, a file onto the shelf.
    private func alternate(_ entry: QuickOpenEntry?) {
        switch entry {
        case .session(let session)?: reference(session)
        case .file(let file)?: addToShelf(file)
        case nil: break
        }
    }

    /// The main window on the session, at the reply that showed the file.
    private func showWhere(_ file: FoundFile) {
        dismiss()
        find.show(file)
    }

    /// The shelf's add, saying so in the toast on the main window. A file
    /// that is there already is shown on the shelf instead.
    private func addToShelf(_ file: FoundFile) {
        dismiss()
        let find = find
        Task { @MainActor in await find.addSayingSo(file) }
    }

    /// Opens the session, which also clears its cards and reminder, and
    /// closes the sheet.
    private func open(_ session: SessionStatus?) {
        guard let session else { return }
        model.open(session)
        dismiss()
    }

    /// ⌥↩, or the row's menu: the reader beside the work
    /// (Reference/ReferenceWindow.swift), which leaves the session's cards
    /// and reminder as they are.
    private func reference(_ session: SessionStatus?) {
        guard let session else { return }
        dismiss()
        ReferenceWindowController.shared.show(session)
    }
}

/// One session: its state's glyph, its title over its project, and on the
/// right what it is doing or when it last did something.
private struct QuickOpenRow: View {
    let session: SessionStatus
    let isSelected: Bool
    let action: () -> Void
    /// Open as Reference, in the row's context menu (and ⌥↩ on the field).
    let reference: () -> Void
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
        .contextMenu {
            Button("Open as Reference", action: reference)
        }
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the session")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open as Reference", reference)
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
                .foregroundStyle(Theme.clayText)
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
