// CompanionHomeView.swift — the menu bar home, drawn after board 1 of the
// Capsid 1.0 mock-ups (DESIGN.md, Menu bar home): one glass popover, 400 points
// wide with 18-point corners and a hairline edge, from the top:
//   - "Capsid", a Quiet While Presenting toggle and Settings;
//   - the "Start a session…" field with its project pill (↩ starts the session
//     in that project from here, through Quick Start's flow; ⌘↩ opens Quick
//     Start with the words and the project), and under it a line while
//     something is typed or sent: what ↩ does, "Starting…", the outcome;
//   - Needs you · N, each row with its own buttons (the cards' own: Reply, Open,
//     Later; Approve, Request changes…), a spinner while one sends, "Approved ✓" after;
//   - Working · N, a small specimen and the turn's clock, ticking;
//   - Recent, the sessions active latest that neither need you nor work: a dot,
//     the title, "project · when"; a click opens one, ⌥-click as a reference;
//   - Results today · N, four tiles and "Show all";
//   - Since you left, when a return is waiting: its headline, and a press opens the sheet;
//   - the 5-hour limit, a bar of what is used;
//   - Open Capsid.
// What it draws is `CompanionModel.sections` (CompanionSections.swift); what the buttons do
// is `CompanionActions`. The glass itself (the blur behind the window) is the panel's
// (CompanionPanel.swift); this draws the ivory (or slate) tint over it.
import AppKit
import SwiftUI

extension Solanum {
    /// The popover's ground over the blur: ivory at 90%, or slate's raised shade at 88%.
    static let homeGlassColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 27 / 255, alpha: 0.88)
            : NSColor(srgbRed: 246 / 255, green: 245 / 255, blue: 240 / 255, alpha: 0.9)
    }
    static let homeGlass = Color(nsColor: homeGlassColor)
}

struct CompanionHomeView: View {
    static let width: CGFloat = 400
    static let corner: CGFloat = 18
    /// The header, the field (and the line under it), the limit and the foot never scroll; this is about what
    /// they take.
    static let pinnedHeight: CGFloat = 236

    @ObservedObject private var model: CompanionModel
    @ObservedObject private var results: CompanionResults
    @ObservedObject private var presenting: PresentingMode
    @ObservedObject private var start: CompanionStart
    private let actions: CompanionActions
    /// The tallest the popover may be: what is more scrolls.
    private let maxHeight: CGFloat
    /// The popover's height as drawn, for the window that holds it.
    private let onFit: (CGFloat) -> Void

    @FocusState private var typing: Bool

    init(model: CompanionModel, presenting: PresentingMode = .shared, actions: CompanionActions = .none,
         maxHeight: CGFloat = 900, onFit: @escaping (CGFloat) -> Void = { _ in }) {
        _model = ObservedObject(wrappedValue: model)
        _results = ObservedObject(wrappedValue: model.sources.results)
        _start = ObservedObject(wrappedValue: model.start)
        _presenting = ObservedObject(wrappedValue: presenting)
        self.actions = actions
        self.maxHeight = maxHeight
        self.onFit = onFit
    }

