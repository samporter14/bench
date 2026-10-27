// WorkspaceView.swift — the Project Workspace panel, drawn on the 1.0 windows'
// Solanum surface (DESIGN.md, Project Workspaces → The panel; Look → The 1.0
// windows): the project's name centred in the title bar over "Project
// workspace", a quiet ⋯ at its trailing edge (Clear Workspace…); on the ivory
// page, what couldn't come back from the last Return, the Working Note on a
// white card (plain text, written as you type, with its size shown near the
// 64 KB limit), and the pinned references, each a row that opens its reply
// with a quiet Unpin. At the foot, a quiet line naming the conversation Return
// to Project opens, and Return to Project, the one clay action. A project with
// nothing yet says what the workspace is for in two sentences.
import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: WorkspacePanelModel
    @ObservedObject private var store: WorkspaceStore
    @ObservedObject private var returner: WorkspaceReturner
    @State private var confirmingClear = false
    /// The page's visible height, and the height of everything on it but the note: the note takes what is left,
    /// never less than `leastNote`, and only then does the page scroll.
    @State private var viewport: CGFloat = 0
    @State private var rest: CGFloat = 0
    /// The window's width, for the title's: it stays clear of the window's buttons and the ⋯.
    @State private var width: CGFloat = WorkspacePanelController.size.width

    private static let side: CGFloat = 20
    private static let leastNote: CGFloat = 96

    private var noteHeight: CGFloat { max(Self.leastNote, viewport - rest) }

    init(model: WorkspacePanelModel) {
        self.model = model
        _store = ObservedObject(wrappedValue: model.store)
        _returner = ObservedObject(wrappedValue: model.returner)
    }

    var body: some View {
        VStack(spacing: 0) {
            page
            footer
        }
        .frame(minWidth: WorkspacePanelController.minimum.width, minHeight: 300)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background { Solanum.page.ignoresSafeArea() }
        .overlay {
            // The title bar's band and its hairline, as the reference window draws them.
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
                WorkspaceTitle(name: model.displayName, windowWidth: width)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                WorkspaceMoreMenu(canClear: model.canClear) { confirmingClear = true }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .alert("Clear the workspace for \u{201C}\(model.displayName)\u{201D}?", isPresented: $confirmingClear) {
            Button("Clear Workspace", role: .destructive) { model.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its note and pinned references go to the Trash, where Put Back brings them back. Kept files and conversations stay as they are.")
        }
    }

    // MARK: The page

    private var page: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    rest = height - (model.standing == .ready ? noteHeight : 0)
                }
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = model.summary, let headline = summary.headline {
                WorkspaceSummaryView(headline: headline, problems: summary.problems)
            }
            if let problem = model.clearProblem {
                Text(problem)
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Theme.clayText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch model.standing {
            case .ready:
                if model.isFresh {
                    Text(WorkspaceWords.intro)
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                note
                // A project with nothing yet: the sentences above say what pins are for.
                if !(model.isFresh && (model.record?.pins.isEmpty ?? true)) { pins }
            case .damaged, .newer, .unreadable:
                VStack(alignment: .leading, spacing: 6) {
                    Text("This workspace can\u{2019}t be read")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Solanum.ink)
                    Text((model.standing?.sentence ?? "") + " " + WorkspaceWords.unreadableTail)
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .loading, nil:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: max(0, viewport - 40))
                    .accessibilityLabel("Reading")
            }
        }
        .padding(.horizontal, Self.side)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The Working Note: a caption, the text on a white card, and under it what is worth saying about it.
    private var note: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Working note")
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
            WorkspaceNoteEditor(text: model.record?.note ?? "", isEditable: model.standing == .ready,
                                change: { model.edit($0) }, refuse: { model.refuseEdit() })
                .overlay(alignment: .topLeading) {
                    if (model.record?.note ?? "").isEmpty {
                        Text("Notes for this project\u{2026}")
                            .font(.system(size: Solanum.bodySize))
                            .foregroundStyle(Solanum.muted.opacity(0.8))
                            .padding(.horizontal, WorkspaceNoteEditor.inset.width + 5)
                            .padding(.vertical, WorkspaceNoteEditor.inset.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Solanum.raised, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
                .frame(height: noteHeight)
            noteStatus
        }
    }

    /// Under the note: why a save or a change didn't happen (with Retry), else its size near the limit.
    @ViewBuilder
    private var noteStatus: some View {
        let save = model.save
        if let failure = save.failure {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(WorkspaceWords.unsaved(failure))
                    .font(.system(size: Solanum.captionSize))
                    .foregroundStyle(Theme.clayText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Retry") { model.retry() }
                    .buttonStyle(SolanumPillStyle(.small))
                    .fixedSize()
                    .disabled(save.writing)
            }
        } else if let projectID = model.projectID, store.refused.contains(projectID) {
            Text(WorkspaceRules.fullSentence)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Theme.clayText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let size = WorkspaceRules.sizeLine(for: model.record?.note ?? "") {
            Text(size)
                .font(.system(size: Solanum.captionSize).monospacedDigit())
                .foregroundStyle(Solanum.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("The note uses \(size)")
        }
    }

    /// The pinned references: each opens its reply when clicked, and has a quiet Unpin.
    @ViewBuilder
    private var pins: some View {
        let pins = model.record?.pins ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text(pins.isEmpty ? "Pinned references" : "Pinned references \u{00B7} \(pins.count) of \(WorkspaceRules.pinLimit)")
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
            if pins.isEmpty {
                if !model.isFresh {
                    Text(WorkspaceWords.noPins)
                        .font(.system(size: 13))
                        .foregroundStyle(Solanum.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                        if index > 0 { Solanum.hairline.frame(height: 1).padding(.leading, 12) }
                        WorkspacePinRow(pin: pin, gone: model.gonePins.contains(pin.sessionID),
                                        open: { model.open(pin) }, unpin: { model.unpin(pin) })
                    }
                }
                .background(Solanum.raised, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Solanum.hairline, lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The foot

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.returnLine)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Solanum.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.returnLineHelp)
            Spacer(minLength: 8)
            if model.isReturning {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Returning")
            }
            Button("Return to Project") { model.returnToProject() }
                .buttonStyle(SolanumPillStyle(.regular, prominent: true))
                .disabled(model.projectID == nil || model.isReturning || Demo.mode != nil)
                .help("Your last conversation here in the main window, the pinned references, and the Shelf showing this project")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Solanum.hairline.frame(height: 1) }
    }
}

/// The title bar's centre: the project's name over "Project workspace". A long name loses its middle; the whole
/// of it is the tooltip.
struct WorkspaceTitle: View {
    let name: String
    /// The window's width: the title keeps clear of the window's three buttons on one side and the ⋯ on the other.
    var windowWidth: CGFloat = WorkspacePanelController.size.width

    var body: some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Solanum.ink)
                .help(name)
            Text("Project workspace")
                .font(.system(size: 11))
                .foregroundStyle(Solanum.muted)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: max(120, windowWidth - 2 * 86))
        .accessibilityElement(children: .combine)
    }
}

