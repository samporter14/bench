// ReferenceWindow.swift — the reference reader (DESIGN.md, Reference): a
// small read-only window with one of Claude's replies from a session, to keep
// beside the work. The figures come first, full width, each with Keep…; then
// what Claude said, as selectable text; above them, quietly, what the user
// asked. The session's title is the window's, and its subtitle says the
// project, when and which reply ("2 of 3"). The toolbar holds the rest: Earlier
// and Later (⌥⌘← and ⌥⌘→ while the window is key), Copy with Source (⇧⌘C) and
// Open Conversation. Window → Keep on Top floats the key one. Nothing here is
// in the clay: the window reads, it never asks.
import AppKit
import Combine
import SwiftUI

/// The Window menu's Keep on Top: the key reference window, if any.
@MainActor
final class ReferenceCommands: ObservableObject {
    static let shared = ReferenceCommands()
    @Published fileprivate(set) var keyWindow: ReferenceWindow?

    var isOnTop: Bool { keyWindow?.level == .floating }

    func setOnTop(_ on: Bool) {
        keyWindow?.setOnTop(on)
        objectWillChange.send()
    }
}

final class ReferenceWindow: NSWindow {
    func setOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }
}

/// One window per session; opening a session again brings its window forward.
@MainActor
final class ReferenceWindowController: NSObject, NSWindowDelegate {
    static let shared = ReferenceWindowController()
    /// The window's width, and its height before the user resizes it.
    static let size = NSSize(width: 440, height: 620)
    private static let frameName = "CapsidReference"
    /// The figures' reads, one at a time, apart from the Results shelf's queue.
    static let transfers = makeTransfers()

    private static func makeTransfers() -> ShelfTransfers {
        ShelfTransfers(
            limit: 1,
            read: { read in
                guard Demo.mode == nil else { return .unreadable }
                return await ArtifactReadAbort.abortable(read, perform: { read, nonce in
                    (try? await WebContainer.shared.readArtifact(read, nonce: nonce)) ?? .unreadable
                }, abort: { nonce in
                    await WebContainer.shared.abortArtifactRead(nonce)
                })
            },
            isReady: { Demo.mode == nil && WebContainer.shared.status == .ready },
            timeout: .seconds(30),
            wait: { try? await Task.sleep(for: $0) })
    }

    private var windows: [String: ReferenceWindow] = [:]
    private var models: [String: ReferenceModel] = [:]
    private var watches: [String: AnyCancellable] = [:]

    func show(_ session: SessionStatus, dependencies: ReferenceDependencies? = nil) {
        if let window = windows[session.id] {
            Demo.activateUnlessQuiet()
            window.makeKeyAndOrderFront(nil)
            return
        }
        ReadingGate.shared.start()
        let model = ReferenceModel(session: session, dependencies: dependencies ?? .live())
        let selection = ReferenceSelection()
        let hosting = NSHostingController(rootView: ReferenceView(model: model, selection: selection))
        // The window keeps its size whatever it shows: the empty and failed
        // states are smaller than a reply, and must not shrink it.
        hosting.sizingOptions = []
        let window = ReferenceWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                     styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                     backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = session.displayTitle
        window.subtitle = model.subtitle
        window.setContentSize(Self.size)
        window.contentMinSize = NSSize(width: 360, height: 320)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.toolbarStyle = .unified
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        // A second window at the remembered place steps down from the first.
        if windows.values.contains(where: { $0.frame.origin == window.frame.origin }) {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: window.frame.minX, y: window.frame.maxY)))
        }
        // The subtitle follows the reply shown.
        watches[session.id] = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak window, weak model] _ in
                guard let window, let model else { return }
                if window.subtitle != model.subtitle { window.subtitle = model.subtitle }
            }
        windows[session.id] = window
        models[session.id] = model
        model.open()
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
    }

    /// The window a session shows in, for tests and the demo.
    func window(for sessionID: String) -> NSWindow? { windows[sessionID] }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? ReferenceWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        // A demo's window remembers nothing.
        if Demo.mode == nil { window.saveFrame(usingName: Self.frameName) }
        models[id]?.close()
        models[id] = nil
        windows[id] = nil
        watches[id] = nil
        if ReferenceCommands.shared.keyWindow === window { ReferenceCommands.shared.keyWindow = nil }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? ReferenceWindow else { return }
        ReferenceCommands.shared.keyWindow = window
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? ReferenceWindow,
              ReferenceCommands.shared.keyWindow === window else { return }
        ReferenceCommands.shared.keyWindow = nil
    }
}

// MARK: The content

/// The text view's selection, for Copy with Source.
@MainActor
final class ReferenceSelection {
    weak var textView: NSTextView?

    /// The selected text, or nil when nothing is selected.
    var selectedText: String? {
        guard let textView else { return nil }
        let range = textView.selectedRange()
        guard range.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: range)
    }
}

struct ReferenceView: View {
    @ObservedObject var model: ReferenceModel
    let selection: ReferenceSelection
    @State private var keeping: KeepModel?

    /// The page's margin, and the space between its parts.
    private static let margin: CGFloat = 20
    private static let gap: CGFloat = 18