    var body: some View {
        let sections = model.sections
        VStack(alignment: .leading, spacing: 4) {
            header
            if let problem = sections.problem { problemLine(problem) }
            field
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    let blocks = sections.blocks
                    ForEach(Array(blocks.enumerated()), id: \.element) { index, block in
                        if index > 0 { divider }
                        content(of: block, sections)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: max(160, maxHeight - Self.pinnedHeight))
            .fixedSize(horizontal: false, vertical: true)
            foot(sections)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: Self.width)
        .background(Solanum.homeGlass)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).strokeBorder(Solanum.hairline, lineWidth: 1))
        // A popover that nothing has made key draws a prominent button dimmed: its buttons are meant to look live.
        .environment(\.appearsActive, true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onFit($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CompanionText.name)
    }

    // MARK: Blocks

    @ViewBuilder
    private func content(of block: CompanionSections.Block, _ sections: CompanionSections) -> some View {
        switch block {
        case .quiet: quietLine
        case .needs: needsSection(sections)
        case .working: workingSection(sections)
        case .recent: recentSection(sections)
        case .results: if let section = sections.results { resultsSection(section) }
        case .since: if let section = sections.since { sinceSection(section) }
        }
    }

    private var divider: some View {
        Rectangle().fill(Solanum.hairline).frame(height: 1)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .accessibilityHidden(true)
    }

    // MARK: Header and field

    private var header: some View {
        HStack(spacing: 8) {
            Text(CompanionText.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Solanum.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button(action: actions.toggleQuiet) {
                Image(systemName: presenting.manualOn ? "moon.fill" : "moon").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SolanumRoundStyle())
            .help(CompanionText.quietHelp)
            .accessibilityLabel(CompanionText.quietHelp)
            .accessibilityValue(presenting.manualOn ? "On" : "Off")
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SolanumRoundStyle())
            .help(CompanionText.settingsHelp)
            .accessibilityLabel(CompanionText.settingsHelp)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func problemLine(_ problem: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Solanum.muted)
            Text(problem).font(.system(size: 12)).foregroundStyle(Theme.clayText).lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Solanum.muted)
                    .accessibilityHidden(true)
                TextField(CompanionText.quickStartPlaceholder, text: $start.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Solanum.ink)
                    .focused($typing)
                    .disabled(start.phase == .sending)
                    // ↩ starts the session; ⌘↩ is the hidden button below, which a key equivalent reaches first.
                    .onSubmit { submit(command: NSApp.currentEvent?.modifierFlags.contains(.command) == true) }
                    .help(fieldHelp)
                    .accessibilityLabel("Start a session")
                    .accessibilityHint(fieldHelp)
                projectPill
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 36)
            .background(Capsule().fill(Solanum.raised.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Solanum.strong, lineWidth: 1))
            if let line = start.line { fieldLine(line) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background {
            // ⌘↩: Quick Start with the words and the project, wherever the focus is in the popover.
            Button("Open in Quick Start") { submit(command: true) }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task {
            // The field has the keyboard as the popover comes up.
            await Task.yield()
            typing = true
        }
        // It is off while a request goes; it has the keyboard again when the request has gone (or hasn't).
        .onChange(of: start.phase == .sending) { _, sending in
            if !sending { typing = true }
        }
    }

    /// ↩ starts the session from here; ⌘↩, or ↩ with nothing typed, opens Quick Start with what is here.
    private func submit(command: Bool) {
        switch CompanionStart.onReturn(command: command, hasText: start.hasText) {
        case .start:
            start.start()
        case .quickStart:
            // The popover goes only once Quick Start has the words; if it can't take them they stay here.
            if start.handOver(through: actions.quickStart) { actions.close() }
        }
    }

    private var fieldHelp: String {
        let key = model.quickStartKey.map { " (\($0) from any app)" } ?? ""
        return "Return starts a session in the project beside it. Command-Return opens Quick Start\(key) with the words and the project, for files and recipes."
    }

    /// The project the field starts in: a quiet pill, its menu the projects as Quick Start's chips have them.
    private var projectPill: some View {
        Menu {
            ForEach(start.menuProjects) { project in
                Toggle(project.name, isOn: Binding(get: { start.projectID == project.id },
                                                   set: { if $0 { start.choose(project) } }))
            }
            let others = start.otherProjects
            if !others.isEmpty {
                Divider()
                Menu("Other Projects") {
                    ForEach(others) { project in
                        Button(project.name) { start.choose(project) }
                    }
                }
            }
            if start.menuProjects.isEmpty && others.isEmpty {
                Text("No projects yet")
            }
        } label: {
            HStack(spacing: 4) {
                Text(start.pillTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Solanum.muted)
            }
            .font(.system(size: 12))
            .foregroundStyle(Solanum.ink)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: 156)
            // Quiet: a faint tint inside the field, no edge of its own and no clay.
            .background(Capsule().fill(Solanum.ink.opacity(0.06)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(start.phase == .sending)
        .help("The project a new session starts in")
        .accessibilityLabel("Project, \(start.pillTitle)")
        .accessibilityHint("Chooses the project a new session starts in")
    }

    /// Under the field: what ↩ does while something is typed, then the send's state and how it went.
    @ViewBuilder
    private func fieldLine(_ line: CompanionStart.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch line {
            case .hint(let hint):
                Text(hint).foregroundStyle(Solanum.muted)
                Spacer(minLength: 8)
                Text(CompanionText.fullPanelHint).foregroundStyle(Solanum.muted)
            case .sending(let words):
                ProgressView().controlSize(.mini).accessibilityHidden(true)
                Text(words).foregroundStyle(Solanum.muted)
                Spacer(minLength: 0)
            case .started(let sentence):
                Text(sentence).foregroundStyle(Solanum.ink)
                Spacer(minLength: 8)
                if let started = start.started {
                    Button("Open") {
                        actions.close()
                        actions.openStarted(started.sessionID, started.projectID)
                    }
                    .buttonStyle(SolanumPillStyle(.small))
                    .help("Open the new session")
                }
            case .failed(let sentence):
                Text(sentence)
                    .foregroundStyle(Theme.clayText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            case .kept(let sentence):
                Text(sentence).foregroundStyle(Solanum.muted)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 12))
        .lineLimit(3)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Needs you

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Solanum.muted)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func needsSection(_ sections: CompanionSections) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = sections.needsTitle { sectionTitle(title) }
            ForEach(sections.needs) { needRow($0) }
            if sections.needsHidden > 0 { moreRow(sections.needsHidden, "need you") { model.showAllNeeds() } }
        }
    }

    private func needRow(_ row: CompanionNeedRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NeedGlyph(kind: row.kind).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Button { actions.open(row.session) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.caption)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.clayText)
                        Text(row.session.displayTitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Solanum.ink)
                            .lineLimit(1)
                        TimelineView(.everyMinute) { context in
                            Text(CompanionText.needDetail(project: row.session.projectName, steps: row.steps,
                                                          waitingSince: row.session.updatedAt, now: context.date))
                                .font(.system(size: 12))
                                .foregroundStyle(Solanum.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open the session")
                .accessibilityLabel("\(row.caption), \(row.session.displayTitle), \(row.session.projectName)")
                .accessibilityHint("Opens the session")
                answer(row)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The row's answer: its buttons, a spinner while one goes, or what it did.
    @ViewBuilder
    private func answer(_ row: CompanionNeedRow) -> some View {
        switch row.lead {
        case .done(let text):
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "checkmark")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.clayText)
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
        case .sending(let label):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).accessibilityLabel(label)
                pills(row)
            }
            .padding(.top, 6)
        case .button:
            pills(row).padding(.top, 6)
        }
        if let problem = row.problem {
            Text(problem)
                .font(.system(size: 12))
                .foregroundStyle(Theme.clayText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func pills(_ row: CompanionNeedRow) -> some View {
        HStack(spacing: 6) {
            ForEach(row.pills) { pill in
                Button(pill.title) { press(pill, row.session) }
                    .buttonStyle(SolanumPillStyle(.small, prominent: pill.prominent))
                    .help(helpText(pill))
            }
        }
    }

    private func helpText(_ pill: CompanionNeedRow.Pill) -> String {
        switch pill.action {
        case .later: "Remind me in 5 minutes"
        case .card(let card): card.help ?? ""
        }
    }

    /// Later puts the card off five minutes; the others are the card's (`CardActions.perform`). What opens a
    /// window of its own, or goes to the session, first steps this popover aside.
    private func press(_ pill: CompanionNeedRow.Pill, _ session: SessionStatus) {
        switch pill.action {
        case .later:
            actions.later(session)
        case .card(let card):
            if card.opensWindow || card == .open || card == .openInCapsid { actions.close() }
            actions.perform(card, session)
        }
    }

    /// "2 more" at the end of a long list: a press shows the rest.
    private func moreRow(_ count: Int, _ what: String, _ show: @escaping () -> Void) -> some View {
        Button(action: show) {
            HStack(spacing: 4) {
                Text(CompanionText.more(count))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Solanum.muted)
            .padding(.leading, 56)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) more that \(what)")
        .accessibilityHint("Shows them")
    }

    // MARK: Working

    private func workingSection(_ sections: CompanionSections) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = sections.workingTitle { sectionTitle(title) }
            ForEach(sections.working) { workingRow($0) }
            if sections.workingHidden > 0 { moreRow(sections.workingHidden, "work") { model.showAllWorking() } }
        }
    }

    private func workingRow(_ row: CompanionWorkingRow) -> some View {
        Button { actions.open(row.session) } label: {
            HStack(spacing: 12) {
                Group {
                    if row.pause != nil {
                        Image(systemName: "pause.circle").font(.system(size: 20)).foregroundStyle(Solanum.muted)
                    } else {
                        WorkingGlyph(tint: Solanum.ink, rotation: SceneSettings.shared.rotation)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.session.displayTitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Solanum.ink)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let pause = row.pause {
                    Text(pause).font(.system(size: 12)).foregroundStyle(Solanum.muted).lineLimit(1)
                } else if let since = row.session.startedAt {
                    // The turn's clock, ticking only while this is on screen.
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(ElapsedClock.format(context.date.timeIntervalSince(since)))
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Solanum.muted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.session.displayTitle), \(row.session.projectName)")
        .accessibilityHint("Opens the session")
    }

    // MARK: Recent

    private func recentSection(_ sections: CompanionSections) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(CompanionText.recentTitle)
            ForEach(sections.recent) { recentRow($0) }
            if sections.recentHidden > 0 {
                Button { actions.close(); actions.showQuickOpen() } label: {
                    HStack(spacing: 4) {
                        Text(CompanionText.more(sections.recentHidden))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Solanum.muted)
                    .padding(.leading, 56)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open Quick Open")
                .accessibilityLabel("\(sections.recentHidden) more recent sessions")
                .accessibilityHint("Opens Quick Open")
            }
        }
    }

    private func recentRow(_ row: CompanionRecentRow) -> some View {
        Button {
            Self.press(row.session, option: NSEvent.modifierFlags.contains(.option), actions: actions)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(row.waits ? Theme.clay : Solanum.muted.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.session.displayTitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Solanum.ink)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { Self.press(row.session, option: false, actions: actions) }
            Button("Open as Reference") { Self.press(row.session, option: true, actions: actions) }
            Divider()
            Button("Copy Link") { actions.copyLink(row.session) }
        }
        .help("Open the session. Option-click opens it as a reference.")
        .accessibilityLabel("\(row.session.displayTitle), \(row.detail)")
        .accessibilityHint("Opens the session")
        .accessibilityAction(named: "Open as Reference") { Self.press(row.session, option: true, actions: actions) }
    }

    /// A Recent row's press: the session in Capsid's window, or with ⌥ as a reference beside the work. Either
    /// way the popover steps aside first.
    static func press(_ session: SessionStatus, option: Bool, actions: CompanionActions) {
        actions.close()
        switch CompanionRecentRow.route(option: option) {
        case .open: actions.open(session)
        case .reference: actions.reference(session)
        }
    }

    // MARK: Results today

    private func resultsSection(_ section: CompanionResultsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Solanum.muted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: actions.showResults) {
                    Text(CompanionText.showAll)
                        .font(.system(size: 12))
                        .underline(true, pattern: .solid, color: Theme.clay)
                        .foregroundStyle(Solanum.ink)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Results")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)
            if !section.tiles.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: CompanionResultsSection.tileLimit),
                          alignment: .leading, spacing: 8) {
                    ForEach(section.tiles) { tile in
                        Button(action: actions.showResults) {
                            CompanionTileView(tile: tile, picture: results.picture(for: tile.version))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Since you left

    private func sinceSection(_ section: CompanionSinceSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(section.title)
            Button(action: actions.showSince) {
                HStack(spacing: 8) {
                    Text(section.headline)
                        .font(.system(size: 14))
                        .foregroundStyle(Solanum.ink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Solanum.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.title), \(section.headline)")
            .accessibilityHint("Opens what changed")
        }
    }

    // MARK: The foot

    private func foot(_ sections: CompanionSections) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let usage = sections.usage {
                Rectangle().fill(Solanum.hairline).frame(height: 1)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(usage.label).foregroundStyle(Solanum.muted)
                        Spacer(minLength: 8)
                        Text(usage.value)
                            .fontWeight(.semibold)
                            .foregroundStyle(usage.isLow ? AnyShapeStyle(Theme.clayText) : AnyShapeStyle(Solanum.ink))
                    }
                    .font(.system(size: 12))
                    Capsule().fill(Solanum.ink.opacity(0.12)).frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(Theme.clay).frame(width: proxy.size.width * min(1, max(0, usage.used)))
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
            Button(action: actions.openCapsid) {
                Text(CompanionText.openButton()).frame(maxWidth: .infinity)
            }
            .buttonStyle(SolanumPillStyle(.regular))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: Quiet

    private var quietLine: some View {
        Text(CompanionText.nothingToDo)
            .font(.system(size: 13))
            .foregroundStyle(Solanum.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

/// One of Results today's tiles: a picture of an image when the app holds one, else a tile naming the kind of
/// file ("PNG", "CSV"), and the name.
struct CompanionTileView: View {
    let tile: CompanionTile
    let picture: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The box is a fixed shape: a picture fills it without growing it (drawn over, not laid out).
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .overlay {
                    if tile.isPicture, let picture {
                        Image(decorative: picture, scale: 1).resizable().scaledToFill()
                    } else {
                        // A file that has no picture, or an image whose picture isn't in memory: its kind.
                        Text(tile.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Solanum.muted)
                    }
                }
                .background(Solanum.raised, in: .rect(cornerRadius: 8))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Solanum.hairline, lineWidth: 1))
            Text(tile.name)
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.name)
        .accessibilityHint("Opens Results")
    }
}
