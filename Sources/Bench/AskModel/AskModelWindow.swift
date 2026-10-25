// AskModelWindow.swift — the Ask Another Model window (DESIGN.md, Ask another
// model), on the 1.0 windows' Solanum surfaces (App/SolanumSurface.swift) as
// the reference window is: the page's own band for a title bar, "Ask Another
// Model" over the session and its project; the question on a white card; one
// switch, "Include the conversation so far", with the turns it sends listed
// under it while it is on; the model's name, quiet, and the one clay action,
// Ask (⌘↩); then the answer, drawn by the reference window's Markdown reader,
// with Copy and Send to Session at the foot. While it asks: a spinner (or a
// quiet "Thinking…" while only reasoning arrives) and Cancel (Esc); then the
// words as they arrive, the view following the end until the reader scrolls
// up (AskScrollFollow), and Cancel still in Ask's place. A failure is one
// sentence in clay-text; one that comes after some words keeps them on
// screen, marked, with Copy and without Send to Session.
//
// One window per session; opening it again brings it forward (with the new
// selection in the field, unless it is asking). Nothing in it is saved: the
// question, the conversation and the answer live in memory while it is open.
import AppKit
import SwiftUI

@MainActor
final class AskModelWindowController: NSObject, NSWindowDelegate {
    static let shared = AskModelWindowController()
    static let size = NSSize(width: 520, height: 640)
    private static let frameName = "CapsidAskModel"

    private var windows: [String: NSWindow] = [:]
    private var models: [String: AskModel] = [:]
    /// Whether the feature is on with a key saved: nothing opens otherwise.
    private let available: @MainActor () -> Bool

    init(available: @escaping @MainActor () -> Bool = { AnotherModel.shared.isAvailable }) {
        self.available = available
    }

    /// Opens the window on `subject`, or brings its session's forward. False,
    /// and nothing opens, while the switch is off or no key is saved.
    @discardableResult
    func show(_ subject: AskSubject, dependencies: AskDependencies? = nil) -> Bool {
        guard available() else { return false }
        if let window = windows[subject.sessionID] {
            models[subject.sessionID]?.reseed(subject.seed)
            Demo.activateUnlessQuiet()
            window.makeKeyAndOrderFront(nil)
            return true
        }
        let model = AskModel(subject: subject, dependencies: dependencies ?? .live())
        let hosting = NSHostingController(rootView: AskModelView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = "Ask Another Model"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = Solanum.pageColor
        window.setContentSize(Self.size)
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.toolbarStyle = .unified
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        windows[subject.sessionID] = window
        models[subject.sessionID] = model
        model.open()
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
        return true
    }

    /// File → Ask Another Model…: the session in the main window, its last question.
    func askAboutViewedSession() {
        Task { @MainActor in
            guard available(), let viewed = await QuickStartProjects.viewedSession() else { return }
            show(Self.subject(viewed, seed: nil))
        }
    }

    /// The item in Claude Science's model menu: the session in the main window,
    /// starting from what is typed in the page's message box (`draft`); with
    /// nothing typed, from the session's last question, as File's item does.
    func askFromModelMenu(draft: String?) {
        Task { @MainActor in
            guard available(), let viewed = await QuickStartProjects.viewedSession() else { return }
            show(Self.subject(viewed, seed: draft))
        }
    }

    static func subject(_ viewed: ViewedSession, seed: String?) -> AskSubject {
        let seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AskSubject(sessionID: viewed.id, title: viewed.title, projectName: viewed.projectName,
                          seed: seed?.isEmpty == false ? seed : nil)
    }

    /// The window a session's question shows in, for tests.
    func window(for sessionID: String) -> NSWindow? { windows[sessionID] }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        if Demo.mode == nil { window.saveFrame(usingName: Self.frameName) }
        models[id]?.close()
        models[id] = nil
        windows[id] = nil
    }
}

// MARK: The content