/// The quiet ⋯ in the title bar: Clear Workspace….
struct WorkspaceMoreMenu: View {
    let canClear: Bool
    let clear: () -> Void

    var body: some View {
        Menu {
            Button("Clear Workspace\u{2026}", action: clear)
                .disabled(!canClear)
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumMoreStyle(diameter: 28))
        .fixedSize()
        .help("Clear Workspace\u{2026}")
        .accessibilityLabel("More for this workspace")
    }
}

/// A round ⋯ button, white with a strong hairline, as the Shelf's detail draws its own.
struct SolanumMoreStyle: ButtonStyle {
    var diameter: CGFloat = 30
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Solanum.ink : Solanum.muted)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Solanum.raised))
            .overlay(Circle().fill(Solanum.hairline).opacity(configuration.isPressed ? 1 : 0))
            .overlay(Circle().strokeBorder(Solanum.strong, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// A pinned reference: its title (muted, with "gone", when the database no longer has it), which opens it, and Unpin.
struct WorkspacePinRow: View {
    let pin: WorkspacePin
    let gone: Bool
    let open: () -> Void
    let unpin: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Text(pin.title.isEmpty ? "Untitled" : pin.title)
                        .font(.system(size: 13))
                        .foregroundStyle(gone ? Solanum.muted : Solanum.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if gone {
                        Text("gone")
                            .font(.system(size: Solanum.captionSize))
                            .foregroundStyle(Solanum.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(gone ? "\(pin.title) isn\u{2019}t in Claude Science any more" : "Open \(pin.title) at its pinned reply")
            .accessibilityLabel(gone ? "\(pin.title), gone" : "Open \(pin.title)")
            Button("Unpin", action: unpin)
                .buttonStyle(.plain)
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(hovering ? Solanum.ink : Solanum.muted)
                .help("Unpin \(pin.title) from this project")
                .accessibilityLabel("Unpin \(pin.title)")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .onHover { hovering = $0 }
    }
}

/// What the last Return couldn't bring back.
struct WorkspaceSummaryView: View {
    let headline: String
    let problems: [WorkspaceReturnProblem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.system(size: Solanum.captionSize, weight: .semibold))
                .foregroundStyle(Solanum.ink)
            ForEach(problems) { problem in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\u{2022}")
                    Text(problem.sentence)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: Solanum.captionSize))
                .foregroundStyle(Theme.clayText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The panel's sentences.
enum WorkspaceWords {
    static let intro = "Keep a note for this project here, and pin up to four replies from reference windows (\u{22EF} \u{203A} Pin to Project). Return to Project brings back your last conversation here, the pinned replies and the Shelf showing this project."
    static let noPins = "None yet. Pin a reply from a reference window\u{2019}s \u{22EF} menu."
    static let unreadableTail = "Return to Project still brings back your last conversation here and the Shelf. Clear Workspace\u{2026} moves the file to the Trash."

    static func unsaved(_ failure: String) -> String {
        "Couldn\u{2019}t save: \(failure) Your note is kept here."
    }
}

/// The note's field: plain text in an AppKit text view, so a change past the 64 KB limit is refused before it is
/// made (a typed character, a paste, a drop), and said, never cut. Text set from the store (another project, a
/// read) replaces the field's only when it differs, and never while something is being composed.
struct WorkspaceNoteEditor: NSViewRepresentable {
    let text: String
    let isEditable: Bool
    let change: (String) -> Void
    let refuse: () -> Void

    static let inset = NSSize(width: 10, height: 10)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var change: (String) -> Void = { _ in }
        var refuse: () -> Void = {}

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }
            let next = (textView.string as NSString).replacingCharacters(in: range, with: replacement)
            guard WorkspaceRules.fits(note: next) else {
                refuse()
                return false
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            change(textView.string)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: Solanum.bodySize)
        textView.textColor = Solanum.inkColor
        textView.insertionPointColor = Solanum.inkColor
        textView.textContainerInset = Self.inset
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Solanum.bodyLeading - 17
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: Solanum.bodySize), .foregroundColor: Solanum.inkColor,
                                     .paragraphStyle: paragraph]
        textView.setAccessibilityLabel("Working note")
        textView.delegate = context.coordinator
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.change = change
        context.coordinator.refuse = refuse
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        guard textView.string != text, !textView.hasMarkedText() else { return }
        let selection = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }
}
