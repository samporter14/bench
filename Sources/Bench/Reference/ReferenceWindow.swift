// ReferenceWindow.swift — the reference reader (DESIGN.md, Reference): a
// small read-only window with one of Claude's answers from a session, to keep
// beside the work. The session's title over "<project> · read only"; Earlier
// and Later in the toolbar (⌥⌘← and ⌥⌘→ while the window is key); the answer
// as selectable text, its figures as thumbnails; Copy with Source and Open in
// Claude Science at the foot. Window → Keep on Top floats the key one. Nothing
// here is in the clay: the window reads, it never asks.
import AppKit
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
    static let size = NSSize(width: 440, height: 560)
    private static let frameName = "CapsidReference"
    /// The figures' thumbnail reads, one at a time, apart from the Results shelf's queue.
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
        // states are smaller than an answer, and must not shrink it.
        hosting.sizingOptions = []
        let window = ReferenceWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                     styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                     backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = session.displayTitle
        window.subtitle = "\(session.projectName) · read only"
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

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 360, minHeight: 320)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button { model.earlier() } label: { Label("Earlier", systemImage: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                        .disabled(!model.canGoEarlier)
                        .help("The answer before this one. Option-Command-Left Arrow.")
                    Button { model.later() } label: { Label("Later", systemImage: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                        .disabled(!model.canGoLater)
                        .help("The answer after this one. Option-Command-Right Arrow.")
                }
            }
        }
        .sheet(item: $keeping) { keep in
            KeepSheet(model: keep, dismiss: { keeping = nil })
        }
    }

    @ViewBuilder
    private var content: some View {
        if let answer = model.current {
            VStack(alignment: .leading, spacing: 0) {
                positionLine
                // One page: the text at its own height, then its figures.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ReferenceTextView(text: model.rendered(answer), selection: selection)
                        if model.readingRest || model.restFailed.contains(answer.i) {
                            Text(model.readingRest ? "Reading the rest…" : "The rest of this answer couldn\u{2019}t be read.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        if !answer.figures.isEmpty { figures(answer) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(answer.i)
            }
        } else {
            empty
        }
    }

    /// "Claude's answer · 8:47 · 2 of 3", with a small spinner while a page is read.
    private var positionLine: some View {
        HStack(spacing: 8) {
            Text(model.positionLine ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.phase == .reading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
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

    /// The answer's figures, as the Results window draws them.
    private func figures(_ answer: ReferenceAnswer) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(answer.figures, id: \.v) { file in
                    ShelfThumbnailView(store: model.thumbnails, version: file.v, kind: file.kind)
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .onAppear { model.wantThumbnail(file) }
                        .help(file.name)
                        .accessibilityLabel("Figure, \(file.name)")
                        .contextMenu {
                            Button("Keep…") { keep(file) }
                            Button("Open in Claude Science") { model.openInScience() }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            Button(model.copied ? "Copied" : "Copy with Source") { copy() }
                .disabled(model.current == nil)
                .help("Copies the selection, or the whole answer, with where it came from")
            Spacer()
            Button("Open in Claude Science") { model.openInScience() }
                .help("Shows this session in the main window")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

/// The answer's text: a read-only, selectable text view as tall as its text
/// at the width it is given, so the page around it scrolls, with the figures
/// after the text rather than pinned under it.
struct ReferenceTextView: NSViewRepresentable {
    let text: NSAttributedString
    let selection: ReferenceSelection

    private static let inset = NSSize(width: 11, height: 8)

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
        textView.textContainerInset = Self.inset
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.setAccessibilityLabel("Claude\u{2019}s answer")
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
        container.containerSize = NSSize(width: width - 2 * Self.inset.width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        container.containerSize = placed
        return CGSize(width: width, height: ceil(used.height) + 2 * Self.inset.height)
    }
}