struct AskModelView: View {
    @ObservedObject var model: AskModel
    @FocusState private var typing: Bool

    private static let side: CGFloat = 24
    private static let gap: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            composer
                .padding(.horizontal, Self.side)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Solanum.hairline.frame(height: 1)
            answerPage
            if model.phase == .answered || model.isPartial { footer }
        }
        .frame(minWidth: 420, minHeight: 420)
        .background { Solanum.page.ignoresSafeArea() }
        .overlay {
            // The title bar's band and its hairline, over the page, as the reference window draws it.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ZStack { Solanum.page; Solanum.bar }
                        .frame(height: proxy.safeAreaInsets.top)
                        .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                AskModelTitle(subject: model.subject)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear { typing = true }
    }

    // MARK: The question

    private var composer: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            questionCard
            conversationRow
            if model.includeConversation { turns }
            HStack(spacing: 8) {
                Text(model.modelName ?? "No model chosen. Choose one in Settings \u{2192} General.")
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("The model chosen in Settings \u{2192} General")
                Spacer(minLength: 8)
                // While it asks, Cancel takes Ask's place: one button at a time.
                if model.isAsking {
                    Button("Cancel") { model.cancel() }
                        .buttonStyle(SolanumPillStyle(.regular))
                        .keyboardShortcut(.cancelAction)
                        .help("Stop asking (Esc); what has come stays")
                } else {
                    Button("Ask") { model.ask() }
                        .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canAsk)
                        .help("Ask the other model (Command-Return)")
                }
            }
        }
    }

    private var questionCard: some View {
        TextEditor(text: $model.question)
            .font(.system(size: Solanum.bodySize))
            .foregroundStyle(Solanum.ink)
            .scrollContentBackground(.hidden)
            .focused($typing)
            .disabled(model.isAsking)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(height: 112)
            .background(alignment: .topLeading) {
                if model.question.isEmpty {
                    Text(placeholder)
                        .font(.system(size: Solanum.bodySize))
                        .foregroundStyle(Solanum.muted)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Solanum.raised)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
            .accessibilityLabel("Your question")
    }

    private var placeholder: String {
        if model.subject.seed == nil, model.reading == .reading { return "Reading your last question\u{2026}" }
        if model.subject.seed == nil, model.reading == .unreadable { return "Your last question couldn\u{2019}t be read. Type it here." }
        return "What should the other model answer?"
    }

    /// The words at the left, the switch at the right under the field's edge,
    /// and while it is on, what it sends beside it.
    private var conversationRow: some View {
        HStack(spacing: 10) {
            Text("Include the conversation so far")
                .font(.system(size: 13))
                .foregroundStyle(Solanum.ink)
            Spacer(minLength: 8)
            if model.includeConversation {
                Text(conversationCount)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .monospacedDigit()
            }
            Toggle("Include the conversation so far", isOn: $model.includeConversation)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.clay)
                .disabled(model.isAsking)
        }
    }

    private var conversationCount: String {
        switch model.reading {
        case .unread, .reading: return "Reading\u{2026}"
        case .unreadable: return "Couldn\u{2019}t be read"
        case .read:
            let count = model.conversation.count
            let characters = model.conversation.reduce(0) { $0 + $1.text.count }
            return count == 0 ? "Nothing before your question" : "\(count) \(count == 1 ? "turn" : "turns") \u{00B7} \(characters.formatted()) characters"
        }
    }

    /// The turns that go with the question, exactly as they are sent.
    @ViewBuilder
    private var turns: some View {
        if model.reading == .read, !model.conversation.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.conversation) { turn in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(turn.role == .you ? "You" : "Claude")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Solanum.muted)
                            Text(turn.text)
                                .font(.system(size: Solanum.captionSize))
                                .foregroundStyle(Solanum.muted)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 104)
            .background(Solanum.selection.opacity(0.5))
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityLabel("The conversation sent with your question")
        }
    }

    // MARK: The answer

    /// Every state that has words shows them in one view, so the reading
    /// position survives the stream ending (a stop, a failure) and the foot
    /// appearing.
    @ViewBuilder
    private var answerPage: some View {
        if model.phase == .streaming || model.phase == .answered || model.isPartial {
            AskAnswerScroll {
                VStack(alignment: .leading, spacing: 10) {
                    Text(answerCaption)
                        .font(.system(size: Solanum.captionSize))
                        .foregroundStyle(Solanum.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ReferenceTextView(text: model.rendered, selection: ReferenceSelection(), keepsSelection: model.isAsking)
                }
                .padding(.horizontal, Self.side)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch model.phase {
            case .asking:
                centred {
                    ProgressView().controlSize(.small)
                    Text(model.thinking ? "Thinking\u{2026}" : "Asking \(model.modelName ?? "the other model")\u{2026}")
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                }
            case .failed(let sentence):
                centred {
                    Text(sentence)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.clayText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .cancelled:
                centred {
                    Text("Cancelled.")
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                }
            default:
                centred {
                    Text("Your question goes to \(model.host), not to Claude.\nThe answer shows here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var answerCaption: String {
        AskRules.caption(phase: model.phase, seconds: model.seconds, answeredBy: model.answeredBy, model: model.modelName)
    }

    private func centred<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The foot

    private var footer: some View {
        HStack(spacing: 10) {
            Button(model.copied ? "Copied" : "Copy") { model.copy() }
                .help("The answer as it came")
            if let line = footerLine {
                Text(line.text)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(line.problem ? AnyShapeStyle(Theme.clayText) : AnyShapeStyle(Solanum.muted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer(minLength: 8)
            }
            if model.sending == .sending || model.sending == .checking {
                ProgressView().controlSize(.mini)
            }
            Button(sendTitle) { model.sendToSession() }
                .disabled(!model.canSend)
                .help("Post the answer in the session as your next message, after a line naming the model")
        }
        .buttonStyle(SolanumPillStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Solanum.hairline.frame(height: 1) }
    }

    private var sendTitle: String {
        if case .done = model.sending { return "Sent \u{2713}" }
        return "Send to Session"
    }

    /// What the foot says beside Send to Session: why it can't go, how it is
    /// going, or how it went.
    private var footerLine: (text: String, problem: Bool)? {
        switch model.sending {
        case .sending: return ("Sending\u{2026}", false)
        case .checking: return (RemoteDecide.Sentence.checking, false)
        case .done(let sentence): return (sentence, false)
        case .failed(let sentence): return (sentence, true)
        case .idle:
            // A failure that came after some words: its sentence leads, and Send is dim.
            if case .failed(let sentence) = model.phase, model.isPartial { return (sentence, true) }
            if let check = model.sendCheck, let why = AskRules.unsendable(check) { return (why, false) }
            return nil
        }
    }
}

/// The title bar's centre: "Ask Another Model" over the session and its project.
struct AskModelTitle: View {
    let subject: AskSubject

    var body: some View {
        VStack(spacing: 1) {
            Text("Ask Another Model")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Solanum.ink)
            Text(subject.projectName.isEmpty ? subject.title : "\(subject.title) \u{00B7} \(subject.projectName)")
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// The answer's scroll view. It goes to the end as words arrive, and stops
/// when the reader scrolls up; it goes on again when they reach the end
/// (`AskScrollFollow`). Short of a full page it is at the top, where reading
/// begins.
private struct AskAnswerScroll<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var follow = AskScrollFollow()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    Color.clear.frame(height: 1).id(Self.end)
                }
            }
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: AskScrollMetrics.self) { geometry in
                AskScrollMetrics(top: geometry.visibleRect.minY, bottom: geometry.visibleRect.maxY,
                                 content: geometry.contentSize.height)
            } action: { old, new in
                if follow.update(from: old, to: new) { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
        }
    }

    private static var end: String { "end" }
}