    var body: some View {
        content
            .frame(minWidth: 360, minHeight: 320)
            .background(Color(nsColor: .textBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button { model.earlier() } label: { Label("Earlier", systemImage: "chevron.left") }
                            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                            .disabled(!model.canGoEarlier)
                            .help("The reply before this one (Option-Command-Left Arrow)")
                        Button { model.later() } label: { Label("Later", systemImage: "chevron.right") }
                            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                            .disabled(!model.canGoLater)
                            .help("The reply after this one (Option-Command-Right Arrow)")
                    }
                    .controlGroupStyle(.navigation)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.phase == .reading, model.current != nil {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Reading")
                    }
                    Button { copy() } label: {
                        Label(model.copied ? "Copied" : "Copy with Source",
                              systemImage: model.copied ? "checkmark" : "doc.on.doc")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.current == nil)
                    .help("Copy with Source: the selection, or the whole reply, with where it came from (Shift-Command-C)")
                    Button { model.openConversation() } label: {
                        Label("Open Conversation", systemImage: "arrow.up.forward.square")
                    }
                    .help("Open Conversation: this session in the main window")
                }
            }
            .sheet(item: $keeping) { keep in
                KeepSheet(model: keep, dismiss: { keeping = nil })
            }
    }

    @ViewBuilder
    private var content: some View {
        if let answer = model.current {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.gap) {
                    if let question = answer.question { asked(question) }
                    ForEach(answer.figures, id: \.v) { file in figure(file) }
                    if !answer.parts.isEmpty {
                        ReferenceTextView(text: model.rendered(answer), selection: selection)
                    }
                    if model.readingRest || model.restMissing {
                        Text(model.readingRest ? "Reading the rest\u{2026}" : "Part of this reply couldn\u{2019}t be read.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Self.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(answer.id)
        } else {
            empty
        }
    }

    /// What the user asked: quiet, a hairline at its side, three lines at most.
    private func asked(_ question: String) -> some View {
        Text(question)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
            }
            .accessibilityLabel("You asked: \(question)")
    }

    /// A figure, the page's width, with its name and Keep… under it.
    private func figure(_ file: HistoryFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ReferenceFigureView(store: model.thumbnails, file: file, failed: model.thumbnailFailed(file))
                .onAppear { model.wantThumbnail(file) }
                .contextMenu {
                    Button("Keep\u{2026}") { keep(file) }
                    Button("Open Conversation") { model.openConversation() }
                }
            HStack(spacing: 8) {
                Text(file.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button { keep(file) } label: { Label("Keep\u{2026}", systemImage: "checkmark.seal") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Keep this figure, with what Claude said about it, in your Kept folder")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Figure, \(file.name)")
    }

    /// Reading, failed or nothing to show. As tall as the window lets it: a
    /// state with a fixed height of its own would shrink the window to it.
    private var empty: some View {
        Group {
            switch model.phase {
            case .reading:
                ProgressView()
                    .accessibilityLabel("Reading")
            case .failed(let sentence):
                ContentUnavailableView {
                    Label("Couldn\u{2019}t read this conversation", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(sentence)
                } actions: {
                    Button("Try Again") { model.retry() }
                }
            case .idle:
                ContentUnavailableView {
                    Label(model.reachedStart ? ReferenceRules.noAnswersYet : ReferenceRules.noAnswerNear,
                          systemImage: "text.bubble")
                } description: {
                    Text(model.reachedStart ? "Claude hasn\u{2019}t answered in this session."
                                            : "Earlier keeps looking back through the conversation.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy() {
        guard let answer = model.current else { return }
        model.copy(selection.selectedText ?? model.rendered(answer).string)
    }

    private func keep(_ file: HistoryFile) {
        guard keeping == nil else { return }
        keeping = KeepModel(subject: model.keepSubject(file), dependencies: .live(shelf: .shared))
    }
}

/// A figure at the page's width: the picture when it has come, else a quiet
/// frame of the same shape as most charts.
struct ReferenceFigureView: View {
    @ObservedObject var store: ShelfThumbnails
    let file: HistoryFile
    let failed: Bool

    /// Taller than this, a picture is shown smaller rather than filling the window.
    private static let maxHeight: CGFloat = 520

    var body: some View {
        Group {
            if let image = store.image(for: file.v) {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.4))
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// The reply's text: a read-only, selectable text view as tall as its text
/// at the width it is given, so the page around it scrolls.
struct ReferenceTextView: NSViewRepresentable {
    let text: NSAttributedString
    let selection: ReferenceSelection

    final class Coordinator {
        /// The text last put in, by identity: the model renders once per text.
        var shown: NSAttributedString?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        // The text lines up with the figures and the question: no inset.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.setAccessibilityLabel("Claude\u{2019}s reply")
        selection.textView = textView
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        guard context.coordinator.shown !== text else { return }
        context.coordinator.shown = text
        textView.textStorage?.setAttributedString(text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// The text's height at the proposed width. SwiftUI measures at several
    /// widths before it places the view, so the container is put back as it
    /// was: the text is laid out at the frame's width (the container tracks
    /// it), never at a probe's.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let container = textView.textContainer,
              let layout = textView.layoutManager else { return nil }
        let placed = container.containerSize
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        container.containerSize = placed
        return CGSize(width: width, height: ceil(used.height))
    }
}
