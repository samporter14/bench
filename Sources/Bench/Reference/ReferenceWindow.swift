// ReferenceWindow.swift — the reference reader (DESIGN.md, Reference): a
// small read-only window with one of Claude's answers from a session, to keep
// beside the work, drawn as the Capsid 1.0 mock-up has it (Solanum's ivory
// page, SolanumSurface.swift). The title bar shows the session's title over
// "<project> · read only", centred, and two round chevrons, Earlier and Later
// (⌥⌘← and ⌥⌘→ while the window is key). The page: "Claude's answer · 8:47",
// what the user asked, the figures on white cards with Add to Shelf under
// each, then what Claude said, then its other files. At the foot, two pills:
// Copy with Source (⇧⌘C) and Open Conversation. Window → Keep on Top floats the
// key one. Nothing here is in the clay: the window reads, it never asks. (What
// it does besides is the Shelf's: Add to Shelf, "On Shelf ✓" once it is, and
// a shelved figure wears board 11's mark, a slate chip and an ink ring. Show
// Where It Came From opens the window on the reply a shelved item came from,
// scrolled to it.)
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
    /// Each window's watch on its session's state (the panel's reads), so a session that finishes is read again.
    private var watches: [String: AnyCancellable] = [:]

    /// Opens a session's window, or brings it forward. With `row` or `mark`
    /// (Show Where It Came From, Open as Reference on a figure) it goes to
    /// the reply that holds that history row, or shows that version, and
    /// scrolls to the file: a window already open moves there too.
    func show(_ session: SessionStatus, dependencies: ReferenceDependencies? = nil, at row: Int? = nil, mark: String? = nil) {
        if let window = windows[session.id] {
            Demo.activateUnlessQuiet()
            window.makeKeyAndOrderFront(nil)
            if row != nil || mark != nil {
                models[session.id]?.land(at: row, mark: mark)
            } else {
                // Shown again from any way in: a reply may have landed since.
                models[session.id]?.refresh()
            }
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
        // The title stays the window's (the Window menu, Mission Control) but
        // is drawn by the toolbar's centre, with its subtitle, as the
        // mock-ups have it; the bar is the page's own band.
        window.title = session.displayTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = Solanum.pageColor
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
        // A session that stops running has finished the reply it was writing.
        watches[session.id] = LabModel.shared.reads.$sessions.sink { [weak model] sessions in
            MainActor.assumeIsolated { model?.sessionChanged(to: sessions.first { $0.id == session.id }?.state) }
        }
        model.open(at: row, mark: mark)
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
    }

    /// The window a session shows in, for tests and the demo.
    func window(for sessionID: String) -> NSWindow? { windows[sessionID] }

    /// The model a session's window shows, for the demo.
    func model(for sessionID: String) -> ReferenceModel? { models[sessionID] }

    /// THE SHELF'S CONTRACT (Kept/Shelf.swift): "Show Where It Came From".
    /// Opens a session's reference window at the reply that holds history row
    /// `row`, scrolled to the file `version` and marked "On your shelf" (the
    /// mark follows the shelf); with no row, at the newest reply that shows the
    /// version. The window's own title and project are the ones given; its
    /// Open Conversation goes to the session's address on the daemon's port.
    func show(sessionID: String, projectID: String, title: String, projectName: String,
              at row: Int?, mark version: String?) {
        show(Self.session(id: sessionID, projectID: projectID, title: title, projectName: projectName,
                          port: WebContainer.shared.port),
             at: row, mark: version)
    }

    /// The session a shelved item names, built from the ids and words its
    /// README kept: Open Conversation needs the address, which is made only
    /// from ids as the database has them (a README can be written by hand).
    static func session(id: String, projectID: String, title: String, projectName: String, port: Int?) -> SessionStatus {
        let link = BrowseSQL.isProjectID(projectID) && PlanCheck.isFrameID(id)
            ? URL(string: "http://localhost:\(port ?? 8765)/projects/\(projectID)/frames/\(id)") : nil
        return SessionStatus(id: id, projectID: projectID, projectName: projectName, title: title,
                             state: .finished, updatedAt: Date(), startedAt: nil, deepLink: link)
    }

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
        // Coming back to the window: the newest rows are read again (at most every few seconds).
        if let id = windows.first(where: { $0.value === window })?.key { models[id]?.refresh() }
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
    /// The shelf, watched so "On Shelf ✓" and the mark follow it.
    @ObservedObject private var shelf: ShelfAccess
    let selection: ReferenceSelection
    @State private var keeping: KeepModel?
    /// The window's width, for the Keep sheet: one wider than the window
    /// would hang off both sides.
    @State private var pageWidth: CGFloat = ReferenceWindowController.size.width

    /// The page's margins and the space between its parts, after the mock-up.
    private static let side: CGFloat = 24
    private static let top: CGFloat = 20
    private static let gap: CGFloat = 14

    init(model: ReferenceModel, selection: ReferenceSelection) {
        self.model = model
        self.selection = selection
        _shelf = ObservedObject(wrappedValue: model.shelf)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .frame(minWidth: 360, minHeight: 320)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .background {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // The title bar's band and its hairline, under the toolbar.
                    Solanum.bar
                        .frame(height: proxy.safeAreaInsets.top)
                        .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                    Solanum.page
                }
                .ignoresSafeArea()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(model.session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    Text("\(model.session.projectName) · read only")
                        .font(.system(size: 11))
                        .foregroundStyle(Solanum.muted)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Button { model.earlier() } label: { Label("Earlier", systemImage: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                        .disabled(!model.canGoEarlier)
                        .help("The answer before this one (Option-Command-Left Arrow)")
                    Button { model.later() } label: { Label("Later", systemImage: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                        .disabled(!model.canGoLater)
                        .help("The answer after this one (Option-Command-Right Arrow)")
                }
                .buttonStyle(SolanumRoundStyle())
                .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // The system's own title would sit beside the centred one and push
        // the chevrons into the overflow menu.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .sheet(item: $keeping) { keep in
            KeepSheet(model: keep, dismiss: { keeping = nil }, width: max(360, pageWidth))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let answer = model.current {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        caption(answer)
                        if let note = model.landingNote {
                            Text(note)
                                .font(.system(size: Solanum.captionSize))
                                .foregroundStyle(Solanum.muted)
                        }
                        if let question = answer.question { asked(question) }
                        ForEach(model.figures(of: answer), id: \.v) { file in figure(file).id(file.v) }
                        if !answer.parts.isEmpty {
                            ReferenceTextView(text: model.rendered(answer), selection: selection)
                        }
                        if model.readingRest || model.restMissing {
                            Text(model.readingRest ? "Reading the rest\u{2026}" : "Part of this answer couldn\u{2019}t be read.")
                                .font(.system(size: Solanum.captionSize))
                                .foregroundStyle(Solanum.muted)
                        }
                        if !answer.files.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(answer.files, id: \.v) { file in fileRow(file).id(file.v) }
                            }
                        }
                    }
                    .padding(.horizontal, Self.side)
                    .padding(.top, Self.top)
                    .padding(.bottom, Self.side)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                // Show Where It Came From: once the reply is up, the file it came for.
                .onChange(of: model.scrollRequest, initial: true) { _, request in
                    guard let request else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(request.id, anchor: .center) }
                    }
                }
            }
            // Another reply starts at the top; the same one, grown by a read, stays where it is.
            .id(model.shownKey)
        } else {
            empty
        }
    }

    /// "Claude's answer · 8:47 · 2 of 3", the count once the start is read,
    /// and a small spinner while a page is.
    private func caption(_ answer: ReferenceAnswer) -> some View {
        HStack(spacing: 8) {
            Text(model.caption)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.phase == .reading {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Reading")
            }
        }
    }

    /// What the user asked: muted, three lines at most.
    private func asked(_ question: String) -> some View {
        Text(question)
            .font(.system(size: 13))
            .foregroundStyle(Solanum.muted)
            .lineSpacing(3)
            .lineLimit(3)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .accessibilityLabel("You asked: \(question)")
    }

    /// A figure on a white card, the page's width, its name and the shelf's
    /// pill under it; shelved, it wears the chip and the ring.
    private func figure(_ file: HistoryFile) -> some View {
        let mark = model.shelfMark(file)
        return VStack(alignment: .leading, spacing: 8) {
            ReferenceFigureView(store: model.thumbnails, file: file, failed: model.thumbnailFailed(file),
                                shelved: mark == .on, wantsPicture: { model.wantThumbnail(file) })
                .contextMenu { shelfItems(file, mark: mark) }
            HStack(spacing: 8) {
                Text(file.name)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Solanum.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                ShelfPill(mark: mark, add: { shelve(file) }, show: { model.showOnShelf(file) })
            }
            problem(file)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mark == .on ? "Figure, \(file.name), on your shelf" : "Figure, \(file.name)")
    }

    /// A file that isn't a picture, in a quiet row under the words.
    private func fileRow(_ file: HistoryFile) -> some View {
        let mark = model.shelfMark(file)
        return VStack(alignment: .leading, spacing: 6) {
            ReferenceFileRow(file: file, mark: mark, add: { shelve(file) }, show: { model.showOnShelf(file) })
                .contextMenu { shelfItems(file, mark: mark) }
            problem(file)
        }
    }

    /// Why an add failed, under the file, until the next try.
    @ViewBuilder
    private func problem(_ file: HistoryFile) -> some View {
        if let sentence = model.shelfProblems[file.v] {
            Text(sentence)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Theme.clayText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The context menu of a figure or a file.
    @ViewBuilder
    private func shelfItems(_ file: HistoryFile, mark: ShelfMark) -> some View {
        if mark == .on {
            Button("Show on Shelf") { model.showOnShelf(file) }
        } else {
            Button(ShelfWords.add) { shelve(file) }
                .disabled(mark == .adding)
        }
        Button(ShelfWords.keep) { keep(file) }
        Divider()
        Button("Open Conversation") { model.openConversation() }
    }

    private func shelve(_ file: HistoryFile) {
        Task { await model.addToShelf(file) }
    }

    /// Copy with Source and Open Conversation, as the mock-up's foot has them.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(model.copied ? "Copied" : "Copy with Source") { copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.current == nil)
                .help("The selection, or the whole answer, with where it came from (Shift-Command-C)")
            Spacer(minLength: 8)
            Button("Open Conversation") { model.openConversation() }
                .help("This session in the main window")
        }
        .buttonStyle(SolanumPillStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Solanum.hairline.frame(height: 1) }
    }

    /// Reading, failed or nothing to show. As tall as the window lets it: a
    /// state with a fixed height of its own would shrink the window to it.
    private var empty: some View {
        Group {
            switch model.phase {
            case .reading:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading")
            case .failed(let sentence):
                VStack(spacing: 12) {
                    Text("Couldn\u{2019}t read this conversation")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    Text(sentence)
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { model.retry() }
                        .buttonStyle(SolanumPillStyle())
                        .padding(.top, 4)
                }
                .padding(.horizontal, 40)
            case .idle:
                VStack(spacing: 8) {
                    Text(model.reachedStart ? ReferenceRules.noAnswersYet : ReferenceRules.noAnswerNear)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    Text(model.reachedStart ? "Claude hasn\u{2019}t answered in this session."
                                            : "Earlier keeps looking back through the conversation.")
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
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
        Task { @MainActor in
            // The words go with it whole, when the reads under way bring the rest in time.
            await model.restRead(for: file)
            guard keeping == nil else { return }
            keeping = KeepModel(subject: model.keepSubject(file), dependencies: .live(shelf: .shared))
        }
    }
}

/// A figure on a white card at the page's width: the picture when it has
/// come, else a quiet card of the shape most charts are.
struct ReferenceFigureView: View {
    @ObservedObject var store: ShelfThumbnails
    let file: HistoryFile
    let failed: Bool
    /// On the shelf: board 11's slate chip and a 2-point ink ring.
    var shelved = false
    /// Called each time the card is drawn with no picture (first drawn, or the
    /// store let the picture go): the reader asks for it, if it isn't coming.
    var wantsPicture: () -> Void = {}

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
                Color.clear
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(Solanum.muted)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .onAppear(perform: wantsPicture)
            }
        }
        .background(Solanum.raised)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .topLeading) {
            if shelved { OnShelfChip().padding(10) }
        }
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(shelved ? Solanum.ink : Solanum.hairline, lineWidth: shelved ? 2 : 1))
    }
}

/// The reader's type: the system font at the mock-up's 14 on 21, in
/// Solanum's ink, links in ink (underlined in clay by the text view).
extension AnswerStyle {
    static let reference = AnswerStyle(
        body: .systemFont(ofSize: Solanum.bodySize),
        lineSpacing: Solanum.bodyLeading - 17,
        headings: [.systemFont(ofSize: 18, weight: .semibold),
                   .systemFont(ofSize: 16, weight: .semibold),
                   .systemFont(ofSize: 14, weight: .semibold)],
        code: .monospacedSystemFont(ofSize: 12.5, weight: .regular),
        secondary: Solanum.mutedColor,
        link: Solanum.inkColor,
        ink: Solanum.inkColor)
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
        textView.linkTextAttributes = [
            .foregroundColor: Solanum.inkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor(Theme.clay), .cursor: NSCursor.pointingHand,
        ]
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
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        container.containerSize = placed
        return CGSize(width: width, height: ceil(used.height))
    }
}
