// ReplyWindow.swift — the small window Reply opens (DESIGN.md, Lab, "Answering
// from the card"). The panel is never key, so it can't take typing; this window
// can, and comes up only when a card's button is pressed, never on its own: a
// question arriving never takes the keyboard from what you're doing. It opens
// beside the panel, says where the answer goes (the session and its project)
// and what Claude said last, and shows each state of the send: sending, sent,
// changed, failed (with the draft kept) and nothing left to answer. It answers
// three things: a question, a permission request (its code read here before
// Allow Once), and what to change in a plan. Once something is sent and more
// sessions wait, Next steps to the next one in the same place.
import AppKit
import SwiftUI

/// A window that can take the keyboard: unlike the panel, it is opened on purpose.
private final class ReplyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ReplyWindowController: NSObject, NSWindowDelegate {
    static let shared = ReplyWindowController()

    private var windows: [String: NSWindow] = [:]
    /// The window's size before its content reports one.
    private static let size = NSSize(width: 440, height: 460)

    /// Reply, Review or Request Changes: the window for this session, opened
    /// beside the panel (or at `origin`, where the last one was), or brought
    /// forward when it is already open. A card still being read opens it
    /// waiting for the read.
    func show(_ sessionID: String, plan: Bool = false, at origin: NSPoint? = nil, replier: QuestionReplier = .shared) {
        // Not answerable now: still opened while its card is being read, or to
        // show a reply kept from before (a notification's answer that failed).
        if !replier.begin(sessionID, plan: plan) {
            guard replier.mode(sessionID) != nil || (!plan && replier.prepare(sessionID)) else { return }
        }
        NSApp.activate()
        if let window = windows[sessionID] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = ReplyView(sessionID: sessionID, replier: replier,
                             onClose: { [weak self] in self?.close(sessionID) },
                             onNext: { [weak self] in self?.next(after: sessionID, replier: replier) })
        let hosting = NSHostingController(rootView: view)
        let window = ReplyPanel(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = Self.title(replier.mode(sessionID))
        window.setContentSize(Self.size)
        window.contentMinSize = NSSize(width: 380, height: 320)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.setFrameOrigin(origin ?? Self.origin(for: window.frame.size, beside: LabPanelController.shared.panelFrame))
        windows[sessionID] = window
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ sessionID: String) {
        windows[sessionID]?.close()
    }

    /// Next: this window gives way to one for the next session waiting, in
    /// the same place.
    private func next(after sessionID: String, replier: QuestionReplier) {
        guard let next = replier.othersWaiting(besides: sessionID).first else {
            close(sessionID)
            return
        }
        let origin = windows[sessionID]?.frame.origin
        close(sessionID)
        show(next, at: origin, replier: replier)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        QuestionReplier.shared.closeReply(id)
    }

    static func title(_ mode: ReplyMode?) -> String {
        switch mode {
        case .permission?: "Permission Request"
        case .plan?: "Request Changes"
        default: "Reply"
        }
    }

    /// Above the panel when there is room, else below it, its trailing edge
    /// with the panel's; centred on the screen when the panel isn't up.
    static func origin(for size: NSSize, beside panel: NSRect?) -> NSPoint {
        let screen = NSScreen.screens.first { panel.map($0.frame.intersects) ?? false } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let panel else {
            return NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        }
        let gap: CGFloat = 4
        var x = panel.maxX - LabPanelView.margin - size.width
        var y = panel.maxY - LabPanelView.margin + gap
        if y + size.height > area.maxY { y = panel.minY + LabPanelView.margin - gap - size.height }
        x = min(max(x, area.minX), area.maxX - size.width)
        y = min(max(y, area.minY), area.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

// MARK: Keys

/// The window's keyboard: ⌘1…⌘9 pick a choice of the question in hand (the
/// one after the last, "Other…"), ⌘↩ sends, Esc closes. Plain Return is left
/// to the text field, so a line break never sends.
enum ReplyKeys {
    static let choices = 9

    /// What ⌘`number` does in a question with `options` choices: pick one,
    /// turn on "Other…", or nothing.
    enum Pick: Equatable {
        case option(Int), other, none
    }

    static func pick(_ number: Int, options: Int) -> Pick {
        guard (1...choices).contains(number) else { return .none }
        if number <= options { return .option(number - 1) }
        return number == options + 1 ? .other : .none
    }
}

// MARK: The window's content

struct ReplyView: View {
    let sessionID: String
    @ObservedObject var replier: QuestionReplier
    let onClose: () -> Void
    let onNext: () -> Void

    @FocusState private var typing: Int?
    @FocusState private var feedbackFocused: Bool
    /// The question ⌘1…⌘9 pick for: the one last touched.
    @State private var inHand = 0
    @State private var contextOpen = false

    var body: some View {
        Group {
            switch replier.mode(sessionID) {
            case .question?:
                if let reply = replier.replies[sessionID] { questionBody(reply) }
            case .permission?:
                if let reply = replier.permissionReplies[sessionID] { permissionBody(reply) }
            case .plan?:
                if let reply = replier.planReplies[sessionID] { planBody(reply) }
            case nil:
                waitingBody
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Read while the window was opening: begin once there is something.
        .onChange(of: replier.cardState(for: sessionID)) { _, _ in
            if replier.mode(sessionID) == nil { replier.begin(sessionID) }
        }
        // Sent: a moment to read it, then the window goes, unless more wait.
        .task(id: sentKey) {
            guard sentKey, othersWaiting == 0 else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, othersWaiting == 0 else { return }
            onClose()
        }
    }

    private var phase: ReplyPhase? {
        switch replier.mode(sessionID) {
        case .question?: replier.replies[sessionID]?.phase
        case .permission?: replier.permissionReplies[sessionID]?.phase
        case .plan?: replier.planReplies[sessionID]?.phase
        case nil: nil
        }
    }

    private var sentKey: Bool {
        if case .sent? = phase { true } else { false }
    }

    private var othersWaiting: Int {
        replier.othersWaiting(besides: sessionID).count
    }

    // MARK: Waiting for the read

    @ViewBuilder
    private var waitingBody: some View {
        switch replier.cardState(for: sessionID) {
        case .loading?:
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unsupported?:
            ContentUnavailableView {
                Label("Answer this one in Capsid", systemImage: "questionmark.bubble")
            } actions: {
                Button("Open in Capsid") { open() }
            }
        default:
            ContentUnavailableView("Nothing to answer", systemImage: "questionmark.bubble",
                                   description: Text("This session isn't waiting for you any more."))
        }
    }

    // MARK: A question

    private func questionBody(_ reply: QuestionReply) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            destination(reply.session, label: "Answering", symbol: "questionmark.bubble")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let context = reply.context { contextBlock(context) }
                    ForEach(Array(reply.ask.items.enumerated()), id: \.offset) { index, item in
                        question(item, at: index, reply: reply)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!reply.phase.canSend)
            Divider()
            footer(phase: reply.phase) {
                if reply.phase.canSend || reply.phase == .sending {
                    Menu("More") {
                        Button("Choose for Me") { replier.submit(sessionID, .chooseForMe) }
                        Button("Cancel Question") { replier.submit(sessionID, .cancel) }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .disabled(!reply.phase.canSend)
                    .help("Let Claude decide, or cancel the question")
                }
            } send: {
                Button("Send Answer") { replier.submit(sessionID) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!replier.canSend(sessionID))
                    .help("Send the answer (⌘↩)")
            } status: {
                if QuestionAnswers.isTooLong(reply.ask, draft: reply.draft) {
                    line(QuestionReplier.Sentence.tooLong, symbol: "exclamationmark.triangle", tint: Theme.clay)
                } else {
                    line("Capsid checks it's still the same question before sending. ⌘1–⌘9 choose, ⌘↩ sends.",
                         symbol: nil, tint: .secondary)
                }
            }
        }
        .background { choiceKeys(reply) }
    }

    private func question(_ item: SessionProjection.Question, at index: Int, reply: QuestionReply) -> some View {
        let draft = reply.draft
        let otherOn = draft.otherOn[index] ?? false
        let showsKeys = index == inHand && reply.phase.canSend
        return VStack(alignment: .leading, spacing: 8) {
            if !item.header.isEmpty {
                Text(item.header)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(item.question)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !item.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { option, choice in
                        let on = (draft.picks[index] ?? []).contains(option)
                        choiceRow(on: on, multi: item.multi, label: choice.label, detail: choice.detail,
                                  key: showsKeys && option < ReplyKeys.choices ? option + 1 : nil) {
                            inHand = index
                            replier.updateDraft(sessionID) { $0.pick(option, in: index, multi: item.multi) }
                        }
                    }
                    choiceRow(on: otherOn, multi: item.multi, label: "Other…", detail: nil,
                              key: showsKeys && item.options.count < ReplyKeys.choices ? item.options.count + 1 : nil) {
                        inHand = index
                        toggleOther(index, multi: item.multi, on: otherOn)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(item.multi ? "Choices, pick any" : "Choices, pick one")
            }
            if otherOn {
                TextField(item.options.isEmpty ? "Your answer" : "Type your answer",
                          text: Binding(get: { replier.replies[sessionID]?.draft.other[index] ?? "" },
                                        set: { text in replier.updateDraft(sessionID) { $0.other[index] = text } }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing, equals: index)
                    .onChange(of: typing) { _, now in if now == index { inHand = index } }
                    .accessibilityLabel("Your own answer")
            }
        }
    }

    private func toggleOther(_ index: Int, multi: Bool, on: Bool) {
        replier.updateDraft(sessionID) { $0.setOther(!on, in: index, multi: multi) }
        if !on { typing = index }
    }

    /// ⌘1…⌘9 for the question in hand: invisible buttons, so the keys work
    /// wherever the focus is in the window.
    private func choiceKeys(_ reply: QuestionReply) -> some View {
        ZStack {
            ForEach(1...ReplyKeys.choices, id: \.self) { number in
                Button("Choice \(number)") {
                    guard reply.ask.items.indices.contains(inHand), reply.phase.canSend else { return }
                    let item = reply.ask.items[inHand]
                    switch ReplyKeys.pick(number, options: item.options.count) {
                    case .option(let option):
                        replier.updateDraft(sessionID) { $0.pick(option, in: inHand, multi: item.multi) }
                    case .other:
                        toggleOther(inHand, multi: item.multi, on: reply.draft.otherOn[inHand] ?? false)
                    case .none:
                        break
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A radio button, or a checkbox when several may be picked, with its
    /// detail under the label and, for the question in hand, its key.
    private func choiceRow(on: Bool, multi: Bool, label: String, detail: String?, key: Int?,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: multi ? (on ? "checkmark.square.fill" : "square")
                                        : (on ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(on ? Theme.clay : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let key {
                    Text("⌘\(key)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: A permission request

    private func permissionBody(_ reply: PermissionReply) -> some View {
        let words = RemotePermission.words(for: reply.request)
        let decision = reply.decision
        return VStack(alignment: .leading, spacing: 0) {
            destination(reply.session, label: "Request from", symbol: "hand.raised")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let context = reply.context { contextBlock(context) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(words.title)
                            .font(.system(size: 14, weight: .semibold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if !words.detail.isEmpty {
                            Text(words.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if reply.request.known == .localExec, let code = reply.request.code, decision.canAllow {
                        codeBlock(code)
                    }
                    if !decision.canAllow, let why = decision.why {
                        line(why, symbol: "info.circle", tint: .secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer(phase: reply.phase) {
                EmptyView()
            } send: {
                if decision.canDeny {
                    Button("Deny") { replier.decide(sessionID, allow: false) }
                        .disabled(!reply.phase.canSend)
                        .help("Deny it. Claude carries on without it.")
                }
                if decision.canAllow {
                    Button("Allow Once") { replier.decide(sessionID, allow: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .disabled(!reply.phase.canSend)
                        .help("Allow it this one time. Capsid checks it's still the same request first.")
                }
            } status: {
                line(decision.canAllow
                     ? "Allow Once lets it happen this one time. Capsid checks it's still the same request first."
                     : "Capsid checks it's still the same request first.",
                     symbol: nil, tint: .secondary)
            }
        }
    }

    /// The code as the request holds it, whole: monospaced, selectable, and
    /// scrolled within its own box.
    private func codeBlock(_ code: String) -> some View {
        var rows = code.split(separator: "\n", omittingEmptySubsequences: false)
        if rows.last?.isEmpty == true { rows.removeLast() }
        let lines = rows.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(lines == 1 ? "1 line" : "\(lines) lines")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(code)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityLabel("The code to run")
        }
    }

    // MARK: What to change in a plan

    private func planBody(_ reply: PlanReply) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            destination(reply.session, label: "Changing the plan of", symbol: "list.bullet.clipboard")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reply.plan.summary)
                            .font(.system(size: 13, weight: .medium))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = reply.plan.detail {
                            Text(detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What should change?")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("For example: add a control plate, or drop step 3",
                                  text: Binding(get: { replier.planReplies[sessionID]?.text ?? "" },
                                                set: { replier.updatePlanFeedback(sessionID, text: $0) }),
                                  axis: .vertical)
                            .lineLimit(4...12)
                            .textFieldStyle(.roundedBorder)
                            .focused($feedbackFocused)
                            .textSelection(.enabled)
                            .accessibilityLabel("What should change in the plan")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!reply.phase.canSend)
            Divider()
            footer(phase: reply.phase) {
                EmptyView()
            } send: {
                Button("Send") { replier.submitPlanFeedback(sessionID) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!replier.canSendPlanFeedback(sessionID))
                    .help("Send it to Claude (⌘↩)")
            } status: {
                let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.unicodeScalars.count > RemoteActionRequest.messageLimit {
                    line(QuestionReplier.Sentence.feedbackTooLong, symbol: "exclamationmark.triangle", tint: Theme.clay)
                } else if PhotoText.hasReference(text) {
                    line(QuestionReplier.Sentence.feedbackReference, symbol: "exclamationmark.triangle", tint: Theme.clay)
                } else {
                    line("Claude revises the plan and asks for your approval again. ⌘↩ sends.",
                         symbol: nil, tint: .secondary)
                }
            }
        }
        .onAppear { feedbackFocused = true }
    }

    // MARK: Parts

    /// The session and its project, always at the top, so an answer can't be
    /// mistaken for another conversation's.
    private func destination(_ session: SessionStatus, label: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.clay)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(session.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text(session.projectName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(session.displayTitle), in \(session.projectName)")
            Spacer(minLength: 8)
        }
        .padding(16)
    }

    /// What Claude said last before it asked: three lines, the rest a click away.
    private func contextBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Claude said")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(contextOpen ? nil : 3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(contextOpen ? "Show less" : "Show more") { contextOpen.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.clay)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    /// The status line, then the buttons: `extra` at the leading edge, Open
    /// in Capsid, and `send` (the send buttons while something can be sent).
    /// Sent with more sessions waiting, Next takes the send buttons' place;
    /// sent with none, or with nothing left to answer, Close does.
    private func footer<Extra: View, Send: View, Status: View>(
        phase: ReplyPhase, @ViewBuilder extra: () -> Extra, @ViewBuilder send: () -> Send,
        @ViewBuilder status: () -> Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .editing:
                status()
            case .sending:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Sending…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .sent(let sentence):
                line(sentence, symbol: "checkmark.circle.fill", tint: Theme.clay)
            case .changed(let sentence):
                line(sentence, symbol: "arrow.triangle.2.circlepath", tint: Theme.clay)
            case .failed(let sentence):
                line(sentence, symbol: "exclamationmark.triangle", tint: Theme.clay)
            case .closed(let sentence):
                line(sentence, symbol: "info.circle", tint: .secondary)
            }
            HStack(spacing: 8) {
                extra()
                Spacer(minLength: 8)
                Button("Open in Capsid") { open() }
                if phase.canSend || phase == .sending {
                    send()
                } else if case .sent = phase, othersWaiting > 0 {
                    Button("Close") { onClose() }
                    Button(othersWaiting == 1 ? "Next (1 more)" : "Next (\(othersWaiting) more)") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .keyboardShortcut(.defaultAction)
                        .help("Answer the next session that needs you")
                } else {
                    Button("Close") { onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.regular)
        }
        .padding(16)
    }

    private func line(_ text: String, symbol: String?, tint: some ShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(symbol == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The session in Capsid, from whatever is known of it; the window goes.
    private func open() {
        LabModel.shared.open(sessionID: sessionID)
        onClose()
    }
}
